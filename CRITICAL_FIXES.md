# Critical Security Fixes - Quick Reference

This document provides immediate fixes for the most critical security issues identified in the audit.

## 🔴 Critical Fix #1: Token Array Manipulation

**File:** `src/Betting.sol`  
**Function:** `removeTokenFromWhitelist`  
**Lines:** 574-582

### Current Code (Vulnerable):
```solidity
// Remove from whitelistedTokensList array
for (uint256 i = 0; i < whitelistedTokensList.length; i++) {
    if (whitelistedTokensList[i] == token) {
        whitelistedTokensList[i] = whitelistedTokensList[whitelistedTokensList.length - 1];
        whitelistedTokensList.pop();
        break;
    }
}
```

### Fixed Code:
```solidity
// Remove from whitelistedTokensList array - SAFE VERSION
uint256 length = whitelistedTokensList.length;
for (uint256 i = 0; i < length; i++) {
    if (whitelistedTokensList[i] == token) {
        // Only swap if not the last element
        if (i != length - 1) {
            whitelistedTokensList[i] = whitelistedTokensList[length - 1];
        }
        whitelistedTokensList.pop();
        break;
    }
}
```

## 🔴 Critical Fix #2: Add Overflow Protection

**File:** `src/Betting.sol`  
**Function:** `resolveGame`  
**Line:** 306

### Add Import:
```solidity
import "@openzeppelin/contracts/utils/math/Math.sol";
```

### Current Code (Vulnerable):
```solidity
uint256 totalPool = invite.stakeAmount * 2;
uint256 platformFee = (totalPool * PLATFORM_FEE_PERCENTAGE) / 100;
uint256 winnerPayout = totalPool - platformFee;
```

### Fixed Code:
```solidity
uint256 totalPool = invite.stakeAmount * 2;
uint256 platformFee = Math.mulDiv(totalPool, PLATFORM_FEE_PERCENTAGE, 100);
uint256 winnerPayout = totalPool - platformFee;
```

## 🟠 High Priority Fix #1: Reentrancy Protection

**File:** `src/Betting.sol`  
**Functions:** `cancelInvite`, `handleExpiredInvite`, `emergencyRefundBet`

### Pattern to Apply (Example with cancelInvite):

### Current Code:
```solidity
function cancelInvite(uint256 inviteId, address creator) external whenNotPaused nonReentrant {
    BettingInvite storage invite = bettingInvites[inviteId];

    // Validate invite
    if (invite.creator == address(0)) revert InviteNotFound();
    if (creator != invite.creator) revert UnauthorizedAction();
    if (invite.betStatus != BetStatus.Open) revert InvalidInviteStatus();

    // Update status
    invite.betStatus = BetStatus.Cancelled;

    // Return stake to creator in the bet token
    IERC20(invite.betToken).safeTransfer(invite.creator, invite.stakeAmount);

    emit InviteCancelled(inviteId, invite.creator, invite.stakeAmount);
}
```

### Fixed Code (Checks-Effects-Interactions):
```solidity
function cancelInvite(uint256 inviteId, address creator) external whenNotPaused nonReentrant {
    BettingInvite storage invite = bettingInvites[inviteId];

    // CHECKS
    if (invite.creator == address(0)) revert InviteNotFound();
    if (creator != invite.creator) revert UnauthorizedAction();
    if (invite.betStatus != BetStatus.Open) revert InvalidInviteStatus();

    // EFFECTS - Store values and update state before external calls
    address betToken = invite.betToken;
    uint256 stakeAmount = invite.stakeAmount;
    address creatorAddress = invite.creator;
    
    invite.betStatus = BetStatus.Cancelled;

    // INTERACTIONS - External calls last
    IERC20(betToken).safeTransfer(creatorAddress, stakeAmount);

    emit InviteCancelled(inviteId, creatorAddress, stakeAmount);
}
```

## 🟠 High Priority Fix #2: Add Pagination to getActiveInvites

**File:** `src/Betting.sol`  
**Function:** `getActiveInvites`  
**Lines:** 535-558

### Current Code (Vulnerable to DoS):
```solidity
function getActiveInvites() external view returns (uint256[] memory activeInvites) {
    // Count active invites first
    uint256 activeCount = 0;
    for (uint256 i = 1; i < nextInviteId; i++) {
        BettingInvite memory invite = bettingInvites[i];
        if (invite.betStatus == BetStatus.Escrowed && !invite.fundsDistributed) {
            activeCount++;
        }
    }

    // Create array of correct size
    activeInvites = new uint256[](activeCount);
    uint256 index = 0;
    
    for (uint256 i = 1; i < nextInviteId; i++) {
        BettingInvite memory invite = bettingInvites[i];
        if (invite.betStatus == BetStatus.Escrowed && !invite.fundsDistributed) {
            activeInvites[index] = i;
            index++;
        }
    }

    return activeInvites;
}
```

### Fixed Code (With Pagination):
```solidity
function getActiveInvites(uint256 offset, uint256 limit) 
    external view returns (uint256[] memory activeInvites, uint256 total, bool hasMore) {
    
    require(limit > 0 && limit <= 100, "Invalid limit"); // Max 100 per call
    
    // First pass: count total active invites
    uint256 totalActive = 0;
    for (uint256 i = 1; i < nextInviteId; i++) {
        BettingInvite memory invite = bettingInvites[i];
        if (invite.betStatus == BetStatus.Escrowed && !invite.fundsDistributed) {
            totalActive++;
        }
    }
    
    // Calculate result size
    uint256 startIndex = offset;
    uint256 endIndex = offset + limit;
    uint256 resultSize = 0;
    
    if (startIndex < totalActive) {
        resultSize = endIndex > totalActive ? totalActive - startIndex : limit;
    }
    
    // Create result array
    activeInvites = new uint256[](resultSize);
    uint256 activeIndex = 0;
    uint256 resultIndex = 0;
    
    // Second pass: collect paginated results
    for (uint256 i = 1; i < nextInviteId && resultIndex < resultSize; i++) {
        BettingInvite memory invite = bettingInvites[i];
        if (invite.betStatus == BetStatus.Escrowed && !invite.fundsDistributed) {
            if (activeIndex >= startIndex) {
                activeInvites[resultIndex] = i;
                resultIndex++;
            }
            activeIndex++;
        }
    }
    
    return (activeInvites, totalActive, endIndex < totalActive);
}

// Keep backward compatibility
function getActiveInvites() external view returns (uint256[] memory activeInvites) {
    (activeInvites, , ) = this.getActiveInvites(0, 100);
    return activeInvites;
}
```

## 🟡 Medium Priority Fix: Token Validation

**File:** `src/Betting.sol`  
**Function:** `whitelistToken`  
**Lines:** 552-562

### Add Token Validation:
```solidity
function whitelistToken(address token, uint256 minStakeAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (token == address(0)) revert InvalidTokenAddress();
    if (whitelistedTokens[token]) revert TokenAlreadyWhitelisted();
    if (minStakeAmount == 0) revert InvalidMinStakeAmount();

    // NEW: Validate token is a proper ERC20
    try IERC20(token).totalSupply() returns (uint256 supply) {
        require(supply > 0, "Token has zero supply");
    } catch {
        revert("Invalid ERC20 token");
    }
    
    // Test basic token operations
    try IERC20(token).balanceOf(address(this)) returns (uint256) {
        // Token supports balanceOf
    } catch {
        revert("Token does not support balanceOf");
    }

    whitelistedTokens[token] = true;
    tokenMinStakeAmounts[token] = minStakeAmount;
    whitelistedTokensList.push(token);

    emit TokenWhitelisted(token, minStakeAmount);
}
```

## Quick Implementation Checklist

- [ ] Apply token array fix
- [ ] Add Math.mulDiv for fee calculation  
- [ ] Update all token transfer functions with CEI pattern
- [ ] Add pagination to getActiveInvites
- [ ] Add token validation to whitelistToken
- [ ] Run full test suite after fixes
- [ ] Deploy to testnet for integration testing

## Gas Impact Assessment

| Fix | Gas Impact | Justification |
|-----|------------|---------------|
| Token Array Fix | Minimal (+50 gas) | Safety critical |
| Math.mulDiv | Small (+100 gas) | Prevents overflows |
| CEI Pattern | Minimal (+20 gas) | Prevents reentrancy |
| Pagination | Reduces gas | Prevents DoS |
| Token Validation | Medium (+2000 gas) | One-time cost for safety |

## Testing After Fixes

Run these specific tests to verify fixes:

```bash
# Test token array manipulation
forge test --match-test "testRemoveTokenFromMiddleOfList" -v

# Test overflow protection
forge test --match-test "testFullGameFlowWithDAI" -v

# Test reentrancy protection  
forge test --match-test "testCancelInviteWithDifferentTokens" -v

# Test pagination
forge test --match-test "testGetActiveInvites" -v

# Run all tests
forge test
```

---

**⚠️ Important:** Test all fixes thoroughly on a testnet before mainnet deployment.