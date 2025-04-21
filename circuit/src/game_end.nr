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
    constrain calculated_commitment == board_commitment;
    
    // Step 2: Verify shot history hash
    let calculated_shot_hash = calculate_shot_history_hash(shots);
    constrain calculated_shot_hash == shot_history_hash;
    
    // Step 3: Verify all ships are hit by the provided shots
    verify_all_ships_hit(ships, shots);
    
    // Step 4: Verify all shots actually hit ships
    // This prevents including irrelevant shots in the proof
    for i in 0..shots.len() {
        let hit = is_position_hit(ships, shots[i].x, shots[i].y);
        constrain hit == true;
    }
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

// Verify that all ships are hit completely
fn verify_all_ships_hit(ships: [Ship; 5], shots: [Shot; 17]) {
    for i in 0..5 {
        let ship = normalize_ship(ships[i]);
        
        if ship.start_x == ship.end_x {
            // Vertical ship
            for y in ship.start_y..=ship.end_y {
                constrain position_in_shots(ship.start_x, y, shots);
            }
        } else {
            // Horizontal ship
            for x in ship.start_x..=ship.end_x {
                constrain position_in_shots(x, ship.start_y, shots);
            }
        }
    }
}

// Check if a position exists in the shots array
fn position_in_shots(x: u8, y: u8, shots: [Shot; 17]) -> bool {
    for i in 0..shots.len() {
        if shots[i].x == x && shots[i].y == y {
            return true;
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

// Calculate the shot history hash using Pedersen hash
fn calculate_shot_history_hash(shots: [Shot; 17]) -> Field {
    // Flatten shot data for hashing
    let mut data: [Field; 34] = [0; 34]; // 17 shots × 2 coordinates
    
    for i in 0..shots.len() {
        data[i*2] = shots[i].x as Field;
        data[i*2 + 1] = shots[i].y as Field;
    }
    
    return std::hash::pedersen(data);
}

// Test vectors
#[test]
fn test_valid_game_end() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Length 2
    ];
    let salt = 12345;
    
    // Create shots that hit all ships
    let shots = [
        // First ship (length 5)
        Shot { x: 0, y: 0 },
        Shot { x: 1, y: 0 },
        Shot { x: 2, y: 0 },
        Shot { x: 3, y: 0 },
        Shot { x: 4, y: 0 },
        
        // Second ship (length 4)
        Shot { x: 0, y: 2 },
        Shot { x: 1, y: 2 },
        Shot { x: 2, y: 2 },
        Shot { x: 3, y: 2 },
        
        // Third ship (length 3)
        Shot { x: 5, y: 5 },
        Shot { x: 6, y: 5 },
        Shot { x: 7, y: 5 },
        
        // Fourth ship (length 3)
        Shot { x: 9, y: 0 },
        Shot { x: 9, y: 1 },
        Shot { x: 9, y: 2 },
        
        // Fifth ship (length 2)
        Shot { x: 3, y: 7 },
        Shot { x: 4, y: 7 }
    ];
    
    // Calculate commitments
    let board_commitment = calculate_board_commitment(ships, salt);
    let shot_history_hash = calculate_shot_history_hash(shots);
    
    // Verify game end conditions
    main(ships, salt, shots, board_commitment, shot_history_hash);
}

#[test]
fn test_incomplete_ship_hits_fails() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Length 2
    ];
    let salt = 12345;
    
    // Create shots that miss one cell of the first ship
    let shots = [
        // First ship (length 5) - missing position (4,0)
        Shot { x: 0, y: 0 },
        Shot { x: 1, y: 0 },
        Shot { x: 2, y: 0 },
        Shot { x: 3, y: 0 },
        
        // Second ship (length 4)
        Shot { x: 0, y: 2 },
        Shot { x: 1, y: 2 },
        Shot { x: 2, y: 2 },
        Shot { x: 3, y: 2 },
        
        // Third ship (length 3)
        Shot { x: 5, y: 5 },
        Shot { x: 6, y: 5 },
        Shot { x: 7, y: 5 },
        
        // Fourth ship (length 3)
        Shot { x: 9, y: 0 },
        Shot { x: 9, y: 1 },
        Shot { x: 9, y: 2 },
        
        // Fifth ship (length 2)
        Shot { x: 3, y: 7 },
        Shot { x: 4, y: 7 },
        
        // Add a dummy shot to maintain array size
        Shot { x: 0, y: 1 }
    ];
    
    // Calculate commitments
    let board_commitment = calculate_board_commitment(ships, salt);
    let shot_history_hash = calculate_shot_history_hash(shots);
    
    // This should fail due to incomplete hits
    let success = std::testing::assert_fails(|| main(ships, salt, shots, board_commitment, shot_history_hash));
    assert(success);
}

#[test]
fn test_shot_on_nonexistent_ship_fails() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Length 2
    ];
    let salt = 12345;
    
    // Create shots with one miss
    let shots = [
        // First ship (length 5)
        Shot { x: 0, y: 0 },
        Shot { x: 1, y: 0 },
        Shot { x: 2, y: 0 },
        Shot { x: 3, y: 0 },
        Shot { x: 4, y: 0 },
        
        // Second ship (length 4)
        Shot { x: 0, y: 2 },
        Shot { x: 1, y: 2 },
        Shot { x: 2, y: 2 },
        Shot { x: 3, y: 2 },
        
        // Third ship (length 3)
        Shot { x: 5, y: 5 },
        Shot { x: 6, y: 5 },
        Shot { x: 7, y: 5 },
        
        // Fourth ship (length 3)
        Shot { x: 9, y: 0 },
        Shot { x: 9, y: 1 },
        Shot { x: 9, y: 2 },
        
        // One shot that doesn't hit any ship (this should fail)
        Shot { x: 8, y: 8 }
    ];
    
    // Calculate commitments
    let board_commitment = calculate_board_commitment(ships, salt);
    let shot_history_hash = calculate_shot_history_hash(shots);
    
    // This should fail due to including a shot that doesn't hit any ship
    let success = std::testing::assert_fails(|| main(ships, salt, shots, board_commitment, shot_history_hash));
    assert(success);
}

#[test]
fn test_missing_ship_hits_fails() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Length 2
    ];
    let salt = 12345;
    
    // Create shots missing an entire ship
    let shots = [
        // First ship (length 5)
        Shot { x: 0, y: 0 },
        Shot { x: 1, y: 0 },
        Shot { x: 2, y: 0 },
        Shot { x: 3, y: 0 },
        Shot { x: 4, y: 0 },
        
        // Second ship (length 4)
        Shot { x: 0, y: 2 },
        Shot { x: 1, y: 2 },
        Shot { x: 2, y: 2 },
        Shot { x: 3, y: 2 },
        
        // Third ship (length 3)
        Shot { x: 5, y: 5 },
        Shot { x: 6, y: 5 },
        Shot { x: 7, y: 5 },
        
        // Fourth ship (length 3) - completely missing
        
        // Fifth ship (length 2)
        Shot { x: 3, y: 7 },
        Shot { x: 4, y: 7 },
        
        // Add additional dummy shots to maintain array size
        Shot { x: 1, y: 1 },
        Shot { x: 2, y: 2 },
        Shot { x: 3, y: 3 },
        Shot { x: 4, y: 4 }
    ];
    
    // Calculate commitments
    let board_commitment = calculate_board_commitment(ships, salt);
    let shot_history_hash = calculate_shot_history_hash(shots);
    
    // This should fail due to missing hits on the fourth ship
    let success = std::testing::assert_fails(|| main(ships, salt, shots, board_commitment, shot_history_hash));
    assert(success);
}

#[test]
fn test_tampered_commitment_fails() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Length 2
    ];
    let salt = 12345;
    
    // Create shots that hit all ships
    let shots = [
        // First ship (length 5)
        Shot { x: 0, y: 0 },
        Shot { x: 1, y: 0 },
        Shot { x: 2, y: 0 },
        Shot { x: 3, y: 0 },
        Shot { x: 4, y: 0 },
        
        // Second ship (length 4)
        Shot { x: 0, y: 2 },
        Shot { x: 1, y: 2 },
        Shot { x: 2, y: 2 },
        Shot { x: 3, y: 2 },
        
        // Third ship (length 3)
        Shot { x: 5, y: 5 },
        Shot { x: 6, y: 5 },
        Shot { x: 7, y: 5 },
        
        // Fourth ship (length 3)
        Shot { x: 9, y: 0 },
        Shot { x: 9, y: 1 },
        Shot { x: 9, y: 2 },
        
        // Fifth ship (length 2)
        Shot { x: 3, y: 7 },
        Shot { x: 4, y: 7 }
    ];
    
    // Calculate shot history hash
    let shot_history_hash = calculate_shot_history_hash(shots);
    
    // Use an incorrect board commitment
    let incorrect_salt = 54321; // Different salt
    let incorrect_board_commitment = calculate_board_commitment(ships, incorrect_salt);
    
    // This should fail due to mismatched board commitment
    let success = std::testing::assert_fails(|| main(ships, salt, shots, incorrect_board_commitment, shot_history_hash));
    assert(success);
}

#[test]
fn test_tampered_shots_hash_fails() {
    // Create a valid board setup
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Length 5
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Length 2
    ];
    let salt = 12345;
    
    // Create shots that hit all ships
    let shots = [
        // First ship (length 5)
        Shot { x: 0, y: 0 },
        Shot { x: 1, y: 0 },
        Shot { x: 2, y: 0 },
        Shot { x: 3, y: 0 },
        Shot { x: 4, y: 0 },
        
        // Second ship (length 4)
        Shot { x: 0, y: 2 },
        Shot { x: 1, y: 2 },
        Shot { x: 2, y: 2 },
        Shot { x: 3, y: 2 },
        
        // Third ship (length 3)
        Shot { x: 5, y: 5 },
        Shot { x: 6, y: 5 },
        Shot { x: 7, y: 5 },
        
        // Fourth ship (length 3)
        Shot { x: 9, y: 0 },
        Shot { x: 9, y: 1 },
        Shot { x: 9, y: 2 },
        
        // Fifth ship (length 2)
        Shot { x: 3, y: 7 },
        Shot { x: 4, y: 7 }
    ];
    
    // Calculate board commitment
    let board_commitment = calculate_board_commitment(ships, salt);
    
    // Create a different set of shots for an incorrect hash
    let different_shots = [
        // Modified shots
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
    let success = std::testing::assert_fails(|| main(ships, salt, shots, board_commitment, incorrect_shot_history_hash));
    assert(success);
}