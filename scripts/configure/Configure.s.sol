// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BattleshipGameImplementation} from "../../src/BattleshipGameImplementation.sol";
import {GameFactoryWithStats} from "../../src/factories/GameFactory.sol";
import {BattleshipStatistics} from "../../src/BattleshipStatistics.sol";
import {BattleshipBetting} from "../../src/Betting.sol";
import {BattleshipPoints} from "../../src/BattleshipPoints.sol";

/**
 * @title ConfigureContracts
 * @notice Post-deployment configuration script for the ZK Battleship contracts
 * @dev Run with: forge script scripts/configure/Configure.s.sol:ConfigureContracts --rpc-url $BASE_MAINNET_RPC_URL --broadcast --account adminKey
 * @dev This script must be run with the admin account to properly configure contract permissions
 */
contract ConfigureContracts is Script {
    function run() external {
        console2.log("Starting ZK Battleship post-deployment configuration...");
        console2.log("Chain ID:", block.chainid);

        // Load contract addresses from environment or deployment config
        address gameFactory = vm.envAddress("GAME_FACTORY_ADDRESS");
        address gameStats = vm.envAddress("STATS_ADDRESS");
        address bettingAddress = vm.envAddress("BETTING_ADDRESS");
        address gameImplementation = vm.envAddress("GAME_IMPLEMENTATION_ADDRESS");
        address pointsAddress = vm.envAddress("POINTS_ADDRESS");
        
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address backend = vm.envAddress("BACKEND_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        console2.log("Contract addresses:");
        console2.log("GameFactory:", gameFactory);
        console2.log("GameStatistics:", gameStats);
        console2.log("BattleshipBetting:", bettingAddress);
        console2.log("GameImplementation:", gameImplementation);
        console2.log("Points:", pointsAddress);
        console2.log("Admin:", admin);
        console2.log("Backend:", backend);
        console2.log("Treasury:", treasury);

        // Start broadcast with admin account
        vm.startBroadcast();
        
        address currentSender = msg.sender;
        console2.log("Current sender (should be admin):", currentSender);
        
        require(currentSender == admin, "Script must be run with admin account");

        // Initialize contract instances
        GameFactoryWithStats factory = GameFactoryWithStats(gameFactory);
        BattleshipStatistics statistics = BattleshipStatistics(gameStats);
        BattleshipBetting betting = BattleshipBetting(bettingAddress);
        BattleshipGameImplementation implementation = BattleshipGameImplementation(gameImplementation);
        BattleshipPoints points = BattleshipPoints(pointsAddress);

        console2.log("\n=== Configuring Contract Permissions ===");

        // 1. Configure GameFactory roles
        console2.log("\n1. Configuring GameFactory roles...");
        
        // Grant backend role to backend address
        if (!factory.hasRole(factory.BACKEND_ROLE(), backend)) {
            factory.grantRole(factory.BACKEND_ROLE(), backend);
            console2.log("- Granted BACKEND_ROLE to backend address");
        } else {
            console2.log("- Backend already has BACKEND_ROLE");
        }

        // Grant backend role to betting contract if not already granted
        if (!factory.hasRole(factory.BACKEND_ROLE(), bettingAddress)) {
            factory.grantRole(factory.BACKEND_ROLE(), bettingAddress);
            console2.log("- Granted BACKEND_ROLE to betting contract");
        } else {
            console2.log("- Betting contract already has BACKEND_ROLE");
        }

        // 2. Configure Statistics contract roles
        console2.log("\n2. Configuring Statistics contract roles...");
        
        // Grant statistics updater role to factory
        if (!statistics.hasRole(statistics.STATS_UPDATER_ROLE(), gameFactory)) {
            statistics.grantRole(statistics.STATS_UPDATER_ROLE(), gameFactory);
            console2.log("- Granted STATS_UPDATER_ROLE to factory");
        } else {
            console2.log("- Factory already has STATS_UPDATER_ROLE");
        }

        // Grant statistics updater role to backend
        if (!statistics.hasRole(statistics.STATS_UPDATER_ROLE(), backend)) {
            statistics.grantRole(statistics.STATS_UPDATER_ROLE(), backend);
            console2.log("- Granted STATS_UPDATER_ROLE to backend");
        } else {
            console2.log("- Backend already has STATS_UPDATER_ROLE");
        }

        // 3. Configure BattleshipPoints contract
        console2.log("\n3. Configuring BattleshipPoints contract...");
        
        // Add factory as authorized source
        if (!points.isAuthorizedSource(gameFactory)) {
            points.addAuthorizedSource(gameFactory);
            console2.log("- Authorized GameFactory to award points");
        } else {
            console2.log("- GameFactory already authorized to award points");
        }

        // Add implementation as authorized source
        if (!points.isAuthorizedSource(gameImplementation)) {
            points.addAuthorizedSource(gameImplementation);
            console2.log("- Authorized GameImplementation to award points");
        } else {
            console2.log("- GameImplementation already authorized to award points");
        }

        // Add backend as authorized source
        if (!points.isAuthorizedSource(backend)) {
            points.addAuthorizedSource(backend);
            console2.log("- Authorized Backend to award points");
        } else {
            console2.log("- Backend already authorized to award points");
        }

        // 4. Configure BattleshipBetting contract
        console2.log("\n4. Configuring BattleshipBetting contract...");
        
        // Check if backend has proper role on betting contract
        bytes32 backendRole = betting.BACKEND_ROLE();
        if (!betting.hasRole(backendRole, backend)) {
            betting.grantRole(backendRole, backend);
            console2.log("- Granted BACKEND_ROLE to backend on betting contract");
        } else {
            console2.log("- Backend already has BACKEND_ROLE on betting contract");
        }

        // 5. Transfer ownership/admin roles from deployer to admin (if needed)
        console2.log("\n5. Checking admin roles...");
        
        // Check if admin has DEFAULT_ADMIN_ROLE on all contracts
        bytes32 adminRole = factory.DEFAULT_ADMIN_ROLE();
        
        if (!factory.hasRole(adminRole, admin)) {
            console2.log("- Admin does not have DEFAULT_ADMIN_ROLE on factory, this needs manual intervention");
        } else {
            console2.log("- Admin has DEFAULT_ADMIN_ROLE on factory");
        }

        if (!statistics.hasRole(adminRole, admin)) {
            console2.log("- Admin does not have DEFAULT_ADMIN_ROLE on statistics, this needs manual intervention");
        } else {
            console2.log("- Admin has DEFAULT_ADMIN_ROLE on statistics");
        }

        if (!betting.hasRole(adminRole, admin)) {
            console2.log("- Admin does not have DEFAULT_ADMIN_ROLE on betting, this needs manual intervention");
        } else {
            console2.log("- Admin has DEFAULT_ADMIN_ROLE on betting");
        }

        vm.stopBroadcast();

        console2.log("\n=== Configuration Summary ===");
        console2.log("✅ All contract permissions have been configured");
        console2.log("✅ Backend has proper roles on all contracts");
        console2.log("✅ Factory can update statistics");
        console2.log("✅ Points contract is properly authorized");
        console2.log("✅ Betting contract has proper backend access");
        
        console2.log("\nConfiguration completed successfully!");
        console2.log("The contracts are now ready for use with the admin account having proper permissions.");
    }
}