// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title SHIPToken
 * @dev Enhanced ERC20 token for ZK Battleship with batch operations and Base optimization
 */
contract SHIPToken is ERC20, ERC20Burnable, Pausable, AccessControl {

    // ==================== Roles ====================
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    // ==================== Structs ====================
    struct RewardParams {
        uint256 participationReward;
        uint256 victoryBonus;
        uint256 rewardCooldown;
        uint256 maxRewardsPerDay;
    }

    struct BatchReward {
        address player;
        bool isWinner;
        uint256 gameId;
    }

    // ==================== State Variables ====================
    address public currentDistributor;
    RewardParams public rewardParams;

    // Anti-abuse tracking
    mapping(address => uint256) private lastRewardTimestamp;
    mapping(address => uint256) private dailyRewards;
    mapping(address => uint256) private dailyRewardReset;

    // Gas optimization for batch operations
    uint256 private constant MAX_BATCH_SIZE = 100;

    // Events
    event RewardMinted(address indexed player, bool isWinner, uint256 amount, uint256 gameId);
    event BatchRewardMinted(uint256 indexed batchId, uint256 totalAmount, uint256 playersRewarded);
    event RewardParametersUpdated(RewardParams oldParams, RewardParams newParams);
    event DistributorUpdated(address indexed oldDistributor, address indexed newDistributor);
    event AbuseAttemptBlocked(address indexed player, string reason);

    // ==================== Constructor ====================
    constructor(address _admin, address _rewardDistributor, uint256 _initialSupply) ERC20("Battleship SHIP", "SHIP") {
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(MINTER_ROLE, _admin);
        _grantRole(DISTRIBUTOR_ROLE, _rewardDistributor);

        currentDistributor = _rewardDistributor;

        // Initialize reward parameters
        rewardParams = RewardParams({
            participationReward: 10 * 10 ** decimals(), // 10 SHIP
            victoryBonus: 25 * 10 ** decimals(), // 25 SHIP
            rewardCooldown: 5 minutes,
            maxRewardsPerDay: 100 * 10 ** decimals() // 100 SHIP max per day
        });

        // Mint initial supply if specified
        if (_initialSupply > 0) {
            _mint(_admin, _initialSupply);
        }
    }

    // ==================== Reward Functions ====================

    /**
     * @notice Mint rewards for a single game participation
     * @param player Address of player to reward
     * @param isWinner Whether player won the game
     * @param gameId Unique identifier of the game
     * @return success Whether the reward was successfully minted
     */
    function mintGameReward(
        address player,
        bool isWinner,
        uint256 gameId
    ) external onlyRole(DISTRIBUTOR_ROLE) whenNotPaused returns (bool success) {
        return _mintReward(player, isWinner, gameId);
    }

    /**
     * @notice Mint rewards for multiple players in a single transaction (gas optimized)
     * @param rewards Array of reward data
     * @return batchId Unique identifier for this batch
     * @return totalRewarded Total amount of tokens minted
     * @return successCount Number of players successfully rewarded
     */
    function mintBatchRewards(
        BatchReward[] memory rewards
    )
        external
        onlyRole(DISTRIBUTOR_ROLE)
        whenNotPaused
        returns (uint256 batchId, uint256 totalRewarded, uint256 successCount)
    {
        require(rewards.length <= MAX_BATCH_SIZE, "SHIP: Batch size too large");
        require(rewards.length > 0, "SHIP: Empty batch");

        batchId = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty)));

        for (uint256 i = 0; i < rewards.length; i++) {
            BatchReward memory reward = rewards[i];

            try this.mintGameReward(reward.player, reward.isWinner, reward.gameId) returns (bool success) {
                if (success) {
                    successCount++;
                    uint256 amount = rewardParams.participationReward;
                    if (reward.isWinner) {
                        amount = amount + rewardParams.victoryBonus;
                    }
                    totalRewarded = totalRewarded + amount;
                }
            } catch {
                // Individual failures don't stop the batch
                continue;
            }
        }

        emit BatchRewardMinted(batchId, totalRewarded, successCount);
        return (batchId, totalRewarded, successCount);
    }

    /**
     * @notice Internal function to mint individual rewards
     * @param player Address of player
     * @param isWinner Whether player won
     * @param gameId Game identifier
     * @return success Whether minting succeeded
     */
    function _mintReward(address player, bool isWinner, uint256 gameId) internal returns (bool success) {
        // Check cooldown
        if (block.timestamp < lastRewardTimestamp[player] + rewardParams.rewardCooldown) {
            emit AbuseAttemptBlocked(player, "Cooldown active");
            return false;
        }

        // Reset daily rewards if day changed
        if (block.timestamp >= dailyRewardReset[player] + 1 days) {
            dailyRewards[player] = 0;
            dailyRewardReset[player] = block.timestamp;
        }

        // Calculate reward
        uint256 reward = rewardParams.participationReward;
        if (isWinner) {
            reward = reward + rewardParams.victoryBonus;
        }

        // Check daily limit
        if (dailyRewards[player] + reward > rewardParams.maxRewardsPerDay) {
            emit AbuseAttemptBlocked(player, "Daily limit exceeded");
            return false;
        }

        // Update tracking
        dailyRewards[player] = dailyRewards[player] + reward;
        lastRewardTimestamp[player] = block.timestamp;

        // Mint tokens
        _mint(player, reward);

        emit RewardMinted(player, isWinner, reward, gameId);
        return true;
    }

    // ==================== Admin Functions ====================

    /**
     * @notice Update reward parameters
     * @param newParams New reward parameters
     */
    function updateRewardParameters(RewardParams memory newParams) external onlyRole(ADMIN_ROLE) {
        require(newParams.participationReward > 0, "SHIP: Invalid participation reward");
        require(newParams.maxRewardsPerDay >= newParams.participationReward, "SHIP: Invalid daily limit");

        RewardParams memory oldParams = rewardParams;
        rewardParams = newParams;

        emit RewardParametersUpdated(oldParams, newParams);
    }

    /**
     * @notice Set new reward distributor
     * @param newDistributor Address of new distributor
     */
    function setDistributor(address newDistributor) external onlyRole(ADMIN_ROLE) {
        require(newDistributor != address(0), "SHIP: Invalid distributor");

        address oldDistributor = currentDistributor;

        // Update roles
        _revokeRole(DISTRIBUTOR_ROLE, oldDistributor);
        _grantRole(DISTRIBUTOR_ROLE, newDistributor);

        currentDistributor = newDistributor;

        emit DistributorUpdated(oldDistributor, newDistributor);
    }

    /**
     * @notice Pause token operations
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause token operations
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Admin mint function
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        _mint(to, amount);
    }

    /**
     * @notice Emergency withdraw function (admin only)
     * @param token Address of token to withdraw (address(0) for ETH)
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            ERC20(token).transfer(msg.sender, amount);
        }
    }

    // ==================== View Functions ====================

    /**
     * @notice Get reward parameters
     * @return Current reward parameters
     */
    function getRewardParams() external view returns (RewardParams memory) {
        return rewardParams;
    }

    /**
     * @notice Check if player can receive reward
     * @param player Address to check
     * @return canReceive Whether player can receive reward
     * @return reason Reason if can't receive
     */
    function canReceiveReward(address player) external view returns (bool canReceive, string memory reason) {
        // Check cooldown
        if (block.timestamp < lastRewardTimestamp[player] + rewardParams.rewardCooldown) {
            return (false, "Cooldown active");
        }

        // Check daily limit
        uint256 resetTime = dailyRewardReset[player] + 1 days;
        uint256 currentDailyRewards = block.timestamp >= resetTime ? 0 : dailyRewards[player];

        if (currentDailyRewards + rewardParams.participationReward > rewardParams.maxRewardsPerDay) {
            return (false, "Daily limit would be exceeded");
        }

        return (true, "");
    }

    /**
     * @notice Get player's daily reward status
     * @param player Address to check
     * @return dailyRewardsUsed Amount used today
     * @return resetTime Time when daily limit resets
     */
    function getDailyRewardStatus(address player) external view returns (uint256 dailyRewardsUsed, uint256 resetTime) {
        resetTime = dailyRewardReset[player] + 1 days;
        dailyRewardsUsed = block.timestamp >= resetTime ? 0 : dailyRewards[player];

        return (dailyRewardsUsed, resetTime);
    }

    // ==================== Required Overrides ====================

    /**
     * @notice Override transfer to add pause functionality
     */
    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        return super.transfer(to, amount);
    }

    /**
     * @notice Override transferFrom to add pause functionality
     */
    function transferFrom(address from, address to, uint256 amount) public override whenNotPaused returns (bool) {
        return super.transferFrom(from, to, amount);
    }

    /**
     * @notice Override supports interface for AccessControl
     */
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // ==================== Public Functions ====================

    /**
     * @notice Get all reward parameters in a single call
     */
    function participationReward() external view returns (uint256) {
        return rewardParams.participationReward;
    }

    /**
     * @notice Get victory bonus amount
     */
    function victoryBonus() external view returns (uint256) {
        return rewardParams.victoryBonus;
    }
}
