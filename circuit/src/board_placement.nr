use dep::std;

// Define board size
const BOARD_SIZE: u8 = 10;
// Define ship sizes
const SHIP_SIZES: [u8; 5] = [5, 4, 3, 3, 2];

// A ship is defined by its start and end coordinates
struct Ship {
    start_x: u8,
    start_y: u8,
    end_x: u8,
    end_y: u8
}

// Main circuit for board placement validation
fn main(
    ships: [Ship; 5],   // Private: Ship positions
    salt: Field,        // Private: Random salt for commitment
    board_commitment: pub Field  // Public: Commitment to board state
) {
    // Step 1: Validate each ship is within bounds and has correct size
    for i in 0..5 {
        let ship = ships[i];
        
        // Check ship is on the board
        constrain ship.start_x < BOARD_SIZE;
        constrain ship.start_y < BOARD_SIZE;
        constrain ship.end_x < BOARD_SIZE;
        constrain ship.end_y < BOARD_SIZE;
        
        // Check ship is either horizontal or vertical
        let is_horizontal = ship.start_y == ship.end_y;
        let is_vertical = ship.start_x == ship.end_x;
        constrain is_horizontal | is_vertical;
        constrain !(is_horizontal & is_vertical) | (ship.start_x == ship.end_x & ship.start_y == ship.end_y);
        
        // Ensure start coordinates are less than or equal to end coordinates
        let normalized_ship = normalize_ship(ship);
        
        // Calculate ship length
        let length = if is_horizontal {
            normalized_ship.end_x - normalized_ship.start_x + 1
        } else {
            normalized_ship.end_y - normalized_ship.start_y + 1
        };
        
        // Verify correct ship size
        constrain length == SHIP_SIZES[i];
    }
    
    // Step 2: Check no ships overlap
    for i in 0..4 {
        for j in (i+1)..5 {
            constrain !ships_overlap(ships[i], ships[j]);
        }
    }
    
    // Step 3: Calculate and verify board commitment
    let calculated_commitment = calculate_board_commitment(ships, salt);
    constrain calculated_commitment == board_commitment;
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

// Check if two ships overlap
fn ships_overlap(ship1: Ship, ship2: Ship) -> bool {
    // Normalize ships so start coordinates are less than end
    let s1 = normalize_ship(ship1);
    let s2 = normalize_ship(ship2);
    
    // Ship 1 horizontal
    if s1.start_y == s1.end_y {
        // Ship 2 horizontal
        if s2.start_y == s2.end_y {
            // Both horizontal - check if they're on the same row and overlap
            if s1.start_y == s2.start_y {
                // Check overlap on x-axis
                return !(s1.end_x < s2.start_x || s1.start_x > s2.end_x);
            } else {
                // Different rows, no overlap
                return false;
            }
        } else {
            // Ship 1 horizontal, Ship 2 vertical
            // Check if vertical ship crosses the horizontal ship's row
            if s2.start_x >= s1.start_x && s2.start_x <= s1.end_x && 
               s1.start_y >= s2.start_y && s1.start_y <= s2.end_y {
                return true;
            } else {
                return false;
            }
        }
    } else {
        // Ship 1 vertical
        if s2.start_y == s2.end_y {
            // Ship 1 vertical, Ship 2 horizontal
            // Check if horizontal ship crosses the vertical ship's column
            if s1.start_x >= s2.start_x && s1.start_x <= s2.end_x && 
               s2.start_y >= s1.start_y && s2.start_y <= s1.end_y {
                return true;
            } else {
                return false;
            }
        } else {
            // Both vertical - check if they're on the same column and overlap
            if s1.start_x == s2.start_x {
                // Check overlap on y-axis
                return !(s1.end_y < s2.start_y || s1.start_y > s2.end_y);
            } else {
                // Different columns, no overlap
                return false;
            }
        }
    }
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
fn test_valid_board() {
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
    
    // Verify the main circuit with these values
    main(ships, salt, commitment);
}

#[test]
fn test_overlapping_ships_fails() {
    // Create a board with overlapping ships
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 4, end_y: 0 }, // Length 5
        Ship { start_x: 0, start_y: 0, end_x: 3, end_y: 0 }, // Overlaps with first ship
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Length 2
    ];
    let salt = 12345;
    
    // Calculate commitment
    let commitment = calculate_board_commitment(ships, salt);
    
    // This should fail due to overlap
    let success = std::testing::assert_fails(|| main(ships, salt, commitment));
    assert(success);
}

#[test]
fn test_invalid_ship_size_fails() {
    // Create a board with an invalid ship size
    let ships = [
        Ship { start_x: 0, start_y: 0, end_x: 5, end_y: 0 }, // Length 6 (invalid)
        Ship { start_x: 0, start_y: 2, end_x: 3, end_y: 2 }, // Length 4
        Ship { start_x: 5, start_y: 5, end_x: 7, end_y: 5 }, // Length 3
        Ship { start_x: 9, start_y: 0, end_x: 9, end_y: 2 }, // Length 3
        Ship { start_x: 3, start_y: 7, end_x: 4, end_y: 7 }  // Length 2
    ];
    let salt = 12345;
    
    // Calculate commitment
    let commitment = calculate_board_commitment(ships, salt);
    
    // This should fail due to invalid ship size
    let success = std::testing::assert_fails(|| main(ships, salt, commitment));
    assert(success);
}