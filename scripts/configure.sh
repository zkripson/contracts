#!/bin/bash

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print header
echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}       ZK Battleship Admin Configuration      ${NC}"
echo -e "${BLUE}===============================================${NC}"

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Please copy .env.example to .env and fill in the values"
    exit 1
fi

# Load environment variables
echo -e "${YELLOW}Loading environment variables...${NC}"
source .env

# Ensure required variables are set
if [ -z "$BASE_MAINNET_RPC_URL" ]; then
    echo -e "${RED}Error: BASE_MAINNET_RPC_URL not set in .env file${NC}"
    exit 1
fi

# Check if adminKey keystore is available
echo -e "${YELLOW}Checking Cast admin keystore...${NC}"
ADMIN_KEYSTORE="adminKey"
ADMIN_ADDRESS="0x69cec43d4d65a9932f4f0f1b606ff9e40e5eb43b"

# Verify the admin keystore exists
if ! cast wallet list | grep -q "$ADMIN_KEYSTORE"; then
    echo -e "${RED}Error: Cast keystore '$ADMIN_KEYSTORE' not found${NC}"
    echo "Please ensure your admin keystore is properly set up with: cast wallet import $ADMIN_KEYSTORE --interactive"
    exit 1
fi

echo -e "${GREEN}Found Cast keystore: $ADMIN_KEYSTORE${NC}"
echo -e "${GREEN}Admin address: $ADMIN_ADDRESS${NC}"

# Check if deployment-config.json exists
if [ ! -f deployment-config.json ]; then
    echo -e "${RED}Error: deployment-config.json not found${NC}"
    echo "Please ensure contracts are deployed first"
    exit 1
fi

# Extract contract addresses from deployment config
if command -v jq &> /dev/null; then
    GAME_FACTORY=$(jq -r '.environments."base-sepolia".contracts.gameFactory // .environments."base-mainnet".contracts.gameFactory' deployment-config.json)
    GAME_STATS=$(jq -r '.environments."base-sepolia".contracts.gameStatistics // .environments."base-mainnet".contracts.gameStatistics' deployment-config.json)
    BETTING_ADDRESS=$(jq -r '.environments."base-sepolia".contracts.battleshipBetting // .environments."base-mainnet".contracts.battleshipBetting' deployment-config.json)
    BACKEND_ADDRESS=$(jq -r '.environments."base-sepolia".config.backend // .environments."base-mainnet".config.backend' deployment-config.json)
else
    echo -e "${RED}Error: jq is required for parsing deployment config${NC}"
    echo "Please install jq: brew install jq"
    exit 1
fi

echo -e "${GREEN}Found deployed contracts:${NC}"
echo -e "GameFactory: $GAME_FACTORY"
echo -e "GameStatistics: $GAME_STATS"
echo -e "BattleshipBetting: $BETTING_ADDRESS"
echo -e "Backend: $BACKEND_ADDRESS"

# Confirm configuration
echo -e "${YELLOW}Ready to configure contracts with admin account${NC}"
echo -e "RPC URL: ${BASE_MAINNET_RPC_URL}"
echo -e "Admin Address: ${ADMIN_ADDRESS}"

read -p "Press Enter to begin configuration or Ctrl+C to cancel..."

# Configure contracts using admin key
echo -e "${YELLOW}Configuring contracts with admin privileges...${NC}"

# Create configuration script and execute it
CONFIG_COMMAND="forge script scripts/configure/Configure.s.sol:ConfigureContracts --rpc-url $BASE_MAINNET_RPC_URL --broadcast -vvvv --account $ADMIN_KEYSTORE"

# Execute configuration
echo $CONFIG_COMMAND
eval $CONFIG_COMMAND

# Check if configuration was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}Configuration failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Configuration completed successfully!${NC}"
echo -e "${BLUE}===============================================${NC}"
echo -e "${GREEN}All contracts are now properly configured with admin privileges${NC}"
echo -e "${BLUE}===============================================${NC}"