# Claude Guide for ZK Battleship Project

## Project Context

ZK Battleship is an on-chain implementation of the classic Battleship game that uses zero-knowledge proofs to maintain privacy while ensuring fair play. The project runs on the Base network, which provides low gas fees and fast confirmations necessary for interactive gameplay.

## Technical Overview

### Core Concepts

- **Zero-Knowledge Proofs**: Used to verify board placement validity, shot results, and game completion without revealing actual board states
- **UUPS Upgradeability**: Universal Upgradeable Proxy Standard for smart contract upgrades without state loss
- **Commit-Reveal Scheme**: Players commit to ship positions cryptographically before gameplay begins
- **On-Chain Gaming**: All game state transitions happen on the blockchain with minimal latency

### Architecture

The system has these primary components:

1. **GameFactory**: Creates game instances and manages player-to-game mappings
2. **BattleshipGameProxy**: Permanent address for each game instance, delegates to implementation
3. **BattleshipGameImplementation**: Core game logic and rules with upgradeability built in
4. **BattleshipStatistics**: Tracks player and game statistics
5. **ShipToken**: Rewards token for gameplay and victories

## Development Guidance

### Smart Contract Modifications

When modifying smart contracts, be aware of:

1. **Storage Layout**: Never reorder storage variables in upgradeable contracts
2. **Implementation vs. Proxy**: Logic goes in implementation; proxy should remain minimal
3. **Gas Optimization**: Use bit-packing and efficient data structures (see GameStorage.sol)
4. **Access Control**: Respect the role-based permissions defined in contracts

### Integration Pattern

For working with backend-driven ZK Battleship:

1. Backend creates games via GameFactory
2. Backend handles game logic and validation
3. Backend submits final results to contracts
4. Contracts distribute rewards and update statistics

### Common Development Tasks

#### Adding Game Features

1. First modify the implementation contract (BattleshipGameImplementation.sol)
2. Ensure storage layout compatibility with existing deployment
3. Test thoroughly with hardhat/foundry
4. Deploy new implementation
5. Propose upgrade through GameUpgradeManager
6. Execute upgrade after timelock period

#### Debugging Gas Issues

1. Use Foundry's gas reports to identify expensive operations
2. Look for opportunities to pack data more efficiently
3. Consider whether operations can be batched
4. Review GameStorage.sol for optimization patterns

#### Handling Upgrades

1. Create new implementation contract
2. Run storage layout compatibility checks
3. Use the upgradeability pattern:
   ```solidity
   function _authorizeUpgrade(address newImplementation) 
       internal 
       override 
       onlyRole(DEFAULT_ADMIN_ROLE) 
   {
       // Validation logic here
   }
   ```

## Project Conventions

### Code Style

- Solidity version: ^0.8.20
- Use OpenZeppelin contracts for standard implementations
- Follow the NatSpec format for documentation
- Prefer external over public for functions when possible
- Use clear error messages in require statements

### Naming Conventions

- Contracts: PascalCase (GameFactory, BattleshipGameImplementation)
- Functions: camelCase (createGame, submitBoard)
- State variables: camelCase (gameId, player1)
- Events: PascalCase (GameCreated, BoardSubmitted)

### Testing Approach

- Unit tests for each contract function
- Integration tests for complete gameplay flows
- Mock the ZK verification for most tests
- Full ZK proof generation and verification in specialized tests

## Deployment Process

1. Update the `.env` file with Base Sepolia settings
2. Run the deployment script: `./scripts/deploy.sh`
3. Verify all contracts on Base Sepolia explorer
4. Update configuration with new contract addresses
5. Test deployment with backend integration

## Useful Commands

```bash
# Build the project
forge build --optimize

# Run tests
forge test

# Deploy to Base Sepolia
./scripts/deploy.sh

# Upgrade implementation (after deploying new implementation)
forge script scripts/upgrade/Upgrade.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast
```

## Important Files

- `src/BattleshipGameImplementation.sol`: Core game logic
- `src/GameFactory.sol`: Entry point for players, creates game instances
- `src/BattleshipStatistics.sol`: Player and game statistics tracking
- `src/libraries/GameStorage.sol`: Optimized storage patterns
- `src/proxies/BattleshipGameProxy.sol`: Proxy contract for each game instance
- `src/ShipToken.sol`: ERC-20 token for rewards

When working with Claude Code, ask me to focus on specific files or development tasks for more detailed assistance.