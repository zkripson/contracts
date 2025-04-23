// SPDX-License-Identifier: MIT
// Battleship Shot Result Circuit with Improved Hashing

// Import the standard library
use std::hash;

// A ship is defined by its start and end coordinates
struct Ship {
    start_x: u8,
    start_y: u8,
    end_x: u8,
    end_y: u8
}

// Main circuit for shot result validation
fn main(
    // Private inputs
    ships: [Ship; 5],        // Private: Ship positions
    salt: Field,             // Private: Random salt for commitment
    
    // Public inputs
    board_commitment: pub Field, // Public: Commitment to board state
    shot_x: pub u8,              // Public: X-coordinate of the shot
    shot_y: pub u8,              // Public: Y-coordinate of the shot
    is_hit: pub bool             // Public: Whether the shot hit a ship
) {
    // Board size - 10x10 grid
    let board_size = 10;
    
    // Step 1: Validate shot coordinates are within board boundaries
    assert(shot_x < board_size);
    assert(shot_y < board_size);
    
    // Step 2: Verify board commitment
    let calculated_commitment = calculate_board_commitment(ships, salt);
    assert(calculated_commitment == board_commitment);
    
    // Step 3: Check if the shot hits any ship
    let actual_hit = is_position_hit(ships, shot_x, shot_y);
    
    // Step 4: Verify claimed result matches actual result
    assert(actual_hit == is_hit);
}

// Normalize ship coordinates so start is always less than or equal to end
fn normalize_ship(ship: Ship) -> Ship {
    if ship.start_x == ship.end_x {
        // Vertical ship
        if ship.start_y <= ship.end_y {
            ship
        } else {
            Ship {
                start_x: ship.start_x,
                start_y: ship.end_y,
                end_x: ship.end_x,
                end_y: ship.start_y
            }
        }
    } else {
        // Horizontal ship
        if ship.start_x <= ship.end_x {
            ship
        } else {
            Ship {
                start_x: ship.end_x,
                start_y: ship.start_y,
                end_x: ship.start_x,
                end_y: ship.end_y
            }
        }
    }
}

// Check if a position hits a ship
fn is_position_hit(ships: [Ship; 5], x: u8, y: u8) -> bool {
    let mut hit = false;
    
    for i in 0..5 {
        let ship = normalize_ship(ships[i]);
        
        if ship.start_x == ship.end_x {
            // Vertical ship - check if x matches and y is within range
            if x == ship.start_x {
                if y >= ship.start_y {
                    if y <= ship.end_y {
                        hit = true;
                    }
                }
            }
        } else {
            // Horizontal ship - check if y matches and x is within range
            if y == ship.start_y {
                if x >= ship.start_x {
                    if x <= ship.end_x {
                        hit = true;
                    }
                }
            }
        }
    }
    
    hit
}

// Calculate the board commitment using Pedersen hash
fn calculate_board_commitment(ships: [Ship; 5], salt: Field) -> Field {
    // Flatten ship data for hashing
    let mut data: [Field; 21] = [0; 21]; // 5 ships x 4 coordinates + 1 salt
    
    for i in 0..5 {
        data[i*4] = ships[i].start_x as Field;
        data[i*4 + 1] = ships[i].start_y as Field;
        data[i*4 + 2] = ships[i].end_x as Field;
        data[i*4 + 3] = ships[i].end_y as Field;
    }
    data[20] = salt;
    
    // Use the Pedersen hash from the standard library
    hash::pedersen_hash(data)
}

// Test with hit
fn test_valid_hit() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Carrier - Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Battleship - Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Cruiser - Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Submarine - Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Destroyer - Length 2
    ];
    
    let salt = 12345;
    let commitment = calculate_board_commitment(ships, salt);
    
    // Test a shot that hits the carrier
    let hit_x = 2;
    let hit_y = 0;
    
    // This should pass with is_hit = true
    main(ships, salt, commitment, hit_x, hit_y, true);
}

// Test with miss
fn test_valid_miss() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Carrier - Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Battleship - Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Cruiser - Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Submarine - Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Destroyer - Length 2
    ];
    
    let salt = 12345;
    let commitment = calculate_board_commitment(ships, salt);
    
    // Test a shot that misses all ships
    let miss_x = 8;
    let miss_y = 8;
    
    // This should pass with is_hit = false
    main(ships, salt, commitment, miss_x, miss_y, false);
}

// This function will be run when the circuit is compiled
fn dummy_entrypoint() {
    test_valid_hit();
    test_valid_miss();
}