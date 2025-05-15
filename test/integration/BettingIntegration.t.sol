// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import { Test, console2 } from "forge-std/Test.sol";
import { BattleshipBetting } from "../../src/Betting.sol";
import { GameFactoryWithStats } from "../../src/factories/GameFactory.sol";
import { BattleshipGameImplementation } from "../../src/BattleshipGameImplementation.sol";
import { BattleshipStatistics } from "../../src/BattleshipStatistics.sol";
import { SHIPToken } from "../../src/ShipToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock USDC token for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
    
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

/**
 * @title BettingIntegrationTest
 * @notice Tests the full integration of the betting system with the ZK Battleship game
 * @dev Demonstrates the complete flow from bet creation to game completion
 */
contract BettingIntegrationTest is Test {
    // Core contracts
    BattleshipBetting betting;
    GameFactoryWithStats factory;
    BattleshipGameImplementation implementation;
    BattleshipStatistics statistics;
    SHIPToken shipToken;
    MockUSDC usdc;
    
    // Test accounts
    address constant ADMIN = address(0x1);
    address constant BACKEND = address(0x2);
    address constant TREASURY = address(0x3);
    address constant PLAYER1 = address(0x4);
    address constant PLAYER2 = address(0x5);
    
    // Test constants
    uint256 constant STANDARD_STAKE = 100 * 10**6; // $100 USDC
    
    function setUp() public {
        // Deploy all contracts in the proper order
        
        // 1. Deploy SHIP token
        shipToken = new SHIPToken(ADMIN, BACKEND, 0); // BACKEND will be the reward distributor
        
        // 2. Deploy statistics contract
        statistics = new BattleshipStatistics(ADMIN);
        
        // 3. Deploy implementation
        implementation = new BattleshipGameImplementation();
        
        // 4. Deploy factory
        vm.startPrank(ADMIN);
        factory = new GameFactoryWithStats(
            address(implementation),
            BACKEND,
            address(shipToken),
            address(statistics)
        );
        
        // 5. Grant permissions
        statistics.grantRole(statistics.STATS_UPDATER_ROLE(), address(factory));
        vm.stopPrank();
        
        // 6. Deploy USDC mock
        usdc = new MockUSDC();
        
        // 7. Deploy betting contract
        betting = new BattleshipBetting(
            address(usdc),
            address(factory),
            TREASURY,
            BACKEND,
            ADMIN
        );
        
        // 8. Grant betting contract backend role on factory (needed to create games)
        vm.startPrank(ADMIN);
        factory.grantRole(factory.BACKEND_ROLE(), address(betting));
        vm.stopPrank();
        
        // 8. Fund test players
        usdc.mint(PLAYER1, STANDARD_STAKE * 10);
        usdc.mint(PLAYER2, STANDARD_STAKE * 10);
        
        // 9. Approve betting contract
        vm.prank(PLAYER1);
        usdc.approve(address(betting), type(uint256).max);
        
        vm.prank(PLAYER2);
        usdc.approve(address(betting), type(uint256).max);
    }
    
    /**
     * @notice Test the complete flow from bet creation to game resolution
     * @dev This simulates a real-world scenario where players bet on a game
     */
    function testCompleteBettingGameFlow() public {
        // Track initial balances
        uint256 player1InitialBalance = usdc.balanceOf(PLAYER1);
        uint256 player2InitialBalance = usdc.balanceOf(PLAYER2);
        
        // Step 1: Player 1 creates a betting invite
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE);
        
        // Verify invite was created
        BattleshipBetting.BettingInvite memory invite = betting.getBettingInvite(inviteId);
        assertEq(invite.creator, PLAYER1);
        assertEq(invite.stakeAmount, STANDARD_STAKE);
        
        // Step 2: Player 2 accepts the invite
        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId);
        
        // Verify funds are escrowed
        assertEq(usdc.balanceOf(address(betting)), STANDARD_STAKE * 2);
        
        // Step 3: Backend creates the game
        vm.prank(BACKEND);
        uint256 gameId = betting.createGame(inviteId);
        
        // Verify game was created in factory
        address gameAddress = factory.games(gameId);
        assertNotEq(gameAddress, address(0));
        
        // Step 4: Verify game state
        BattleshipGameImplementation game = BattleshipGameImplementation(gameAddress);
        assertEq(game.player1(), PLAYER1);
        assertEq(game.player2(), PLAYER2);
        
        // Step 5: Start the game (backend simulation)
        vm.prank(BACKEND);
        game.startGame();
        
        // Step 6: Submit game result (backend simulation)
        vm.prank(BACKEND);
        game.submitGameResult(PLAYER1, 20, "completed");
        
        // Step 7: Report completion to factory
        vm.prank(BACKEND);
        factory.reportGameCompletion(gameId, PLAYER1, 300, 20, "completed");
        
        // Step 8: Resolve betting
        vm.prank(BACKEND);
        betting.resolveGame(gameId, PLAYER1);
        
        // Verify final balances
        uint256 totalPool = STANDARD_STAKE * 2;
        uint256 platformFee = (totalPool * betting.PLATFORM_FEE_PERCENTAGE()) / 100;
        uint256 winnerPayout = totalPool - platformFee;
        
        assertEq(usdc.balanceOf(PLAYER1), player1InitialBalance - STANDARD_STAKE + winnerPayout);
        assertEq(usdc.balanceOf(PLAYER2), player2InitialBalance - STANDARD_STAKE);
        assertEq(usdc.balanceOf(TREASURY), platformFee);
        assertEq(usdc.balanceOf(address(betting)), 0);
        
        // Verify statistics were updated
        GameFactoryWithStats.PlayerStats memory player1Stats = factory.getPlayerStats(PLAYER1);
        assertEq(player1Stats.wins, 1);
        assertEq(player1Stats.totalGames, 1);
        
        GameFactoryWithStats.PlayerStats memory player2Stats = factory.getPlayerStats(PLAYER2);
        assertEq(player2Stats.losses, 1);
        assertEq(player2Stats.totalGames, 1);
    }
    
    /**
     * @notice Test draw scenario with betting
     * @dev When a game ends in a draw, both players get their stakes back
     */
    function testDrawScenarioWithBetting() public {
        // Create and match bet
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE);
        
        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId);
        
        // Create game
        vm.prank(BACKEND);
        uint256 gameId = betting.createGame(inviteId);
        
        // Resolve as draw (winner = address(0))
        vm.prank(BACKEND);
        betting.resolveGame(gameId, address(0));
        
        // Both players should get their stakes back
        assertEq(usdc.balanceOf(PLAYER1), STANDARD_STAKE * 10); // Back to original
        assertEq(usdc.balanceOf(PLAYER2), STANDARD_STAKE * 10); // Back to original
        assertEq(usdc.balanceOf(TREASURY), 0); // No platform fee on draws
    }
    
    /**
     * @notice Test cancellation flow
     * @dev Player can cancel an unmatched invite and get their stake back
     */
    function testCancellationFlow() public {
        // Create invite
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE);
        
        uint256 balanceBefore = usdc.balanceOf(PLAYER1);
        
        // Cancel before anyone accepts
        vm.prank(PLAYER1);
        betting.cancelInvite(inviteId);
        
        // Verify stake was returned
        assertEq(usdc.balanceOf(PLAYER1), balanceBefore + STANDARD_STAKE);
        
        BattleshipBetting.BettingInvite memory invite = betting.getBettingInvite(inviteId);
        assertEq(uint256(invite.betStatus), uint256(BattleshipBetting.BetStatus.Cancelled));
    }
    
    /**
     * @notice Test expired invite handling
     * @dev Anyone can trigger refund for expired invites
     */
    function testExpiredInviteHandling() public {
        // Create invite
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE);
        
        // Time travel past expiration
        vm.warp(block.timestamp + betting.INVITE_TIMEOUT() + 1);
        
        // Anyone can trigger the refund
        vm.prank(address(0x999)); // Random address
        betting.handleExpiredInvite(inviteId);
        
        // Verify stake was returned
        assertEq(usdc.balanceOf(PLAYER1), STANDARD_STAKE * 10);
        
        BattleshipBetting.BettingInvite memory invite = betting.getBettingInvite(inviteId);
        assertEq(uint256(invite.betStatus), uint256(BattleshipBetting.BetStatus.Expired));
    }
    
    /**
     * @notice Test view functions for game betting info
     * @dev Verify that betting info can be retrieved using game ID
     */
    function testGetGameBettingInfo() public {
        // Setup game with betting
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE);
        
        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId);
        
        vm.prank(BACKEND);
        uint256 gameId = betting.createGame(inviteId);
        
        // Get betting info
        (uint256 returnedInviteId, uint256 totalPool, bool resolved) = betting.getGameBettingInfo(gameId);
        
        assertEq(returnedInviteId, inviteId);
        assertEq(totalPool, STANDARD_STAKE * 2);
        assertFalse(resolved);
        
        // Resolve and check again
        vm.prank(BACKEND);
        betting.resolveGame(gameId, PLAYER1);
        
        (, , bool resolvedAfter) = betting.getGameBettingInfo(gameId);
        assertTrue(resolvedAfter);
    }
}