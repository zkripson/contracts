// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./factories/GameFactory.sol";
import "./BattleshipGameImplementation.sol";

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
        uint256 drawCount; // Number of draws in this betting session
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
    uint256 public inviteTimeout = 24 hours;
    uint256 public platformFeePercentage = 10; // 10% to treasury  
    uint256 public constant MIN_STAKE_AMOUNT = 1 * 10 ** 6; // $1 USDC (6 decimals) - Keep as reference
    
    // Nonce mechanism for replay protection (Security Fix H-5)
    mapping(address => uint256) public userNonces;
    
    // Maximum allowed deadline (1 week) for security
    uint256 public constant MAX_DEADLINE = 7 days;

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
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event InviteTimeoutUpdated(uint256 oldTimeout, uint256 newTimeout);
    event DrawCountIncremented(uint256 indexed gameId, uint256 indexed inviteId, uint256 newDrawCount);
    event GameStatusUpdated(uint256 indexed inviteId, GameStatus oldStatus, GameStatus newStatus);
    event NonceIncremented(address indexed user, uint256 newNonce);

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
    error GameNotCompleted();
    error GameNotInFactory();
    error InvalidNonce();
    error DeadlineExpired();
    error InvalidTreasuryAddress();
    error InvalidWinnerAddress();
    error ERC20CallFailed();
    error GameFactoryCallFailed();
    error InvalidFeePercentage();
    error InvalidTimeout();

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
     * @dev Allows players to create betting invites with any whitelisted token
     * @param stakeAmount Amount to stake in the specified token
     * @param creator Address creating the invite  
     * @param betToken Token to use for betting (must be whitelisted)
     * @return inviteId Unique identifier for the invite
     * @custom:security Validates token is whitelisted and creator has sufficient balance
     * @custom:reentrancy Protected by nonReentrant modifier
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

        // Security Fix M-4: Improve error handling for external calls
        uint256 creatorBalance;
        try IERC20(betToken).balanceOf(creator) returns (uint256 balance) {
            creatorBalance = balance;
        } catch {
            revert ERC20CallFailed();
        }
        
        if (creatorBalance < stakeAmount) {
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
        invite.timeout = block.timestamp + inviteTimeout;
        invite.betStatus = BetStatus.Open;
        invite.gameStatus = GameStatus.CREATED; // Starts with first player

        // Track invite for player
        playerInvites[creator].push(inviteId);

        // Security Fix H-5: Increment nonce for replay protection
        userNonces[creator]++;
        emit NonceIncremented(creator, userNonces[creator]);

        // Escrow creator's stake
        IERC20(betToken).safeTransferFrom(creator, address(this), stakeAmount);

        emit InviteCreated(inviteId, creator, stakeAmount, betToken);
        return inviteId;
    }

    /**
     * @notice Create a betting invite with USDC (backward compatibility)
     * @dev Maintains backward compatibility for existing integrations using USDC
     * @param stakeAmount Amount in USDC to stake (6 decimals)
     * @param creator Address creating the invite
     * @return inviteId Unique identifier for the invite
     * @custom:compatibility This function defaults to USDC for backward compatibility
     */
    function createInvite(
        uint256 stakeAmount,
        address creator
    ) external whenNotPaused nonReentrant returns (uint256 inviteId) {
        return _createInviteWithToken(stakeAmount, creator, address(usdcToken));
    }

    /**
     * @notice Accept a betting invite by matching the stake
     * @dev Acceptor must have sufficient balance in the same token as the invite
     * @param inviteId ID of the invite to accept
     * @param acceptor Address accepting the invite
     * @custom:security Validates invite exists, is open, not expired, and acceptor has sufficient balance
     * @custom:reentrancy Protected by nonReentrant modifier
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

        // Security Fix M-4: Improve error handling for external calls
        uint256 acceptorBalance;
        try IERC20(invite.betToken).balanceOf(acceptor) returns (uint256 balance) {
            acceptorBalance = balance;
        } catch {
            revert ERC20CallFailed();
        }
        
        if (acceptorBalance < invite.stakeAmount) {
            revert InsufficientBalance();
        }

        // Update invite
        invite.acceptor = acceptor;
        invite.betStatus = BetStatus.Matched;

        // Track invite for acceptor
        playerInvites[acceptor].push(inviteId);

        // Security Fix H-5: Increment nonce for replay protection  
        userNonces[acceptor]++;
        emit NonceIncremented(acceptor, userNonces[acceptor]);

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
        
        // Security Fix M-5: Add deadline validation 
        if (block.timestamp > invite.createdAt + invite.timeout) {
            revert DeadlineExpired();
        }
        
        // Allow creating games for Matched OR Escrowed status (for replays)
        if (invite.betStatus != BetStatus.Matched && invite.betStatus != BetStatus.Escrowed) {
            revert InvalidInviteStatus();
        }

        // Security Fix M-4: Improve error handling for external calls
        try gameFactory.createGame(invite.creator, invite.acceptor) returns (uint256 newGameId) {
            gameId = newGameId;
        } catch {
            revert GameFactoryCallFailed();
        }

        // Update invite status (only if first game)
        if (invite.betStatus == BetStatus.Matched) {
            GameStatus oldStatus = invite.gameStatus;
            invite.betStatus = BetStatus.Escrowed;
            invite.gameStatus = GameStatus.WAITING;
            invite.gameId = gameId; // Keep reference to first game
            
            // Security Fix L-1: Emit event for state change
            emit GameStatusUpdated(inviteId, oldStatus, GameStatus.WAITING);
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
        // Security Fix H-4: Add proper access control validation
        if (winner == address(0)) revert InvalidWinnerAddress();
        
        uint256 inviteId = gameIdToInviteId[gameId];
        if (inviteId == 0) revert GameNotFound();

        BettingInvite storage invite = bettingInvites[inviteId];

        // Validate game state
        if (invite.betStatus != BetStatus.Escrowed) revert InvalidInviteStatus();
        if (invite.fundsDistributed) revert AlreadyResolved();
        
        // Security Fix H-4: Validate game exists in GameFactory and is completed
        address gameAddress;
        try gameFactory.games(gameId) returns (address addr) {
            gameAddress = addr;
        } catch {
            revert GameFactoryCallFailed();
        }
        
        if (gameAddress == address(0)) revert GameNotInFactory();
        
        // Validate game is actually completed
        try BattleshipGameImplementation(gameAddress).state() returns (BattleshipGameImplementation.GameState gameState) {
            if (gameState != BattleshipGameImplementation.GameState.Completed) {
                revert GameNotCompleted();
            }
        } catch {
            revert GameFactoryCallFailed();
        }

        // Validate winner is one of the players
        if (winner != invite.creator && winner != invite.acceptor) {
            revert UnauthorizedAction();
        }

        // Mark as resolved (Security Fix L-1: Add event for state change)
        GameStatus oldStatus = invite.gameStatus;
        invite.betStatus = BetStatus.Resolved;
        invite.gameStatus = GameStatus.COMPLETED;
        invite.fundsDistributed = true;
        
        emit GameStatusUpdated(inviteId, oldStatus, GameStatus.COMPLETED);

        uint256 totalPool = invite.stakeAmount * 2;
        uint256 platformFee = Math.mulDiv(totalPool, platformFeePercentage, 100);
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
        
        // Security Fix H-4: Validate game exists in GameFactory (similar to resolveGame)
        address gameAddress;
        try gameFactory.games(gameId) returns (address addr) {
            gameAddress = addr;
        } catch {
            revert GameFactoryCallFailed();
        }
        
        if (gameAddress == address(0)) revert GameNotInFactory();

        // Update persistent state - increment draw count
        invite.drawCount++;

        // Security Fix L-1: Emit event for draw count increment
        emit DrawCountIncremented(gameId, inviteId, invite.drawCount);
        emit GameDraw(gameId, inviteId, invite.creator, invite.acceptor);
    }

    /**
     * @notice Cancel an open invite and return stake to creator
     * @dev Only the creator can cancel their own open invite
     * @param inviteId ID of the invite to cancel
     * @param creator Address of the invite creator (must match stored creator)
     * @custom:security Only invite creator can cancel, invite must be in Open status
     * @custom:reentrancy Protected by nonReentrant modifier and CEI pattern
     */
    function cancelInvite(uint256 inviteId, address creator) external whenNotPaused nonReentrant {
        BettingInvite storage invite = bettingInvites[inviteId];

        // CHECKS - Validate invite
        if (invite.creator == address(0)) revert InviteNotFound();
        if (creator != invite.creator) revert UnauthorizedAction();
        if (invite.betStatus != BetStatus.Open) revert InvalidInviteStatus();

        // EFFECTS - Store values and update state before external calls
        address betToken = invite.betToken;
        uint256 stakeAmount = invite.stakeAmount;
        address creatorAddress = invite.creator;
        
        invite.betStatus = BetStatus.Cancelled;

        // INTERACTIONS - External calls last
        IERC20(betToken).safeTransfer(creatorAddress, stakeAmount);

        emit InviteCancelled(inviteId, creatorAddress, stakeAmount);
    }

    /**
     * @notice Handle expired invites (anyone can call)
     * @dev Anyone can call this function to clean up expired invites and return funds
     * @param inviteId ID of the expired invite
     * @custom:security Validates invite exists, is open, and has actually expired
     * @custom:reentrancy Protected by nonReentrant modifier and CEI pattern
     * @custom:accessibility Public function - anyone can call for gas efficiency
     */
    function handleExpiredInvite(uint256 inviteId) external whenNotPaused nonReentrant {
        BettingInvite storage invite = bettingInvites[inviteId];

        // CHECKS - Validate invite
        if (invite.creator == address(0)) revert InviteNotFound();
        if (invite.betStatus != BetStatus.Open) revert InvalidInviteStatus();
        if (block.timestamp <= invite.timeout) revert NotExpired();

        // EFFECTS - Store values and update state before external calls
        address betToken = invite.betToken;
        uint256 stakeAmount = invite.stakeAmount;
        address creatorAddress = invite.creator;
        
        invite.betStatus = BetStatus.Expired;

        // INTERACTIONS - External calls last
        IERC20(betToken).safeTransfer(creatorAddress, stakeAmount);

        emit InviteExpired(inviteId, creatorAddress, stakeAmount);
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
     * @return drawCount Number of draws in this betting session
     */
    function getGameBettingInfo(
        uint256 gameId
    ) external view returns (uint256 inviteId, uint256 totalPool, bool resolved, uint256 drawCount) {
        inviteId = gameIdToInviteId[gameId];
        if (inviteId > 0) {
            BettingInvite memory invite = bettingInvites[inviteId];
            totalPool = invite.stakeAmount * 2;
            resolved = invite.betStatus == BetStatus.Resolved;
            drawCount = invite.drawCount;
        }
        return (inviteId, totalPool, resolved, drawCount);
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

    /**
     * @notice Get number of draws for a betting invite
     * @param inviteId ID of the invite
     * @return drawCount Number of draws in this betting session
     */
    function getInviteDrawCount(uint256 inviteId) external view returns (uint256 drawCount) {
        return bettingInvites[inviteId].drawCount;
    }

    // ==================== Admin Functions ====================

    /**
     * @notice Update treasury address
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Security Fix L-4: Standardize error messages
        if (newTreasury == address(0)) revert InvalidTreasuryAddress();

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
        
        // CHECKS - Validate invite exists and has escrowed funds
        require(invite.creator != address(0), "Invite not found");
        require(invite.betStatus == BetStatus.Escrowed, "Bet not escrowed");
        require(!invite.fundsDistributed, "Funds already distributed");

        // Additional validation: Check if any associated games were resolved outside the betting system
        uint256[] memory gameIds = inviteGameIds[inviteId];
        for (uint256 i = 0; i < gameIds.length; i++) {
            address gameAddress = gameFactory.games(gameIds[i]);
            if (gameAddress != address(0)) {
                try BattleshipGameImplementation(gameAddress).state() returns (BattleshipGameImplementation.GameState gameState) {
                    require(
                        gameState != BattleshipGameImplementation.GameState.Completed,
                        "Game already completed - use normal resolution"
                    );
                } catch {
                    // If we can't check the game state, proceed with emergency refund
                    // This could happen if the game contract is broken
                }
            }
        }

        // EFFECTS - Store values and update state before external calls
        address betToken = invite.betToken;
        uint256 stakeAmount = invite.stakeAmount;
        address creatorAddress = invite.creator;
        address acceptorAddress = invite.acceptor;
        
        invite.betStatus = BetStatus.Resolved;
        invite.fundsDistributed = true;

        // INTERACTIONS - External calls last
        IERC20(betToken).safeTransfer(creatorAddress, stakeAmount);
        IERC20(betToken).safeTransfer(acceptorAddress, stakeAmount);

        emit EmergencyRefund(inviteId, creatorAddress, acceptorAddress, stakeAmount);
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
            
            // CHECKS - Skip if already resolved or invalid
            if (invite.creator == address(0) || 
                invite.betStatus != BetStatus.Escrowed || 
                invite.fundsDistributed) {
                continue;
            }

            // EFFECTS - Store values and update state before external calls
            address betToken = invite.betToken;
            uint256 stakeAmount = invite.stakeAmount;
            address creatorAddress = invite.creator;
            address acceptorAddress = invite.acceptor;
            
            invite.betStatus = BetStatus.Resolved;
            invite.fundsDistributed = true;

            // INTERACTIONS - External calls
            IERC20(betToken).safeTransfer(creatorAddress, stakeAmount);
            IERC20(betToken).safeTransfer(acceptorAddress, stakeAmount);

            emit EmergencyRefund(inviteId, creatorAddress, acceptorAddress, stakeAmount);
        }
    }

    /**
     * @notice Get active (escrowed) betting invite IDs with pagination
     * @param offset Starting index for pagination
     * @param limit Maximum number of invites to return (max 100)
     * @return activeInvites Array of invite IDs that have escrowed funds
     * @return total Total number of active invites
     * @return hasMore Whether there are more invites beyond this page
     */
    function getActiveInvites(uint256 offset, uint256 limit) 
        external view returns (uint256[] memory activeInvites, uint256 total, bool hasMore) {
        
        require(limit > 0 && limit <= 100, "Invalid limit"); // Max 100 per call
        
        // First pass: count total active invites
        uint256 totalActive = 0;
        for (uint256 i = 1; i < nextInviteId; i++) {
            BettingInvite memory invite = bettingInvites[i];
            if (invite.betStatus == BetStatus.Escrowed && !invite.fundsDistributed) {
                totalActive++;
            }
        }
        
        // Calculate result size
        uint256 startIndex = offset;
        uint256 endIndex = offset + limit;
        uint256 resultSize = 0;
        
        if (startIndex < totalActive) {
            resultSize = endIndex > totalActive ? totalActive - startIndex : limit;
        }
        
        // Create result array
        activeInvites = new uint256[](resultSize);
        uint256 activeIndex = 0;
        uint256 resultIndex = 0;
        
        // Second pass: collect paginated results
        for (uint256 i = 1; i < nextInviteId && resultIndex < resultSize; i++) {
            BettingInvite memory invite = bettingInvites[i];
            if (invite.betStatus == BetStatus.Escrowed && !invite.fundsDistributed) {
                if (activeIndex >= startIndex) {
                    activeInvites[resultIndex] = i;
                    resultIndex++;
                }
                activeIndex++;
            }
        }
        
        return (activeInvites, totalActive, endIndex < totalActive);
    }

    /**
     * @notice Get all active (escrowed) betting invite IDs for emergency refunds (backward compatibility)
     * @return activeInvites Array of invite IDs that have escrowed funds (limited to first 100)
     */
    function getActiveInvites() external view returns (uint256[] memory activeInvites) {
        (activeInvites, , ) = this.getActiveInvites(0, 100);
        return activeInvites;
    }

    // ==================== Configuration Functions ====================

    /**
     * @notice Update platform fee percentage
     * @param newFeePercentage New fee percentage (max 50%)
     */
    function setPlatformFee(uint256 newFeePercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFeePercentage > 50) revert InvalidFeePercentage(); // Max 50%
        
        uint256 oldFee = platformFeePercentage;
        platformFeePercentage = newFeePercentage;
        
        emit PlatformFeeUpdated(oldFee, newFeePercentage);
    }

    /**
     * @notice Update invite timeout duration
     * @param newTimeout New timeout duration in seconds (min 1 hour, max 7 days)
     */
    function setInviteTimeout(uint256 newTimeout) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTimeout < 1 hours || newTimeout > 7 days) revert InvalidTimeout();
        
        uint256 oldTimeout = inviteTimeout;
        inviteTimeout = newTimeout;
        
        emit InviteTimeoutUpdated(oldTimeout, newTimeout);
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

        // Validate token is a proper ERC20
        try IERC20(token).totalSupply() returns (uint256 supply) {
            require(supply > 0, "Token has zero supply");
        } catch {
            revert("Invalid ERC20 token");
        }
        
        // Test basic token operations
        try IERC20(token).balanceOf(address(this)) returns (uint256) {
            // Token supports balanceOf
        } catch {
            revert("Token does not support balanceOf");
        }

        // Test allowance function
        try IERC20(token).allowance(address(this), address(this)) returns (uint256) {
            // Token supports allowance
        } catch {
            revert("Token does not support allowance");
        }

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

        // Remove from whitelistedTokensList array - Safe version
        uint256 length = whitelistedTokensList.length;
        for (uint256 i = 0; i < length; i++) {
            if (whitelistedTokensList[i] == token) {
                // Only swap if not the last element
                if (i != length - 1) {
                    whitelistedTokensList[i] = whitelistedTokensList[length - 1];
                }
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
