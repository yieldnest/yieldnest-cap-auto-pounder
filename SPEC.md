# CAP AutoPounder — Spec Sheet

## Task Origin

Epic: [Shortcut #3634](https://app.shortcut.com/yieldnest/epic/3634) — Claim rewards from CAP restaking and compound into ynLSDe.

Assigned by Dan Octavian. Reference implementation: [yieldnest-stakedao-auto-pounder](https://github.com/yieldnest/yieldnest-stakedao-auto-pounder).

## Status Overview

| Component | Status | Notes |
|-----------|--------|-------|
| Core contract (`CAPAutoPounder.sol`) | DONE | All PR review comments addressed + audit fixes |
| Interfaces | DONE | IRewardsCoordinator, ISwapRouter, IOETHVaultCore, IERC4626, ICAPInterest, IRedemptionAssetsVault |
| Mainnet addresses (`Contracts.sol`) | DONE | Dynamic staking nodes, all tokens sourced from EigenLayer Sidecar API |
| Actor addresses (`Actors.sol`) | DONE | YnSecurityCouncil, YnDev, StrategyController, YnDelegator |
| Fork integration tests | DONE | **21 tests passing** (18 original + 2 audit-fix + 1 deadline) |
| Off-chain keeper (`keeper/`) | DONE | check-rewards.ts + compound.ts |
| minWethOutput calculation | DONE | Uniswap V3 QuoterV2 + configurable slippage (default 2%) |
| Per-swap slippage protection | DONE | `minPerSwapOutputs[]` param prevents individual sandwich attacks |
| oETH mint slippage protection | DONE | 0.1% tolerance check on WETH→oETH conversion |
| README documentation | DONE | Architecture, addresses, design decisions, audit history |
| Security audit — Pashov | DONE | 2 findings at confidence 80, both fixed (commit `a0f5e78`) |
| Security audit — all 15 pipelines | DONE | **0 Critical, 0 High, 0 Medium** (deadline fixed). See `reports/mega-audit-report.md` |
| Deadline parameter | DONE | `compound()` now accepts `deadline` param, passed to Uniswap swaps |
| Deploy script (`Deploy.s.sol`) | DONE | Forge Script with full config |
| Verifier script (`Verify.s.sol`) | DONE | Post-deploy config + claimer validation |
| CI workflow | DONE | Unit tests (default) + fork tests (mainnet) + `forge fmt --check` |
| `setClaimer()` coordination | TODO | Via YnDelegator Safe tx after deployment |
| COMPOUNDER_ROLE grant | TODO | Grant to keeper wallet after deployment |
| Keeper hosting | TODO | Digital Ocean cron job |

## Architecture

```
                        Off-Chain Keeper (keeper/)
                              │
                    ┌─────────▼──────────┐
                    │  EigenLayer Sidecar │
                    │  (merkle proofs)    │
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │  Uniswap V3        │
                    │  QuoterV2          │ ← quotes expected WETH output
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │  CAPAutoPounder    │  ← COMPOUNDER_ROLE required
                    │  (on-chain)        │
                    └─────────┬──────────┘
                              │
        ┌─────────┬───────────┼───────────┬──────────┐
        ▼         ▼           ▼           ▼          ▼
   RewardsCoord  Uniswap V3  OETHVault  wOETH    RedemptionAssetsVault
   (claim)       (swap→WETH)  (mint oETH) (wrap)  (donate → ynLSDe)
```

**Workflow:** `claim rewards → swap to WETH → mint oETH → wrap to wOETH → donate to ynLSDe`

Donation via `RedemptionAssetsVault.deposit()` increases ynLSDe's `totalAssets()` without minting shares, raising the share rate for all holders.

## What's Been Built

### Contract: `src/CAPAutoPounder.sol`

**Entry Points (all require COMPOUNDER_ROLE):**
- `compound(claims, shouldRealizeInterest, minWethOutput, minPerSwapOutputs, deadline)` — Full pipeline
- `claimOnly(claims)` — Claim rewards only
- `realizeInterest()` — CAP interest only

**Admin (DEFAULT_ADMIN_ROLE):**
- `updateConfig(Config)` — Atomic config update
- `recoverToken(token, amount, dest)` — Sweep stuck tokens

**Key Design Decisions:**
- COMPOUNDER_ROLE always required (prevents sandwich attacks on minWethOutput)
- Typed `ICAPInterest` interface with try/catch (not low-level calls)
- Donation via `RedemptionAssetsVault` (not direct deposit)
- Dynamic staking nodes via `TokenStakingNodesManager.getAllNodes()`
- Per-swap `minPerSwapOutputs[]` prevents individual token sandwich attacks
- Aggregate `minWethOutput` as secondary safety net
- oETH mint protected with 0.1% tolerance (1:1 rate is protocol invariant)

### Off-Chain Keeper: `keeper/`

- `src/check-rewards.ts` — Read-only: queries unclaimed rewards across all nodes
- `src/compound.ts` — Full flow: fetch proofs → quote output → build claims → send tx
- **minWethOutput**: Uniswap V3 QuoterV2 quotes exact expected output per token, sums them, applies slippage tolerance (default 2%, configurable via `SLIPPAGE_BPS`)
- Supports `--dry-run` and `--realize-interest` flags
- EigenLayer Sidecar API for merkle proofs

### Tests: `test/mainnet/compound.spec.sol`

21 fork tests — all passing (`FOUNDRY_PROFILE=mainnet ETH_MAINNET_RPC_URL=<rpc> forge test -vv`):

| Test | What It Covers |
|------|---------------|
| `test_Configuration` | All state variables match expected |
| `test_StakingNodesClaimerSet` | All 5 nodes have autoPounder as claimer |
| `test_ClaimAndSwap` | EIGEN + USDC + WETH → swap → donate |
| `test_CompoundIncreasesYnLSDeRate` | totalAssets increases after donation |
| `test_CompoundWethOnly` | WETH-only path works |
| `test_CompoundNoTokens` | Zero balance doesn't revert |
| `test_CompoundSlippageProtection` | minWethOutput reverts when not met |
| `test_CompoundRequiresRole` | COMPOUNDER_ROLE enforced on compound() |
| `test_RealizeInterestRequiresRole` | COMPOUNDER_ROLE enforced on realizeInterest() |
| `test_ClaimOnlyRequiresRole` | COMPOUNDER_ROLE enforced on claimOnly() |
| `test_OnlyAdminCanUpdateConfig` | Non-admin reverts |
| `test_AdminCanUpdateConfig` | Config update succeeds + assertions |
| `test_RecoverToken` | Token sweep works |
| `test_RecoverTokenInvalidDestination` | address(0) reverts |
| `test_RealizeInterest` | Doesn't revert on CAP call failure |
| `test_ClaimOnly` | Empty claims works |
| `test_ConstructorInvalidAdmin` | address(0) admin reverts |
| `test_ConstructorArrayLengthMismatch` | Mismatched arrays revert |
| `test_CompoundDeadlineExpired` | Expired deadline reverts |
| `test_CompoundPerSwapSlippage` | Per-swap minimum reverts when not met |
| `test_CompoundMinPerSwapOutputsLengthMismatch` | Wrong array length reverts |

## Reward Tokens

Sourced from EigenLayer Sidecar API across all 5 staking nodes:

| Token | Address | Nodes | Unclaimed | Previously Claimed |
|-------|---------|-------|-----------|--------------------|
| EIGEN | `0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83` | All 5 | ~4,812 | ~11,057 (nodes 1-2) |
| USDC | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | Node 2 | ~528 | 0 |
| WETH | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` | Node 1 | ~0.024 | ~0.0036 |
| ARPA | `0xBA50933C268F567BDC86E1aC131BE072C6B0b71a` | All 5 | ~44 | ~15 (node 1) |
| ezSKATE | `0xC12E4D31e92ceDC1AD4c8c23DBcE2C5f7Cb52998` | Node 5 | ~0.807 | 0 |

## What's Left

### 1. Security Audit (COMPLETE)

**All 15 audit pipelines completed. No Critical or High vulnerabilities found.**

| Pipeline | Status | Findings |
|----------|--------|----------|
| `/solidity-auditor` (Pashov) | DONE | 2 HIGH (both fixed in `a0f5e78`) |
| `scv-scan` (36 vuln types) | DONE | 1 LOW (deadline), 1 INFO (wOETH shares) |
| Cyfrin `solskill` | DONE | 3 HIGH (code quality), 11 MEDIUM (style) — no security vulns |
| Quill `reentrancy` | DONE | 0 vulns, 3 informational |
| Quill `external-call-safety` | DONE | 2 MEDIUM (fee-on-transfer, residual WETH) |
| Quill `input-arithmetic-safety` | DONE | 1 MEDIUM (address(0) validation) |
| Quill `state-invariant-detection` | DONE | 2 MEDIUM (duplicate tokens, config orphans) |
| Quill `behavioral-state-analysis` | DONE | 5 LOW |
| Trail of Bits `building-secure-contracts` | DONE | 3 MEDIUM (timelock, oETH tolerance, admin powers), 4 LOW |
| Trail of Bits `static-analysis` (Semgrep) | DONE | 1 false positive, 26 gas optimizations |
| Trail of Bits `property-based-testing` | DONE | 9 suggested fuzz/invariant tests (no vulns) |
| Trail of Bits `second-opinion` | DONE | No disagreements with primary analysis |
| Trail of Bits `sharp-edges` | DONE | 3 MEDIUM (fee=0 skip, zero slippage, keeper bounds), 6 LOW |
| `forefy-audit` | DONE | Covered in mega-audit |
| Archethect `sc-auditor` | DONE | 2 LOW, 2 INFO |
| `mega-audit` (orchestrator) | DONE | Consolidated: 0 CRIT, 0 HIGH, 1 MEDIUM, 3 LOW, 3 INFO |

**Consolidated report:** `reports/mega-audit-report.md`

**Only actionable finding (MEDIUM):** `deadline: block.timestamp` on Uniswap swaps provides no real deadline protection. Mitigated by keeper-supplied per-swap and aggregate slippage minimums. Consider adding a `deadline` parameter to `compound()`.

**Low-priority improvements (not exploitable):**
1. Add `address(0)` check for reward tokens in `_applyConfig()`
2. Require `capRestaker`/`capInterestToken` non-zero when `capInterestContract` is set
3. Document WETH placeholder in `minPerSwapOutputs[]`
4. Consider timelock on `updateConfig()` (admin is already a multisig)
5. Consider making oETH mint tolerance configurable
6. Add fuzz/invariant tests (see TOB property-based testing report)

### 2. Deploy Script (`script/Deploy.s.sol`)

Following StakeDAO pattern:
```
script/
├── Deploy.s.sol              # forge script, saves deployment JSON
├── CAPAutoPounderDeployer.sol # Reusable config builder + deploy()
├── Verify.s.sol              # Post-deploy config validation
├── Contracts.sol              # DONE
└── Actors.sol                 # DONE
```

### 3. CI Workflow Update

Current `.github/workflows/test.yml` references `FOUNDRY_PROFILE: ci` which doesn't exist. Needs:
- Fix profile to use `default` for unit tests
- Add `mainnet` job for fork tests with `ETH_MAINNET_RPC_URL` secret
- Add `forge fmt --check`

### 4. Keeper Hosting

Set up on Digital Ocean with cron job. Needs:
- Node.js runtime with `keeper/` code
- Funded wallet with COMPOUNDER_ROLE
- `ETH_MAINNET_RPC_URL`, `PRIVATE_KEY`, `AUTO_POUNDER_ADDRESS` env vars
- Cron schedule (e.g., weekly or when rewards exceed threshold)

## Deployment Checklist

- [x] **1a. Pashov audit** — Done, 2 findings fixed
- [x] **1b. All 15 security scans complete** — No Critical/High. Deadline finding fixed.
- [x] **2. Deploy scripts** — `Deploy.s.sol` + `Verify.s.sol`
- [x] **3. CI fixed** — Unit tests + fork tests + `forge fmt --check`
- [ ] **4. Get ETH for deployment** — Dan sends to Saurabh's deploy address
- [ ] **5. Deploy to mainnet** — `forge script script/Deploy.s.sol --broadcast --verify`
- [ ] **6. Verify deployment** — `forge script script/Verify.s.sol`
- [ ] **7. setClaimer() on all 5 nodes** — YnDelegator (`0xDF51...28eF`) Safe tx
- [ ] **8. Grant COMPOUNDER_ROLE** — Admin grants to keeper wallet
- [ ] **9. Deploy keeper** — Digital Ocean cron job
- [ ] **10. First compound (dry-run)** — `npx tsx src/compound.ts --dry-run`
- [ ] **11. First compound (live)** — Monitor tx, verify ynLSDe totalAssets increases

## Key Addresses

| Name | Address | Role |
|------|---------|------|
| YnSecurityCouncil | `0xfcad670592a3b24869C0b51a6c6FDED4F95D6975` | DEFAULT_ADMIN_ROLE |
| YnDelegator | `0xDF51B7843817F76220C0970eF58Ba726630028eF` | TOKEN_STAKING_NODES_DELEGATOR_ROLE (setClaimer) |
| Current Claimer (EOA) | `0xaa6A4b49dc2E3fDee2d32d0B116b043067437593` | To be replaced by contract |
| RedemptionAssetsVault | `0x73bC33999C34a5126CA19dC900F22690C288D55e` | Donation target |

## Action Items

**Saurabh:**
- Run security audit skills against the contract (new Claude session)
- Build deploy script
- Set up keeper on Digital Ocean
- Deploy to mainnet

**Dan:**
- Send ETH to Saurabh's deploy address
- Submit setClaimer Safe tx via YnDelegator after deployment
- Grant COMPOUNDER_ROLE to keeper wallet

## Open Questions

1. **ezSKATE swap path** — Node 5 earns ezSKATE but no known Uniswap pool. Exclude from auto-compounding? Sweep later via `recoverToken`?
2. **Confirm RedemptionAssetsVault donation** — Verified on-chain, but worth confirming with Dan that this is the intended path.
3. **Keeper frequency** — How often to compound? Weekly? Threshold-based?

## Audit History

| # | Source | Severity | Finding | Resolution |
|---|--------|----------|---------|------------|
| 1 | Review | CRITICAL | wOETH wrapping used WETH directly | Fixed: WETH → OETHVault.mint() → oETH → wOETH.deposit() |
| 2 | Review | CRITICAL | Duplicate IERC20 in IRewardsCoordinator | Fixed: imports OZ IERC20 |
| 3 | Review | CRITICAL | minOutputBps + previewDeposit was no-op slippage | Fixed: keeper-provided minWethOutput |
| 4 | Review | HIGH | Low-level calls for wOETH/DepositAdapter | Fixed: typed interfaces |
| 5 | Review | HIGH | realizeInterest() missing address(0) guard | Fixed |
| 6 | Review | MEDIUM | WETH double-counting in swap loop | Fixed: returns balanceOf after all swaps |
| 7 | Review | MEDIUM | _realizeInterest swallowed failures | Fixed: CAPInterestRealizeFailed event |
| 8 | Review | MEDIUM | minOutputBps was dead code | Fixed: removed entirely |
| 9 | Pashov | HIGH | Per-swap `amountOutMinimum: 0` allows sandwich within aggregate | Fixed: `minPerSwapOutputs[]` param (commit `a0f5e78`) |
| 10 | Pashov | HIGH | oETH mint passes `0` minimum, unprotected by minWethOutput | Fixed: 0.1% tolerance check (commit `a0f5e78`) |

## Git History

| Commit | Description |
|--------|-------------|
| `266023b` | Initial repo scaffolding with Foundry and dependencies |
| `fac62bf` | Add CAPAutoPounder contract, tests, and documentation |
| `1400190` | Address PR review comments: off-chain keeper, typed interfaces, donation |
| `a86c634` | Fix fork tests: setClaimer and vm.prank ordering |
| `33d2413` | Update SPEC.md to reflect current state |
| `c22499f` | Add minWethOutput quoter and YnDelegator address |
| `35a2da6` | Update SPEC.md with action items |
| `a0f5e78` | Fix audit findings: per-swap slippage and oETH mint protection |
