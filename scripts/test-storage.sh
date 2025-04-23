#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Running GameStorage library tests...${NC}"

# Check if Forge is installed
if ! command -v forge &> /dev/null
then
    echo -e "${RED}Forge could not be found. Please install Foundry.${NC}"
    echo -e "${YELLOW}Install Foundry with: curl -L https://foundry.paradigm.xyz | bash${NC}"
    exit 1
fi

# Check if the GameStorage library exists
if [ ! -f "src/libraries/GameStorage.sol" ]; then
    echo -e "${RED}GameStorage library not found at src/libraries/GameStorage.sol${NC}"
    echo -e "${YELLOW}Make sure you've implemented the library before running tests.${NC}"
    exit 1
fi

# Define the specific test path for GameStorage
TEST_PATH="test/unit/GameStorage.t.sol"

# Check if the test file exists
if [ ! -f "$TEST_PATH" ]; then
    echo -e "${RED}Test file $TEST_PATH not found!${NC}"
    echo -e "${YELLOW}Make sure you've created the test file at $TEST_PATH${NC}"
    exit 1
fi

# Clean any previous build artifacts
echo -e "${YELLOW}Cleaning previous build artifacts...${NC}"
forge clean

# Compile only what's needed for the test
echo -e "${YELLOW}Compiling GameStorage library and tests...${NC}"
# Skip compiling verification contracts by explicitly building only what we need
forge build --skip test --sizes

# Run the specific test file
echo -e "${YELLOW}Running tests for GameStorage library...${NC}"
forge test --match-path "$TEST_PATH" -vv

# Run gas snapshot for optimization analysis
echo -e "${YELLOW}Generating gas report for GameStorage...${NC}"
forge test --match-path "$TEST_PATH" --gas-report

echo -e "${GREEN}GameStorage tests completed successfully!${NC}"
echo -e "${YELLOW}Don't forget to add the GameStorage library to your git commit:${NC}"
echo -e "git add src/libraries/GameStorage.sol test/unit/GameStorage.t.sol"