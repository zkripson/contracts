## Contract Modification Request: Backend-Driven ZK Battleship

**Context:** We've simplified our ZK Battleship implementation to handle all gameplay in the backend (Cloudflare Workers). The contracts now only need to:
1. Create games and assign IDs
2. Store game metadata and final results
3. Track player/game statistics
4. Handle reward distribution on Base

**Key Changes Needed:**
1. Simplify BattleshipGameImplementation
* Remove all ZK verification functionality
* Remove board submission and shot mechanics
* Keep only game metadata (players, creation time, etc.)
* Add a simple `submitGameResult()` function for backend to call
* Add game statistics storage
2. Update GameFactory
* Keep game creation functionality
* Add player statistics tracking
* Add game statistics aggregation
* Remove unnecessary complexity
3. Enhance ShipToken for Base deployment
* Ensure proper reward distribution
* Add anti-abuse measures
* Keep existing daily limits and cooldowns
4. Add Statistics Contracts
* Player statistics (games played, wins, losses, streaks, etc.)
* Game statistics (total games, average duration, etc.)
* Leaderboards functionality

**Specific Requirements:**

```solidity
// Simplified game flow:
// 1. Frontend calls GameFactory.createGame(opponent) → returns gameId
// 2. Backend handles gameplay logic
// 3. Backend calls submitGameResult(gameId, winner, stats)
// 4. Contract distributes rewards and updates statistics

// New data structures needed:
struct GameResult {
    uint256 gameId;
    address player1;
    address player2;
    address winner;
    uint256 startTime;
    uint256 endTime;
    uint256 totalShots;
    string endReason; // "completed", "forfeit", "timeout", "time_limit"
}

struct PlayerStats {
    uint256 totalGames;
    uint256 wins;
    uint256 losses;
    uint256 winStreak;
    uint256 bestWinStreak;
    uint256 totalShipsDestroyed;
    uint256 averageGameDuration;
    uint256 totalRewardsEarned;
}

```

**Contract Architecture:**

```
GameFactory (creates games, manages player stats)
    ↓
BattleshipGameImplementation (simplified, stores results)
    ↓
ShipToken (rewards on Base)

```

**Key Functions to Implement:**
1. **GameFactory.sol:**
   * `createGame(address opponent)` → returns gameId
   * `getPlayerStats(address player)` → returns PlayerStats
   * `getGameStats()` → returns overall statistics
   * `getLeaderboard(uint256 limit)` → returns top players
2. **BattleshipGameImplementation.sol:**
   * `submitGameResult(address winner, uint256 endTime, uint256 totalShots, string endReason)`
   * `getGameInfo()` → returns game metadata
   * Remove: ZK functions, board functions, shot functions
3. **ShipToken.sol:**
   * Keep existing reward functionality
   * Ensure Base network compatibility
   * Add batch reward distribution for gas efficiency
**Backend Integration Points:**
* Backend calls `createGame()` when players are ready
* Backend calls `submitGameResult()` when game ends
* Backend can query stats for leaderboards/profiles
* Rewards are automatically distributed when results are submitted
**Additional Considerations:**
* Use events for the backend to monitor contract interactions
* Add access control (only backend can submit results)
* Handle edge cases (game cancellation, timeout, etc.)
* Optimize for Base network (low gas costs)
Please modify the contracts to implement this simplified, backend-driven architecture while maintaining clean code structure and proper access control.