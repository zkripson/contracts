// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title SHIPToken
 * @dev ERC20 token for the ZK Battleship game with reward distribution capabilities
 * Deployed on Base mainnet, rewards distributed through a trusted backend service
 */
contract SHIPToken is ERC20, ERC20Burnable, Pausable, AccessControl {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    // Events
    event RewardMinted(address indexed player, bool isWinner, uint256 amount);
    event RewardParametersUpdated(uint256 newParticipationReward, uint256 newVictoryBonus);
    event DistributorUpdated(address indexed newDistributor);

    // Current distributor address
    address public currentDistributor;

    // Token reward parameters (maintained for consistency but used by backend)
    uint256 public participationReward;
    uint256 public victoryBonus;

    // Rate limiting for rewards to prevent abuse
    mapping(address => uint256) private lastRewardTimestamp;
    uint256 public rewardCooldown;

    // Max rewards per period (anti-abuse)
    uint256 public maxRewardsPerDay;
    mapping(address => uint256) private dailyRewards;
    mapping(address => uint256) private dailyRewardReset;

    /**
     * @dev Constructor sets up roles and parameters
     * @param _admin Admin address for overall contract control
     * @param _rewardDistributor Backend service address authorized to mint rewards
     * @param _initialSupply Initial supply to mint to admin
     */
    constructor(address _admin, address _rewardDistributor, uint256 _initialSupply) ERC20("Battleship SHIP", "SHIP") {
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(MINTER_ROLE, _admin);
        _grantRole(DISTRIBUTOR_ROLE, _rewardDistributor);

        // Set current distributor
        currentDistributor = _rewardDistributor;

        // Set default reward parameters (for reference)
        participationReward = 10 * 10 ** decimals(); // 10 SHIP
        victoryBonus = 25 * 10 ** decimals(); // 25 SHIP

        // Configure anti-abuse measures
        rewardCooldown = 5 minutes;
        maxRewardsPerDay = 100 * 10 ** decimals(); // 100 SHIP max per day

        // Mint initial supply if specified
        if (_initialSupply > 0) {
            _mint(_admin, _initialSupply);
        }
    }

    /**
     * @dev Mint rewards for game participation (only callable by reward distributor)
     * @param player Address of player to reward
     * @param isWinner Whether player won the game
     * @param gameId Unique identifier of the game (for tracking)
     */
    function mintGameReward(
        address player,
        bool isWinner,
        uint256 gameId
    ) external onlyRole(DISTRIBUTOR_ROLE) whenNotPaused returns (bool) {
        // Prevent reward abuse with cooldown
        require(block.timestamp >= lastRewardTimestamp[player] + rewardCooldown, "SHIP: Reward cooldown still active");

        // Reset daily rewards if day changed
        if (block.timestamp >= dailyRewardReset[player] + 1 days) {
            dailyRewards[player] = 0;
            dailyRewardReset[player] = block.timestamp;
        }

        // Calculate reward
        uint256 reward = participationReward;
        if (isWinner) {
            reward += victoryBonus;
        }

        // Check daily reward limit
        require(dailyRewards[player] + reward <= maxRewardsPerDay, "SHIP: Daily reward limit exceeded");

        // Update reward tracking
        dailyRewards[player] += reward;
        lastRewardTimestamp[player] = block.timestamp;

        // Mint tokens to player
        _mint(player, reward);

        emit RewardMinted(player, isWinner, reward);
        return true;
    }

    /**
     * @dev Update reward parameters (only admin)
     * @param newParticipationReward New base participation reward amount
     * @param newVictoryBonus New victory bonus amount
     */
    function updateRewardParameters(
        uint256 newParticipationReward,
        uint256 newVictoryBonus
    ) external onlyRole(ADMIN_ROLE) {
        participationReward = newParticipationReward;
        victoryBonus = newVictoryBonus;

        emit RewardParametersUpdated(newParticipationReward, newVictoryBonus);
    }

    /**
     * @dev Set the reward distributor address (backend service)
     * @param newDistributor Address of the new distributor
     */
    function setDistributor(address newDistributor) external onlyRole(ADMIN_ROLE) {
        // Revoke role from current distributor
        if (currentDistributor != address(0)) {
            revokeRole(DISTRIBUTOR_ROLE, currentDistributor);
        }

        // Grant role to the new distributor
        grantRole(DISTRIBUTOR_ROLE, newDistributor);

        // Update current distributor
        currentDistributor = newDistributor;

        emit DistributorUpdated(newDistributor);
    }

    /**
     * @dev Update anti-abuse parameters
     * @param newCooldown New cooldown between rewards
     * @param newDailyLimit New maximum rewards per day
     */
    function updateAbuseControls(uint256 newCooldown, uint256 newDailyLimit) external onlyRole(ADMIN_ROLE) {
        rewardCooldown = newCooldown;
        maxRewardsPerDay = newDailyLimit;
    }

    /**
     * @dev Pause token operations (minting, transfers)
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause token operations
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Mint tokens (admin only)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @dev Required override for AccessControl
     */
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
