# Kripson Overview

This project implements an onchain Battleship game leveraging the MegaETH network's low-latency capabilities. Players can create games, place ships, and battle in real-time using smart contracts. The game logic is fully implemented onchain, with state verification and anti-cheat mechanisms built into the protocol.

## Features

- Complete onchain Battleship game mechanics
- Real-time gameplay using MegaETH's sub-10ms mini blocks
- Private ship placement with commit-reveal scheme
- Fair matchmaking and turn enforcement
- Upgradeable game contracts for future feature expansion
- WebSocket event subscriptions for real-time game updates
- Comprehensive test suite simulating complete game scenarios

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

5. Build the project:
   ```bash
   forge build
   ```

6. Run tests:
   ```bash
   forge test
   ```

## Deploying to MegaETH

1. Ensure your `.env` file is properly configured with your private key and the MegaETH RPC URL.

2. Run the deployment script:
   ```bash
   forge script script/deploy/Deploy.s.sol --rpc-url $MEGAETH_RPC_URL --broadcast
   ```

## MegaETH Network Details

MegaETH is a Layer 2 solution with the following features:

- Sequencers that execute transactions and assemble blocks
- Replica nodes that maintain chain state
- Realtime API for low-latency (~10ms) access to blockchain state
- Mini blocks for faster transaction confirmation
- WebSocket subscriptions for real-time data access

For more details, refer to the [MegaETH documentation](https://docs.megaeth.io).

## Using the Realtime API

MegaETH's Realtime API extends the standard Ethereum JSON-RPC API, providing:

- ~10ms latency via mini blocks (compared to 1s+ for standard EVM blocks)
- Immediate visibility of transaction data
- WebSocket subscriptions for real-time event streaming

For API details, see the [Realtime API documentation](https://docs.megaeth.io/realtime-api).

## License

This project is licensed under the MIT License - see the LICENSE file for details.