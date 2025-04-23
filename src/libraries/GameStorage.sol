// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

/**
 * @title GameStorage
 * @notice Gas-optimized storage library for Battleship game state
 * @dev Provides efficient data structures and helpers for board state, shots, and hits
 */
library GameStorage {
    // Constants for board dimensions and ship configuration
    uint8 internal constant BOARD_SIZE = 10;
    uint8 internal constant TOTAL_SHIP_CELLS = 17; // 5 + 4 + 3 + 3 + 2 = 17 total ship cells

    // Board representation using bit-packed uint256 array
    // For a 10x10 board, we need 100 bits (can fit in a single uint256)
    // Each bit represents a cell: 1 = ship present, 0 = empty
    struct Board {
        uint256 shipPositions; // Bit-packed ship positions (for ZK verification only)
        uint256 hitMap; // Bit-packed hit positions
        uint256 shotMap; // Bit-packed shot positions
        uint8 hitsReceived; // Counter for how many successful hits received
    }

    // Storage for game state
    struct GameState {
        mapping(address => Board) boards; // Maps player addresses to their boards
        address player1; // Address of player 1
        address player2; // Address of player 2
        address currentTurn; // Address of player whose turn it is
        address winner; // Address of winner (if game is completed)
        uint8 gameState; // Game state enum value
    }

    /**
     * @notice Convert x,y coordinates to bit position
     * @param x X coordinate (0-9)
     * @param y Y coordinate (0-9)
     * @return pos Bit position in the packed uint256 (0-99)
     */
    function coordsToBitPosition(uint8 x, uint8 y) internal pure returns (uint8 pos) {
        require(x < BOARD_SIZE && y < BOARD_SIZE, "Invalid coordinates");
        return y * BOARD_SIZE + x;
    }

    /**
     * @notice Convert bit position to x,y coordinates
     * @param pos Bit position (0-99)
     * @return x X coordinate (0-9)
     * @return y Y coordinate (0-9)
     */
    function bitPositionToCoords(uint8 pos) internal pure returns (uint8 x, uint8 y) {
        require(pos < BOARD_SIZE * BOARD_SIZE, "Invalid position");
        return (pos % BOARD_SIZE, pos / BOARD_SIZE);
    }

    /**
     * @notice Store board commitment
     * @dev In the ZK implementation, we store the hash commitment rather than actual positions
     * @param gameState The game state storage
     * @param player Player address
     * @param boardCommitment Hash commitment of the board
     */
    function storeBoard(GameState storage gameState, address player, bytes32 boardCommitment) internal {
        // In our design, the actual board positions remain private
        // We only store the commitment hash on-chain
        // The actual positions are tracked off-chain by the player

        // Initialize the player's board
        Board storage board = gameState.boards[player];

        // Store commitment by using it to initialize the board state
        // This is a placeholder, as the real commitment verification happens in ZKVerifier
        board.shipPositions = uint256(boardCommitment);
        board.shotMap = 0;
        board.hitMap = 0;
        board.hitsReceived = 0;
    }

    /**
     * @notice Record a shot
     * @param gameState The game state storage
     * @param _shooter Player making the shot
     * @param target Player being targeted
     * @param x X coordinate
     * @param y Y coordinate
     * @return success Whether the shot was successfully recorded (not a repeat)
     */
    function recordShot(
        GameState storage gameState,
        address _shooter,
        address target,
        uint8 x,
        uint8 y
    )
        internal
        returns (bool success)
    {
        uint8 position = coordsToBitPosition(x, y);

        // Check if this position has been shot before
        bool alreadyShot = (gameState.boards[target].shotMap & (1 << position)) != 0;
        if (alreadyShot) {
            return false;
        }

        // Record the shot in target's shotMap
        gameState.boards[target].shotMap |= (1 << position);
        return true;
    }

    /**
     * @notice Record a hit
     * @param gameState The game state storage
     * @param target Player being hit
     * @param x X coordinate
     * @param y Y coordinate
     * @return gameOver Whether the game is over (all ships sunk)
     */
    function recordHit(
        GameState storage gameState,
        address target,
        uint8 x,
        uint8 y
    )
        internal
        returns (bool gameOver)
    {
        uint8 position = coordsToBitPosition(x, y);

        // Set the bit in the hitMap
        gameState.boards[target].hitMap |= (1 << position);

        // Increment hits received counter
        gameState.boards[target].hitsReceived += 1;

        // Check if all ships are sunk
        return gameState.boards[target].hitsReceived >= TOTAL_SHIP_CELLS;
    }

    /**
     * @notice Check if all ships are sunk for a player
     * @param gameState The game state storage
     * @param player Player to check
     * @return allSunk True if all ships are sunk
     */
    function checkAllShipsSunk(GameState storage gameState, address player) internal view returns (bool allSunk) {
        return gameState.boards[player].hitsReceived >= TOTAL_SHIP_CELLS;
    }

    /**
     * @notice Check if coordinates have been shot
     * @param gameState The game state storage
     * @param player Player to check
     * @param x X coordinate
     * @param y Y coordinate
     * @return shot Whether the position has been shot
     */
    function isShot(GameState storage gameState, address player, uint8 x, uint8 y) internal view returns (bool shot) {
        uint8 position = coordsToBitPosition(x, y);
        return (gameState.boards[player].shotMap & (1 << position)) != 0;
    }

    /**
     * @notice Check if coordinates have been hit
     * @param gameState The game state storage
     * @param player Player to check
     * @param x X coordinate
     * @param y Y coordinate
     * @return hit Whether the position has been hit
     */
    function isHit(GameState storage gameState, address player, uint8 x, uint8 y) internal view returns (bool hit) {
        uint8 position = coordsToBitPosition(x, y);
        return (gameState.boards[player].hitMap & (1 << position)) != 0;
    }

    /**
     * @notice Get state fingerprint for verification
     * @param gameState The game state storage
     * @return fingerprint A bytes32 hash representing the current game state
     */
    function getStateFingerprint(GameState storage gameState) internal view returns (bytes32 fingerprint) {
        return keccak256(
            abi.encodePacked(
                gameState.boards[gameState.player1].shotMap,
                gameState.boards[gameState.player1].hitMap,
                gameState.boards[gameState.player1].hitsReceived,
                gameState.boards[gameState.player2].shotMap,
                gameState.boards[gameState.player2].hitMap,
                gameState.boards[gameState.player2].hitsReceived,
                gameState.currentTurn,
                gameState.gameState
            )
        );
    }

    /**
     * @notice Get shot history hash for a player
     * @param gameState The game state storage
     * @param player Player address
     * @return shotHistoryHash Hash of shot history
     */
    function getShotHistoryHash(
        GameState storage gameState,
        address player
    )
        internal
        view
        returns (bytes32 shotHistoryHash)
    {
        return keccak256(abi.encodePacked(gameState.boards[player].shotMap, gameState.boards[player].hitMap));
    }
}
