# Claude Guide for ZK Battleship Project

## Project Context

ZK Battleship is an on-chain implementation of the classic Battleship game that uses zero-knowledge proofs to maintain privacy while ensuring fair play. The project runs on the MegaETH network, which provides low-latency transactions (~10ms) necessary for interactive gameplay.

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
4. **ZKVerifier**: Validates all ZK proofs for the game (board placement, shot results, game ending)
5. **GameStorage**: Optimizes on-chain storage for game state
6. **GameUpgradeManager**: Controls implementation upgrades with timelock mechanism
7. **SHIPToken**: Rewards token for gameplay and victories

## Development Guidance

### Smart Contract Modifications

When modifying smart contracts, be aware of:

1. **Storage Layout**: Never reorder storage variables in upgradeable contracts
2. **Implementation vs. Proxy**: Logic goes in implementation; proxy should remain minimal
3. **Gas Optimization**: Use bit-packing and efficient data structures (see GameStorage.sol)
4. **Access Control**: Respect the role-based permissions defined in contracts

### ZK Circuit Integration

For working with the ZK verifier contracts:

1. **Verifier Types**:
   - BoardPlacementVerifier: Validates ship placement rules
   - ShotResultVerifier: Confirms honest reporting of hits/misses
   - GameEndVerifier: Validates game completion state

2. **Expected Public Inputs**:
   - Board Placement: 1 public input (board commitment)
   - Shot Result: 4 public inputs (board commitment, x, y, isHit)
   - Game End: 2 public inputs (board commitment, shot history hash)

3. **Integration Pattern**:
   ```solidity
   // Example verification call
   require(
       zkVerifier.verifyBoardPlacement(boardCommitment, zkProof),
       "Invalid board placement proof"
   );
   ```

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

## Troubleshooting Common Issues

### "Stack Too Deep" Errors with Verifier Contracts

Solution: Use the pre-build script to handle compilation:
```bash
./scripts/pre-build.sh --optimize --via-ir
```

### Upgrade Issues

If upgrades fail, check:
1. Storage layout compatibility
2. Function selector conflicts
3. Access control permissions
4. Timelock period completion

### ZK Proof Verification Failures

Common causes:
1. Incorrect public input format/order
2. Mismatched circuit and verifier contract
3. Invalid proof generation parameters

## MegaETH-Specific Considerations

- Use WebSocket subscriptions for real-time game updates
- Take advantage of fast mini blocks for responsive gameplay
- Consider realtime API endpoints for UI interaction
- Test gas consumption thoroughly as MegaETH has different cost profiles

## Deployment Process

1. Prepare verifier contracts
2. Deploy ZKVerifier first
3. Deploy GameFactory and supporting contracts
4. Link contracts together (set references)
5. Initialize system parameters
6. Verify all contracts on MegaETH explorer

## Useful Commands

```bash
# Build the project
./scripts/pre-build.sh --optimize --via-ir

# Run tests
forge test

# Deploy to MegaETH
./scripts/deploy.sh

# Upgrade implementation (after deploying new implementation)
forge script script/upgrade/UpgradeImplementation.s.sol --rpc-url $MEGAETH_RPC_URL --broadcast
```

## Important Files

- `src/BattleshipGameImplementation.sol`: Core game logic
- `src/GameFactory.sol`: Entry point for players, creates game instances
- `src/verifiers/`: Contains the three ZK verifier contracts
- `src/libraries/GameStorage.sol`: Optimized storage patterns
- `src/proxies/BattleshipGameProxy.sol`: Proxy contract for each game instance
- `src/SHIPToken.sol`: ERC-20 token for rewards

When working with Claude Code, ask me to focus on specific files or development tasks for more detailed assistance.