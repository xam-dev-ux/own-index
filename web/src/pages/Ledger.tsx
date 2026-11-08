import { useState } from "react";
import { useAccount, usePublicClient, useReadContract, useReadContracts, useWriteContract } from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { formatUnits } from "viem";
import type { Addresses } from "../config";
import { BUILDER_SUFFIX } from "../config";
import { oracleSystemAbi } from "../abiSystem";
import { TOKENS } from "../tokens";
import { explainRevert } from "../errors";
import { Card, Empty, fmtAge, fmtDate } from "../ui";

const px = (v: bigint) => `$${Number(formatUnits(v, 8)).toFixed(2)}`;
const bps = (v: bigint | number) => `${Number(v) > 0 ? "+" : ""}${Number(v)} bps`;

export function Ledger({ addr }: { addr: Addresses }) {
  const [sel, setSel] = useState(0);
  const stats = useReadContracts({
    contracts: TOKENS.map((t) => ({ address: addr.oracle, abi: oracleSystemAbi, functionName: "gapStats", args: [t.address] }) as const),
    query: { refetchInterval: 15000 },
  });
  const count = Number((stats.data?.[sel]?.result as readonly bigint[] | undefined)?.[3] ?? 0n);
  const gaps = useReadContract({
    address: addr.oracle, abi: oracleSystemAbi, functionName: "gapsPage",
    args: [TOKENS[sel].address, BigInt(Math.max(0, count - 10)), 10n], query: { enabled: count > 0 },
  }).data;
  return (
    <>
      <div className="intro">
        <h1>The weekend gap ledger</h1>
        <p>Every time a market reopens, this ledger records how far the price moved between the last print before the close and the first print after the reopen. Anyone can add to it. It is a public, timestamped record of what weekends and holidays do to each stock.</p>
      </div>
      <Card title="Gap statistics by token" aside="mean and largest absolute gap">
        <div className="tablewrap">
          <table className="stack">
            <thead><tr><th>Token</th><th className="num">Gaps recorded</th><th className="num">Mean |gap|</th><th className="num">Largest |gap|</th><th className="num">Mean closure</th></tr></thead>
            <tbody>
              {TOKENS.map((t, i) => {
                const r = stats.data?.[i]?.result as readonly bigint[] | undefined;
                return (
                  <tr key={t.symbol} className={i === sel ? "sel" : ""} onClick={() => setSel(i)} style={{ cursor: "pointer" }}>
                    <td data-l="Token"><strong>{t.symbol}</strong></td>
                    <td data-l="Gaps recorded" className="num">{r ? r[3].toString() : "…"}</td>
                    <td data-l="Mean |gap|" className="num">{r && r[3] > 0n ? `${r[0]} bps` : "—"}</td>
                    <td data-l="Largest |gap|" className="num">{r && r[3] > 0n ? `${r[1]} bps` : "—"}</td>
                    <td data-l="Mean closure" className="num">{r && r[3] > 0n ? fmtAge(Number(r[2])) : "—"}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </Card>
      <Card title={`${TOKENS[sel].symbol}: latest gaps`} aside="select a row above to change token">
        {count === 0 ? (
          <Empty>No gaps recorded for {TOKENS[sel].symbol} yet. A gap is recorded when someone takes a snapshot after a closed market has reopened.</Empty>
        ) : !gaps ? <Empty>Loading…</Empty> : (
          <div className="tablewrap">
            <table className="stack">
              <thead><tr><th>Closed at</th><th className="num">Close print</th><th>Reopened at</th><th className="num">Reopen print</th><th className="num">Gap</th><th className="num">Closed for</th></tr></thead>
              <tbody>
                {[...gaps].reverse().map((g) => (
                  <tr key={g.observedBlock.toString()}>
                    <td data-l="Closed at">{fmtDate(g.closePrintAt)}</td><td data-l="Close print" className="num">{px(g.closePrice)}</td>
                    <td data-l="Reopened at">{fmtDate(g.reopenPrintAt)}</td><td data-l="Reopen print" className="num">{px(g.reopenPrice)}</td>
                    <td data-l="Gap" className="num"><strong>{bps(g.gapBps)}</strong></td><td data-l="Closed for" className="num">{fmtAge(g.closureSecs)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="note">Print times come from the feed and have one-second resolution. The time a gap was observed uses the chain's millisecond clock. If several prints land before a snapshot, the latest is the one recorded.</p>
      </Card>
      <Snapshot addr={addr} />
    </>
  );
}

function Snapshot({ addr }: { addr: Addresses }) {
  const { address } = useAccount();
  const client = usePublicClient();
  const qc = useQueryClient();
  const { writeContractAsync } = useWriteContract();
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  async function run() {
    setBusy(true); setMsg(null);
    try {
      const p = { address: addr.oracle, abi: oracleSystemAbi, functionName: "snapshotAll" } as const;
      const est = await client!.estimateContractGas({ ...p, account: address! });
      const hash = await writeContractAsync({ ...p, gas: (est * 13n) / 10n, ...(BUILDER_SUFFIX ? { dataSuffix: BUILDER_SUFFIX } : {}) } as never);
      await client!.waitForTransactionReceipt({ hash });
      await qc.invalidateQueries();
      setMsg({ ok: true, text: `Snapshot recorded (${hash.slice(0, 10)}…). A gap appears only for tokens whose market reopened since the last one.` });
    } catch (e) { setMsg({ ok: false, text: explainRevert(e) }); }
    finally { setBusy(false); }
  }
  return (
    <Card title="Take a snapshot" aside="open to everyone">
      <p className="note">Taking a snapshot reads every token's verdict and records a gap if its market has just reopened. It has no owner and moves no funds. You pay the gas.</p>
      <button disabled={busy || !address} onClick={run}>{address ? "Record snapshot for all tokens" : "Connect a wallet to record a snapshot"}</button>
      {msg && <p className={`banner ${msg.ok ? "fresh" : "expected"}`}>{msg.text}</p>}
    </Card>
  );
}
