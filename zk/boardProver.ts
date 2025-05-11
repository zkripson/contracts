import { ethers } from "ethers";
import { CIRCUIT_PATHS, generateProof } from "./noirConfig";

// Ship sizes in Battleship game
const SHIP_SIZES = [5, 4, 3, 3, 2];

// Board size (10x10)
const BOARD_SIZE = 10;

// Field modulos
const F_MOD =
  21888242871839275222246405745257275088548364400416034343698204186575808495617n;

// Interface for ship placement
export interface Ship {
  size: number;
  x: number;
  y: number;
  horizontal: boolean;
}

// Interface for board state
export interface Board {
  ships: Ship[];
  grid: number[][]; // 0 = empty, 1 = ship
}

/**
 * Generates a cryptographic commitment for a board layout
 * @param board The player's board with ship placements
 * @param salt A random salt value to protect the commitment
 * @returns The commitment as a bytes32 string
 */
export function generateBoardCommitment(board: Board, salt: string): string {
  // Convert board to a compact string representation
  const boardString = serializeBoard(board);

  // Hash the board with the salt using keccak256
  const commitment = ethers.keccak256(
    ethers.solidityPacked(
      ["string", "bytes32"],
      [boardString, ethers.encodeBytes32String(salt)],
    ),
  );

  return commitment;
}

/**
 * Serialize board to a compact string
 * @param board The player's board
 * @returns A string representation of the board
 */
function serializeBoard(board: Board): string {
  // Flatten 2D grid to 1D array of 0s and 1s
  const flattened = board.grid.flat().join("");
  return flattened;
}

/**
 * Create a board from ship placements
 * @param ships Array of ships with positions
 * @returns A complete board with grid representation
 */
export function createBoard(ships: Ship[]): Board {
  // Initialize empty grid
  const grid = Array(BOARD_SIZE)
    .fill(0)
    .map(() => Array(BOARD_SIZE).fill(0));

  // Place ships on grid
  for (const ship of ships) {
    for (let i = 0; i < ship.size; i++) {
      const x = ship.horizontal ? ship.x + i : ship.x;
      const y = ship.horizontal ? ship.y : ship.y + i;

      // Check bounds
      if (x >= BOARD_SIZE || y >= BOARD_SIZE) {
        throw new Error(`Ship placement out of bounds: (${x}, ${y})`);
      }

      // Check overlap
      if (grid[y][x] !== 0) {
        throw new Error(`Ship overlap at (${x}, ${y})`);
      }

      grid[y][x] = 1;
    }
  }

  return { ships, grid };
}

/**
 * Validate that a board placement is legal
 * @param board The board to validate
 * @returns true if valid, throws error if invalid
 */
export function validateBoard(board: Board): boolean {
  // Check number of ships
  if (board.ships.length !== SHIP_SIZES.length) {
    throw new Error(`Invalid number of ships: ${board.ships.length}`);
  }

  // Check each ship is the correct size
  const shipSizeCount = new Map<number, number>();
  for (const ship of board.ships) {
    shipSizeCount.set(ship.size, (shipSizeCount.get(ship.size) || 0) + 1);
  }

  const expectedCounts = new Map<number, number>();
  for (const size of SHIP_SIZES) {
    expectedCounts.set(size, (expectedCounts.get(size) || 0) + 1);
  }

  for (const [size, count] of expectedCounts.entries()) {
    if ((shipSizeCount.get(size) || 0) !== count) {
      throw new Error(`Invalid number of ships of size ${size}`);
    }
  }

  // Check grid representation matches ships
  const reconstructedBoard = createBoard(board.ships);

  // Count cells in both boards
  const originalCount = board.grid.flat().filter((cell) => cell === 1).length;
  const reconstructedCount = reconstructedBoard.grid
    .flat()
    .filter((cell) => cell === 1).length;

  if (originalCount !== reconstructedCount) {
    throw new Error("Grid representation doesn't match ships");
  }

  return true;
}

/**
 * Generate a ZK proof that a board placement is valid
 * @param board The player's board
 * @param salt Random salt used in the commitment
 * @returns ZK proof as a hex string
 */
export async function generateBoardProof(
  board: Board,
  salt: string,
): Promise<string> {
  try {
    // Validate board first
    validateBoard(board);

    // Convert board to Noir-compatible format
    const boardCells = new Array(100).fill(0);
    // Fill in ship positions with 1s
    for (let y = 0; y < BOARD_SIZE; y++) {
      for (let x = 0; x < BOARD_SIZE; x++) {
        if (board.grid[y][x] === 1) {
          boardCells[y * BOARD_SIZE + x] = 1;
        }
      }
    }

    // Format ships for Noir input
    // const formattedShips = board.ships.map((ship) => ({
    //   start_x: ship.size,
    //   end_x: ship.x,
    //   start_y: ship.y,
    //   end_y: ship.horizontal ? 1 : 0, // Convert boolean to 0/1 for Noir
    // }));
    const formattedShips = board.ships.map((ship) => ({
      size: ship.size,
      x: ship.x,
      y: ship.y,
      horizontal: ship.horizontal ? 1 : 0, // Convert boolean to 0/1 for Noir
    }));

    // Ensure we have exactly 5 ships
    while (formattedShips.length < 5) {
      // Add dummy ships if needed (should never happen with valid boards)
      formattedShips.push({ size: 0, x: 0, y: 0, horizontal: 0 });
      // formattedShips.push({ size: 0, start_x: 0, start_y: 0, horizontal: 0 });
    }

    // Calculate board commitment
    const commitment = generateBoardCommitment(board, salt);

    console.log(formattedShips);

    // Prepare circuit input
    const input = {
      board: { cells: boardCells },
      ships: formattedShips,
      salt: salt,
      board_commitment: "0x" + (BigInt(commitment) % F_MOD).toString(16),
    };

    // Use shared proof generation utility
    return await generateProof(CIRCUIT_PATHS.BOARD_PLACEMENT, input);
  } catch (error) {
    console.error("Error generating board proof:", error);
    throw error;
  }
}

/**
 * Generate a random valid board layout
 * @returns A valid random board with ships placed
 */
export function generateRandomBoard(): Board {
  const ships: Ship[] = [];

  // Create temporary grid to track placements
  const tempGrid = Array(BOARD_SIZE)
    .fill(0)
    .map(() => Array(BOARD_SIZE).fill(0));

  // Place each ship
  for (const size of SHIP_SIZES) {
    let placed = false;
    let attempts = 0;
    const maxAttempts = 100;

    while (!placed && attempts < maxAttempts) {
      attempts++;

      // Random position and orientation
      const horizontal = Math.random() > 0.5;
      const maxX = horizontal ? BOARD_SIZE - size : BOARD_SIZE - 1;
      const maxY = horizontal ? BOARD_SIZE - 1 : BOARD_SIZE - size;

      const x = Math.floor(Math.random() * (maxX + 1));
      const y = Math.floor(Math.random() * (maxY + 1));

      // Check if placement is valid
      let valid = true;

      // Check cells and surrounding cells
      for (let i = -1; i <= size; i++) {
        for (let j = -1; j <= 1; j++) {
          const checkX = horizontal ? x + i : x + j;
          const checkY = horizontal ? y + j : y + i;

          // Skip out of bounds checks
          if (
            checkX < 0 ||
            checkX >= BOARD_SIZE ||
            checkY < 0 ||
            checkY >= BOARD_SIZE
          ) {
            continue;
          }

          // If this is part of the ship (not surrounding), ignore edge cases
          if (
            (horizontal && i >= 0 && i < size && j === 0) ||
            (!horizontal && i >= 0 && i < size && j === 0)
          ) {
            // Only check the actual ship cell
            if (tempGrid[checkY][checkX] !== 0) {
              valid = false;
              break;
            }
          } else {
            // For surrounding cells, check if they contain a ship
            if (tempGrid[checkY][checkX] !== 0) {
              valid = false;
              break;
            }
          }
        }
        if (!valid) break;
      }

      if (valid) {
        // Place the ship
        const ship = { size, x, y, horizontal };
        ships.push(ship);

        // Update temp grid
        for (let i = 0; i < size; i++) {
          const placeX = horizontal ? x + i : x;
          const placeY = horizontal ? y : y + i;
          tempGrid[placeY][placeX] = 1;
        }

        placed = true;
      }
    }

    if (!placed) {
      // If we couldn't place a ship after max attempts, start over
      return generateRandomBoard();
    }
  }

  return createBoard(ships);
}

/**
 * Generate a random salt for board commitment
 * @returns A random string to use as salt
 */
export function generateSalt(): string {
  return ethers.hexlify(ethers.randomBytes(14));
  //   return ethers.hexlify(ethers.randomBytes(15)).slice(2);
}
