// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

/**
 * @title ZKVerifier Interface
 * @dev Interface for interacting with the ZKVerifier contract
 */
interface IZKVerifier {
    function verifyBoardPlacement(bytes32 boardCommitment, bytes calldata proof) external view returns (bool);
    function verifyShotResult(
        bytes32 boardCommitment,
        uint8 x,
        uint8 y,
        bool isHit,
        bytes calldata proof
    )
        external
        view
        returns (bool);
    function verifyGameEnd(
        bytes32 boardCommitment,
        bytes32 shotHistoryHash,
        bytes calldata proof
    )
        external
        view
        returns (bool);
}
