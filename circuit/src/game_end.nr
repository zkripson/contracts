// SPDX-License-Identifier: MIT
// Battleship Game End Circuit
// This circuit verifies that all ships have been hit, validating a win condition

// A ship is defined by its start and end coordinates
struct Ship {
    start_x: u8,
    start_y: u8,
    end_x: u8,
    end_y: u8
}

// Shot coordinates
struct Shot {
    x: u8,
    y: u8
}

// Main circuit for game end validation
fn main(
    // Private inputs
    ships: [Ship; 5],              // Private: Ship positions
    salt: Field,                   // Private: Random salt for commitment
    shots: [Shot; 17],             // Private: All shots that hit ships (17 is total ship cells)
    
    // Public inputs
    board_commitment: pub Field,    // Public: Commitment to board state
    shot_history_hash: pub Field    // Public: Hash of shot history
) {
    // Step 1: Verify board commitment
    let calculated_commitment = calculate_board_commitment(ships, salt);
    assert(calculated_commitment == board_commitment);
    
    // Step 2: Verify shot history hash
    let calculated_shot_hash = calculate_shot_history_hash(shots);
    assert(calculated_shot_hash == shot_history_hash);
    
    // Step 3: Verify all ships are hit by the provided shots
    verify_all_ships_hit(ships, shots);
    
    // Step 4: Verify all shots actually hit ships
    // This prevents including irrelevant shots in the proof
    for i in 0..shots.len() {
        let hit = is_position_hit(ships, shots[i].x, shots[i].y);
        assert(hit);
    }
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

// Check if a position hits any ship
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

// Verify that all ship positions have been hit
fn verify_all_ships_hit(ships: [Ship; 5], shots: [Shot; 17]) {
    for i in 0..5 {
        let ship = normalize_ship(ships[i]);
        
        if ship.start_x == ship.end_x {
            // Vertical ship
            for y in ship.start_y..ship.end_y + 1 {
                assert(position_in_shots(ship.start_x, y, shots));
            }
        } else {
            // Horizontal ship
            for x in ship.start_x..ship.end_x + 1 {
                assert(position_in_shots(x, ship.start_y, shots));
            }
        }
    }
}

// Check if a position exists in the shots array
fn position_in_shots(x: u8, y: u8, shots: [Shot; 17]) -> bool {
    let mut found = false;
    
    for i in 0..shots.len() {
        if shots[i].x == x {
            if shots[i].y == y {
                found = true;
            }
        }
    }
    
    found
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

// Calculate the shot history hash
fn calculate_shot_history_hash(shots: [Shot; 17]) -> Field {
    // Flatten shot data for hashing
    let mut data: [Field; 34] = [0; 34]; // 17 shots x 2 coordinates
    
    for i in 0..shots.len() {
        data[i*2] = shots[i].x as Field;
        data[i*2 + 1] = shots[i].y as Field;
    }
    
    // Hash the data
    hash_shot_data(data)
}

// Hash function for board data
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

// Hash function for shot data
fn hash_shot_data(data: [Field; 34]) -> Field {
    let mut result: Field = 0;
    
    // Combine all values with weighted addition
    for i in 0..data.len() {
        // Use a different multiplier for each position
        let multiplier = (13 * (i + 1)) as Field;
        result = result + (data[i] * multiplier);
    }
    
    result
}

// Test valid game end where all ships are hit
fn test_valid_game_end() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Carrier - Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Battleship - Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Cruiser - Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Submarine - Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Destroyer - Length 2
    ];
    let salt = 12345;
    
    // Create shots that hit all ships
    let shots = [
        // First ship (Carrier - length 5)
        Shot { x: 0, y: 0 },
        Shot { x: 1, y: 0 },
        Shot { x: 2, y: 0 },
        Shot { x: 3, y: 0 },
        Shot { x: 4, y: 0 },
        
        // Second ship (Battleship - length 4)
        Shot { x: 0, y: 2 },
        Shot { x: 1, y: 2 },
        Shot { x: 2, y: 2 },
        Shot { x: 3, y: 2 },
        
        // Third ship (Cruiser - length 3)
        Shot { x: 5, y: 5 },
        Shot { x: 6, y: 5 },
        Shot { x: 7, y: 5 },
        
        // Fourth ship (Submarine - length 3)
        Shot { x: 9, y: 0 },
        Shot { x: 9, y: 1 },
        Shot { x: 9, y: 2 },
        
        // Fifth ship (Destroyer - length 2)
        Shot { x: 3, y: 7 },
        Shot { x: 4, y: 7 }
    ];
    
    // Calculate commitments
    let board_commitment = calculate_board_commitment(ships, salt);
    let shot_history_hash = calculate_shot_history_hash(shots);
    
    // Verify game end conditions
    main(ships, salt, shots, board_commitment, shot_history_hash);
}

// Test incomplete ship hits (should fail)
fn test_incomplete_ship_hits() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Carrier - Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Battleship - Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Cruiser - Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Submarine - Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Destroyer - Length 2
    ];
    let salt = 12345;
    
    // Create shots that miss one cell of the first ship
    let shots = [
        // First ship (Carrier - length 5) - missing position (4,0)
        Shot { x: 0, y: 0 },
        Shot { x: 1, y: 0 },
        Shot { x: 2, y: 0 },
        Shot { x: 3, y: 0 },
        // Missing Shot { x: 4, y: 0 }, - instead adding a duplicate
        Shot { x: 3, y: 0 }, // Duplicate to maintain array size
        
        // Second ship (Battleship - length 4)
        Shot { x: 0, y: 2 },
        Shot { x: 1, y: 2 },
        Shot { x: 2, y: 2 },
        Shot { x: 3, y: 2 },
        
        // Third ship (Cruiser - length 3)
        Shot { x: 5, y: 5 },
        Shot { x: 6, y: 5 },
        Shot { x: 7, y: 5 },
        
        // Fourth ship (Submarine - length 3)
        Shot { x: 9, y: 0 },
        Shot { x: 9, y: 1 },
        Shot { x: 9, y: 2 },
        
        // Fifth ship (Destroyer - length 2)
        Shot { x: 3, y: 7 },
        Shot { x: 4, y: 7 }
    ];
    
    // Calculate commitments
    let board_commitment = calculate_board_commitment(ships, salt);
    let shot_history_hash = calculate_shot_history_hash(shots);
    
    // This should fail due to incomplete hits
    // Uncomment to test:
    // main(ships, salt, shots, board_commitment, shot_history_hash);
}

// Test with a shot that doesn't hit any ship (should fail)
fn test_shot_on_nonexistent_ship() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Carrier - Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Battleship - Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Cruiser - Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Submarine - Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Destroyer - Length 2
    ];
    let salt = 12345;
    
    // Create shots with one miss
    let shots = [
        // First 16 shots hit ships correctly
        Shot { x: 0, y: 0 },
        Shot { x: 1, y: 0 },
        Shot { x: 2, y: 0 },
        Shot { x: 3, y: 0 },
        Shot { x: 4, y: 0 },
        Shot { x: 0, y: 2 },
        Shot { x: 1, y: 2 },
        Shot { x: 2, y: 2 },
        Shot { x: 3, y: 2 },
        Shot { x: 5, y: 5 },
        Shot { x: 6, y: 5 },
        Shot { x: 7, y: 5 },
        Shot { x: 9, y: 0 },
        Shot { x: 9, y: 1 },
        Shot { x: 9, y: 2 },
        Shot { x: 3, y: 7 },
        
        // Last shot doesn't hit any ship (8,8)
        Shot { x: 8, y: 8 }
    ];
    
    // Calculate commitments
    let board_commitment = calculate_board_commitment(ships, salt);
    let shot_history_hash = calculate_shot_history_hash(shots);
    
    // This should fail due to including a shot that doesn't hit any ship
    // Uncomment to test:
    // main(ships, salt, shots, board_commitment, shot_history_hash);
}

// Test tampered commitment (should fail)
fn test_tampered_commitment() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Carrier - Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Battleship - Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Cruiser - Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Submarine - Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Destroyer - Length 2
    ];
    let salt = 12345;
    
    // Create valid shots that hit all ships
    let shots = [
        Shot { x: 0, y: 0 },
        Shot { x: 1, y: 0 },
        Shot { x: 2, y: 0 },
        Shot { x: 3, y: 0 },
        Shot { x: 4, y: 0 },
        Shot { x: 0, y: 2 },
        Shot { x: 1, y: 2 },
        Shot { x: 2, y: 2 },
        Shot { x: 3, y: 2 },
        Shot { x: 5, y: 5 },
        Shot { x: 6, y: 5 },
        Shot { x: 7, y: 5 },
        Shot { x: 9, y: 0 },
        Shot { x: 9, y: 1 },
        Shot { x: 9, y: 2 },
        Shot { x: 3, y: 7 },
        Shot { x: 4, y: 7 }
    ];
    
    // Calculate shot history hash correctly
    let shot_history_hash = calculate_shot_history_hash(shots);
    
    // Use an incorrect salt to generate a different board commitment
    let wrong_salt = 54321;
    let incorrect_commitment = calculate_board_commitment(ships, wrong_salt);
    
    // This should fail due to incorrect board commitment
    // Uncomment to test:
    // main(ships, salt, shots, incorrect_commitment, shot_history_hash);
}

// Test tampered shot history (should fail)
fn test_tampered_shot_history() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Carrier - Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Battleship - Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Cruiser - Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Submarine - Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Destroyer - Length 2
    ];
    let salt = 12345;
    
    // Create valid shots that hit all ships
    let shots = [
        Shot { x: 0, y: 0 },
        Shot { x: 1, y: 0 },
        Shot { x: 2, y: 0 },
        Shot { x: 3, y: 0 },
        Shot { x: 4, y: 0 },
        Shot { x: 0, y: 2 },
        Shot { x: 1, y: 2 },
        Shot { x: 2, y: 2 },
        Shot { x: 3, y: 2 },
        Shot { x: 5, y: 5 },
        Shot { x: 6, y: 5 },
        Shot { x: 7, y: 5 },
        Shot { x: 9, y: 0 },
        Shot { x: 9, y: 1 },
        Shot { x: 9, y: 2 },
        Shot { x: 3, y: 7 },
        Shot { x: 4, y: 7 }
    ];
    
    // Calculate board commitment correctly
    let board_commitment = calculate_board_commitment(ships, salt);
    
    // Create different shots for an incorrect hash
    let different_shots = [
        Shot { x: 0, y: 0 },
        Shot { x: 1, y: 0 },
        Shot { x: 2, y: 0 },
        Shot { x: 3, y: 0 },
        Shot { x: 4, y: 0 },
        Shot { x: 0, y: 2 },
        Shot { x: 1, y: 2 },
        Shot { x: 2, y: 2 },
        Shot { x: 3, y: 2 },
        Shot { x: 5, y: 5 },
        Shot { x: 6, y: 5 },
        Shot { x: 7, y: 5 },
        Shot { x: 9, y: 0 },
        Shot { x: 9, y: 1 },
        Shot { x: 9, y: 2 },
        Shot { x: 3, y: 8 }, // Changed from (3,7)
        Shot { x: 4, y: 8 }  // Changed from (4,7)
    ];
    
    // Calculate incorrect shot history hash
    let incorrect_shot_history_hash = calculate_shot_history_hash(different_shots);
    
    // This should fail due to mismatched shot history hash
    // Uncomment to test:
    // main(ships, salt, shots, board_commitment, incorrect_shot_history_hash);
}

// This function will be run when the circuit is compiled
fn dummy_entrypoint() {
    test_valid_game_end();
    // Uncomment to test failure cases:
    // test_incomplete_ship_hits();
    // test_shot_on_nonexistent_ship();
    // test_tampered_commitment();
    // test_tampered_shot_history();
}