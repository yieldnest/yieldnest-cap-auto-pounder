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
    address constant DEPOSIT_ADAPTER = 0x9e72155d301a6555dc565315be72D295c76753c0;
    address constant TOKEN_STAKING_NODES_MANAGER = 0x6B566CB6cDdf7d140C59F84594756a151030a0C3;
    address constant EIGEN_STRATEGY_MANAGER = 0x92D904019A92B0Cafce3492Abb95577C285A68fC;

    // ============================================
    // Staking Nodes (Earners)
    // ============================================
    address constant STAKING_NODE_1 = 0x7E312a16214ceDb43E3CD68BDc508c36CfD7c356;
    address constant STAKING_NODE_2 = 0x2B055a6898C0518Ed35733B162eC4C7459e9ACda;
    address constant STAKING_NODE_3 = 0xb7ae463C61366214a656c7B0365F462a6ed5D180;
    address constant STAKING_NODE_4 = 0x692E4991fD98c5aFB8e48f339Eda3DDd4240f0d6;
    address constant STAKING_NODE_5 = 0xDc9D9eff40BA2d4c8c0816f4982a5eaE52Df8863;

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
    address constant EIGEN = 0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant ARPA = 0xBA50933C268F567BDC86E1aC131BE072C6B0b71a;

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

    function getStakingNodes() internal pure returns (address[] memory) {
        address[] memory nodes = new address[](5);
        nodes[0] = STAKING_NODE_1;
        nodes[1] = STAKING_NODE_2;
        nodes[2] = STAKING_NODE_3;
        nodes[3] = STAKING_NODE_4;
        nodes[4] = STAKING_NODE_5;
        return nodes;
    }
}
