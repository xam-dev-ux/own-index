import { useState } from "react";
import { useAccount, usePublicClient, useReadContract, useReadContracts, useWriteContract } from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { encodeFunctionData, formatUnits, parseUnits, type Abi } from "viem";
import { type Addresses, BUILDER_SUFFIX } from "./config";
import { oracleAbi, vaultAbi } from "./abi";
import { adapterAbi, erc20Abi, factoryAbi, vaultWriteAbi } from "./abiWrite";
import { TOKENS } from "./tokens";
import { explainRevert } from "./errors";

type Addr = `0x${string}`;
const sym = (a: string) => TOKENS.find((t) => t.address.toLowerCase() === a.toLowerCase())?.symbol ?? a.slice(0, 6);
const usd = (v: bigint) => `$${Number(formatUnits(v, 6)).toLocaleString(undefined, { maximumFractionDigits: 2 })}`;
/** B20 stock tokens have 8 decimals and feeds have 8 decimals; USDC has 6. value(USDC units) = raw * price / 1e10. */
const valueOf = (raw: bigint, price: bigint) => (raw * price) / 10n ** 10n;
const rawFor = (value: bigint, price: bigint) => (value * 10n ** 10n) / price;

interface Leg { token: Addr; kind: "buy" | "sell"; value: bigint; amount: bigint; cap: bigint }

/** Shared sender: every write goes through here, so the Builder Code suffix (when configured) is added in one place. */
function useSender() {
  const client = usePublicClient();
  const { address: account } = useAccount();
  const qc = useQueryClient();
  const { writeContractAsync } = useWriteContract();
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  async function send(label: string, params: Parameters<typeof writeContractAsync>[0]) {
    setBusy(true); setMsg(null);
    try {
      // The estimate is too tight for a batch of nested swaps (it ran out of gas on a fork), so send with 30% headroom.
      const est = await client!.estimateContractGas({ ...params, account: account! } as never);
      const hash = await writeContractAsync({ ...params, gas: (est * 13n) / 10n, ...(BUILDER_SUFFIX ? { dataSuffix: BUILDER_SUFFIX } : {}) } as never);
      const rc = await client!.waitForTransactionReceipt({ hash });
      await qc.invalidateQueries();
      setMsg(rc.status === "success" ? { ok: true, text: `${label}: done (${hash.slice(0, 10)}…)` } : { ok: false, text: `${label}: transaction reverted` });
      return rc.status === "success";
    } catch (e) { setMsg({ ok: false, text: explainRevert(e) }); return false; }
    finally { setBusy(false); }
  }
  return { client, send, busy, msg, setMsg };
}

function Msg({ m }: { m: { ok: boolean; text: string } | null }) {
  return m ? <p className={`banner ${m.ok ? "fresh" : "expected"}`}>{m.text}</p> : null;
}

export function CreateVault({ addr }: { addr: Addresses }) {
  const { send, busy, msg } = useSender();
  return (
    <section>
      <h2>Create your vault</h2>
      <p className="note">A vault is a contract owned by your wallet. Only you can trade with it or withdraw from it. Nobody else, including whoever deployed Own Index, has any permission over it.</p>
      <button disabled={busy} onClick={() => send("Create vault", { address: addr.factory, abi: factoryAbi, functionName: "createVault" })}>Create vault</button>
      <Msg m={msg} />
    </section>
  );
}

export function Setup({ addr, vault }: { addr: Addresses; vault: Addr }) {
  const { send, busy, msg, setMsg } = useSender();
  const [w, setW] = useState<Record<string, string>>({});
  const [drift, setDrift] = useState("5"), [interval, setIntervalS] = useState("3600"), [slip, setSlip] = useState("1");
  const caps = useReadContracts({ contracts: TOKENS.map((t) => ({ address: addr.factory, abi: factoryAbi, functionName: "capOf", args: [t.address] }) as const) });
  const picked = TOKENS.filter((t) => Number(w[t.symbol] || 0) > 0);
  const total = picked.reduce((s, t) => s + Number(w[t.symbol]), 0);
  async function save() {
    if (Math.round(total * 100) !== 10000) { setMsg({ ok: false, text: "Weights must add up to 100%." }); return; }
    const comps = picked.map((t) => ({ token: t.address as Addr, targetWeightBps: Math.round(Number(w[t.symbol]) * 100) }));
    if (await send("Set components", { address: vault, abi: vaultWriteAbi, functionName: "setComponents", args: [comps] }))
      await send("Set rules", { address: vault, abi: vaultWriteAbi, functionName: "setRules", args: [{ driftThresholdBps: Math.round(Number(drift) * 100), minRebalanceInterval: Number(interval), maxSlippageBps: Math.round(Number(slip) * 100) }] });
  }
  return (
    <section>
      <h2>Choose your components</h2>
      <p className="note">You pick the weights. Own Index does not recommend any.</p>
      <table>
        <thead><tr><th>Token</th><th className="num">Weight %</th><th className="num">Size cap per trade</th></tr></thead>
        <tbody>{TOKENS.map((t, i) => {
          const cap = caps.data?.[i]?.result as bigint | undefined;
          return (
            <tr key={t.symbol}><td><strong>{t.symbol}</strong></td>
              <td className="num"><input type="number" min="0" max="100" step="0.01" value={w[t.symbol] ?? ""} onChange={(e) => setW({ ...w, [t.symbol]: e.target.value })} /></td>
              <td className="num">{cap ? usd(cap) : "—"}</td></tr>
          );
        })}</tbody>
      </table>
      <p className="note">Total {total.toFixed(2)}%. Rules: rebalance when a weight drifts <input className="sm" value={drift} onChange={(e) => setDrift(e.target.value)} />% · at least <input className="sm" value={interval} onChange={(e) => setIntervalS(e.target.value)} />s between rebalances · max slippage <input className="sm" value={slip} onChange={(e) => setSlip(e.target.value)} />% (hard cap 5%).</p>
      <button disabled={busy} onClick={save}>Save components and rules</button>
      <Msg m={msg} />
    </section>
  );
}

export function Actions({ addr, vault }: { addr: Addresses; vault: Addr }) {
  const { address: account } = useAccount();
  const comps = useReadContract({ address: vault, abi: vaultAbi, functionName: "components", query: { refetchInterval: 5000 } }).data;
  const tokens = (comps ?? []).map((c) => c.token);
  const n = tokens.length;
  type Call = { address: Addr; abi: Abi; functionName: string; args?: readonly unknown[] };
  const { data } = useReadContracts({
    contracts: ([
      { address: addr.oracle, abi: oracleAbi, functionName: "marksOf", args: [tokens] },
      ...tokens.map((t) => ({ address: addr.factory, abi: factoryAbi, functionName: "capOf", args: [t] }) as const),
      ...tokens.map((t) => ({ address: t, abi: erc20Abi, functionName: "balanceOf", args: [vault] }) as const),
      { address: addr.usdc, abi: erc20Abi, functionName: "balanceOf", args: [vault] },
      { address: addr.usdc, abi: erc20Abi, functionName: "balanceOf", args: [account!] },
      { address: addr.usdc, abi: erc20Abi, functionName: "allowance", args: [account!, vault] },
    ] as unknown as Call[]),
    query: { enabled: n > 0 && !!account, refetchInterval: 5000 },
  });
  if (!comps || n === 0 || !data || data.some((d) => d.status !== "success")) return null;
  const marks = data[0].result as unknown as readonly { price: bigint }[];
  const caps = tokens.map((_, i) => data[1 + i].result as bigint);
  const bals = tokens.map((_, i) => data[1 + n + i].result as bigint);
  const vaultUsdc = data[1 + 2 * n].result as bigint;
  const myUsdc = data[2 + 2 * n].result as bigint;
  const allowance = data[3 + 2 * n].result as bigint;
  const ctx = { addr, vault, account: account!, comps, caps, bals, marks, vaultUsdc, myUsdc, allowance };
  return (<><DepositPanel {...ctx} /><RebalancePanel {...ctx} /><WithdrawPanel vault={vault} account={account!} /></>);
}

interface Ctx {
  addr: Addresses; vault: Addr; account: Addr; comps: readonly { token: Addr; targetWeightBps: number }[];
  caps: bigint[]; bals: bigint[]; marks: readonly { price: bigint }[]; vaultUsdc: bigint; myUsdc: bigint; allowance: bigint;
}

const encode = (adapter: Addr, l: Leg) => encodeFunctionData({ abi: adapterAbi, functionName: l.kind, args: [l.token, l.kind === "buy" ? l.value : l.amount, 0n] });

function LegTable({ legs }: { legs: Leg[] }) {
  return (
    <table>
      <thead><tr><th>Leg</th><th>Token</th><th className="num">Size</th><th className="num">Cap</th><th /></tr></thead>
      <tbody>{legs.map((l, i) => (
        <tr key={i}><td>{l.kind}</td><td><strong>{sym(l.token)}</strong></td><td className="num">{usd(l.value)}</td><td className="num">{usd(l.cap)}</td>
          <td>{l.value > l.cap ? <span className="pill expected">over cap</span> : null}</td></tr>
      ))}</tbody>
    </table>
  );
}

function DepositPanel(c: Ctx) {
  const { client, send, busy, msg, setMsg } = useSender();
  const [amount, setAmount] = useState("");
  const [checked, setChecked] = useState<string | null>(null);
  let amt = 0n;
  try { amt = amount ? parseUnits(amount, 6) : 0n; } catch { /* partial input */ }
  const legs: Leg[] = [];
  let rest = amt;
  c.comps.forEach((k, i) => {
    const v = i === c.comps.length - 1 ? rest : (amt * BigInt(k.targetWeightBps)) / 10000n;
    rest -= v;
    if (v > 0n) legs.push({ token: k.token, kind: "buy", value: v, amount: 0n, cap: c.caps[i] });
  });
  const over = legs.filter((l) => l.value > l.cap);
  // Largest deposit that keeps every leg inside its token's cap at the chosen weights.
  const maxDeposit = c.comps.reduce((m, k, i) => (k.targetWeightBps === 0 ? m : (c.caps[i] * 10000n) / BigInt(k.targetWeightBps) < m ? (c.caps[i] * 10000n) / BigInt(k.targetWeightBps) : m), 2n ** 255n);
  const needsApproval = amt > 0n && c.allowance < amt;
  async function check() {
    setMsg(null);
    try {
      await client!.simulateContract({ address: c.vault, abi: vaultWriteAbi, functionName: "deposit", args: [amt, legs.map((l) => encode(c.addr.adapter, l))], account: c.account });
      setChecked(amount); setMsg({ ok: true, text: "Simulation passed: the vault would accept this deposit right now." });
    } catch (e) { setChecked(null); setMsg({ ok: false, text: explainRevert(e) }); }
  }
  return (
    <section>
      <h2>Deposit</h2>
      <p className="note">USDC in your wallet: {usd(c.myUsdc)}. Deposits buy your components at your target weights through the Aero Slipstream pools. Largest deposit that fits every token's cap at your weights: <strong>{usd(maxDeposit)}</strong>.</p>
      <input placeholder="USDC amount" value={amount} onChange={(e) => { setAmount(e.target.value); setChecked(null); setMsg(null); }} />{" "}
      {amt > c.myUsdc && <span className="pill expected">more than your balance</span>}
      {amt > 0n && <LegTable legs={legs} />}
      {over.length > 0 && <p className="banner expected">The vault would refuse this: {over.map((l) => sym(l.token)).join(", ")} above the size cap. Reduce the amount to at most {usd(maxDeposit)}.</p>}
      {needsApproval ? (
        <button disabled={busy || amt > c.myUsdc} onClick={() => send("Approve USDC", { address: c.addr.usdc, abi: erc20Abi, functionName: "approve", args: [c.vault, amt] })}>Approve {usd(amt)} USDC</button>
      ) : (
        <>
          <button disabled={busy || amt === 0n || over.length > 0 || amt > c.myUsdc} onClick={check}>Check</button>{" "}
          <button disabled={busy || checked !== amount || amt === 0n} onClick={async () => { if (await send("Deposit", { address: c.vault, abi: vaultWriteAbi, functionName: "deposit", args: [amt, legs.map((l) => encode(c.addr.adapter, l))] })) setChecked(null); }}>Deposit</button>
        </>
      )}
      <Msg m={msg} />
    </section>
  );
}

function RebalancePanel(c: Ctx) {
  const { client, send, busy, msg, setMsg } = useSender();
  const [ok, setOk] = useState(false);
  const [refused, setRefused] = useState(false);
  const prices = c.marks.map((m) => m.price);
  const cur = c.comps.map((_, i) => (prices[i] > 0n ? valueOf(c.bals[i], prices[i]) : 0n));
  const total = cur.reduce((a, b) => a + b, 0n) + c.vaultUsdc;
  const diff = c.comps.map((k, i) => (total * BigInt(k.targetWeightBps)) / 10000n - cur[i]);
  const rules = useReadContract({ address: c.vault, abi: vaultAbi, functionName: "rules" }).data;
  const thresholdBps = rules ? BigInt(rules[0]) : 0n;
  const maxDriftBps = total > 0n ? diff.reduce((m, d) => ((d < 0n ? -d : d) * 10000n) / total > m ? ((d < 0n ? -d : d) * 10000n) / total : m, 0n) : 0n;
  const withinThreshold = !!rules && maxDriftBps < thresholdBps;
  const legs: Leg[] = [];
  let proceeds = c.vaultUsdc;
  c.comps.forEach((k, i) => {
    if (withinThreshold) return;
    if (diff[i] >= -1_000_000n || prices[i] <= 0n) return;
    const amount = (() => { const a = rawFor(-diff[i], prices[i]); return a > c.bals[i] ? c.bals[i] : a; })();
    legs.push({ token: k.token, kind: "sell", value: -diff[i], amount, cap: c.caps[i] });
    proceeds += -diff[i];
  });
  const want = c.comps.reduce((s, _, i) => (diff[i] > 1_000_000n ? s + diff[i] : s), 0n);
  c.comps.forEach((k, i) => {
    if (withinThreshold || diff[i] <= 1_000_000n) return;
    // Buys are scaled to what the sells (plus idle USDC) will provide, with 1% held back for pool fees and impact.
    const v = want > proceeds ? (diff[i] * proceeds * 99n) / (want * 100n) : diff[i];
    if (v > 0n) legs.push({ token: k.token, kind: "buy", value: v, amount: 0n, cap: c.caps[i] });
  });
  const over = legs.some((l) => l.value > l.cap);
  const calls = legs.map((l) => encode(c.addr.adapter, l));
  async function check() {
    setMsg(null); setRefused(false);
    try {
      await client!.simulateContract({ address: c.vault, abi: vaultWriteAbi, functionName: "rebalance", args: [calls], account: c.account });
      setOk(true); setMsg({ ok: true, text: "Simulation passed: the vault would execute this rebalance right now." });
    } catch (e) { setOk(false); setRefused(true); setMsg({ ok: false, text: explainRevert(e) }); }
  }
  return (
    <section>
      <h2>Rebalance</h2>
      <p className="note">Sells what is above target, then buys what is below, in one atomic batch. If any price is not fresh the whole batch is refused.</p>
      {withinThreshold ? <p className="note">Largest drift is {(Number(maxDriftBps) / 100).toFixed(2)}%, inside your {(Number(thresholdBps) / 100).toFixed(2)}% threshold. Nothing to trade. Check still asks the vault, and the refusal can be recorded on chain.</p> : legs.length === 0 ? <p className="note">Nothing to trade.</p> : <LegTable legs={legs} />}
      {over && <p className="banner expected">At least one leg is above its token's size cap, so the vault would refuse it.</p>}
      <button disabled={busy} onClick={check}>Check</button>{" "}
      <button disabled={busy || !ok} onClick={async () => { if (await send("Rebalance", { address: c.vault, abi: vaultWriteAbi, functionName: "rebalance", args: [calls] })) setOk(false); }}>Rebalance</button>{" "}
      {refused && <button disabled={busy} title="Leaves a RebalanceRefused event on chain. A reverted call leaves no log." onClick={() => send("Record refusal", { address: c.vault, abi: vaultWriteAbi, functionName: "tryRebalance", args: [calls] })}>Record this refusal on chain</button>}
      <Msg m={msg} />
    </section>
  );
}

function WithdrawPanel({ vault, account }: { vault: Addr; account: Addr }) {
  const { send, busy, msg } = useSender();
  return (
    <section>
      <h2>Withdraw</h2>
      <p className="note">Sends every component and any USDC from your vault to your wallet, as they are. This never consults the oracle, a feed or a pool, so it works at any time, including when the market is closed or a feed is broken.</p>
      <button disabled={busy} onClick={() => send("Withdraw everything", { address: vault, abi: vaultWriteAbi, functionName: "withdrawAllInKind", args: [account] })}>Withdraw everything in kind</button>
      <Msg m={msg} />
    </section>
  );
}
