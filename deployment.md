# ZK Battleship Deployment Information

This document contains information about the deployed ZK Battleship contracts on various networks.

## MegaETH Testnet

### Verifier Contracts

| Contract | Address | Description |
|----------|---------|-------------|
| BoardPlacementVerifier | `0x2dd5ee6f05ee772301730aa273b5fab211153a09` | Verifies board placement proofs (1 public input) |
| ShotResultVerifier | `0x8bb12ce8761e5f43f82b06752d957e845580de70` | Verifies shot result proofs (4 public inputs) |
| GameEndVerifier | `0x2690d996eaafdda967a9ffabf52f33eb8faed235` | Verifies game end proofs (2 public inputs) |

### Game Contracts

| Contract | Address | Description |
|----------|---------|-------------|
| ZKVerifier | TBD | Wrapper for all three verifiers |
| GameFactory | TBD | Creates new game instances |
| SHIPToken | TBD | Game reward token |
| GameUpgradeManager | TBD | Manages contract upgrades |

## Deployment Information

### Deployment Date

The verifier contracts were deployed on [date].

### Compiler Settings

The contracts were compiled with the following settings:

```toml
[profile.default]
optimizer = true
optimizer_runs = 10000
via_ir = true
evm_version = "london"
```

### Verification Status

- [ ] BoardPlacementVerifier verified on explorer
- [ ] ShotResultVerifier verified on explorer
- [ ] GameEndVerifier verified on explorer

## Notes

The verifier contracts were manually deployed due to their complexity and size. The deployment of these contracts required special settings to handle stack-too-deep errors during compilation.

When deploying the remaining contracts, we reference these pre-deployed verifier contracts instead of deploying new ones.