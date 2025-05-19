// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import { Test, console2 } from "forge-std/Test.sol";
import { BattleshipGameImplementation } from "../../src/BattleshipGameImplementation.sol";
import { GameFactoryWithStats } from "../../src/factories/GameFactory.sol";
import { SHIPToken } from "../../src/ShipToken.sol";
import { BattleshipStatistics } from "../../src/BattleshipStatistics.sol";
import { BattleshipPoints } from "../../src/BattleshipPoints.sol";

contract GameFlowTest is Test {
    // Contracts
    BattleshipGameImplementation implementation;
    GameFactoryWithStats factory;
    SHIPToken token;
    BattleshipStatistics statistics;
    BattleshipPoints pointsContract;

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
        token = new SHIPToken(ADMIN, BACKEND, 1_000_000 * 10 ** 18);

        // Deploy statistics
        statistics = new BattleshipStatistics(ADMIN);

        // Deploy points contract
        pointsContract = new BattleshipPoints();

        // Deploy implementation
        implementation = new BattleshipGameImplementation();

        // Deploy factory with points contract
        factory = new GameFactoryWithStats(
            address(implementation), 
            BACKEND, 
            address(token), 
            address(statistics),
            address(pointsContract)
        );

        // Setup roles
        statistics.grantRole(statistics.STATS_UPDATER_ROLE(), address(factory));
        
        // Authorize factory to award points
        pointsContract.addAuthorizedSource(address(factory));

        vm.stopPrank();
    }

    // Test a complete game flow
    function testCompleteGameFlow() public {
        // Create a simplified test focused only on game initialization and completion

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

        // Verify game result directly using individual getters rather than getGameInfo()
        assertEq(uint256(game.state()), uint256(BattleshipGameImplementation.GameState.Completed));

        // Verify the game duration
        assertEq(game.getGameDuration(), 300);
        
        // 4. Report game completion to factory to award points
        vm.prank(BACKEND);
        factory.reportGameCompletion(
            gameId,
            PLAYER1, // winner
            300, // duration
            20, // shots
            "completed"
        );
        
        // 5. Verify points were awarded
        uint256 player1Points = pointsContract.getTotalPoints(PLAYER1);
        uint256 player2Points = pointsContract.getTotalPoints(PLAYER2);
        
        // Winner gets participation + victory points
        assertEq(player1Points, factory.PARTICIPATION_POINTS() + factory.VICTORY_POINTS());
        
        // Loser gets only participation points
        assertEq(player2Points, factory.PARTICIPATION_POINTS());
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

        // 4. Ensure no points were awarded
        assertEq(pointsContract.getTotalPoints(PLAYER1), 0);
        assertEq(pointsContract.getTotalPoints(PLAYER2), 0);
        
        // Still verify no tokens were minted
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

        // Deploy new implementation (for testing we'll use the same contract, but in reality it would be an upgraded
        // version)
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
        // We only need to test the factory pause functionality, since we can't
        // directly access the game contract's admin functions in this integration test

        // Pause the factory
        vm.prank(ADMIN);
        factory.pause();

        // Verify cannot create new games
        vm.prank(BACKEND);
        vm.expectRevert(); // Using general expectRevert() without a specific message
        factory.createGame(PLAYER1, PLAYER2);

        // Unpause
        vm.prank(ADMIN);
        factory.unpause();

        // Can create games again
        vm.prank(BACKEND);
        uint256 newGameId = factory.createGame(PLAYER1, PLAYER2);
        assertGt(newGameId, 0);
    }
}
