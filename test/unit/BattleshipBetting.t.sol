// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import {Test, console2} from "forge-std/Test.sol";
import {BattleshipBetting} from "../../src/Betting.sol";
import {GameFactoryWithStats} from "../../src/factories/GameFactory.sol";
import {BattleshipGameImplementation} from "../../src/BattleshipGameImplementation.sol";
import {BattleshipStatistics} from "../../src/BattleshipStatistics.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock USDC token for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// Mock GameFactory to handle createGame calls
contract MockGameFactory {
    uint256 private nextGameId = 1;
    mapping(uint256 => bool) public games;

    function createGame(address, address) external returns (uint256) {
        uint256 gameId = nextGameId++;
        games[gameId] = true;
        return gameId;
    }
}

contract BattleshipBettingTest is Test {
    // Contracts
    BattleshipBetting betting;
    MockUSDC usdc;
    MockGameFactory mockFactory;

    // Test accounts
    address constant ADMIN = address(0x1);
    address constant BACKEND = address(0x2);
    address constant TREASURY = address(0x3);
    address constant PLAYER1 = address(0x4);
    address constant PLAYER2 = address(0x5);
    address constant PLAYER3 = address(0x6);
    address constant RANDOM_USER = address(0x7);

    // Constants
    uint256 constant MIN_STAKE = 1 * 10 ** 6; // $1 USDC
    uint256 constant MAX_STAKE = 10_000 * 10 ** 6; // $10,000 USDC
    uint256 constant STANDARD_STAKE = 100 * 10 ** 6; // $100 USDC

    // Events
    event InviteCreated(uint256 indexed inviteId, address indexed creator, uint256 stakeAmount);
    event InviteAccepted(uint256 indexed inviteId, address indexed acceptor);
    event GameCreated(uint256 indexed gameId, uint256 indexed inviteId, address indexed playerA, address playerB);
    event GameResolved(uint256 indexed gameId, address indexed winner, uint256 winnerPayout, uint256 platformFee);
    event InviteCancelled(uint256 indexed inviteId, address indexed creator, uint256 stakeAmount);
    event InviteExpired(uint256 indexed inviteId, address indexed creator, uint256 stakeAmount);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    function setUp() public {
        // Deploy mock contracts
        usdc = new MockUSDC();
        mockFactory = new MockGameFactory();

        // Deploy betting contract
        betting = new BattleshipBetting(address(usdc), address(mockFactory), TREASURY, BACKEND, ADMIN);

        // Mint USDC to test players
        usdc.mint(PLAYER1, MAX_STAKE * 2);
        usdc.mint(PLAYER2, MAX_STAKE * 2);
        usdc.mint(PLAYER3, MAX_STAKE * 2);

        // Approve betting contract to spend USDC
        vm.prank(PLAYER1);
        usdc.approve(address(betting), type(uint256).max);

        vm.prank(PLAYER2);
        usdc.approve(address(betting), type(uint256).max);

        vm.prank(PLAYER3);
        usdc.approve(address(betting), type(uint256).max);
    }

    // ==================== Initialization Tests ====================

    function testInitialization() public {
        assertEq(address(betting.usdcToken()), address(usdc));
        assertEq(address(betting.gameFactory()), address(mockFactory));
        assertEq(betting.treasury(), TREASURY);
        assertEq(betting.MIN_STAKE_AMOUNT(), MIN_STAKE);
        assertEq(betting.PLATFORM_FEE_PERCENTAGE(), 10);

        // Check roles
        assertTrue(betting.hasRole(betting.DEFAULT_ADMIN_ROLE(), ADMIN));
        assertTrue(betting.hasRole(betting.BACKEND_ROLE(), BACKEND));
        assertTrue(betting.hasRole(betting.TREASURY_ROLE(), TREASURY));
    }

    // ==================== Create Invite Tests ====================

    function testCreateInvite() public {
        uint256 initialBalance = usdc.balanceOf(PLAYER1);

        vm.prank(PLAYER1);
        vm.expectEmit(true, true, false, true);
        emit InviteCreated(1, PLAYER1, STANDARD_STAKE);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        // Check invite details
        assertEq(inviteId, 1);
        BattleshipBetting.BettingInvite memory invite = betting.getBettingInvite(inviteId);
        assertEq(invite.id, inviteId);
        assertEq(invite.creator, PLAYER1);
        assertEq(invite.stakeAmount, STANDARD_STAKE);
        assertEq(uint256(invite.betStatus), uint256(BattleshipBetting.BetStatus.Open));
        assertEq(uint256(invite.gameStatus), uint256(BattleshipBetting.GameStatus.CREATED));

        // Check funds were escrowed
        assertEq(usdc.balanceOf(PLAYER1), initialBalance - STANDARD_STAKE);
        assertEq(usdc.balanceOf(address(betting)), STANDARD_STAKE);

        // Check player invites tracking
        uint256[] memory playerInvites = betting.getPlayerInvites(PLAYER1);
        assertEq(playerInvites.length, 1);
        assertEq(playerInvites[0], inviteId);
    }

    function test_RevertWhen_CreateInviteStakeTooLow() public {
        vm.prank(PLAYER1);
        vm.expectRevert(BattleshipBetting.InvalidStakeAmount.selector);
        betting.createInvite(MIN_STAKE - 1, PLAYER1);
    }

    function test_RevertWhen_CreateInviteInsufficientBalance() public {
        // Drain player1's balance (also revoke approval to avoid ERC20 error)
        vm.startPrank(PLAYER1);
        usdc.approve(address(betting), 0); // Revoke approval first
        usdc.transfer(address(0xdead), usdc.balanceOf(PLAYER1));
        usdc.approve(address(betting), type(uint256).max); // Re-approve
        vm.stopPrank();

        vm.prank(PLAYER1);
        vm.expectRevert(BattleshipBetting.InsufficientBalance.selector);
        betting.createInvite(STANDARD_STAKE, PLAYER1);
    }

    function testCreateInviteWhenPaused() public {
        // Pause the contract
        vm.prank(ADMIN);
        betting.pause();

        vm.prank(PLAYER1);
        vm.expectRevert(); // Generic revert when paused
        betting.createInvite(STANDARD_STAKE, PLAYER1);
    }

    // ==================== Accept Invite Tests ====================

    function testAcceptInvite() public {
        // First create an invite
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        uint256 initialP2Balance = usdc.balanceOf(PLAYER2);

        // Accept the invite
        vm.prank(PLAYER2);
        vm.expectEmit(true, true, false, false);
        emit InviteAccepted(inviteId, PLAYER2);
        betting.acceptInvite(inviteId, PLAYER2);

        // Check invite status
        BattleshipBetting.BettingInvite memory invite = betting.getBettingInvite(inviteId);
        assertEq(invite.acceptor, PLAYER2);
        assertEq(uint256(invite.betStatus), uint256(BattleshipBetting.BetStatus.Matched));

        // Check funds were escrowed
        assertEq(usdc.balanceOf(PLAYER2), initialP2Balance - STANDARD_STAKE);
        assertEq(usdc.balanceOf(address(betting)), STANDARD_STAKE * 2);

        // Check player invites tracking
        uint256[] memory playerInvites = betting.getPlayerInvites(PLAYER2);
        assertEq(playerInvites.length, 1);
        assertEq(playerInvites[0], inviteId);
    }

    function test_RevertWhen_AcceptNonExistentInvite() public {
        vm.prank(PLAYER2);
        vm.expectRevert(BattleshipBetting.InviteNotFound.selector);
        betting.acceptInvite(999, PLAYER2);
    }

    function test_RevertWhen_AcceptOwnInvite() public {
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        vm.prank(PLAYER1);
        vm.expectRevert(BattleshipBetting.SamePlayerNotAllowed.selector);
        betting.acceptInvite(inviteId, PLAYER1);
    }

    function test_RevertWhen_AcceptAlreadyMatchedInvite() public {
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId, PLAYER2);

        vm.prank(PLAYER3);
        vm.expectRevert(BattleshipBetting.InvalidInviteStatus.selector);
        betting.acceptInvite(inviteId, PLAYER3);
    }

    function test_RevertWhen_AcceptExpiredInvite() public {
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        // Time travel past timeout
        vm.warp(block.timestamp + betting.INVITE_TIMEOUT() + 1);

        vm.prank(PLAYER2);
        vm.expectRevert(BattleshipBetting.NotExpired.selector);
        betting.acceptInvite(inviteId, PLAYER2);
    }

    function test_RevertWhen_AcceptWithInsufficientBalance() public {
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        // Drain player2's balance (also revoke approval to avoid ERC20 error)
        vm.startPrank(PLAYER2);
        usdc.approve(address(betting), 0); // Revoke approval first
        usdc.transfer(address(0xdead), usdc.balanceOf(PLAYER2));
        usdc.approve(address(betting), type(uint256).max); // Re-approve
        vm.stopPrank();

        vm.prank(PLAYER2);
        vm.expectRevert(BattleshipBetting.InsufficientBalance.selector);
        betting.acceptInvite(inviteId, PLAYER2);
    }

    // ==================== Create Game Tests ====================

    function testCreateGame() public {
        // Create and accept invite
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId, PLAYER2);

        // Create game
        vm.prank(BACKEND);
        vm.expectEmit(true, true, true, true);
        emit GameCreated(1, inviteId, PLAYER1, PLAYER2);
        uint256 gameId = betting.createGame(inviteId);

        assertEq(gameId, 1);

        // Check invite status
        BattleshipBetting.BettingInvite memory invite = betting.getBettingInvite(inviteId);
        assertEq(invite.gameId, gameId);
        assertEq(uint256(invite.betStatus), uint256(BattleshipBetting.BetStatus.Escrowed));
        assertEq(uint256(invite.gameStatus), uint256(BattleshipBetting.GameStatus.WAITING));

        // Check game mapping
        assertEq(betting.gameIdToBettingInvite(gameId), inviteId);
    }

    function test_RevertWhen_CreateGameNotBackend() public {
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId, PLAYER2);

        vm.prank(RANDOM_USER);
        vm.expectRevert();
        betting.createGame(inviteId);
    }

    function test_RevertWhen_CreateGameNotMatched() public {
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        vm.prank(BACKEND);
        vm.expectRevert(BattleshipBetting.InvalidInviteStatus.selector);
        betting.createGame(inviteId);
    }

    // ==================== Resolve Game Tests ====================

    function testResolveGameWithWinner() public {
        // Setup: Create invite, accept, and create game
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId, PLAYER2);

        vm.prank(BACKEND);
        uint256 gameId = betting.createGame(inviteId);

        uint256 totalPool = STANDARD_STAKE * 2;
        uint256 platformFee = (totalPool * betting.PLATFORM_FEE_PERCENTAGE()) / 100;
        uint256 winnerPayout = totalPool - platformFee;

        uint256 treasuryBalanceBefore = usdc.balanceOf(TREASURY);
        uint256 player1BalanceBefore = usdc.balanceOf(PLAYER1);

        // Resolve with PLAYER1 as winner
        vm.prank(BACKEND);
        vm.expectEmit(true, true, false, true);
        emit GameResolved(gameId, PLAYER1, winnerPayout, platformFee);
        betting.resolveGame(gameId, PLAYER1);

        // Check balances
        assertEq(usdc.balanceOf(PLAYER1), player1BalanceBefore + winnerPayout);
        assertEq(usdc.balanceOf(TREASURY), treasuryBalanceBefore + platformFee);
        assertEq(usdc.balanceOf(address(betting)), 0);

        // Check invite status
        BattleshipBetting.BettingInvite memory invite = betting.getBettingInvite(inviteId);
        assertEq(uint256(invite.betStatus), uint256(BattleshipBetting.BetStatus.Resolved));
        assertEq(uint256(invite.gameStatus), uint256(BattleshipBetting.GameStatus.COMPLETED));
        assertTrue(invite.fundsDistributed);
    }

    function testResolveGameAsDraw() public {
        // Setup: Create invite, accept, and create game
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId, PLAYER2);

        vm.prank(BACKEND);
        uint256 gameId = betting.createGame(inviteId);

        uint256 p1BalanceBefore = usdc.balanceOf(PLAYER1);
        uint256 p2BalanceBefore = usdc.balanceOf(PLAYER2);

        // Resolve as draw
        vm.prank(BACKEND);
        vm.expectEmit(true, true, false, true);
        emit GameResolved(gameId, address(0), 0, 0);
        betting.resolveGame(gameId, address(0));

        // Check balances - both players get their stakes back
        assertEq(usdc.balanceOf(PLAYER1), p1BalanceBefore + STANDARD_STAKE);
        assertEq(usdc.balanceOf(PLAYER2), p2BalanceBefore + STANDARD_STAKE);
        assertEq(usdc.balanceOf(address(betting)), 0);
    }

    function test_RevertWhen_ResolveInvalidWinner() public {
        // Setup
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId, PLAYER2);

        vm.prank(BACKEND);
        uint256 gameId = betting.createGame(inviteId);

        // Try to resolve with invalid winner (not one of the players)
        vm.prank(BACKEND);
        vm.expectRevert(BattleshipBetting.UnauthorizedAction.selector);
        betting.resolveGame(gameId, PLAYER3);
    }

    function test_RevertWhen_ResolveAlreadyResolved() public {
        // Setup
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId, PLAYER2);

        vm.prank(BACKEND);
        uint256 gameId = betting.createGame(inviteId);

        // Resolve once
        vm.prank(BACKEND);
        betting.resolveGame(gameId, PLAYER1);

        // Try to resolve again - Since bet status is now Resolved, it will fail with InvalidInviteStatus
        vm.prank(BACKEND);
        vm.expectRevert(BattleshipBetting.InvalidInviteStatus.selector);
        betting.resolveGame(gameId, PLAYER1);
    }

    function test_RevertWhen_ResolveNotBackend() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        betting.resolveGame(1, PLAYER1);
    }

    // ==================== Cancel Invite Tests ====================

    function testCancelInvite() public {
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        uint256 balanceBefore = usdc.balanceOf(PLAYER1);

        vm.prank(PLAYER1);
        vm.expectEmit(true, true, false, true);
        emit InviteCancelled(inviteId, PLAYER1, STANDARD_STAKE);
        betting.cancelInvite(inviteId, PLAYER1);

        // Check invite status
        BattleshipBetting.BettingInvite memory invite = betting.getBettingInvite(inviteId);
        assertEq(uint256(invite.betStatus), uint256(BattleshipBetting.BetStatus.Cancelled));

        // Check funds returned
        assertEq(usdc.balanceOf(PLAYER1), balanceBefore + STANDARD_STAKE);
        assertEq(usdc.balanceOf(address(betting)), 0);
    }

    function test_RevertWhen_CancelInviteNotCreator() public {
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        vm.prank(PLAYER2);
        vm.expectRevert(BattleshipBetting.UnauthorizedAction.selector);
        betting.cancelInvite(inviteId, PLAYER2);
    }

    function test_RevertWhen_CancelMatchedInvite() public {
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId, PLAYER2);

        vm.prank(PLAYER1);
        vm.expectRevert(BattleshipBetting.InvalidInviteStatus.selector);
        betting.cancelInvite(inviteId, PLAYER1);
    }

    // ==================== Handle Expired Invite Tests ====================

    function testHandleExpiredInvite() public {
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        // Time travel past timeout
        vm.warp(block.timestamp + betting.INVITE_TIMEOUT() + 1);

        uint256 balanceBefore = usdc.balanceOf(PLAYER1);

        // Anyone can handle expired invite
        vm.prank(RANDOM_USER);
        vm.expectEmit(true, true, false, true);
        emit InviteExpired(inviteId, PLAYER1, STANDARD_STAKE);
        betting.handleExpiredInvite(inviteId);

        // Check invite status
        BattleshipBetting.BettingInvite memory invite = betting.getBettingInvite(inviteId);
        assertEq(uint256(invite.betStatus), uint256(BattleshipBetting.BetStatus.Expired));

        // Check funds returned
        assertEq(usdc.balanceOf(PLAYER1), balanceBefore + STANDARD_STAKE);
        assertEq(usdc.balanceOf(address(betting)), 0);
    }

    function test_RevertWhen_HandleExpiredNotExpired() public {
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        vm.prank(RANDOM_USER);
        vm.expectRevert(BattleshipBetting.NotExpired.selector);
        betting.handleExpiredInvite(inviteId);
    }

    // ==================== View Function Tests ====================

    function testGetGameBettingInfo() public {
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId, PLAYER2);

        vm.prank(BACKEND);
        uint256 gameId = betting.createGame(inviteId);

        (uint256 returnedInviteId, uint256 totalPool, bool resolved) = betting.getGameBettingInfo(gameId);

        assertEq(returnedInviteId, inviteId);
        assertEq(totalPool, STANDARD_STAKE * 2);
        assertFalse(resolved);

        // Resolve and check again
        vm.prank(BACKEND);
        betting.resolveGame(gameId, PLAYER1);

        (, , bool resolvedAfter) = betting.getGameBettingInfo(gameId);
        assertTrue(resolvedAfter);
    }

    function testIsInviteExpired() public {
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        assertFalse(betting.isInviteExpired(inviteId));

        // Time travel
        vm.warp(block.timestamp + betting.INVITE_TIMEOUT() + 1);

        assertTrue(betting.isInviteExpired(inviteId));
    }

    // ==================== Admin Function Tests ====================

    function testSetTreasury() public {
        address newTreasury = address(0x8);

        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, false);
        emit TreasuryUpdated(TREASURY, newTreasury);
        betting.setTreasury(newTreasury);

        assertEq(betting.treasury(), newTreasury);
        assertFalse(betting.hasRole(betting.TREASURY_ROLE(), TREASURY));
        assertTrue(betting.hasRole(betting.TREASURY_ROLE(), newTreasury));
    }

    function test_RevertWhen_SetTreasuryNotAdmin() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        betting.setTreasury(address(0x8));
    }

    function test_RevertWhen_SetTreasuryZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert("Invalid treasury address");
        betting.setTreasury(address(0));
    }

    function testPauseUnpause() public {
        assertFalse(betting.paused());

        vm.prank(ADMIN);
        betting.pause();
        assertTrue(betting.paused());

        vm.prank(ADMIN);
        betting.unpause();
        assertFalse(betting.paused());
    }

    function testEmergencyWithdraw() public {
        // Send some USDC to the contract directly
        usdc.mint(address(betting), 1000 * 10 ** 6);

        uint256 balanceBefore = usdc.balanceOf(ADMIN);

        vm.prank(ADMIN);
        betting.emergencyWithdraw(address(usdc), 1000 * 10 ** 6);

        assertEq(usdc.balanceOf(ADMIN), balanceBefore + 1000 * 10 ** 6);
    }

    // ==================== Integration Tests ====================

    function testFullGameFlow() public {
        // Create invite
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE, PLAYER1);

        // Accept invite
        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId, PLAYER2);

        // Create game
        vm.prank(BACKEND);
        uint256 gameId = betting.createGame(inviteId);

        // Resolve game with winner
        vm.prank(BACKEND);
        betting.resolveGame(gameId, PLAYER1);

        // Verify final state
        BattleshipBetting.BettingInvite memory invite = betting.getBettingInvite(inviteId);
        assertEq(uint256(invite.betStatus), uint256(BattleshipBetting.BetStatus.Resolved));
        assertTrue(invite.fundsDistributed);
        assertEq(betting.gameIdToBettingInvite(gameId), inviteId);
    }

    function testMultipleInvitesFromSamePlayer() public {
        // Player can create multiple invites
        vm.startPrank(PLAYER1);
        uint256 invite1 = betting.createInvite(STANDARD_STAKE, PLAYER1);
        uint256 invite2 = betting.createInvite(STANDARD_STAKE * 2, PLAYER1);
        vm.stopPrank();

        uint256[] memory invites = betting.getPlayerInvites(PLAYER1);
        assertEq(invites.length, 2);
        assertEq(invites[0], invite1);
        assertEq(invites[1], invite2);
    }
}
