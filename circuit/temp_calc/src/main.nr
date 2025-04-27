// calculate_commitment.nr
use std::hash;

// A ship is defined by its start and end coordinates
struct Ship {
    start_x: u8,
    start_y: u8,
    end_x: u8,
    end_y: u8
}

// Return the board commitment as a public value
fn main(
    ships: [Ship; 5],  // Private: Ship positions
    salt: Field,       // Private: Random salt for commitment
) -> pub Field {      // Public return value will be the commitment
    // Calculate and return the commitment
    calculate_board_commitment(ships, salt)
}

// Calculate the board commitment using Pedersen hash - copied from your original circuit
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