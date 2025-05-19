// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../proxies/BattleShipGameProxy.sol";
import "../BattleshipGameImplementation.sol";
import "../ShipToken.sol";
import "../BattleshipStatistics.sol";
import "../BattleshipPoints.sol";

/**
 * @title GameFactoryWithStats
 * @notice Creates and manages ZK Battleship games with comprehensive statistics
 */
contract GameFactoryWithStats is AccessControl, Pausable {
    // ==================== Roles ====================
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant BACKEND_ROLE = keccak256("BACKEND_ROLE");
    bytes32 public constant STATS_ROLE = keccak256("STATS_ROLE");

    // ==================== Structs ====================
    struct PlayerStats {
        uint256 totalGames;
        uint256 wins;
        uint256 losses;
        uint256 winStreak;
        uint256 bestWinStreak;
        uint256 totalShipsDestroyed;
        uint256 totalGameDuration;
        uint256 totalRewardsEarned;
        uint256 firstGameTime;
        uint256 lastGameTime;
    }

    struct GameStats {
        uint256 totalGames;
        uint256 completedGames;
        uint256 cancelledGames;
        uint256 totalPlayTime;
        uint256 averageGameDuration;
        uint256 totalShotsAcrossGames;
        mapping(string => uint256) endReasonCounts;
    }

    struct LeaderboardEntry {
        address player;
        uint256 wins;
        uint256 winRate; // Percentage (0-10000, where 10000 = 100%)
        uint256 currentStreak;
        uint256 bestStreak;
    }

    // ==================== State Variables ====================
    mapping(uint256 => address) public games;
    mapping(address => uint256[]) public playerGames;
    mapping(address => PlayerStats) public playerStats;

    uint256 private nextGameId;
    address public currentImplementation;
    address public backend;
    SHIPToken public shipToken;
    BattleshipStatistics public statistics;
    BattleshipPoints public pointsContract;

    GameStats public gameStats;

    // Leaderboard tracking
    address[] private leaderboardPlayers;
    mapping(address => bool) private isInLeaderboard;

    // Points constants
    uint256 public constant PARTICIPATION_POINTS = 50;
    uint256 public constant VICTORY_POINTS = 100;
    uint256 public constant DRAW_POINTS = 25;

    // ==================== Events ====================
    event GameCreated(uint256 indexed gameId, address indexed gameAddress, address indexed player1, address player2);
    event GameCompleted(uint256 indexed gameId, address indexed winner, uint256 duration, uint256 shots);
    event ImplementationUpdated(address indexed oldImplementation, address indexed newImplementation);
    event BackendUpdated(address indexed oldBackend, address indexed newBackend);
    event RewardsDistributed(uint256 indexed gameId, address indexed player, uint256 amount, bool isWinner);
    event StatsUpdated(address indexed player);

    // ==================== Errors ====================
    error InvalidImplementation();
    error InvalidBackend();
    error GameNotFound();
    error UnauthorizedCaller();
    error NoGames();

    // ==================== Constructor ====================
    constructor(address _implementation, address _backend, address _shipToken, address _statistics, address _pointsContract) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(BACKEND_ROLE, _backend);

        currentImplementation = _implementation;
        backend = _backend;
        shipToken = SHIPToken(_shipToken);
        statistics = BattleshipStatistics(_statistics);
        pointsContract = BattleshipPoints(_pointsContract);

        nextGameId = 1;
    }

    // ==================== Game Management ====================

    /**
     * @notice Create a new game
     * @param player1 Address of first player
     * @param player2 Address of second player
     * @return gameId Unique identifier for the created game
     */
    function createGame(
        address player1,
        address player2
    ) external onlyRole(BACKEND_ROLE) whenNotPaused returns (uint256 gameId) {
        require(player1 != player2, "Cannot play against yourself");
        require(player1 != address(0) && player2 != address(0), "Invalid player address");

        gameId = nextGameId++;

        // Generate initialization data for the proxy
        bytes memory initData = abi.encodeWithSelector(
            BattleshipGameImplementation.initialize.selector,
            gameId,
            player1,
            player2,
            address(this),
            backend
        );

        // Deploy new proxy contract
        BattleshipGameProxy proxy = new BattleshipGameProxy(currentImplementation, initData);
        address gameAddress = address(proxy);

        // Store game mapping
        games[gameId] = gameAddress;

        // Add to player's game lists
        playerGames[player1].push(gameId);
        playerGames[player2].push(gameId);

        // Initialize player stats if first game
        if (playerStats[player1].firstGameTime == 0) {
            playerStats[player1].firstGameTime = block.timestamp;
            _addToLeaderboard(player1);
        }
        if (playerStats[player2].firstGameTime == 0) {
            playerStats[player2].firstGameTime = block.timestamp;
            _addToLeaderboard(player2);
        }

        // Update total games counter
        gameStats.totalGames++;

        emit GameCreated(gameId, gameAddress, player1, player2);
        return gameId;
    }

    /**
     * @notice Report game completion and update statistics
     * @param gameId ID of the completed game
     * @param winner Address of the winner (address(0) for draw)
     * @param duration Game duration in seconds
     * @param shots Total shots taken
     * @param endReason How the game ended
     */
    function reportGameCompletion(
        uint256 gameId,
        address winner,
        uint256 duration,
        uint256 shots,
        string memory endReason
    ) external onlyRole(BACKEND_ROLE) {
        address gameAddress = games[gameId];
        if (gameAddress == address(0)) revert GameNotFound();

        BattleshipGameImplementation game = BattleshipGameImplementation(gameAddress);
        address player1 = game.player1();
        address player2 = game.player2();

        // Update game statistics
        gameStats.completedGames++;
        gameStats.totalPlayTime += duration;
        gameStats.totalShotsAcrossGames += shots;
        gameStats.averageGameDuration = gameStats.totalPlayTime / gameStats.completedGames;
        gameStats.endReasonCounts[endReason]++;

        // Update player statistics
        _updatePlayerStats(player1, player2, winner, duration);

        // Distribute rewards
        uint256 player1Rewards = 0;
        uint256 player2Rewards = 0;
        (player1Rewards, player2Rewards) = _distributeRewards(gameId, player1, player2, winner);

        // Update comprehensive statistics in BattleshipStatistics contract
        if (winner == address(0)) {
            // Draw case
            statistics.recordDraw(player1, player2, duration, shots, endReason);
        } else {
            // Winner case - update both players
            statistics.recordGameResult(
                player1,
                winner == player1,
                gameId,
                duration,
                shots / 2, // Approximate shots for each player
                endReason,
                player1Rewards
            );

            statistics.recordGameResult(
                player2,
                winner == player2,
                gameId,
                duration,
                shots / 2, // Approximate shots for each player
                endReason,
                player2Rewards
            );
        }

        emit GameCompleted(gameId, winner, duration, shots);
    }

    /**
     * @notice Cancel a game and update statistics
     * @param gameId ID of the game to cancel
     */
    function cancelGame(uint256 gameId) external onlyRole(BACKEND_ROLE) {
        address gameAddress = games[gameId];
        if (gameAddress == address(0)) revert GameNotFound();

        BattleshipGameImplementation game = BattleshipGameImplementation(gameAddress);
        address player1 = game.player1();
        address player2 = game.player2();

        game.cancelGame();

        gameStats.cancelledGames++;

        // Update comprehensive statistics in BattleshipStatistics
        // Record as a draw with "cancelled" as the end reason
        statistics.recordDraw(
            player1,
            player2,
            0, // Duration is 0 since game was cancelled
            0, // No shots taken
            "cancelled"
        );
    }

    // ==================== Statistics ====================

    /**
     * @notice Get player statistics
     * @param player Address of the player
     * @return stats Player statistics struct
     */
    function getPlayerStats(address player) external view returns (PlayerStats memory stats) {
        return playerStats[player];
    }

    /**
     * @notice Get overall game statistics
     * @return totalGames Total number of games created
     * @return completedGames Number of completed games
     * @return cancelledGames Number of cancelled games
     * @return averageDuration Average game duration
     * @return totalShots Total shots across all games
     */
    function getGameStats()
        external
        view
        returns (
            uint256 totalGames,
            uint256 completedGames,
            uint256 cancelledGames,
            uint256 averageDuration,
            uint256 totalShots
        )
    {
        return (
            gameStats.totalGames,
            gameStats.completedGames,
            gameStats.cancelledGames,
            gameStats.averageGameDuration,
            gameStats.totalShotsAcrossGames
        );
    }

    /**
     * @notice Get leaderboard of top players
     * @param limit Maximum number of entries to return
     * @return entries Array of leaderboard entries
     */
    function getLeaderboard(uint256 limit) external view returns (LeaderboardEntry[] memory entries) {
        uint256 totalPlayers = leaderboardPlayers.length;
        uint256 returnCount = limit > totalPlayers ? totalPlayers : limit;

        entries = new LeaderboardEntry[](returnCount);

        // Create a sorted list of entries
        LeaderboardEntry[] memory tempEntries = new LeaderboardEntry[](totalPlayers);

        // Fill temp array
        for (uint256 i = 0; i < totalPlayers; i++) {
            address player = leaderboardPlayers[i];
            PlayerStats memory stats = playerStats[player];

            tempEntries[i] = LeaderboardEntry({
                player: player,
                wins: stats.wins,
                winRate: stats.totalGames > 0 ? (stats.wins * 10_000) / stats.totalGames : 0,
                currentStreak: stats.winStreak,
                bestStreak: stats.bestWinStreak
            });
        }

        // Simple bubble sort by wins (could be optimized)
        for (uint256 i = 0; i < totalPlayers - 1; i++) {
            for (uint256 j = 0; j < totalPlayers - i - 1; j++) {
                if (tempEntries[j].wins < tempEntries[j + 1].wins) {
                    LeaderboardEntry memory temp = tempEntries[j];
                    tempEntries[j] = tempEntries[j + 1];
                    tempEntries[j + 1] = temp;
                }
            }
        }

        // Copy top entries
        for (uint256 i = 0; i < returnCount; i++) {
            entries[i] = tempEntries[i];
        }

        return entries;
    }

    /**
     * @notice Get player's game history
     * @param player Address of the player
     * @return gameIds Array of game IDs the player participated in
     */
    function getPlayerGames(address player) external view returns (uint256[] memory gameIds) {
        return playerGames[player];
    }

    // ==================== Admin Functions ====================

    /**
     * @notice Set new implementation address
     * @param newImplementation Address of the new implementation
     */
    function setImplementation(address newImplementation) external onlyRole(UPGRADER_ROLE) {
        if (newImplementation == address(0)) revert InvalidImplementation();

        address oldImplementation = currentImplementation;
        currentImplementation = newImplementation;

        emit ImplementationUpdated(oldImplementation, newImplementation);
    }

    /**
     * @notice Update backend address
     * @param newBackend New backend address
     */
    function setBackend(address newBackend) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newBackend == address(0)) revert InvalidBackend();

        address oldBackend = backend;

        // Update role
        _revokeRole(BACKEND_ROLE, oldBackend);
        _grantRole(BACKEND_ROLE, newBackend);

        backend = newBackend;

        emit BackendUpdated(oldBackend, newBackend);
    }

    /**
     * @notice Set SHIPToken address
     * @param _shipToken Address of the token contract
     */
    function setShipToken(address _shipToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_shipToken != address(0), "Invalid token address");
        shipToken = SHIPToken(_shipToken);
    }

    /**
     * @notice Set BattleshipStatistics address
     * @param _statistics Address of the statistics contract
     */
    function setStatistics(address _statistics) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_statistics != address(0), "Invalid statistics address");
        statistics = BattleshipStatistics(_statistics);
    }

    /**
     * @notice Set BattleshipPoints address
     * @param _pointsContract Address of the points contract
     */
    function setPointsContract(address _pointsContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_pointsContract != address(0), "Invalid points contract address");
        pointsContract = BattleshipPoints(_pointsContract);
    }

    /**
     * @notice Pause the factory
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the factory
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ==================== Internal Functions ====================

    /**
     * @notice Update player statistics after a game
     * @param player1 First player address
     * @param player2 Second player address
     * @param winner Winner address (address(0) for draw)
     * @param duration Game duration
     */
    function _updatePlayerStats(address player1, address player2, address winner, uint256 duration) internal {
        // Update both players' game counts and duration
        playerStats[player1].totalGames++;
        playerStats[player1].totalGameDuration += duration;
        playerStats[player1].lastGameTime = block.timestamp;

        playerStats[player2].totalGames++;
        playerStats[player2].totalGameDuration += duration;
        playerStats[player2].lastGameTime = block.timestamp;

        // Handle win/loss and streaks
        if (winner == address(0)) {
            // Draw - reset both streaks
            playerStats[player1].winStreak = 0;
            playerStats[player2].winStreak = 0;
        } else if (winner == player1) {
            // Player1 wins
            playerStats[player1].wins++;
            playerStats[player1].winStreak++;
            if (playerStats[player1].winStreak > playerStats[player1].bestWinStreak) {
                playerStats[player1].bestWinStreak = playerStats[player1].winStreak;
            }

            playerStats[player2].losses++;
            playerStats[player2].winStreak = 0;
        } else {
            // Player2 wins
            playerStats[player2].wins++;
            playerStats[player2].winStreak++;
            if (playerStats[player2].winStreak > playerStats[player2].bestWinStreak) {
                playerStats[player2].bestWinStreak = playerStats[player2].winStreak;
            }

            playerStats[player1].losses++;
            playerStats[player1].winStreak = 0;
        }

        emit StatsUpdated(player1);
        emit StatsUpdated(player2);
    }

    /**
     * @notice Distribute rewards to players
     * @param gameId Game ID
     * @param player1 First player
     * @param player2 Second player
     * @param winner Winner (address(0) for draw)
     * @return player1Reward Amount rewarded to player1
     * @return player2Reward Amount rewarded to player2
     */
    function _distributeRewards(
        uint256 gameId,
        address player1,
        address player2,
        address winner
    ) internal returns (uint256 player1Reward, uint256 player2Reward) {
        // Convert gameId to bytes32 for points contract
        bytes32 gameIdBytes = bytes32(gameId);
        
        // Award points based on game outcome
        if (winner == address(0)) {
            // Draw case - both players get draw points
            player1Reward = DRAW_POINTS;
            player2Reward = DRAW_POINTS;
            
            pointsContract.awardPoints(player1, DRAW_POINTS, "GAME_DRAW", gameIdBytes);
            pointsContract.awardPoints(player2, DRAW_POINTS, "GAME_DRAW", gameIdBytes);
        } else {
            // Victory case
            if (winner == player1) {
                player1Reward = PARTICIPATION_POINTS + VICTORY_POINTS;
                player2Reward = PARTICIPATION_POINTS;
                
                pointsContract.awardPoints(player1, VICTORY_POINTS, "GAME_WIN", gameIdBytes);
                pointsContract.awardPoints(player1, PARTICIPATION_POINTS, "GAME_PARTICIPATION", gameIdBytes);
                pointsContract.awardPoints(player2, PARTICIPATION_POINTS, "GAME_PARTICIPATION", gameIdBytes);
            } else {
                player1Reward = PARTICIPATION_POINTS;
                player2Reward = PARTICIPATION_POINTS + VICTORY_POINTS;
                
                pointsContract.awardPoints(player2, VICTORY_POINTS, "GAME_WIN", gameIdBytes);
                pointsContract.awardPoints(player1, PARTICIPATION_POINTS, "GAME_PARTICIPATION", gameIdBytes);
                pointsContract.awardPoints(player2, PARTICIPATION_POINTS, "GAME_PARTICIPATION", gameIdBytes);
            }
        }

        // Update player reward statistics with points
        playerStats[player1].totalRewardsEarned += player1Reward;
        playerStats[player2].totalRewardsEarned += player2Reward;

        emit RewardsDistributed(gameId, player1, player1Reward, winner == player1);
        emit RewardsDistributed(gameId, player2, player2Reward, winner == player2);

        return (player1Reward, player2Reward);
    }

    /**
     * @notice Add player to leaderboard tracking
     * @param player Player address
     */
    function _addToLeaderboard(address player) internal {
        if (!isInLeaderboard[player]) {
            leaderboardPlayers.push(player);
            isInLeaderboard[player] = true;
        }
    }
}
