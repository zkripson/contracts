#!/bin/bash
# pre-deploy.sh
# Script to temporarily move verifier contracts out of the way during compilation

set -e # Exit on any error

echo "===== ZK Battleship Build Script ====="



# Run forge build with the specified parameters
echo "Running forge build..."
forge build "$@"
BUILD_RESULT=$?

# Exit with the build result
exit $BUILD_RESULT