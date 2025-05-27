# ZK Battleship Deployment Guide

This document provides instructions for deploying the ZK Battleship project to the Base Mainnet.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) for contract compilation and deployment
- Cast keystore with Base Mainnet ETH for deployment
- Base Mainnet RPC URL (e.g., from [Base documentation](https://docs.base.org/tools/node-providers))

## Environment Setup

1. Create a `.env` file based on the example:
```bash
cp .env.example .env
```

2. Fill in the required values:
```
# Set up Cast keystore first: cast wallet import deployKey --interactive
BASE_MAINNET_RPC_URL=https://mainnet.base.org
BASE_MAINNET_WS_URL=wss://mainnet.base.org
BASE_MAINNET_API_KEY=your_basescan_api_key_for_verification
BACKEND_ADDRESS=your_backend_address_or_can_leave_empty
ADMIN_ADDRESS=your_admin_address
TREASURY_ADDRESS=your_treasury_address
USDC_ADDRESS=0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
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
- Deploy them to Base Mainnet
- Update the deployment configuration
- Save contract addresses to `.env` and `deployment-config.json` files

### Manual Deployment

If you prefer to run the deployment manually:

```bash
forge script scripts/deploy/Deploy.s.sol:DeployZKBattleship \
  --rpc-url $BASE_MAINNET_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $BASE_MAINNET_API_KEY \
  --account deployKey
```

## Deployed Contracts

After deployment, the following contracts will be available on Base Mainnet:

1. **SHIPToken**: ERC20 token for rewards
2. **BattleshipGameImplementation**: Core game logic implementation
3. **BattleshipStatistics**: Player statistics tracking
4. **GameFactoryWithStats**: Factory for creating game instances

## Verification

All contracts will be automatically verified on [Base Mainnet Explorer](https://basescan.org/) if you provided an API key.

If verification fails, you can manually verify using:

```bash
forge verify-contract \
  --chain-id 8453 \
  --compiler-version v0.8.29 \
  --constructor-args $(cast abi-encode "constructor(address,address,uint256)" $ADMIN_ADDRESS $BACKEND_ADDRESS 1000000000000000000000000) \
  $DEPLOYED_ADDRESS \
  src/SHIPToken.sol:SHIPToken \
  --etherscan-api-key $BASE_MAINNET_API_KEY
```

Replace the parameters as needed for each contract.

## Contract Interaction

After deployment, you can interact with the contracts:

1. **Create a game**:
```bash
cast send $GAME_FACTORY_ADDRESS "createGame(address,address)" $PLAYER1_ADDRESS $PLAYER2_ADDRESS \
  --rpc-url $BASE_MAINNET_RPC_URL \
  --account backendKey
```

2. **Get player statistics**:
```bash
cast call $STATS_ADDRESS "getPlayerStats(address)" $PLAYER_ADDRESS \
  --rpc-url $BASE_MAINNET_RPC_URL
```

## Next Steps

- Set up your backend to communicate with the deployed contracts
- Configure your frontend to display game state and statistics
- Monitor game activity on the Base Mainnet explorer

## Troubleshooting

- **Insufficient funds**: Ensure your deployer account has enough Base Mainnet ETH
- **Failed transactions**: Check gas limits and ensure the RPC URL is correct
- **Verification issues**: Double-check API key and contract parameters

For further assistance, check the Base documentation or open an issue on GitHub.

---

# Deployment History

## Base Mainnet

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