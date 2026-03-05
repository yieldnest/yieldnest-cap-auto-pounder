/**
 * Check unclaimed rewards across all staking nodes.
 * Usage: npx tsx src/check-rewards.ts
 */
import { createPublicClient, http, formatUnits } from "viem";
import { mainnet } from "viem/chains";
import { ADDRESSES, KNOWN_TOKENS } from "./config.js";
import { tokenStakingNodesManagerAbi, rewardsCoordinatorAbi } from "./abi.js";
import { getLifetimeRewards } from "./sidecar.js";

const rpcUrl = process.env.ETH_MAINNET_RPC_URL;
if (!rpcUrl) {
  console.error("ETH_MAINNET_RPC_URL is required");
  process.exit(1);
}

const client = createPublicClient({
  chain: mainnet,
  transport: http(rpcUrl),
});

async function main() {
  // 1. Get all staking nodes from on-chain manager
  const nodes = await client.readContract({
    address: ADDRESSES.tokenStakingNodesManager,
    abi: tokenStakingNodesManagerAbi,
    functionName: "getAllNodes",
  });

  console.log(`Found ${nodes.length} staking nodes\n`);

  // 2. For each node, check lifetime rewards and subtract claimed
  const allUnclaimed: Record<string, bigint> = {};

  for (const node of nodes) {
    console.log(`--- Node: ${node} ---`);
    const rewards = await getLifetimeRewards(node);

    for (const reward of rewards) {
      const tokenAddr = reward.token.toLowerCase();
      const symbol = KNOWN_TOKENS[tokenAddr] ?? tokenAddr;
      const lifetime = BigInt(reward.amount);

      // Get cumulative claimed amount
      const claimed = await client.readContract({
        address: ADDRESSES.rewardsCoordinator,
        abi: rewardsCoordinatorAbi,
        functionName: "cumulativeClaimed",
        args: [node as `0x${string}`, tokenAddr as `0x${string}`],
      });

      const unclaimed = lifetime - claimed;
      if (unclaimed > 0n) {
        allUnclaimed[tokenAddr] = (allUnclaimed[tokenAddr] ?? 0n) + unclaimed;
        const decimals = symbol === "USDC" ? 6 : 18;
        console.log(`  ${symbol}: ${formatUnits(unclaimed, decimals)} unclaimed`);
      }
    }
  }

  console.log("\n=== Total Unclaimed ===");
  for (const [token, amount] of Object.entries(allUnclaimed)) {
    const symbol = KNOWN_TOKENS[token] ?? token;
    const decimals = symbol === "USDC" ? 6 : 18;
    console.log(`  ${symbol}: ${formatUnits(amount, decimals)}`);
  }
}

main().catch(console.error);
