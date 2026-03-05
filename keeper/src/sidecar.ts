import { SIDECAR_BASE_URL } from "./config.js";

export interface TokenReward {
  token: string;
  amount: string; // raw wei string
}

export interface EarnerReward {
  earner: string;
  tokens: TokenReward[];
}

export interface ClaimProof {
  earnerIndex: number;
  earnerTreeProof: string;
  earnerLeaf: {
    earner: string;
    earnerTokenRoot: string;
  };
  tokenIndices: number[];
  tokenTreeProofs: string[];
  tokenLeaves: Array<{
    token: string;
    cumulativeEarnings: string;
  }>;
  rootIndex: number;
}

/**
 * Fetch lifetime rewards for a given earner from EigenLayer Sidecar API.
 */
export async function getLifetimeRewards(earner: string): Promise<TokenReward[]> {
  const url = `${SIDECAR_BASE_URL}/rewards/v1/earners/${earner}/lifetime-rewards`;
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Sidecar API error for ${earner}: ${res.status} ${res.statusText}`);
  }
  const data = await res.json();

  // API returns array of { token, amount }
  if (!Array.isArray(data)) return [];
  return data.map((r: any) => ({
    token: r.token?.toLowerCase() ?? r.Token?.toLowerCase(),
    amount: r.amount ?? r.Amount ?? "0",
  }));
}

/**
 * Fetch a claim proof for a given earner and list of tokens.
 */
export async function getClaimProof(
  earner: string,
  tokens: string[]
): Promise<ClaimProof | null> {
  const url = `${SIDECAR_BASE_URL}/rewards/v1/claim-proof`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ earnerAddress: earner, tokens }),
  });

  if (!res.ok) {
    console.error(`Failed to get claim proof for ${earner}: ${res.status}`);
    return null;
  }

  return res.json();
}
