// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IVerifier
 * @notice Interface for ZK proof verification
 */
interface IVerifier {
    /**
     * @notice Verify a zero-knowledge proof
     * @param _proof The ZK proof to verify
     * @param _publicInputs Public inputs for the proof verification
     * @return True if the proof is valid, false otherwise
     */
    function verify(bytes calldata _proof, bytes32[] calldata _publicInputs) external view returns (bool);
}