// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "../../src/BattleshipPoints.sol";

contract BattleshipPointsTest is Test {
    BattleshipPoints public points;
    
    address public owner = address(this);
    address public gameContract = address(0x1);
    address public player1 = address(0x2);
    address public player2 = address(0x3);
    address public player3 = address(0x4);
    address public player4 = address(0x5);
    address public player5 = address(0x6);
    
    event PointsAwarded(address indexed player, uint256 amount, string category, bytes32 indexed gameId);
    event WeeklyDistributionSnapshot(uint256 timestamp, uint256 totalPoints);
    event AuthorizedSourceAdded(address indexed source);
    event AuthorizedSourceRemoved(address indexed source);
    event PlayerActivated(address indexed player);

    function setUp() public {
        points = new BattleshipPoints();
        
        // Add game contract as authorized source
        points.addAuthorizedSource(gameContract);
    }

    function testInitialState() public {
        assertEq(points.owner(), owner);
        assertEq(points.weekStartTimestamp(), block.timestamp);
        assertEq(points.minimumPointsThreshold(), 100);
        assertEq(points.WEEK_DURATION(), 7 days);
        assertTrue(points.authorizedSources(owner));
    }

    function testAddAuthorizedSource() public {
        address newSource = address(0x10);
        
        vm.expectEmit(true, false, false, true);
        emit AuthorizedSourceAdded(newSource);
        
        points.addAuthorizedSource(newSource);
        assertTrue(points.authorizedSources(newSource));
    }

    function testAddAuthorizedSourceFailures() public {
        // Test zero address
        vm.expectRevert("Invalid address");
        points.addAuthorizedSource(address(0));
        
        // Test already authorized
        vm.expectRevert("Already authorized");
        points.addAuthorizedSource(gameContract);
    }

    function testRemoveAuthorizedSource() public {
        vm.expectEmit(true, false, false, true);
        emit AuthorizedSourceRemoved(gameContract);
        
        points.removeAuthorizedSource(gameContract);
        assertFalse(points.authorizedSources(gameContract));
    }

    function testRemoveAuthorizedSourceFailure() public {
        address notAuthorized = address(0x20);
        
        vm.expectRevert("Not authorized");
        points.removeAuthorizedSource(notAuthorized);
    }

    function testAwardPoints() public {
        vm.startPrank(gameContract);
        
        bytes32 gameId = keccak256("game1");
        string memory category = "GAME_WIN";
        uint256 amount = 50;
        
        vm.expectEmit(true, true, false, true);
        emit PlayerActivated(player1);
        vm.expectEmit(true, true, false, true);
        emit PointsAwarded(player1, amount, category, gameId);
        
        points.awardPoints(player1, amount, category, gameId);
        
        assertEq(points.totalPlayerPoints(player1), amount);
        assertEq(points.weeklyPlayerPoints(player1), amount);
        assertEq(points.getActivePlayerCount(), 1);
        assertTrue(points.isActiveThisWeek(player1));
        assertEq(points.getTotalPlayerCount(), 1);
        assertTrue(points.hasPlayedBefore(player1));
        
        vm.stopPrank();
    }

    function testAwardPointsMultipleTimes() public {
        vm.startPrank(gameContract);
        
        bytes32 gameId1 = keccak256("game1");
        bytes32 gameId2 = keccak256("game2");
        
        points.awardPoints(player1, 50, "GAME_WIN", gameId1);
        points.awardPoints(player1, 30, "DAILY_BONUS", gameId2);
        
        assertEq(points.totalPlayerPoints(player1), 80);
        assertEq(points.weeklyPlayerPoints(player1), 80);
        assertEq(points.getActivePlayerCount(), 1);
        
        vm.stopPrank();
    }

    function testAwardPointsFailures() public {
        vm.startPrank(gameContract);
        
        // Test zero address
        vm.expectRevert("Invalid player address");
        points.awardPoints(address(0), 50, "GAME_WIN", keccak256("game1"));
        
        // Test zero amount
        vm.expectRevert("Amount must be greater than zero");
        points.awardPoints(player1, 0, "GAME_WIN", keccak256("game1"));
        
        vm.stopPrank();
        
        // Test unauthorized - use a different address that's not authorized
        address notAuthorized = address(0x100);
        vm.startPrank(notAuthorized);
        vm.expectRevert("Not authorized");
        points.awardPoints(player1, 50, "GAME_WIN", keccak256("game1"));
        vm.stopPrank();
    }

    function testWeeklySnapshot() public {
        vm.startPrank(gameContract);
        
        // Award points to multiple players
        points.awardPoints(player1, 150, "GAME_WIN", keccak256("game1"));
        points.awardPoints(player2, 200, "GAME_WIN", keccak256("game2"));
        points.awardPoints(player3, 80, "GAME_WIN", keccak256("game3")); // Below threshold
        
        // Advance time by 1 week
        vm.warp(block.timestamp + 7 days);
        
        vm.expectEmit(true, false, false, true);
        emit WeeklyDistributionSnapshot(block.timestamp, 350); // Only player1 (150) + player2 (200)
        
        points.takeWeeklySnapshot();
        
        // Check points were reset
        assertEq(points.weeklyPlayerPoints(player1), 0);
        assertEq(points.weeklyPlayerPoints(player2), 0);
        assertEq(points.weeklyPlayerPoints(player3), 0);
        
        // Check claimable points
        assertEq(points.getClaimablePoints(player1), 150);
        assertEq(points.getClaimablePoints(player2), 200);
        assertEq(points.getClaimablePoints(player3), 0); // Below threshold
        
        // Check active players cleared
        assertEq(points.getActivePlayerCount(), 0);
        assertFalse(points.isActiveThisWeek(player1));
        assertFalse(points.isActiveThisWeek(player2));
        assertFalse(points.isActiveThisWeek(player3));
        
        // Total points should remain
        assertEq(points.totalPlayerPoints(player1), 150);
        assertEq(points.totalPlayerPoints(player2), 200);
        assertEq(points.totalPlayerPoints(player3), 80);
        
        vm.stopPrank();
    }

    function testWeeklySnapshotTooEarly() public {
        vm.startPrank(gameContract);
        
        vm.expectRevert("Week not over yet");
        points.takeWeeklySnapshot();
        
        vm.stopPrank();
    }

    function testSetMinimumPointsThreshold() public {
        uint256 newThreshold = 200;
        
        points.setMinimumPointsThreshold(newThreshold);
        assertEq(points.minimumPointsThreshold(), newThreshold);
    }

    function testGetTimeUntilNextDistribution() public {
        uint256 timeUntil = points.getTimeUntilNextDistribution();
        assertEq(timeUntil, 7 days);
        
        // Advance time
        vm.warp(block.timestamp + 3 days);
        timeUntil = points.getTimeUntilNextDistribution();
        assertEq(timeUntil, 4 days);
        
        // Advance past week end
        vm.warp(block.timestamp + 5 days);
        timeUntil = points.getTimeUntilNextDistribution();
        assertEq(timeUntil, 0);
    }

    function testGetTopPlayersByWeeklyPoints() public {
        vm.startPrank(gameContract);
        
        // Award different amounts to players
        points.awardPoints(player1, 100, "GAME_WIN", keccak256("game1"));
        points.awardPoints(player2, 500, "GAME_WIN", keccak256("game2"));
        points.awardPoints(player3, 300, "GAME_WIN", keccak256("game3"));
        points.awardPoints(player4, 400, "GAME_WIN", keccak256("game4"));
        points.awardPoints(player5, 200, "GAME_WIN", keccak256("game5"));
        
        // Get top 3 players
        (address[] memory topPlayers, uint256[] memory topPoints) = points.getTopPlayersByWeeklyPoints(3);
        
        assertEq(topPlayers.length, 3);
        assertEq(topPlayers[0], player2); // 500 points
        assertEq(topPlayers[1], player4); // 400 points
        assertEq(topPlayers[2], player3); // 300 points
        
        assertEq(topPoints[0], 500);
        assertEq(topPoints[1], 400);
        assertEq(topPoints[2], 300);
        
        vm.stopPrank();
    }

    function testGetTopPlayersByTotalPoints() public {
        vm.startPrank(gameContract);
        
        // Award points
        points.awardPoints(player1, 100, "GAME_WIN", keccak256("game1"));
        points.awardPoints(player2, 500, "GAME_WIN", keccak256("game2"));
        points.awardPoints(player3, 300, "GAME_WIN", keccak256("game3"));
        
        // Week 1 ends
        vm.warp(block.timestamp + 7 days);
        points.takeWeeklySnapshot();
        
        // Award more points in week 2
        points.awardPoints(player1, 400, "GAME_WIN", keccak256("game4")); // Total: 500
        points.awardPoints(player4, 600, "GAME_WIN", keccak256("game5")); // Total: 600
        
        // Get top 3 players by total points
        (address[] memory topPlayers, uint256[] memory topPoints) = points.getTopPlayersByTotalPoints(3);
        
        assertEq(topPlayers.length, 3);
        assertEq(topPlayers[0], player4); // 600 points
        assertEq(topPlayers[1], player1); // 500 points
        assertEq(topPlayers[2], player2); // 500 points (but added first)
        
        assertEq(topPoints[0], 600);
        assertEq(topPoints[1], 500);
        assertEq(topPoints[2], 500);
        
        vm.stopPrank();
    }

    function testGetTopPlayersWithLessThanRequested() public {
        vm.startPrank(gameContract);
        
        // Only award points to 2 players
        points.awardPoints(player1, 100, "GAME_WIN", keccak256("game1"));
        points.awardPoints(player2, 200, "GAME_WIN", keccak256("game2"));
        
        // Request top 5 players
        (address[] memory topPlayers, uint256[] memory topPoints) = points.getTopPlayersByWeeklyPoints(5);
        
        assertEq(topPlayers.length, 2);
        assertEq(topPoints.length, 2);
        
        vm.stopPrank();
    }

    function testGetTopPlayersWithNoPlayers() public {
        // Request top players when none exist
        (address[] memory topPlayers, uint256[] memory topPoints) = points.getTopPlayersByWeeklyPoints(5);
        
        assertEq(topPlayers.length, 0);
        assertEq(topPoints.length, 0);
    }

    function testMultipleWeeksFlow() public {
        vm.startPrank(gameContract);
        
        // Week 1
        points.awardPoints(player1, 150, "GAME_WIN", keccak256("game1"));
        points.awardPoints(player2, 200, "GAME_WIN", keccak256("game2"));
        
        // Get the initial week start timestamp
        uint256 weekStart = points.weekStartTimestamp();
        
        // Advance past the first week
        vm.warp(weekStart + 7 days + 1);
        points.takeWeeklySnapshot();
        
        // Week 2
        points.awardPoints(player1, 100, "GAME_WIN", keccak256("game3"));
        points.awardPoints(player3, 300, "GAME_WIN", keccak256("game4"));
        
        // Get the new week start timestamp after first snapshot
        weekStart = points.weekStartTimestamp();
        
        // Advance past the second week
        vm.warp(weekStart + 7 days + 1);
        points.takeWeeklySnapshot();
        
        // Check final state
        assertEq(points.totalPlayerPoints(player1), 250);
        assertEq(points.totalPlayerPoints(player2), 200);
        assertEq(points.totalPlayerPoints(player3), 300);
        
        assertEq(points.getClaimablePoints(player1), 250);
        assertEq(points.getClaimablePoints(player2), 200);
        assertEq(points.getClaimablePoints(player3), 300);
        
        vm.stopPrank();
    }

    function testOnlyOwnerModifiers() public {
        address notOwner = address(0x99);
        
        vm.startPrank(notOwner);
        
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        points.addAuthorizedSource(address(0x100));
        
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        points.removeAuthorizedSource(gameContract);
        
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        points.setMinimumPointsThreshold(500);
        
        vm.stopPrank();
    }

    function testOnlyAuthorizedModifiers() public {
        address notAuthorized = address(0x99);
        
        vm.startPrank(notAuthorized);
        
        vm.expectRevert("Not authorized");
        points.awardPoints(player1, 100, "GAME_WIN", keccak256("game1"));
        
        vm.expectRevert("Not authorized");
        points.takeWeeklySnapshot();
        
        vm.stopPrank();
    }
}