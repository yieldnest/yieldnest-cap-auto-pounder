# CAP AutoPounder — Spec Sheet

## Task Origin

Epic: [Shortcut #3634](https://app.shortcut.com/yieldnest/epic/3634) — Claim rewards from CAP restaking and compound into ynLSDe.

Assigned by Dan Octavian. Reference implementation: [yieldnest-stakedao-auto-pounder](https://github.com/yieldnest/yieldnest-stakedao-auto-pounder).

## Status Overview

| Component | Status | Notes |
|-----------|--------|-------|
| Core contract (`CAPAutoPounder.sol`) | DONE | 3 audit rounds completed |
| Interfaces | DONE | IRewardsCoordinator, ISwapRouter, IOETHVaultCore, IERC4626, IDepositAdapter |
| Mainnet addresses (`Contracts.sol`) | DONE | All 5 staking nodes, CAP, Origin, Uniswap, ynLSDe |
| Actor addresses (`Actors.sol`) | DONE | YnSecurityCouncil, YnDev, StrategyController |
| Fork integration tests | DONE | 16 tests covering compound, permissions, admin, constructor |
| README documentation | DONE | Architecture, addresses, design decisions, audit history |
| Deploy script (`Deploy.s.sol`) | TODO | Need Forge Script for deterministic deployment |
| Deployer library | TODO | Reusable config builder (pattern from StakeDAO) |
| Verifier script + library | TODO | Post-deploy config validation |
| Constructor args helper | TODO | For Etherscan bytecode verification |
| CI workflow update | TODO | Current CI uses `ci` profile (missing), needs `mainnet` fork tests |
| Deployment JSON artifact | TODO | `deployments/autoPounder-1.json` |
| Off-chain keeper | TODO | Fetches merkle proofs from EigenLayer Sidecar, calls `compound()` |
| `setClaimer()` coordination | TODO | Requires DELEGATOR role on TokenStakingNodesManager |

## What's Been Built

### Contract: `src/CAPAutoPounder.sol`

**Workflow:**
```
realizeRestakerInterest() → processClaim() → swap to WETH → OETHVault.mint() → wOETH.deposit() → DepositAdapter.deposit()
```

**Entry Points:**
- `compound(claims, shouldRealizeInterest, minWethOutput)` — Full pipeline
- `claimOnly(claims)` — Claim rewards only
- `realizeInterest()` — CAP interest only

**Admin:**
- `updateConfig(Config)` — Atomic config update (DEFAULT_ADMIN_ROLE)
- `recoverToken(token, amount, dest)` — Sweep stuck tokens (DEFAULT_ADMIN_ROLE)

**Auth Model:**
- COMPOUNDER_ROLE empty → permissionless
- COMPOUNDER_ROLE has members → restricted

### Tests: `test/mainnet/compound.spec.sol`

| Test | What It Covers |
|------|---------------|
| `test_Configuration` | All state variables match expected |
| `test_StakingNodesClaimerSet` | All 5 nodes have autoPounder as claimer |
| `test_ClaimAndSwap` | EIGEN + USDC + WETH → ynLSDe shares |
| `test_CompoundWethOnly` | WETH-only path works |
| `test_CompoundNoTokens` | Zero balance doesn't revert |
| `test_CompoundSlippageProtection` | `minWethOutput` reverts when not met |
| `test_CompoundPermissionless` | Works with no COMPOUNDER_ROLE members |
| `test_CompoundRequiresRole` | Enforced when members exist |
| `test_RealizeInterestRequiresRole` | Role gating on realizeInterest() |
| `test_ClaimOnlyRequiresRole` | Role gating on claimOnly() |
| `test_OnlyAdminCanUpdateConfig` | Non-admin reverts |
| `test_AdminCanUpdateConfig` | Config update succeeds + assertions |
| `test_RecoverToken` | Sweep works |
| `test_RecoverTokenInvalidDestination` | address(0) reverts |
| `test_RealizeInterest` | Doesn't revert on CAP call failure |
| `test_ClaimOnly` | Empty claims works |
| `test_ConstructorInvalidAdmin` | address(0) admin reverts |
| `test_ConstructorArrayLengthMismatch` | Mismatched arrays revert |

### Audit Findings (3 rounds)

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| 1 | CRITICAL | wOETH wrapping used WETH directly (wOETH is ERC4626 over oETH) | Fixed: WETH → OETHVault.mint() → oETH → wOETH.deposit() |
| 2 | CRITICAL | Duplicate IERC20 in IRewardsCoordinator.sol | Fixed: imports OZ IERC20 |
| 3 | CRITICAL | minOutputBps + previewDeposit was a no-op slippage check | Fixed: keeper-provided `minWethOutput` parameter |
| 4 | HIGH | Low-level calls for wOETH/DepositAdapter | Fixed: typed interfaces |
| 5 | HIGH | realizeInterest() missing address(0) guard | Fixed: added check |
| 6 | MEDIUM | WETH double-counting in swap loop | Fixed: returns balanceOf after all swaps |
| 7 | MEDIUM | _realizeInterest swallowed failures silently | Fixed: CAPInterestRealizeFailed event |
| 8 | MEDIUM | minOutputBps was dead code (stored but never enforced) | Fixed: removed entirely |

### Known Accepted Risks

- **Individual swap sandwich**: `amountOutMinimum: 0` per swap, aggregate `minWethOutput` limits total. Low risk given ~$15K reward size.
- **Pre-existing WETH inclusion**: Residual WETH counted in `totalWeth`. Mitigated by `recoverToken()` for sweeping.
- **No pause mechanism**: Admin grants COMPOUNDER_ROLE to dummy address to effectively pause.

## What Needs To Be Built

### 1. Deploy Script (`script/Deploy.s.sol`)

Following StakeDAO pattern:
```
script/
├── Deploy.s.sol              # forge script, saves deployment JSON
├── CAPAutoPounderDeployer.sol # Reusable config builder + deploy()
├── Verify.s.sol              # Post-deploy verification script
├── CAPAutoPounderVerifier.sol # Reusable verification library
├── ConstructorArgs.s.sol      # For Etherscan bytecode verification
├── Contracts.sol              # DONE — mainnet addresses
└── Actors.sol                 # DONE — admin addresses
```

Deployer should:
- Build Config struct from Contracts.sol constants
- Deploy with `new CAPAutoPounder(config, admin)`
- Save deployment artifact to `deployments/autoPounder-1.json`

Verifier should:
- Read deployment artifact
- Assert all config fields match expected values
- Assert admin role is correctly assigned

### 2. `setClaimer()` Transaction

After deploy, each of the 5 staking nodes needs:
```solidity
ITokenStakingNode(node).setClaimer(address(autoPounder));
```

This requires the **DELEGATOR role** on TokenStakingNodesManager (`0x6B566CB6cDdf7d140C59F84594756a151030a0C3`).

Options:
- Safe transaction from YnSecurityCouncil (`0xfcad...6975`)
- Multisig proposal if YN_DEV (`0xa08F...1C3`) has the role

Current claimer EOA: `0xaa6A4b49dc2E3fDee2d32d0B116b043067437593`

### 3. CI Workflow Update

Current `.github/workflows/test.yml` references `FOUNDRY_PROFILE: ci` which doesn't exist in `foundry.toml`. Needs:
- Fix profile to use `default` for unit tests
- Add `mainnet` job for fork tests with `ETH_MAINNET_RPC_URL` secret
- Add `forge fmt --check`

### 4. Off-Chain Keeper

**Purpose:** Periodically fetch merkle proofs and call `compound()`.

**EigenLayer Sidecar API:**
- Base URL: `https://sidecar-rpc.eigenlayer.xyz/mainnet`
- `GET /rewards/v1/earners/{addr}/lifetime-rewards` — Check available rewards
- `POST /rewards/v1/claim-proof` — Get merkle proof for claiming

**Keeper Flow:**
1. For each of 5 staking nodes, query lifetime rewards
2. Subtract already-claimed amounts (`cumulativeClaimed()` on RewardsCoordinator)
3. If unclaimed > threshold, fetch merkle proofs
4. Calculate expected WETH output (off-chain price feeds) → set `minWethOutput`
5. Call `compound(claims, shouldRealizeInterest, minWethOutput)`

**Tech options:** TypeScript with ethers.js/viem, or Python with web3.py. Can run as cron job, Gelato task, or GitHub Action.

### 5. Deployment Artifact

Save to `deployments/autoPounder-1.json`:
```json
{
  "contractAddress": "0x...",
  "deployer": "0x...",
  "admin": "0xfcad670592a3b24869C0b51a6c6FDED4F95D6975",
  "chainId": 1,
  "blockNumber": ...,
  "config": {
    "rewardsCoordinator": "0x7750d328b314EfFa365A0402CcfD489B80B0adda",
    "capInterestContract": "0x15622c3dbbc5614E6DFa9446603c1779647f01FC",
    "capRestaker": "0x5f33ff3027c4763D36e6f4F7C20eE72F700A5D34",
    "...": "..."
  }
}
```

## Deployment Checklist (Ordered)

- [ ] **1. Build deploy scripts** — Deploy.s.sol, Deployer lib, Verifier lib
- [ ] **2. Fix CI** — Update workflow to use correct profile, add fork test job
- [ ] **3. Run fork tests** — `FOUNDRY_PROFILE=mainnet forge test -vvv`
- [ ] **4. Deploy to mainnet** — `forge script script/Deploy.s.sol --broadcast --verify`
- [ ] **5. Verify deployment** — `forge script script/Verify.s.sol`
- [ ] **6. setClaimer() on all 5 nodes** — Coordinate with YN admin (Safe tx)
- [ ] **7. (Optional) Grant COMPOUNDER_ROLE** — If restricting to keeper address
- [ ] **8. Build & deploy keeper** — Off-chain merkle proof fetcher + compound() caller
- [ ] **9. Monitor first compound** — Verify ynLSDe shares received at recipient

## Unclaimed Rewards (as of Feb 2025)

| Token | Amount | USD Est. |
|-------|--------|----------|
| EIGEN | ~4,812 | ~$8,000 |
| USDC | ~528 | $528 |
| WETH | ~0.024 | ~$65 |
| ARPA | ~44 | ~$2 |
| **Total** | | **~$8,600** |

## Key Contacts

- **Dan Octavian** — Task owner, YieldNest
- **CAP Team** — For `realizeRestakerInterest` questions
- **YN Admin (YnSecurityCouncil)** — For setClaimer() and role grants
