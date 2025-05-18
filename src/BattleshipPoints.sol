// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BattleshipPoints
 * @dev Manages points for the ZK Battleship game. Players earn points from gameplay,
 * which can be viewed for leaderboards and claimed later for tokens through a separate contract.
 */
contract BattleshipPoints is Ownable(msg.sender), ReentrancyGuard {
    // Weekly distribution settings
    uint256 public weekStartTimestamp;
    uint256 public constant WEEK_DURATION = 7 days;
    uint256 public minimumPointsThreshold = 100;

    // Authorized addresses that can award points
    mapping(address => bool) public authorizedSources;

    // Points tracking
    mapping(address => uint256) public totalPlayerPoints;
    mapping(address => uint256) public weeklyPlayerPoints;
    mapping(address => uint256) public claimablePoints;

    // Active players tracking
    address[] public activePlayers;
    mapping(address => uint256) public activePlayerIndices; // 1-based indices (0 means not present)
    mapping(address => bool) public isActiveThisWeek;

    // All players tracking for leaderboards
    address[] public allPlayers;
    mapping(address => bool) public hasPlayedBefore;

    // Events
    event PointsAwarded(address indexed player, uint256 amount, string category, bytes32 indexed gameId);
    event WeeklyDistributionSnapshot(uint256 timestamp, uint256 totalPoints);
    event AuthorizedSourceAdded(address indexed source);
    event AuthorizedSourceRemoved(address indexed source);
    event PlayerActivated(address indexed player);

    /**
     * @dev Constructor sets initial week start
     */
    constructor() {
        weekStartTimestamp = block.timestamp;

        // Add deployer as authorized source
        authorizedSources[msg.sender] = true;
        emit AuthorizedSourceAdded(msg.sender);
    }

    /**
     * @dev Modifier to restrict function access to authorized sources only
     */
    modifier onlyAuthorized() {
        require(authorizedSources[msg.sender], "Not authorized");
        _;
    }

    /**
     * @dev Adds a new authorized source that can award points
     * @param source Address to authorize
     */
    function addAuthorizedSource(address source) external onlyOwner {
        require(source != address(0), "Invalid address");
        require(!authorizedSources[source], "Already authorized");

        authorizedSources[source] = true;
        emit AuthorizedSourceAdded(source);
    }

    /**
     * @dev Removes an authorized source
     * @param source Address to remove authorization from
     */
    function removeAuthorizedSource(address source) external onlyOwner {
        require(authorizedSources[source], "Not authorized");

        authorizedSources[source] = false;
        emit AuthorizedSourceRemoved(source);
    }

    /**
     * @dev Awards points to a player
     * @param player Address of the player
     * @param amount Amount of points to award
     * @param category Category of points (e.g., "GAME_WIN", "DAILY_BONUS")
     * @param gameId Unique identifier for the game (if applicable)
     */
    function awardPoints(
        address player,
        uint256 amount,
        string calldata category,
        bytes32 gameId
    ) external onlyAuthorized {
        require(player != address(0), "Invalid player address");
        require(amount > 0, "Amount must be greater than zero");

        // Update points
        totalPlayerPoints[player] += amount;
        weeklyPlayerPoints[player] += amount;

        // Add player to all players list if first time
        if (!hasPlayedBefore[player]) {
            hasPlayedBefore[player] = true;
            allPlayers.push(player);
        }

        // Add player to active players list if not already present
        if (!isActiveThisWeek[player]) {
            isActiveThisWeek[player] = true;
            activePlayers.push(player);
            activePlayerIndices[player] = activePlayers.length;
            emit PlayerActivated(player);
        }

        emit PointsAwarded(player, amount, category, gameId);
    }

    /**
     * @dev Takes a snapshot of weekly points for future token distribution
     */
    function takeWeeklySnapshot() external onlyAuthorized {
        require(block.timestamp >= weekStartTimestamp + WEEK_DURATION, "Week not over yet");

        // Calculate total weekly points across all players
        uint256 totalWeeklyPoints = 0;

        for (uint256 i = 0; i < activePlayers.length; i++) {
            address player = activePlayers[i];
            uint256 playerPoints = weeklyPlayerPoints[player];

            if (playerPoints >= minimumPointsThreshold) {
                totalWeeklyPoints += playerPoints;
                // Store claimable points for this player
                claimablePoints[player] += playerPoints;
            }

            // Reset weekly points and active status
            weeklyPlayerPoints[player] = 0;
            isActiveThisWeek[player] = false;
        }

        // Clear active players array for the new week
        delete activePlayers;

        // Start new week
        weekStartTimestamp = block.timestamp;
        emit WeeklyDistributionSnapshot(block.timestamp, totalWeeklyPoints);
    }

    /**
     * @dev Updates the minimum points threshold for eligibility
     * @param newThreshold New threshold value
     */
    function setMinimumPointsThreshold(uint256 newThreshold) external onlyOwner {
        minimumPointsThreshold = newThreshold;
    }

    /**
     * @dev Gets a player's current weekly points
     * @param player Address of the player
     * @return Current weekly points
     */
    function getWeeklyPoints(address player) external view returns (uint256) {
        return weeklyPlayerPoints[player];
    }

    /**
     * @dev Gets a player's total lifetime points
     * @param player Address of the player
     * @return Total lifetime points
     */
    function getTotalPoints(address player) external view returns (uint256) {
        return totalPlayerPoints[player];
    }

    /**
     * @dev Gets a player's claimable points
     * @param player Address of the player
     * @return Claimable points
     */
    function getClaimablePoints(address player) external view returns (uint256) {
        return claimablePoints[player];
    }

    /**
     * @dev Gets time until next weekly distribution
     * @return Seconds until next distribution
     */
    function getTimeUntilNextDistribution() external view returns (uint256) {
        uint256 endOfWeek = weekStartTimestamp + WEEK_DURATION;
        if (block.timestamp >= endOfWeek) {
            return 0;
        }
        return endOfWeek - block.timestamp;
    }

    /**
     * @dev Gets the number of active players this week
     * @return Active player count
     */
    function getActivePlayerCount() external view returns (uint256) {
        return activePlayers.length;
    }

    /**
     * @dev Get all active players
     * @return Array of active player addresses
     */
    function getAllActivePlayers() external view returns (address[] memory) {
        return activePlayers;
    }

    /**
     * @dev Get total number of unique players who have earned points
     * @return Total player count
     */
    function getTotalPlayerCount() external view returns (uint256) {
        return allPlayers.length;
    }

    /**
     * @dev Get top N players by weekly points
     * @param count Number of top players to return
     * @return Array of player addresses sorted by weekly points (highest first)
     * @return Array of corresponding point values
     */
    function getTopPlayersByWeeklyPoints(uint256 count) external view returns (address[] memory, uint256[] memory) {
        // Limit count to the number of active players
        uint256 resultCount = count;
        if (activePlayers.length < resultCount) {
            resultCount = activePlayers.length;
        }

        // Create arrays for results
        address[] memory topPlayers = new address[](resultCount);
        uint256[] memory topPoints = new uint256[](resultCount);

        if (resultCount == 0) {
            return (topPlayers, topPoints);
        }

        // Create working arrays
        address[] memory workingPlayers = new address[](activePlayers.length);
        uint256[] memory workingPoints = new uint256[](activePlayers.length);

        // Copy active players and their points
        for (uint256 i = 0; i < activePlayers.length; i++) {
            workingPlayers[i] = activePlayers[i];
            workingPoints[i] = weeklyPlayerPoints[activePlayers[i]];
        }

        // Simple selection sort to find top N players
        for (uint256 i = 0; i < resultCount; i++) {
            uint256 maxPointsIndex = i;

            for (uint256 j = i + 1; j < workingPlayers.length; j++) {
                if (workingPoints[j] > workingPoints[maxPointsIndex]) {
                    maxPointsIndex = j;
                }
            }

            // Swap if needed
            if (maxPointsIndex != i) {
                // Swap points
                uint256 tempPoints = workingPoints[i];
                workingPoints[i] = workingPoints[maxPointsIndex];
                workingPoints[maxPointsIndex] = tempPoints;

                // Swap addresses
                address tempAddress = workingPlayers[i];
                workingPlayers[i] = workingPlayers[maxPointsIndex];
                workingPlayers[maxPointsIndex] = tempAddress;
            }

            // Add to results
            topPlayers[i] = workingPlayers[i];
            topPoints[i] = workingPoints[i];
        }

        return (topPlayers, topPoints);
    }

    /**
     * @dev Get top N players by total points
     * @param count Number of top players to return
     * @return Array of player addresses sorted by total points (highest first)
     * @return Array of corresponding point values
     */
    function getTopPlayersByTotalPoints(uint256 count) external view returns (address[] memory, uint256[] memory) {
        // Limit count to the number of all players
        uint256 resultCount = count;
        if (allPlayers.length < resultCount) {
            resultCount = allPlayers.length;
        }

        // Create arrays for results
        address[] memory topPlayers = new address[](resultCount);
        uint256[] memory topPoints = new uint256[](resultCount);

        if (resultCount == 0) {
            return (topPlayers, topPoints);
        }

        // Use partial insertion sort to find top N players efficiently
        uint256[] memory minHeap = new uint256[](resultCount);
        address[] memory heapAddresses = new address[](resultCount);
        uint256 heapSize = 0;

        // Process all players
        for (uint256 i = 0; i < allPlayers.length; i++) {
            address player = allPlayers[i];
            uint256 points = totalPlayerPoints[player];

            if (heapSize < resultCount) {
                // Heap not full, add this player
                minHeap[heapSize] = points;
                heapAddresses[heapSize] = player;
                heapSize++;
                _heapifyUp(minHeap, heapAddresses, heapSize - 1);
            } else if (points > minHeap[0]) {
                // This player has more points than the minimum in our heap
                minHeap[0] = points;
                heapAddresses[0] = player;
                _heapifyDown(minHeap, heapAddresses, 0, heapSize);
            }
        }

        // Extract elements from heap in descending order
        for (uint256 i = 0; i < heapSize; i++) {
            uint256 idx = heapSize - 1 - i;
            topPlayers[idx] = heapAddresses[0];
            topPoints[idx] = minHeap[0];

            if (i < heapSize - 1) {
                minHeap[0] = minHeap[heapSize - 1 - i];
                heapAddresses[0] = heapAddresses[heapSize - 1 - i];
                _heapifyDown(minHeap, heapAddresses, 0, heapSize - 1 - i);
            }
        }

        return (topPlayers, topPoints);
    }

    /**
     * @dev Helper function to maintain min heap property when inserting
     */
    function _heapifyUp(uint256[] memory heap, address[] memory addresses, uint256 index) private pure {
        while (index > 0) {
            uint256 parentIndex = (index - 1) / 2;
            if (heap[index] >= heap[parentIndex]) {
                break;
            }

            // Swap with parent
            uint256 tempPoints = heap[index];
            heap[index] = heap[parentIndex];
            heap[parentIndex] = tempPoints;

            address tempAddress = addresses[index];
            addresses[index] = addresses[parentIndex];
            addresses[parentIndex] = tempAddress;

            index = parentIndex;
        }
    }

    /**
     * @dev Helper function to maintain min heap property when removing
     */
    function _heapifyDown(uint256[] memory heap, address[] memory addresses, uint256 index, uint256 heapSize) private pure {
        while (true) {
            uint256 smallest = index;
            uint256 leftChild = 2 * index + 1;
            uint256 rightChild = 2 * index + 2;

            if (leftChild < heapSize && heap[leftChild] < heap[smallest]) {
                smallest = leftChild;
            }

            if (rightChild < heapSize && heap[rightChild] < heap[smallest]) {
                smallest = rightChild;
            }

            if (smallest == index) {
                break;
            }

            // Swap with smallest child
            uint256 tempPoints = heap[index];
            heap[index] = heap[smallest];
            heap[smallest] = tempPoints;

            address tempAddress = addresses[index];
            addresses[index] = addresses[smallest];
            addresses[smallest] = tempAddress;

            index = smallest;
        }
    }
}
