# SCV-Scan Audit Report: CAPAutoPounder

**Date:** 2026-03-09
**Audited Contract:** `src/CAPAutoPounder.sol`
**Solidity Version:** ^0.8.24
**Scope:** All files under `src/` (CAPAutoPounder.sol + 6 interfaces)

---

### Ineffective Swap Deadline (`block.timestamp`)

**File:** `src/CAPAutoPounder.sol` L255-264
**Severity:** Low

**Description:** The Uniswap V3 swap sets `deadline: block.timestamp`, which provides no actual deadline protection. The deadline is meant to allow the transaction to revert if it has been sitting in the mempool too long and the keeper's slippage parameters are based on stale prices. Since `block.timestamp` always equals the current block's timestamp at execution time, the deadline can never expire, regardless of how long the transaction was pending.

The impact is reduced because the contract has per-swap `amountOutMinimum` values (`minPerSwapOutputs[i]`) and a total `minWethOutput` check, which together provide primary sandwich protection. However, these minimums are calculated off-chain by the keeper based on prices at submission time. If the transaction is delayed in the mempool, those minimums may no longer represent adequate protection as prices have moved.

**Code:**
```solidity
ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
    tokenIn: token,
    tokenOut: weth,
    fee: fee,
    recipient: address(this),
    deadline: block.timestamp,  // Always passes -- provides no protection
    amountIn: balance,
    amountOutMinimum: minPerSwapOutputs[i],
    sqrtPriceLimitX96: 0
});
```

**Recommendation:** Accept a `deadline` parameter from the keeper (caller of `compound()`) and pass it through to the swap. This allows the keeper to set a real expiration time. If the transaction is not mined by the deadline, it reverts, and the keeper can resubmit with fresh slippage parameters.

```solidity
function compound(
    IRewardsCoordinator.RewardsMerkleClaim[] calldata claims,
    bool shouldRealizeInterest,
    uint256 minWethOutput,
    uint256[] calldata minPerSwapOutputs,
    uint256 deadline  // Add deadline parameter
) external nonReentrant onlyRole(COMPOUNDER_ROLE) {
    require(block.timestamp <= deadline, "expired");
    // ...
}
```

---

### No Minimum Shares Check on wOETH Wrapping

**File:** `src/CAPAutoPounder.sol` L296-297
**Severity:** Informational

**Description:** The `woeth.deposit(oethReceived, address(this))` call wraps oETH into wOETH via an ERC4626 vault but does not verify the returned `woethReceived` against any minimum expected amount. While the wOETH contract (Origin Protocol) is a trusted, deterministic ERC4626 vault where the exchange rate is well-defined, as a defense-in-depth measure, validating the output would protect against unexpected behavior from the external vault (e.g., if the vault were upgraded to a version with different rounding behavior).

**Code:**
```solidity
IERC20(oeth).forceApprove(address(woeth), oethReceived);
uint256 woethReceived = woeth.deposit(oethReceived, address(this));
// No check: woethReceived could theoretically be less than expected
return woethReceived;
```

**Recommendation:** Add a minimum output check using `previewDeposit()` or a hardcoded tolerance, similar to the oETH mint check above it.

```solidity
uint256 woethReceived = woeth.deposit(oethReceived, address(this));
uint256 expectedShares = woeth.previewDeposit(oethReceived);
if (woethReceived < expectedShares * 9990 / 10000) {
    revert WOETHWrapSlippage(woethReceived, expectedShares);
}
```

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0     |
| High     | 0     |
| Medium   | 0     |
| Low      | 1     |
| Info     | 1     |

## Notes on Positive Security Practices

The codebase demonstrates several strong security patterns:

- **ReentrancyGuard** applied to all state-changing external functions that interact with multiple protocols
- **AccessControlEnumerable** with proper role separation (COMPOUNDER_ROLE vs DEFAULT_ADMIN_ROLE)
- **SafeERC20** with `safeTransfer` and `forceApprove` used consistently for all token operations
- **Per-swap slippage protection** via `minPerSwapOutputs` plus aggregate `minWethOutput` check
- **oETH mint slippage** with 0.1% tolerance check
- **Input validation** on config with zero-address checks and array length matching
- **Token recovery** function with destination validation for stuck tokens
- **Solidity ^0.8.24** with built-in overflow protection (no `unchecked` blocks)
- No use of `delegatecall`, `selfdestruct`, `tx.origin`, `ecrecover`, or assembly
- No upgradeable proxy pattern (simple deployment, reduced attack surface)
