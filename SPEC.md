# CAP AutoPounder — Spec Sheet

## Task Origin

Epic: [Shortcut #3634](https://app.shortcut.com/yieldnest/epic/3634) — Claim rewards from CAP restaking and compound into ynLSDe.

Assigned by Dan Octavian. Reference implementation: [yieldnest-stakedao-auto-pounder](https://github.com/yieldnest/yieldnest-stakedao-auto-pounder).

## Status Overview

| Component | Status | Notes |
|-----------|--------|-------|
| Core contract (`CAPAutoPounder.sol`) | DONE | All PR review comments addressed |
| Interfaces | DONE | IRewardsCoordinator, ISwapRouter, IOETHVaultCore, IERC4626, ICAPInterest, IRedemptionAssetsVault |
| Mainnet addresses (`Contracts.sol`) | DONE | Dynamic staking nodes, all tokens sourced from EigenLayer Sidecar API |
| Actor addresses (`Actors.sol`) | DONE | YnSecurityCouncil, YnDev, StrategyController, YnDelegator |
| Fork integration tests | DONE | 18 tests passing |
| Off-chain keeper (`keeper/`) | DONE | check-rewards.ts + compound.ts |
| minWethOutput calculation | DONE | Uniswap V3 QuoterV2 + configurable slippage (default 2%) |
| README documentation | DONE | Architecture, addresses, design decisions, audit history |
| Security audit (skills) | TODO | Pashov, Trail of Bits, Cyfrin, scv-scan, Quill skills installed |
| Deploy script (`Deploy.s.sol`) | TODO | Forge Script for deterministic deployment |
| Verifier script | TODO | Post-deploy config validation |
| CI workflow update | TODO | Current CI uses `ci` profile (missing), needs `mainnet` fork tests |
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
- `compound(claims, shouldRealizeInterest, minWethOutput)` — Full pipeline
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
- Per-swap `amountOutMinimum: 0` with aggregate `minWethOutput` check

### Off-Chain Keeper: `keeper/`

- `src/check-rewards.ts` — Read-only: queries unclaimed rewards across all nodes
- `src/compound.ts` — Full flow: fetch proofs → quote output → build claims → send tx
- **minWethOutput**: Uniswap V3 QuoterV2 quotes exact expected output per token, sums them, applies slippage tolerance (default 2%, configurable via `SLIPPAGE_BPS`)
- Supports `--dry-run` and `--realize-interest` flags
- EigenLayer Sidecar API for merkle proofs

### Tests: `test/mainnet/compound.spec.sol`

18 fork tests — all passing (`FOUNDRY_PROFILE=mainnet ETH_MAINNET_RPC_URL=<rpc> forge test -vv`):

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

### 1. Security Audit (Next)

Run installed skills against the contract:
- `/solidity-auditor` (Pashov) — full security review
- `scv-scan` — 36 vulnerability types
- Trail of Bits skills — static analysis, sharp edges, second opinion
- Quill plugins — reentrancy, external calls, arithmetic, state invariants

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

- [ ] **1. Run security scans** — Pashov, scv-scan, TOB, Quill skills
- [ ] **2. Build deploy scripts** — Deploy.s.sol, Verifier
- [ ] **3. Fix CI** — Update workflow to use correct profile, add fork test job
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

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| 1 | CRITICAL | wOETH wrapping used WETH directly | Fixed: WETH → OETHVault.mint() → oETH → wOETH.deposit() |
| 2 | CRITICAL | Duplicate IERC20 in IRewardsCoordinator | Fixed: imports OZ IERC20 |
| 3 | CRITICAL | minOutputBps + previewDeposit was no-op slippage | Fixed: keeper-provided minWethOutput |
| 4 | HIGH | Low-level calls for wOETH/DepositAdapter | Fixed: typed interfaces |
| 5 | HIGH | realizeInterest() missing address(0) guard | Fixed |
| 6 | MEDIUM | WETH double-counting in swap loop | Fixed: returns balanceOf after all swaps |
| 7 | MEDIUM | _realizeInterest swallowed failures | Fixed: CAPInterestRealizeFailed event |
| 8 | MEDIUM | minOutputBps was dead code | Fixed: removed entirely |
