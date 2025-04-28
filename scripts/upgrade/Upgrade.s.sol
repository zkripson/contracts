// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import "../../src/BattleShipGameImplementation.sol";
import "../../src/factories/GameFactory.sol";

/**
 * @title UpgradeZKBattleship
 * @notice Upgrade script for ZK Battleship on MegaETH
 * @dev Run with: forge script script/upgrade/UpgradeZKBattleship.s.sol --rpc-url $MEGAETH_RPC_URL --broadcast
 */
contract UpgradeZKBattleship is Script {
    // Address of the existing GameFactory contract
    address public constant GAME_FACTORY = 0x75d67fc7a0d77128416d2D55b00c857e780999d7;

    function run() external {
        console2.log("Starting ZK Battleship upgrade on MegaETH...");
        uint256 deployerPrivateKey = _getPrivateKey();

        // Deploy new implementation
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the new implementation contract
        BattleshipGameImplementation newImplementation = new BattleshipGameImplementation();
        address newImplementationAddress = address(newImplementation);

        console2.log("New implementation deployed at:", newImplementationAddress);

        // Update the implementation in the GameFactory
        GameFactory factory = GameFactory(GAME_FACTORY);
        factory.setImplementation(newImplementationAddress);

        vm.stopBroadcast();

        console2.log("Upgrade completed. New games will use the updated implementation.");
    }

    /// @notice Get the private key for deployment
    function _getPrivateKey() internal view returns (uint256) {
        try vm.envUint("PRIVATE_KEY") returns (uint256 privateKey) {
            return privateKey;
        } catch {
            console2.log("PRIVATE_KEY environment variable not set or invalid");
            revert("PRIVATE_KEY environment variable not set or invalid");
        }
    }
}
