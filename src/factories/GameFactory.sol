// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "../proxies/BattleShipGameProxy.sol";
import "../BattleshipGameImplementation.sol";

/**
 * @title GameFactory
 * @notice Creates and manages ZK Battleship game instances
 */
contract GameFactory is AccessControl {
    // ==================== Roles ====================
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ==================== State Variables ====================
    // Mapping from game ID to game proxy address
    mapping(uint256 => address) public games;

    // Mapping from player address to active game IDs
    mapping(address => uint256[]) public playerGames;

    // Game ID counter for unique identifiers
    uint256 private nextGameId;

    // Current implementation address
    address public currentImplementation;

    // ZK Verifier address
    address public zkVerifier;

    // SHIPToken address (for rewards)
    address public shipToken;

    // ==================== Events ====================
    event GameCreated(uint256 indexed gameId, address indexed gameAddress, address player1, address player2);
    event ImplementationUpdated(address indexed oldImplementation, address indexed newImplementation);
    event GameJoined(uint256 indexed gameId, address indexed player);
    event GameCancelled(uint256 indexed gameId);

    // ==================== Constructor ====================
    /**
     * @notice Constructor sets up initial roles and addresses
     * @param _implementation Address of the initial game implementation
     * @param _zkVerifier Address of the ZK verifier contract
     */
    constructor(address _implementation, address _zkVerifier) {
        // Setup admin role
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);

        // Set initial addresses
        currentImplementation = _implementation;
        zkVerifier = _zkVerifier;

        // Start game ID counter
        nextGameId = 1;
    }

    /**
     * @notice Create a new game
     * @param opponent Address of the opponent player
     * @return gameId Unique identifier for the created game
     */
    function createGame(address opponent) external returns (uint256 gameId) {
        // Ensure opponent is not the sender
        require(opponent != msg.sender, "Cannot play against yourself");
        require(opponent != address(0), "Invalid opponent address");

        // Get new game ID
        gameId = nextGameId++;

        // Generate initialization data for the proxy
        bytes memory initData = abi.encodeWithSelector(
            BattleshipGameImplementation.initialize.selector,
            gameId,
            msg.sender, // player1
            opponent, // player2
            address(this), // factory
            zkVerifier // ZK verifier
        );

        // Deploy new proxy contract
        BattleshipGameProxy proxy = new BattleshipGameProxy(currentImplementation, initData);

        // Store game address
        address gameAddress = address(proxy);
        games[gameId] = gameAddress;

        // Add game to creator's active games
        playerGames[msg.sender].push(gameId);

        // Emit event
        emit GameCreated(gameId, gameAddress, msg.sender, opponent);

        return gameId;
    }

    /**
     * @notice Join an existing game
     * @param gameId ID of the game to join
     */
    function joinGame(uint256 gameId) external {
        // Get game address
        address gameAddress = games[gameId];
        require(gameAddress != address(0), "Game does not exist");

        // Check if sender is player2
        BattleshipGameImplementation game = BattleshipGameImplementation(gameAddress);
        require(game.player2() == msg.sender, "Not authorized to join this game");

        // Add game to player's active games
        playerGames[msg.sender].push(gameId);

        emit GameJoined(gameId, msg.sender);
    }

    /**
     * @notice Set new implementation address (for upgrades)
     * @param newImplementation Address of the new implementation contract
     */
    function setImplementation(address newImplementation) external onlyRole(UPGRADER_ROLE) {
        require(newImplementation != address(0), "Invalid implementation address");

        address oldImplementation = currentImplementation;
        currentImplementation = newImplementation;

        emit ImplementationUpdated(oldImplementation, newImplementation);
    }

    /**
     * @notice Cancel a game that hasn't started
     * @param gameId ID of the game to cancel
     */
    function cancelGame(uint256 gameId) external {
        // Get game address
        address gameAddress = games[gameId];
        require(gameAddress != address(0), "Game does not exist");

        // Get game contract instance
        BattleshipGameImplementation game = BattleshipGameImplementation(gameAddress);

        // Check that caller is a player
        require(game.player1() == msg.sender || game.player2() == msg.sender, "Not a player in this game");

        // Cancel the game (game contract will check state)
        game.cancelGame();

        // Emit event
        emit GameCancelled(gameId);
    }

    /**
     * @notice Get list of active games for a player
     * @param player Address of the player
     * @return List of game IDs
     */
    function getPlayerGames(address player) external view returns (uint256[] memory) {
        return playerGames[player];
    }

    /**
     * @notice Set the SHIPToken address (for rewards)
     * @param _shipToken Address of the token contract
     */
    function setShipToken(address _shipToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_shipToken != address(0), "Invalid token address");
        shipToken = _shipToken;
    }

    /**
     * @notice Set the ZK verifier address
     * @param _zkVerifier Address of the verifier contract
     */
    function setZKVerifier(address _zkVerifier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_zkVerifier != address(0), "Invalid verifier address");
        zkVerifier = _zkVerifier;
    }
}
