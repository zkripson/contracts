#!/bin/bash

# Load environment variables
source .env

# Set required environment variables for deployment
export ADMIN_ADDRESS=${ADMIN_ADDRESS}
export BACKEND_ADDRESS=${BACKEND_ADDRESS}
export TREASURY_ADDRESS=${TREASURY_ADDRESS}
export USDC_ADDRESS=${USDC_ADDRESS}
export PRIVATE_KEY=${PRIVATE_KEY}

# Network configuration
NETWORK=${NETWORK:-base-sepolia}
RPC_URL=${BASE_SEPOLIA_RPC_URL}

echo "Deploying BattleshipBetting to $NETWORK..."
echo "Admin: $ADMIN_ADDRESS"
echo "Backend: $BACKEND_ADDRESS"
echo "Treasury: $TREASURY_ADDRESS"
echo "USDC: $USDC_ADDRESS"

# Run deployment
forge script scripts/DeployBetting.s.sol:DeployBetting \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY \
    -vvvv

# Check if deployment was successful
if [ $? -eq 0 ]; then
    echo "✅ BattleshipBetting deployment successful!"
    echo "Check deployment/betting.json for the contract address"
else
    echo "❌ Deployment failed"
    exit 1
fi