// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import "./interfaces/IVerifiers.sol";

/**
 * @title ZKVerifier
 * @notice Wrapper contract for verifying different types of ZK proofs
 * @dev Handles verification for board placement, shot results, and game end conditions
 */
contract ZKVerifier {
    // Verifier contracts for each type of proof
    IBoardPlacementVerifier public immutable boardPlacementVerifier;
    IShotResultVerifier public immutable shotResultVerifier;
    IGameEndVerifier public immutable gameEndVerifier;

    // Contract owner for upgrades
    address public owner;

    // Events
    event VerifierUpdated(string verifierType, address verifierAddress);

    /// @notice Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    /// @notice Constructor sets initial verifier addresses
    /// @param _boardPlacementVerifier Address of the board placement verifier contract
    /// @param _shotResultVerifier Address of the shot result verifier contract
    /// @param _gameEndVerifier Address of the game end verifier contract
    constructor(address _boardPlacementVerifier, address _shotResultVerifier, address _gameEndVerifier) {
        boardPlacementVerifier = IBoardPlacementVerifier(_boardPlacementVerifier);
        shotResultVerifier = IShotResultVerifier(_shotResultVerifier);
        gameEndVerifier = IGameEndVerifier(_gameEndVerifier);
        owner = msg.sender;
    }

    /// @notice Verify valid board placement
    /// @param boardCommitment Commitment to the board placement
    /// @param proof Zero-knowledge proof of valid board placement
    /// @return True if the board placement is valid
    function verifyBoardPlacement(bytes32 boardCommitment, bytes calldata proof) external view returns (bool) {
        // Convert boardCommitment to the format required by the verifier
        bytes32[] memory publicInputs = new bytes32[](1);
        publicInputs[0] = boardCommitment;

        // Call the Noir-generated verifier
        return boardPlacementVerifier.verify(proof, publicInputs);
    }

    /// @notice Verify shot result
    /// @param boardCommitment Commitment to the target player's board
    /// @param x X-coordinate of the shot
    /// @param y Y-coordinate of the shot
    /// @param isHit Boolean indicating if the shot hit a ship
    /// @param proof Zero-knowledge proof of the shot result
    /// @return True if the shot result is correctly reported
    function verifyShotResult(
        bytes32 boardCommitment,
        uint8 x,
        uint8 y,
        bool isHit,
        bytes calldata proof
    )
        external
        view
        returns (bool)
    {
        // Convert all inputs to the format required by the verifier
        bytes32[] memory publicInputs = new bytes32[](4);
        publicInputs[0] = boardCommitment;
        publicInputs[1] = bytes32(uint256(x));
        publicInputs[2] = bytes32(uint256(y));
        publicInputs[3] = isHit ? bytes32(uint256(1)) : bytes32(uint256(0));

        // Call the Noir-generated verifier
        return shotResultVerifier.verify(proof, publicInputs);
    }

    /// @notice Verify game ending state
    /// @param boardCommitment Commitment to player's board
    /// @param shotHistoryHash Hash of the shot history
    /// @param proof Zero-knowledge proof that all ships are sunk
    /// @return True if the game ending condition is valid
    function verifyGameEnd(
        bytes32 boardCommitment,
        bytes32 shotHistoryHash,
        bytes calldata proof
    )
        external
        view
        returns (bool)
    {
        // Convert inputs to the format required by the verifier
        bytes32[] memory publicInputs = new bytes32[](2);
        publicInputs[0] = boardCommitment;
        publicInputs[1] = shotHistoryHash;

        // Call the Noir-generated verifier
        return gameEndVerifier.verify(proof, publicInputs);
    }

    /// @notice Transfer ownership to a new address
    /// @param _newOwner Address of the new owner
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "New owner cannot be zero address");
        owner = _newOwner;
    }
}
