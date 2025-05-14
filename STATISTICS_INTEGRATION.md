# Statistics Integration in ZK Battleship

This document outlines the changes made to integrate the BattleshipStatistics contract with the GameFactoryWithStats contract in the ZK Battleship project.

## 1. Overview of Changes

We've modified the system to have the GameFactoryWithStats contract update the comprehensive BattleshipStatistics contract after game events, while maintaining its own simplified statistics. This creates a more modular architecture with dedicated responsibilities.

## 2. Changes Made

### GameFactoryWithStats Contract

1. **Added Import and State Variable**
   - Imported BattleshipStatistics contract
   - Added a state variable to reference the statistics contract

2. **Updated Constructor**
   - Added statistics contract address parameter
   - Initialized the statistics contract reference

3. **Added Setter Method**
   - Added `setStatistics` method to allow updating the statistics contract reference

4. **Modified `reportGameCompletion` Method**
   - Updated to call appropriate statistics contract methods
   - Added handling for both win and draw scenarios
   - Modified `_distributeRewards` to return reward amounts for stats tracking

5. **Modified `cancelGame` Method**
   - Updated to call statistics contract to record game cancellation as a draw

### Deploy Script Updates

1. **Modified `Deploy.s.sol`**
   - Updated to deploy the statistics contract
   - Modified GameFactoryWithStats constructor call to include statistics
   - Added code to grant STATS_UPDATER_ROLE to the factory

2. **Modified `Upgrade.s.sol`**
   - Updated to load contract addresses from environment variables
   - Added validation of STATS_UPDATER_ROLE during upgrades
   - Improved error handling and logging

### Testing

1. **Created New Integration Test**
   - Added `StatisticsIntegration.t.sol` to test the integration
   - Tested game completion with different outcomes (win, loss, draw)
   - Tested game cancellation statistics updates
   - Validated consistency between factory and statistics contracts

## 3. Architecture Benefits

1. **Separation of Concerns**
   - GameFactory focuses on game creation and management
   - BattleshipStatistics focuses on comprehensive statistics tracking

2. **Scalability**
   - Statistics contract can be expanded independently
   - New statistics features can be added without modifying game logic

3. **Upgradeability**
   - Both contracts can be upgraded independently
   - Statistics contract can be replaced without affecting ongoing games

4. **Data Consistency**
   - Basic statistics are maintained in GameFactory for quick access
   - Comprehensive, historical statistics are stored in BattleshipStatistics

## 4. Deployment Process

1. Deploy all contracts (implementation, statistics, token, factory)
2. Grant STATS_UPDATER_ROLE to the factory
3. Set factory as the token distributor
4. Update configuration with deployed addresses

## 5. Usage Example

```solidity
// After a game completes
function reportGameCompletion(uint256 gameId, address winner, uint256 duration, uint256 shots, string memory endReason) {
    // Update basic stats in factory
    _updateLocalStats(player1, player2, winner, duration);
    
    // Update comprehensive statistics in dedicated contract
    if (winner == address(0)) {
        // Draw case
        statistics.recordDraw(player1, player2, duration, shots, endReason);
    } else {
        // Winner case
        statistics.recordGameResult(player1, winner == player1, gameId, duration, shots/2, endReason, player1Rewards);
        statistics.recordGameResult(player2, winner == player2, gameId, duration, shots/2, endReason, player2Rewards);
    }
}
```