// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import { Test, console } from "forge-std/Test.sol";
import "../../src/BattleshipGameImplementation.sol";
import "../../src/factories/GameFactory.sol";
import "../../src/libraries/GameStorage.sol";
import "../../src/interfaces/IVerifiers.sol";

/**
 * @title MockVerifier
 * @notice Mock implementation of the verifier interfaces for testing
 */
contract MockVerifier is IBoardPlacementVerifier, IShotResultVerifier, IGameEndVerifier {
    /// @notice Mock verify functions that always return true
    function verify(bytes calldata, bytes32[] calldata) external pure override returns (bool) {
        return true;
    }
}

/**
 * @title BattleshipTest
 * @notice Test suite for ZK Battleship contracts
 */
contract BattleshipTest is Test {
    // Contracts
    BattleshipGameImplementation implementation;
    GameFactory factory;
    ZKVerifier zkVerifier;

    // Mock verifiers
    MockVerifier mockBoardVerifier;
    MockVerifier mockShotVerifier;
    MockVerifier mockEndVerifier;

    // Test accounts
    address admin = makeAddr("admin");
    address player1 = makeAddr("player1");
    address player2 = makeAddr("player2");

    // Game variables
    uint256 gameId;
    address gameAddress;
    BattleshipGameImplementation gameProxy;

    function setUp() public {
        // Setup with admin account
        vm.startPrank(admin);

        // Deploy mock verifiers
        mockBoardVerifier = new MockVerifier();
        mockShotVerifier = new MockVerifier();
        mockEndVerifier = new MockVerifier();

        // Deploy ZK verifier
        zkVerifier = new ZKVerifier(address(mockBoardVerifier), address(mockShotVerifier), address(mockEndVerifier));

        // Deploy implementation contract
        implementation = new BattleshipGameImplementation();

        // Deploy factory
        factory = new GameFactory(address(implementation), address(zkVerifier));

        vm.stopPrank();
    }

    /**
     * @notice Test the complete game flow
     */
    function testCompleteGameFlow() public {
        // 1. Player1 creates a game
        vm.startPrank(player1);
        gameId = factory.createGame(player2);
        vm.stopPrank();

        // Get game address and instance
        gameAddress = factory.games(gameId);
        gameProxy = BattleshipGameImplementation(gameAddress);

        // 2. Player2 joins the game
        vm.startPrank(player2);
        factory.joinGame(gameId);
        vm.stopPrank();

        // 3. Both players submit their boards
        bytes32 player1BoardCommitment = bytes32(uint256(1));
        bytes32 player2BoardCommitment = bytes32(uint256(2));

        // Player1 submits board
        vm.startPrank(player1);
        gameProxy.submitBoard(player1BoardCommitment, bytes("proof"));
        vm.stopPrank();

        // Player2 submits board
        vm.startPrank(player2);
        gameProxy.submitBoard(player2BoardCommitment, bytes("proof"));
        vm.stopPrank();

        // Verify game is in Active state
        assertEq(uint8(gameProxy.state()), uint8(BattleshipGameImplementation.GameState.Active));

        // 4. Player1 makes a shot (player1 goes first)
        vm.startPrank(player1);
        gameProxy.makeShot(0, 0);
        vm.stopPrank();

        // 5. Player2 responds with hit/miss result
        vm.startPrank(player2);
        gameProxy.submitShotResult(0, 0, true, bytes("proof"));
        vm.stopPrank();

        // Check hit and shot were recorded correctly
        assertTrue(gameProxy.hasHit(player1, 0, 0));
        assertTrue(gameProxy.hasShot(player1, 0, 0));

        // Check hit count increased for player1
        assertEq(gameProxy.getHitCount(player1), 1);

        // 6. Now it's player2's turn
        assertEq(gameProxy.currentTurn(), player2);

        // Play several more rounds to reach win condition
        // For testing purposes, we'll simulate a quick win by having player1 hit all ships
        for (uint8 i = 1; i < 17; i++) {
            uint8 x = i % 10;
            uint8 y = i / 10;

            // Player2's turn
            vm.startPrank(player2);
            gameProxy.makeShot(x, y);
            vm.stopPrank();

            // Player1 responds
            vm.startPrank(player1);
            gameProxy.submitShotResult(x, y, false, bytes("proof"));
            vm.stopPrank();

            // Player1's turn
            vm.startPrank(player1);
            gameProxy.makeShot(x, y);
            vm.stopPrank();

            // Player2 responds (with hit)
            vm.startPrank(player2);
            gameProxy.submitShotResult(x, y, true, bytes("proof"));
            vm.stopPrank();
        }

        // Player1 should have 17 hits now (win condition)
        assertEq(gameProxy.getHitCount(player1), 17);

        // 7. Player1 verifies game end
        vm.startPrank(player1);
        gameProxy.verifyGameEnd(player2BoardCommitment, bytes("proof"));
        vm.stopPrank();

        // 8. Game should be completed with player1 as winner
        assertEq(uint8(gameProxy.state()), uint8(BattleshipGameImplementation.GameState.Completed));
        assertEq(gameProxy.winner(), player1);

        // 9. Both players claim rewards
        vm.startPrank(player1);
        gameProxy.claimReward();
        vm.stopPrank();

        vm.startPrank(player2);
        gameProxy.claimReward();
        vm.stopPrank();
    }

    /**
     * @notice Test forfeit functionality
     */
    function testForfeit() public {
        // Setup a game
        vm.startPrank(player1);
        gameId = factory.createGame(player2);
        vm.stopPrank();

        gameAddress = factory.games(gameId);
        gameProxy = BattleshipGameImplementation(gameAddress);

        vm.startPrank(player2);
        factory.joinGame(gameId);
        vm.stopPrank();

        // Both players submit boards
        vm.startPrank(player1);
        gameProxy.submitBoard(bytes32(uint256(1)), bytes("proof"));
        vm.stopPrank();

        vm.startPrank(player2);
        gameProxy.submitBoard(bytes32(uint256(2)), bytes("proof"));
        vm.stopPrank();

        // Player2 forfeits
        vm.startPrank(player2);
        gameProxy.forfeit();
        vm.stopPrank();

        // Check game state
        assertEq(uint8(gameProxy.state()), uint8(BattleshipGameImplementation.GameState.Completed));
        assertEq(gameProxy.winner(), player1);
    }

    /**
     * @notice Test timeout claim
     */
    function testTimeoutClaim() public {
        // Setup a game
        vm.startPrank(player1);
        gameId = factory.createGame(player2);
        vm.stopPrank();

        gameAddress = factory.games(gameId);
        gameProxy = BattleshipGameImplementation(gameAddress);

        vm.startPrank(player2);
        factory.joinGame(gameId);
        vm.stopPrank();

        // Both players submit boards
        vm.startPrank(player1);
        gameProxy.submitBoard(bytes32(uint256(1)), bytes("proof"));
        vm.stopPrank();

        vm.startPrank(player2);
        gameProxy.submitBoard(bytes32(uint256(2)), bytes("proof"));
        vm.stopPrank();

        // Player1 makes a move
        vm.startPrank(player1);
        gameProxy.makeShot(0, 0);
        vm.stopPrank();

        // Advance time past timeout
        vm.warp(block.timestamp + 25 hours);

        // Player1 claims timeout win
        vm.startPrank(player1);
        gameProxy.claimTimeoutWin();
        vm.stopPrank();

        // Check game state
        assertEq(uint8(gameProxy.state()), uint8(BattleshipGameImplementation.GameState.Completed));
        assertEq(gameProxy.winner(), player1);
    }

    /**
     * @notice Test access controls
     */
    function testAccessControls() public {
        // Setup a game
        vm.startPrank(player1);
        gameId = factory.createGame(player2);
        vm.stopPrank();

        gameAddress = factory.games(gameId);
        gameProxy = BattleshipGameImplementation(gameAddress);

        // Try to join a game as non-player
        address randomUser = makeAddr("random");
        vm.startPrank(randomUser);
        vm.expectRevert();
        factory.joinGame(gameId);
        vm.stopPrank();

        // Try to submit a board as non-player
        vm.startPrank(randomUser);
        vm.expectRevert();
        gameProxy.submitBoard(bytes32(uint256(1)), bytes("proof"));
        vm.stopPrank();

        // Submit boards from real players to activate the game
        vm.startPrank(player1);
        gameProxy.submitBoard(bytes32(uint256(1)), bytes("proof"));
        vm.stopPrank();

        vm.startPrank(player2);
        gameProxy.submitBoard(bytes32(uint256(2)), bytes("proof"));
        vm.stopPrank();

        // Try to make a shot as non-player
        vm.startPrank(randomUser);
        vm.expectRevert();
        gameProxy.makeShot(0, 0);
        vm.stopPrank();

        // Try to make a shot when it's not your turn (player2's attempt)
        vm.startPrank(player2);
        vm.expectRevert();
        gameProxy.makeShot(0, 0);
        vm.stopPrank();

        // Try to forfeit as non-player
        vm.startPrank(randomUser);
        vm.expectRevert();
        gameProxy.forfeit();
        vm.stopPrank();
    }

    /**
     * @notice Test upgrade mechanism
     */
    function testUpgrade() public {
        // Deploy a new implementation
        vm.startPrank(admin);
        BattleshipGameImplementation newImplementation = new BattleshipGameImplementation();

        // Update the implementation in factory
        factory.setImplementation(address(newImplementation));
        vm.stopPrank();

        // Create a new game that should use the new implementation
        vm.startPrank(player1);
        uint256 newGameId = factory.createGame(player2);
        vm.stopPrank();

        address newGameAddress = factory.games(newGameId);
        BattleshipGameImplementation newGameProxy = BattleshipGameImplementation(newGameAddress);

        // Check version - should be the same in this test, but in a real upgrade would be different
        assertEq(newGameProxy.VERSION(), "1.0.0");

        // Verify the game was initialized correctly
        assertEq(newGameProxy.player1(), player1);
        assertEq(newGameProxy.player2(), player2);
    }

    /**
     * @notice Test the bit-packed storage functions
     */
    function testBitPackedStorage() public {
        // Setup a game
        vm.startPrank(player1);
        gameId = factory.createGame(player2);
        vm.stopPrank();

        gameAddress = factory.games(gameId);
        gameProxy = BattleshipGameImplementation(gameAddress);

        vm.startPrank(player2);
        factory.joinGame(gameId);
        vm.stopPrank();

        // Both players submit boards
        vm.startPrank(player1);
        gameProxy.submitBoard(bytes32(uint256(1)), bytes("proof"));
        vm.stopPrank();

        vm.startPrank(player2);
        gameProxy.submitBoard(bytes32(uint256(2)), bytes("proof"));
        vm.stopPrank();

        // Make some shots to test storage
        // Player1 shoots at various positions
        vm.startPrank(player1);
        gameProxy.makeShot(0, 0);
        vm.stopPrank();

        vm.startPrank(player2);
        gameProxy.submitShotResult(0, 0, true, bytes("proof"));
        vm.stopPrank();

        vm.startPrank(player2);
        gameProxy.makeShot(1, 1);
        vm.stopPrank();

        vm.startPrank(player1);
        gameProxy.submitShotResult(1, 1, false, bytes("proof"));
        vm.stopPrank();

        vm.startPrank(player1);
        gameProxy.makeShot(2, 2);
        vm.stopPrank();

        vm.startPrank(player2);
        gameProxy.submitShotResult(2, 2, true, bytes("proof"));
        vm.stopPrank();

        // Test that the storage is working correctly
        assertTrue(gameProxy.hasShot(player1, 0, 0));
        assertTrue(gameProxy.hasHit(player1, 0, 0));

        assertTrue(gameProxy.hasShot(player2, 1, 1));
        assertFalse(gameProxy.hasHit(player2, 1, 1));

        assertTrue(gameProxy.hasShot(player1, 2, 2));
        assertTrue(gameProxy.hasHit(player1, 2, 2));

        // Check that non-shot positions return false
        assertFalse(gameProxy.hasShot(player1, 3, 3));
        assertFalse(gameProxy.hasHit(player1, 3, 3));

        // Check hit count
        assertEq(gameProxy.getHitCount(player1), 2); // Player1 has 2 hits (0,0 and 2,2)
        assertEq(gameProxy.getHitCount(player2), 0); // Player2 has no hits
    }
}
