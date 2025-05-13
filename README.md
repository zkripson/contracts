# Kripson Overview

This project implements an onchain Battleship game optimized for Layer 2 networks like Base. Players can create games, place ships, and battle in real-time using smart contracts. The game logic is fully implemented onchain, with state verification and anti-cheat mechanisms built into the protocol.

## Features

- Complete onchain Battleship game mechanics
- Optimized for Layer 2 performance
- Private ship placement with commit-reveal scheme
- Fair matchmaking and turn enforcement
- Upgradeable game contracts for future feature expansion
- WebSocket event subscriptions for real-time game updates
- Comprehensive test suite simulating complete game scenarios

## Architecture Overview

The ZK Battleship contract system consists of the following components:

```
┌──────────────────────────────────────────────────────────────────────┐
│                      ZK Battleship Contract System                    │
└──────────────────────────────────────┬───────────────────────────────┘
                                       │
           ┌──────────────────────────┐│┌───────────────────────────┐
           │                          │││                           │
           │  ┌────────────────────┐  │││  ┌────────────────────┐   │
           │  │ GameFactory        │◄─┘│└─►│ $SHIPToken         │   │
           │  │ (Game Creation)    │   │   │ (Rewards)          │   │
           │  └──────────┬─────────┘   │   └────────────────────┘   │
           │             │             │                             │
           │  ┌──────────▼─────────┐   │   ┌────────────────────┐   │
           │  │ BattleshipGameProxy│   │   │ ZKVerifier         │   │
           │  │ (Permanent Address)│◄──┼───┤ (Proof Validation) │   │
           │  └──────────┬─────────┘   │   └────────────────────┘   │
           │             │             │                             │
           │             │             │   ┌────────────────────┐   │
           │  ┌──────────▼─────────┐   │   │ GameUpgradeManager │   │
           │  │ Game Implementation│◄──┼───┤ (Upgrade Control)  │   │
           │  │ (Upgradeable Logic)│   │   └────────────────────┘   │
           │  └──────────┬─────────┘   │                             │
           │             │             │                             │
           │  ┌──────────▼─────────┐   │                             │
           │  │ GameStorage        │   │                             │
           │  │ (State Management) │   │                             │
           │  └────────────────────┘   │                             │
           │                           │                             │
           │      Core Gameplay        │        Support Systems      │
           └───────────────────────────┘     └─────────────────────┘
```

## Core Components

### 1. BattleshipGameImplementation.sol

The main gameplay logic contract that implements:
- Game lifecycle management (Created -> Setup -> Active -> Completed/Cancelled)
- Move validation and state transitions
- Integration with ZK proof verification
- Access controls for players and admin functions
- Upgradeability via UUPS pattern

### 2. BattleshipGameProxy.sol

A simple proxy contract that follows the ERC1967 standard to:
- Provide a permanent address for each game instance
- Delegate all calls to the current implementation
- Maintain game state across upgrades

### 3. GameFactory.sol

Manages game creation and serves as the entry point for players:
- Creates new game instances as proxy contracts
- Maintains registry of active games
- Manages player-to-game mappings
- Controls implementation upgrades

### 4. ZKVerifier.sol

Validates zero-knowledge proofs for game actions:
- Verifies board placement proofs
- Validates shot result proofs
- Confirms game ending proofs

### 5. GameStorage.sol

Optimizes storage and retrieval of game state:
- Uses bit-packed board representation
- Compresses storage of shot history
- Provides gas-optimized data structures

## Upgradeability Design

The implementation uses the UUPS (Universal Upgradeable Proxy Standard) pattern:

1. The proxy contract is minimal and non-upgradeable itself
2. The implementation contract contains the upgrade logic
3. Upgrade authorization is controlled by access roles
4. Storage uses gap slots to allow future extensions

Benefits of this approach:
- **Gas Efficiency**: Reduced proxy deployment costs
- **Security**: Clear upgrade authorization controls
- **Simplicity**: Clean separation of concerns

## Optimized Storage

The GameStorage library provides optimized on-chain storage:

1. **Efficient Board Representation**:
   - Bit-packed ship positions using uint256
   - Compressed storage of hit and shot maps
   - Minimal storage requirements

2. **Gas Optimization**:
   - Each 10x10 board fits in a single storage slot
   - Coordinates are packed for efficient storage
   - O(1) lookups for shot and hit checks

## Game Flow

1. **Game Creation**:
   - Player calls `GameFactory.createGame(opponent)`
   - Factory deploys new proxy with implementation
   - Game initializes with both player addresses

2. **Board Submission**:
   - Players generate ZK proofs of valid board layouts
   - Both players call `submitBoard(commitment, proof)`
   - Once both boards are submitted, game moves to Active state

3. **Gameplay**:
   - Current player calls `makeShot(x, y)`
   - Target player calls `submitShotResult(x, y, isHit, proof)`
   - Turns alternate until win condition is met

4. **Game Completion**:
   - When all ships of a player are sunk
   - Player calls `verifyGameEnd(commitment, proof)`
   - Players can claim rewards via `claimReward()`


## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Bun](https://bun.sh/docs/installation) (for development tools and scripting)
- [Solhint](https://github.com/protofire/solhint) (`bun install -g solhint`)

## Project Structure

```
├── .github/            # GitHub Actions workflows
├── circuit/            # ZK circuit files
├── lib/                # Dependencies (managed by Foundry)
├── script/             # Deployment and operation scripts
│   ├── deploy/         # Deployment scripts
│   └── upgrade/        # Upgrade scripts
├── src/                # Smart contract source code
│   ├── access/         # Access control contracts
│   ├── interfaces/     # Interface definitions
│   ├── libraries/      # Shared libraries
│   └── proxies/        # Proxy contracts
└── test/               # Test suite
    ├── integration/    # Integration tests
    └── unit/           # Unit tests
```

## Getting Started

1. Clone this repository:
   ```bash
   git clone https://github.com/zkripson/contracts.git
   cd kripson
   ```

2. Install dependencies:
   ```bash
   forge install
   ```

3. Create a `.env` file from the example:
   ```bash
   cp .env.example .env
   ```

4. Configure your environment variables in the `.env` file.

Building the Project
We use a special build script to handle the verifier contracts, which are complex and can cause stack-too-deep errors when compiled.
Setup

Ensure the scripts are executable:

bashchmod +x scripts/pre-build.sh scripts/deploy.sh

Create a .env file with your deployment settings:

PRIVATE_KEY=your_private_key
MEGAETH_RPC_URL=your_rpc_url

## Building the Project

We use a special build script to handle the verifier contracts, which are complex and can cause stack-too-deep errors when compiled.

### Setup

1. Ensure the scripts are executable:

```bash
chmod +x scripts/pre-build.sh scripts/deploy.sh
```

2. Create a `.env` file with your deployment settings:

```
PRIVATE_KEY=your_private_key
BASE_SEPOLIA_RPC_URL=your_rpc_url
BASE_SEPOLIA_API_KEY=your_api_key_for_verification
```

### Building

To build the project:

```bash
forge build --optimize
```

For a build with specific parameters:

```bash
forge build --optimize --via-ir
```

### Deploying

To deploy the project:

```bash
./scripts/deploy.sh
```

This script will:
1. Build the contracts
2. Deploy the contracts to Base Sepolia testnet
3. Verify the contracts on the Base Sepolia explorer


6. Run tests:
   ```bash
   forge test
   ```

## Deploying to Base Sepolia

1. Ensure your `.env` file is properly configured with your private key and the Base Sepolia RPC URL.

2. Run the deployment script:
   ```bash
   forge script scripts/deploy/Deploy.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --private-key $PRIVATE_KEY
   ```
   
3. To verify contracts on Base Sepolia explorer:
   ```bash
   forge script scripts/deploy/Deploy.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --verify --etherscan-api-key $BASE_SEPOLIA_API_KEY --private-key $PRIVATE_KEY
   ```

## Base Network Details

Base is a secure, low-cost, builder-friendly Layer 2 solution built on Ethereum, offering:

- Fast transaction confirmations
- Low gas costs for better user experience
- Full Ethereum compatibility
- Strong security guarantees through Optimistic Rollups
- Reliable infrastructure built by Coinbase

For more details, refer to the [Base documentation](https://docs.base.org).

## Monitoring Events

The system emits various events to track game progression:

- Game creation and state transitions
- Player actions and turn progression
- Reward distribution on game completion

You can monitor these events using standard Ethereum event listeners or Base's RPC endpoints.

## License

This project is licensed under the MIT License - see the LICENSE file for details.