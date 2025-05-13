// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/**
 * @title IBackendBattleship
 * @notice Interface for backend integration with simplified ZK Battleship contracts
 * @dev This interface defines all the functions the backend needs to interact with
 */
interface IBackendBattleship {
    // ==================== Structs ====================
    struct GameInfo {
        uint256 gameId;
        address player1;
        address player2;
        uint8 state; // 0: Created, 1: Active, 2: Completed, 3: Cancelled
        uint256 createdAt;
        address winner;
        uint256 startTime;
        uint256 endTime;
        uint256 totalShots;
        string endReason;
    }

    struct PlayerStats {
        uint256 totalGames;
        uint256 wins;
        uint256 losses;
        uint256 draws;
        uint256 winRate;
        uint256 currentWinStreak;
        uint256 bestWinStreak;
        uint256 averageGameDuration;
        uint256 totalRewardsEarned;
        uint256 gamesThisWeek;
        uint256 weeklyWinRate;
    }

    // ==================== Game Management ====================

    /**
     * @notice Create a new game between two players
     * @param player1 Address of first player
     * @param player2 Address of second player
     * @return gameId Unique identifier for the created game
     */
    function createGame(address player1, address player2) external returns (uint256 gameId);

    /**
     * @notice Start a game (transition from Created to Active)
     * @param gameId ID of the game to start
     */
    function startGame(uint256 gameId) external;

    /**
     * @notice Submit game result and complete the game
     * @param gameId ID of the game
     * @param winner Address of the winner (address(0) for draw)
     * @param totalShots Number of shots taken
     * @param endReason Reason for game ending ("completed", "forfeit", "timeout", etc.)
     */
    function submitGameResult(uint256 gameId, address winner, uint256 totalShots, string memory endReason) external;

    /**
     * @notice Cancel a game
     * @param gameId ID of the game to cancel
     */
    function cancelGame(uint256 gameId) external;

    // ==================== Game Information ====================

    /**
     * @notice Get game information
     * @param gameId ID of the game
     * @return info Game information struct
     */
    function getGameInfo(uint256 gameId) external view returns (GameInfo memory info);

    /**
     * @notice Get all games for a player
     * @param player Player address
     * @return gameIds Array of game IDs
     */
    function getPlayerGames(address player) external view returns (uint256[] memory gameIds);

    // ==================== Statistics ====================

    /**
     * @notice Get player statistics
     * @param player Player address
     * @return stats Player statistics
     */
    function getPlayerStats(address player) external view returns (PlayerStats memory stats);

    /**
     * @notice Get global game statistics
     * @return totalGames Total number of games
     * @return totalPlayers Total number of players
     * @return averageDuration Average game duration
     * @return totalPlayTime Total play time across all games
     * @return totalShots Total shots across all games
     */
    function getGlobalStats()
        external
        view
        returns (
            uint256 totalGames,
            uint256 totalPlayers,
            uint256 averageDuration,
            uint256 totalPlayTime,
            uint256 totalShots
        );

    // ==================== Rewards ====================

    /**
     * @notice Get current reward parameters
     * @return participationReward Reward for participating
     * @return victoryBonus Bonus for winning
     */
    function getRewardParams() external view returns (uint256 participationReward, uint256 victoryBonus);

    /**
     * @notice Check if player can receive rewards
     * @param player Player address
     * @return canReceive Whether player can receive rewards
     * @return reason Reason if can't receive
     */
    function canReceiveReward(address player) external view returns (bool canReceive, string memory reason);

    // ==================== Admin Functions ====================

    /**
     * @notice Update reward parameters (admin only)
     * @param participationReward New participation reward
     * @param victoryBonus New victory bonus
     * @param cooldown New cooldown between rewards
     * @param dailyLimit New daily reward limit
     */
    function updateRewardParams(
        uint256 participationReward,
        uint256 victoryBonus,
        uint256 cooldown,
        uint256 dailyLimit
    ) external;
}

/**
 * @title IBackendEvents
 * @notice Events that the backend should monitor
 */
interface IBackendEvents {
    // Game events
    event GameCreated(uint256 indexed gameId, address indexed player1, address indexed player2);
    event GameStarted(uint256 indexed gameId, uint256 startTime);
    event GameCompleted(uint256 indexed gameId, address indexed winner, uint256 endTime);
    event GameCancelled(uint256 indexed gameId);

    // Reward events
    event RewardMinted(address indexed player, uint256 amount, bool isWinner, uint256 gameId);
    event RewardBlocked(address indexed player, string reason);

    // Statistics events
    event PlayerStatsUpdated(address indexed player);
    event LeaderboardUpdated(bytes32 indexed leaderboardType);
}
