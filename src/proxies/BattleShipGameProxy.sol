// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title BattleshipGameProxy
 * @dev Proxy contract that delegates calls to the current implementation
 * @notice This proxy uses ERC1967 standard for upgradeable contracts
 */
contract BattleshipGameProxy is ERC1967Proxy {
    /**
     * @notice Constructor for the proxy
     * @param _logic Address of the initial implementation
     * @param _data Initialization calldata to be passed to implementation
     */
    constructor(address _logic, bytes memory _data) ERC1967Proxy(_logic, _data) { }
}
