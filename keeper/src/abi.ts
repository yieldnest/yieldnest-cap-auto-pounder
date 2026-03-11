export const tokenStakingNodesManagerAbi = [
  {
    inputs: [],
    name: "getAllNodes",
    outputs: [{ internalType: "address[]", name: "", type: "address[]" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

export const rewardsCoordinatorAbi = [
  {
    inputs: [
      { internalType: "address", name: "earner", type: "address" },
      { internalType: "contract IERC20", name: "token", type: "address" },
    ],
    name: "cumulativeClaimed",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

export const autoPounderAbi = [
  {
    inputs: [
      {
        components: [
          { internalType: "uint32", name: "rootIndex", type: "uint32" },
          { internalType: "uint32", name: "earnerIndex", type: "uint32" },
          { internalType: "bytes", name: "earnerTreeProof", type: "bytes" },
          {
            components: [
              { internalType: "address", name: "earner", type: "address" },
              { internalType: "bytes32", name: "earnerTokenRoot", type: "bytes32" },
            ],
            internalType: "struct IRewardsCoordinator.EarnerTreeMerkleLeaf",
            name: "earnerLeaf",
            type: "tuple",
          },
          { internalType: "uint32[]", name: "tokenIndices", type: "uint32[]" },
          { internalType: "bytes[]", name: "tokenTreeProofs", type: "bytes[]" },
          {
            components: [
              { internalType: "contract IERC20", name: "token", type: "address" },
              { internalType: "uint256", name: "cumulativeEarnings", type: "uint256" },
            ],
            internalType: "struct IRewardsCoordinator.TokenTreeMerkleLeaf[]",
            name: "tokenLeaves",
            type: "tuple[]",
          },
        ],
        internalType: "struct IRewardsCoordinator.RewardsMerkleClaim[]",
        name: "claims",
        type: "tuple[]",
      },
      { internalType: "bool", name: "shouldRealizeInterest", type: "bool" },
      { internalType: "uint256", name: "minWethOutput", type: "uint256" },
      { internalType: "uint256[]", name: "minPerSwapOutputs", type: "uint256[]" },
      { internalType: "uint256", name: "deadline", type: "uint256" },
    ],
    name: "compound",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

export const quoterV2Abi = [
  {
    inputs: [
      {
        components: [
          { internalType: "address", name: "tokenIn", type: "address" },
          { internalType: "address", name: "tokenOut", type: "address" },
          { internalType: "uint256", name: "amountIn", type: "uint256" },
          { internalType: "uint24", name: "fee", type: "uint24" },
          { internalType: "uint160", name: "sqrtPriceLimitX96", type: "uint160" },
        ],
        internalType: "struct IQuoterV2.QuoteExactInputSingleParams",
        name: "params",
        type: "tuple",
      },
    ],
    name: "quoteExactInputSingle",
    outputs: [
      { internalType: "uint256", name: "amountOut", type: "uint256" },
      { internalType: "uint160", name: "sqrtPriceX96After", type: "uint160" },
      { internalType: "uint32", name: "initializedTicksCrossed", type: "uint32" },
      { internalType: "uint256", name: "gasEstimate", type: "uint256" },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

export const autoPounderViewAbi = [
  {
    inputs: [],
    name: "getRewardTokenCount",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    name: "rewardTokens",
    outputs: [{ internalType: "address", name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

export const erc20Abi = [
  {
    inputs: [{ internalType: "address", name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "decimals",
    outputs: [{ internalType: "uint8", name: "", type: "uint8" }],
    stateMutability: "view",
    type: "function",
  },
] as const;
