import { useReadContract, useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import { isFork, type Addresses } from "../config";
import { oracleSystemAbi, factorySystemAbi } from "../abiSystem";
import { factoryAbi } from "../abiWrite";
import { TOKENS } from "../tokens";
import { Card, Empty, Pill, basescan, fmtAge, fmtDate, fmtWeekOffset } from "../ui";

export function System({ addr }: { addr: Addresses }) {
  const o = { address: addr.oracle, abi: oracleSystemAbi } as const;
  const cfg = useReadContracts({
    contracts: [
      { ...o, functionName: "weekOpenOffset" }, { ...o, functionName: "weekCloseOffset" }, { ...o, functionName: "heartbeatSecs" },
      { ...o, functionName: "heartbeatMarginSecs" }, { ...o, functionName: "comparisonWindowSecs" }, { ...o, functionName: "confirmedUntil" },
      { ...o, functionName: "closureCount" },
      { address: addr.factory, abi: factorySystemAbi, functionName: "multiplierWindowSecs" },
      { address: addr.factory, abi: factorySystemAbi, functionName: "vaultCount" },
    ],
  }).data;
  const nClosures = Number((cfg?.[6]?.result as bigint | undefined) ?? 0n);
  const closures = useReadContracts({
    contracts: Array.from({ length: nClosures }, (_, i) => ({ ...o, functionName: "closureAt", args: [BigInt(i)] }) as const),
    query: { enabled: nClosures > 0 },
  }).data;
  const perToken = useReadContracts({
    contracts: TOKENS.flatMap((t) => [
      { ...o, functionName: "configOf", args: [t.address] } as const,
      { address: addr.factory, abi: factoryAbi, functionName: "capOf", args: [t.address] } as const,
    ]),
  }).data;
  const v = (i: number) => cfg?.[i]?.result as number | bigint | undefined;
  const link = (a: string) => (isFork(addr) ? <code>{a}</code> : <a href={basescan(a)} target="_blank" rel="noreferrer"><code>{a}</code></a>);
  return (
    <>
      <div className="intro">
        <h1>What is deployed, and how it is set</h1>
        <p>Everything on this page is read from the chain. Nothing here is a promise: it is the configuration the contracts actually hold.</p>
      </div>
      <Card title="Contracts" aside={isFork(addr) ? <Pill tone="expected">local fork, not mainnet</Pill> : <Pill tone="fresh">Base mainnet</Pill>}>
        <dl className="kv">
          <dt>SessionOracle (WeekendMark)</dt><dd>{link(addr.oracle)}</dd>
          <dt>Slipstream adapter</dt><dd>{link(addr.adapter)}</dd>
          <dt>Vault factory</dt><dd>{link(addr.factory)}</dd>
          <dt>Vaults created</dt><dd>{v(8)?.toString() ?? "…"}</dd>
        </dl>
        <p className="note">The oracle's only privileged role is a recorder permission for calendar and threshold configuration. It touches no funds. Vaults are owned by the wallet that created them. The factory and adapter have no owner and no setters.</p>
      </Card>
      <Card title="Trading calendar">
        <dl className="kv">
          <dt>Weekly window opens</dt><dd>{typeof v(0) === "number" ? fmtWeekOffset(v(0) as number) : "…"}</dd>
          <dt>Weekly window closes</dt><dd>{typeof v(1) === "number" ? fmtWeekOffset(v(1) as number) : "…"}</dd>
          <dt>Calendar confirmed until</dt><dd>{v(5) !== undefined ? fmtDate(v(5) as bigint) : "…"}</dd>
          <dt>Heartbeat (hard limit)</dt><dd>{v(2) !== undefined ? `${fmtAge(Number(v(2)))} + ${fmtAge(Number(v(3)))} margin, counted in open time` : "…"}</dd>
          <dt>24/7 comparison window</dt><dd>{v(4) !== undefined ? fmtAge(Number(v(4))) : "…"}</dd>
        </dl>
        <h3>Declared closures</h3>
        {nClosures === 0 ? <Empty>No closures declared.</Empty> : (
          <ul className="plain">
            {closures?.map((c, i) => {
              const r = c.result as { start: bigint; end: bigint; kind: number } | undefined;
              return r ? <li key={i}><Pill tone="closed">{r.kind === 0 ? "Holiday" : "Early close"}</Pill> {fmtDate(r.start)} to {fmtDate(r.end)}</li> : null;
            })}
          </ul>
        )}
        <p className="note">Past the confirmed date the oracle answers "calendar not loaded" and the vaults refuse to trade, rather than guess whether a holiday applies. Closures are only ever added, never removed.</p>
      </Card>
      <Card title="Per-token configuration" aside="silence threshold and size cap">
        <div className="tablewrap">
          <table className="stack">
            <thead><tr><th>Token</th><th className="num">Silence threshold</th><th>24/7 feed</th><th className="num">Size cap per trade</th></tr></thead>
            <tbody>
              {TOKENS.map((t, i) => {
                const c = perToken?.[2 * i]?.result as readonly [string, string, number, bigint, bigint, boolean] | undefined;
                const cap = perToken?.[2 * i + 1]?.result as bigint | undefined;
                return (
                  <tr key={t.symbol}>
                    <td data-l="Token"><strong>{t.symbol}</strong></td>
                    <td data-l="Silence threshold" className="num">{c ? fmtAge(c[2]) : "…"}</td>
                    <td data-l="24/7 feed">{c ? (/^0x0+$/.test(c[1]) ? "none" : "compared") : "…"}</td>
                    <td data-l="Size cap" className="num">{cap !== undefined ? `$${Number(formatUnits(cap, 6)).toLocaleString()}` : "…"}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <p className="note">The size cap is immutable: it is fixed in the factory when it is deployed and cannot be changed. It limits how far one trade may move a token's pool price, and it was derived from real swaps on a fork. Pool depth varies a lot between blocks, so a cap is an upper bound for the pool state it was measured in, not a promise of execution. {v(7) !== undefined && <>After a corporate-action multiplier change, vaults wait {fmtAge(Number(v(7)))} before trading that token.</>}</p>
      </Card>
    </>
  );
}
