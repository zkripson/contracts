// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import "forge-std/Test.sol";
import "../../src/factories/GameFactory.sol";
import "../../src/BattleshipGameImplementation.sol";
import "../../src/BattleshipStatistics.sol";
import "../../src/ShipToken.sol";
import "../../src/proxies/BattleShipGameProxy.sol";

contract StatisticsIntegrationTest is Test {
    // Contracts
    GameFactoryWithStats factory;
    BattleshipGameImplementation implementation;
    BattleshipStatistics statistics;
    SHIPToken shipToken;

    // Test addresses
    address admin = address(0x1);
    address backend = address(0x2);
    address player1 = address(0x3);
    address player2 = address(0x4);

    function setUp() public {
        vm.startPrank(admin);

        // Deploy contracts
        implementation = new BattleshipGameImplementation();
        statistics = new BattleshipStatistics(admin);
        shipToken = new SHIPToken(admin, admin, 1_000_000 ether);

        factory = new GameFactoryWithStats(address(implementation), backend, address(shipToken), address(statistics));

        // Set up permissions
        bytes32 statsUpdaterRole = statistics.STATS_UPDATER_ROLE();
        statistics.grantRole(statsUpdaterRole, address(factory));
        shipToken.setDistributor(address(factory));

        vm.stopPrank();
    }

    function testStatsIntegration() public {
        // 1. Create a game
        vm.startPrank(backend);
        uint256 gameId = factory.createGame(player1, player2);

        // Get game address
        address gameAddress = factory.games(gameId);
        BattleshipGameImplementation game = BattleshipGameImplementation(gameAddress);

        // 2. Start the game
        game.startGame();

        // Simulate some time passing
        vm.warp(block.timestamp + 300); // 5 minutes later

        // 3. End the game with player1 as winner
        uint256 duration = 300; // seconds
        uint256 shots = 20;
        string memory endReason = "completed";

        factory.reportGameCompletion(gameId, player1, duration, shots, endReason);
        vm.stopPrank();

        // 4. Verify statistics are updated in both contracts

        // Check factory stats
        (
            uint256 totalGames,
            uint256 wins,
            uint256 losses, // draws
            // winRate
            ,
            ,
            uint256 currentWinStreak,
            uint256 bestWinStreak, // avgDuration
            ,
            uint256 totalRewards, // gamesThisWeek
            ,

        ) = // weeklyWinRate
            statistics.getPlayerStats(player1);

        // Check GameFactory statistics
        GameFactoryWithStats.PlayerStats memory factoryStats = factory.getPlayerStats(player1);

        // 5. Assert values are consistent
        assertEq(totalGames, 1, "Statistics totalGames should be 1");
        assertEq(wins, 1, "Statistics wins should be 1");
        assertEq(currentWinStreak, 1, "Statistics winStreak should be 1");
        assertEq(bestWinStreak, 1, "Statistics bestWinStreak should be 1");

        assertEq(factoryStats.totalGames, 1, "Factory totalGames should be 1");
        assertEq(factoryStats.wins, 1, "Factory wins should be 1");
        assertEq(factoryStats.winStreak, 1, "Factory winStreak should be 1");

        // 6. Test a second game where player2 wins
        vm.startPrank(backend);
        uint256 gameId2 = factory.createGame(player1, player2);
        address gameAddress2 = factory.games(gameId2);
        BattleshipGameImplementation game2 = BattleshipGameImplementation(gameAddress2);
        game2.startGame();

        vm.warp(block.timestamp + 400); // 400 seconds later
        factory.reportGameCompletion(gameId2, player2, 400, 30, "completed");
        vm.stopPrank();

        // Check updated statistics for player1 (should have a loss)
        (
            totalGames,
            wins,
            losses, // draws
            // winRate
            ,
            ,
            currentWinStreak,
            bestWinStreak, // avgDuration
            // totalRewards
            // gamesThisWeek
            // weeklyWinRate
            ,
            ,
            ,

        ) = statistics.getPlayerStats(player1);

        assertEq(totalGames, 2, "Player1 should have 2 games total");
        assertEq(wins, 1, "Player1 should have 1 win");
        assertEq(losses, 1, "Player1 should have 1 loss");
        assertEq(currentWinStreak, 0, "Player1 should have 0 current streak");
        assertEq(bestWinStreak, 1, "Player1 best streak should still be 1");

        // Check player2 stats (should have a win)
        (
            totalGames,
            wins, // losses
            // draws
            // winRate
            ,
            ,
            ,
            currentWinStreak, // bestWinStreak
            // avgDuration
            // totalRewards
            // gamesThisWeek
            // weeklyWinRate
            ,
            ,
            ,
            ,

        ) = statistics.getPlayerStats(player2);

        assertEq(totalGames, 2, "Player2 should have 2 games total");
        assertEq(wins, 1, "Player2 should have 1 win");
        assertEq(currentWinStreak, 1, "Player2 should have 1 current streak");
    }

    function testDrawGameStats() public {
        // Create a game that ends in a draw
        vm.startPrank(backend);
        uint256 gameId = factory.createGame(player1, player2);

        address gameAddress = factory.games(gameId);
        BattleshipGameImplementation game = BattleshipGameImplementation(gameAddress);
        game.startGame();

        vm.warp(block.timestamp + 500);

        // End in a draw (winner = address(0))
        factory.reportGameCompletion(gameId, address(0), 500, 40, "draw");
        vm.stopPrank();

        // Check both players have a draw recorded
        (
            uint256 totalGames,
            uint256 wins,
            uint256 losses,
            uint256 draws, // winRate
            ,
            uint256 currentWinStreak, // bestWinStreak
            // avgDuration
            // totalRewards
            // gamesThisWeek
            ,
            ,
            ,
            ,

        ) = // weeklyWinRate
            statistics.getPlayerStats(player1);

        assertEq(totalGames, 1, "Player1 should have 1 game");
        assertEq(wins, 0, "Player1 should have 0 wins");
        assertEq(losses, 0, "Player1 should have 0 losses");
        assertEq(draws, 1, "Player1 should have 1 draw");
        assertEq(currentWinStreak, 0, "Player1 should have 0 current streak");
    }

    function testCancelledGameStats() public {
        // Create a game that gets cancelled
        vm.startPrank(backend);
        uint256 gameId = factory.createGame(player1, player2);

        // Cancel the game
        factory.cancelGame(gameId);
        vm.stopPrank();

        // Verify that both players have a draw with "cancelled" reason
        (
            uint256 totalGames,
            uint256 wins,
            uint256 losses,
            uint256 draws, // winRate
            // currentWinStreak
            // bestWinStreak
            // avgDuration
            // totalRewards
            // gamesThisWeek
            ,
            ,
            ,
            ,
            ,
            ,

        ) = // weeklyWinRate
            statistics.getPlayerStats(player1);

        assertEq(totalGames, 1, "Player1 should have 1 game");
        assertEq(wins, 0, "Player1 should have 0 wins");
        assertEq(losses, 0, "Player1 should have 0 losses");
        assertEq(draws, 1, "Player1 should have 1 draw for cancelled game");
    }
}
