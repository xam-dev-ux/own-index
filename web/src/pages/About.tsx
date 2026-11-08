import { Card, Pill } from "../ui";

export function About() {
  return (
    <>
      <div className="intro">
        <h1>An index you hold yourself, that knows when not to trade</h1>
        <p>Own Index lets you build a basket of tokenized stocks with weights you choose, in a vault only you control. Its one idea: a vault should refuse to trade against a price that is not fresh, and should say exactly why.</p>
      </div>
      <Card title="How it works">
        <ol className="steps">
          <li><strong>You create a vault.</strong> It is a contract owned by your wallet. Nobody else, including whoever deployed Own Index, has any permission over it.</li>
          <li><strong>You choose components and weights.</strong> Own Index does not recommend any. You also set your own drift threshold, minimum interval and maximum slippage.</li>
          <li><strong>You deposit USDC.</strong> The vault buys your components through Aero Slipstream pools, in one atomic batch.</li>
          <li><strong>You rebalance when you decide to.</strong> Nothing trades on its own, and there is no keeper with access to your funds.</li>
          <li><strong>You can always leave.</strong> Withdrawal in kind never consults the oracle, a feed or a pool. It works with the market closed and with a feed broken.</li>
        </ol>
      </Card>
      <Card title="Why a vault refuses">
        <p className="note">The vault asks the oracle for a verdict on every component before any trade. Anything other than fresh refuses the whole batch, never part of it.</p>
        <dl className="kv wide">
          <dt><Pill tone="fresh">Fresh</Pill></dt><dd>Trading hours, and the latest print is recent enough. Trading allowed.</dd>
          <dt><Pill tone="closed">Closed</Pill></dt><dd>Weekend, holiday or early close. Normal. The held price is the last print and trading is refused.</dd>
          <dt><Pill tone="expected">Awaiting first print</Pill></dt><dd>The market reopened and the held price predates it. Expected for a short while after a reopen. Trading is refused until a new print arrives.</dd>
          <dt><Pill tone="paused">Paused</Pill></dt><dd>A corporate action is flagged, or a multiplier changed recently. Trading is refused until it settles.</dd>
          <dt><Pill tone="fault">Fault</Pill></dt><dd>Trading hours but the feed has gone quiet, exceeded its heartbeat, or cannot be read. Something may be wrong. Trading is refused.</dd>
        </dl>
        <p className="note">After a trade, two more guards apply: no token may move by more than its immutable size cap, and the whole batch may not lose more than your slippage limit against oracle prices.</p>
      </Card>
      <Card title="What this is not">
        <ul className="plain">
          <li>It is not a fund, a pooled product or a managed account. There is no shared token, share or NAV, and no one manages anything for you.</li>
          <li>It gives no advice or recommendation. Weights, rules and timing are yours.</li>
          <li>The WeekendMark oracle is reference data. It is explicitly not a liquidation oracle and must not be used as one.</li>
          <li>Own Index charges no fees in this version. The pools' own swap fees and price impact still apply to every trade.</li>
          <li>Smart contracts can fail. The contracts are not audited.</li>
        </ul>
      </Card>
    </>
  );
}
