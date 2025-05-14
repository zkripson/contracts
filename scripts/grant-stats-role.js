// Script to grant STATS_UPDATER_ROLE from BattleshipStatistics to GameFactoryWithStats

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Granting statistics role with account:", deployer.address);

  // Get contract instances
  const GameFactoryWithStats = await ethers.getContractFactory("GameFactoryWithStats");
  const BattleshipStatistics = await ethers.getContractFactory("BattleshipStatistics");

  // Use your deployed contract addresses
  const gameFactoryAddress = process.env.GAME_FACTORY_ADDRESS;
  const statisticsAddress = process.env.STATISTICS_ADDRESS;

  if (!gameFactoryAddress || !statisticsAddress) {
    console.error("Please set GAME_FACTORY_ADDRESS and STATISTICS_ADDRESS environment variables");
    process.exit(1);
  }

  const gameFactory = await GameFactoryWithStats.attach(gameFactoryAddress);
  const statistics = await BattleshipStatistics.attach(statisticsAddress);

  // Check if role is already granted
  const STATS_UPDATER_ROLE = await statistics.STATS_UPDATER_ROLE();
  const hasRole = await statistics.hasRole(STATS_UPDATER_ROLE, gameFactoryAddress);

  if (hasRole) {
    console.log("GameFactoryWithStats already has STATS_UPDATER_ROLE");
    return;
  }

  // Grant role from BattleshipStatistics to GameFactoryWithStats
  console.log("Granting STATS_UPDATER_ROLE to GameFactoryWithStats...");
  const tx = await statistics.grantRole(STATS_UPDATER_ROLE, gameFactoryAddress);
  await tx.wait();

  console.log(`Successfully granted STATS_UPDATER_ROLE to GameFactoryWithStats at ${gameFactoryAddress}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });