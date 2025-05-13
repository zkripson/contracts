// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import {Test, console2} from "forge-std/Test.sol";
import {GameFactoryWithStats} from "../../src/factories/GameFactory.sol";
import {BattleshipGameImplementation} from "../../src/BattleshipGameImplementation.sol";
import {SHIPToken} from "../../src/ShipToken.sol";
import {BattleshipStatistics} from "../../src/BattleshipStatistics.sol";

contract MockSHIPToken {
    function participationReward() external pure returns (uint256) {
        return 10 ether;
    }
    
    function victoryBonus() external pure returns (uint256) {
        return 25 ether;
    }
    
    function mintGameReward(address, bool, uint256) external pure returns (bool) {
        return true;
    }
}

contract GameFactoryTest is Test {
    // Contracts
    GameFactoryWithStats factory;
    BattleshipGameImplementation implementation;
    MockSHIPToken shipToken;
    
    // Test accounts
    address constant ADMIN = address(0x1);
    address constant BACKEND = address(0x2);
    address constant PLAYER1 = address(0x3);
    address constant PLAYER2 = address(0x4);
    address constant RANDOM_USER = address(0x5);
    
    // Setup before each test
    function setUp() public {
        // Deploy the implementation contract
        implementation = new BattleshipGameImplementation();
        
        // Deploy mock token
        shipToken = new MockSHIPToken();
        
        // Deploy the factory
        vm.prank(ADMIN);
        factory = new GameFactoryWithStats(
            address(implementation),
            BACKEND,
            address(shipToken)
        );
    }
    
    // Test initialization
    function testInitialization() public {
        assertEq(factory.currentImplementation(), address(implementation));
        assertEq(factory.backend(), BACKEND);
        assertEq(address(factory.shipToken()), address(shipToken));
        
        // Check roles
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), ADMIN));
        assertTrue(factory.hasRole(factory.UPGRADER_ROLE(), ADMIN));
        assertTrue(factory.hasRole(factory.BACKEND_ROLE(), BACKEND));
    }
    
    // Test creating a game
    function testCreateGame() public {
        // Create a game
        vm.prank(BACKEND);
        uint256 gameId = factory.createGame(PLAYER1, PLAYER2);
        
        // Verify game was created
        address gameAddress = factory.games(gameId);
        assertNotEq(gameAddress, address(0));
        
        // Check that game is properly initialized
        BattleshipGameImplementation game = BattleshipGameImplementation(gameAddress);
        assertEq(game.gameId(), gameId);
        assertEq(game.player1(), PLAYER1);
        assertEq(game.player2(), PLAYER2);
        assertEq(game.factory(), address(factory));
        assertEq(game.backend(), BACKEND);
    }
    
    // Test that only backend can create games
    function test_RevertWhen_CreateGameNotBackend() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        factory.createGame(PLAYER1, PLAYER2);
    }
    
    // Test creating game with invalid players
    function test_RevertWhen_CreateGameInvalidPlayer() public {
        // Cannot create game with same player
        vm.prank(BACKEND);
        vm.expectRevert();
        factory.createGame(PLAYER1, PLAYER1);
    }
    
    // Test creating game with zero address
    function test_RevertWhen_CreateGameZeroAddress() public {
        vm.prank(BACKEND);
        vm.expectRevert();
        factory.createGame(PLAYER1, address(0));
    }
    
    // Helper function to create a game
    function _createGame() internal returns (uint256, address) {
        vm.prank(BACKEND);
        uint256 gameId = factory.createGame(PLAYER1, PLAYER2);
        address gameAddress = factory.games(gameId);
        
        return (gameId, gameAddress);
    }
    
    // Simple test for game reporting 
    function testReportGameCompletion() public {
        // Create a game
        (uint256 gameId, address gameAddress) = _createGame();
        
        // Start the game
        vm.prank(BACKEND);
        BattleshipGameImplementation(gameAddress).startGame();
        
        // We need to call submitGameResult on the game contract before reporting to factory
        vm.prank(BACKEND);
        BattleshipGameImplementation(gameAddress).submitGameResult(
            PLAYER1, // winner
            20,      // shots
            "completed"
        );
        
        // Get the current stats before reporting
        (
            uint256 totalGamesBefore,
            uint256 completedGamesBefore,
            ,
            ,
            
        ) = factory.getGameStats();
        
        // Now report completion to factory
        vm.prank(BACKEND);
        factory.reportGameCompletion(
            gameId,
            PLAYER1, // winner
            300,     // duration
            20,      // shots
            "completed"
        );
        
        // Get updated stats
        (
            uint256 totalGamesAfter,
            uint256 completedGamesAfter,
            ,
            ,
            
        ) = factory.getGameStats();
        
        // Just verify that stats were updated
        assertEq(totalGamesAfter, totalGamesBefore);
        assertGt(completedGamesAfter, completedGamesBefore);
    }
    
    // Test that only backend can report completion
    function test_RevertWhen_ReportGameCompletionNotBackend() public {
        (uint256 gameId, address gameAddress) = _createGame();
        
        // Start the game
        vm.prank(BACKEND);
        BattleshipGameImplementation(gameAddress).startGame();
        
        // Try to report completion from non-backend
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        factory.reportGameCompletion(gameId, PLAYER1, 300, 20, "completed");
    }
    
    // Test reporting with invalid game ID
    function test_RevertWhen_ReportGameCompletionInvalidGame() public {
        uint256 invalidGameId = 999;
        
        vm.prank(BACKEND);
        vm.expectRevert();
        factory.reportGameCompletion(invalidGameId, PLAYER1, 300, 20, "completed");
    }
    
    // Test cancelling a game
    function testCancelGame() public {
        (uint256 gameId, address gameAddress) = _createGame();
        
        // Cancel the game
        vm.prank(BACKEND);
        factory.cancelGame(gameId);
        
        // Verify game state is updated
        BattleshipGameImplementation game = BattleshipGameImplementation(gameAddress);
        assertEq(uint256(game.state()), uint256(BattleshipGameImplementation.GameState.Cancelled));
        
        // Check global stats
        (
            uint256 totalGames,
            uint256 completedGames,
            uint256 cancelledGames,
            ,
            
        ) = factory.getGameStats();
        
        assertEq(totalGames, 1);
        assertEq(completedGames, 0);
        assertEq(cancelledGames, 1);
    }
    
    // Test that only backend can cancel games
    function test_RevertWhen_CancelGameNotBackend() public {
        (uint256 gameId,) = _createGame();
        
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        factory.cancelGame(gameId);
    }
    
    // Test setting new implementation
    function testSetImplementation() public {
        // Deploy new implementation
        BattleshipGameImplementation newImpl = new BattleshipGameImplementation();
        
        // Set new implementation
        vm.prank(ADMIN);
        factory.setImplementation(address(newImpl));
        
        // Verify implementation was updated
        assertEq(factory.currentImplementation(), address(newImpl));
    }
    
    // Test that only upgrader can set implementation
    function test_RevertWhen_SetImplementationNotUpgrader() public {
        BattleshipGameImplementation newImpl = new BattleshipGameImplementation();
        
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        factory.setImplementation(address(newImpl));
    }
    
    // Test setting implementation to zero address
    function test_RevertWhen_SetImplementationZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        factory.setImplementation(address(0));
    }
    
    // Test setting new backend
    function testSetBackend() public {
        address newBackend = address(0x6);
        
        vm.prank(ADMIN);
        factory.setBackend(newBackend);
        
        assertEq(factory.backend(), newBackend);
        
        // Check roles are updated
        assertFalse(factory.hasRole(factory.BACKEND_ROLE(), BACKEND));
        assertTrue(factory.hasRole(factory.BACKEND_ROLE(), newBackend));
    }
    
    // Test that only admin can set backend
    function test_RevertWhen_SetBackendNotAdmin() public {
        address newBackend = address(0x6);
        
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        factory.setBackend(newBackend);
    }
    
    // Test setting backend to zero address
    function test_RevertWhen_SetBackendZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        factory.setBackend(address(0));
    }
    
    // Test setting ship token
    function testSetShipToken() public {
        address newToken = address(0x7);
        
        vm.prank(ADMIN);
        factory.setShipToken(newToken);
        
        assertEq(address(factory.shipToken()), newToken);
    }
    
    // Test that only admin can set ship token
    function test_RevertWhen_SetShipTokenNotAdmin() public {
        address newToken = address(0x7);
        
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        factory.setShipToken(newToken);
    }
    
    // Test setting ship token to zero address
    function test_RevertWhen_SetShipTokenZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        factory.setShipToken(address(0));
    }
    
    // Test pausing the factory
    function testPause() public {
        vm.prank(ADMIN);
        factory.pause();
        
        assertTrue(factory.paused());
        
        // Verify cannot create games while paused
        vm.prank(BACKEND);
        vm.expectRevert(); // Using general expectRevert() without a specific message
        factory.createGame(PLAYER1, PLAYER2);
        
        // Unpause
        vm.prank(ADMIN);
        factory.unpause();
        
        assertFalse(factory.paused());
        
        // Can create games again
        vm.prank(BACKEND);
        factory.createGame(PLAYER1, PLAYER2);
    }
    
    // Test that only admin can pause/unpause
    function test_RevertWhen_PauseNotAdmin() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        factory.pause();
    }
    
    // Test player statistics tracking
    function testPlayerStats() public {
        // Create a game
        (uint256 gameId, address gameAddress) = _createGame();
        
        // Start the game
        vm.prank(BACKEND);
        BattleshipGameImplementation(gameAddress).startGame();
        
        // Report completion
        vm.prank(BACKEND);
        factory.reportGameCompletion(
            gameId,
            PLAYER1, // winner
            300,     // duration
            20,      // shots
            "completed"
        );
        
        // Get player stats
        GameFactoryWithStats.PlayerStats memory player1Stats = factory.getPlayerStats(PLAYER1);
        GameFactoryWithStats.PlayerStats memory player2Stats = factory.getPlayerStats(PLAYER2);
        
        // Check player1 stats (winner)
        assertEq(player1Stats.totalGames, 1);
        assertEq(player1Stats.wins, 1);
        assertEq(player1Stats.losses, 0);
        assertEq(player1Stats.winStreak, 1);
        assertEq(player1Stats.bestWinStreak, 1);
        assertEq(player1Stats.totalGameDuration, 300);
        assertGt(player1Stats.lastGameTime, 0);
        
        // Check player2 stats (loser)
        assertEq(player2Stats.totalGames, 1);
        assertEq(player2Stats.wins, 0);
        assertEq(player2Stats.losses, 1);
        assertEq(player2Stats.winStreak, 0);
        assertEq(player2Stats.bestWinStreak, 0);
        assertEq(player2Stats.totalGameDuration, 300);
        assertGt(player2Stats.lastGameTime, 0);
    }
    
    // Test getting player games
    function testGetPlayerGames() public {
        // Create multiple games for player1
        vm.startPrank(BACKEND);
        uint256 gameId1 = factory.createGame(PLAYER1, PLAYER2);
        uint256 gameId2 = factory.createGame(PLAYER1, address(0x7));
        vm.stopPrank();
        
        // Get player games
        uint256[] memory games = factory.getPlayerGames(PLAYER1);
        
        // Check games
        assertEq(games.length, 2);
        assertEq(games[0], gameId1);
        assertEq(games[1], gameId2);
    }
}