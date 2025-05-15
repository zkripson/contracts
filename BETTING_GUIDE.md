# Battleship Betting Guide

## Overview

The BattleshipBetting contract adds a financial layer to the ZK Battleship game, allowing players to wager USDC on game outcomes. This guide explains how the betting system works and how to integrate it with the existing game infrastructure.

## Key Features

- **USDC-based betting**: Players stake USDC tokens to create and join games
- **Invite system**: Players create betting invites that others can accept
- **Escrow mechanism**: Funds are held in contract until game completion
- **Platform fees**: 10% fee on winning payouts goes to treasury
- **Draw support**: Stakes are returned to both players in case of a draw
- **Time-limited invites**: Unmatched invites expire after 24 hours

## Contract Flow

1. **Create Invite**: Player creates a betting invite with desired stake amount
2. **Accept Invite**: Another player accepts the invite, matching the stake
3. **Create Game**: Backend creates the actual game instance via GameFactory
4. **Play Game**: Players complete the game through normal gameplay
5. **Resolve Bet**: Backend resolves the bet, distributing winnings

## Integration with ZK Battleship

### Prerequisites

1. Deploy the BattleshipBetting contract with:
   - USDC token address
   - GameFactory address
   - Treasury address for fee collection
   - Backend address for game creation
   - Admin address for contract management

2. Grant the betting contract BACKEND_ROLE on the GameFactory:
   ```solidity
   gameFactory.grantRole(gameFactory.BACKEND_ROLE(), address(bettingContract));
   ```

### Creating a Bet-Based Game

```solidity
// 1. Player 1 creates an invite
uint256 inviteId = betting.createInvite(100 * 10**6); // $100 USDC

// 2. Player 2 accepts the invite
betting.acceptInvite(inviteId);

// 3. Backend creates the game
uint256 gameId = betting.createGame(inviteId);

// 4. Game proceeds as normal...

// 5. Backend resolves the bet after game completion
betting.resolveGame(gameId, winnerAddress);
```

## Contract Methods

### For Players

- `createInvite(uint256 stakeAmount)`: Create a new betting invite
- `acceptInvite(uint256 inviteId)`: Accept an existing invite
- `cancelInvite(uint256 inviteId)`: Cancel your own unmatched invite
- `getPlayerInvites(address player)`: View all invites for a player

### For Backend

- `createGame(uint256 inviteId)`: Create game from matched invite
- `resolveGame(uint256 gameId, address winner)`: Distribute winnings

### For Admin

- `setTreasury(address newTreasury)`: Update treasury address
- `pause()`: Pause contract in emergency
- `unpause()`: Resume normal operations

## View Functions

- `getBettingInvite(uint256 inviteId)`: Get invite details
- `getGameBettingInfo(uint256 gameId)`: Get betting info for a game
- `isInviteExpired(uint256 inviteId)`: Check if invite has expired

## Security Features

1. **Role-based access control**: Only authorized addresses can create games and resolve bets
2. **Reentrancy protection**: All fund transfers are protected against reentrancy
3. **Pausable**: Contract can be paused in emergency situations
4. **Time limits**: Invites expire after 24 hours to prevent stale bets
5. **Balance checks**: Validates players have sufficient funds before accepting

## Testing

The contract includes comprehensive unit tests and integration tests:

```bash
# Run unit tests
forge test --match-contract BattleshipBettingTest

# Run integration tests
forge test --match-contract BettingIntegrationTest
```

## Gas Optimization

The contract is optimized for Base network with:
- Efficient storage packing in the BettingInvite struct
- Minimal external calls during critical operations
- Batch operations where possible

## Platform Economics

- **Winner payout**: 90% of total pool (180% of their original stake)
- **Platform fee**: 10% of total pool
- **Draw handling**: No fees, both players get their stakes back
- **Min stake**: $1 USDC
- **Max stake**: $10,000 USDC

## Example Scenarios

### Successful Game with Winner
- Player A stakes $100
- Player B stakes $100
- Total pool: $200
- Player A wins
- Player A receives: $180 (90% of pool)
- Treasury receives: $20 (10% of pool)

### Draw Game
- Player A stakes $100
- Player B stakes $100
- Game ends in draw
- Player A receives: $100 (original stake)
- Player B receives: $100 (original stake)
- Treasury receives: $0 (no fees on draws)

### Cancelled/Expired Invite
- Player A stakes $100
- No one accepts within 24 hours
- Player A or anyone can trigger expiration
- Player A receives: $100 (full refund)

## Future Enhancements

1. **Variable fee rates**: Different fee percentages for different stake levels
2. **Tournament support**: Multi-player betting pools
3. **Betting history**: On-chain tracking of betting statistics
4. **Reward tokens**: Additional SHIP token rewards for betting participants
5. **Referral system**: Incentives for bringing new players

## Security Considerations

1. Always validate USDC token address on deployment
2. Ensure proper role assignments before production
3. Monitor invite creation for potential spam
4. Consider implementing rate limiting for large stakes
5. Regular audits of treasury withdrawals

## Support

For issues or questions about the betting system:
1. Check the test files for usage examples
2. Review the contract documentation
3. Contact the development team
4. Submit issues to the GitHub repository