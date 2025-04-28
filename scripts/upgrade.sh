#!/bin/bash

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print header
echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}       ZK Battleship Upgrade Script           ${NC}"
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

# Confirm upgrade
echo -e "${YELLOW}Ready to upgrade ZK Battleship implementation on MegaETH${NC}"
echo -e "RPC URL: ${MEGAETH_RPC_URL}"

read -p "Press Enter to begin upgrade or Ctrl+C to cancel..."

# Deploy new implementation and upgrade
echo -e "${YELLOW}Deploying new implementation and upgrading...${NC}"

# Use --fork-url instead of --rpc-url based on error message
UPGRADE_COMMAND="forge script scripts/upgrade/Upgrade.s.sol:UpgradeZKBattleship --fork-url $MEGAETH_RPC_URL --broadcast -vvvv --private-key $PRIVATE_KEY"

# Add verification if MEGAETH_API_KEY is provided
if [ ! -z "$MEGAETH_API_KEY" ]; then
    UPGRADE_COMMAND="$UPGRADE_COMMAND --verify --etherscan-api-key $MEGAETH_API_KEY"
fi

# Execute upgrade
echo $UPGRADE_COMMAND
eval $UPGRADE_COMMAND

# Check if upgrade was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}Upgrade failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Upgrade completed successfully!${NC}"

# Extract new implementation address from the logs
echo -e "${YELLOW}Extracting new implementation address...${NC}"
LOGS_FILE="upgrade_logs.txt"

# Try to extract new implementation address from the logs
NEW_IMPLEMENTATION=$(grep -A 1 "New implementation deployed at:" $LOGS_FILE | tail -n 1 | tr -d ' ')

# Update .env file with new implementation address
if [ ! -z "$NEW_IMPLEMENTATION" ]; then
    echo -e "${YELLOW}Updating .env file with new implementation address...${NC}"
    
    # Create a backup of the .env file
    cp .env .env.upgrade.backup
    
    # Update the .env file
    sed -i "s/GAME_IMPLEMENTATION_ADDRESS=.*/GAME_IMPLEMENTATION_ADDRESS=$NEW_IMPLEMENTATION/" .env
    
    echo -e "${GREEN}Environment variables updated in .env file${NC}"
fi

# Update deployment configuration
echo -e "${YELLOW}Updating deployment configuration...${NC}"
CURRENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Update the game implementation in the deployment configuration
if [ -f "deployment-config.json" ]; then
    # Make a backup of the current deployment configuration
    cp deployment-config.json deployment-config.json.backup
    
    # Use jq to update the JSON if available
    if command -v jq >/dev/null 2>&1; then
        jq --arg impl "$NEW_IMPLEMENTATION" --arg date "$CURRENT_DATE" '.environments."megaeth-testnet".contracts.gameImplementation = $impl | .deployment-history += [{"date": $date, "environment": "megaeth-testnet", "commit": "", "note": "Implementation upgrade"}]' deployment-config.json > temp-config.json
        mv temp-config.json deployment-config.json
    else
        echo -e "${YELLOW}jq not found. Skipping deployment configuration update.${NC}"
        echo -e "${YELLOW}Please manually update deployment-config.json with the new implementation address: $NEW_IMPLEMENTATION${NC}"
    fi
else
    echo -e "${YELLOW}deployment-config.json not found. Skipping update.${NC}"
fi

# Print upgrade summary
echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}         Upgrade Summary                      ${NC}"
echo -e "${BLUE}===============================================${NC}"
echo -e "${GREEN}New Implementation:${NC} $NEW_IMPLEMENTATION"
echo -e "${GREEN}GameFactory:${NC} $GAME_FACTORY_ADDRESS"
echo -e "${BLUE}===============================================${NC}"
echo -e "${GREEN}Upgrade completed successfully!${NC}"
echo -e "Next steps:"
echo -e "1. Verify the upgrade with: node verify-deployment.js"
echo -e "2. For monitoring game events: node megaeth-realtime-monitor.js <gameAddress>"
echo -e "${BLUE}===============================================${NC}"