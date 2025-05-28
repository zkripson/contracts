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

        address admin = vm.envAddress("ADMIN_ADDRESS");
        address backend = vm.envAddress("BACKEND_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address usdcToken = vm.envAddress("USDC_ADDRESS");

        // Load contract addresses from deployment config
        address gameFactory = 0xD1a2812933b9cBCEcd024c0F5F3b1B0D03817f45;
        address gameStats = 0xc675457aF4387739672E8C087191191961Ae4A4B;
        address bettingAddress = 0x68e19F765E20bAEDfc06e431ADdD7f7d92945324;
        address gameImplementation = 0x6291BA16b085768a332C330b5fBA044f5dA86012;
        address pointsAddress = 0x502714828F254Fd890Ec78424A50cF257Ee5EA84;

        console2.log("Contract addresses:");
        console2.log("GameFactory:", gameFactory);
        console2.log("GameStatistics:", gameStats);
        console2.log("BattleshipBetting:", bettingAddress);
        console2.log("GameImplementation:", gameImplementation);
        console2.log("Points:", pointsAddress);
        console2.log("Admin:", admin);
        console2.log("Backend:", backend);
        console2.log("Treasury:", treasury);

        // When using Cast keystore, start broadcast without parameter
        vm.startBroadcast();

        // Get current sender address
        address currentSender = msg.sender;
        console2.log("Current sender (should be admin):", currentSender);

        // Initialize contract instances
        GameFactoryWithStats factory = GameFactoryWithStats(gameFactory);
        BattleshipStatistics statistics = BattleshipStatistics(gameStats);
        BattleshipBetting betting = BattleshipBetting(bettingAddress);

        console2.log("\n=== Configuring Contract Permissions ===");

        // 1. Grant statistics updater role to factory
        statistics.grantRole(statistics.STATS_UPDATER_ROLE(), gameFactory);
        console2.log("- Granted STATS_UPDATER_ROLE to factory");

        // 2. Grant factory the backend role for betting contract
        factory.grantRole(factory.BACKEND_ROLE(), bettingAddress);
        console2.log("- Granted BACKEND_ROLE to betting contract on GameFactory");

        // 3. Configure BattleshipPoints if deployed
        if (pointsAddress != address(0)) {
            BattleshipPoints points = BattleshipPoints(pointsAddress);

            points.addAuthorizedSource(gameImplementation);
            console2.log("- Authorized BattleshipGameImplementation to award points");

            points.addAuthorizedSource(gameFactory);
            console2.log("- Authorized GameFactory to award points");

            points.addAuthorizedSource(backend);
            console2.log("- Authorized Backend to award points");
        } else {
            console2.log("- Points contract address not provided, skipping points configuration");
        }

        vm.stopBroadcast();

        console2.log("\n=== Configuration Summary ===");
        console2.log("Statistics updater role granted to factory");
        console2.log("Backend role granted to betting contract on factory");
        if (pointsAddress != address(0)) {
            console2.log("Points contract properly authorized");
        }

        console2.log("\nConfiguration completed successfully!");
        console2.log("The contracts are now ready for use with proper admin permissions.");
    }
}
