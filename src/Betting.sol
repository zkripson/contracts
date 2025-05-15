// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./factories/GameFactory.sol";

/**
 * @title BattleshipBetting
 * @notice Handles betting/wagering for ZK Battleship games with USDC escrow
 * @dev Integrates with GameFactory to create games with monetary stakes
 */
contract BattleshipBetting is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ==================== Roles ====================
    bytes32 public constant BACKEND_ROLE = keccak256("BACKEND_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    // ==================== Structs ====================
    enum BetStatus {
        Open, // Created, waiting for acceptor
        Matched, // Acceptor found, both stakes escrowed
        Escrowed, // Funds locked, game can be created
        Resolved, // Game completed, funds distributed
        Cancelled, // Invite cancelled, funds returned
        Expired // Invite expired, funds returned
    }

    enum GameStatus {
        CREATED, // Initial state when session created with first player
        WAITING, // Second player joined, waiting for board submissions
        SETUP, // At least one player submitted board, not all
        ACTIVE, // Both players submitted boards, game in progress
        COMPLETED, // Game finished with winner/tie
        CANCELLED // Game cancelled before starting
    }

    struct BettingInvite {
        uint256 id;
        address creator;
        uint256 stakeAmount;
        address acceptor;
        uint256 createdAt;
        uint256 timeout;
        BetStatus betStatus; // Betting-related status
        GameStatus gameStatus; // Game-related status
        uint256 gameId; // Links to actual game once created
        bool fundsDistributed; // Prevents double distribution
    }

    // ==================== State Variables ====================
    IERC20 public immutable usdcToken;
    GameFactoryWithStats public immutable gameFactory;
    address public treasury;

    mapping(uint256 => BettingInvite) public bettingInvites;
    mapping(uint256 => uint256) public gameIdToBettingInvite; // Reverse lookup: gameId => inviteId
    mapping(address => uint256[]) public playerInvites; // Track player's invites

    uint256 private nextInviteId = 1;
    uint256 public constant INVITE_TIMEOUT = 24 hours;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 10; // 10% to treasury
    uint256 public constant MIN_STAKE_AMOUNT = 1 * 10 ** 6; // $1 USDC (6 decimals)

    // ==================== Events ====================
    event InviteCreated(uint256 indexed inviteId, address indexed creator, uint256 stakeAmount);
    event InviteAccepted(uint256 indexed inviteId, address indexed acceptor);
    event GameCreated(uint256 indexed gameId, uint256 indexed inviteId, address indexed playerA, address playerB);
    event GameResolved(uint256 indexed gameId, address indexed winner, uint256 winnerPayout, uint256 platformFee);
    event InviteCancelled(uint256 indexed inviteId, address indexed creator, uint256 stakeAmount);
    event InviteExpired(uint256 indexed inviteId, address indexed creator, uint256 stakeAmount);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    // ==================== Errors ====================
    error InvalidStakeAmount();
    error InviteNotFound();
    error UnauthorizedAction();
    error InvalidInviteStatus();
    error GameNotFound();
    error AlreadyResolved();
    error SamePlayerNotAllowed();
    error InsufficientBalance();
    error TransferFailed();
    error NotExpired();

    // ==================== Constructor ====================
    constructor(address _usdcToken, address _gameFactory, address _treasury, address _backend, address _admin) {
        require(_usdcToken != address(0), "Invalid USDC token");
        require(_gameFactory != address(0), "Invalid game factory");
        require(_treasury != address(0), "Invalid treasury");
        require(_backend != address(0), "Invalid backend");
        require(_admin != address(0), "Invalid admin");

        usdcToken = IERC20(_usdcToken);
        gameFactory = GameFactoryWithStats(_gameFactory);
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(BACKEND_ROLE, _backend);
        _grantRole(TREASURY_ROLE, _treasury);
    }

    // ==================== Main Functions ====================

    /**
     * @notice Create a betting invite with stake amount
     * @param stakeAmount Amount in USDC to stake (with 6 decimals)
     * @return inviteId Unique identifier for the invite
     */
    function createInvite(uint256 stakeAmount) external whenNotPaused nonReentrant returns (uint256 inviteId) {
        // Validate stake amount
        if (stakeAmount < MIN_STAKE_AMOUNT) {
            revert InvalidStakeAmount();
        }

        // Check user has sufficient balance
        if (usdcToken.balanceOf(msg.sender) < stakeAmount) {
            revert InsufficientBalance();
        }

        inviteId = nextInviteId++;

        // Create the invite
        BettingInvite storage invite = bettingInvites[inviteId];
        invite.id = inviteId;
        invite.creator = msg.sender;
        invite.stakeAmount = stakeAmount;
        invite.createdAt = block.timestamp;
        invite.timeout = block.timestamp + INVITE_TIMEOUT;
        invite.betStatus = BetStatus.Open;
        invite.gameStatus = GameStatus.CREATED; // Starts with first player

        // Track invite for player
        playerInvites[msg.sender].push(inviteId);

        // Escrow creator's stake
        usdcToken.safeTransferFrom(msg.sender, address(this), stakeAmount);

        emit InviteCreated(inviteId, msg.sender, stakeAmount);
        return inviteId;
    }

    /**
     * @notice Accept a betting invite by matching the stake
     * @param inviteId ID of the invite to accept
     */
    function acceptInvite(uint256 inviteId) external whenNotPaused nonReentrant {
        BettingInvite storage invite = bettingInvites[inviteId];

        // Validate invite exists and is open
        if (invite.creator == address(0)) revert InviteNotFound();
        if (invite.betStatus != BetStatus.Open) revert InvalidInviteStatus();
        if (msg.sender == invite.creator) revert SamePlayerNotAllowed();
        if (block.timestamp > invite.timeout) {
            // Mark as expired
            invite.betStatus = BetStatus.Expired;
            revert NotExpired();
        }

        // Check acceptor has sufficient balance
        if (usdcToken.balanceOf(msg.sender) < invite.stakeAmount) {
            revert InsufficientBalance();
        }

        // Update invite
        invite.acceptor = msg.sender;
        invite.betStatus = BetStatus.Matched;

        // Track invite for acceptor
        playerInvites[msg.sender].push(inviteId);

        // Escrow acceptor's stake
        usdcToken.safeTransferFrom(msg.sender, address(this), invite.stakeAmount);

        emit InviteAccepted(inviteId, msg.sender);
    }

    /**
     * @notice Create a game from a matched betting invite
     * @param inviteId ID of the matched invite
     * @return gameId ID of the created game
     */
    function createGame(uint256 inviteId) external onlyRole(BACKEND_ROLE) whenNotPaused returns (uint256 gameId) {
        BettingInvite storage invite = bettingInvites[inviteId];

        // Validate invite
        if (invite.creator == address(0)) revert InviteNotFound();
        if (invite.betStatus != BetStatus.Matched) revert InvalidInviteStatus();

        // Create game via GameFactory
        gameId = gameFactory.createGame(invite.creator, invite.acceptor);

        // Update invite status
        invite.gameId = gameId;
        invite.betStatus = BetStatus.Escrowed;
        invite.gameStatus = GameStatus.WAITING; // Now has both players, waiting for boards

        // Create reverse mapping
        gameIdToBettingInvite[gameId] = inviteId;

        emit GameCreated(gameId, inviteId, invite.creator, invite.acceptor);
        return gameId;
    }

    /**
     * @notice Resolve a game and distribute winnings
     * @param gameId ID of the completed game
     * @param winner Address of the winner (or address(0) for draw)
     */
    function resolveGame(uint256 gameId, address winner) external onlyRole(BACKEND_ROLE) whenNotPaused nonReentrant {
        uint256 inviteId = gameIdToBettingInvite[gameId];
        if (inviteId == 0) revert GameNotFound();

        BettingInvite storage invite = bettingInvites[inviteId];

        // Validate game state
        if (invite.betStatus != BetStatus.Escrowed) revert InvalidInviteStatus();
        if (invite.fundsDistributed) revert AlreadyResolved();

        // Mark as resolved
        invite.betStatus = BetStatus.Resolved;
        invite.gameStatus = GameStatus.COMPLETED;
        invite.fundsDistributed = true;

        uint256 totalPool = invite.stakeAmount * 2;
        uint256 platformFee = (totalPool * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 winnerPayout = totalPool - platformFee;

        if (winner == address(0)) {
            // Draw - return stakes to both players
            usdcToken.safeTransfer(invite.creator, invite.stakeAmount);
            usdcToken.safeTransfer(invite.acceptor, invite.stakeAmount);
            winnerPayout = 0;
            platformFee = 0;
        } else if (winner == invite.creator || winner == invite.acceptor) {
            // Valid winner - distribute funds
            usdcToken.safeTransfer(winner, winnerPayout);
            usdcToken.safeTransfer(treasury, platformFee);
        } else {
            revert UnauthorizedAction();
        }

        emit GameResolved(gameId, winner, winnerPayout, platformFee);
    }

    /**
     * @notice Cancel an open invite and return stake to creator
     * @param inviteId ID of the invite to cancel
     */
    function cancelInvite(uint256 inviteId) external whenNotPaused nonReentrant {
        BettingInvite storage invite = bettingInvites[inviteId];

        // Validate invite
        if (invite.creator == address(0)) revert InviteNotFound();
        if (msg.sender != invite.creator) revert UnauthorizedAction();
        if (invite.betStatus != BetStatus.Open) revert InvalidInviteStatus();

        // Update status
        invite.betStatus = BetStatus.Cancelled;

        // Return stake to creator
        usdcToken.safeTransfer(invite.creator, invite.stakeAmount);

        emit InviteCancelled(inviteId, invite.creator, invite.stakeAmount);
    }

    /**
     * @notice Handle expired invites (anyone can call)
     * @param inviteId ID of the expired invite
     */
    function handleExpiredInvite(uint256 inviteId) external whenNotPaused nonReentrant {
        BettingInvite storage invite = bettingInvites[inviteId];

        // Validate invite
        if (invite.creator == address(0)) revert InviteNotFound();
        if (invite.betStatus != BetStatus.Open) revert InvalidInviteStatus();
        if (block.timestamp <= invite.timeout) revert NotExpired();

        // Update status
        invite.betStatus = BetStatus.Expired;

        // Return stake to creator
        usdcToken.safeTransfer(invite.creator, invite.stakeAmount);

        emit InviteExpired(inviteId, invite.creator, invite.stakeAmount);
    }

    // ==================== View Functions ====================

    /**
     * @notice Get betting invite details
     * @param inviteId ID of the invite
     * @return invite Betting invite struct
     */
    function getBettingInvite(uint256 inviteId) external view returns (BettingInvite memory invite) {
        return bettingInvites[inviteId];
    }

    /**
     * @notice Get all invites for a player
     * @param player Player address
     * @return inviteIds Array of invite IDs
     */
    function getPlayerInvites(address player) external view returns (uint256[] memory inviteIds) {
        return playerInvites[player];
    }

    /**
     * @notice Get betting info for a game
     * @param gameId Game ID
     * @return inviteId Associated invite ID
     * @return totalPool Total betting pool
     * @return resolved Whether betting is resolved
     */
    function getGameBettingInfo(
        uint256 gameId
    ) external view returns (uint256 inviteId, uint256 totalPool, bool resolved) {
        inviteId = gameIdToBettingInvite[gameId];
        if (inviteId > 0) {
            BettingInvite memory invite = bettingInvites[inviteId];
            totalPool = invite.stakeAmount * 2;
            resolved = invite.betStatus == BetStatus.Resolved;
        }
        return (inviteId, totalPool, resolved);
    }

    /**
     * @notice Check if an invite has expired
     * @param inviteId ID of the invite
     * @return expired Whether the invite has expired
     */
    function isInviteExpired(uint256 inviteId) external view returns (bool expired) {
        BettingInvite memory invite = bettingInvites[inviteId];
        return block.timestamp > invite.timeout && invite.betStatus == BetStatus.Open;
    }

    // ==================== Admin Functions ====================

    /**
     * @notice Update treasury address
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasury != address(0), "Invalid treasury address");

        address oldTreasury = treasury;

        // Update role
        _revokeRole(TREASURY_ROLE, oldTreasury);
        _grantRole(TREASURY_ROLE, newTreasury);

        treasury = newTreasury;

        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Emergency pause
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Emergency withdraw (admin only, for stuck funds)
     * @param token Token address (should rarely be used)
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }
}
