# Verifier Integration Steps

This document outlines the steps to properly integrate the three Honk verifier contracts (BoardPlacement, ShotResult, and GameEnd) into the project.

## 1. Prepare the Verifier Contracts

For each of the three verification requirements (board placement, shot result, and game end), you need to create a separate Solidity file:

### File Structure

```
src/
├── verifiers/
│   ├── BoardPlacementVerifier.sol
│   ├── ShotResultVerifier.sol
│   └── GameEndVerifier.sol
```

### For Each Verifier

1. Create the appropriate file
2. Paste the Honk Verifier contract code into it
3. Rename each contract to be unique (e.g., `HonkVerifier` -> `BoardPlacementVerifier`)

## 2. Adjust Import Paths

In the deployment script (`DeployZKBattleship.s.sol`), make sure the import paths match your project structure:

```solidity
import {HonkVerifier as BoardPlacementVerifier} from "../src/verifiers/BoardPlacementVerifier.sol";
import {HonkVerifier as ShotResultVerifier} from "../src/verifiers/ShotResultVerifier.sol";
import {HonkVerifier as GameEndVerifier} from "../src/verifiers/GameEndVerifier.sol";
```

## 3. Update Integration With Game Logic

Make sure your `BattleshipGameImplementation` contract imports and uses the `ZKVerifier` contract correctly:

```solidity
// In your BattleshipGameImplementation.sol
import {ZKVerifier} from "./ZKVerifier.sol";

contract BattleshipGameImplementation is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    ZKVerifier public zkVerifier;
    
    // Make sure zkVerifier is set in the initialize function
    function initialize(
        uint256 _gameId,
        address _player1,
        address _player2,
        address _factory,
        address _zkVerifier
    ) public initializer {
        zkVerifier = ZKVerifier(_zkVerifier);
        // ... other initialization code
    }
    
    // Example of a function that uses the verifier
    function submitBoard(bytes32 boardCommitment, bytes calldata zkProof) external {
        require(
            zkVerifier.verifyBoardPlacement(boardCommitment, zkProof),
            "Invalid board placement proof"
        );
        
        // ... rest of function
    }
}
```

## 4. Verifier Contract Formats

### Expected Public Inputs

- **Board Placement Verifier**: 1 public input (board commitment)
- **Shot Result Verifier**: 4 public inputs (board commitment, x, y, isHit)
- **Game End Verifier**: 2 public inputs (board commitment, shot history hash)

## 5. Testing

Create specific tests for each verifier to ensure they work correctly:

```solidity
// In your test file
function testBoardPlacementVerifier() public {
    // Set up test data and generate a valid proof
    bytes32 boardCommitment = /* board commitment */;
    bytes memory proof = /* valid proof */;
    
    // Test verification
    bool result = zkVerifier.verifyBoardPlacement(boardCommitment, proof);
    assertTrue(result, "Board placement verification failed");
}
```

## 6. Deployment Consideration

When deploying to MegaETH, ensure the gas limits are sufficient for the verifier contracts, which can be gas-intensive during deployment.

---

By following these steps, you'll successfully integrate all three verifier contracts into your ZK Battleship game.