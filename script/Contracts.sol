// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library MainnetContracts {
    // ============================================
    // EigenLayer
    // ============================================
    address constant REWARDS_COORDINATOR = 0x7750d328b314EfFa365A0402CcfD489B80B0adda;

    // ============================================
    // YieldNest ynLSDe Deployment
    // ============================================
    address constant YN_LSDE = 0x35Ec69A77B79c255e5d47D5A3BdbEFEfE342630c;
    address constant TOKEN_STAKING_NODES_MANAGER = 0x6B566CB6cDdf7d140C59F84594756a151030a0C3;
    address constant EIGEN_STRATEGY_MANAGER = 0x92D904019A92B0Cafce3492Abb95577C285A68fC;
    address constant REDEMPTION_ASSETS_VAULT = 0x73bC33999C34a5126CA19dC900F22690C288D55e;

    // ============================================
    // CAP Protocol
    // ============================================
    address constant CAP_INTEREST_CONTRACT = 0x15622c3dbbc5614E6DFa9446603c1779647f01FC;
    address constant CAP_RESTAKER_SAFE = 0x5f33ff3027c4763D36e6f4F7C20eE72F700A5D34;

    // ============================================
    // Origin Protocol (oETH / wOETH)
    // ============================================
    address constant OETH_VAULT = 0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab;

    // ============================================
    // Tokens
    // ============================================
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WOETH = 0xDcEe70654261AF21C44c093C300eD3Bb97b78192;
    address constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;

    // Reward tokens — sourced from EigenLayer Sidecar API:
    // GET https://sidecar-rpc.eigenlayer.xyz/mainnet/rewards/v1/earners/{node}/lifetime-rewards
    // Queried across all 5 staking nodes (via TokenStakingNodesManager.getAllNodes())
    address constant EIGEN = 0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83; // All 5 nodes
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // Node 2
    address constant ARPA = 0xBA50933C268F567BDC86E1aC131BE072C6B0b71a; // All 5 nodes
    address constant EZ_SKATE = 0xC12E4D31e92ceDC1AD4c8c23DBcE2C5f7Cb52998; // Node 5

    // ============================================
    // DEX
    // ============================================
    address constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    // ============================================
    // Uniswap V3 Fee Tiers
    // ============================================
    uint24 constant FEE_LOW = 500; // 0.05%
    uint24 constant FEE_MEDIUM = 3000; // 0.3%
    uint24 constant FEE_HIGH = 10000; // 1%

    // ============================================
    // Current Claimer (to be replaced by CAPAutoPounder)
    // ============================================
    address constant CURRENT_CLAIMER = 0xaa6A4b49dc2E3fDee2d32d0B116b043067437593;
}
