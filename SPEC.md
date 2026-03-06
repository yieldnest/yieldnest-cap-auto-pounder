# CAP AutoPounder — Spec Sheet

## Task Origin

Epic: [Shortcut #3634](https://app.shortcut.com/yieldnest/epic/3634) — Claim rewards from CAP restaking and compound into ynLSDe.

Assigned by Dan Octavian. Reference implementation: [yieldnest-stakedao-auto-pounder](https://github.com/yieldnest/yieldnest-stakedao-auto-pounder).

## Status Overview

| Component | Status | Notes |
|-----------|--------|-------|
| Core contract (`CAPAutoPounder.sol`) | DONE | Audited, all PR review comments addressed |
| Interfaces | DONE | IRewardsCoordinator, ISwapRouter, IOETHVaultCore, IERC4626, ICAPInterest, IRedemptionAssetsVault |
| Mainnet addresses (`Contracts.sol`) | DONE | Dynamic staking nodes, all tokens sourced from EigenLayer Sidecar API |
| Actor addresses (`Actors.sol`) | DONE | YnSecurityCouncil, YnDev, StrategyController |
| Fork integration tests | DONE | 18 tests passing — compound, permissions, admin, constructor, donation rate |
| Off-chain keeper (`keeper/`) | DONE | Node.js/viem — check-rewards.ts + compound.ts with --dry-run |
| README documentation | DONE | Architecture, addresses, design decisions, audit history |
| Deploy script (`Deploy.s.sol`) | TODO | Forge Script for deterministic deployment |
| Deployer library | TODO | Reusable config builder (pattern from StakeDAO) |
| Verifier script + library | TODO | Post-deploy config validation |
| Constructor args helper | TODO | For Etherscan bytecode verification |
| CI workflow update | TODO | Current CI uses `ci` profile (missing), needs `mainnet` fork tests |
| Deployment JSON artifact | TODO | `deployments/autoPounder-1.json` |
| `setClaimer()` coordination | TODO | Requires DELEGATOR role — Safe transaction from YnSecurityCouncil |
| COMPOUNDER_ROLE grant | TODO | Grant to keeper wallet after deployment |

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
- `src/compound.ts` — Full flow: fetch proofs → build claims → send tx
- Supports `--dry-run` and `--realize-interest` flags
- EigenLayer Sidecar API for merkle proofs

### Tests: `test/mainnet/compound.spec.sol`

18 fork tests covering:
- Configuration validation
- Claimer setup for all staking nodes
- Compound with mixed tokens (EIGEN + USDC + WETH)
- Compound WETH-only path
- Compound with zero balances (no revert)
- Slippage protection (minWethOutput enforcement)
- ynLSDe totalAssets increases after donation
- COMPOUNDER_ROLE enforcement on all 3 entry points
- Admin config update (authorized + unauthorized)
- Token recovery
- CAP interest realization
- Constructor validation (invalid admin, array mismatch)

## Reward Tokens

Sourced from EigenLayer Sidecar API across all 5 staking nodes:

| Token | Address | Nodes | Unclaimed | Previously Claimed |
|-------|---------|-------|-----------|--------------------|
| EIGEN | `0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83` | All 5 | ~4,812 | ~11,057 (nodes 1-2) |
| USDC | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | Node 2 | ~528 | 0 |
| WETH | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` | Node 1 | ~0.024 | ~0.0036 |
| ARPA | `0xBA50933C268F567BDC86E1aC131BE072C6B0b71a` | All 5 | ~44 | ~15 (node 1) |
| ezSKATE | `0xC12E4D31e92ceDC1AD4c8c23DBcE2C5f7Cb52998` | Node 5 | ~0.807 | 0 |

## What Needs To Be Built

### 1. Deploy Script (`script/Deploy.s.sol`)

Following StakeDAO pattern:
```
script/
├── Deploy.s.sol              # forge script, saves deployment JSON
├── CAPAutoPounderDeployer.sol # Reusable config builder + deploy()
├── Verify.s.sol              # Post-deploy config validation
├── CAPAutoPounderVerifier.sol # Reusable verification library
├── ConstructorArgs.s.sol      # For Etherscan bytecode verification
├── Contracts.sol              # DONE
└── Actors.sol                 # DONE
```

### 2. CI Workflow Update

Current `.github/workflows/test.yml` references `FOUNDRY_PROFILE: ci` which doesn't exist. Needs:
- Fix profile to use `default` for unit tests
- Add `mainnet` job for fork tests with `ETH_MAINNET_RPC_URL` secret
- Add `forge fmt --check`

### 3. Deployment Artifact

Save to `deployments/autoPounder-1.json` with contract address, deployer, config, block number.

## Deployment Checklist

- [ ] **1. Build deploy scripts** — Deploy.s.sol, Deployer lib, Verifier lib
- [ ] **2. Fix CI** — Update workflow to use correct profile, add fork test job
- [ ] **3. Deploy to mainnet** — `forge script script/Deploy.s.sol --broadcast --verify`
- [ ] **4. Verify deployment** — `forge script script/Verify.s.sol`
- [ ] **5. setClaimer() on all 5 nodes** — Safe tx from YnSecurityCouncil (changes claimer from `0xaa6A...7593` to deployed contract)
- [ ] **6. Grant COMPOUNDER_ROLE** — Admin grants to keeper wallet address
- [ ] **7. Deploy keeper** — Set up cron/Gelato for periodic compounding
- [ ] **8. First compound (dry-run)** — `npx tsx src/compound.ts --dry-run`
- [ ] **9. First compound (live)** — Monitor tx, verify ynLSDe totalAssets increases

## Action Items for Team Discussion

1. **Who calls setClaimer?** — Requires DELEGATOR role on each staking node. Current claimer is EOA `0xaa6A4b49dc2E3fDee2d32d0B116b043067437593`. Need YnSecurityCouncil Safe transaction to change to deployed contract address.

2. **Keeper hosting** — Where to run the keeper? Options: cron on a server, Gelato Network, GitHub Actions. Needs a funded wallet with COMPOUNDER_ROLE.

3. **Confirm RedemptionAssetsVault donation mechanism** — Verified on-chain that `0x73bC...D55e` is permissionless and wOETH is supported. Should confirm with Dan/ynLSDe team that this is the intended donation path.

4. **ezSKATE swap path** — ezSKATE is earned by Node 5 but not currently in the reward tokens config (no known Uniswap pool). Need to research liquidity or exclude from auto-compounding.

5. **minWethOutput calculation** — Currently keeper passes 0 in dry-run. Need to integrate price feeds (Chainlink/Uniswap TWAP) for production slippage calculation.

6. **Deploy timing** — ~$8,600 in unclaimed rewards growing. Previous claims totaled ~$18K EIGEN across nodes 1-2.

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

## Key Contacts

- **Dan Octavian** — Task owner, YieldNest
- **CAP Team** — For `realizeRestakerInterest` questions
- **YN Admin (YnSecurityCouncil)** — For setClaimer() and role grants
