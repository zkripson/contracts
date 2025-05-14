#!/bin/bash

# Load environment variables
source .env

# Check if required environment variables are set
if [ -z "$GAME_FACTORY_ADDRESS" ] || [ -z "$STATISTICS_ADDRESS" ]; then
  echo "Error: Please set GAME_FACTORY_ADDRESS and STATISTICS_ADDRESS in .env file"
  exit 1
fi

# Run the script
npx hardhat run scripts/grant-stats-role.js --network base-sepolia