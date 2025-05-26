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
        address betToken; // Token used for this bet
    }

    // ==================== State Variables ====================
    IERC20 public immutable usdcToken; // Deprecated but kept for backward compatibility
    GameFactoryWithStats public immutable gameFactory;
    address public treasury;
    
    // Token whitelisting
    mapping(address => bool) public whitelistedTokens;
    mapping(address => uint256) public tokenMinStakeAmounts; // Minimum stake per token
    address[] public whitelistedTokensList; // For enumeration

    mapping(uint256 => BettingInvite) public bettingInvites;
    mapping(uint256 => uint256[]) public inviteGameIds; // inviteId => gameId[] for replays
    mapping(uint256 => uint256) public gameIdToInviteId; // gameId => inviteId
    mapping(address => uint256[]) public playerInvites; // Track player's invites

    uint256 private nextInviteId = 1;
    uint256 public constant INVITE_TIMEOUT = 24 hours;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 10; // 10% to treasury
    uint256 public constant MIN_STAKE_AMOUNT = 1 * 10 ** 6; // $1 USDC (6 decimals)

    // ==================== Events ====================
    event InviteCreated(uint256 indexed inviteId, address indexed creator, uint256 stakeAmount, address indexed token);
    event InviteAccepted(uint256 indexed inviteId, address indexed acceptor);
    event GameCreated(uint256 indexed gameId, uint256 indexed inviteId, address indexed playerA, address playerB);
    event GameResolved(uint256 indexed gameId, address indexed winner, uint256 winnerPayout, uint256 platformFee);
    event InviteCancelled(uint256 indexed inviteId, address indexed creator, uint256 stakeAmount);
    event InviteExpired(uint256 indexed inviteId, address indexed creator, uint256 stakeAmount);
    event GameDraw(uint256 indexed gameId, uint256 indexed inviteId, address indexed playerA, address playerB);
    event EmergencyRefund(uint256 indexed inviteId, address indexed creator, address indexed acceptor, uint256 stakeAmount);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event TokenWhitelisted(address indexed token, uint256 minStakeAmount);
    event TokenRemovedFromWhitelist(address indexed token);
    event TokenMinStakeUpdated(address indexed token, uint256 oldMinStake, uint256 newMinStake);

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
    error TokenNotWhitelisted();
    error TokenAlreadyWhitelisted();
    error InvalidTokenAddress();
    error InvalidMinStakeAmount();

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

        // Whitelist USDC by default for backward compatibility
        whitelistedTokens[_usdcToken] = true;
        tokenMinStakeAmounts[_usdcToken] = MIN_STAKE_AMOUNT;
        whitelistedTokensList.push(_usdcToken);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(BACKEND_ROLE, _backend);
        _grantRole(TREASURY_ROLE, _treasury);
    }

    // ==================== Main Functions ====================

    /**
     * @notice Create a betting invite with stake amount and token
     * @param stakeAmount Amount to stake in the specified token
     * @param creator Address creating the invite
     * @param betToken Token to use for betting (must be whitelisted)
     * @return inviteId Unique identifier for the invite
     */
    function createInviteWithToken(
        uint256 stakeAmount,
        address creator,
        address betToken
    ) external whenNotPaused nonReentrant returns (uint256 inviteId) {
        return _createInviteWithToken(stakeAmount, creator, betToken);
    }

    /**
     * @notice Internal function to create a betting invite with a specific token
     * @param stakeAmount Amount to stake in the specified token
     * @param creator Address creating the invite
     * @param betToken Token to use for betting (must be whitelisted)
     * @return inviteId Unique identifier for the invite
     */
    function _createInviteWithToken(
        uint256 stakeAmount,
        address creator,
        address betToken
    ) internal returns (uint256 inviteId) {
        // Validate token is whitelisted
        if (!whitelistedTokens[betToken]) {
            revert TokenNotWhitelisted();
        }

        // Validate stake amount meets minimum for this token
        if (stakeAmount < tokenMinStakeAmounts[betToken]) {
            revert InvalidStakeAmount();
        }

        // Check user has sufficient balance
        if (IERC20(betToken).balanceOf(creator) < stakeAmount) {
            revert InsufficientBalance();
        }

        inviteId = nextInviteId++;

        // Create the invite
        BettingInvite storage invite = bettingInvites[inviteId];
        invite.id = inviteId;
        invite.creator = creator;
        invite.stakeAmount = stakeAmount;
        invite.betToken = betToken;
        invite.createdAt = block.timestamp;
        invite.timeout = block.timestamp + INVITE_TIMEOUT;
        invite.betStatus = BetStatus.Open;
        invite.gameStatus = GameStatus.CREATED; // Starts with first player

        // Track invite for player
        playerInvites[creator].push(inviteId);

        // Escrow creator's stake
        IERC20(betToken).safeTransferFrom(creator, address(this), stakeAmount);

        emit InviteCreated(inviteId, creator, stakeAmount, betToken);
        return inviteId;
    }

    /**
     * @notice Create a betting invite with USDC (backward compatibility)
     * @param stakeAmount Amount in USDC to stake
     * @param creator Address creating the invite
     * @return inviteId Unique identifier for the invite
     */
    function createInvite(
        uint256 stakeAmount,
        address creator
    ) external whenNotPaused nonReentrant returns (uint256 inviteId) {
        return _createInviteWithToken(stakeAmount, creator, address(usdcToken));
    }

    /**
     * @notice Accept a betting invite by matching the stake
     * @param inviteId ID of the invite to accept
     */
    function acceptInvite(uint256 inviteId, address acceptor) external whenNotPaused nonReentrant {
        BettingInvite storage invite = bettingInvites[inviteId];

        // Validate invite exists and is open
        if (invite.creator == address(0)) revert InviteNotFound();
        if (invite.betStatus != BetStatus.Open) revert InvalidInviteStatus();
        if (acceptor == invite.creator) revert SamePlayerNotAllowed();
        if (block.timestamp > invite.timeout) {
            // Mark as expired
            invite.betStatus = BetStatus.Expired;
            revert NotExpired();
        }

        // Check acceptor has sufficient balance in the bet token
        if (IERC20(invite.betToken).balanceOf(acceptor) < invite.stakeAmount) {
            revert InsufficientBalance();
        }

        // Update invite
        invite.acceptor = acceptor;
        invite.betStatus = BetStatus.Matched;

        // Track invite for acceptor
        playerInvites[acceptor].push(inviteId);

        // Escrow acceptor's stake
        IERC20(invite.betToken).safeTransferFrom(acceptor, address(this), invite.stakeAmount);

        emit InviteAccepted(inviteId, acceptor);
    }

    /**
     * @notice Create a game from a matched betting invite (including replays)
     * @param inviteId ID of the matched invite
     * @return gameId ID of the created game
     */
    function createGame(uint256 inviteId) external onlyRole(BACKEND_ROLE) whenNotPaused returns (uint256 gameId) {
        BettingInvite storage invite = bettingInvites[inviteId];

        // Validate invite
        if (invite.creator == address(0)) revert InviteNotFound();
        
        // Allow creating games for Matched OR Escrowed status (for replays)
        if (invite.betStatus != BetStatus.Matched && invite.betStatus != BetStatus.Escrowed) {
            revert InvalidInviteStatus();
        }

        // Create game via GameFactory
        gameId = gameFactory.createGame(invite.creator, invite.acceptor);

        // Update invite status (only if first game)
        if (invite.betStatus == BetStatus.Matched) {
            invite.betStatus = BetStatus.Escrowed;
            invite.gameStatus = GameStatus.WAITING;
            invite.gameId = gameId; // Keep reference to first game
        }

        // Track all games for this invite
        inviteGameIds[inviteId].push(gameId);
        gameIdToInviteId[gameId] = inviteId;

        emit GameCreated(gameId, inviteId, invite.creator, invite.acceptor);
        return gameId;
    }

    /**
     * @notice Resolve a game and distribute winnings (only for decisive wins)
     * @param gameId ID of the completed game  
     * @param winner Address of the winner (must NOT be address(0))
     */
    function resolveGame(uint256 gameId, address winner) external onlyRole(BACKEND_ROLE) whenNotPaused nonReentrant {
        // Draws should not call this function - they should just create new games
        require(winner != address(0), "Draws should not resolve betting - create replay game instead");
        
        uint256 inviteId = gameIdToInviteId[gameId];
        if (inviteId == 0) revert GameNotFound();

        BettingInvite storage invite = bettingInvites[inviteId];

        // Validate game state
        if (invite.betStatus != BetStatus.Escrowed) revert InvalidInviteStatus();
        if (invite.fundsDistributed) revert AlreadyResolved();

        // Validate winner is one of the players
        if (winner != invite.creator && winner != invite.acceptor) {
            revert UnauthorizedAction();
        }

        // Mark as resolved
        invite.betStatus = BetStatus.Resolved;
        invite.gameStatus = GameStatus.COMPLETED;
        invite.fundsDistributed = true;

        uint256 totalPool = invite.stakeAmount * 2;
        uint256 platformFee = (totalPool * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 winnerPayout = totalPool - platformFee;

        // Distribute funds to winner using the bet token
        IERC20(invite.betToken).safeTransfer(treasury, platformFee);
        IERC20(invite.betToken).safeTransfer(winner, winnerPayout);

        emit GameResolved(gameId, winner, winnerPayout, platformFee);
    }

    /**
     * @notice Handle a draw by recording it but keeping bet active for replay
     * @param gameId ID of the game that ended in draw
     */
    function recordDraw(uint256 gameId) external onlyRole(BACKEND_ROLE) whenNotPaused {
        uint256 inviteId = gameIdToInviteId[gameId];
        if (inviteId == 0) revert GameNotFound();

        BettingInvite storage invite = bettingInvites[inviteId];
        if (invite.betStatus != BetStatus.Escrowed) revert InvalidInviteStatus();

        // Just emit event for tracking, but keep bet active
        emit GameDraw(gameId, inviteId, invite.creator, invite.acceptor);
    }

    /**
     * @notice Cancel an open invite and return stake to creator
     * @param inviteId ID of the invite to cancel
     */
    function cancelInvite(uint256 inviteId, address creator) external whenNotPaused nonReentrant {
        BettingInvite storage invite = bettingInvites[inviteId];

        // Validate invite
        if (invite.creator == address(0)) revert InviteNotFound();
        if (creator != invite.creator) revert UnauthorizedAction();
        if (invite.betStatus != BetStatus.Open) revert InvalidInviteStatus();

        // Update status
        invite.betStatus = BetStatus.Cancelled;

        // Return stake to creator in the bet token
        IERC20(invite.betToken).safeTransfer(invite.creator, invite.stakeAmount);

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

        // Return stake to creator in the bet token
        IERC20(invite.betToken).safeTransfer(invite.creator, invite.stakeAmount);

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
     * @notice Get all game IDs associated with a betting invite
     * @param inviteId ID of the betting invite
     * @return gameIds Array of game IDs (including replays)
     */
    function getInviteGameIds(uint256 inviteId) external view returns (uint256[] memory gameIds) {
        return inviteGameIds[inviteId];
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
        inviteId = gameIdToInviteId[gameId];
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

    /**
     * @notice Emergency function to return stakes to players for a specific betting invite
     * @param inviteId ID of the betting invite to refund
     * @dev Should only be used in emergency situations when normal resolution is impossible
     */
    function emergencyRefundBet(uint256 inviteId) external onlyRole(DEFAULT_ADMIN_ROLE) whenPaused {
        BettingInvite storage invite = bettingInvites[inviteId];
        
        // Validate invite exists and has escrowed funds
        require(invite.creator != address(0), "Invite not found");
        require(invite.betStatus == BetStatus.Escrowed, "Bet not escrowed");
        require(!invite.fundsDistributed, "Funds already distributed");

        // Mark as resolved to prevent double withdrawal
        invite.betStatus = BetStatus.Resolved;
        invite.fundsDistributed = true;

        // Return stakes to both players (no platform fee in emergency)
        IERC20(invite.betToken).safeTransfer(invite.creator, invite.stakeAmount);
        IERC20(invite.betToken).safeTransfer(invite.acceptor, invite.stakeAmount);

        emit EmergencyRefund(inviteId, invite.creator, invite.acceptor, invite.stakeAmount);
    }

    /**
     * @notice Emergency function to refund multiple betting invites at once
     * @param inviteIds Array of invite IDs to refund
     * @dev Batch version of emergencyRefundBet for efficiency
     */
    function emergencyRefundMultipleBets(uint256[] calldata inviteIds) external onlyRole(DEFAULT_ADMIN_ROLE) whenPaused {
        for (uint256 i = 0; i < inviteIds.length; i++) {
            uint256 inviteId = inviteIds[i];
            BettingInvite storage invite = bettingInvites[inviteId];
            
            // Skip if already resolved or invalid
            if (invite.creator == address(0) || 
                invite.betStatus != BetStatus.Escrowed || 
                invite.fundsDistributed) {
                continue;
            }

            // Mark as resolved
            invite.betStatus = BetStatus.Resolved;
            invite.fundsDistributed = true;

            // Return stakes
            IERC20(invite.betToken).safeTransfer(invite.creator, invite.stakeAmount);
            IERC20(invite.betToken).safeTransfer(invite.acceptor, invite.stakeAmount);

            emit EmergencyRefund(inviteId, invite.creator, invite.acceptor, invite.stakeAmount);
        }
    }

    /**
     * @notice Get all active (escrowed) betting invite IDs for emergency refunds
     * @return activeInvites Array of invite IDs that have escrowed funds
     */
    function getActiveInvites() external view returns (uint256[] memory activeInvites) {
        // Count active invites first
        uint256 activeCount = 0;
        for (uint256 i = 1; i < nextInviteId; i++) {
            BettingInvite memory invite = bettingInvites[i];
            if (invite.betStatus == BetStatus.Escrowed && !invite.fundsDistributed) {
                activeCount++;
            }
        }

        // Create array of correct size
        activeInvites = new uint256[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 1; i < nextInviteId; i++) {
            BettingInvite memory invite = bettingInvites[i];
            if (invite.betStatus == BetStatus.Escrowed && !invite.fundsDistributed) {
                activeInvites[index] = i;
                index++;
            }
        }

        return activeInvites;
    }

    // ==================== Token Whitelisting Functions ====================

    /**
     * @notice Whitelist a new token for betting
     * @param token Token address to whitelist
     * @param minStakeAmount Minimum stake amount for this token
     */
    function whitelistToken(address token, uint256 minStakeAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) revert InvalidTokenAddress();
        if (whitelistedTokens[token]) revert TokenAlreadyWhitelisted();
        if (minStakeAmount == 0) revert InvalidMinStakeAmount();

        whitelistedTokens[token] = true;
        tokenMinStakeAmounts[token] = minStakeAmount;
        whitelistedTokensList.push(token);

        emit TokenWhitelisted(token, minStakeAmount);
    }

    /**
     * @notice Remove a token from whitelist
     * @param token Token address to remove
     */
    function removeTokenFromWhitelist(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!whitelistedTokens[token]) revert TokenNotWhitelisted();

        whitelistedTokens[token] = false;
        tokenMinStakeAmounts[token] = 0;

        // Remove from whitelistedTokensList array
        for (uint256 i = 0; i < whitelistedTokensList.length; i++) {
            if (whitelistedTokensList[i] == token) {
                whitelistedTokensList[i] = whitelistedTokensList[whitelistedTokensList.length - 1];
                whitelistedTokensList.pop();
                break;
            }
        }

        emit TokenRemovedFromWhitelist(token);
    }

    /**
     * @notice Update minimum stake amount for a whitelisted token
     * @param token Token address
     * @param newMinStakeAmount New minimum stake amount
     */
    function updateTokenMinStake(address token, uint256 newMinStakeAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!whitelistedTokens[token]) revert TokenNotWhitelisted();
        if (newMinStakeAmount == 0) revert InvalidMinStakeAmount();

        uint256 oldMinStake = tokenMinStakeAmounts[token];
        tokenMinStakeAmounts[token] = newMinStakeAmount;

        emit TokenMinStakeUpdated(token, oldMinStake, newMinStakeAmount);
    }

    /**
     * @notice Get all whitelisted tokens
     * @return tokens Array of whitelisted token addresses
     */
    function getWhitelistedTokens() external view returns (address[] memory tokens) {
        return whitelistedTokensList;
    }

    /**
     * @notice Check if a token is whitelisted
     * @param token Token address to check
     * @return isWhitelisted True if token is whitelisted
     */
    function isTokenWhitelisted(address token) external view returns (bool isWhitelisted) {
        return whitelistedTokens[token];
    }

    /**
     * @notice Get minimum stake amount for a token
     * @param token Token address
     * @return minStakeAmount Minimum stake amount for the token
     */
    function getTokenMinStake(address token) external view returns (uint256 minStakeAmount) {
        return tokenMinStakeAmounts[token];
    }
}
