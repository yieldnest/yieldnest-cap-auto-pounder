export const SIDECAR_BASE_URL = "https://sidecar-rpc.eigenlayer.xyz/mainnet";

export const ADDRESSES = {
  // Contract
  autoPounder: process.env.AUTO_POUNDER_ADDRESS as `0x${string}`,

  // EigenLayer
  rewardsCoordinator: "0x7750d328b314EfFa365A0402CcfD489B80B0adda" as const,

  // TokenStakingNodesManager — staking nodes are read dynamically
  tokenStakingNodesManager: "0x6B566CB6cDdf7d140C59F84594756a151030a0C3" as const,

  // Uniswap V3
  quoterV2: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e" as const,

  // Tokens
  weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2" as const,
  eigen: "0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83" as const,
  usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48" as const,
  arpa: "0xBA50933C268F567BDC86E1aC131BE072C6B0b71a" as const,
  ezSkate: "0xC12E4D31e92ceDC1AD4c8c23DBcE2C5f7Cb52998" as const,
} as const;

// Uniswap V3 fee tiers per reward token (must match contract config)
export const SWAP_FEES: Record<string, number> = {
  [ADDRESSES.eigen.toLowerCase()]: 3000,   // 0.3%
  [ADDRESSES.usdc.toLowerCase()]: 500,     // 0.05%
  [ADDRESSES.arpa.toLowerCase()]: 10000,   // 1%
};

// Default slippage tolerance for minWethOutput (2%)
export const SLIPPAGE_BPS = Number(process.env.SLIPPAGE_BPS ?? "200");

// Known reward tokens for logging purposes
export const KNOWN_TOKENS: Record<string, string> = {
  "0xec53bf9167f50cdeb3ae105f56099aaab9061f83": "EIGEN",
  "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2": "WETH",
  "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48": "USDC",
  "0xba50933c268f567bdc86e1ac131be072c6b0b71a": "ARPA",
  "0xc12e4d31e92cedc1ad4c8c23dbce2c5f7cb52998": "ezSKATE",
};
