// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import {Test, console2} from "forge-std/Test.sol";
import {BattleshipBetting} from "../../src/Betting.sol";
import {GameFactoryWithStats} from "../../src/factories/GameFactory.sol";
import {BattleshipGameImplementation} from "../../src/BattleshipGameImplementation.sol";
import {BattleshipStatistics} from "../../src/BattleshipStatistics.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock tokens for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MockUSDT is ERC20 {
    constructor() ERC20("Tether USD", "USDT") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MockDAI is ERC20 {
    constructor() ERC20("Dai Stablecoin", "DAI") {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// Mock Game Contract
contract MockGame {
    enum GameState { WaitingForPlayers, Playing, Completed, Cancelled }
    GameState public state;
    
    constructor() {
        state = GameState.Playing; // Default to playing state for emergency refund tests
    }
    
    function setState(GameState _state) external {
        state = _state;
    }
}

// Mock GameFactory to handle createGame calls
contract MockGameFactory {
    uint256 private nextGameId = 1;
    mapping(uint256 => address) public games;

    function createGame(address, address) external returns (uint256) {
        uint256 gameId = nextGameId++;
        // Deploy a new mock game contract
        games[gameId] = address(new MockGame());
        return gameId;
    }
}

contract BattleshipBettingMultiTokenTest is Test {
    // Contracts
    BattleshipBetting betting;
    MockUSDC usdc;
    MockUSDT usdt;
    MockDAI dai;
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
    uint256 constant MIN_STAKE_USDC = 1 * 10 ** 6; // $1 USDC
    uint256 constant MIN_STAKE_USDT = 5 * 10 ** 6; // $5 USDT
    uint256 constant MIN_STAKE_DAI = 10 * 10 ** 18; // $10 DAI
    uint256 constant STANDARD_STAKE_USDC = 100 * 10 ** 6; // $100 USDC
    uint256 constant STANDARD_STAKE_USDT = 100 * 10 ** 6; // $100 USDT
    uint256 constant STANDARD_STAKE_DAI = 100 * 10 ** 18; // $100 DAI

    // Events
    event TokenWhitelisted(address indexed token, uint256 minStakeAmount);
    event TokenRemovedFromWhitelist(address indexed token);
    event TokenMinStakeUpdated(address indexed token, uint256 oldMinStake, uint256 newMinStake);
    event InviteCreated(uint256 indexed inviteId, address indexed creator, uint256 stakeAmount, address indexed token);
    event GameResolved(uint256 indexed gameId, address indexed winner, uint256 winnerPayout, uint256 platformFee);

    function setUp() public {
        // Deploy mock contracts
        usdc = new MockUSDC();
        usdt = new MockUSDT();
        dai = new MockDAI();
        mockFactory = new MockGameFactory();

        // Deploy betting contract (USDC is whitelisted by default)
        betting = new BattleshipBetting(address(usdc), address(mockFactory), TREASURY, BACKEND, ADMIN);

        // Mint tokens to test players
        usdc.mint(PLAYER1, STANDARD_STAKE_USDC * 10);
        usdc.mint(PLAYER2, STANDARD_STAKE_USDC * 10);
        usdc.mint(PLAYER3, STANDARD_STAKE_USDC * 10);

        usdt.mint(PLAYER1, STANDARD_STAKE_USDT * 10);
        usdt.mint(PLAYER2, STANDARD_STAKE_USDT * 10);
        usdt.mint(PLAYER3, STANDARD_STAKE_USDT * 10);

        dai.mint(PLAYER1, STANDARD_STAKE_DAI * 10);
        dai.mint(PLAYER2, STANDARD_STAKE_DAI * 10);
        dai.mint(PLAYER3, STANDARD_STAKE_DAI * 10);

        // Approve betting contract to spend tokens
        vm.startPrank(PLAYER1);
        usdc.approve(address(betting), type(uint256).max);
        usdt.approve(address(betting), type(uint256).max);
        dai.approve(address(betting), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(PLAYER2);
        usdc.approve(address(betting), type(uint256).max);
        usdt.approve(address(betting), type(uint256).max);
        dai.approve(address(betting), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(PLAYER3);
        usdc.approve(address(betting), type(uint256).max);
        usdt.approve(address(betting), type(uint256).max);
        dai.approve(address(betting), type(uint256).max);
        vm.stopPrank();
    }

    // ==================== Token Whitelisting Tests ====================

    function testInitialTokenWhitelisting() public {
        // USDC should be whitelisted by default
        assertTrue(betting.isTokenWhitelisted(address(usdc)));
        assertEq(betting.getTokenMinStake(address(usdc)), MIN_STAKE_USDC);

        // Other tokens should not be whitelisted initially
        assertFalse(betting.isTokenWhitelisted(address(usdt)));
        assertFalse(betting.isTokenWhitelisted(address(dai)));

        // Check whitelist array
        address[] memory whitelistedTokens = betting.getWhitelistedTokens();
        assertEq(whitelistedTokens.length, 1);
        assertEq(whitelistedTokens[0], address(usdc));
    }

    function testWhitelistNewToken() public {
        vm.prank(ADMIN);
        vm.expectEmit(true, false, false, true);
        emit TokenWhitelisted(address(usdt), MIN_STAKE_USDT);
        betting.whitelistToken(address(usdt), MIN_STAKE_USDT);

        // Check token is whitelisted
        assertTrue(betting.isTokenWhitelisted(address(usdt)));
        assertEq(betting.getTokenMinStake(address(usdt)), MIN_STAKE_USDT);

        // Check whitelist array updated
        address[] memory whitelistedTokens = betting.getWhitelistedTokens();
        assertEq(whitelistedTokens.length, 2);
        assertTrue(_arrayContains(whitelistedTokens, address(usdc)));
        assertTrue(_arrayContains(whitelistedTokens, address(usdt)));
    }

    function test_RevertWhen_WhitelistTokenNotAdmin() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        betting.whitelistToken(address(usdt), MIN_STAKE_USDT);
    }

    function test_RevertWhen_WhitelistZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(BattleshipBetting.InvalidTokenAddress.selector);
        betting.whitelistToken(address(0), MIN_STAKE_USDT);
    }

    function test_RevertWhen_WhitelistAlreadyWhitelisted() public {
        vm.prank(ADMIN);
        vm.expectRevert(BattleshipBetting.TokenAlreadyWhitelisted.selector);
        betting.whitelistToken(address(usdc), MIN_STAKE_USDC);
    }

    function test_RevertWhen_WhitelistZeroMinStake() public {
        vm.prank(ADMIN);
        vm.expectRevert(BattleshipBetting.InvalidMinStakeAmount.selector);
        betting.whitelistToken(address(usdt), 0);
    }

    function testRemoveTokenFromWhitelist() public {
        // First whitelist USDT
        vm.prank(ADMIN);
        betting.whitelistToken(address(usdt), MIN_STAKE_USDT);

        // Then remove it
        vm.prank(ADMIN);
        vm.expectEmit(true, false, false, false);
        emit TokenRemovedFromWhitelist(address(usdt));
        betting.removeTokenFromWhitelist(address(usdt));

        // Check token is no longer whitelisted
        assertFalse(betting.isTokenWhitelisted(address(usdt)));
        assertEq(betting.getTokenMinStake(address(usdt)), 0);

        // Check whitelist array updated
        address[] memory whitelistedTokens = betting.getWhitelistedTokens();
        assertEq(whitelistedTokens.length, 1);
        assertEq(whitelistedTokens[0], address(usdc));
    }

    function test_RevertWhen_RemoveTokenNotWhitelisted() public {
        vm.prank(ADMIN);
        vm.expectRevert(BattleshipBetting.TokenNotWhitelisted.selector);
        betting.removeTokenFromWhitelist(address(usdt));
    }

    function testUpdateTokenMinStake() public {
        uint256 newMinStake = MIN_STAKE_USDC * 2;

        vm.prank(ADMIN);
        vm.expectEmit(true, false, false, true);
        emit TokenMinStakeUpdated(address(usdc), MIN_STAKE_USDC, newMinStake);
        betting.updateTokenMinStake(address(usdc), newMinStake);

        assertEq(betting.getTokenMinStake(address(usdc)), newMinStake);
    }

    function test_RevertWhen_UpdateMinStakeNotWhitelisted() public {
        vm.prank(ADMIN);
        vm.expectRevert(BattleshipBetting.TokenNotWhitelisted.selector);
        betting.updateTokenMinStake(address(usdt), MIN_STAKE_USDT);
    }

    function test_RevertWhen_UpdateMinStakeToZero() public {
        vm.prank(ADMIN);
        vm.expectRevert(BattleshipBetting.InvalidMinStakeAmount.selector);
        betting.updateTokenMinStake(address(usdc), 0);
    }

    // ==================== Multi-Token Betting Tests ====================

    function testCreateInviteWithDifferentTokens() public {
        // Whitelist additional tokens
        vm.startPrank(ADMIN);
        betting.whitelistToken(address(usdt), MIN_STAKE_USDT);
        betting.whitelistToken(address(dai), MIN_STAKE_DAI);
        vm.stopPrank();

        // Create invites with different tokens
        vm.prank(PLAYER1);
        uint256 usdcInvite = betting.createInviteWithToken(STANDARD_STAKE_USDC, PLAYER1, address(usdc));

        vm.prank(PLAYER1);
        uint256 usdtInvite = betting.createInviteWithToken(STANDARD_STAKE_USDT, PLAYER1, address(usdt));

        vm.prank(PLAYER1);
        uint256 daiInvite = betting.createInviteWithToken(STANDARD_STAKE_DAI, PLAYER1, address(dai));

        // Check invite details
        BattleshipBetting.BettingInvite memory usdcInviteData = betting.getBettingInvite(usdcInvite);
        assertEq(usdcInviteData.betToken, address(usdc));
        assertEq(usdcInviteData.stakeAmount, STANDARD_STAKE_USDC);

        BattleshipBetting.BettingInvite memory usdtInviteData = betting.getBettingInvite(usdtInvite);
        assertEq(usdtInviteData.betToken, address(usdt));
        assertEq(usdtInviteData.stakeAmount, STANDARD_STAKE_USDT);

        BattleshipBetting.BettingInvite memory daiInviteData = betting.getBettingInvite(daiInvite);
        assertEq(daiInviteData.betToken, address(dai));
        assertEq(daiInviteData.stakeAmount, STANDARD_STAKE_DAI);

        // Check tokens were escrowed
        assertEq(usdc.balanceOf(address(betting)), STANDARD_STAKE_USDC);
        assertEq(usdt.balanceOf(address(betting)), STANDARD_STAKE_USDT);
        assertEq(dai.balanceOf(address(betting)), STANDARD_STAKE_DAI);
    }

    function testBackwardCompatibilityCreateInvite() public {
        // Old createInvite function should still work and use USDC
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInvite(STANDARD_STAKE_USDC, PLAYER1);

        BattleshipBetting.BettingInvite memory invite = betting.getBettingInvite(inviteId);
        assertEq(invite.betToken, address(usdc));
        assertEq(invite.stakeAmount, STANDARD_STAKE_USDC);
    }

    function test_RevertWhen_CreateInviteWithNonWhitelistedToken() public {
        vm.prank(PLAYER1);
        vm.expectRevert(BattleshipBetting.TokenNotWhitelisted.selector);
        betting.createInviteWithToken(STANDARD_STAKE_USDT, PLAYER1, address(usdt));
    }

    function test_RevertWhen_CreateInviteBelowMinStake() public {
        vm.prank(ADMIN);
        betting.whitelistToken(address(usdt), MIN_STAKE_USDT);

        vm.prank(PLAYER1);
        vm.expectRevert(BattleshipBetting.InvalidStakeAmount.selector);
        betting.createInviteWithToken(MIN_STAKE_USDT - 1, PLAYER1, address(usdt));
    }

    function testFullGameFlowWithUSDT() public {
        // Whitelist USDT
        vm.prank(ADMIN);
        betting.whitelistToken(address(usdt), MIN_STAKE_USDT);

        // Create invite with USDT
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInviteWithToken(STANDARD_STAKE_USDT, PLAYER1, address(usdt));

        // Accept invite
        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId, PLAYER2);

        // Create game
        vm.prank(BACKEND);
        uint256 gameId = betting.createGame(inviteId);

        uint256 treasuryBalanceBefore = usdt.balanceOf(TREASURY);
        uint256 player1BalanceBefore = usdt.balanceOf(PLAYER1);

        // Resolve game with PLAYER1 as winner
        vm.prank(BACKEND);
        betting.resolveGame(gameId, PLAYER1);

        // Check payouts in USDT
        uint256 totalPool = STANDARD_STAKE_USDT * 2;
        uint256 platformFee = (totalPool * betting.platformFeePercentage()) / 100;
        uint256 winnerPayout = totalPool - platformFee;

        assertEq(usdt.balanceOf(PLAYER1), player1BalanceBefore + winnerPayout);
        assertEq(usdt.balanceOf(TREASURY), treasuryBalanceBefore + platformFee);
        assertEq(usdt.balanceOf(address(betting)), 0);
    }

    function testFullGameFlowWithDAI() public {
        // Whitelist DAI
        vm.prank(ADMIN);
        betting.whitelistToken(address(dai), MIN_STAKE_DAI);

        // Create invite with DAI
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInviteWithToken(STANDARD_STAKE_DAI, PLAYER1, address(dai));

        // Accept invite
        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId, PLAYER2);

        // Create game
        vm.prank(BACKEND);
        uint256 gameId = betting.createGame(inviteId);

        uint256 treasuryBalanceBefore = dai.balanceOf(TREASURY);
        uint256 player2BalanceBefore = dai.balanceOf(PLAYER2);

        // Resolve game with PLAYER2 as winner
        vm.prank(BACKEND);
        betting.resolveGame(gameId, PLAYER2);

        // Check payouts in DAI
        uint256 totalPool = STANDARD_STAKE_DAI * 2;
        uint256 platformFee = (totalPool * betting.platformFeePercentage()) / 100;
        uint256 winnerPayout = totalPool - platformFee;

        assertEq(dai.balanceOf(PLAYER2), player2BalanceBefore + winnerPayout);
        assertEq(dai.balanceOf(TREASURY), treasuryBalanceBefore + platformFee);
        assertEq(dai.balanceOf(address(betting)), 0);
    }

    function testCancelInviteWithDifferentTokens() public {
        // Whitelist USDT
        vm.prank(ADMIN);
        betting.whitelistToken(address(usdt), MIN_STAKE_USDT);

        // Create invites with different tokens
        vm.prank(PLAYER1);
        uint256 usdcInvite = betting.createInviteWithToken(STANDARD_STAKE_USDC, PLAYER1, address(usdc));

        vm.prank(PLAYER1);
        uint256 usdtInvite = betting.createInviteWithToken(STANDARD_STAKE_USDT, PLAYER1, address(usdt));

        uint256 usdcBalanceBefore = usdc.balanceOf(PLAYER1);
        uint256 usdtBalanceBefore = usdt.balanceOf(PLAYER1);

        // Cancel both invites
        vm.startPrank(PLAYER1);
        betting.cancelInvite(usdcInvite, PLAYER1);
        betting.cancelInvite(usdtInvite, PLAYER1);
        vm.stopPrank();

        // Check refunds in correct tokens
        assertEq(usdc.balanceOf(PLAYER1), usdcBalanceBefore + STANDARD_STAKE_USDC);
        assertEq(usdt.balanceOf(PLAYER1), usdtBalanceBefore + STANDARD_STAKE_USDT);
        assertEq(usdc.balanceOf(address(betting)), 0);
        assertEq(usdt.balanceOf(address(betting)), 0);
    }

    function testEmergencyRefundWithDifferentTokens() public {
        // Whitelist USDT
        vm.prank(ADMIN);
        betting.whitelistToken(address(usdt), MIN_STAKE_USDT);

        // Create and accept invite with USDT
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInviteWithToken(STANDARD_STAKE_USDT, PLAYER1, address(usdt));

        vm.prank(PLAYER2);
        betting.acceptInvite(inviteId, PLAYER2);

        vm.prank(BACKEND);
        betting.createGame(inviteId);

        // Pause for emergency
        vm.prank(ADMIN);
        betting.pause();

        uint256 p1BalanceBefore = usdt.balanceOf(PLAYER1);
        uint256 p2BalanceBefore = usdt.balanceOf(PLAYER2);

        // Emergency refund
        vm.prank(ADMIN);
        betting.emergencyRefundBet(inviteId);

        // Check refunds in USDT
        assertEq(usdt.balanceOf(PLAYER1), p1BalanceBefore + STANDARD_STAKE_USDT);
        assertEq(usdt.balanceOf(PLAYER2), p2BalanceBefore + STANDARD_STAKE_USDT);
        assertEq(usdt.balanceOf(address(betting)), 0);
    }

    function testMixedTokenInvites() public {
        // Whitelist all tokens
        vm.startPrank(ADMIN);
        betting.whitelistToken(address(usdt), MIN_STAKE_USDT);
        betting.whitelistToken(address(dai), MIN_STAKE_DAI);
        vm.stopPrank();

        // Create multiple invites with different tokens
        vm.startPrank(PLAYER1);
        uint256 usdcInvite = betting.createInviteWithToken(STANDARD_STAKE_USDC, PLAYER1, address(usdc));
        uint256 usdtInvite = betting.createInviteWithToken(STANDARD_STAKE_USDT, PLAYER1, address(usdt));
        vm.stopPrank();

        vm.prank(PLAYER2);
        uint256 daiInvite = betting.createInviteWithToken(STANDARD_STAKE_DAI, PLAYER2, address(dai));

        // Check player invites tracking
        uint256[] memory player1Invites = betting.getPlayerInvites(PLAYER1);
        uint256[] memory player2Invites = betting.getPlayerInvites(PLAYER2);

        assertEq(player1Invites.length, 2);
        assertEq(player2Invites.length, 1);

        // Check different token balances in contract
        assertEq(usdc.balanceOf(address(betting)), STANDARD_STAKE_USDC);
        assertEq(usdt.balanceOf(address(betting)), STANDARD_STAKE_USDT);
        assertEq(dai.balanceOf(address(betting)), STANDARD_STAKE_DAI);
    }

    function testEventEmissionWithTokenInfo() public {
        vm.prank(ADMIN);
        betting.whitelistToken(address(usdt), MIN_STAKE_USDT);

        vm.prank(PLAYER1);
        vm.expectEmit(true, true, false, true);
        emit InviteCreated(1, PLAYER1, STANDARD_STAKE_USDT, address(usdt));
        betting.createInviteWithToken(STANDARD_STAKE_USDT, PLAYER1, address(usdt));
    }

    // ==================== Edge Cases and Security Tests ====================

    function testWhitelistMaxTokens() public {
        // Test whitelisting many tokens by deploying actual mock ERC20 contracts
        address[] memory newTokens = new address[](10);
        
        for (uint256 i = 0; i < 10; i++) {
            // Deploy a new mock ERC20 for each test
            MockUSDC mockToken = new MockUSDC();
            mockToken.mint(address(this), 1000 * 10 ** 6); // Give it some supply
            newTokens[i] = address(mockToken);
            
            vm.prank(ADMIN);
            betting.whitelistToken(newTokens[i], 1 * 10 ** 6);
        }

        address[] memory tokens = betting.getWhitelistedTokens();
        assertEq(tokens.length, 11); // 10 + original USDC
    }

    function testRemoveTokenFromMiddleOfList() public {
        // Whitelist multiple tokens
        vm.startPrank(ADMIN);
        betting.whitelistToken(address(usdt), MIN_STAKE_USDT);
        betting.whitelistToken(address(dai), MIN_STAKE_DAI);
        vm.stopPrank();

        // Remove middle token (USDT)
        vm.prank(ADMIN);
        betting.removeTokenFromWhitelist(address(usdt));

        address[] memory tokens = betting.getWhitelistedTokens();
        assertEq(tokens.length, 2);
        assertTrue(_arrayContains(tokens, address(usdc)));
        assertTrue(_arrayContains(tokens, address(dai)));
        assertFalse(_arrayContains(tokens, address(usdt)));
    }

    function testCannotAcceptInviteWithDifferentTokenBalance() public {
        // Whitelist USDT
        vm.prank(ADMIN);
        betting.whitelistToken(address(usdt), MIN_STAKE_USDT);

        // Create invite with USDT
        vm.prank(PLAYER1);
        uint256 inviteId = betting.createInviteWithToken(STANDARD_STAKE_USDT, PLAYER1, address(usdt));

        // Drain PLAYER2's USDT balance
        vm.startPrank(PLAYER2);
        usdt.approve(address(betting), 0);
        usdt.transfer(address(0xdead), usdt.balanceOf(PLAYER2));
        usdt.approve(address(betting), type(uint256).max);
        vm.stopPrank();

        // Try to accept invite without sufficient USDT
        vm.prank(PLAYER2);
        vm.expectRevert(BattleshipBetting.InsufficientBalance.selector);
        betting.acceptInvite(inviteId, PLAYER2);
    }

    // ==================== Helper Functions ====================

    function _arrayContains(address[] memory array, address target) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == target) {
                return true;
            }
        }
        return false;
    }
}