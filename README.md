# 💳🌽 Ethereum Over-Collateralized Lending Challenge

A decentralized lending platform built on Ethereum that allows users to borrow CORN tokens using ETH as collateral. This project is part of the SpeedRunEthereum challenges.

## 🎯 Project Overview

This lending dApp creates a simple but powerful over-collateralized lending system where users deposit ETH as collateral and borrow CORN tokens against it. The system maintains safety through liquidation mechanisms and collateralization ratios.

### Key Features

- **ETH Collateral Deposits**: Users deposit ETH to secure their borrowing position
- **CORN Token Borrowing**: Borrow CORN tokens up to 83.33% of collateral value (120% collateral ratio)
- **Liquidation System**: Positions below 120% collateral ratio can be liquidated by anyone
- **Liquidator Incentives**: 10% bonus reward for liquidators to ensure system stability
- **Price Oracle Integration**: Uses CornDEX contract as price oracle for ETH/CORN exchange rates

## 🔧 Smart Contract Architecture

The project consists of four main contracts:

### 1. Lending Contract (`Lending.sol`)
The core contract that handles:
- Collateral deposits and withdrawals
- CORN borrowing and repayment
- Position health calculations
- Liquidation mechanics

### 2. CORN Token (`Corn.sol`)
- Standard ERC20 token that users can borrow
- The borrowable asset in the lending system

### 3. CornDEX (`CornDEX.sol`)
- DEX contract for ETH/CORN swaps
- Acts as price oracle for collateral valuation
- Enables price manipulation for testing scenarios

### 4. MovePrice (`MovePrice.sol`)
- Utility contract for making large swaps
- Used to change asset ratios and test price movements

## 🎮 How It Works

1. **Deposit Collateral**: Users send ETH to the contract as collateral
2. **Borrow CORN**: Users can borrow CORN tokens up to 83.33% of their ETH collateral value
3. **Maintain Health**: Position must stay above 120% collateralization ratio
4. **Repay or Get Liquidated**: 
   - Repay CORN to maintain position
   - If ratio drops below 120%, anyone can liquidate for 10% profit
5. **Withdraw**: Remove excess collateral after repaying loans

## 🛠️ Key Functions

### Core Lending Functions
- `addCollateral()`: Deposit ETH as collateral (payable)
- `withdrawCollateral(uint256 amount)`: Withdraw excess collateral
- `borrowCorn(uint256 borrowAmount)`: Borrow CORN against collateral
- `repayCorn(uint256 repayAmount)`: Repay borrowed CORN tokens
- `liquidate(address user)`: Liquidate underwater positions

### Helper Functions
- `calculateCollateralValue(address user)`: Get collateral value in CORN terms
- `isLiquidatable(address user)`: Check if position can be liquidated
- `_calculatePositionRatio(address user)`: Calculate current collateral ratio

## 🔍 Contract Constants

```solidity
uint256 public constant COLLATERAL_RATIO = 120e18; // 120% minimum ratio
uint256 public constant LIQUIDATOR_REWARD = 10; // 10% liquidation bonus
```

## 📊 Economic Model

### Collateralization Requirements
- **Minimum Ratio**: 120% (borrowers must have $1.20 in ETH for every $1.00 in CORN borrowed)
- **Maximum Borrow**: ~83.33% of collateral value
- **Liquidation Trigger**: When ratio falls below 120%

### Liquidation Process
1. Position becomes liquidatable when collateral ratio < 120%
2. Liquidator repays borrower's CORN debt
3. Liquidator receives equivalent ETH collateral + 10% bonus
4. Original borrower keeps their CORN tokens but loses collateral

## 🚀 Getting Started

### Prerequisites
- Node.js (v18 LTS)
- Yarn (v1 or v2+)
- Git

### Setup
```bash
# Clone the challenge
npx create-eth@1.0.2 -e challenge-over-collateralized-lending challenge-over-collateralized-lending
cd challenge-over-collateralized-lending

# Start local blockchain
yarn chain

# Deploy contracts (new terminal)
yarn deploy

# Start frontend (new terminal)  
yarn start
```

### Testing
```bash
# Run market simulation with bots
yarn simulate

# Fresh deployment
yarn deploy --reset
```

## 🎯 Learning Outcomes

This challenge demonstrates:

- **Over-Collateralized Lending**: Understanding why DeFi lending requires more collateral than borrowed value
- **Liquidation Mechanics**: Building automated systems to prevent bad debt
- **Price Oracle Integration**: Using external price feeds for collateral valuation
- **Financial Risk Management**: Implementing safety margins and incentive structures
- **Smart Contract Security**: Position validation and safe transfer patterns

## 🔗 Challenge Deployment

### Testnet Deployment
```bash
# Generate deployer account
yarn generate

# Check balance
yarn account

# Deploy to testnet (get testnet ETH first)
yarn deploy --network sepolia

# Verify contracts
yarn verify --network sepolia
```

### Frontend Deployment
```bash
# Configure target network in scaffold.config.ts
# Deploy frontend
yarn vercel
```

## 🎮 Testing Scenarios

1. **Basic Flow**: Deposit ETH → Borrow CORN → Repay → Withdraw
2. **Price Movement**: Use +/- buttons to change CORN price and see position health change
3. **Liquidation**: Create underwater position and liquidate it from another account
4. **Multi-Account**: Use private browser tabs to simulate multiple users

## 🏆 Challenge Completion Checklist

- ✅ `addCollateral()` and `withdrawCollateral()` functions working
- ✅ `borrowCorn()` and `repayCorn()` functions implemented
- ✅ Helper functions for position calculations
- ✅ `liquidate()` function with proper incentives
- ✅ Position validation preventing unsafe withdrawals
- ✅ Frontend integration and wallet connection
- ✅ Contracts deployed to testnet
- ✅ Contract verification on Etherscan
- ✅ Frontend deployed to public URL

## 💡 Use Cases for Over-Collateralized Lending

- **Maintaining Price Exposure**: Keep ETH exposure while accessing liquidity
- **Leverage Trading**: Borrow assets to increase position sizes
- **Tax Optimization**: Access funds without triggering taxable sale events

## 🔗 Links

- [SpeedRunEthereum Challenge](https://speedrunethereum.com/challenge/over-collateralized-lending)
- [Live Demo](https://overlending-oact2d27i-einarmigs-projects.vercel.app)
- [Contract Verification](https://sepolia.etherscan.io/address/0x159AA20E6cC45eEfe0D5905C5c059bd8DD849466)

---

*Built with 🌽 as part of the SpeedRunEthereum journey*

> **Educational Purpose**: This is a simplified lending protocol for learning. Production systems require additional security measures, proper oracles, and comprehensive audits.