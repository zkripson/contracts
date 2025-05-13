// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import {Test, console2} from "forge-std/Test.sol";
import {BattleshipGameImplementation} from "../../src/BattleshipGameImplementation.sol";
import {GameFactoryWithStats} from "../../src/factories/GameFactory.sol";
import {SHIPToken} from "../../src/ShipToken.sol";
import {BattleshipStatistics} from "../../src/BattleshipStatistics.sol";

contract GameFlowTest is Test {
    // Contracts
    BattleshipGameImplementation implementation;
    GameFactoryWithStats factory;
    SHIPToken token;
    BattleshipStatistics statistics;
    
    // Test accounts
    address constant ADMIN = address(0x1);
    address constant BACKEND = address(0x2);
    address constant PLAYER1 = address(0x3);
    address constant PLAYER2 = address(0x4);
    
    // Game state
    uint256 gameId;
    address gameAddress;
    
    // Setup before each test
    function setUp() public {
        vm.startPrank(ADMIN);
        
        // Deploy token
        token = new SHIPToken(ADMIN, BACKEND, 1_000_000 * 10**18);
        
        // Deploy statistics
        statistics = new BattleshipStatistics(ADMIN);
        
        // Deploy implementation
        implementation = new BattleshipGameImplementation();
        
        // Deploy factory
        factory = new GameFactoryWithStats(
            address(implementation),
            BACKEND,
            address(token)
        );
        
        // Setup roles
        statistics.grantRole(statistics.STATS_UPDATER_ROLE(), address(factory));
        factory.grantRole(factory.STATS_ROLE(), address(statistics));
        
        vm.stopPrank();
    }
    
    // Test a complete game flow
    function testCompleteGameFlow() public {
        // 1. Create Game
        vm.prank(BACKEND);
        gameId = factory.createGame(PLAYER1, PLAYER2);
        
        gameAddress = factory.games(gameId);
        BattleshipGameImplementation game = BattleshipGameImplementation(gameAddress);
        
        // Verify game initialization
        assertEq(game.player1(), PLAYER1);
        assertEq(game.player2(), PLAYER2);
        assertEq(uint256(game.state()), uint256(BattleshipGameImplementation.GameState.Created));
        
        // 2. Start Game
        vm.prank(BACKEND);
        game.startGame();
        
        assertEq(uint256(game.state()), uint256(BattleshipGameImplementation.GameState.Active));
        
        // 3. Submit Game Result (Player1 wins)
        // Use block.timestamp since we're in the same block as game start
        vm.warp(block.timestamp + 300); // 5 minutes of gameplay
        
        vm.prank(BACKEND);
        game.submitGameResult(PLAYER1, 20, "completed");
        
        // Verify game completion
        assertEq(uint256(game.state()), uint256(BattleshipGameImplementation.GameState.Completed));
        
        // Get game info to check results
        (,,, BattleshipGameImplementation.GameState currentState,, BattleshipGameImplementation.GameResult memory result) = game.getGameInfo();
        
        assertEq(uint256(currentState), uint256(BattleshipGameImplementation.GameState.Completed));
        assertEq(result.winner, PLAYER1);
        assertEq(result.totalShots, 20);
        assertEq(result.endReason, "completed");
        assertEq(game.getGameDuration(), 300);
        
        // 5. Check Token Rewards
        uint256 participationReward = token.participationReward();
        uint256 victoryBonus = token.victoryBonus();
        
        // Player1 should have participation + victory bonus
        assertEq(token.balanceOf(PLAYER1), participationReward + victoryBonus);
        
        // Player2 should have just participation reward
        assertEq(token.balanceOf(PLAYER2), participationReward);
    }
    
    // Test game cancellation flow
    function testGameCancellationFlow() public {
        // 1. Create Game
        vm.prank(BACKEND);
        gameId = factory.createGame(PLAYER1, PLAYER2);
        
        gameAddress = factory.games(gameId);
        BattleshipGameImplementation game = BattleshipGameImplementation(gameAddress);
        
        // 2. Cancel Game before it starts
        vm.prank(BACKEND);
        factory.cancelGame(gameId);
        
        // Verify game state
        assertEq(uint256(game.state()), uint256(BattleshipGameImplementation.GameState.Cancelled));
        
        // 4. Ensure no rewards distributed
        assertEq(token.balanceOf(PLAYER1), 0);
        assertEq(token.balanceOf(PLAYER2), 0);
    }
    
    // Test multiple games and win streak
    function testMultipleGamesAndWinStreak() public {
        // Play 3 games with Player1 winning all
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(BACKEND);
            gameId = factory.createGame(PLAYER1, PLAYER2);
            
            gameAddress = factory.games(gameId);
            BattleshipGameImplementation game = BattleshipGameImplementation(gameAddress);
            
            // Start and complete game
            vm.prank(BACKEND);
            game.startGame();
            
            vm.warp(block.timestamp + 300);
            
            vm.prank(BACKEND);
            game.submitGameResult(PLAYER1, 20, "completed");
            
            // Skip cooldown period for token rewards
            vm.warp(block.timestamp + 5 minutes + 1);
        }
    }
    
    // Test contract upgrades
    function testUpgradeImplementation() public {
        // Create game with original implementation
        vm.prank(BACKEND);
        gameId = factory.createGame(PLAYER1, PLAYER2);
        
        gameAddress = factory.games(gameId);
        BattleshipGameImplementation game = BattleshipGameImplementation(gameAddress);
        
        // Deploy new implementation (for testing we'll use the same contract, but in reality it would be an upgraded version)
        BattleshipGameImplementation newImplementation = new BattleshipGameImplementation();
        
        // Update implementation in factory
        vm.prank(ADMIN);
        factory.setImplementation(address(newImplementation));
        
        // Create a new game with updated implementation
        vm.prank(BACKEND);
        uint256 newGameId = factory.createGame(PLAYER1, PLAYER2);
        
        address newGameAddress = factory.games(newGameId);
        BattleshipGameImplementation newGame = BattleshipGameImplementation(newGameAddress);
        
        // Verify both games work correctly
        // Original game uses original implementation
        vm.prank(BACKEND);
        game.startGame();
        
        assertEq(uint256(game.state()), uint256(BattleshipGameImplementation.GameState.Active));
        
        // New game uses new implementation
        vm.prank(BACKEND);
        newGame.startGame();
        
        assertEq(uint256(newGame.state()), uint256(BattleshipGameImplementation.GameState.Active));
        
        // Complete both games
        vm.prank(BACKEND);
        game.submitGameResult(PLAYER1, 20, "completed");
        
        vm.prank(BACKEND);
        newGame.submitGameResult(PLAYER2, 20, "completed");
        
        // Verify both completed correctly
        assertEq(uint256(game.state()), uint256(BattleshipGameImplementation.GameState.Completed));
        assertEq(uint256(newGame.state()), uint256(BattleshipGameImplementation.GameState.Completed));
    }
    
    // Test pause/unpause functionality
    function testPauseAndUnpause() public {
        // Pause the factory
        vm.prank(ADMIN);
        factory.pause();
        
        // Verify cannot create new games
        vm.expectRevert("Pausable: paused");
        vm.prank(BACKEND);
        factory.createGame(PLAYER1, PLAYER2);
        
        // Unpause
        vm.prank(ADMIN);
        factory.unpause();
        
        // Can create games again
        vm.prank(BACKEND);
        factory.createGame(PLAYER1, PLAYER2);
        
        // Test pausing a specific game
        gameAddress = factory.games(1);
        BattleshipGameImplementation game = BattleshipGameImplementation(gameAddress);
        
        vm.prank(ADMIN);
        game.pause();
        
        // Start should fail while paused
        vm.expectRevert("Pausable: paused");
        vm.prank(BACKEND);
        game.startGame();
        
        // Unpause game
        vm.prank(ADMIN);
        game.unpause();
        
        // Can start now
        vm.prank(BACKEND);
        game.startGame();
    }
}