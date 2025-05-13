// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import {Test, console2} from "forge-std/Test.sol";
import {BattleshipGameImplementation} from "../../src/BattleshipGameImplementation.sol";

contract BattleshipGameImplementationTest is Test {
    // Contracts
    BattleshipGameImplementation gameImpl;
    
    // Test accounts
    address constant FACTORY = address(0x1);
    address constant PLAYER1 = address(0x2);
    address constant PLAYER2 = address(0x3);
    address constant BACKEND = address(0x4);
    address constant RANDOM_USER = address(0x5);
    
    // Test data
    uint256 constant GAME_ID = 1;
    
    // Setup before each test
    function setUp() public {
        // Create implementation as the deployer (test contract)
        gameImpl = new BattleshipGameImplementation();
        
        // Since we're the deployer, grant factory role to FACTORY
        gameImpl.grantRole(gameImpl.DEFAULT_ADMIN_ROLE(), FACTORY);
        
        // Have FACTORY initialize it
        vm.prank(FACTORY);
        gameImpl.initialize(GAME_ID, PLAYER1, PLAYER2, FACTORY, BACKEND);
    }
    
    // Test that initialization sets the correct values
    function testInitialization() public {
        assertEq(gameImpl.gameId(), GAME_ID);
        assertEq(gameImpl.player1(), PLAYER1);
        assertEq(gameImpl.player2(), PLAYER2);
        assertEq(gameImpl.factory(), FACTORY);
        assertEq(gameImpl.backend(), BACKEND);
        assertEq(uint256(gameImpl.state()), uint256(BattleshipGameImplementation.GameState.Created));
        
        // Check that roles are correctly assigned
        assertTrue(gameImpl.hasRole(gameImpl.DEFAULT_ADMIN_ROLE(), FACTORY));
        assertTrue(gameImpl.hasRole(gameImpl.FACTORY_ROLE(), FACTORY));
        assertTrue(gameImpl.hasRole(gameImpl.BACKEND_ROLE(), BACKEND));
    }
    
    // Test that initializing twice fails
    function test_RevertWhen_InitializeTwice() public {
        vm.prank(FACTORY);
        vm.expectRevert();
        gameImpl.initialize(GAME_ID, PLAYER1, PLAYER2, FACTORY, BACKEND);
    }
    
    // Test game start functionality
    function testStartGame() public {
        // Only backend can start the game
        vm.prank(BACKEND);
        gameImpl.startGame();
        
        // Check state has changed to Active
        assertEq(uint256(gameImpl.state()), uint256(BattleshipGameImplementation.GameState.Active));
        
        // Check start time is recorded
        (,,,,, BattleshipGameImplementation.GameResult memory result) = gameImpl.getGameInfo();
        assertGt(result.startTime, 0);
    }
    
    // Test that only backend can start the game
    function test_RevertWhen_StartGameNotBackend() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        gameImpl.startGame();
    }
    
    // Test that game can't be started twice
    function test_RevertWhen_StartGameAlreadyActive() public {
        // First start is successful
        vm.prank(BACKEND);
        gameImpl.startGame();
        
        // Second start should fail
        vm.prank(BACKEND);
        vm.expectRevert();
        gameImpl.startGame();
    }
    
    // Test submitting game result
    function testSubmitGameResult() public {
        // First, start the game
        vm.prank(BACKEND);
        gameImpl.startGame();
        
        // Submit result with player1 as winner
        vm.prank(BACKEND);
        gameImpl.submitGameResult(PLAYER1, 10, "completed");
        
        // Check state has changed to Completed
        assertEq(uint256(gameImpl.state()), uint256(BattleshipGameImplementation.GameState.Completed));
        
        // Check result data is stored correctly
        (,,,,, BattleshipGameImplementation.GameResult memory result) = gameImpl.getGameInfo();
        assertEq(result.winner, PLAYER1);
        assertEq(result.totalShots, 10);
        assertEq(result.endReason, "completed");
        assertGt(result.endTime, 0);
    }
    
    // Test that only backend can submit results
    function test_RevertWhen_SubmitGameResultNotBackend() public {
        // Start the game
        vm.prank(BACKEND);
        gameImpl.startGame();
        
        // Attempt to submit result from non-backend
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        gameImpl.submitGameResult(PLAYER1, 10, "completed");
    }
    
    // Test that results can only be submitted for active games
    function test_RevertWhen_SubmitGameResultNotActive() public {
        // Attempt to submit result without starting game
        vm.prank(BACKEND);
        vm.expectRevert();
        gameImpl.submitGameResult(PLAYER1, 10, "completed");
    }
    
    // Test that winner must be a valid player
    function test_RevertWhen_SubmitGameResultInvalidWinner() public {
        // Start the game
        vm.prank(BACKEND);
        gameImpl.startGame();
        
        // Submit with invalid winner
        vm.prank(BACKEND);
        vm.expectRevert();
        gameImpl.submitGameResult(RANDOM_USER, 10, "completed");
    }
    
    // Test game cancellation
    function testCancelGame() public {
        // Cancel from backend
        vm.prank(BACKEND);
        gameImpl.cancelGame();
        
        // Check state has changed to Cancelled
        assertEq(uint256(gameImpl.state()), uint256(BattleshipGameImplementation.GameState.Cancelled));
    }
    
    // Test that factory can also cancel game
    function testCancelGameFromFactory() public {
        // Cancel from factory
        vm.prank(FACTORY);
        gameImpl.cancelGame();
        
        // Check state has changed to Cancelled
        assertEq(uint256(gameImpl.state()), uint256(BattleshipGameImplementation.GameState.Cancelled));
    }
    
    // Test that random users can't cancel games
    function test_RevertWhen_CancelGameNotAuthorized() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        gameImpl.cancelGame();
    }
    
    // Test that completed games can't be cancelled
    function test_RevertWhen_CancelCompletedGame() public {
        // First, start and complete the game
        vm.prank(BACKEND);
        gameImpl.startGame();
        
        vm.prank(BACKEND);
        gameImpl.submitGameResult(PLAYER1, 10, "completed");
        
        // Try to cancel after completion
        vm.prank(BACKEND);
        vm.expectRevert();
        gameImpl.cancelGame();
    }
    
    // Test updating backend address
    function testUpdateBackend() public {
        address newBackend = address(0x6);
        
        // Update backend address
        vm.prank(FACTORY);
        gameImpl.updateBackend(newBackend);
        
        // Check backend is updated
        assertEq(gameImpl.backend(), newBackend);
        
        // Check roles are updated
        assertFalse(gameImpl.hasRole(gameImpl.BACKEND_ROLE(), BACKEND));
        assertTrue(gameImpl.hasRole(gameImpl.BACKEND_ROLE(), newBackend));
    }
    
    // Test that only admin can update backend
    function test_RevertWhen_UpdateBackendNotAdmin() public {
        address newBackend = address(0x6);
        
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        gameImpl.updateBackend(newBackend);
    }
    
    // Test get game duration
    function testGetGameDuration() public {
        // Should return 0 when game hasn't started
        assertEq(gameImpl.getGameDuration(), 0);
        
        // Start game
        vm.prank(BACKEND);
        gameImpl.startGame();
        
        // Should still return 0 if not completed
        assertEq(gameImpl.getGameDuration(), 0);
        
        // Warp time forward
        vm.warp(block.timestamp + 100);
        
        // Complete game
        vm.prank(BACKEND);
        gameImpl.submitGameResult(PLAYER1, 10, "completed");
        
        // Should return correct duration
        assertEq(gameImpl.getGameDuration(), 100);
    }
    
    // Test isPlayer function
    function testIsPlayer() public {
        assertTrue(gameImpl.isPlayer(PLAYER1));
        assertTrue(gameImpl.isPlayer(PLAYER2));
        assertFalse(gameImpl.isPlayer(BACKEND));
        assertFalse(gameImpl.isPlayer(RANDOM_USER));
    }
    
    // Test getGameInfo function
    function testGetGameInfo() public {
        // Get game info
        (
            uint256 id, 
            address p1, 
            address p2, 
            BattleshipGameImplementation.GameState currentState, 
            uint256 created, 
            BattleshipGameImplementation.GameResult memory result
        ) = gameImpl.getGameInfo();
        
        // Check values
        assertEq(id, GAME_ID);
        assertEq(p1, PLAYER1);
        assertEq(p2, PLAYER2);
        assertEq(uint256(currentState), uint256(BattleshipGameImplementation.GameState.Created));
        assertEq(created, gameImpl.createdAt());
        assertEq(result.winner, address(0));
    }
    
    // Test pause functionality
    function testPause() public {
        vm.prank(FACTORY);
        gameImpl.pause();
        
        assertTrue(gameImpl.paused());
        
        vm.prank(FACTORY);
        gameImpl.unpause();
        
        assertFalse(gameImpl.paused());
    }
    
    // Test that only admin can pause/unpause
    function test_RevertWhen_PauseNotAdmin() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        gameImpl.pause();
    }
    
    // Test UUPS upgrade authorization
    function testAuthorizeUpgrade() public {
        // Implementation of _authorizeUpgrade is tested indirectly
        // by checking the modifier onlyRole(DEFAULT_ADMIN_ROLE)
        
        // First, let's verify FACTORY has the role
        assertTrue(gameImpl.hasRole(gameImpl.DEFAULT_ADMIN_ROLE(), FACTORY));
        
        // Actual upgrade would be tested in integration tests
    }
}