## Contract Structure Overview

The smart contract architecture for ZK Battleship V1 consists of five main components with upgradeability built in:

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

## Detailed Contract Designs

### 1. GameFactory Contract

**Purpose**: Creates and tracks game instances, serves as the entry point for players.

**Key Features**:

- Creates new game instances as proxy contracts
- Maintains registry of active games
- Manages player-to-game mappings
- Supports upgradeable game implementations

**State Variables**:

```solidity
// Mapping from game ID to game proxy address
mapping(uint256 => address) public games;

// Mapping from player address to active game IDs
mapping(address => uint256[]) public playerGames;

// Game ID counter for unique identifiers
uint256 private nextGameId;

// Current implementation address
address public currentImplementation;

// Reference to token contract
SHIPToken public shipToken;

// Upgrade manager reference
GameUpgradeManager public upgradeManager;

```

**Key Functions**:

```solidity
// Create a new game
function createGame(address opponent) external returns (uint256 gameId)

// Update implementation address (only upgrade manager)
function setImplementation(address newImplementation) external onlyUpgradeManager

// Join an existing game by ID
function joinGame(uint256 gameId) external

// Get list of active games for a player
function getPlayerGames(address player) external view returns (uint256[] memory)

// Cancel a game that hasn't started
function cancelGame(uint256 gameId) external

```

### 2. BattleshipGameProxy Contract

**Purpose**: Serves as the permanent address for a game instance while delegating logic to the current implementation.

**Key Features**:

- Uses UUPS (Universal Upgradeable Proxy Standard) pattern
- Delegates all calls to implementation contract
- Maintains game state across upgrades
- Minimal and non-upgradeable itself

**Implementation**:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BattleshipGameProxy is ERC1967Proxy {
    constructor(
        address _logic,
        bytes memory _data
    ) ERC1967Proxy(_logic, _data) {}
}

```

### 3. BattleshipGameImplementation Contract

**Purpose**: Contains the upgradeable game logic and rules for battleship games.

**Key Features**:

- Implements the core game logic and rules
- Uses initializer pattern instead of constructor
- Includes UUPS upgrade logic
- Versioned for tracking upgrades

**State Variables**:

```solidity
// Using OpenZeppelin's upgradeable contracts
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

// Version tracking
string public constant VERSION = "1.0.0";

// Game metadata
uint256 public gameId;
address public factory;
uint8 public boardSize; // Default 10x10

// Player information
address public player1;
address public player2;
address public currentTurn;

// Game state
enum GameState { Created, Setup, Active, Completed, Cancelled }
GameState public state;

// Boards and ships
bytes32 public player1BoardCommitment;
bytes32 public player2BoardCommitment;
mapping(address => bool[]) public shots; // Tracks all shots by each player
mapping(address => bool[]) public hits;  // Tracks all hits by each player

// Final results
address public winner;
uint256 public gameEndTime;

```

**Key Functions**:

```solidity
// Initializer (replaces constructor in upgradeable contracts)
function initialize(
    uint256 _gameId,
    address _player1,
    address _player2,
    address _factory
) public initializer {
    __UUPSUpgradeable_init();
    __AccessControl_init();

    gameId = _gameId;
    player1 = _player1;
    player2 = _player2;
    factory = _factory;
    state = GameState.Created;
    boardSize = 10; // Default 10x10 board

    // Grant factory the ability to manage this game
    _grantRole(DEFAULT_ADMIN_ROLE, factory);
}

// Submit board placement with ZK proof
function submitBoard(bytes32 boardCommitment, bytes calldata zkProof) external

// Make a shot at target coordinates
function makeShot(uint8 x, uint8 y) external

// Submit hit/miss result with ZK proof
function submitShotResult(uint8 x, uint8 y, bool isHit, bytes calldata zkProof) external

// Verify game ending
function verifyGameEnd(bytes calldata zkProof) external

// Claim reward after game completion
function claimReward() external

// Forfeit game (surrender)
function forfeit() external

// UUPS upgrade authorization (only factory can trigger upgrades)
function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
    // Additional validation can be added here
}

```

### 4. GameUpgradeManager Contract

**Purpose**: Manages the upgrade process and provides governance controls.

**Key Features**:

- Controls implementation upgrades
- Implements timelock for transparency
- Provides emergency upgrade capabilities
- Tracks upgrade history

**State Variables**:

```solidity
// Admin role for upgrade authorization
address public admin;

// Pending implementation for timelock
address public pendingImplementation;

// Timestamp when pending implementation can be activated
uint256 public upgradeTimestamp;

// Timelock duration (default: 48 hours for V1)
uint256 public timelockDuration = 48 hours;

// Upgrade history
struct UpgradeRecord {
    address oldImplementation;
    address newImplementation;
    uint256 timestamp;
    string reason;
}

UpgradeRecord[] public upgradeHistory;

```

**Key Functions**:

```solidity
// Propose a new implementation (starts timelock)
function proposeUpgrade(
    address newImplementation,
    string calldata reason
) external onlyAdmin {
    pendingImplementation = newImplementation;
    upgradeTimestamp = block.timestamp + timelockDuration;

    emit UpgradeProposed(newImplementation, upgradeTimestamp, reason);
}

// Execute upgrade after timelock expires
function executeUpgrade() external onlyAdmin {
    require(block.timestamp >= upgradeTimestamp, "Timelock not expired");
    require(pendingImplementation != address(0), "No pending implementation");

    address oldImplementation = GameFactory(factory).currentImplementation();

    // Update factory to use new implementation
    GameFactory(factory).setImplementation(pendingImplementation);

    // Record upgrade in history
    upgradeHistory.push(UpgradeRecord({
        oldImplementation: oldImplementation,
        newImplementation: pendingImplementation,
        timestamp: block.timestamp,
        reason: pendingReason
    }));

    emit UpgradeExecuted(oldImplementation, pendingImplementation);

    // Reset pending state
    pendingImplementation = address(0);
    upgradeTimestamp = 0;
}

// Emergency upgrade (bypass timelock, for critical vulnerabilities)
function emergencyUpgrade(
    address newImplementation,
    string calldata reason
) external onlyAdmin {
    address oldImplementation = GameFactory(factory).currentImplementation();

    // Update factory immediately
    GameFactory(factory).setImplementation(newImplementation);

    // Record upgrade in history
    upgradeHistory.push(UpgradeRecord({
        oldImplementation: oldImplementation,
        newImplementation: newImplementation,
        timestamp: block.timestamp,
        reason: reason
    }));

    emit EmergencyUpgradeExecuted(oldImplementation, newImplementation, reason);
}

```

### 5. GameStorage Library

**Purpose**: Optimizes storage and retrieval of game state to minimize gas costs.

**Key Features**:

- Efficient board state representation
- Compressed storage of shot history
- Gas-optimized data structures
- Compatible with upgrades

**Key Functions**:

```solidity
// Store board state efficiently
function storeBoard(bytes32 commitment) internal

// Record a shot
function recordShot(address player, uint8 x, uint8 y) internal

// Record a hit
function recordHit(address player, uint8 x, uint8 y) internal

// Check if all ships are sunk
function checkAllShipsSunk(address player) internal view returns (bool)

// Get state fingerprint for verification
function getStateFingerprint() internal view returns (bytes32)

```

### 6. ZKVerifier Contract

**Purpose**: Validates zero-knowledge proofs for game actions.

**Key Features**:

- Verifies board placement proofs
- Validates shot result proofs
- Confirms game ending proofs
- Non-upgradeable for security

**Key Functions**:

```solidity
// Verify valid board placement
function verifyBoardPlacement(
    bytes32 boardCommitment,
    bytes calldata proof
) external view returns (bool)

// Verify shot result
function verifyShotResult(
    bytes32 boardCommitment,
    uint8 x,
    uint8 y,
    bool claimed_hit,
    bytes calldata proof
) external view returns (bool)

// Verify game ending state
function verifyGameEnd(
    bytes32 boardCommitment,
    bytes32 shotHistoryHash,
    bytes calldata proof
) external view returns (bool)

```

### 7. SHIPToken Contract

**Purpose**: Handles token issuance and rewards for gameplay.

**Key Features**:

- ERC-20 token implementation
- Game completion rewards
- Victory bonuses
- Non-upgradeable for stability

**State Variables**:

```solidity
// ERC-20 standard variables
string public constant name = "Battleship SHIP";
string public constant symbol = "SHIP";
uint8 public constant decimals = 18;
uint256 private _totalSupply;

// Reward parameters
uint256 public participationReward = 10 * 10**18; // 10 SHIP
uint256 public victoryBonus = 25 * 10**18;       // 25 SHIP

// Permission management
address public owner;
address public gameFactory;

```

**Key Functions**:

```solidity
// Mint rewards for game participation
function mintGameReward(address player, bool isWinner) external

// Update reward parameters (admin only)
function updateRewardParameters(
    uint256 newParticipationReward,
    uint256 newVictoryBonus
) external onlyOwner

// Set approved game factory (admin only)
function setGameFactory(address newFactory) external onlyOwner

// Standard ERC-20 functions
function transfer(address to, uint256 amount) external returns (bool)
function approve(address spender, uint256 amount) external returns (bool)
function transferFrom(address from, address to, uint256 amount) external returns (bool)
function balanceOf(address account) external view returns (uint256)

```

## Contract Interactions & Upgrade Flow

### Game Creation Flow

1. Player calls `GameFactory.createGame(opponent)`
2. GameFactory:
    - Generates unique gameId
    - Deploys new BattleshipGameProxy with current implementation address
    - Initializes game with player addresses
    - Maps gameId to proxy address
    - Adds gameId to player's active games list
    - Emits GameCreated event

### Gameplay Flow

1. **Setup Phase**:
    - Both players call `BattleshipGame.submitBoard(boardCommitment, zkProof)`
    - ZKVerifier validates board placements
    - Game transitions to Active state once both boards are submitted
2. **Active Phase**:
    - Current player calls `BattleshipGame.makeShot(x, y)`
    - Game records shot and notifies target player
    - Target player's client generates proof of hit/miss
    - Target player calls `BattleshipGame.submitShotResult(x, y, isHit, zkProof)`
    - ZKVerifier validates shot result
    - Game updates state and transitions turn
3. **Completion Phase**: 
    - When all ships of a player are sunk, game can be ended
    - Either player can call `BattleshipGame.verifyGameEnd(zkProof)`
    - ZKVerifier confirms valid game ending
    - Game transfers to Completed state
    - SHIPToken mints rewards for both players

### Upgrade Process Flow

1. **Propose Upgrade**:
    - Admin identifies need for upgrade (new features, bug fixes)
    - Admin calls `GameUpgradeManager.proposeUpgrade(newImplementationAddress, reason)`
    - New implementation is built and deployed, but not yet activated
    - Timelock period begins (48 hours in V1)
2. **Review Period**:
    - Community can review proposed implementation code
    - Stakeholders can prepare for any changes
    - If critical issues found, proposal can be cancelled
3. **Execute Upgrade**:
    - After timelock expires, admin calls `GameUpgradeManager.executeUpgrade()`
    - GameFactory's currentImplementation is updated
    - New games will use new implementation
    - Upgrade recorded in history
4. **Effect on Existing Games**:
    - Existing game proxies point to old implementation until completed
    - New games use new implementation
    - This prevents disruption to in-progress games
5. **Emergency Process**:
    - For critical vulnerabilities, `emergencyUpgrade()` bypasses timelock
    - Reserved for security issues only
    - Requires strong governance controls

## Security Considerations

1. **ZK Proof Validation**:
    - All game state transitions verified by ZK proofs
    - Independent verification of win conditions
    - Protection against board manipulation
2. **Access Control**:
    - Only players can interact with their game
    - Factory controls game creation
    - Only authorized contracts can mint tokens
3. **Game Integrity**:
    - Timeout mechanisms for inactive players
    - Forfeit ability to prevent deadlocks
    - Cryptographic commitments of board states
4. **Economic Security**:
    - Rate limiting for reward issuance
    - Caps on rewards per time period
    - Factory approval for token minting

## Circuit Design Overview

The ZK circuits for Battleship comprise three main components:

1. **Board Placement Circuit**:
    - Inputs: Ship positions, board size, salt
    - Constraints:
        - Ships are within board boundaries
        - Ships have correct sizes (5,4,3,3,2)
        - No ships overlap
    - Output: Valid board commitment
2. **Shot Verification Circuit**:
    - Inputs: Board state, shot coordinates, hit/miss claim, salt
    - Constraints:
        - Shot coordinates are valid
        - Hit/miss result matches actual board state
    - Output: Valid shot result verification
3. **Game Ending Circuit**:
    - Inputs: Board state, shot history, salt
    - Constraints:
        - All ships are hit properly
        - Win condition is met
    - Output: Valid game completion verification

## Gas Optimization Strategies

1. **Efficient Board Representation**:
    - Bitpacked board states to minimize storage
    - Use of bytes32 for commitments rather than larger structures
2. **Minimal On-Chain Storage**:
    - Store only cryptographic commitments of board states
    - Keep full board state off-chain
    - Record only shot coordinates and results, not full boards
3. **Batched Updates**:
    - Group state changes where possible
    - Optimize storage slot usage
4. **Library Usage**:
    - GameStorage as a library to reduce contract size
    - Share verification logic across game instances

## Upgradeability Design Rationale

### 1. UUPS Pattern Selection

We've chosen the UUPS (Universal Upgradeable Proxy Standard) pattern over alternatives for several reasons:

- **Gas Efficiency**: The upgrade logic is in the implementation contract rather than the proxy, reducing proxy deployment costs
- **Security**: Upgrade functionality can be removed in final version if desired
- **Simplicity**: Proxy contract is minimal and less prone to errors
- **Compatibility**: Well-tested OpenZeppelin implementation available

### 2. Separation of Game Instances

Each game gets its own proxy contract with these benefits:

- **Isolation**: Issues in one game don't affect others
- **Gas Optimization**: Smaller state per contract
- **Clean Lifecycle**: Game contracts can be "completed" and removed from active lists
- **Upgrade Flexibility**: Different games can use different implementations if needed

### 3. Governance Controls

For V1, we implement a simple timelock mechanism:

- **Transparency**: 48-hour delay allows for review
- **Emergency Override**: Critical fixes can bypass timelock
- **Upgrade History**: All changes recorded on-chain for auditability
- **Future Expansion**: Can be replaced with more complex governance (e.g., DAO voting) in later versions

## Security Considerations

### 1. Upgrade-Related Risks

- **Storage Collisions**: Implementation upgrades must maintain storage layout compatibility
- **Initialization Risks**: Initializer functions replace constructors and must be properly secured
- **Admin Controls**: Initially centralized upgrade authority (can be decentralized in future versions)
- **Verification**: New implementations should be thoroughly audited before activation

### 2. Implementation Details

- **Storage Gaps**: Reserved slots in storage layout for future variables
- **Function Selector Stability**: Consistent function signatures across versions
- **Version Tracking**: Explicit versioning for easier audit trail
- **Separate Concerns**: Critical verification logic (ZKVerifier) is non-upgradeable

## Implementation Priorities for V1

For the V1 implementation with upgradeability, we prioritize:

1. Solid foundation with clean separation of concerns
2. Simple but effective governance via timelock
3. Minimal proxy contracts for efficiency
4. Clear upgrade paths for future improvements
5. Compatibility with all core gameplay features

Adding upgradeability to V1 provides:

- **Future-proofing**: Architecture supports evolution without disruption
- **Risk mitigation**: Ability to fix issues quickly if discovered
- **Feature expansion**: Path to add betting, tournaments, etc. in future updates
- **Economic flexibility**: Reward parameters can be adjusted based on usage data