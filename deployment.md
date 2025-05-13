# ZK Battleship Deployment Guide

This document provides instructions for deploying the ZK Battleship project to the Base Sepolia testnet.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) for contract compilation and deployment
- Private key with Base Sepolia ETH for deployment
- Base Sepolia RPC URL (e.g., from [Base documentation](https://docs.base.org/tools/node-providers))

## Environment Setup

1. Create a `.env` file based on the example:
```bash
cp .env.example .env
```

2. Fill in the required values:
```
PRIVATE_KEY=your_private_key_here
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BASE_SEPOLIA_WS_URL=wss://sepolia.base.org
BASE_SEPOLIA_API_KEY=your_basescan_api_key_for_verification
BACKEND_ADDRESS=your_backend_address_or_can_leave_empty
```

## Deployment Process

### 1. Update Dependencies

```bash
forge install
```

### 2. Build Contracts

```bash
forge build --optimize
```

### 3. Run Deployment Script

```bash
./scripts/deploy.sh
```

This script will:
- Build the contracts
- Deploy them to Base Sepolia testnet
- Update the deployment configuration
- Save contract addresses to `.env` and `deployment-config.json` files

### Manual Deployment

If you prefer to run the deployment manually:

```bash
forge script scripts/deploy/Deploy.s.sol:DeployZKBattleship \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $BASE_SEPOLIA_API_KEY \
  --private-key $PRIVATE_KEY
```

## Deployed Contracts

After deployment, the following contracts will be available on Base Sepolia:

1. **SHIPToken**: ERC20 token for rewards
2. **BattleshipGameImplementation**: Core game logic implementation
3. **BattleshipStatistics**: Player statistics tracking
4. **GameFactoryWithStats**: Factory for creating game instances

## Verification

All contracts will be automatically verified on [Base Sepolia Explorer](https://sepolia.basescan.org/) if you provided an API key.

If verification fails, you can manually verify using:

```bash
forge verify-contract \
  --chain-id 84532 \
  --compiler-version v0.8.29 \
  --constructor-args $(cast abi-encode "constructor(address,address,uint256)" $ADMIN_ADDRESS $BACKEND_ADDRESS 1000000000000000000000000) \
  $DEPLOYED_ADDRESS \
  src/SHIPToken.sol:SHIPToken \
  --etherscan-api-key $BASE_SEPOLIA_API_KEY
```

Replace the parameters as needed for each contract.

## Contract Interaction

After deployment, you can interact with the contracts:

1. **Create a game**:
```bash
cast send $GAME_FACTORY_ADDRESS "createGame(address,address)" $PLAYER1_ADDRESS $PLAYER2_ADDRESS \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $BACKEND_PRIVATE_KEY
```

2. **Get player statistics**:
```bash
cast call $STATS_ADDRESS "getPlayerStats(address)" $PLAYER_ADDRESS \
  --rpc-url $BASE_SEPOLIA_RPC_URL
```

## Next Steps

- Set up your backend to communicate with the deployed contracts
- Configure your frontend to display game state and statistics
- Monitor game activity on the Base Sepolia explorer

## Troubleshooting

- **Insufficient funds**: Ensure your deployer account has enough Base Sepolia ETH
- **Failed transactions**: Check gas limits and ensure the RPC URL is correct
- **Verification issues**: Double-check API key and contract parameters

For further assistance, check the Base documentation or open an issue on GitHub.

---

# Deployment History

## Base Sepolia Testnet

Deployment in progress...

<!--
### Game Contracts

| Contract | Address | Description |
|----------|---------|-------------|
| SHIPToken | TBD | Game reward token |
| BattleshipGameImplementation | TBD | Core game logic |
| BattleshipStatistics | TBD | Statistics tracking |
| GameFactoryWithStats | TBD | Creates new game instances |

### Deployment Date

The contracts were deployed on [date].

### Verification Status

- [ ] SHIPToken verified on explorer
- [ ] BattleshipGameImplementation verified on explorer
- [ ] BattleshipStatistics verified on explorer
- [ ] GameFactoryWithStats verified on explorer
-->