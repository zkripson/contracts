#!/bin/bash
# pre-deploy.sh
# Script to temporarily move verifier contracts out of the way during compilation

set -e # Exit on any error

echo "===== ZK Battleship Build Script ====="
echo "Temporarily moving verifier contracts..."

# Create backup directory if it doesn't exist
mkdir -p .verifier_backup

# Check if there are verifier contracts to move
if [ -d "src/verifiers" ] && [ "$(ls -A src/verifiers/*.sol 2>/dev/null)" ]; then
    # Move verifier contracts to backup location
    mv src/verifiers/*.sol .verifier_backup/
    echo "Verifiers moved to backup location"
else
    echo "No verifier contracts found in src/verifiers"
fi

# Run forge build with the specified parameters
echo "Running forge build..."
forge build "$@"
BUILD_RESULT=$?

# Move verifier contracts back
if [ -d ".verifier_backup" ] && [ "$(ls -A .verifier_backup/*.sol 2>/dev/null)" ]; then
    echo "Restoring verifier contracts..."
    # Make sure the verifiers directory exists
    mkdir -p src/verifiers
    # Move verifier contracts back
    mv .verifier_backup/*.sol src/verifiers/
    echo "Verifiers restored"
fi

# Exit with the build result
exit $BUILD_RESULT