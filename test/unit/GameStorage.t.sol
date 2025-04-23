// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import { Test, console2 } from "forge-std/Test.sol";
import { GameStorage } from "../../src/libraries/GameStorage.sol";

// Helper contract to expose library functions
contract GameStorageTestHelper {
    GameStorage.GameState internal gameState;

    function initializeGame(address player1, address player2) external {
        gameState.player1 = player1;
        gameState.player2 = player2;
        gameState.currentTurn = player1;
        gameState.gameState = 0; // Created
    }

    function storeBoard(address player, bytes32 boardCommitment) external {
        GameStorage.storeBoard(gameState, player, boardCommitment);
    }

    function recordShot(address shooter, address target, uint8 x, uint8 y) external returns (bool) {
        return GameStorage.recordShot(gameState, shooter, target, x, y);
    }

    function recordHit(address target, uint8 x, uint8 y) external returns (bool) {
        return GameStorage.recordHit(gameState, target, x, y);
    }

    function isShot(address player, uint8 x, uint8 y) external view returns (bool) {
        return GameStorage.isShot(gameState, player, x, y);
    }

    function isHit(address player, uint8 x, uint8 y) external view returns (bool) {
        return GameStorage.isHit(gameState, player, x, y);
    }

    function checkAllShipsSunk(address player) external view returns (bool) {
        return GameStorage.checkAllShipsSunk(gameState, player);
    }

    function getStateFingerprint() external view returns (bytes32) {
        return GameStorage.getStateFingerprint(gameState);
    }

    function getShotHistoryHash(address player) external view returns (bytes32) {
        return GameStorage.getShotHistoryHash(gameState, player);
    }

    function coordsToBitPosition(uint8 x, uint8 y) external pure returns (uint8) {
        return GameStorage.coordsToBitPosition(x, y);
    }

    function bitPositionToCoords(uint8 pos) external pure returns (uint8 x, uint8 y) {
        return GameStorage.bitPositionToCoords(pos);
    }
}

contract GameStorageTest is Test {
    GameStorageTestHelper internal helper;
    address internal player1 = address(0x1);
    address internal player2 = address(0x2);
    bytes32 internal boardCommitment1 = bytes32(uint256(1));
    bytes32 internal boardCommitment2 = bytes32(uint256(2));

    function setUp() public {
        helper = new GameStorageTestHelper();
        helper.initializeGame(player1, player2);

        // Set up board commitments for both players
        helper.storeBoard(player1, boardCommitment1);
        helper.storeBoard(player2, boardCommitment2);
    }

    function test_CoordinateConversion() public {
        // Test corner cases
        assertEq(helper.coordsToBitPosition(0, 0), 0);
        assertEq(helper.coordsToBitPosition(9, 9), 99);

        // Test a middle case
        assertEq(helper.coordsToBitPosition(3, 4), 43);

        // Test bitPositionToCoords
        (uint8 x, uint8 y) = helper.bitPositionToCoords(43);
        assertEq(x, 3);
        assertEq(y, 4);

        // Round trip conversion
        for (uint8 i = 0; i < 10; i++) {
            for (uint8 j = 0; j < 10; j++) {
                uint8 pos = helper.coordsToBitPosition(i, j);
                (uint8 x, uint8 y) = helper.bitPositionToCoords(pos);
                assertEq(x, i);
                assertEq(y, j);
            }
        }
    }

    function test_InvalidCoordinates() public {
        // Should revert when x or y is out of bounds
        vm.expectRevert("Invalid coordinates");
        helper.coordsToBitPosition(10, 5);

        vm.expectRevert("Invalid coordinates");
        helper.coordsToBitPosition(5, 10);

        // Should revert when position is out of bounds
        vm.expectRevert("Invalid position");
        helper.bitPositionToCoords(100);
    }

    function test_RecordShot() public {
        // Record a shot from player1 to player2
        bool success = helper.recordShot(player1, player2, 3, 4);
        assertTrue(success);

        // Verify shot was recorded
        assertTrue(helper.isShot(player2, 3, 4));

        // Attempt to record the same shot again
        success = helper.recordShot(player1, player2, 3, 4);
        assertFalse(success);
    }

    function test_RecordHit() public {
        // Record a hit on player2
        bool gameOver = helper.recordHit(player2, 3, 4);

        // With only one hit, game should not be over
        assertFalse(gameOver);

        // Verify hit was recorded
        assertTrue(helper.isHit(player2, 3, 4));

        // Record all remaining hits to sink all ships
        // Total ship cells = 17 (5+4+3+3+2)
        for (uint8 i = 0; i < 16; i++) {
            uint8 x = i % 10;
            uint8 y = i / 10;

            // Skip the cell we already hit
            if (x == 3 && y == 4) continue;

            gameOver = helper.recordHit(player2, x, y);
        }

        // Now all ships should be sunk
        assertTrue(gameOver);
        assertTrue(helper.checkAllShipsSunk(player2));
    }

    function test_StateFingerprint() public {
        // Initial fingerprint
        bytes32 initialFingerprint = helper.getStateFingerprint();

        // Record a shot and hit
        helper.recordShot(player1, player2, 3, 4);
        helper.recordHit(player2, 3, 4);

        // Fingerprint should change
        bytes32 newFingerprint = helper.getStateFingerprint();
        assertTrue(initialFingerprint != newFingerprint);
    }

    function test_ShotHistoryHash() public {
        // Initial shot history hash
        bytes32 initialHash = helper.getShotHistoryHash(player2);

        // Record a shot and hit
        helper.recordShot(player1, player2, 3, 4);
        helper.recordHit(player2, 3, 4);

        // Shot history hash should change
        bytes32 newHash = helper.getShotHistoryHash(player2);
        assertTrue(initialHash != newHash);
    }

    function test_GasOptimization() public {
        uint256 gasStart;
        uint256 gasUsed;

        // Test gas usage for recordShot
        gasStart = gasleft();
        helper.recordShot(player1, player2, 3, 4);
        gasUsed = gasStart - gasleft();
        console2.log("Gas used for recordShot:", gasUsed);

        // Test gas usage for recordHit
        gasStart = gasleft();
        helper.recordHit(player2, 3, 4);
        gasUsed = gasStart - gasleft();
        console2.log("Gas used for recordHit:", gasUsed);

        // Test gas usage for checking if a position is shot
        gasStart = gasleft();
        helper.isShot(player2, 3, 4);
        gasUsed = gasStart - gasleft();
        console2.log("Gas used for isShot:", gasUsed);

        // Test gas usage for getting state fingerprint
        gasStart = gasleft();
        helper.getStateFingerprint();
        gasUsed = gasStart - gasleft();
        console2.log("Gas used for getStateFingerprint:", gasUsed);
    }
}
