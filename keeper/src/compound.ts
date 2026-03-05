/**
 * Fetch merkle proofs from EigenLayer Sidecar and call compound() on CAPAutoPounder.
 *
 * Usage:
 *   ETH_MAINNET_RPC_URL=... \
 *   PRIVATE_KEY=... \
 *   AUTO_POUNDER_ADDRESS=0x... \
 *   npx tsx src/compound.ts [--dry-run] [--realize-interest]
 *
 * Environment:
 *   ETH_MAINNET_RPC_URL   — Ethereum mainnet RPC endpoint
 *   PRIVATE_KEY            — Private key of COMPOUNDER_ROLE holder
 *   AUTO_POUNDER_ADDRESS   — Deployed CAPAutoPounder contract address
 *   MIN_WETH_THRESHOLD     — Minimum WETH (in ETH) to justify compounding (default: 0.01)
 */
import {
  createPublicClient,
  createWalletClient,
  http,
  formatEther,
  parseEther,
} from "viem";
import { mainnet } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { ADDRESSES, KNOWN_TOKENS } from "./config.js";
import {
  tokenStakingNodesManagerAbi,
  rewardsCoordinatorAbi,
  autoPounderAbi,
} from "./abi.js";
import { getLifetimeRewards, getClaimProof, type ClaimProof } from "./sidecar.js";

// --- Parse args ---
const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const realizeInterest = args.includes("--realize-interest");

// --- Validate env ---
const rpcUrl = process.env.ETH_MAINNET_RPC_URL;
const privateKey = process.env.PRIVATE_KEY as `0x${string}` | undefined;
const autoPounderAddress = process.env.AUTO_POUNDER_ADDRESS as `0x${string}` | undefined;
const minWethThreshold = parseEther(process.env.MIN_WETH_THRESHOLD ?? "0.01");

if (!rpcUrl) {
  console.error("ETH_MAINNET_RPC_URL is required");
  process.exit(1);
}
if (!autoPounderAddress) {
  console.error("AUTO_POUNDER_ADDRESS is required");
  process.exit(1);
}
if (!dryRun && !privateKey) {
  console.error("PRIVATE_KEY is required (or use --dry-run)");
  process.exit(1);
}

const publicClient = createPublicClient({
  chain: mainnet,
  transport: http(rpcUrl),
});

async function main() {
  console.log(`CAPAutoPounder: ${autoPounderAddress}`);
  console.log(`Mode: ${dryRun ? "DRY RUN" : "LIVE"}`);
  console.log(`Realize interest: ${realizeInterest}\n`);

  // 1. Get staking nodes
  const nodes = await publicClient.readContract({
    address: ADDRESSES.tokenStakingNodesManager,
    abi: tokenStakingNodesManagerAbi,
    functionName: "getAllNodes",
  });
  console.log(`Found ${nodes.length} staking nodes`);

  // 2. For each node, check unclaimed rewards and build claim proofs
  const claims: any[] = [];
  let hasUnclaimed = false;

  for (const node of nodes) {
    const rewards = await getLifetimeRewards(node);
    const unclaimedTokens: string[] = [];

    for (const reward of rewards) {
      const tokenAddr = reward.token.toLowerCase();
      const lifetime = BigInt(reward.amount);

      const claimed = await publicClient.readContract({
        address: ADDRESSES.rewardsCoordinator,
        abi: rewardsCoordinatorAbi,
        functionName: "cumulativeClaimed",
        args: [node as `0x${string}`, tokenAddr as `0x${string}`],
      });

      if (lifetime > claimed) {
        unclaimedTokens.push(tokenAddr);
        hasUnclaimed = true;
        const symbol = KNOWN_TOKENS[tokenAddr] ?? tokenAddr;
        const decimals = symbol === "USDC" ? 6 : 18;
        const unclaimed = lifetime - claimed;
        console.log(`  ${node} — ${symbol}: ${formatEther(unclaimed)} unclaimed`);
      }
    }

    // Fetch claim proof for this node if there are unclaimed tokens
    if (unclaimedTokens.length > 0) {
      const proof = await getClaimProof(node, unclaimedTokens);
      if (proof) {
        claims.push(formatClaimForContract(proof));
      }
    }
  }

  if (!hasUnclaimed) {
    console.log("\nNo unclaimed rewards found. Nothing to compound.");
    return;
  }

  console.log(`\nBuilt ${claims.length} claim proofs`);

  // 3. Estimate expected WETH output
  // For safety, we use minWethOutput = 0 in initial version.
  // TODO: Integrate price feeds for proper slippage calculation.
  const minWethOutput = 0n;
  console.log(`minWethOutput: ${formatEther(minWethOutput)} ETH`);

  if (dryRun) {
    console.log("\n--- DRY RUN — not sending transaction ---");
    console.log(`Would call compound() with:`);
    console.log(`  claims: ${claims.length} proofs`);
    console.log(`  shouldRealizeInterest: ${realizeInterest}`);
    console.log(`  minWethOutput: ${minWethOutput}`);
    return;
  }

  // 4. Send transaction
  const account = privateKeyToAccount(privateKey!);
  const walletClient = createWalletClient({
    account,
    chain: mainnet,
    transport: http(rpcUrl),
  });

  console.log(`\nSending compound() from ${account.address}...`);

  const hash = await walletClient.writeContract({
    address: autoPounderAddress!,
    abi: autoPounderAbi,
    functionName: "compound",
    args: [claims, realizeInterest, minWethOutput],
  });

  console.log(`Transaction sent: ${hash}`);

  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  console.log(`Confirmed in block ${receipt.blockNumber} (gas: ${receipt.gasUsed})`);
}

/**
 * Format a sidecar ClaimProof into the struct expected by the contract ABI.
 */
function formatClaimForContract(proof: ClaimProof) {
  return {
    rootIndex: proof.rootIndex,
    earnerIndex: proof.earnerIndex,
    earnerTreeProof: proof.earnerTreeProof as `0x${string}`,
    earnerLeaf: {
      earner: proof.earnerLeaf.earner as `0x${string}`,
      earnerTokenRoot: proof.earnerLeaf.earnerTokenRoot as `0x${string}`,
    },
    tokenIndices: proof.tokenIndices,
    tokenTreeProofs: proof.tokenTreeProofs.map((p) => p as `0x${string}`),
    tokenLeaves: proof.tokenLeaves.map((l) => ({
      token: l.token as `0x${string}`,
      cumulativeEarnings: BigInt(l.cumulativeEarnings),
    })),
  };
}

main().catch((err) => {
  console.error("Compound failed:", err);
  process.exit(1);
});
