// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Corn.sol";
import "./CornDEX.sol";

/// @title Lending Protocol for Corn Token
/// @author [Your Name]
/// @notice A decentralized lending protocol that allows users to deposit ETH as collateral and borrow CORN tokens
/// @dev This contract implements a over-collateralized lending system with liquidation mechanism
/// @custom:security-contact [security@yourprotocol.com]

/// @notice Thrown when an invalid amount (0 or insufficient) is provided
error Lending__InvalidAmount();

/// @notice Thrown when a transfer operation fails
error Lending__TransferFailed();

/// @notice Thrown when a user's position ratio becomes unsafe (below collateral requirement)
error Lending__UnsafePositionRatio();

/// @notice Thrown when a borrow operation fails
error Lending__BorrowingFailed();

/// @notice Thrown when a repay operation fails
error Lending__RepayingFailed();

/// @notice Thrown when trying to liquidate a safe position
error Lending__PositionSafe();

/// @notice Thrown when a position is not eligible for liquidation
error Lending__NotLiquidatable();

/// @notice Thrown when liquidator doesn't have sufficient CORN tokens
error Lending__InsufficientLiquidatorCorn();

contract Lending is Ownable {
    /// @notice Minimum collateralization ratio required (120%)
    /// @dev Positions below this ratio can be liquidated
    uint256 private constant COLLATERAL_RATIO = 120;
    
    /// @notice Reward percentage for liquidators (10%)
    /// @dev Liquidators receive 10% of the liquidated collateral as reward
    uint256 private constant LIQUIDATOR_REWARD = 10;

    /// @notice The CORN token contract instance
    /// @dev Used for borrowing and repaying CORN tokens
    Corn private i_corn;
    
    /// @notice The CornDEX contract instance for price feeds
    /// @dev Used to get current ETH/CORN price for collateral calculations
    CornDEX private i_cornDEX;

    /// @notice Mapping of user addresses to their collateral balance in ETH
    /// @dev Tracks how much ETH each user has deposited as collateral
    mapping(address => uint256) public s_userCollateral;
    
    /// @notice Mapping of user addresses to their borrowed CORN amount
    /// @dev Tracks how much CORN each user has borrowed
    mapping(address => uint256) public s_userBorrowed;

    /// @notice Emitted when a user adds collateral to their account
    /// @param user The address of the user adding collateral
    /// @param amount The amount of ETH added as collateral
    /// @param price The current ETH price at the time of adding collateral
    event CollateralAdded(address indexed user, uint256 indexed amount, uint256 price);
    
    /// @notice Emitted when a user withdraws collateral from their account
    /// @param user The address of the user withdrawing collateral
    /// @param amount The amount of ETH withdrawn
    /// @param price The current ETH price at the time of withdrawal
    event CollateralWithdrawn(address indexed user, uint256 indexed amount, uint256 price);
    
    /// @notice Emitted when a user borrows CORN tokens
    /// @param user The address of the user borrowing
    /// @param amount The amount of CORN tokens borrowed
    /// @param price The current ETH price at the time of borrowing
    event AssetBorrowed(address indexed user, uint256 indexed amount, uint256 price);
    
    /// @notice Emitted when a user repays CORN tokens
    /// @param user The address of the user repaying
    /// @param amount The amount of CORN tokens repaid
    /// @param price The current ETH price at the time of repayment
    event AssetRepaid(address indexed user, uint256 indexed amount, uint256 price);
    
    /// @notice Emitted when a liquidation occurs
    /// @param user The address of the user being liquidated
    /// @param liquidator The address of the liquidator
    /// @param amountForLiquidator The amount of collateral given to the liquidator as reward
    /// @param liquidatedUserDebt The amount of debt that was liquidated
    /// @param price The current ETH price at the time of liquidation
    event Liquidation(
        address indexed user,
        address indexed liquidator,
        uint256 amountForLiquidator,
        uint256 liquidatedUserDebt,
        uint256 price
    );

    /// @notice Constructor to initialize the Lending contract
    /// @dev Sets up the CornDEX and Corn contract references and approves maximum spending
    /// @param _cornDEX The address of the CornDEX contract for price feeds
    /// @param _corn The address of the CORN token contract
    constructor(address _cornDEX, address _corn) Ownable(msg.sender) {
        i_cornDEX = CornDEX(_cornDEX);
        i_corn = Corn(_corn);
        i_corn.approve(address(this), type(uint256).max);
    }

    /// @notice Allows users to add ETH collateral to their account
    /// @dev Users send ETH with this transaction which gets added to their collateral balance
    /// @custom:requirements msg.value must be greater than 0
    /// @custom:effects Increases user's collateral balance by msg.value
    /// @custom:interactions Emits CollateralAdded event
    function addCollateral() public payable {
        if (msg.value == 0) {revert Lending__InvalidAmount();}
        s_userCollateral[msg.sender] += msg.value;

        emit CollateralAdded(msg.sender, msg.value, i_cornDEX.currentPrice());
    }

    /// @notice Allows users to withdraw collateral as long as it doesn't make them liquidatable
    /// @dev Validates position safety before allowing withdrawal
    /// @param amount The amount of ETH collateral to withdraw
    /// @custom:requirements amount must be > 0 and <= user's collateral balance
    /// @custom:requirements resulting position must remain above collateral ratio
    /// @custom:effects Decreases user's collateral balance by amount
    /// @custom:interactions Transfers ETH to user, emits CollateralWithdrawn event
    function withdrawCollateral(uint256 amount) public {
        if (amount == 0 || s_userCollateral[msg.sender] < amount) {revert Lending__InvalidAmount();}
        s_userCollateral[msg.sender] -= amount;
        _validatePosition(msg.sender);

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            revert Lending__TransferFailed();
        }

        emit CollateralWithdrawn(msg.sender, amount, i_cornDEX.currentPrice()); 
    }

    /// @notice Calculates the total collateral value for a user in CORN tokens
    /// @dev Multiplies user's ETH collateral by current ETH price and adjusts for decimals
    /// @param user The address of the user to calculate the collateral value for
    /// @return The collateral value in CORN token units
    /// @custom:formula collateralValue = (userCollateral * currentPrice) / 1e18
    function calculateCollateralValue(address user) public view returns (uint256) {
        return s_userCollateral[user] * i_cornDEX.currentPrice() / 1e18;
    }

    /// @notice Calculates the position ratio for a user to ensure they are within safe limits
    /// @dev Returns the percentage ratio of collateral value to borrowed amount
    /// @param user The address of the user to calculate the position ratio for
    /// @return The position ratio as a percentage (e.g., 150 means 150%)
    /// @custom:formula ratio = (collateralValue * 100) / borrowedAmount
    /// @custom:note Returns type(uint256).max if user has no borrowed amount
    function _calculatePositionRatio(address user) public view returns (uint256) { 
       uint256 borrowedAmount = s_userBorrowed[user];
       if (borrowedAmount == 0) {return type(uint256).max;} 
       return (calculateCollateralValue(user) * 100) / borrowedAmount; 
    }

    /// @notice Checks if a user's position can be liquidated
    /// @dev A position is liquidatable if the collateral ratio falls below the minimum requirement
    /// @param user The address of the user to check
    /// @return True if the position is liquidatable (ratio < COLLATERAL_RATIO), false otherwise
    function isLiquidatable(address user) public view returns (bool) {
        return _calculatePositionRatio(user) < COLLATERAL_RATIO;
    }

    /// @notice Internal view method that reverts if a user's position is unsafe
    /// @dev Used to validate positions before allowing operations that could make them unsafe
    /// @param user The address of the user to validate
    /// @custom:reverts Lending__UnsafePositionRatio if position is liquidatable
    function _validatePosition(address user) internal view {
        if (isLiquidatable(user)) {revert Lending__UnsafePositionRatio();}
    }

    /// @notice Allows users to borrow CORN tokens based on their collateral
    /// @dev Validates that the resulting position remains safe after borrowing
    /// @param borrowAmount The amount of CORN tokens to borrow
    /// @custom:requirements borrowAmount must be > 0
    /// @custom:requirements resulting position must remain above collateral ratio
    /// @custom:effects Increases user's borrowed balance by borrowAmount
    /// @custom:interactions Transfers CORN tokens to user, emits AssetBorrowed event
    function borrowCorn(uint256 borrowAmount) public {
        if (borrowAmount == 0) {revert Lending__InvalidAmount();}

        s_userBorrowed[msg.sender] += borrowAmount;
        _validatePosition(msg.sender);
        bool success = i_corn.transfer(msg.sender, borrowAmount);
        if (!success) {
            revert Lending__BorrowingFailed(); 
        }

        emit AssetBorrowed(msg.sender, borrowAmount, i_cornDEX.currentPrice());
    }
    /**
    * @notice Allows users to repay corn and reduce their debt
    * @dev Validates the repay amount and updates user's debt balance
    * @dev Emits AssetRepaid event with current corn price
    * @param repayAmount The amount of corn to repay
    * @custom:requirements
    * - repayAmount must be greater than 0
    * - repayAmount must not exceed user's current debt
    * - User must have approved this contract to transfer repayAmount of CORN tokens
    * - User must have sufficient CORN balance
    */
    function repayCorn(uint256 repayAmount) public {
        if (repayAmount == 0 || repayAmount > s_userBorrowed[msg.sender]) {
            revert Lending__InvalidAmount();
        }
        s_userBorrowed[msg.sender] -= repayAmount;
        i_corn.transferFrom(msg.sender, address(this), repayAmount);
        emit AssetRepaid(msg.sender, repayAmount, i_cornDEX.currentPrice());
    }

    /**
    * @notice Allows liquidators to liquidate unsafe positions
    * @dev Liquidates a user's position by paying their debt and receiving collateral plus reward
    * @dev The liquidation reward is calculated as a percentage of the collateral being liquidated
    * @dev If calculated reward exceeds available collateral, the liquidator receives all remaining collateral
    * @param user The address of the user to liquidate
    * @custom:requirements
    * - The user's position must be liquidatable (checked via isLiquidatable function)
    * - Liquidator must have sufficient CORN balance to cover the user's debt
    * - Liquidator must have approved this contract to transfer the debt amount in CORN
    * @custom:effects
    * - User's debt is set to 0
    * - User's collateral is reduced by the amount transferred to liquidator
    * - Liquidator receives collateral proportional to debt plus liquidation reward
    * @custom:interactions
    * - Transfers CORN from liquidator to this contract
    * - Transfers ETH collateral to liquidator
    * @custom:events Emits Liquidation event with liquidation details and current corn price
    */
    function liquidate(address user) public {
        if (!isLiquidatable(user)) {
            revert Lending__NotLiquidatable();
        }
        
        uint256 userDebt = s_userBorrowed[user];
        if (i_corn.balanceOf(msg.sender) < userDebt) {
            revert Lending__InsufficientLiquidatorCorn();
        }
        
        uint256 userCollateral = s_userCollateral[user];
        uint256 collateralValue = calculateCollateralValue(user);
        
        // Transfer debt payment from liquidator
        i_corn.transferFrom(msg.sender, address(this), userDebt);
        s_userBorrowed[user] = 0;
        
        // Calculate collateral to liquidate and reward
        uint256 collateral = (userDebt * userCollateral) / collateralValue;
        uint256 liquidatorReward = (collateral * LIQUIDATOR_REWARD) / 100;
        uint256 amountForLiquidator = collateral + liquidatorReward;
        
        // Ensure we don't exceed available collateral
        amountForLiquidator = amountForLiquidator > userCollateral ? userCollateral : amountForLiquidator;
        
        // Update user's collateral balance
        s_userCollateral[user] = userCollateral - amountForLiquidator;
        
        // Transfer collateral to liquidator
        (bool success,) = payable(msg.sender).call{ value: amountForLiquidator }("");
        if (!success) {
            revert Lending__TransferFailed();
        }
        
        emit Liquidation(user, msg.sender, amountForLiquidator, userDebt, i_cornDEX.currentPrice());
    }
}