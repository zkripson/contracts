// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import {Test, console2} from "forge-std/Test.sol";
import {SHIPToken} from "../../src/ShipToken.sol";

contract ShipTokenTest is Test {
    // Contracts
    SHIPToken shipToken;
    
    // Test accounts
    address constant ADMIN = address(0x1);
    address constant DISTRIBUTOR = address(0x2);
    address constant PLAYER1 = address(0x3);
    address constant PLAYER2 = address(0x4);
    address constant RANDOM_USER = address(0x5);
    
    // Initial supply
    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10**18; // 1M tokens
    
    // Setup before each test
    function setUp() public {
        // Deploy the token contract
        shipToken = new SHIPToken(ADMIN, DISTRIBUTOR, INITIAL_SUPPLY);
    }
    
    // Test initialization
    function testInitialization() public {
        // Check initial values
        assertEq(shipToken.name(), "Battleship SHIP");
        assertEq(shipToken.symbol(), "SHIP");
        assertEq(shipToken.decimals(), 18);
        assertEq(shipToken.totalSupply(), INITIAL_SUPPLY);
        assertEq(shipToken.balanceOf(ADMIN), INITIAL_SUPPLY);
        assertEq(shipToken.currentDistributor(), DISTRIBUTOR);
        
        // Check roles
        assertTrue(shipToken.hasRole(shipToken.DEFAULT_ADMIN_ROLE(), ADMIN));
        assertTrue(shipToken.hasRole(shipToken.PAUSER_ROLE(), ADMIN));
        assertTrue(shipToken.hasRole(shipToken.MINTER_ROLE(), ADMIN));
        assertTrue(shipToken.hasRole(shipToken.ADMIN_ROLE(), ADMIN));
        assertTrue(shipToken.hasRole(shipToken.DISTRIBUTOR_ROLE(), DISTRIBUTOR));
        
        // Check reward parameters
        SHIPToken.RewardParams memory params = shipToken.getRewardParams();
        assertEq(params.participationReward, 10 * 10**18); // 10 SHIP
        assertEq(params.victoryBonus, 25 * 10**18); // 25 SHIP
        assertEq(params.rewardCooldown, 5 minutes);
        assertEq(params.maxRewardsPerDay, 100 * 10**18); // 100 SHIP
    }
    
    // Test minting game reward
    function testMintGameReward() public {
        uint256 participationReward = shipToken.participationReward();
        
        // Mint reward for non-winner
        vm.prank(DISTRIBUTOR);
        bool success = shipToken.mintGameReward(PLAYER1, false, 1);
        
        assertTrue(success);
        assertEq(shipToken.balanceOf(PLAYER1), participationReward);
        
        // Mint reward for winner
        uint256 victoryBonus = shipToken.victoryBonus();
        vm.prank(DISTRIBUTOR);
        success = shipToken.mintGameReward(PLAYER2, true, 2);
        
        assertTrue(success);
        assertEq(shipToken.balanceOf(PLAYER2), participationReward + victoryBonus);
    }
    
    // Test that only distributor can mint rewards
    function test_RevertWhen_MintGameRewardNotDistributor() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        shipToken.mintGameReward(PLAYER1, false, 1);
    }
    
    // Test cooldown enforcement
    function testRewardCooldown() public {
        // First mint succeeds
        vm.prank(DISTRIBUTOR);
        bool success = shipToken.mintGameReward(PLAYER1, false, 1);
        assertTrue(success);
        
        // Second mint within cooldown period fails
        vm.prank(DISTRIBUTOR);
        success = shipToken.mintGameReward(PLAYER1, false, 2);
        assertFalse(success);
        
        // Advance time past cooldown
        vm.warp(block.timestamp + 5 minutes + 1);
        
        // Now minting should succeed
        vm.prank(DISTRIBUTOR);
        success = shipToken.mintGameReward(PLAYER1, false, 3);
        assertTrue(success);
    }
    
    // Test daily reward limit
    function testDailyRewardLimit() public {
        uint256 participationReward = shipToken.participationReward();
        uint256 maxRewardsPerDay = shipToken.getRewardParams().maxRewardsPerDay;
        uint256 maxGames = maxRewardsPerDay / participationReward;
        
        // Mint rewards up to limit
        vm.startPrank(DISTRIBUTOR);
        
        // Skip cooldown for testing
        for (uint256 i = 0; i < maxGames; i++) {
            shipToken.mintGameReward(PLAYER1, false, i);
            vm.warp(block.timestamp + 5 minutes + 1); // Skip cooldown
        }
        
        vm.stopPrank();
        
        // Verify balance is at daily limit
        assertEq(shipToken.balanceOf(PLAYER1), maxRewardsPerDay);
        
        // One more should fail
        vm.prank(DISTRIBUTOR);
        bool success = shipToken.mintGameReward(PLAYER1, false, maxGames);
        assertFalse(success);
        
        // Advance time to next day
        vm.warp(block.timestamp + 1 days + 1);
        
        // Now minting should succeed again
        vm.prank(DISTRIBUTOR);
        success = shipToken.mintGameReward(PLAYER1, false, maxGames + 1);
        assertTrue(success);
    }
    
    // Test batch rewards minting
    function testMintBatchRewards() public {
        // Setup batch of rewards
        SHIPToken.BatchReward[] memory rewards = new SHIPToken.BatchReward[](2);
        rewards[0] = SHIPToken.BatchReward(PLAYER1, false, 1);
        rewards[1] = SHIPToken.BatchReward(PLAYER2, true, 2);
        
        // Mint batch rewards
        vm.prank(DISTRIBUTOR);
        (uint256 batchId, uint256 totalRewarded, uint256 successCount) = 
            shipToken.mintBatchRewards(rewards);
        
        // Verify results
        assertGt(batchId, 0);
        
        uint256 participationReward = shipToken.participationReward();
        uint256 victoryBonus = shipToken.victoryBonus();
        uint256 expectedTotal = participationReward + (participationReward + victoryBonus);
        
        assertEq(totalRewarded, expectedTotal);
        assertEq(successCount, 2);
        
        // Check player balances
        assertEq(shipToken.balanceOf(PLAYER1), participationReward);
        assertEq(shipToken.balanceOf(PLAYER2), participationReward + victoryBonus);
    }
    
    // Test batch size limits
    function test_RevertWhen_BatchTooLarge() public {
        uint256 MAX_BATCH_SIZE = 100;
        
        // Create oversized batch
        SHIPToken.BatchReward[] memory rewards = new SHIPToken.BatchReward[](MAX_BATCH_SIZE + 1);
        for (uint256 i = 0; i < MAX_BATCH_SIZE + 1; i++) {
            rewards[i] = SHIPToken.BatchReward(address(uint160(i + 100)), false, i);
        }
        
        vm.prank(DISTRIBUTOR);
        vm.expectRevert();
        shipToken.mintBatchRewards(rewards);
    }
    
    // Test empty batch
    function test_RevertWhen_EmptyBatch() public {
        SHIPToken.BatchReward[] memory rewards = new SHIPToken.BatchReward[](0);
        
        vm.prank(DISTRIBUTOR);
        vm.expectRevert();
        shipToken.mintBatchRewards(rewards);
    }
    
    // Test updating reward parameters
    function testUpdateRewardParameters() public {
        // Create new parameters
        SHIPToken.RewardParams memory newParams = SHIPToken.RewardParams({
            participationReward: 5 * 10**18, // 5 SHIP
            victoryBonus: 15 * 10**18, // 15 SHIP
            rewardCooldown: 10 minutes,
            maxRewardsPerDay: 50 * 10**18 // 50 SHIP
        });
        
        // Update parameters
        vm.prank(ADMIN);
        shipToken.updateRewardParameters(newParams);
        
        // Verify parameters were updated
        SHIPToken.RewardParams memory params = shipToken.getRewardParams();
        assertEq(params.participationReward, 5 * 10**18);
        assertEq(params.victoryBonus, 15 * 10**18);
        assertEq(params.rewardCooldown, 10 minutes);
        assertEq(params.maxRewardsPerDay, 50 * 10**18);
    }
    
    // Test that only admin can update parameters
    function test_RevertWhen_UpdateRewardParametersNotAdmin() public {
        SHIPToken.RewardParams memory newParams = SHIPToken.RewardParams({
            participationReward: 5 * 10**18,
            victoryBonus: 15 * 10**18,
            rewardCooldown: 10 minutes,
            maxRewardsPerDay: 50 * 10**18
        });
        
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        shipToken.updateRewardParameters(newParams);
    }
    
    // Test invalid reward parameters
    function test_RevertWhen_InvalidRewardParameters() public {
        // Zero participation reward
        SHIPToken.RewardParams memory newParams = SHIPToken.RewardParams({
            participationReward: 0,
            victoryBonus: 15 * 10**18,
            rewardCooldown: 10 minutes,
            maxRewardsPerDay: 50 * 10**18
        });
        
        vm.prank(ADMIN);
        vm.expectRevert();
        shipToken.updateRewardParameters(newParams);
    }
    
    // Test daily limit less than participation reward
    function test_RevertWhen_InvalidDailyLimit() public {
        SHIPToken.RewardParams memory newParams = SHIPToken.RewardParams({
            participationReward: 10 * 10**18,
            victoryBonus: 15 * 10**18,
            rewardCooldown: 10 minutes,
            maxRewardsPerDay: 5 * 10**18 // Less than participation reward
        });
        
        vm.prank(ADMIN);
        vm.expectRevert();
        shipToken.updateRewardParameters(newParams);
    }
    
    // Test setting distributor
    function testSetDistributor() public {
        address newDistributor = address(0x6);
        
        vm.prank(ADMIN);
        shipToken.setDistributor(newDistributor);
        
        assertEq(shipToken.currentDistributor(), newDistributor);
        
        // Check roles are updated
        assertFalse(shipToken.hasRole(shipToken.DISTRIBUTOR_ROLE(), DISTRIBUTOR));
        assertTrue(shipToken.hasRole(shipToken.DISTRIBUTOR_ROLE(), newDistributor));
    }
    
    // Test that only admin can set distributor
    function test_RevertWhen_SetDistributorNotAdmin() public {
        address newDistributor = address(0x6);
        
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        shipToken.setDistributor(newDistributor);
    }
    
    // Test setting distributor to zero address
    function test_RevertWhen_SetDistributorZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        shipToken.setDistributor(address(0));
    }
    
    // Test pause functionality
    function testPause() public {
        // Transfer some tokens to test pausing
        vm.prank(ADMIN);
        shipToken.transfer(PLAYER1, 100 * 10**18);
        
        // Pause the contract
        vm.prank(ADMIN);
        shipToken.pause();
        
        assertTrue(shipToken.paused());
        
        // Verify cannot transfer when paused
        vm.expectRevert("Pausable: paused");
        vm.prank(PLAYER1);
        shipToken.transfer(PLAYER2, 50 * 10**18);
        
        // Unpause
        vm.prank(ADMIN);
        shipToken.unpause();
        
        assertFalse(shipToken.paused());
        
        // Can transfer again
        vm.prank(PLAYER1);
        shipToken.transfer(PLAYER2, 50 * 10**18);
        assertEq(shipToken.balanceOf(PLAYER2), 50 * 10**18);
    }
    
    // Test that only pauser can pause/unpause
    function test_RevertWhen_PauseNotPauser() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        shipToken.pause();
    }
    
    // Test admin mint function
    function testMint() public {
        vm.prank(ADMIN);
        shipToken.mint(PLAYER1, 100 * 10**18);
        
        assertEq(shipToken.balanceOf(PLAYER1), 100 * 10**18);
    }
    
    // Test that only minter can mint
    function test_RevertWhen_MintNotMinter() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        shipToken.mint(PLAYER1, 100 * 10**18);
    }
    
    // Test emergency withdraw
    function testEmergencyWithdraw() public {
        // Send ETH to contract
        vm.deal(address(shipToken), 1 ether);
        
        // Check balance before
        uint256 adminBalanceBefore = address(ADMIN).balance;
        
        // Withdraw ETH
        vm.prank(ADMIN);
        shipToken.emergencyWithdraw(address(0), 1 ether);
        
        // Check balances after
        assertEq(address(shipToken).balance, 0);
        assertEq(address(ADMIN).balance, adminBalanceBefore + 1 ether);
        
        // Test withdrawing ERC20 tokens
        vm.prank(ADMIN);
        shipToken.transfer(address(shipToken), 100 * 10**18);
        
        vm.prank(ADMIN);
        shipToken.emergencyWithdraw(address(shipToken), 100 * 10**18);
        
        assertEq(shipToken.balanceOf(address(shipToken)), 0);
        // Admin balance would be original supply minus what was just transferred
    }
    
    // Test that only admin can emergency withdraw
    function test_RevertWhen_EmergencyWithdrawNotAdmin() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        shipToken.emergencyWithdraw(address(0), 1 ether);
    }
    
    // Test can receive reward check
    function testCanReceiveReward() public {
        // Initially should be able to receive
        (bool canReceive, string memory reason) = shipToken.canReceiveReward(PLAYER1);
        assertTrue(canReceive);
        assertEq(reason, "");
        
        // After receiving, should hit cooldown
        vm.prank(DISTRIBUTOR);
        shipToken.mintGameReward(PLAYER1, false, 1);
        
        (canReceive, reason) = shipToken.canReceiveReward(PLAYER1);
        assertFalse(canReceive);
        assertEq(reason, "Cooldown active");
        
        // Skip cooldown
        vm.warp(block.timestamp + 5 minutes + 1);
        
        (canReceive, reason) = shipToken.canReceiveReward(PLAYER1);
        assertTrue(canReceive);
        
        // Test daily limit
        uint256 participationReward = shipToken.participationReward();
        uint256 maxRewardsPerDay = shipToken.getRewardParams().maxRewardsPerDay;
        uint256 maxGames = maxRewardsPerDay / participationReward;
        
        vm.startPrank(DISTRIBUTOR);
        
        for (uint256 i = 0; i < maxGames; i++) {
            shipToken.mintGameReward(PLAYER1, false, i + 2);
            vm.warp(block.timestamp + 5 minutes + 1); // Skip cooldown
        }
        
        vm.stopPrank();
        
        (canReceive, reason) = shipToken.canReceiveReward(PLAYER1);
        assertFalse(canReceive);
        assertEq(reason, "Daily limit would be exceeded");
    }
    
    // Test daily reward status
    function testGetDailyRewardStatus() public {
        // Initially zero
        (uint256 dailyRewardsUsed, uint256 resetTime) = shipToken.getDailyRewardStatus(PLAYER1);
        assertEq(dailyRewardsUsed, 0);
        assertEq(resetTime, 0); // No rewards yet, so no reset time
        
        // After receiving reward
        uint256 participationReward = shipToken.participationReward();
        
        vm.prank(DISTRIBUTOR);
        shipToken.mintGameReward(PLAYER1, false, 1);
        
        (dailyRewardsUsed, resetTime) = shipToken.getDailyRewardStatus(PLAYER1);
        assertEq(dailyRewardsUsed, participationReward);
        assertEq(resetTime, block.timestamp + 1 days);
        
        // After reset time
        vm.warp(block.timestamp + 1 days + 1);
        
        (dailyRewardsUsed, resetTime) = shipToken.getDailyRewardStatus(PLAYER1);
        assertEq(dailyRewardsUsed, 0); // Reset to zero
    }
}