// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import { Test, console } from "forge-std/Test.sol";
import "../../src/ShipToken.sol";

contract SHIPTokenTest is Test {
    SHIPToken public shipToken;

    address public admin = address(1);
    address public distributor = address(2);
    address public player1 = address(3);
    address public player2 = address(4);

    uint256 public initialSupply = 1_000_000 * 10 ** 18; // 1M tokens
    uint256 public gameId = 12_345;

    function setUp() public {
        // Deploy token
        shipToken = new SHIPToken(admin, distributor, initialSupply);

        // For testing, we need admin to grant distributor role to this test contract
        vm.startPrank(admin);
        shipToken.grantRole(shipToken.DISTRIBUTOR_ROLE(), address(this));
        vm.stopPrank();
    }

    function testInitialSetup() public {
        // Check initial token supply
        assertEq(shipToken.totalSupply(), initialSupply);
        assertEq(shipToken.balanceOf(admin), initialSupply);

        // Check roles
        assertTrue(shipToken.hasRole(shipToken.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(shipToken.hasRole(shipToken.DISTRIBUTOR_ROLE(), distributor));
        assertTrue(shipToken.hasRole(shipToken.ADMIN_ROLE(), admin));
        assertTrue(shipToken.hasRole(shipToken.MINTER_ROLE(), admin));

        // Check reward parameters
        assertEq(shipToken.participationReward(), 10 * 10 ** 18); // 10 SHIP
        assertEq(shipToken.victoryBonus(), 25 * 10 ** 18); // 25 SHIP
    }

    function testMintGameReward() public {
        // Set a zero cooldown for testing
        vm.startPrank(admin);
        shipToken.updateAbuseControls(0, 1000 * 10 ** 18);
        vm.stopPrank();

        // Mint reward to player1 (participation only)
        bool success = shipToken.mintGameReward(player1, false, gameId);
        assertTrue(success);
        assertEq(shipToken.balanceOf(player1), 10 * 10 ** 18); // 10 SHIP

        // Mint reward to player2 (with victory bonus)
        success = shipToken.mintGameReward(player2, true, gameId);
        assertTrue(success);
        assertEq(shipToken.balanceOf(player2), 35 * 10 ** 18); // 10 + 25 SHIP
    }

    function testRewardCooldown() public {
        // Set a small cooldown for testing
        vm.startPrank(admin);
        shipToken.updateAbuseControls(1, 1000 * 10 ** 18);
        vm.stopPrank();

        // First reward should succeed
        shipToken.mintGameReward(player1, false, gameId);

        // Immediate second reward should fail
        vm.expectRevert("SHIP: Reward cooldown still active");
        shipToken.mintGameReward(player1, false, gameId + 1);

        // Advance time past cooldown
        vm.warp(block.timestamp + 2); // Advance 2 seconds

        // Now reward should succeed
        bool success = shipToken.mintGameReward(player1, false, gameId + 1);
        assertTrue(success);
        assertEq(shipToken.balanceOf(player1), 20 * 10 ** 18); // 10 + 10 SHIP
    }

    function testDailyRewardLimit() public {
        // Update reward parameters to make testing easier
        vm.startPrank(admin);
        shipToken.updateRewardParameters(20 * 10 ** 18, 0); // 20 SHIP participation, no bonus
        shipToken.updateAbuseControls(0, 50 * 10 ** 18); // No cooldown, 50 SHIP daily limit
        vm.stopPrank();

        // First two rewards (20 + 20 = 40) should succeed
        shipToken.mintGameReward(player1, false, gameId); // 20 SHIP
        shipToken.mintGameReward(player1, false, gameId + 1); // 20 more SHIP
        assertEq(shipToken.balanceOf(player1), 40 * 10 ** 18);

        // Third reward would exceed daily limit (40 + 20 > 50)
        vm.expectRevert("SHIP: Daily reward limit exceeded");
        shipToken.mintGameReward(player1, false, gameId + 2);

        // Advance 1 day to reset limit
        vm.warp(block.timestamp + 1 days + 1);

        // Now reward should succeed
        bool success = shipToken.mintGameReward(player1, false, gameId + 2);
        assertTrue(success);
        assertEq(shipToken.balanceOf(player1), 60 * 10 ** 18); // 40 + 20 SHIP
    }

    function testUpdateRewardParameters() public {
        // Update reward parameters
        vm.startPrank(admin);
        shipToken.updateRewardParameters(5 * 10 ** 18, 15 * 10 ** 18);

        // Disable cooldown for testing
        shipToken.updateAbuseControls(0, 1000 * 10 ** 18);
        vm.stopPrank();

        assertEq(shipToken.participationReward(), 5 * 10 ** 18);
        assertEq(shipToken.victoryBonus(), 15 * 10 ** 18);

        // Verify new parameters are used for rewards
        shipToken.mintGameReward(player1, true, gameId);
        assertEq(shipToken.balanceOf(player1), 20 * 10 ** 18); // 5 + 15 SHIP
    }

    function testUpdateDistributor() public {
        address newDistributor = address(5);

        vm.startPrank(admin);
        shipToken.setDistributor(newDistributor);
        vm.stopPrank();

        // Original distributor should no longer have role
        assertFalse(shipToken.hasRole(shipToken.DISTRIBUTOR_ROLE(), distributor));

        // New distributor should have role
        assertTrue(shipToken.hasRole(shipToken.DISTRIBUTOR_ROLE(), newDistributor));
    }

    function testTransferFunctionality() public {
        // Disable cooldown for testing
        vm.startPrank(admin);
        shipToken.updateAbuseControls(0, 1000 * 10 ** 18);
        vm.stopPrank();

        // Mint tokens to player
        shipToken.mintGameReward(player1, true, gameId);
        uint256 initialBalance = shipToken.balanceOf(player1);

        // Player should be able to transfer tokens
        vm.startPrank(player1);
        shipToken.transfer(player2, 5 * 10 ** 18);
        vm.stopPrank();

        assertEq(shipToken.balanceOf(player1), initialBalance - 5 * 10 ** 18);
        assertEq(shipToken.balanceOf(player2), 5 * 10 ** 18);
    }

    function testPauseAndUnpause() public {
        // First ensure we can mint when not paused
        vm.startPrank(admin);
        shipToken.updateAbuseControls(0, 1000 * 10 ** 18); // No cooldown
        vm.stopPrank();

        bool success = shipToken.mintGameReward(player1, false, gameId);
        assertTrue(success);

        // Now pause the contract
        vm.prank(admin);
        shipToken.pause();

        // Check that the contract is actually paused
        assertTrue(shipToken.paused());

        // Try to mint while paused - should fail
        // Try/catch approach to verify the revert
        bool reverted = false;
        try shipToken.mintGameReward(player2, true, gameId + 1) {
            // Should not reach here
        } catch {
            // Caught an error as expected
            reverted = true;
        }
        assertTrue(reverted, "Minting should revert when paused");

        // Unpause
        vm.prank(admin);
        shipToken.unpause();

        // Verify we can mint after unpausing
        success = shipToken.mintGameReward(player2, true, gameId + 1);
        assertTrue(success);
        assertEq(shipToken.balanceOf(player2), 35 * 10 ** 18); // 10 + 25 SHIP
    }

    function testAdminMinting() public {
        uint256 amount = 50 * 10 ** 18;

        vm.startPrank(admin);
        shipToken.mint(player1, amount);
        vm.stopPrank();

        assertEq(shipToken.balanceOf(player1), amount);
    }

    function testAccessControl() public {
        // Non-admin shouldn't be able to update parameters
        vm.startPrank(player1);
        vm.expectRevert(); // AccessControl error
        shipToken.updateRewardParameters(1, 1);
        vm.stopPrank();

        // Non-distributor shouldn't be able to mint rewards
        vm.startPrank(player1);
        vm.expectRevert(); // AccessControl error
        shipToken.mintGameReward(player1, true, gameId);
        vm.stopPrank();
    }
}
