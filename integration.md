# Backend Integration Guide for Simplified ZK Battleship

## Overview

This guide explains how to integrate the simplified ZK Battleship smart contracts with your Cloudflare Workers backend using Viem. The architecture removes all ZK complexity from the contracts, making them lightweight and focused on game metadata, statistics, and rewards.

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                    Frontend (React)                        │
├─────────────────────────────────────────────────────────────┤
│              Cloudflare Workers (Backend)                  │
├─────────────────────────────────────────────────────────────┤
│                Smart Contracts (Base)                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │GameFactory  │  │BattleshipGameImplementation│  │ SHIPToken   │        │
│                  │    │             │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│       │                    │                │              │
│  ┌─────────────┐                      ┌─────────────┐        │
│  │Statistics   │                      │   Events    │        │
│  │Contract     │                      │ Monitoring  │        │
│  └─────────────┘                      └─────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Installation

```bash
npm install viem
```

## Contract Addresses

After deployment, you'll need these contract addresses (saved in `deployment-output.json`):

```typescript
interface ContractAddresses {
  SHIPToken: `0x${string}`;                              // On Base
  BattleshipGameImplementation: `0x${string}`; // On Base
  BattleshipStatistics: `0x${string}`;                   // On Base
  GameFactory: `0x${string}`;                   // On Base
  backend: `0x${string}`;                               // Your backend wallet
}
```

## Integration Steps

### 1. Contract Setup

```typescript
// contracts.ts
import { 
  createPublicClient, 
  createWalletClient, 
  http, 
  getContract,
  Account
} from 'viem';
import { base } from 'viem/chains';
import { privateKeyToAccount } from 'viem/accounts';

// Create account from private key
const account = privateKeyToAccount(process.env.BACKEND_PRIVATE_KEY! as `0x${string}`);

// Create clients
export const publicClient = createPublicClient({
  chain: base,
  transport: http('https://mainnet.base.org'),
});

export const walletClient = createWalletClient({
  account,
  chain: base,
  transport: http('https://mainnet.base.org'),
});

// Contract instances
export const gameFactory = getContract({
  address: CONTRACT_ADDRESSES.GameFactory,
  abi: gameFactoryABI,
  client: { public: publicClient, wallet: walletClient },
});

export const statistics = getContract({
  address: CONTRACT_ADDRESSES.BattleshipStatistics,
  abi: statisticsABI,
  client: { public: publicClient, wallet: walletClient },
});

export const shipToken = getContract({
  address: CONTRACT_ADDRESSES.SHIPToken,
  abi: shipTokenABI,
  client: { public: publicClient, wallet: walletClient },
});
```

### 2. Game Creation Flow

```typescript
// game-service.ts
import { parseEventLogs } from 'viem';

export class GameService {
  /**
   * Create a new game on-chain
   */
  async createGame(player1: `0x${string}`, player2: `0x${string}`): Promise<number> {
    try {
      // Call the contract
      const hash = await gameFactory.write.createGame([player1, player2]);
      
      // Wait for transaction receipt
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      
      // Extract game ID from events
      const logs = parseEventLogs({
        abi: gameFactoryABI,
        logs: receipt.logs,
      });
      
      const gameCreatedEvent = logs.find(log => log.eventName === 'GameCreated');
      if (!gameCreatedEvent) {
        throw new Error('GameCreated event not found');
      }
      
      const gameId = Number(gameCreatedEvent.args.gameId);
      
      console.log(`Game created: ${gameId} between ${player1} and ${player2}`);
      return gameId;
    } catch (error) {
      console.error('Error creating game:', error);
      throw new Error('Failed to create game');
    }
  }

  /**
   * Start a game (transition from Created to Active)
   */
  async startGame(gameId: number): Promise<void> {
    const gameAddress = await gameFactory.read.games([BigInt(gameId)]);
    
    const gameContract = getContract({
      address: gameAddress,
      abi: simplifiedGameABI,
      client: { public: publicClient, wallet: walletClient },
    });
    
    const hash = await gameContract.write.startGame();
    await publicClient.waitForTransactionReceipt({ hash });
    
    console.log(`Game ${gameId} started`);
  }

  /**
   * Submit game result when game ends
   */
  async completeGame(
    gameId: number,
    winner: `0x${string}` | null,
    totalShots: number,
    endReason: string
  ): Promise<void> {
    try {
      // Get game contract
      const gameAddress = await gameFactory.read.games([BigInt(gameId)]);
      const gameContract = getContract({
        address: gameAddress,
        abi: simplifiedGameABI,
        client: { public: publicClient, wallet: walletClient },
      });
      
      // Submit result to game contract
      const winnerAddress = winner || '0x0000000000000000000000000000000000000000';
      const hash = await gameContract.write.submitGameResult([
        winnerAddress,
        BigInt(totalShots),
        endReason
      ]);
      
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      
      // Report to factory for statistics
      const gameDuration = await this.calculateGameDuration(gameId);
      const reportHash = await gameFactory.write.reportGameCompletion([
        BigInt(gameId),
        winnerAddress,
        BigInt(gameDuration),
        BigInt(totalShots),
        endReason
      ]);
      
      await publicClient.waitForTransactionReceipt({ hash: reportHash });
      
      console.log(`Game ${gameId} completed. Winner: ${winner || 'Draw'}`);
    } catch (error) {
      console.error('Error completing game:', error);
      throw new Error('Failed to complete game');
    }
  }

  /**
   * Calculate game duration from creation to now
   */
  private async calculateGameDuration(gameId: number): Promise<number> {
    const gameAddress = await gameFactory.read.games([BigInt(gameId)]);
    const gameContract = getContract({
      address: gameAddress,
      abi: simplifiedGameABI,
      client: { public: publicClient },
    });
    
    const createdAt = await gameContract.read.createdAt();
    return Math.floor(Date.now() / 1000) - Number(createdAt);
  }
}
```

### 3. Game State Management in Durable Objects

```typescript
// game-session.ts
export class GameSession implements DurableObject {
  private state: DurableObjectState;
  private gameId?: number;
  private players: `0x${string}`[] = [];
  private gameStartTime?: number;
  
  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
  }

  /**
   * Handle game creation
   */
  async createGame(player1: `0x${string}`, player2: `0x${string}`): Promise<GameSessionResponse> {
    // Store players
    this.players = [player1, player2];
    
    // Create on-chain game
    const gameId = await gameService.createGame(player1, player2);
    this.gameId = gameId;
    
    // Save state
    await this.state.storage.put('gameData', {
      gameId,
      players: this.players,
      created: Date.now(),
      state: 'CREATED'
    });
    
    return { success: true, gameId };
  }

  /**
   * Handle game start
   */
  async startGame(): Promise<void> {
    if (!this.gameId) throw new Error('Game not created');
    
    // Start on-chain
    await gameService.startGame(this.gameId);
    
    // Update local state
    this.gameStartTime = Date.now();
    await this.state.storage.put('gameState', 'ACTIVE');
    await this.state.storage.put('startTime', this.gameStartTime);
  }

  /**
   * Handle game completion
   */
  async completeGame(
    winner: `0x${string}` | null,
    reason: string
  ): Promise<void> {
    if (!this.gameId || !this.gameStartTime) {
      throw new Error('Game not properly initialized');
    }
    
    const totalShots = await this.calculateTotalShots();
    
    // Complete on-chain
    await gameService.completeGame(
      this.gameId,
      winner,
      totalShots,
      reason
    );
    
    // Update local state
    await this.state.storage.put('gameState', 'COMPLETED');
    await this.state.storage.put('winner', winner);
    await this.state.storage.put('endTime', Date.now());
  }
}
```

### 4. Statistics Integration

```typescript
// statistics-service.ts
import { keccak256, toBytes } from 'viem';

export class StatisticsService {
  /**
   * Get player statistics
   */
  async getPlayerStats(playerAddress: `0x${string}`): Promise<PlayerStats> {
    const [
      totalGames,
      wins,
      losses,
      draws,
      winRate,
      currentWinStreak,
      bestWinStreak,
      averageGameDuration,
      totalRewardsEarned,
      gamesThisWeek,
      weeklyWinRate
    ] = await statistics.read.getPlayerStats([playerAddress]);
    
    return {
      totalGames: Number(totalGames),
      wins: Number(wins),
      losses: Number(losses),
      draws: Number(draws),
      winRate: Number(winRate),
      currentWinStreak: Number(currentWinStreak),
      bestWinStreak: Number(bestWinStreak),
      averageGameDuration: Number(averageGameDuration),
      totalRewardsEarned: Number(totalRewardsEarned),
      gamesThisWeek: Number(gamesThisWeek),
      weeklyWinRate: Number(weeklyWinRate)
    };
  }

  /**
   * Get leaderboard
   */
  async getLeaderboard(type: string, limit: number = 10): Promise<LeaderboardEntry[]> {
    const leaderboardTypes: Record<string, `0x${string}`> = {
      'wins': keccak256(toBytes('WINS')),
      'winRate': keccak256(toBytes('WIN_RATE')),
      'streak': keccak256(toBytes('STREAK')),
      'weekly': keccak256(toBytes('WEEKLY')),
      'monthly': keccak256(toBytes('MONTHLY'))
    };
    
    const entries = await statistics.read.getLeaderboard([
      leaderboardTypes[type],
      BigInt(limit)
    ]);
    
    return entries.map(entry => ({
      player: entry.player,
      score: Number(entry.score),
      rank: Number(entry.rank)
    }));
  }

  /**
   * Get global statistics
   */
  async getGlobalStats(): Promise<GlobalStats> {
    const [
      totalGames,
      totalPlayers,
      averageDuration,
      totalPlayTime,
      longestGame,
      shortestGame,
      totalRewardsDistributed
    ] = await statistics.read.getGlobalStats();
    
    return {
      totalGames: Number(totalGames),
      totalPlayers: Number(totalPlayers),
      averageDuration: Number(averageDuration),
      totalPlayTime: Number(totalPlayTime),
      longestGame: Number(longestGame),
      shortestGame: Number(shortestGame),
      totalRewardsDistributed: Number(totalRewardsDistributed)
    };
  }
}
```

### 5. Reward Distribution

```typescript
// reward-service.ts
export class RewardService {
  /**
   * Check if player can receive rewards
   */
  async canReceiveReward(playerAddress: `0x${string}`): Promise<{canReceive: boolean, reason: string}> {
    const [canReceive, reason] = await shipToken.read.canReceiveReward([playerAddress]);
    return { canReceive, reason };
  }

  /**
   * Batch distribute rewards (gas efficient)
   */
  async distributeBatchRewards(rewards: BatchReward[]): Promise<void> {
    try {
      // Convert to Viem-compatible format
      const viemRewards = rewards.map(reward => [
        reward.player,
        reward.isWinner,
        BigInt(reward.gameId)
      ] as const);
      
      const hash = await shipToken.write.mintBatchRewards([viemRewards]);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      
      console.log(`Batch rewards distributed. Gas used: ${receipt.gasUsed}`);
    } catch (error) {
      console.error('Error distributing rewards:', error);
      // Handle individual failures gracefully
    }
  }

  /**
   * Get current reward parameters
   */
  async getRewardParams(): Promise<{participationReward: bigint, victoryBonus: bigint}> {
    const rewardParams = await shipToken.read.getRewardParams();
    return {
      participationReward: rewardParams.participationReward,
      victoryBonus: rewardParams.victoryBonus
    };
  }
}
```

### 6. Event Monitoring

```typescript
// event-monitor.ts
import { parseEventLogs, watchContractEvent } from 'viem';

export class EventMonitor {
  private unsubscribeFunctions: Array<() => void> = [];
  
  /**
   * Set up event listeners
   */
  setupEventListeners(): void {
    // Game Factory events
    const unsubscribeGameCreated = watchContractEvent(publicClient, {
      address: gameFactory.address,
      abi: gameFactoryABI,
      eventName: 'GameCreated',
      onLogs: (logs) => {
        logs.forEach(log => {
          console.log(`Game created: ${log.args.gameId}`);
          this.handleGameCreated(
            Number(log.args.gameId),
            log.args.player1,
            log.args.player2
          );
        });
      },
    });
    
    const unsubscribeGameCompleted = watchContractEvent(publicClient, {
      address: gameFactory.address,
      abi: gameFactoryABI,
      eventName: 'GameCompleted',
      onLogs: (logs) => {
        logs.forEach(log => {
          console.log(`Game completed: ${log.args.gameId}`);
          this.handleGameCompleted(
            Number(log.args.gameId),
            log.args.winner
          );
        });
      },
    });

    // Statistics events
    const unsubscribeLeaderboard = watchContractEvent(publicClient, {
      address: statistics.address,
      abi: statisticsABI,
      eventName: 'LeaderboardUpdated',
      onLogs: (logs) => {
        logs.forEach(log => {
          console.log(`Leaderboard updated: ${log.args.leaderboardType}`);
          this.notifyClients('leaderboard-update', { 
            type: log.args.leaderboardType 
          });
        });
      },
    });

    // Ship Token events
    const unsubscribeRewardMinted = watchContractEvent(publicClient, {
      address: shipToken.address,
      abi: shipTokenABI,
      eventName: 'RewardMinted',
      onLogs: (logs) => {
        logs.forEach(log => {
          console.log(`Reward minted: ${log.args.amount} to ${log.args.player}`);
          this.notifyClients('reward-minted', {
            player: log.args.player,
            amount: log.args.amount,
            isWinner: log.args.isWinner,
            gameId: log.args.gameId
          });
        });
      },
    });

    // Store unsubscribe functions
    this.unsubscribeFunctions.push(
      unsubscribeGameCreated,
      unsubscribeGameCompleted,
      unsubscribeLeaderboard,
      unsubscribeRewardMinted
    );
  }

  /**
   * Handle specific events
   */
  private async handleGameCreated(
    gameId: number, 
    player1: `0x${string}`, 
    player2: `0x${string}`
  ): Promise<void> {
    // Notify connected players
    await this.notifyClients('game-created', { gameId, player1, player2 });
  }

  private async handleGameCompleted(gameId: number, winner: `0x${string}`): Promise<void> {
    // Update UI, notify players, etc.
    await this.notifyClients('game-completed', { gameId, winner });
  }

  /**
   * Clean up event listeners
   */
  cleanup(): void {
    this.unsubscribeFunctions.forEach(unsubscribe => unsubscribe());
    this.unsubscribeFunctions = [];
  }
}
```

### 7. Error Handling and Retry Logic

```typescript
// utils/retry.ts
import { TransactionExecutionError, TransactionReceiptNotFoundError } from 'viem';

export async function withRetry<T>(
  fn: () => Promise<T>,
  retries: number = 3,
  delay: number = 1000
): Promise<T> {
  for (let i = 0; i < retries; i++) {
    try {
      return await fn();
    } catch (error) {
      if (i === retries - 1) throw error;
      
      // Handle specific Viem errors
      if (error instanceof TransactionExecutionError) {
        console.log(`Transaction failed: ${error.message}`);
      } else if (error instanceof TransactionReceiptNotFoundError) {
        console.log(`Transaction receipt not found, retrying...`);
      }
      
      console.log(`Retry ${i + 1}/${retries} after error:`, error);
      await new Promise(resolve => setTimeout(resolve, delay * Math.pow(2, i)));
    }
  }
  throw new Error('Max retries exceeded');
}

// Usage
const gameId = await withRetry(() => 
  gameService.createGame(player1, player2)
);
```

### 8. Environment Configuration

```typescript
// env.d.ts
interface Env {
  // Contract addresses (all on Base)
  GAME_FACTORY_ADDRESS: string;
  STATISTICS_ADDRESS: string;
  SHIP_TOKEN_ADDRESS: string;
  
  // Network configuration
  BASE_RPC_URL: string;
  
  // Backend configuration
  BACKEND_PRIVATE_KEY: string; // Must start with 0x
  
  // Durable Objects
  GAME_SESSIONS: DurableObjectNamespace;
  
  // KV stores (optional)
  GAME_STATE: KVNamespace;
}
```

### 9. Testing Integration

```typescript
// test/integration.test.ts
import { test, expect } from 'vitest';
import { getContract } from 'viem';

test('should create and complete a game', async () => {
  const gameService = new GameService();
  
  // Create game
  const gameId = await gameService.createGame(
    '0x1234567890123456789012345678901234567890' as `0x${string}`,
    '0x0987654321098765432109876543210987654321' as `0x${string}`
  );
  expect(gameId).toBeGreaterThan(0);
  
  // Start game
  await gameService.startGame(gameId);
  
  // Get game info
  const gameAddress = await gameFactory.read.games([BigInt(gameId)]);
  const gameContract = getContract({
    address: gameAddress,
    abi: simplifiedGameABI,
    client: { public: publicClient },
  });
  
  const state = await gameContract.read.state();
  expect(state).toBe(1); // Active
  
  // Complete game
  await gameService.completeGame(
    gameId, 
    '0x1234567890123456789012345678901234567890' as `0x${string}`,
    10, 
    'completed'
  );
  
  // Verify completion
  const updatedState = await gameContract.read.state();
  expect(updatedState).toBe(2); // Completed
});
```

## Best Practices with Viem

1. **Type Safety**:
   - Use Viem's TypeScript-first approach for better type safety
   - Explicitly type addresses as `0x${string}`
   - Use `BigInt` for large numbers to avoid precision issues

2. **Gas Optimization**:
   - Use `estimateGas` before executing transactions
   - Implement proper gas limit strategies
   - Use `simulateContract` for dry runs

3. **Error Handling**:
   - Handle specific Viem error types
   - Use proper retry logic for network failures
   - Implement transaction confirmation strategies

4. **Performance**:
   - Use connection pooling for HTTP transports
   - Cache contract instances
   - Implement efficient event filtering

## Health Checks with Viem

```typescript
export async function healthCheck(): Promise<HealthStatus> {
  try {
    // Check contract connectivity
    const blockNumber = await publicClient.getBlockNumber();
    
    // Check backend wallet balance
    const balance = await publicClient.getBalance({ 
      address: account.address 
    });
    
    return {
      status: 'healthy',
      blockNumber: Number(blockNumber),
      walletBalance: balance.toString(),
      timestamp: new Date().toISOString()
    };
  } catch (error) {
    return {
      status: 'unhealthy',
      error: error.message,
      timestamp: new Date().toISOString()
    };
  }
}
```

## Conclusion

This integration guide provides a complete framework for connecting your Cloudflare Workers backend with the simplified ZK Battleship smart contracts using Viem. Key advantages of using Viem:

1. **Better Type Safety**: TypeScript-first design with excellent type inference
2. **Modern API**: Clean, intuitive API design
3. **Performance**: Optimized for performance and tree-shaking
4. **Error Handling**: Better error types and debugging capabilities
5. **Size**: Smaller bundle size compared to ethers.js

Remember to:
- Use proper TypeScript types for addresses and BigInt values
- Implement robust error handling for different failure scenarios
- Take advantage of Viem's batch operations for efficiency
- Monitor contract events for real-time state synchronization

For additional support or questions, refer to the Viem documentation and the contract ABIs generated during deployment.