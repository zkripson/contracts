// SPDX-License-Identifier: MIT
use dep::std;

// Define board size
const BOARD_SIZE: u8 = 10;

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
    ships: [Ship; 5],   // Private: Ship positions
    salt: Field,        // Private: Random salt for commitment
    
    // Public inputs
    board_commitment: pub Field,  // Public: Commitment to board state
    shot_x: pub u8,              // Public: X-coordinate of the shot
    shot_y: pub u8,              // Public: Y-coordinate of the shot
    is_hit: pub bool             // Public: Whether the shot hit a ship
) {
    // Step 1: Validate shot coordinates are within board boundaries
    constrain shot_x < BOARD_SIZE;
    constrain shot_y < BOARD_SIZE;
    
    // Step 2: Verify board commitment
    let calculated_commitment = calculate_board_commitment(ships, salt);
    constrain calculated_commitment == board_commitment;
    
    // Step 3: Check if the shot hits any ship
    let actual_hit = is_position_hit(ships, shot_x, shot_y);
    
    // Step 4: Verify claimed result matches actual result
    constrain actual_hit == is_hit;
}

// Normalize ship coordinates so start is always less than end
fn normalize_ship(ship: Ship) -> Ship {
    if ship.start_x == ship.end_x {
        // Vertical ship
        if ship.start_y <= ship.end_y {
            return ship;
        } else {
            return Ship {
                start_x: ship.start_x,
                start_y: ship.end_y,
                end_x: ship.end_x,
                end_y: ship.start_y
            };
        }
    } else {
        // Horizontal ship
        if ship.start_x <= ship.end_x {
            return ship;
        } else {
            return Ship {
                start_x: ship.end_x,
                start_y: ship.start_y,
                end_x: ship.start_x,
                end_y: ship.end_y
            };
        }
    }
}

// Check if a position hits a ship
fn is_position_hit(ships: [Ship; 5], x: u8, y: u8) -> bool {
    for i in 0..5 {
        let ship = normalize_ship(ships[i]);
        
        if ship.start_x == ship.end_x {
            // Vertical ship
            if x == ship.start_x && y >= ship.start_y && y <= ship.end_y {
                return true;
            }
        } else {
            // Horizontal ship
            if y == ship.start_y && x >= ship.start_x && x <= ship.end_x {
                return true;
            }
        }
    }
    
    return false;
}

// Calculate the board commitment using Pedersen hash
fn calculate_board_commitment(ships: [Ship; 5], salt: Field) -> Field {
    // Flatten ship data for hashing
    let mut data: [Field; 21] = [0; 21]; // 5 ships × 4 coordinates + 1 salt
    
    for i in 0..5 {
        data[i*4] = ships[i].start_x as Field;
        data[i*4 + 1] = ships[i].start_y as Field;
        data[i*4 + 2] = ships[i].end_x as Field;
        data[i*4 + 3] = ships[i].end_y as Field;
    }
    data[20] = salt;
    
    return std::hash::pedersen(data);
}

// Test vectors
#[test]
fn test_hit_validation() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Length 2
    ];
    let salt = 12345;
    
    // Calculate commitment
    let commitment = calculate_board_commitment(ships, salt);
    
    // Test a hit
    let hit_x = 2;
    let hit_y = 0;
    
    // This should be a hit (on the first ship)
    main(ships, salt, commitment, hit_x, hit_y, true);
    
    // Test a miss
    let miss_x = 8;
    let miss_y = 8;
    
    // This should be a miss
    main(ships, salt, commitment, miss_x, miss_y, false);
}

#[test]
fn test_incorrect_hit_claim_fails() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Length 2
    ];
    let salt = 12345;
    
    // Calculate commitment
    let commitment = calculate_board_commitment(ships, salt);
    
    // This is a miss, but we'll claim it's a hit
    let miss_x = 8;
    let miss_y = 8;
    
    // This should fail due to incorrect claim
    let success = std::testing::assert_fails(|| main(ships, salt, commitment, miss_x, miss_y, true));
    assert(success);
}

#[test]
fn test_out_of_bounds_shot_fails() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Length 2
    ];
    let salt = 12345;
    
    // Calculate commitment
    let commitment = calculate_board_commitment(ships, salt);
    
    // Out of bounds shot
    let invalid_x = 10; // Board size is 10, so valid indices are 0-9
    let invalid_y = 5;
    
    // This should fail due to out of bounds shot
    let success = std::testing::assert_fails(|| main(ships, salt, commitment, invalid_x, invalid_y, false));
    assert(success);
}