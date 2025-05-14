// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import "../../src/BattleshipGameImplementation.sol";
import "../../src/factories/GameFactory.sol";
import "../../src/BattleshipStatistics.sol";

/**
 * @title UpgradeZKBattleship
 * @notice Upgrade script for ZK Battleship on MegaETH
 * @dev Run with: forge script script/upgrade/UpgradeZKBattleship.s.sol --rpc-url $MEGAETH_RPC_URL --broadcast
 */
contract UpgradeZKBattleship is Script {
    // Addresses of the existing contracts - these will be replaced by environment variables
    address public gameFactoryAddress;
    address public statisticsAddress;

    function run() external {
        console2.log("Starting ZK Battleship upgrade on Base Sepolia...");
        uint256 deployerPrivateKey = _getPrivateKey();
        
        // Load addresses from environment variables
        _loadAddresses();

        // Deploy new implementation
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the new implementation contract
        BattleshipGameImplementation newImplementation = new BattleshipGameImplementation();
        address newImplementationAddress = address(newImplementation);

        console2.log("New implementation deployed at:", newImplementationAddress);

        // Update the implementation in the GameFactory
        GameFactoryWithStats factory = GameFactoryWithStats(gameFactoryAddress);
        factory.setImplementation(newImplementationAddress);
        
        // Ensure the GameFactory has the STATS_UPDATER_ROLE in the Statistics contract
        BattleshipStatistics statistics = BattleshipStatistics(statisticsAddress);
        bytes32 statsUpdaterRole = statistics.STATS_UPDATER_ROLE();
        
        if (!statistics.hasRole(statsUpdaterRole, gameFactoryAddress)) {
            console2.log("Granting STATS_UPDATER_ROLE to GameFactory");
            statistics.grantRole(statsUpdaterRole, gameFactoryAddress);
        } else {
            console2.log("GameFactory already has STATS_UPDATER_ROLE");
        }

        vm.stopBroadcast();

        console2.log("Upgrade completed. New games will use the updated implementation.");
        console2.log("Statistics permissions verified. GameFactory can update statistics.");
    }
    
    /// @notice Load contract addresses from environment variables
    function _loadAddresses() internal {
        string memory gameFactoryEnv = "GAME_FACTORY_ADDRESS";
        string memory statisticsEnv = "STATS_ADDRESS";
        
        try vm.envAddress(gameFactoryEnv) returns (address factoryAddress) {
            gameFactoryAddress = factoryAddress;
        } catch {
            console2.log("GAME_FACTORY_ADDRESS environment variable not set or invalid");
            revert("GAME_FACTORY_ADDRESS environment variable not set or invalid");
        }
        
        try vm.envAddress(statisticsEnv) returns (address statsAddress) {
            statisticsAddress = statsAddress;
        } catch {
            console2.log("STATS_ADDRESS environment variable not set or invalid");
            revert("STATS_ADDRESS environment variable not set or invalid");
        }
        
        console2.log("Loaded GameFactory address:", gameFactoryAddress);
        console2.log("Loaded Statistics address:", statisticsAddress);
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
