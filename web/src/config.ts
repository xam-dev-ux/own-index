import { createConfig, http } from "wagmi";
import { defineChain } from "viem";

export interface Addresses {
  chainId: number; rpc: string; forkBlock: number; owner: `0x${string}`;
  oracle: `0x${string}`; adapter: `0x${string}`; factory: `0x${string}`; vault: `0x${string}`; usdc: `0x${string}`;
}

/** Addresses are configuration, never code: public/addresses.json is written by `make setup-fork` (fork) or by the deploy (mainnet). */
export async function loadAddresses(): Promise<Addresses> {
  const r = await fetch("/addresses.json", { cache: "no-store" });
  if (!r.ok) throw new Error("addresses.json not found. Run `make setup-fork`, then restart `npm run dev`.");
  return r.json();
}

export function makeConfig(a: Addresses) {
  const chain = defineChain({
    id: a.chainId, name: a.rpc.includes("127.0.0.1") ? "Base (local fork)" : "Base",
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 }, rpcUrls: { default: { http: [a.rpc] } },
  });
  return createConfig({ chains: [chain], transports: { [chain.id]: http(a.rpc) } });
}
