// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./libraries/GameStorage.sol";
import "./interfaces/IZKVerifier.sol";


/**
 * @title BattleshipGameImplementation
 * @dev Core game logic for ZK Battleship, following UUPS upgradeable pattern
 * @notice This implementation handles the game mechanics and integrates with ZK verification
 */
contract BattleshipGameImplementation is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    // Use GameStorage library for GameState struct
    using GameStorage for GameStorage.GameState;

    // ==================== Version Tracking ====================
    /// @notice Version identifier for tracking implementations
    string public constant VERSION = "1.0.0";

    // ==================== Role Definition ====================
    /// @notice Role for factory contract that manages game instances
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    // ==================== Game Constants ====================
    /// @notice Standard board size (10x10 grid)
    uint8 public constant BOARD_SIZE = 10;

    /// @notice Maximum number of shots a player can take (equals board size squared)
    uint16 public constant MAX_SHOTS = BOARD_SIZE * BOARD_SIZE;

    // ==================== Game State Enum ====================
    /// @notice Possible states for a game instance
    enum GameState {
        Created, // Game created but boards not submitted
        Setup, // One player submitted board, waiting for other
        Active, // Both boards submitted, gameplay active
        Completed, // Game completed with a winner
        Cancelled // Game cancelled before completion

    }

    // ==================== Storage ====================
    /// @notice Game state storage using GameStorage library
    GameStorage.GameState internal gameState;

    // ==================== Game Metadata ====================
    /// @notice Unique identifier for this game instance
    uint256 public gameId;

    /// @notice Address of the game factory that created this instance
    address public factory;

    /// @notice Timestamp when the game was created
    uint256 public createdAt;

    /// @notice Timestamp when the game ended (if applicable)
    uint256 public endedAt;

    // ==================== Player Information ====================
    /// @notice Address of the first player
    address public player1;

    /// @notice Address of the second player
    address public player2;

    /// @notice Address of the player whose turn it is
    address public currentTurn;

    /// @notice Address of the game winner (if game complete)
    address public winner;

    // ==================== Game State ====================
    /// @notice Current state of the game
    GameState public state;

    /// @notice Commitment to player1's board placement (verified by ZK)
    bytes32 public player1BoardCommitment;

    /// @notice Commitment to player2's board placement (verified by ZK)
    bytes32 public player2BoardCommitment;

    /// @notice ZK Verifier contract address for proof validation
    address public zkVerifier;

    // ==================== Timeout Handling ====================
    /// @notice Maximum time allowed for a move before timeout (in seconds)
    uint256 public moveTimeout;

    /// @notice Timestamp of last action in the game
    uint256 public lastActionTime;

    // ==================== Storage Gap ====================
    /// @notice Gap for future storage variables in upgrades
    uint256[50] private __gap;

    // ==================== Events ====================
    /// @notice Emitted when a player submits their board
    event BoardSubmitted(address indexed player, bytes32 commitment);

    /// @notice Emitted when a player makes a shot
    event ShotFired(address indexed shooter, uint8 x, uint8 y);

    /// @notice Emitted when a shot result is submitted
    event ShotResult(address indexed target, uint8 x, uint8 y, bool hit);

    /// @notice Emitted when the game state changes
    event GameStateChanged(GameState newState);

    /// @notice Emitted when the game completes
    event GameCompleted(address indexed winner, uint256 endTime);

    /// @notice Emitted when a player claims their reward
    event RewardClaimed(address indexed player, bool isWinner);

    // ==================== Errors ====================
    error InvalidPlayer();
    error InvalidGameState();
    error InvalidTurn();
    error InvalidProof();
    error InvalidCoordinates();
    error AlreadyShot();
    error GameNotComplete();
    error RewardAlreadyClaimed();
    error Unauthorized();
    error Timeout();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializer function (replaces constructor in upgradeable contracts)
     * @param _gameId Unique identifier for this game instance
     * @param _player1 Address of the first player
     * @param _player2 Address of the second player
     * @param _factory Address of the factory contract
     * @param _zkVerifier Address of the ZK verifier contract
     */
    function initialize(
        uint256 _gameId,
        address _player1,
        address _player2,
        address _factory,
        address _zkVerifier
    )
        public
        initializer
    {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();

        // Set game metadata
        gameId = _gameId;
        player1 = _player1;
        player2 = _player2;
        factory = _factory;
        zkVerifier = _zkVerifier;

        // Initialize timestamps
        createdAt = block.timestamp;
        lastActionTime = block.timestamp;

        // Set game state
        state = GameState.Created;

        // Set timeout (24 hours by default)
        moveTimeout = 24 hours;

        // Initialize gameState struct
        gameState.player1 = _player1;
        gameState.player2 = _player2;
        gameState.gameState = uint8(GameState.Created);

        // Grant factory the ability to manage this game
        _grantRole(DEFAULT_ADMIN_ROLE, _factory);
        _grantRole(FACTORY_ROLE, _factory);

        emit GameStateChanged(GameState.Created);
    }

    /**
     * @notice Modifier to ensure caller is a player in the game
     */
    modifier onlyPlayer() {
        if (msg.sender != player1 && msg.sender != player2) {
            revert InvalidPlayer();
        }
        _;
    }

    /**
     * @notice Modifier to ensure the game is in the appropriate state
     * @param _state The required game state
     */
    modifier inState(GameState _state) {
        if (state != _state) {
            revert InvalidGameState();
        }
        _;
    }

    /**
     * @notice Modifier to ensure it's the caller's turn
     */
    modifier onlyCurrentTurn() {
        if (msg.sender != currentTurn) {
            revert InvalidTurn();
        }
        _;
    }

    /**
     * @notice Checks if the game has timed out and can be claimed by the opponent
     */
    modifier checkTimeout() {
        if (state == GameState.Active && block.timestamp > lastActionTime + moveTimeout) {
            // If timed out, the player making the call wins
            _completeGame(msg.sender);
        }
        _;
    }

    /**
     * @notice Submit board placement with ZK proof
     * @param boardCommitment Commitment to board state (ships placement)
     * @param zkProof ZK proof verifying valid board configuration
     */
    function submitBoard(bytes32 boardCommitment, bytes calldata zkProof) external onlyPlayer checkTimeout {
        // Check current game state
        if (state == GameState.Completed || state == GameState.Cancelled) {
            revert InvalidGameState();
        }

        // Verify the board placement proof
        bool isValid = _verifyBoardPlacement(boardCommitment, zkProof);
        if (!isValid) {
            revert InvalidProof();
        }

        // Store the commitment based on which player is submitting
        if (msg.sender == player1) {
            require(player1BoardCommitment == bytes32(0), "Board already submitted");
            player1BoardCommitment = boardCommitment;
        } else {
            require(player2BoardCommitment == bytes32(0), "Board already submitted");
            player2BoardCommitment = boardCommitment;
        }

        // Store board in optimized storage
        gameState.storeBoard(msg.sender, boardCommitment);

        emit BoardSubmitted(msg.sender, boardCommitment);

        // Update game state if needed
        _updateGameState();
    }

    /**
     * @notice Make a shot at target coordinates
     * @param x X-coordinate (0-9)
     * @param y Y-coordinate (0-9)
     */
    function makeShot(uint8 x, uint8 y) external onlyPlayer inState(GameState.Active) onlyCurrentTurn checkTimeout {
        // Validate coordinates
        if (x >= BOARD_SIZE || y >= BOARD_SIZE) {
            revert InvalidCoordinates();
        }

        // Get target player
        address target = (msg.sender == player1) ? player2 : player1;

        // Use GameStorage to check and record shot
        bool success = gameState.recordShot(msg.sender, target, x, y);
        if (!success) {
            revert AlreadyShot();
        }

        // Update last action time
        lastActionTime = block.timestamp;

        // Emit shot event
        emit ShotFired(msg.sender, x, y);
    }

    /**
     * @notice Submit result of a shot with ZK proof
     * @param x X-coordinate of the shot
     * @param y Y-coordinate of the shot
     * @param isHit Whether the shot hit a ship
     * @param zkProof ZK proof verifying shot result
     */
    function submitShotResult(
        uint8 x,
        uint8 y,
        bool isHit,
        bytes calldata zkProof
    )
        external
        onlyPlayer
        inState(GameState.Active)
        checkTimeout
    {
        // Ensure responder is not the shooter but the target
        address shooter = currentTurn;
        address target = msg.sender;

        if (shooter == target) {
            revert InvalidPlayer();
        }

        // Get the board commitment of the target
        bytes32 boardCommitment = target == player1 ? player1BoardCommitment : player2BoardCommitment;

        // Verify the shot result with ZK proof
        bool isValid = _verifyShotResult(boardCommitment, x, y, isHit, zkProof);
        if (!isValid) {
            revert InvalidProof();
        }

        // If it's a hit, record it and check for game over
        bool gameOver = false;
        if (isHit) {
            gameOver = gameState.recordHit(target, x, y);
        }

        // Update last action time
        lastActionTime = block.timestamp;

        // Check for win condition
        if (gameOver) {
            _completeGame(shooter);
            emit ShotResult(target, x, y, isHit);
            return;
        }

        // Swap turns
        currentTurn = target;
        gameState.currentTurn = target;

        // Emit result event
        emit ShotResult(target, x, y, isHit);
    }

    /**
     * @notice Verify game ending with ZK proof (all ships are sunk)
     * @param boardCommitment Board commitment of the losing player
     * @param zkProof ZK proof that all ships are sunk
     */
    function verifyGameEnd(
        bytes32 boardCommitment,
        bytes calldata zkProof
    )
        external
        onlyPlayer
        inState(GameState.Active)
        checkTimeout
    {
        // Get the opponent's address
        address opponent = msg.sender == player1 ? player2 : player1;

        // Ensure the provided board commitment matches the opponent's
        bytes32 expectedCommitment = opponent == player1 ? player1BoardCommitment : player2BoardCommitment;

        if (boardCommitment != expectedCommitment) {
            revert InvalidProof();
        }

        // Generate shot history hash for verification
        bytes32 shotHistoryHash = gameState.getShotHistoryHash(msg.sender);

        // Verify the game end proof
        bool isValid = IZKVerifier(zkVerifier).verifyGameEnd(boardCommitment, shotHistoryHash, zkProof);

        if (!isValid) {
            revert InvalidProof();
        }

        // Check if all ships are sunk using GameStorage
        bool allSunk = gameState.checkAllShipsSunk(opponent);
        if (!allSunk) {
            revert InvalidProof();
        }

        // Complete the game with the caller as winner
        _completeGame(msg.sender);
    }

    /**
     * @notice Forfeit the game (surrender)
     */
    function forfeit() external onlyPlayer checkTimeout {
        // Game must be in progress (not completed or cancelled)
        if (state == GameState.Completed || state == GameState.Cancelled) {
            revert InvalidGameState();
        }

        // Determine winner (the other player)
        address gameWinner = msg.sender == player1 ? player2 : player1;

        // Complete the game with the determined winner
        _completeGame(gameWinner);
    }

    /**
     * @notice Claim timeout win if opponent hasn't played
     */
    function claimTimeoutWin() external onlyPlayer inState(GameState.Active) {
        // Check if enough time has passed since last action
        if (block.timestamp <= lastActionTime + moveTimeout) {
            revert Timeout();
        }

        // The current turn player has timed out, so other player wins
        address timeoutWinner = msg.sender;

        // Complete the game with timeout winner
        _completeGame(timeoutWinner);
    }

    /**
     * @notice Claim reward after game completion
     * This would typically call to a token contract for rewards
     */
    function claimReward() external onlyPlayer inState(GameState.Completed) {
        // For now we just emit an event - in a real implementation
        // this would call to a token contract
        bool isWinner = msg.sender == winner;

        emit RewardClaimed(msg.sender, isWinner);
    }

    /**
     * @notice Cancel a game that hasn't started active play
     */
    function cancelGame() external {
        // Only factory or players can cancel
        if (!hasRole(FACTORY_ROLE, msg.sender) && msg.sender != player1 && msg.sender != player2) {
            revert Unauthorized();
        }

        // Only cancel if not already active or completed
        if (state == GameState.Active || state == GameState.Completed) {
            revert InvalidGameState();
        }

        // Update state
        state = GameState.Cancelled;
        gameState.gameState = uint8(GameState.Cancelled);
        endedAt = block.timestamp;

        emit GameStateChanged(GameState.Cancelled);
    }

    /**
     * @notice Pause the game (admin only)
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the game (admin only)
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Set a new timeout duration for moves (admin only)
     * @param newTimeout New timeout duration in seconds
     */
    function setMoveTimeout(uint256 newTimeout) external onlyRole(DEFAULT_ADMIN_ROLE) {
        moveTimeout = newTimeout;
    }

    /**
     * @notice Check if a coordinate has been shot
     * @param player Address of the player who made the shot
     * @param x X-coordinate
     * @param y Y-coordinate
     * @return Whether the position has been shot
     */
    function hasShot(address player, uint8 x, uint8 y) external view returns (bool) {
        // Get target player (shots are recorded on the target's board)
        address target = (player == player1) ? player2 : player1;
        return gameState.isShot(target, x, y);
    }

    /**
     * @notice Check if a coordinate has been hit
     * @param player Address of the player who scored the hit
     * @param x X-coordinate
     * @param y Y-coordinate
     * @return Whether the position has been hit
     */
    function hasHit(address player, uint8 x, uint8 y) external view returns (bool) {
        // Get target player (hits are recorded on the target's board)
        address target = (player == player1) ? player2 : player1;
        return gameState.isHit(target, x, y);
    }

    /**
     * @notice Get hit count for a player
     * @param player Address of the player
     * @return Number of hits scored
     */
    function getHitCount(address player) external view returns (uint8) {
        // Get target player (hits are recorded on the target's board)
        address target = (player == player1) ? player2 : player1;
        return gameState.boards[target].hitsReceived;
    }

    /**
     * @notice Update game state based on current conditions
     * @dev Internal function to transition game state when needed
     */
    function _updateGameState() internal {
        // If both players have submitted boards, start the game
        if (player1BoardCommitment != bytes32(0) && player2BoardCommitment != bytes32(0) && state != GameState.Active) {
            state = GameState.Active;
            gameState.gameState = uint8(GameState.Active);

            // Set initial turn (player1 starts)
            currentTurn = player1;
            gameState.currentTurn = player1;

            // Update timestamp
            lastActionTime = block.timestamp;

            emit GameStateChanged(GameState.Active);
        }
        // If one player submitted but not both, move to Setup state
        else if (
            (player1BoardCommitment != bytes32(0) || player2BoardCommitment != bytes32(0)) && state == GameState.Created
        ) {
            state = GameState.Setup;
            gameState.gameState = uint8(GameState.Setup);
            emit GameStateChanged(GameState.Setup);
        }
    }

    /**
     * @notice Complete the game with specified winner
     * @param gameWinner Address of the winner
     */
    function _completeGame(address gameWinner) internal {
        // Update game state
        state = GameState.Completed;
        gameState.gameState = uint8(GameState.Completed);
        winner = gameWinner;
        gameState.winner = gameWinner;
        endedAt = block.timestamp;

        // Emit events
        emit GameCompleted(gameWinner, endedAt);
        emit GameStateChanged(GameState.Completed);
    }

    /**
     * @notice Verify board placement is valid using ZK proof
     * @param boardCommitment Commitment to board state
     * @param proof ZK proof of valid board
     * @return True if valid, false otherwise
     */
    function _verifyBoardPlacement(bytes32 boardCommitment, bytes calldata proof) internal view returns (bool) {
        // Call to the ZKVerifier contract
        return IZKVerifier(zkVerifier).verifyBoardPlacement(boardCommitment, proof);
    }

    /**
     * @notice Verify shot result is valid using ZK proof
     * @param boardCommitment Commitment to board state
     * @param x X-coordinate
     * @param y Y-coordinate
     * @param claimedHit Whether the shot is claimed as a hit
     * @param proof ZK proof of valid result
     * @return True if valid, false otherwise
     */
    function _verifyShotResult(
        bytes32 boardCommitment,
        uint8 x,
        uint8 y,
        bool claimedHit,
        bytes calldata proof
    )
        internal
        view
        returns (bool)
    {
        // Call to the ZKVerifier contract
        return IZKVerifier(zkVerifier).verifyShotResult(boardCommitment, x, y, claimedHit, proof);
    }

    /**
     * @notice UUPS upgrade authorization
     * @param newImplementation Address of new implementation
     * @dev Only the factory can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        // Additional validation can be added here if needed
    }
}
