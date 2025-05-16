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
if [ -z "$BASE_SEPOLIA_RPC_URL" ]; then
    echo -e "${RED}Error: BASE_SEPOLIA_RPC_URL not set in .env file${NC}"
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
echo -e "${YELLOW}Ready to deploy ZK Battleship contracts to Base Sepolia${NC}"
echo -e "RPC URL: ${BASE_SEPOLIA_RPC_URL}"

read -p "Press Enter to begin deployment or Ctrl+C to cancel..."

# Deploy contracts
echo -e "${YELLOW}Deploying contracts...${NC}"

DEPLOY_COMMAND="forge script scripts/deploy/Deploy.s.sol:DeployZKBattleship --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast -vvvv --private-key $PRIVATE_KEY"

# Add verification if BASE_API_KEY is provided
if [ ! -z "$BASE_SEPOLIA_API_KEY" ]; then
    DEPLOY_COMMAND="$DEPLOY_COMMAND --verify --etherscan-api-key $BASE_SEPOLIA_API_KEY"
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

# Extract contract addresses from the deployment output file
echo -e "${YELLOW}Extracting deployed contract addresses...${NC}"

# Set the deployment output file path
DEPLOYMENT_OUTPUT="./broadcast/Deploy.s.sol/deployment-output.json"

if [ -f "$DEPLOYMENT_OUTPUT" ]; then
    echo -e "${GREEN}Found $DEPLOYMENT_OUTPUT${NC}"
    
    # Extract addresses using jq if available
    if command -v jq &> /dev/null; then
        SHIP_TOKEN=$(jq -r '.contracts.SHIPToken' "$DEPLOYMENT_OUTPUT")
        GAME_IMPLEMENTATION=$(jq -r '.contracts.BattleshipGameImplementation' "$DEPLOYMENT_OUTPUT")
        GAME_STATS=$(jq -r '.contracts.BattleshipStatistics' "$DEPLOYMENT_OUTPUT")
        GAME_FACTORY=$(jq -r '.contracts.GameFactoryWithStats' "$DEPLOYMENT_OUTPUT")
        BETTING_ADDRESS=$(jq -r '.contracts.BattleshipBetting' "$DEPLOYMENT_OUTPUT")
        BACKEND_ADDRESS=$(jq -r '.config.backend' "$DEPLOYMENT_OUTPUT")
    else
        # Fallback to grep if jq is not available
        echo -e "${YELLOW}jq not found, using grep instead${NC}"
        SHIP_TOKEN=$(grep -o '"SHIPToken": "[^"]*' "$DEPLOYMENT_OUTPUT" | cut -d'"' -f4)
        GAME_IMPLEMENTATION=$(grep -o '"BattleshipGameImplementation": "[^"]*' "$DEPLOYMENT_OUTPUT" | cut -d'"' -f4)
        GAME_STATS=$(grep -o '"BattleshipStatistics": "[^"]*' "$DEPLOYMENT_OUTPUT" | cut -d'"' -f4)
        GAME_FACTORY=$(grep -o '"GameFactoryWithStats": "[^"]*' "$DEPLOYMENT_OUTPUT" | cut -d'"' -f4)
        BETTING_ADDRESS=$(grep -o '"BattleshipBetting": "[^"]*' "$DEPLOYMENT_OUTPUT" | cut -d'"' -f4)
        BACKEND_ADDRESS=$(grep -o '"backend": "[^"]*' "$DEPLOYMENT_OUTPUT" | cut -d'"' -f4)
    fi
else
    echo -e "${RED}${DEPLOYMENT_OUTPUT} not found!${NC}"
    echo -e "${YELLOW}Attempting to extract from Forge deployment logs...${NC}"
    
    # Look for broadcasts directory
    LATEST_BROADCAST=$(find broadcast -name "run-latest.json" | sort | tail -n 1)
    
    if [ ! -z "$LATEST_BROADCAST" ]; then
        echo -e "${GREEN}Found deployment log: $LATEST_BROADCAST${NC}"
        
        # Extract addresses from the broadcast logs using grep
        SHIP_TOKEN=$(grep -o '"contractAddress": "[^"]*"' "$LATEST_BROADCAST" | grep -A 3 "SHIPToken" | head -n 1 | cut -d'"' -f4)
        GAME_IMPLEMENTATION=$(grep -o '"contractAddress": "[^"]*"' "$LATEST_BROADCAST" | grep -A 3 "BattleshipGameImplementation" | head -n 1 | cut -d'"' -f4)
        GAME_STATS=$(grep -o '"contractAddress": "[^"]*"' "$LATEST_BROADCAST" | grep -A 3 "BattleshipStatistics" | head -n 1 | cut -d'"' -f4)
        GAME_FACTORY=$(grep -o '"contractAddress": "[^"]*"' "$LATEST_BROADCAST" | grep -A 3 "GameFactoryWithStats" | head -n 1 | cut -d'"' -f4)
        BETTING_ADDRESS=$(grep -o '"contractAddress": "[^"]*"' "$LATEST_BROADCAST" | grep -A 3 "BattleshipBetting" | head -n 1 | cut -d'"' -f4)
        
        # Try to extract backend address from environment
        BACKEND_ADDRESS=${BACKEND_ADDRESS:-$DEPLOYER}
        
        echo -e "${GREEN}Extracted addresses from broadcast logs${NC}"
    else
        echo -e "${RED}No broadcast logs found!${NC}"
        exit 1
    fi
fi

# BattleshipBetting address is now extracted from the main deployment output

# Update .env file with deployed addresses
if [ ! -z "$SHIP_TOKEN" ] && [ ! -z "$GAME_IMPLEMENTATION" ] && [ ! -z "$GAME_FACTORY" ]; then
    echo -e "${YELLOW}Updating .env file with deployed addresses...${NC}"
    
    # Create a backup of the .env file
    cp .env .env.backup
    
    # Update the .env file
    sed -i "s/SHIP_TOKEN_ADDRESS=.*/SHIP_TOKEN_ADDRESS=$SHIP_TOKEN/" .env
    sed -i "s/GAME_IMPLEMENTATION_ADDRESS=.*/GAME_IMPLEMENTATION_ADDRESS=$GAME_IMPLEMENTATION/" .env
    sed -i "s/STATS_ADDRESS=.*/STATS_ADDRESS=$GAME_STATS/" .env
    sed -i "s/GAME_FACTORY_ADDRESS=.*/GAME_FACTORY_ADDRESS=$GAME_FACTORY/" .env
    
    # Update betting address if it exists
    if [ ! -z "$BETTING_ADDRESS" ]; then
        sed -i "s/BETTING_ADDRESS=.*/BETTING_ADDRESS=$BETTING_ADDRESS/" .env
    fi
    
    echo -e "${GREEN}Environment variables updated in .env file${NC}"
fi

# Update deployment configuration
echo -e "${YELLOW}Updating deployment configuration...${NC}"
CURRENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create a temporary file with the updated configuration
cat > temp_config.json << EOF
{
  "environments": {
    "base-sepolia": {
      "network": "Base Sepolia Testnet",
      "rpc": "$BASE_SEPOLIA_RPC_URL",
      "ws": "$BASE_SEPOLIA_WS_URL",
      "explorer": "https://sepolia.basescan.org",
      "contracts": {
        "shipToken": "$SHIP_TOKEN",
        "gameImplementation": "$GAME_IMPLEMENTATION",
        "gameStatistics": "$GAME_STATS",
        "gameFactory": "$GAME_FACTORY"${BETTING_ADDRESS:+,
        "battleshipBetting": "$BETTING_ADDRESS"}
      },
      "config": {
        "backend": "$BACKEND_ADDRESS"${USDC_ADDRESS:+,
        "usdcToken": "$USDC_ADDRESS"}${TREASURY_ADDRESS:+,
        "treasury": "$TREASURY_ADDRESS"}${ADMIN_ADDRESS:+,
        "admin": "$ADMIN_ADDRESS"}
      },
      "deploymentDate": "$CURRENT_DATE"
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
echo -e "${GREEN}SHIPToken:${NC} $SHIP_TOKEN"
echo -e "${GREEN}GameImplementation:${NC} $GAME_IMPLEMENTATION"
echo -e "${GREEN}BattleshipStatistics:${NC} $GAME_STATS"
echo -e "${GREEN}GameFactory:${NC} $GAME_FACTORY"
if [ ! -z "$BETTING_ADDRESS" ] && [ "$BETTING_ADDRESS" != "null" ]; then
    echo -e "${GREEN}BattleshipBetting:${NC} $BETTING_ADDRESS"
fi
echo -e "${GREEN}Backend Address:${NC} $BACKEND_ADDRESS"
if [ ! -z "$TREASURY_ADDRESS" ]; then
    echo -e "${GREEN}Treasury Address:${NC} $TREASURY_ADDRESS"
fi
if [ ! -z "$USDC_ADDRESS" ]; then
    echo -e "${GREEN}USDC Token:${NC} $USDC_ADDRESS"
fi
echo -e "${BLUE}===============================================${NC}"
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "Next steps:"
echo -e "1. Configure your backend to use these contract addresses"
echo -e "2. Run tests against Base Sepolia testnet"
echo -e "3. Monitor transactions on Base Sepolia explorer: https://sepolia.basescan.org"
if [ ! -z "$BETTING_ADDRESS" ] && [ "$BETTING_ADDRESS" != "null" ]; then
    echo -e "4. Ensure backend has proper roles for betting operations"
    echo -e "5. Verify USDC token address and treasury are configured correctly"
fi
echo -e "${BLUE}===============================================${NC}"