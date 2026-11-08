import { Component, useEffect, useMemo, useState, type ReactNode } from "react";
import { WagmiProvider, useAccount, useChainId, useConnect, useDisconnect, useReadContract, useSwitchChain } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { formatUnits } from "viem";
import { loadAddresses, makeConfig, isFork, type Addresses } from "./config";
import { erc20Abi } from "./abiWrite";
import { Gate } from "./Gate";
import { Markets } from "./pages/Markets";
import { MyVault } from "./pages/MyVault";
import { Ledger } from "./pages/Ledger";
import { System } from "./pages/System";
import { About } from "./pages/About";
import { States } from "./pages/States";

const qc = new QueryClient();

const ROUTES = [
  { id: "markets", label: "Markets" },
  { id: "vault", label: "My vault" },
  { id: "ledger", label: "Gap ledger" },
  { id: "system", label: "System" },
  { id: "about", label: "How it works" },
] as const;

function useRoute() {
  const get = () => window.location.hash.replace(/^#\/?/, "") || "markets";
  const [r, setR] = useState(get);
  useEffect(() => { const f = () => setR(get()); window.addEventListener("hashchange", f); return () => window.removeEventListener("hashchange", f); }, []);
  return r;
}

class Boundary extends Component<{ children: ReactNode }, { err: string | null }> {
  state = { err: null as string | null };
  static getDerivedStateFromError(e: Error) { return { err: e.message }; }
  render() { return this.state.err ? <p className="banner fault">Something went wrong rendering this page: {this.state.err}</p> : this.props.children; }
}

export function App() {
  const [addr, setAddr] = useState<Addresses | null>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => { loadAddresses().then(setAddr).catch((e) => setErr(String(e.message ?? e))); }, []);
  const config = useMemo(() => (addr ? makeConfig(addr) : null), [addr]);
  return (
    <Gate>
      {err && <p className="banner fault page">{err}</p>}
      {addr && config && (
        <WagmiProvider config={config}><QueryClientProvider client={qc}><Shell addr={addr} /></QueryClientProvider></WagmiProvider>
      )}
    </Gate>
  );
}

function Shell({ addr }: { addr: Addresses }) {
  const route = useRoute();
  const fork = isFork(addr);
  const nav = fork ? [...ROUTES, { id: "states", label: "All states" }] : ROUTES;
  return (
    <>
      <header className="top">
        <div className="bar">
          <a className="brand" href="#/markets">Own<span>Index</span></a>
          <nav>{nav.map((n) => <a key={n.id} href={`#/${n.id}`} className={route === n.id ? "on" : ""}>{n.label}</a>)}</nav>
          <Wallet addr={addr} />
        </div>
        {fork && <div className="forkbanner">Local fork of Base. Nothing here is on mainnet and the funds are test funds.</div>}
      </header>
      <ChainGuard addr={addr} />
      <main className="page">
        <Boundary key={route}>
          {route === "markets" && <Markets addr={addr} />}
          {route === "vault" && <MyVault addr={addr} />}
          {route === "ledger" && <Ledger addr={addr} />}
          {route === "system" && <System addr={addr} />}
          {route === "about" && <About />}
          {route === "states" && fork && <States />}
        </Boundary>
      </main>
      <Footer />
    </>
  );
}

function Wallet({ addr }: { addr: Addresses }) {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const usdc = useReadContract({ address: addr.usdc, abi: erc20Abi, functionName: "balanceOf", args: [address!], query: { enabled: !!address, refetchInterval: 5000 } }).data;
  if (!isConnected) {
    return <button className="primary" disabled={isPending} onClick={() => connect({ connector: connectors[0] })}>{isFork(addr) ? "Connect dev account" : "Connect wallet"}</button>;
  }
  return (
    <div className="wallet">
      <span className="addr">{address!.slice(0, 6)}…{address!.slice(-4)}</span>
      {usdc !== undefined && <span className="bal">${Number(formatUnits(usdc, 6)).toLocaleString(undefined, { maximumFractionDigits: 0 })} USDC</span>}
      <button className="ghost" onClick={() => disconnect()}>Disconnect</button>
    </div>
  );
}

/** A browser wallet on another network would send transactions to the wrong chain: say so and offer the switch. */
function ChainGuard({ addr }: { addr: Addresses }) {
  const { isConnected } = useAccount();
  const chainId = useChainId();
  const { switchChain } = useSwitchChain();
  const { connector } = useAccount();
  const walletChain = useReadWalletChain();
  if (!isConnected || walletChain === null || walletChain === addr.chainId) return null;
  return (
    <div className="chainwarn">Your wallet is on another network (chain {walletChain}). Switch to Base before sending anything.{" "}
      <button onClick={() => switchChain({ chainId: addr.chainId })}>Switch to Base</button>
      <span hidden>{chainId}{connector?.id}</span>
    </div>
  );
}

function useReadWalletChain(): number | null {
  const { connector, isConnected } = useAccount();
  const [id, setId] = useState<number | null>(null);
  useEffect(() => {
    if (!isConnected || !connector) { setId(null); return; }
    let live = true;
    connector.getChainId().then((c) => { if (live) setId(c); }).catch(() => { if (live) setId(null); });
    const onChange = (d: { chainId?: number }) => { if (d.chainId) setId(d.chainId); };
    connector.emitter?.on("change", onChange);
    return () => { live = false; connector.emitter?.off("change", onChange); };
  }, [connector, isConnected]);
  return id;
}

function Footer() {
  return (
    <footer>
      <p>
        Own Index is software that lets you hold your own tokenized-equity positions in a vault you control. It is not an
        investment product, offers no advice or recommendation, pools no funds, issues no token or share, and manages
        nothing on your behalf. You can withdraw everything in kind at any time. Tokenized stocks may not be available
        to you depending on where you live; you are responsible for checking whether you are eligible. WeekendMark is
        reference data and is explicitly not a liquidation oracle. Smart contracts can fail and these ones are not
        audited. Use at your own risk.
      </p>
    </footer>
  );
}
