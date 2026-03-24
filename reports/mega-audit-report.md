# CAPAutoPounder Mega-Audit Report

**Target:** `src/CAPAutoPounder.sol` + `src/interfaces/`
**Solidity Version:** ^0.8.24
**Date:** 2026-03-09
**Audit Pipelines Applied:** scv-scan (36 vuln types), forefy (yield + staking protocols), Quill (reentrancy, external-call-safety, input-arithmetic-safety, state-invariant-detection), Trail of Bits (building-secure-contracts, static-analysis, sharp-edges, second-opinion), Cyfrin (solskill), Archethect (Map-Hunt-Attack)

---

## Executive Summary

CAPAutoPounder is a well-structured auto-compounding contract that claims EigenLayer rewards, swaps them to WETH via Uniswap V3, mints oETH, wraps to wOETH, and donates to ynLSDe's RedemptionAssetsVault. The contract demonstrates strong security practices including ReentrancyGuard, AccessControlEnumerable, SafeERC20, keeper-supplied slippage bounds (both per-swap and aggregate), and a 0.1% oETH mint tolerance. Two previously-identified HIGH findings (per-swap zero slippage and oETH mint zero minimum) have already been fixed.

After running all audit pipelines, **no Critical or High severity findings were identified**. The contract has a clean security posture for its intended use case. Several Medium and Low/Informational findings are documented below.

---

## Findings

### Finding 1: `deadline: block.timestamp` Provides No Deadline Protection

**Severity:** MEDIUM
**Pipeline:** scv-scan (transaction-ordering-dependence), forefy (fv-sol-8 slippage)
**File:** `src/CAPAutoPounder.sol` L260
**Confidence:** 70

**Description:**
The Uniswap V3 swap sets `deadline: block.timestamp` (line 260). This is equivalent to having no deadline at all -- a validator or MEV searcher can hold the transaction in the mempool indefinitely and execute it in any future block, because `block.timestamp` always equals the current block's timestamp at execution time. If the transaction is delayed (e.g., due to gas price fluctuations), the swap will execute at a potentially stale price.

**Code:**
```solidity
ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
    tokenIn: token,
    tokenOut: weth,
    fee: fee,
    recipient: address(this),
    deadline: block.timestamp, // Always passes -- no real protection
    amountIn: balance,
    amountOutMinimum: minPerSwapOutputs[i],
    sqrtPriceLimitX96: 0
});
```

**Impact Analysis:**
The practical impact is mitigated by three factors: (1) `minPerSwapOutputs[i]` provides per-swap slippage protection, (2) `minWethOutput` provides aggregate slippage protection, and (3) only COMPOUNDER_ROLE can call the function. However, if the keeper's transaction sits in the mempool for hours or days, the off-chain-computed slippage bounds become stale and may allow execution at a worse-than-intended price (though still above the minimum). A validator who delays inclusion can sandwich the transaction when the min output becomes favorable to sandwich.

**Recommendation:**
Accept a `deadline` parameter in `compound()` and pass it through to the swap router, or compute `block.timestamp + DEADLINE_BUFFER` where `DEADLINE_BUFFER` is a configurable constant (e.g., 300 seconds). This ensures delayed transactions revert rather than executing at stale prices.

---

### Finding 2: No Validation on Reward Token Addresses in `_applyConfig`

**Severity:** LOW
**Pipeline:** scv-scan (insufficient-access-control, inadherence-to-standards), forefy (missing input validation fv-sol-5)
**File:** `src/CAPAutoPounder.sol` L344-347
**Confidence:** 60

**Description:**
The `_applyConfig` function validates core protocol addresses against `address(0)` (lines 317-323) but does not validate individual reward token addresses in the `config.rewardTokens` array. An admin misconfiguration could set a reward token to `address(0)`, which would cause `balanceOf(address(this))` to call the zero address (reverting or returning unexpected data depending on the EVM implementation). Similarly, duplicate reward tokens in the array could cause the second entry's `swapPoolFees` to overwrite the first.

**Code:**
```solidity
for (uint256 i = 0; i < config.rewardTokens.length; i++) {
    rewardTokens.push(config.rewardTokens[i]);
    swapPoolFees[config.rewardTokens[i]] = config.swapPoolFees[i];
}
```

**Impact Analysis:**
Low impact because `updateConfig` is restricted to `DEFAULT_ADMIN_ROLE` (a multisig). Duplicate tokens would simply overwrite the fee mapping and one of them would execute a swap with zero balance (skipped). The `address(0)` case would cause a revert on the next `compound()` call but not a loss of funds.

**Recommendation:**
Add `if (config.rewardTokens[i] == address(0)) revert InvalidAddress();` inside the loop. Optionally check for duplicates, though this adds gas cost and the admin is trusted.

---

### Finding 3: `_applyConfig` Does Not Validate `capRestaker` and `capInterestToken`

**Severity:** LOW
**Pipeline:** forefy (missing input validation fv-sol-5), Quill (state-invariant-detection)
**File:** `src/CAPAutoPounder.sol` L316-335
**Confidence:** 55

**Description:**
The `_applyConfig` function validates most protocol addresses but does not validate `capRestaker` or `capInterestToken`. These can be set to `address(0)` without reverting. When `shouldRealizeInterest` is true and `capInterestContract` is set, `_realizeInterest()` will call `realizeRestakerInterest(address(0), address(0))` which may silently succeed or fail depending on the CAP protocol's implementation.

**Impact Analysis:**
Low impact because: (1) `_realizeInterest` uses try/catch, so failure does not revert the compound operation, (2) the CAP interest realization is optional, (3) only the admin can set the config. The worst case is that interest realization silently fails, which is the same behavior as the catch path.

**Recommendation:**
If `capInterestContract` is non-zero, require that `capRestaker` and `capInterestToken` are also non-zero. This enforces that the interest realization feature is either fully configured or disabled.

---

### Finding 4: `recoverToken` Can Sweep Operational Tokens Mid-Compound

**Severity:** LOW
**Pipeline:** Archethect (Map-Hunt-Attack), forefy (access control bypass fv-sol-4)
**File:** `src/CAPAutoPounder.sol` L187-191
**Confidence:** 40

**Description:**
The `recoverToken` function allows the admin to sweep any token at any time, including WETH, oETH, or wOETH that might be mid-flow during a compound operation. Since `compound` is protected by `nonReentrant`, this is not exploitable via reentrancy. However, if the admin and compounder submit transactions in the same block, a race condition could occur where `recoverToken` sweeps WETH after claims but before swaps complete.

**Impact Analysis:**
Very low. The admin is a multisig (YnSecurityCouncil), and `recoverToken` is designed as an emergency function for stuck tokens. The `nonReentrant` guard on `compound` prevents same-transaction exploitation. Cross-transaction race conditions require the admin to deliberately interfere.

**Recommendation:**
No change needed. This is the standard pattern for emergency token recovery. Document that `recoverToken` should not be called while a compound transaction is pending.

---

### Finding 5: Unbounded Claims Array Could Exceed Block Gas Limit

**Severity:** LOW
**Pipeline:** scv-scan (dos-gas-limit), forefy (denial-of-service fv-sol-9)
**File:** `src/CAPAutoPounder.sol` L226-229
**Confidence:** 35

**Description:**
The `_claimRewards` function iterates over the `claims` array without a bound. Each `processClaim` call to the EigenLayer RewardsCoordinator involves merkle proof verification, which is gas-intensive. With a large number of staking nodes and token types, the claims array could theoretically grow large enough to exceed the block gas limit.

**Code:**
```solidity
for (uint256 i = 0; i < claims.length; i++) {
    rewardsCoordinator.processClaim(claims[i], address(this));
}
```

**Impact Analysis:**
Low impact because: (1) the claims array is constructed off-chain by the keeper, who naturally limits it, (2) there are currently only 5 staking nodes with 5 reward tokens, making the maximum claims array ~25 entries, (3) the keeper can batch across multiple transactions if needed.

**Recommendation:**
No change needed for current scale. If the number of staking nodes grows significantly, consider adding a `maxClaims` constant or supporting batched compound operations.

---

### Finding 6: WETH Entry in `minPerSwapOutputs` Array Is Ignored But Required

**Severity:** INFORMATIONAL
**Pipeline:** Trail of Bits (sharp-edges), Quill (input-arithmetic-safety)
**File:** `src/CAPAutoPounder.sol` L239, L245-246
**Confidence:** 80

**Description:**
The `minPerSwapOutputs` array must match `rewardTokens.length` exactly (line 239). However, the WETH entry is always skipped (line 245: `if (token == weth) continue;`), meaning the keeper must always include a placeholder value for WETH's position in the array. This is a minor footgun -- the keeper must pass a dummy value (typically 0) at the WETH index.

**Code:**
```solidity
if (minPerSwapOutputs.length != rewardTokens.length) revert MinPerSwapOutputsLengthMismatch();

for (uint256 i = 0; i < rewardTokens.length; i++) {
    address token = rewardTokens[i];
    if (token == weth) continue; // Skipped, but minPerSwapOutputs[i] still required
```

**Impact Analysis:**
No security impact. The keeper already handles this correctly. It is a documentation/usability concern.

**Recommendation:**
Document in the NatDoc that `minPerSwapOutputs[wethIndex]` is ignored but must be present. Alternatively, restructure to exclude WETH from the array entirely.

---

### Finding 7: `forceApprove` Used Correctly But Multiple Approvals Per Compound

**Severity:** INFORMATIONAL
**Pipeline:** scv-scan (inadherence-to-standards), Quill (external-call-safety)
**File:** `src/CAPAutoPounder.sol` L253, L282, L296, L308
**Confidence:** 90

**Description:**
The contract correctly uses `forceApprove` from SafeERC20 (which handles USDT-style tokens by resetting to 0 first). Each `compound` call issues multiple approve calls -- one per reward token swap, one for oETH vault, one for wOETH wrapping, and one for RedemptionAssetsVault deposit. These are all correct and necessary.

**Impact Analysis:**
No security impact. This is a confirmation that the token approval pattern is correctly implemented. The use of `forceApprove` over `safeApprove` is the correct choice for supporting non-standard tokens like USDT.

**Recommendation:**
No change needed. The implementation is correct.

---

## Pipeline-Specific Assessments

### scv-scan (36 Vulnerability Types)

| Vulnerability Type | Result |
|---|---|
| Reentrancy | PASS - `nonReentrant` on `compound`, `claimOnly`; `realizeInterest` has no exploitable state |
| Overflow/Underflow | PASS - Solidity ^0.8.24, no `unchecked` blocks |
| Access Control | PASS - All state-changing functions protected by roles |
| Frontrunning/MEV | FINDING 1 - `deadline: block.timestamp` (mitigated by minOutput) |
| Delegatecall | PASS - No delegatecall usage |
| tx.origin | PASS - Not used |
| Unchecked Return Values | PASS - SafeERC20 used throughout |
| DoS Gas Limit | FINDING 5 - Unbounded claims loop (mitigated by off-chain construction) |
| Timestamp Dependence | FINDING 1 - Used only in swap deadline (no randomness) |
| Hash Collision | PASS - No `abi.encodePacked` with dynamic types |
| Signature Replay | PASS - No signature verification |
| All other 25 types | PASS - Not applicable to this contract |

### forefy (Yield + Staking Protocol Patterns)

| Pattern | Result |
|---|---|
| First Depositor Attack | N/A - Contract is not a vault, no share minting |
| Reward Accounting Errors | N/A - No reward accumulator, direct claim-and-forward |
| Stale Cached State | PASS - No cached external state; reads balances fresh |
| Slippage/Sandwich | PASS - Per-swap and aggregate minimums from keeper |
| Reentrancy | PASS - ReentrancyGuard applied |
| Access Control Bypass | PASS - No unprotected internal helpers reachable externally |
| DoS/Griefing | PASS - No unbounded user-controlled arrays |
| Unsafe Token Handling | PASS - SafeERC20 + forceApprove throughout |
| Missing Input Validation | FINDINGS 2, 3 - Minor validation gaps in config |
| ERC Standard Non-Compliance | N/A - Not implementing any ERC standard |

### Quill (5 Analysis Modules)

| Module | Result |
|---|---|
| Reentrancy Pattern Analysis | PASS - CEI pattern followed with ReentrancyGuard |
| External Call Safety | PASS - All external calls to trusted contracts with proper error handling |
| Input/Arithmetic Safety | PASS - No unsafe casts, no unchecked blocks, precision handled correctly |
| State Invariant Detection | FINDING 3 - Partial config validation allows inconsistent CAP state |
| Behavioral State Analysis | PASS - State transitions are atomic and consistent |

### Trail of Bits (5 Modules)

| Module | Result |
|---|---|
| Building Secure Contracts | PASS - Follows best practices (CEI, access control, SafeERC20) |
| Static Analysis Patterns | FINDING 1 - `block.timestamp` deadline pattern |
| Property-Based Testing | N/A - Requires test framework integration |
| Second Opinion | PASS - No disagreements with primary analysis |
| Sharp Edges | FINDING 6 - WETH placeholder in minPerSwapOutputs array |

### Cyfrin (solskill)

| Check | Result |
|---|---|
| Custom errors over require | PASS - All custom errors used |
| Access control | PASS - AccessControlEnumerable with proper role separation |
| Reentrancy guard | PASS - Applied to entry points |
| Function ordering | PASS - external > admin > view > internal |
| SafeERC20 usage | PASS - Consistent throughout |

### Archethect (Map-Hunt-Attack)

| Phase | Result |
|---|---|
| MAP - Attack surface | 3 external entry points (compound, claimOnly, realizeInterest) + 2 admin (updateConfig, recoverToken) |
| HUNT - Hypothesis testing | Tested: admin race condition (Finding 4), oracle manipulation (N/A), flash loan (N/A) |
| ATTACK - Exploit construction | No exploitable paths identified |

---

## Summary

| Severity | Count | IDs |
|----------|-------|-----|
| Critical | 0 | - |
| High | 0 | - |
| Medium | 1 | #1 (deadline: block.timestamp) |
| Low | 3 | #2 (reward token validation), #3 (CAP config validation), #4 (recoverToken race) |
| Informational | 3 | #5 (unbounded claims), #6 (WETH placeholder), #7 (forceApprove confirmation) |

---

## Previous Findings (Already Fixed)

For completeness, the two HIGH findings from the Pashov audit (commit `a0f5e78`) are confirmed fixed:

1. **Per-swap `amountOutMinimum: 0`** -- Fixed: `minPerSwapOutputs[]` array parameter now enforces per-token minimums
2. **oETH mint passes `0` minimum** -- Fixed: 0.1% tolerance check (`wethAmount * 9990 / 10000`) now applied

---

## Conclusion

CAPAutoPounder is a well-engineered contract with strong security properties. The only actionable finding is the `deadline: block.timestamp` pattern (Medium), which has meaningful mitigation already in place through the keeper-supplied slippage parameters. The remaining findings are low-severity defensive coding improvements that do not represent exploitable vulnerabilities given the trusted admin (multisig) and trusted compounder (keeper) roles.
