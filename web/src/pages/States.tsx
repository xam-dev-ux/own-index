import { CAUSE, REFUSAL, SESSION } from "../abi";
import { refusalView, verdictOf } from "../verdict";
import { Card, Pill } from "../ui";

/** Development page: every verdict and refusal the UI can show, rendered from the same functions the real pages use.
 *  The fork only ever produces a few of them, so this is how the rest are looked at. */
export function States() {
  const combos: [number, number][] = [[0, 0], [1, 1], [1, 2], [1, 3], [2, 4], [2, 5], [2, 6], [3, 7], [4, 8], [4, 9], [4, 10]];
  return (
    <>
      <div className="intro"><h1>All states</h1><p>Every verdict and refusal, rendered from the same code as the real pages.</p></div>
      <Card title="Oracle verdicts">
        <table><thead><tr><th>Session / cause</th><th>As shown</th></tr></thead><tbody>
          {combos.map(([s, c]) => { const v = verdictOf(s, c); return (
            <tr key={`${s}-${c}`}><td><code>{SESSION[s]} / {CAUSE[c]}</code></td><td><Pill tone={v.tone}>{v.label}</Pill><div className="why">{v.explain}</div></td></tr>
          ); })}
        </tbody></table>
      </Card>
      <Card title="Refusal kinds">
        <table><thead><tr><th>Kind</th><th>As shown</th></tr></thead><tbody>
          {REFUSAL.slice(1).map((k, i) => { const r = refusalView(i + 1, k === "MARKET_CLOSED" ? 1 : k === "FEED_FAULT" ? 5 : 0); return (
            <tr key={k}><td><code>{k}</code></td><td><Pill tone={r.tone}>{r.label}</Pill><div className="why">{r.explain}</div></td></tr>
          ); })}
        </tbody></table>
      </Card>
    </>
  );
}
