import { createConfig, http } from "wagmi";
import { injected, mock } from "wagmi/connectors";
import { defineChain } from "viem";

export interface Addresses {
  chainId: number; rpc: string; forkBlock: number; owner?: `0x${string}`; // block of the first deploy; refusal logs are read from the next block
  oracle: `0x${string}`; adapter: `0x${string}`; factory: `0x${string}`; vault?: `0x${string}`; usdc: `0x${string}`; // owner and vault exist only on the local fork
}

export const isFork = (a: Addresses) => a.rpc.includes("127.0.0.1") || a.rpc.includes("localhost");

/** Optional ERC-8021 Builder Code suffix, appended by the client to every write. Unset until the code is registered. */
export const BUILDER_SUFFIX = (import.meta.env.VITE_BUILDER_CODE_SUFFIX as `0x${string}` | undefined) || undefined;

/** Addresses are configuration, never code: public/addresses.json is copied from the fork (`npm run dev`) or from addresses.mainnet.json (`npm run build`). */
export async function loadAddresses(): Promise<Addresses> {
  const r = await fetch("/addresses.json", { cache: "no-store" });
  if (!r.ok) throw new Error("addresses.json not found. Run `make setup-fork`, then restart `npm run dev`.");
  return r.json();
}

export function makeConfig(a: Addresses) {
  const chain = defineChain({
    id: a.chainId, name: isFork(a) ? "Base (local fork)" : "Base",
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 }, rpcUrls: { default: { http: [a.rpc] } },
  });
  // A local fork is never wired to a browser wallet that shares the real chain id: it uses the impersonated dev account.
  const connectors = isFork(a) ? [mock({ accounts: [a.owner!] })] : [injected()];
  return createConfig({ chains: [chain], connectors, transports: { [chain.id]: http(a.rpc) } });
}
