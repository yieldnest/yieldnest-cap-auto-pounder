# CAP AutoPounder

Automates EigenLayer reward claiming and compounding into ynLSDe for YieldNest's CAP restaking positions.

## Overview

YieldNest's ynLSDe system uses 5 TokenStakingNodes that earn EigenLayer rewards (EIGEN, WETH, USDC, ARPA) via CAP restaking. This contract replaces the current manual EOA claimer (`0xaa6A...7593`) with an automated compounding pipeline:

```
EigenLayer Rewards → Claim → Swap to WETH → Mint oETH → Wrap to wOETH → Deposit into ynLSDe
```

### Workflow

1. **(Optional)** Call `realizeRestakerInterest(address,address)` on CAP protocol to notify EigenLayer
2. **Claim** accumulated rewards from EigenLayer RewardsCoordinator using merkle proofs
3. **Swap** reward tokens (EIGEN, USDC, ARPA) to WETH via Uniswap V3
4. **Mint** oETH from WETH via Origin Protocol's OETHVault (1:1 rate)
5. **Wrap** oETH into wOETH (ERC4626 vault share)
6. **Deposit** wOETH into ynLSDe via DepositAdapter

## Architecture

```
                    ┌─────────────────────────┐
                    │    Off-chain Keeper      │
                    │ (fetches merkle proofs   │
                    │  from EigenLayer Sidecar │
                    │  API, calls compound())  │
                    └────────────┬────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │    CAPAutoPounder       │
                    │  (set as claimer for    │
                    │   all 5 staking nodes)  │
                    └────────────┬────────────┘
                                 │
        ┌────────────┬───────────┼───────────┬────────────┐
        │            │           │           │            │
   ┌────▼────┐  ┌────▼────┐ ┌───▼───┐  ┌───▼───┐  ┌────▼────┐
   │  CAP    │  │EigenLayer│ │Uniswap│  │ Origin│  │ynLSDe   │
   │Interest │  │Rewards   │ │  V3   │  │ oETH  │  │Deposit  │
   │Contract │  │Coord.    │ │Router │  │ Vault │  │Adapter  │
   └─────────┘  └──────────┘ └───────┘  └───────┘  └─────────┘
```

## Key Design Decisions

### wOETH Wrapping Path
wOETH is an ERC4626 vault over **oETH** (not WETH). The correct path is:
```
WETH → OETHVault.mint() → oETH → wOETH.deposit() → wOETH
```
Verified on-chain: `wOETH.asset()` = oETH, `OETHVault.priceUnitMint(WETH)` = 1e18 (1:1).

### Slippage Protection
- **Aggregate slippage**: The keeper calculates expected WETH output off-chain and passes `minWethOutput` to `compound()`. If total WETH after all swaps is below this threshold, the transaction reverts with `SlippageExceeded`.
- **Individual swaps**: Use `amountOutMinimum: 0` on Uniswap since the aggregate check covers sandwich protection.
- The `minWethOutput` approach was chosen over an on-chain BPS check because on-chain oracle-free BPS calculations provide false security (the reference price itself can be manipulated in the same block).

### Permissioning
- If `COMPOUNDER_ROLE` has zero members → **anyone** can call `compound()` (permissionless)
- If `COMPOUNDER_ROLE` has members → only those addresses can call (keeper-restricted)
- `DEFAULT_ADMIN_ROLE` manages configuration updates and token recovery

### oETH Rebasing
Smart contracts default to non-rebasing mode for oETH. The balance-before-after pattern in `_mintAndWrapToWoeth` correctly tracks minted oETH.

## Mainnet Addresses

| Contract | Address |
|----------|---------|
| RewardsCoordinator | `0x7750d328b314EfFa365A0402CcfD489B80B0adda` |
| Staking Node 1 | `0x7E312a16214ceDb43E3CD68BDc508c36CfD7c356` |
| Staking Node 2 | `0x2B055a6898C0518Ed35733B162eC4C7459e9ACda` |
| Staking Node 3 | `0xb7ae463C61366214a656c7B0365F462a6ed5D180` |
| Staking Node 4 | `0x692E4991fD98c5aFB8e48f339Eda3DDd4240f0d6` |
| Staking Node 5 | `0xDc9D9eff40BA2d4c8c0816f4982a5eaE52Df8863` |
| CAP Interest Contract | `0x15622c3dbbc5614E6DFa9446603c1779647f01FC` |
| CAP Restaker Safe | `0x5f33ff3027c4763D36e6f4F7C20eE72F700A5D34` |
| Current Claimer (EOA, to be replaced) | `0xaa6A4b49dc2E3fDee2d32d0B116b043067437593` |
| OETHVault | `0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab` |
| wOETH | `0xDcEe70654261AF21C44c093C300eD3Bb97b78192` |
| oETH | `0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3` |
| WETH | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` |
| EIGEN | `0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83` |
| USDC | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` |
| ARPA | `0xBA50933C268F567BDC86E1aC131BE072C6B0b71a` |
| Uniswap V3 Router | `0xE592427A0AEce92De3Edee1F18E0157C05861564` |
| ynLSDe | `0x35Ec69A77B79c255e5d47D5A3BdbEFEfE342630c` |
| DepositAdapter | `0x9e72155d301a6555dc565315be72D295c76753c0` |
| TokenStakingNodesManager | `0x6B566CB6cDdf7d140C59F84594756a151030a0C3` |
| Admin (YnSecurityCouncil) | `0xfcad670592a3b24869C0b51a6c6FDED4F95D6975` |

## Unclaimed Rewards (as of Feb 2025)

Queried from EigenLayer Sidecar API (`https://sidecar-rpc.eigenlayer.xyz/mainnet`):

| Token | Amount | Across Nodes |
|-------|--------|--------------|
| EIGEN | ~4,812 | All 5 nodes |
| USDC | ~528 | Nodes 1-4 |
| WETH | ~0.024 ETH | Nodes 1-2 |
| ARPA | ~44 | Nodes 1-2 |

## Uniswap V3 Fee Tiers

| Pair | Fee | Tier |
|------|-----|------|
| EIGEN/WETH | 3000 (0.3%) | Medium |
| USDC/WETH | 500 (0.05%) | Low |
| ARPA/WETH | 10000 (1%) | High |
| WETH | 0 | No swap needed |

## Development

### Build
```bash
forge build
```

### Test (Unit)
```bash
forge test
```

### Test (Mainnet Fork)
```bash
ETH_MAINNET_RPC_URL=<your-rpc-url> FOUNDRY_PROFILE=mainnet forge test -vvv
```

### Project Structure
```
src/
├── CAPAutoPounder.sol              # Main contract
└── interfaces/
    ├── IRewardsCoordinator.sol     # EigenLayer rewards claiming
    ├── ISwapRouter.sol             # Uniswap V3 exact input single
    ├── IOETHVaultCore.sol          # Origin Protocol oETH minting
    ├── IERC4626.sol                # ERC4626 for wOETH wrapping
    └── IDepositAdapter.sol         # ynLSDe deposit adapter
script/
├── Contracts.sol                   # Mainnet contract addresses
└── Actors.sol                      # Admin/dev addresses
test/
└── mainnet/
    ├── BaseIntegrationTest.sol     # Fork test setup + claimer config
    └── compound.spec.sol           # Integration tests
```

## Deployment Checklist

1. Deploy `CAPAutoPounder` with Config struct and admin address
2. Call `setClaimer(address(autoPounder))` on each of the 5 TokenStakingNodes (requires DELEGATOR role via TokenStakingNodesManager)
3. (Optional) Grant `COMPOUNDER_ROLE` to keeper address to restrict who can compound
4. Deploy off-chain keeper that:
   - Fetches merkle proofs from EigenLayer Sidecar API
   - Calculates expected WETH output for `minWethOutput` slippage protection
   - Calls `compound()` periodically

## Audit History

Three rounds of manual audit were performed covering:
- Correct wrapping path (WETH → oETH → wOETH, not WETH → wOETH directly)
- Slippage protection design (keeper-provided `minWethOutput` vs dead on-chain BPS check)
- Interface correctness (typed interfaces vs low-level calls)
- Token safety (SafeERC20/forceApprove for USDT compatibility)
- Reentrancy protection (ReentrancyGuard on state-changing functions)
- Access control (role-based with permissionless fallback)
- oETH rebasing behavior (contracts default to non-rebasing)
- Balance tracking (before-after pattern for oETH minting)

### Known Accepted Risks
- **Individual swap sandwich**: `amountOutMinimum: 0` on each Uniswap swap means individual swaps can be sandwiched, though the aggregate `minWethOutput` limits total damage. For the reward amounts involved (~$15K total), MEV risk is low.
- **Pre-existing WETH**: If the contract holds residual WETH before `compound()`, it gets included in `totalWeth`. The `recoverToken()` admin function can sweep residual tokens if needed.
- **No pause**: To effectively pause, admin grants `COMPOUNDER_ROLE` to a dummy address. A formal pause mechanism was not added to keep the contract simple.

## EigenLayer Sidecar API

Base URL: `https://sidecar-rpc.eigenlayer.xyz/mainnet`

### Get Lifetime Rewards
```
GET /rewards/v1/earners/{earnerAddress}/lifetime-rewards
```

### Get Claim Proof
```
POST /rewards/v1/claim-proof
Body: { "earnerAddress": "0x...", "tokens": ["0x..."] }
```

The keeper uses these endpoints to construct `RewardsMerkleClaim` structs for `compound()`.
