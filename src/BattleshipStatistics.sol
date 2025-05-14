// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title BattleshipStatistics
 * @notice Comprehensive statistics tracking for ZK Battleship
 * @dev Handles player statistics, global game stats, and leaderboards
 */
contract BattleshipStatistics is AccessControl, Pausable {
    // ==================== Roles ====================
    bytes32 public constant STATS_UPDATER_ROLE = keccak256("STATS_UPDATER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ==================== Structs ====================
    struct PlayerStats {
        uint256 totalGames;
        uint256 wins;
        uint256 losses;
        uint256 draws;
        uint256 currentWinStreak;
        uint256 bestWinStreak;
        uint256 currentLossStreak;
        uint256 totalShotsInGames;
        uint256 totalGameDuration;
        uint256 totalRewardsEarned;
        uint256 firstGameTimestamp;
        uint256 lastGameTimestamp;
        uint256 gamesThisWeek;
        uint256 gamesThisMonth;
        uint256 weeklyWins;
        uint256 monthlyWins;
        mapping(string => uint256) endReasonCounts; // "completed", "forfeit", "timeout", etc.
    }

    struct GlobalStats {
        uint256 totalGames;
        uint256 totalPlayers;
        uint256 averageGameDuration;
        uint256 totalPlayTime;
        uint256 longestGame;
        uint256 shortestGame;
        uint256 totalRewardsDistributed;
        uint256 peakConcurrentGames;
        uint256 lastUpdated;
        mapping(string => uint256) popularEndReasons;
    }

    struct LeaderboardEntry {
        address player;
        uint256 score;
        uint256 rank;
    }

    // ==================== State Variables ====================
    mapping(address => PlayerStats) private playerStats;
    mapping(address => bool) private hasPlayedGame;
    address[] private allPlayers;

    GlobalStats private globalStats;

    // Weekly/Monthly tracking
    uint256 private currentWeek;
    uint256 private currentMonth;

    // Leaderboards
    mapping(bytes32 => LeaderboardEntry[]) private leaderboards;
    bytes32 public constant WINS_LEADERBOARD = keccak256("WINS");
    bytes32 public constant WIN_RATE_LEADERBOARD = keccak256("WIN_RATE");
    bytes32 public constant STREAK_LEADERBOARD = keccak256("STREAK");
    bytes32 public constant WEEKLY_LEADERBOARD = keccak256("WEEKLY");
    bytes32 public constant MONTHLY_LEADERBOARD = keccak256("MONTHLY");

    // Constants
    uint256 private constant WEEK_SECONDS = 7 * 24 * 60 * 60;
    uint256 private constant MONTH_SECONDS = 30 * 24 * 60 * 60;

    // ==================== Events ====================
    event PlayerStatsUpdated(address indexed player, uint256 timestamp);
    event GlobalStatsUpdated(uint256 timestamp);
    event LeaderboardUpdated(bytes32 indexed leaderboardType, uint256 timestamp);
    event NewPlayer(address indexed player, uint256 timestamp);
    event WeeklyStatsReset(uint256 newWeek);
    event MonthlyStatsReset(uint256 newMonth);

    // ==================== Constructor ====================
    constructor(address _admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);

        // Initialize time tracking
        currentWeek = block.timestamp / WEEK_SECONDS;
        currentMonth = block.timestamp / MONTH_SECONDS;

        // Initialize global stats
        globalStats.lastUpdated = block.timestamp;
        globalStats.shortestGame = type(uint256).max;
    }

    // ==================== Player Statistics ====================

    /**
     * @notice Record a game result for a player
     * @param player Player address
     * @param isWinner Whether the player won
     * @param gameId Game ID
     * @param duration Game duration in seconds
     * @param shots Number of shots taken
     * @param endReason How the game ended
     * @param rewardEarned Amount of reward earned
     */
    function recordGameResult(
        address player,
        bool isWinner,
        uint256 gameId,
        uint256 duration,
        uint256 shots,
        string memory endReason,
        uint256 rewardEarned
    )
        external
        onlyRole(STATS_UPDATER_ROLE)
        whenNotPaused
    {
        // Check if new player
        if (!hasPlayedGame[player]) {
            _addNewPlayer(player);
        }

        // Check if we need to reset weekly/monthly stats
        _checkAndResetPeriodStats();

        PlayerStats storage stats = playerStats[player];

        // Update basic stats
        stats.totalGames++;
        stats.totalShotsInGames += shots;
        stats.totalGameDuration += duration;
        stats.totalRewardsEarned += rewardEarned;
        stats.lastGameTimestamp = block.timestamp;
        stats.gamesThisWeek++;
        stats.gamesThisMonth++;

        // Update win/loss stats
        if (isWinner) {
            stats.wins++;
            stats.weeklyWins++;
            stats.monthlyWins++;
            stats.currentWinStreak++;
            stats.currentLossStreak = 0;

            if (stats.currentWinStreak > stats.bestWinStreak) {
                stats.bestWinStreak = stats.currentWinStreak;
            }
        } else {
            stats.losses++;
            stats.currentLossStreak++;
            stats.currentWinStreak = 0;
        }

        // Update end reason count
        stats.endReasonCounts[endReason]++;

        // Update global stats
        _updateGlobalStats(duration, shots, rewardEarned, endReason);

        emit PlayerStatsUpdated(player, block.timestamp);

        // Update relevant leaderboards
        _updateLeaderboards(player);
    }

    /**
     * @notice Record a draw result
     * @param player1 First player
     * @param player2 Second player
     * @param duration Game duration
     * @param shots Number of shots
     * @param endReason End reason
     */
    function recordDraw(
        address player1,
        address player2,
        uint256 duration,
        uint256 shots,
        string memory endReason
    )
        external
        onlyRole(STATS_UPDATER_ROLE)
        whenNotPaused
    {
        // Both players get a draw
        if (!hasPlayedGame[player1]) _addNewPlayer(player1);
        if (!hasPlayedGame[player2]) _addNewPlayer(player2);

        _checkAndResetPeriodStats();

        PlayerStats storage stats1 = playerStats[player1];
        PlayerStats storage stats2 = playerStats[player2];

        // Update both players
        for (uint256 i = 0; i < 2; i++) {
            PlayerStats storage stats = i == 0 ? stats1 : stats2;

            stats.totalGames++;
            stats.draws++;
            stats.totalGameDuration += duration;
            stats.totalShotsInGames += shots / 2; // Split shots between players
            stats.lastGameTimestamp = block.timestamp;
            stats.gamesThisWeek++;
            stats.gamesThisMonth++;
            stats.currentWinStreak = 0;
            stats.currentLossStreak = 0;
            stats.endReasonCounts[endReason]++;
        }

        _updateGlobalStats(duration, shots, 0, endReason);

        emit PlayerStatsUpdated(player1, block.timestamp);
        emit PlayerStatsUpdated(player2, block.timestamp);
    }

    // ==================== View Functions ====================

    /**
     * @notice Get comprehensive player statistics
     * @param player Player address
     * @return totalGames Total number of games played
     * @return wins Number of games won
     * @return losses Number of games lost
     * @return draws Number of draw games
     * @return winRate Win rate as percentage (0-10000)
     * @return currentWinStreak Current win streak
     * @return bestWinStreak Best win streak achieved
     * @return averageGameDuration Average duration of games played
     * @return totalRewardsEarned Total rewards earned
     * @return gamesThisWeek Number of games played this week
     * @return weeklyWinRate Win rate for this week (0-10000)
     */
    function getPlayerStats(address player)
        external
        view
        returns (
            uint256 totalGames,
            uint256 wins,
            uint256 losses,
            uint256 draws,
            uint256 winRate, // Percentage (0-10000)
            uint256 currentWinStreak,
            uint256 bestWinStreak,
            uint256 averageGameDuration,
            uint256 totalRewardsEarned,
            uint256 gamesThisWeek,
            uint256 weeklyWinRate
        )
    {
        PlayerStats storage stats = playerStats[player];

        uint256 avgDuration = stats.totalGames > 0 ? stats.totalGameDuration / stats.totalGames : 0;
        uint256 winRateCalc = stats.totalGames > 0 ? (stats.wins * 10_000) / stats.totalGames : 0;
        uint256 weeklyWinRateCalc = stats.gamesThisWeek > 0 ? (stats.weeklyWins * 10_000) / stats.gamesThisWeek : 0;

        return (
            stats.totalGames,
            stats.wins,
            stats.losses,
            stats.draws,
            winRateCalc,
            stats.currentWinStreak,
            stats.bestWinStreak,
            avgDuration,
            stats.totalRewardsEarned,
            stats.gamesThisWeek,
            weeklyWinRateCalc
        );
    }

    /**
     * @notice Get global game statistics
     * @return totalGames Total number of games played
     * @return totalPlayers Total number of players
     * @return averageGameDuration Average game duration in seconds
     * @return totalPlayTime Total play time across all games
     * @return longestGame Duration of the longest game
     * @return shortestGame Duration of the shortest game
     * @return totalRewardsDistributed Total rewards distributed
     */
    function getGlobalStats()
        external
        view
        returns (
            uint256 totalGames,
            uint256 totalPlayers,
            uint256 averageGameDuration,
            uint256 totalPlayTime,
            uint256 longestGame,
            uint256 shortestGame,
            uint256 totalRewardsDistributed
        )
    {
        return (
            globalStats.totalGames,
            globalStats.totalPlayers,
            globalStats.averageGameDuration,
            globalStats.totalPlayTime,
            globalStats.longestGame,
            globalStats.shortestGame == type(uint256).max ? 0 : globalStats.shortestGame,
            globalStats.totalRewardsDistributed
        );
    }

    /**
     * @notice Get leaderboard for a specific type
     * @param leaderboardType Type of leaderboard
     * @param limit Maximum entries to return
     * @return entries Leaderboard entries
     */
    function getLeaderboard(
        bytes32 leaderboardType,
        uint256 limit
    )
        external
        view
        returns (LeaderboardEntry[] memory entries)
    {
        LeaderboardEntry[] storage board = leaderboards[leaderboardType];
        uint256 length = board.length > limit ? limit : board.length;

        entries = new LeaderboardEntry[](length);
        for (uint256 i = 0; i < length; i++) {
            entries[i] = board[i];
        }

        return entries;
    }

    /**
     * @notice Get player's rank in a specific leaderboard
     * @param player Player address
     * @param leaderboardType Type of leaderboard
     * @return rank Player's rank (1-based, 0 if not found)
     */
    function getPlayerRank(address player, bytes32 leaderboardType) external view returns (uint256 rank) {
        LeaderboardEntry[] storage board = leaderboards[leaderboardType];

        for (uint256 i = 0; i < board.length; i++) {
            if (board[i].player == player) {
                return i + 1; // 1-based ranking
            }
        }

        return 0; // Not found
    }

    /**
     * @notice Check if it's time to reset weekly/monthly stats
     * @return needsWeeklyReset Whether weekly reset is needed
     * @return needsMonthlyReset Whether monthly reset is needed
     */
    function checkResetNeeded() external view returns (bool needsWeeklyReset, bool needsMonthlyReset) {
        uint256 week = block.timestamp / WEEK_SECONDS;
        uint256 month = block.timestamp / MONTH_SECONDS;

        return (week != currentWeek, month != currentMonth);
    }

    // ==================== Admin Functions ====================

    /**
     * @notice Manually reset weekly statistics
     */
    function resetWeeklyStats() external onlyRole(ADMIN_ROLE) {
        _resetWeeklyStats();
    }

    /**
     * @notice Manually reset monthly statistics
     */
    function resetMonthlyStats() external onlyRole(ADMIN_ROLE) {
        _resetMonthlyStats();
    }

    /**
     * @notice Update a specific leaderboard manually
     * @param leaderboardType Type of leaderboard to update
     */
    function updateLeaderboard(bytes32 leaderboardType) external onlyRole(ADMIN_ROLE) {
        _rebuildLeaderboard(leaderboardType);
    }

    /**
     * @notice Pause statistics recording
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause statistics recording
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ==================== Internal Functions ====================

    /**
     * @notice Add a new player to tracking
     * @param player Player address
     */
    function _addNewPlayer(address player) internal {
        if (!hasPlayedGame[player]) {
            hasPlayedGame[player] = true;
            allPlayers.push(player);
            playerStats[player].firstGameTimestamp = block.timestamp;
            globalStats.totalPlayers++;

            emit NewPlayer(player, block.timestamp);
        }
    }

    /**
     * @notice Update global statistics
     * @param duration Game duration
     * @param shots Number of shots
     * @param reward Reward distributed
     * @param endReason End reason
     */
    function _updateGlobalStats(uint256 duration, uint256 shots, uint256 reward, string memory endReason) internal {
        globalStats.totalGames++;
        globalStats.totalPlayTime += duration;
        globalStats.totalRewardsDistributed += reward;
        globalStats.averageGameDuration = globalStats.totalPlayTime / globalStats.totalGames;

        if (duration > globalStats.longestGame) {
            globalStats.longestGame = duration;
        }

        if (duration < globalStats.shortestGame) {
            globalStats.shortestGame = duration;
        }

        globalStats.lastUpdated = block.timestamp;
        globalStats.popularEndReasons[endReason]++;

        emit GlobalStatsUpdated(block.timestamp);
    }

    /**
     * @notice Check and reset period statistics if needed
     */
    function _checkAndResetPeriodStats() internal {
        uint256 week = block.timestamp / WEEK_SECONDS;
        uint256 month = block.timestamp / MONTH_SECONDS;

        if (week != currentWeek) {
            _resetWeeklyStats();
        }

        if (month != currentMonth) {
            _resetMonthlyStats();
        }
    }

    /**
     * @notice Reset weekly statistics for all players
     */
    function _resetWeeklyStats() internal {
        currentWeek = block.timestamp / WEEK_SECONDS;

        for (uint256 i = 0; i < allPlayers.length; i++) {
            PlayerStats storage stats = playerStats[allPlayers[i]];
            stats.gamesThisWeek = 0;
            stats.weeklyWins = 0;
        }

        // Rebuild weekly leaderboard
        _rebuildLeaderboard(WEEKLY_LEADERBOARD);

        emit WeeklyStatsReset(currentWeek);
    }

    /**
     * @notice Reset monthly statistics for all players
     */
    function _resetMonthlyStats() internal {
        currentMonth = block.timestamp / MONTH_SECONDS;

        for (uint256 i = 0; i < allPlayers.length; i++) {
            PlayerStats storage stats = playerStats[allPlayers[i]];
            stats.gamesThisMonth = 0;
            stats.monthlyWins = 0;
        }

        // Rebuild monthly leaderboard
        _rebuildLeaderboard(MONTHLY_LEADERBOARD);

        emit MonthlyStatsReset(currentMonth);
    }

    /**
     * @notice Update all relevant leaderboards for a player
     * @param player Player address
     */
    function _updateLeaderboards(address player) internal {
        // Update all leaderboards - in a real implementation,
        // you might want to do this less frequently for gas efficiency
        _updatePlayerInLeaderboard(player, WINS_LEADERBOARD);
        _updatePlayerInLeaderboard(player, WIN_RATE_LEADERBOARD);
        _updatePlayerInLeaderboard(player, STREAK_LEADERBOARD);
        _updatePlayerInLeaderboard(player, WEEKLY_LEADERBOARD);
        _updatePlayerInLeaderboard(player, MONTHLY_LEADERBOARD);
    }

    /**
     * @notice Update a specific player in a specific leaderboard
     * @param player Player address
     * @param leaderboardType Type of leaderboard
     */
    function _updatePlayerInLeaderboard(address player, bytes32 leaderboardType) internal {
        uint256 score = _getPlayerScore(player, leaderboardType);

        LeaderboardEntry[] storage board = leaderboards[leaderboardType];

        // Find if player already exists in leaderboard
        uint256 existingIndex = type(uint256).max;
        for (uint256 i = 0; i < board.length; i++) {
            if (board[i].player == player) {
                existingIndex = i;
                break;
            }
        }

        // Update or add entry
        if (existingIndex != type(uint256).max) {
            board[existingIndex].score = score;
        } else {
            board.push(
                LeaderboardEntry({
                    player: player,
                    score: score,
                    rank: 0 // Will be updated in sort
                 })
            );
        }

        // Sort leaderboard (simple insertion sort for small arrays)
        _sortLeaderboard(board);

        // Update ranks
        for (uint256 i = 0; i < board.length; i++) {
            board[i].rank = i + 1;
        }

        emit LeaderboardUpdated(leaderboardType, block.timestamp);
    }

    /**
     * @notice Get player's score for a specific leaderboard type
     * @param player Player address
     * @param leaderboardType Type of leaderboard
     * @return score Player's score
     */
    function _getPlayerScore(address player, bytes32 leaderboardType) internal view returns (uint256 score) {
        PlayerStats storage stats = playerStats[player];

        if (leaderboardType == WINS_LEADERBOARD) {
            return stats.wins;
        } else if (leaderboardType == WIN_RATE_LEADERBOARD) {
            return stats.totalGames > 0 ? (stats.wins * 10_000) / stats.totalGames : 0;
        } else if (leaderboardType == STREAK_LEADERBOARD) {
            return stats.bestWinStreak;
        } else if (leaderboardType == WEEKLY_LEADERBOARD) {
            return stats.weeklyWins;
        } else if (leaderboardType == MONTHLY_LEADERBOARD) {
            return stats.monthlyWins;
        }

        return 0;
    }

    /**
     * @notice Sort leaderboard in descending order
     * @param board Leaderboard array to sort
     */
    function _sortLeaderboard(LeaderboardEntry[] storage board) internal {
        if (board.length <= 1) return;

        // Simple insertion sort (sufficient for most leaderboards)
        for (uint256 i = 1; i < board.length; i++) {
            LeaderboardEntry memory key = board[i];
            uint256 j = i;

            while (j > 0 && board[j - 1].score < key.score) {
                board[j] = board[j - 1];
                j--;
            }

            board[j] = key;
        }
    }

    /**
     * @notice Rebuild a complete leaderboard
     * @param leaderboardType Type of leaderboard to rebuild
     */
    function _rebuildLeaderboard(bytes32 leaderboardType) internal {
        delete leaderboards[leaderboardType];

        for (uint256 i = 0; i < allPlayers.length; i++) {
            _updatePlayerInLeaderboard(allPlayers[i], leaderboardType);
        }
    }
}
