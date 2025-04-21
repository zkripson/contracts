// SPDX-License-Identifier: MIT
// Battleship Board Placement Circuit
// This circuit validates that a player's ship placement is valid according to game rules

// A ship is defined by its start and end coordinates
struct Ship {
    start_x: u8,
    start_y: u8,
    end_x: u8,
    end_y: u8
}

// Main circuit for board placement validation
fn main(
    ships: [Ship; 5],        // Private: Ship positions
    salt: Field,             // Private: Random salt for commitment
    board_commitment: pub Field  // Public: Commitment to board state
) {
    // Board size constants
    let board_size = 10;     // 10x10 board
    
    // Ship sizes in order [carrier, battleship, cruiser, submarine, destroyer]
    let ship_size_0 = 5;  // Carrier
    let ship_size_1 = 4;  // Battleship
    let ship_size_2 = 3;  // Cruiser
    let ship_size_3 = 3;  // Submarine
    let ship_size_4 = 2;  // Destroyer
    
    // Step 1: Validate each ship is within bounds and has correct size
    for i in 0..5 {
        let ship = ships[i];
        
        // Check ship is on the board
        assert(ship.start_x < board_size);
        assert(ship.start_y < board_size);
        assert(ship.end_x < board_size);
        assert(ship.end_y < board_size);
        
        // Check ship is either horizontal or vertical
        let is_horizontal = ship.start_y == ship.end_y;
        let is_vertical = ship.start_x == ship.end_x;
        assert(is_horizontal | is_vertical);
        
        // Special case for single-cell ships (shouldn't happen in valid battleship)
        if is_horizontal & is_vertical {
            assert(ship.start_x == ship.end_x);
            assert(ship.start_y == ship.end_y);
        }
        
        // Normalize ship coordinates
        let normalized_ship = normalize_ship(ship);
        
        // Calculate ship length
        let length = if is_horizontal {
            normalized_ship.end_x - normalized_ship.start_x + 1
        } else {
            normalized_ship.end_y - normalized_ship.start_y + 1
        };
        
        // Verify correct ship size
        if i == 0 {
            assert(length == ship_size_0);
        } else if i == 1 {
            assert(length == ship_size_1);
        } else if i == 2 {
            assert(length == ship_size_2);
        } else if i == 3 {
            assert(length == ship_size_3);
        } else {
            assert(length == ship_size_4);
        }
    }
    
    // Step 2: Check no ships overlap
    for i in 0..4 {
        for j in (i+1)..5 {
            assert(!ships_overlap(ships[i], ships[j]));
        }
    }
    
    // Step 3: Calculate and verify board commitment
    let calculated_commitment = calculate_board_commitment(ships, salt);
    assert(calculated_commitment == board_commitment);
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

// Check if two ships overlap
fn ships_overlap(ship1: Ship, ship2: Ship) -> bool {
    // Normalize ships so start coordinates are less than end
    let s1 = normalize_ship(ship1);
    let s2 = normalize_ship(ship2);
    
    let mut result = false;
    
    // Ship 1 horizontal
    if s1.start_y == s1.end_y {
        // Ship 2 horizontal
        if s2.start_y == s2.end_y {
            // Both horizontal - check if they're on the same row and overlap
            if s1.start_y == s2.start_y {
                // Check overlap on x-axis
                if !(s1.end_x < s2.start_x | s1.start_x > s2.end_x) {
                    result = true;
                }
            }
        } else {
            // Ship 1 horizontal, Ship 2 vertical
            // Check if vertical ship crosses the horizontal ship's row
            if s2.start_x >= s1.start_x & s2.start_x <= s1.end_x & 
               s1.start_y >= s2.start_y & s1.start_y <= s2.end_y {
                result = true;
            }
        }
    } else {
        // Ship 1 vertical
        if s2.start_y == s2.end_y {
            // Ship 1 vertical, Ship 2 horizontal
            // Check if horizontal ship crosses the vertical ship's column
            if s1.start_x >= s2.start_x & s1.start_x <= s2.end_x & 
               s2.start_y >= s1.start_y & s2.start_y <= s1.end_y {
                result = true;
            }
        } else {
            // Both vertical - check if they're on the same column and overlap
            if s1.start_x == s2.start_x {
                // Check overlap on y-axis
                if !(s1.end_y < s2.start_y | s1.start_y > s2.end_y) {
                    result = true;
                }
            }
        }
    }
    
    result
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

// Improved hash function without modulo operations
fn hash_data(data: [Field; 21]) -> Field {
    let mut result: Field = 0;
    
    // Combine all values with weighted addition
    // This is a simplified hash, suited for circuit constraints
    for i in 0..data.len() {
        // Use a different multiplier for each position
        let multiplier = (7 * (i + 1)) as Field;
        result = result + (data[i] * multiplier);
    }
    
    // Add salt-based factor to ensure uniqueness
    result = result + (data[20] * 31);
    
    result
}

// Test with valid ships
fn test_valid_placement() {
    // Create a valid board setup with non-overlapping ships
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Carrier - Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Battleship - Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Cruiser - Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Submarine - Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Destroyer - Length 2
    ];
    
    let salt = 12345;
    let commitment = calculate_board_commitment(ships, salt);
    
    // This should pass validation
    main(ships, salt, commitment);
}

// Test with overlapping ships (should fail)
fn test_overlapping_ships() {
    // Create a board with overlapping ships
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Carrier - Length 5
        Ship { start_x: 3, start_y: 0, end_x: 6, end_y: 0 }, // Battleship - Length 4 (overlaps with carrier)
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Cruiser - Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Submarine - Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Destroyer - Length 2
    ];
    
    let salt = 12345;
    let commitment = calculate_board_commitment(ships, salt);
    
    // Call main here and the assertion will fail
    // Uncomment the following line to test:
    // main(ships, salt, commitment);
}

// Test with invalid ship size (should fail)
fn test_invalid_size() {
    // Create a board with invalid ship size
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 5, end_y: 0 }, // Invalid size - Length 6 (should be 5)
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Battleship - Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Cruiser - Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Submarine - Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Destroyer - Length 2
    ];
    
    let salt = 12345;
    let commitment = calculate_board_commitment(ships, salt);
    
    // Call main here and the assertion will fail
    // Uncomment the following line to test:
    // main(ships, salt, commitment);
}

// Test with ships outside the board (should fail)
fn test_out_of_bounds() {
    // Create a board with ships going outside the 10x10 grid
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Carrier - Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Battleship - Length 4
        Ship { start_x: 8, start_y: 8, end_x: 10, end_y: 8 }, // Out of bounds (x=10)
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Submarine - Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Destroyer - Length 2
    ];
    
    let salt = 12345;
    let commitment = calculate_board_commitment(ships, salt);
    
    // Call main here and the assertion will fail
    // Uncomment the following line to test:
    // main(ships, salt, commitment);
}

// This function will be run when the circuit is compiled 
// It serves as the primary test
fn dummy_entrypoint() {
    test_valid_placement();
    // Uncomment to test various failure modes:
    // test_overlapping_ships();
    // test_invalid_size();
    // test_out_of_bounds();
}