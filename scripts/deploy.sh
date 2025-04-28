#!/bin/bash

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print header
echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}       ZK Battleship Deployment Script        ${NC}"
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
if [ -z "$MEGAETH_RPC_URL" ]; then
    echo -e "${RED}Error: MEGAETH_RPC_URL not set in .env file${NC}"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY not set in .env file${NC}"
    exit 1
fi

# Install dependencies
echo -e "${YELLOW}Installing Forge dependencies...${NC}"
forge install

# Clean existing build artifacts
echo -e "${YELLOW}Cleaning build artifacts...${NC}"
forge clean

# Build contracts
echo -e "${YELLOW}Building contracts...${NC}"
forge build --optimize

# Confirm deployment
echo -e "${YELLOW}Ready to deploy ZK Battleship contracts to MegaETH${NC}"
echo -e "RPC URL: ${MEGAETH_RPC_URL}"
echo -e "Verifier Addresses:"
echo -e "  Board Placement: ${BOARD_PLACEMENT_VERIFIER}"
echo -e "  Shot Result: ${SHOT_RESULT_VERIFIER}"
echo -e "  Game End: ${GAME_END_VERIFIER}"

read -p "Press Enter to begin deployment or Ctrl+C to cancel..."

# Deploy contracts
echo -e "${YELLOW}Deploying contracts...${NC}"

DEPLOY_COMMAND="forge script scripts/deploy/Deploy.s.sol:DeployZKBattleship --rpc-url $MEGAETH_RPC_URL --broadcast -vvvv --private-key $PRIVATE_KEY"

# Add verification if MEGAETH_API_KEY is provided
if [ ! -z "$MEGAETH_API_KEY" ]; then
    DEPLOY_COMMAND="$DEPLOY_COMMAND --verify --etherscan-api-key $MEGAETH_API_KEY"
fi

# Execute deployment
echo $DEPLOY_COMMAND
eval $DEPLOY_COMMAND

# Check if deployment was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}Deployment failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Deployment completed successfully!${NC}"

# Extract contract addresses from the logs
echo -e "${YELLOW}Extracting deployed contract addresses...${NC}"
LOGS_FILE="deployment_logs.txt"

# Try to extract contract addresses from the logs
ZK_VERIFIER=$(grep -A 1 "ZKVerifier deployed at:" $LOGS_FILE | tail -n 1 | tr -d ' ')
GAME_IMPLEMENTATION=$(grep -A 1 "BattleShipGameImplementation deployed at:" $LOGS_FILE | tail -n 1 | tr -d ' ')
GAME_FACTORY=$(grep -A 1 "GameFactory deployed at:" $LOGS_FILE | tail -n 1 | tr -d ' ')
SHIP_TOKEN=$(grep -A 1 "SHIPToken deployed at:" $LOGS_FILE | tail -n 1 | tr -d ' ')

# Update .env file with deployed addresses
if [ ! -z "$ZK_VERIFIER" ] && [ ! -z "$GAME_IMPLEMENTATION" ] && [ ! -z "$GAME_FACTORY" ] && [ ! -z "$SHIP_TOKEN" ]; then
    echo -e "${YELLOW}Updating .env file with deployed addresses...${NC}"
    
    # Create a backup of the .env file
    cp .env .env.backup
    
    # Update the .env file
    sed -i "s/ZK_VERIFIER_ADDRESS=.*/ZK_VERIFIER_ADDRESS=$ZK_VERIFIER/" .env
    sed -i "s/GAME_IMPLEMENTATION_ADDRESS=.*/GAME_IMPLEMENTATION_ADDRESS=$GAME_IMPLEMENTATION/" .env
    sed -i "s/GAME_FACTORY_ADDRESS=.*/GAME_FACTORY_ADDRESS=$GAME_FACTORY/" .env
    sed -i "s/SHIP_TOKEN_ADDRESS=.*/SHIP_TOKEN_ADDRESS=$SHIP_TOKEN/" .env
    
    echo -e "${GREEN}Environment variables updated in .env file${NC}"
fi

# Update deployment configuration
echo -e "${YELLOW}Updating deployment configuration...${NC}"
CURRENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create a temporary file with the updated configuration
cat > temp_config.json << EOF
{
  "environments": {
    "megaeth-testnet": {
      "network": "MegaETH Testnet",
      "rpc": "$MEGAETH_RPC_URL",
      "ws": "$MEGAETH_WS_URL",
      "explorer": "https://explorer.megaeth.io",
      "verifiers": {
        "boardPlacementVerifier": "$BOARD_PLACEMENT_VERIFIER",
        "shotResultVerifier": "$SHOT_RESULT_VERIFIER",
        "gameEndVerifier": "$GAME_END_VERIFIER"
      },
      "contracts": {
        "zkVerifier": "$ZK_VERIFIER",
        "gameImplementation": "$GAME_IMPLEMENTATION",
        "gameFactory": "$GAME_FACTORY",
        "shipToken": "$SHIP_TOKEN"
      },
      "deploymentDate": "$CURRENT_DATE",
      "deploymentTx": ""
    }
  }
}
EOF

# Update the deployment configuration file
mv temp_config.json deployment-config.json

echo -e "${GREEN}Deployment configuration updated${NC}"

# Print deployment summary
echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}         Deployment Summary                   ${NC}"
echo -e "${BLUE}===============================================${NC}"
echo -e "${GREEN}ZKVerifier:${NC} $ZK_VERIFIER"
echo -e "${GREEN}GameImplementation:${NC} $GAME_IMPLEMENTATION"
echo -e "${GREEN}GameFactory:${NC} $GAME_FACTORY"
echo -e "${GREEN}SHIPToken:${NC} $SHIP_TOKEN"
echo -e "${BLUE}===============================================${NC}"
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "Next steps:"
echo -e "1. Verify the deployment with: node verify-deployment.js"
echo -e "2. For monitoring game events: node megaeth-realtime-monitor.js <gameAddress>"
echo -e "${BLUE}===============================================${NC}"