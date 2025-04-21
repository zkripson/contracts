// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Base deployment script for Kripson
 * @notice Contains utility functions for deploying upgradeable contracts on Kripson
 */
abstract contract BaseDeployScript is Script {
    /// @notice Get the private key for deployment
    function _getPrivateKey() internal view returns (uint256) {
        try vm.envUint("PRIVATE_KEY") returns (uint256 privateKey) {
            return privateKey;
        } catch {
            console2.log("PRIVATE_KEY environment variable not set or invalid");
            revert("PRIVATE_KEY environment variable not set or invalid");
        }
    }

    /// @notice Deploy an implementation contract
    function _deployImplementation(bytes memory creationCode) internal returns (address implementation) {
        uint256 deployerPrivateKey = _getPrivateKey();
        
        vm.startBroadcast(deployerPrivateKey);
        assembly {
            implementation := create(0, add(creationCode, 0x20), mload(creationCode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }
        vm.stopBroadcast();
        
        console2.log("Implementation deployed at:", implementation);
    }

    /// @notice Deploy a proxy pointing to an implementation
    function _deployProxy(address implementation, bytes memory initData) internal returns (address proxy) {
        uint256 deployerPrivateKey = _getPrivateKey();
        
        vm.startBroadcast(deployerPrivateKey);
        proxy = address(new ERC1967Proxy(implementation, initData));
        vm.stopBroadcast();
        
        console2.log("Proxy deployed at:", proxy);
    }
}

/**
 * @title Kripson deployment script
 * @notice Use this script to deploy contracts to Kripson
 * @dev Run with: forge script script/deploy/Deploy.s.sol --rpc-url $MEGAETH_RPC_URL --broadcast
 */
contract DeployKripson is BaseDeployScript {
    function run() external {
        console2.log("Starting deployment to MegaETH...");
        
        // Deployment steps will go here when we have actual contracts
        
        console2.log("Deployment completed successfully");
    }
}