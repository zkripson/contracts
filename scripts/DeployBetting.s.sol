// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import "forge-std/Script.sol";
import "../src/Betting.sol";
import "../deployment/contracts.json";

contract DeployBetting is Script {
    function run() external {
        // Load environment variables
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address backend = vm.envAddress("BACKEND_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address usdcToken = vm.envAddress("USDC_ADDRESS");
        
        // Load deployed contracts from JSON
        string memory json = vm.readFile("deployment/contracts.json");
        address gameFactory = abi.decode(vm.parseJson(json, ".gameFactory"), (address));
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy BattleshipBetting
        BattleshipBetting betting = new BattleshipBetting(
            usdcToken,
            gameFactory,
            treasury,
            backend,
            admin
        );
        
        console.log("BattleshipBetting deployed at:", address(betting));
        
        // Grant betting contract BACKEND_ROLE on GameFactory
        // This allows the betting contract to create games
        GameFactoryWithStats factory = GameFactoryWithStats(gameFactory);
        factory.grantRole(factory.BACKEND_ROLE(), address(betting));
        
        console.log("Granted BACKEND_ROLE to betting contract on GameFactory");
        
        vm.stopBroadcast();
        
        // Save the deployment address
        string memory deploymentOutput = string(abi.encodePacked(
            '{"betting": "',
            vm.toString(address(betting)),
            '"}'
        ));
        vm.writeFile("deployment/betting.json", deploymentOutput);
        
        console.log("Deployment info saved to deployment/betting.json");
    }
}