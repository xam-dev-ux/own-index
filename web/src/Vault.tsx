import { useEffect, useState } from "react";
import { useReadContracts, usePublicClient } from "wagmi";
import { formatUnits } from "viem";
import type { Addresses } from "./config";
import { vaultAbi, refusedEvent } from "./abi";
import { TOKENS } from "./tokens";
import { refusalView, type Tone } from "./verdict";

const ZERO = "0x0000000000000000000000000000000000000000";
const sym = (a: string) => TOKENS.find((t) => t.address.toLowerCase() === a.toLowerCase())?.symbol ?? `${a.slice(0, 6)}…`;
const pct = (bps: number | bigint) => `${(Number(bps) / 100).toFixed(2)}%`;
const usd = (v: bigint) => `$${Number(formatUnits(v, 6)).toLocaleString(undefined, { maximumFractionDigits: 2 })}`;

function Pill({ tone, children }: { tone: Tone; children: React.ReactNode }) {
  return <span className={`pill ${tone}`}>{children}</span>;
}

export function Vault({ addr }: { addr: Addresses }) {
  const v = { address: addr.vault, abi: vaultAbi } as const;
  const { data } = useReadContracts({
    contracts: [
      { ...v, functionName: "components" },
      { ...v, functionName: "currentWeights" },
      { ...v, functionName: "totalValue" },
      { ...v, functionName: "rules" },
      { ...v, functionName: "rebalanceStatus" },
      { ...v, functionName: "refusalCount" },
    ],
    query: { refetchInterval: 5000 },
  });
  if (!data || data.some((d) => d.status !== "success")) return <p>Reading the vault…</p>;
  const comps = data[0].result as readonly { token: `0x${string}`; targetWeightBps: number }[];
  const weights = data[1].result as readonly number[];
  const [value, allFresh] = data[2].result as readonly [bigint, boolean];
  const [driftBps, minInt, slipBps] = data[3].result as readonly [number, number, number];
  const [possible, refusals, , maxDrift] = data[4].result as readonly [boolean, readonly { kind: number; token: `0x${string}`; cause: number }[], bigint, number];
  const count = Number(data[5].result as bigint);
  return (
    <section>
      <h2>Your vault</h2>
      <p className="legend">
        <strong>{usd(value)}</strong>{" "}
        {allFresh ? <Pill tone="fresh">all prices fresh</Pill> : <Pill tone="expected">components without a fresh price are not counted</Pill>}
      </p>
      <table>
        <thead><tr><th>Token</th><th className="num">Target</th><th className="num">Current</th></tr></thead>
        <tbody>
          {comps.map((c, i) => (
            <tr key={c.token}><td><strong>{sym(c.token)}</strong></td><td className="num">{pct(c.targetWeightBps)}</td><td className="num">{pct(weights[i])}</td></tr>
          ))}
        </tbody>
      </table>
      <h3>Can it rebalance now?</h3>
      {possible ? (
        <p><Pill tone="fresh">Yes</Pill> Largest drift {pct(maxDrift)}.</p>
      ) : (
        <ul className="refusals">
          {refusals.map((x, i) => {
            const r = refusalView(x.kind, x.cause);
            return (
              <li key={i}>
                <Pill tone={r.tone}>{r.label}</Pill>
                {x.token !== ZERO && <strong> {sym(x.token)}</strong>} <span className="why">{r.explain}</span>
              </li>
            );
          })}
        </ul>
      )}
      <p className="note">Rules: rebalance when a weight drifts {pct(driftBps)}; at least {minInt}s between rebalances; max slippage {pct(slipBps)} against oracle prices.</p>
      <RefusalLog addr={addr} count={count} />
    </section>
  );
}

interface Row { id: bigint; kind: number; token: `0x${string}`; cause: number; ms: bigint; block: bigint }

function RefusalLog({ addr, count }: { addr: Addresses; count: number }) {
  const client = usePublicClient();
  const [rows, setRows] = useState<Row[] | null>(null);
  useEffect(() => {
    if (!client) return;
    client
      .getLogs({ address: addr.vault, event: refusedEvent, fromBlock: BigInt(addr.forkBlock) + 1n })
      .then((logs) =>
        setRows(logs.map((l) => ({ id: l.args.refusalId!, kind: l.args.kind!, token: l.args.token!, cause: l.args.cause!, ms: l.args.timestampMs!, block: l.blockNumber })).reverse()),
      )
      .catch(() => setRows([]));
  }, [client, addr, count]);
  return (
    <>
      <h3>Recorded refusals <span className="why">({count} on chain)</span></h3>
      <p className="note">A refused trade that reverts leaves no log. These are the refusals the vault chose to record with <code>tryRebalance</code>.</p>
      {rows === null ? <p>Loading…</p> : rows.length === 0 ? <p className="note">None found.</p> : (
        <table>
          <thead><tr><th>#</th><th>Reason</th><th>Token</th><th>When (UTC)</th></tr></thead>
          <tbody>
            {rows.map((x) => {
              const r = refusalView(x.kind, x.cause);
              return (
                <tr key={`${x.block}-${x.id}-${x.token}`}>
                  <td>{x.id.toString()}</td>
                  <td><Pill tone={r.tone}>{r.label}</Pill></td>
                  <td>{x.token === ZERO ? "—" : sym(x.token)}</td>
                  <td>{new Date(Number(x.ms)).toISOString().replace("T", " ").slice(0, 19)}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </>
  );
}
