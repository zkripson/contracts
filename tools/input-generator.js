// input-generator.js
import fs from "fs";
import { ethers } from "ethers";
import BN from "bn.js";

// Board size
const BOARD_SIZE = 10;

// Ship types and lengths
const SHIPS = [
  { name: "Carrier", length: 5 },
  { name: "Battleship", length: 4 },
  { name: "Cruiser", length: 3 },
  { name: "Submarine", length: 3 },
  { name: "Destroyer", length: 2 },
];

// Total number of ship cells
const TOTAL_SHIP_CELLS = SHIPS.reduce((sum, ship) => sum + ship.length, 0); // Should be 17

/**
 * Generates a random integer between min and max (inclusive)
 */
function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

/**
 * Generate a random salt for the commitment
 */
function generateSalt() {
  // Generate a random number between 1 and 10^15
  return Math.floor(Math.random() * 10 ** 15).toString();
}

/**
 * Generates random ship placements that don't overlap
 */
function generateShipPlacements() {
  const board = Array(BOARD_SIZE)
    .fill()
    .map(() => Array(BOARD_SIZE).fill(false));
  const ships = [];

  for (const ship of SHIPS) {
    let placed = false;
    let attempts = 0;
    const maxAttempts = 100;

    while (!placed && attempts < maxAttempts) {
      attempts++;

      // Randomly choose orientation (horizontal or vertical)
      const isHorizontal = Math.random() < 0.5;

      // Calculate max start positions based on ship length
      const maxStartX = isHorizontal ? BOARD_SIZE - ship.length : BOARD_SIZE - 1;
      const maxStartY = isHorizontal ? BOARD_SIZE - 1 : BOARD_SIZE - ship.length;

      // Generate random start position
      const startX = randomInt(0, maxStartX);
      const startY = randomInt(0, maxStartY);

      // Calculate end position based on orientation
      const endX = isHorizontal ? startX + ship.length - 1 : startX;
      const endY = isHorizontal ? startY : startY + ship.length - 1;

      // Check if all cells are free
      let canPlace = true;
      for (let x = startX; x <= endX; x++) {
        for (let y = startY; y <= endY; y++) {
          if (board[y][x]) {
            canPlace = false;
            break;
          }
        }
        if (!canPlace) break;
      }

      // Place the ship if all cells are free
      if (canPlace) {
        for (let x = startX; x <= endX; x++) {
          for (let y = startY; y <= endY; y++) {
            board[y][x] = true;
          }
        }

        ships.push({
          name: ship.name,
          start_x: startX,
          start_y: startY,
          end_x: endX,
          end_y: endY,
        });

        placed = true;
      }
    }

    if (!placed) {
      console.error(`Failed to place ${ship.name} after ${maxAttempts} attempts`);
      return generateShipPlacements(); // Try again from scratch
    }
  }

  return ships;
}

/**
 * Checks if a shot at (x, y) hits any of the ships
 */
function checkHit(ships, x, y) {
  for (const ship of ships) {
    const minX = Math.min(ship.start_x, ship.end_x);
    const maxX = Math.max(ship.start_x, ship.end_x);
    const minY = Math.min(ship.start_y, ship.end_y);
    const maxY = Math.max(ship.start_y, ship.end_y);

    if (x >= minX && x <= maxX && y >= minY && y <= maxY) {
      return true;
    }
  }
  return false;
}

/**
 * Generates all shots that would hit ships
 */
function generateAllHitShots(ships) {
  const hits = [];

  for (const ship of ships) {
    const minX = Math.min(ship.start_x, ship.end_x);
    const maxX = Math.max(ship.start_x, ship.end_x);
    const minY = Math.min(ship.start_y, ship.end_y);
    const maxY = Math.max(ship.start_y, ship.end_y);

    for (let x = minX; x <= maxX; x++) {
      for (let y = minY; y <= maxY; y++) {
        hits.push({ x, y });
      }
    }
  }

  return hits;
}

/**
 * Generates a random shot that would miss all ships
 */
function generateMissShot(ships) {
  let x, y;
  let isMiss = false;

  while (!isMiss) {
    x = randomInt(0, BOARD_SIZE - 1);
    y = randomInt(0, BOARD_SIZE - 1);

    isMiss = !checkHit(ships, x, y);
  }

  return { x, y };
}

/**
 * Generate a shot that would hit a ship
 */
function generateHitShot(ships) {
  // Get all possible hit positions
  const allHits = generateAllHitShots(ships);

  // Pick a random hit
  const randomIndex = randomInt(0, allHits.length - 1);
  return allHits[randomIndex];
}

/**
 * Format the ships for Prover.toml
 */
function formatShipsForToml(ships) {
  let toml = "";

  for (const ship of ships) {
    toml += `# ${ship.name} - Length ${
      Math.max(Math.abs(ship.end_x - ship.start_x), Math.abs(ship.end_y - ship.start_y)) + 1
    }\n`;
    toml += `[[ships]]\n`;
    toml += `start_x = "${ship.start_x}"\n`;
    toml += `start_y = "${ship.start_y}"\n`;
    toml += `end_x = "${ship.end_x}"\n`;
    toml += `end_y = "${ship.end_y}"\n\n`;
  }

  return toml;
}

/**
 * Format the shots for Prover.toml
 */
function formatShotsForToml(shots) {
  let toml = "";

  for (const shot of shots) {
    toml += `[[shots]]\n`;
    toml += `x = "${shot.x}"\n`;
    toml += `y = "${shot.y}"\n\n`;
  }

  return toml;
}

/**
 * Generate inputs for the board placement circuit
 */
function generateBoardPlacementInputs() {
  const ships = generateShipPlacements();
  const salt = generateSalt();

  let toml = `board_commitment = "0" # For proving, this will be calculated; for verification, use the actual commitment\n`;
  toml += `salt = "${salt}" # Use a random number as salt\n\n`;
  toml += formatShipsForToml(ships);

  fs.writeFileSync("../circuit/board_placement/Prover.toml", toml);
  console.log("Generated board placement inputs");
}

/**
 * Generate inputs for the shot result circuit
 */
function generateShotResultInputs() {
  const ships = generateShipPlacements();
  const salt = generateSalt();

  // Generate one hit and one miss shot
  const hitShot = generateHitShot(ships);

  let toml = `board_commitment = "0" # Will be calculated for proving\n`;
  toml += `salt = "${salt}"\n`;
  toml += `shot_x = "${hitShot.x}"\n`;
  toml += `shot_y = "${hitShot.y}"\n`;
  toml += `is_hit = "true"\n\n`;
  toml += formatShipsForToml(ships);

  fs.writeFileSync("../circuit/shot_result/Prover.toml", toml);
  console.log("Generated shot result inputs");

  // Create a miss version too
  const missShot = generateMissShot(ships);

  let tomlMiss = `board_commitment = "0" # Will be calculated for proving\n`;
  tomlMiss += `salt = "${salt}"\n`;
  tomlMiss += `shot_x = "${missShot.x}"\n`;
  tomlMiss += `shot_y = "${missShot.y}"\n`;
  tomlMiss += `is_hit = "false"\n\n`;
  tomlMiss += formatShipsForToml(ships);

  fs.writeFileSync("../circuit/shot_result/Prover.miss.toml", tomlMiss);
  console.log("Generated shot result (miss) inputs");
}

/**
 * Generate inputs for the game end circuit
 */
function generateGameEndInputs() {
  const ships = generateShipPlacements();
  const salt = generateSalt();
  const allHits = generateAllHitShots(ships);

  let toml = `board_commitment = "0" # Will be calculated for proving\n`;
  toml += `salt = "${salt}"\n`;
  toml += `shot_history_hash = "0" # Will be calculated for proving\n\n`;
  toml += formatShipsForToml(ships);

  // Add shots section with hit descriptions
  let shotCount = 0;
  for (const ship of ships) {
    const length = Math.max(Math.abs(ship.end_x - ship.start_x), Math.abs(ship.end_y - ship.start_y)) + 1;

    toml += `# ${ship.name} hits (${length})\n`;

    // Generate shots for this ship
    const isHorizontal = ship.start_y === ship.end_y;
    const normalizedStartX = Math.min(ship.start_x, ship.end_x);
    const normalizedStartY = Math.min(ship.start_y, ship.end_y);

    if (isHorizontal) {
      for (let i = 0; i < length; i++) {
        const x = normalizedStartX + i;
        const y = normalizedStartY;
        toml += `[[shots]]\n`;
        toml += `x = "${x}"\n`;
        toml += `y = "${y}"\n\n`;
        shotCount++;
      }
    } else {
      for (let i = 0; i < length; i++) {
        const x = normalizedStartX;
        const y = normalizedStartY + i;
        toml += `[[shots]]\n`;
        toml += `x = "${x}"\n`;
        toml += `y = "${y}"\n\n`;
        shotCount++;
      }
    }
  }

  fs.writeFileSync("../circuit/game_end/Prover.toml", toml);
  console.log(`Generated game end inputs with ${shotCount} hit shots`);
}

// Generate inputs for all three circuits
function generateAllInputs() {
  generateBoardPlacementInputs();
  generateShotResultInputs();
  generateGameEndInputs();
  console.log("All inputs generated successfully");
}

// Run the generator
generateAllInputs();
