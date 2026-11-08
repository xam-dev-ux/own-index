import { useReadContract } from "wagmi";
import { formatUnits } from "viem";
import type { Addresses } from "../config";
import { oracleAbi, DIVERGENCE } from "../abi";
import { TOKENS } from "../tokens";
import { verdictOf, type Tone } from "../verdict";
import { Card, Empty, Pill, Stat, fmtAge } from "../ui";

export function Markets({ addr }: { addr: Addresses }) {
  const { data, error, isLoading } = useReadContract({
    address: addr.oracle, abi: oracleAbi, functionName: "marksOf",
    args: [TOKENS.map((t) => t.address)], query: { refetchInterval: 5000 },
  });
  if (isLoading) return <Card><Empty>Reading the oracle…</Empty></Card>;
  if (error || !data) return <Card><p className="banner fault">Could not read the oracle: {error?.message}</p></Card>;

  const verdicts = data.map((m) => verdictOf(m.session, m.cause));
  const count = (t: Tone) => verdicts.filter((v) => v.tone === t).length;
  return (
    <>
      <div className="intro">
        <h1>Is the price usable right now?</h1>
        <p>Each tokenized stock has a verdict that says whether its price may be used for a decision, and why. A closed market is a normal state. A silent feed during trading hours is not. Own Index shows them differently, and the vaults refuse to trade against anything that is not fresh.</p>
      </div>
      <div className="stats">
        <Stat label="fresh" value={count("fresh")} tone="fresh" />
        <Stat label="closed (normal)" value={count("closed")} tone="closed" />
        <Stat label="awaiting first print" value={count("expected")} tone="expected" />
        <Stat label="paused" value={count("paused")} tone="paused" />
        <Stat label="fault" value={count("fault")} tone="fault" />
      </div>
      <Card title="Session verdicts" aside="refreshes every 5 s">
        <div className="tablewrap">
          <table className="stack">
            <thead><tr><th>Token</th><th>Verdict</th><th className="num">Price</th><th className="num">Last print</th><th>24/7 feed comparison</th></tr></thead>
            <tbody>
              {TOKENS.map((t, i) => {
                const m = data[i]; const v = verdicts[i];
                return (
                  <tr key={t.symbol}>
                    <td data-l="Token"><strong>{t.symbol}</strong></td>
                    <td data-l="Verdict"><Pill tone={v.tone}>{v.label}</Pill><div className="why">{v.explain}</div></td>
                    <td data-l="Price" className="num">{m.price > 0n ? `$${Number(formatUnits(m.price, 8)).toFixed(2)}` : "—"}</td>
                    <td data-l="Last print" className="num">{m.stalenessSecs < 4_000_000 ? `${fmtAge(m.stalenessSecs)} ago` : "—"}</td>
                    <td data-l="24/7 comparison">{DIVERGENCE[m.divergenceStatus]?.toLowerCase().replace(/_/g, " ")}{m.divergenceStatus === 5 ? ` · ${Number(m.divergenceBps)} bps` : ""}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <p className="note">Prices are the primary Chainlink feed and already include the corporate-action multiplier. The 24/7 comparison is reported alongside and never replaces the primary price. This is reference data, not a liquidation oracle.</p>
      </Card>
    </>
  );
}
