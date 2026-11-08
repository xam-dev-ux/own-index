import { useEffect, useMemo, useState } from "react";
import { WagmiProvider, useReadContract } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { formatUnits } from "viem";
import { loadAddresses, makeConfig, type Addresses } from "./config";
import { oracleAbi, DIVERGENCE } from "./abi";
import { TOKENS } from "./tokens";
import { Vault } from "./Vault";
import { verdictOf, type Tone } from "./verdict";

const qc = new QueryClient();

export function App() {
  const [addr, setAddr] = useState<Addresses | null>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => { loadAddresses().then(setAddr).catch((e) => setErr(String(e.message ?? e))); }, []);
  const config = useMemo(() => (addr ? makeConfig(addr) : null), [addr]);
  return (
    <div className="page">
      <header><h1>Own Index</h1><p className="sub">Self-custodial index vaults that refuse to trade against prices that are not fresh.</p></header>
      <main>
        {err && <p className="banner fault">{err}</p>}
        {addr && config && (
          <WagmiProvider config={config}><QueryClientProvider client={qc}><Marks addr={addr} /><Vault addr={addr} /></QueryClientProvider></WagmiProvider>
        )}
      </main>
      <Footer />
    </div>
  );
}

function Marks({ addr }: { addr: Addresses }) {
  const { data, error, isLoading } = useReadContract({
    address: addr.oracle, abi: oracleAbi, functionName: "marksOf",
    args: [TOKENS.map((t) => t.address)], query: { refetchInterval: 5000 },
  });
  if (isLoading) return <p>Reading the oracle…</p>;
  if (error || !data) return <p className="banner fault">Could not read the oracle: {error?.message}</p>;

  const verdicts = data.map((m) => verdictOf(m.session, m.cause));
  const count = (t: Tone) => verdicts.filter((v) => v.tone === t).length;
  return (
    <section>
      <h2>Session verdicts</h2>
      <p className="legend">
        <Pill tone="fresh">{count("fresh")} fresh</Pill>
        <Pill tone="closed">{count("closed")} closed (normal)</Pill>
        <Pill tone="expected">{count("expected")} awaiting first print</Pill>
        <Pill tone="paused">{count("paused")} paused</Pill>
        <Pill tone="fault">{count("fault")} fault</Pill>
      </p>
      <table>
        <thead><tr><th>Token</th><th>Verdict</th><th className="num">Price</th><th className="num">Age</th><th>24/7 comparison</th></tr></thead>
        <tbody>
          {TOKENS.map((t, i) => {
            const m = data[i]; const v = verdicts[i];
            return (
              <tr key={t.symbol}>
                <td><strong>{t.symbol}</strong></td>
                <td title={v.explain}><Pill tone={v.tone}>{v.label}</Pill><div className="why">{v.explain}</div></td>
                <td className="num">{m.price > 0n ? `$${Number(formatUnits(m.price, 8)).toFixed(2)}` : "—"}</td>
                <td className="num">{m.stalenessSecs < 100000 ? fmtAge(m.stalenessSecs) : "—"}</td>
                <td>{DIVERGENCE[m.divergenceStatus]?.toLowerCase().replace(/_/g, " ")}{m.divergenceStatus === 5 ? ` · ${Number(m.divergenceBps)} bps` : ""}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
      <p className="note">Prices are the primary Chainlink feed, already including the corporate-action multiplier. The 24/7 comparison is reported alongside and never replaces the primary price. This is reference data, not a liquidation oracle.</p>
    </section>
  );
}

function fmtAge(s: number) { return s < 90 ? `${s}s` : s < 5400 ? `${Math.round(s / 60)}m` : `${(s / 3600).toFixed(1)}h`; }
function Pill({ tone, children }: { tone: Tone; children: React.ReactNode }) { return <span className={`pill ${tone}`}>{children}</span>; }

function Footer() {
  return (
    <footer>
      <p>
        Own Index is software that lets you hold your own tokenized-equity positions in a vault you control. It is not an
        investment product, offers no advice or recommendation, pools no funds, issues no token or share, and manages
        nothing on your behalf. You can withdraw everything in kind at any time. Tokenized stocks may not be available
        to you depending on where you live; you are responsible for checking whether you are eligible. WeekendMark is
        reference data and is explicitly not a liquidation oracle. Smart contracts can fail. Use at your own risk.
      </p>
    </footer>
  );
}
