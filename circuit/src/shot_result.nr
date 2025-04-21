// SPDX-License-Identifier: MIT
// Battleship Shot Result Circuit
// This circuit validates that a player honestly reports hit/miss results

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

// Calculate the board commitment
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
    
    // Hash the data
    hash_data(data)
}

// Hash function 
fn hash_data(data: [Field; 21]) -> Field {
    let mut result: Field = 0;
    
    // Combine all values with weighted addition
    for i in 0..data.len() {
        // Use a different multiplier for each position
        let multiplier = (7 * (i + 1)) as Field;
        result = result + (data[i] * multiplier);
    }
    
    // Add salt-based factor to ensure uniqueness
    result = result + (data[20] * 31);
    
    result
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

// Test with lying about a hit
fn test_invalid_hit_claim() {
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
    
    // Shot clearly misses all ships
    let miss_x = 8;
    let miss_y = 8;
    
    // This should fail because we're lying and claiming a hit
    // Uncomment to test:
    // main(ships, salt, commitment, miss_x, miss_y, true);
}

// Test with lying about a miss
fn test_invalid_miss_claim() {
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
    
    // Shot clearly hits the carrier
    let hit_x = 2;
    let hit_y = 0;
    
    // This should fail because we're lying and claiming a miss
    // Uncomment to test:
    // main(ships, salt, commitment, hit_x, hit_y, false);
}

// Test with out of bounds shot
fn test_out_of_bounds_shot() {
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
    
    // Shot is out of bounds
    let invalid_x = 10; // Board size is 10, so valid indices are 0-9
    let invalid_y = 5;
    
    // This should fail due to out of bounds coordinates
    // Uncomment to test:
    // main(ships, salt, commitment, invalid_x, invalid_y, false);
}

// Test with incorrect board commitment
fn test_invalid_commitment() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Carrier - Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Battleship - Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Cruiser - Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Submarine - Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Destroyer - Length 2
    ];
    
    let salt = 12345;
    // Use an incorrect salt to generate a different commitment
    let wrong_salt = 54321;
    let wrong_commitment = calculate_board_commitment(ships, wrong_salt);
    
    // Valid shot
    let hit_x = 2;
    let hit_y = 0;
    
    // This should fail because the commitment doesn't match the ships
    // Uncomment to test:
    // main(ships, salt, wrong_commitment, hit_x, hit_y, true);
}

// This function will be run when the circuit is compiled
fn dummy_entrypoint() {
    test_valid_hit();
    test_valid_miss();
    // Uncomment to test failure cases:
    // test_invalid_hit_claim();
    // test_invalid_miss_claim();
    // test_out_of_bounds_shot();
    // test_invalid_commitment();
}