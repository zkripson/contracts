// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title BattleshipGameImplementation
 * @dev  game logic for backend-driven ZK Battleship
 * @notice This implementation only stores game metadata and results
 */
contract BattleshipGameImplementation is Initializable, UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable {
    // ==================== Version Tracking ====================
    string public constant VERSION = "2.0.0";

    // ==================== Role Definition ====================
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");
    bytes32 public constant BACKEND_ROLE = keccak256("BACKEND_ROLE");

    // ==================== Game State Enum ====================
    enum GameState {
        Created, // Game created, waiting for backend
        Active, // Game is being played (backend handles gameplay)
        Completed, // Game completed with a winner
        Cancelled // Game cancelled
    }

    // ==================== Structs ====================
    struct GameResult {
        address winner;
        uint256 startTime;
        uint256 endTime;
        uint256 totalShots;
        string endReason; // "completed", "forfeit", "timeout", "time_limit"
    }

    // ==================== Storage ====================
    uint256 public gameId;
    address public factory;
    address public player1;
    address public player2;
    address public backend;

    GameState public state;
    uint256 public createdAt;
    GameResult public gameResult;

    // ==================== Storage Gap ====================
    uint256[50] private __gap;

    // ==================== Events ====================
    event GameStarted(uint256 indexed gameId, uint256 startTime);
    event GameCompleted(
        uint256 indexed gameId,
        address indexed winner,
        uint256 endTime,
        uint256 totalShots,
        string endReason
    );
    event GameCancelled(uint256 indexed gameId);
    event BackendUpdated(address indexed oldBackend, address indexed newBackend);

    // ==================== Errors ====================
    error NotBackend();
    error InvalidGameState();
    error GameAlreadyCompleted();
    error InvalidPlayer();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the game contract
     * @param _gameId Unique identifier for this game
     * @param _player1 Address of first player
     * @param _player2 Address of second player
     * @param _factory Address of the factory contract
     * @param _backend Address authorized to submit game results
     */
    function initialize(
        uint256 _gameId,
        address _player1,
        address _player2,
        address _factory,
        address _backend
    ) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();

        gameId = _gameId;
        player1 = _player1;
        player2 = _player2;
        factory = _factory;
        backend = _backend;

        state = GameState.Created;
        createdAt = block.timestamp;

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, _factory);
        _grantRole(FACTORY_ROLE, _factory);
        _grantRole(BACKEND_ROLE, _backend);
    }

    /**
     * @notice Start the game (called by backend when game begins)
     */
    function startGame() external onlyRole(BACKEND_ROLE) {
        if (state != GameState.Created) revert InvalidGameState();

        state = GameState.Active;
        gameResult.startTime = block.timestamp;

        emit GameStarted(gameId, block.timestamp);
    }

    /**
     * @notice Submit game result (called by backend when game ends)
     * @param winner Address of the winning player (address(0) for draw)
     * @param totalShots Number of shots taken in the game
     * @param endReason Reason for game ending
     */
    function submitGameResult(
        address winner,
        uint256 totalShots,
        string memory endReason
    ) external onlyRole(BACKEND_ROLE) {
        if (state != GameState.Active) revert InvalidGameState();
        if (winner != address(0) && winner != player1 && winner != player2) {
            revert InvalidPlayer();
        }

        // Store game result
        gameResult.winner = winner;
        gameResult.endTime = block.timestamp;
        gameResult.totalShots = totalShots;
        gameResult.endReason = endReason;

        state = GameState.Completed;

        emit GameCompleted(gameId, winner, block.timestamp, totalShots, endReason);
    }

    /**
     * @notice Cancel the game (can be called by factory or backend)
     */
    function cancelGame() external {
        if (!hasRole(FACTORY_ROLE, msg.sender) && !hasRole(BACKEND_ROLE, msg.sender)) {
            revert NotBackend();
        }

        if (state == GameState.Completed) revert GameAlreadyCompleted();

        state = GameState.Cancelled;

        emit GameCancelled(gameId);
    }

    /**
     * @notice Update backend address (admin only)
     * @param newBackend New backend address
     */
    function updateBackend(address newBackend) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldBackend = backend;

        // Revoke role from old backend
        _revokeRole(BACKEND_ROLE, oldBackend);

        // Grant role to new backend
        _grantRole(BACKEND_ROLE, newBackend);

        backend = newBackend;

        emit BackendUpdated(oldBackend, newBackend);
    }

    /**
     * @notice Get game duration in seconds
     * @return duration Game duration (0 if not completed)
     */
    function getGameDuration() external view returns (uint256 duration) {
        if (gameResult.startTime == 0 || gameResult.endTime == 0) {
            return 0;
        }
        return gameResult.endTime - gameResult.startTime;
    }

    /**
     * @notice Check if player participated in this game
     * @param player Address to check
     * @return participated True if player participated
     */
    function isPlayer(address player) external view returns (bool participated) {
        return player == player1 || player == player2;
    }

    /**
     * @notice Get game information
     * @return gameId Game ID
     * @return player1 Address of player 1
     * @return player2 Address of player 2
     * @return state Current game state
     * @return createdAt Timestamp when game was created
     * @return gameResult Game result struct
     */
    function getGameInfo()
        external
        view
        returns (
            uint256 gameId,
            address player1,
            address player2,
            GameState state,
            uint256 createdAt,
            GameResult memory gameResult
        )
    {
        return (gameId, player1, player2, state, createdAt, gameResult);
    }

    /**
     * @notice Pause the contract (admin only)
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract (admin only)
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice UUPS upgrade authorization
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        // Additional validation can be added here if needed
    }
}
