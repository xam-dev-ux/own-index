import { useState, type ReactNode } from "react";

const KEY = "own-index-eligibility-v1";

const read = () => { try { return localStorage.getItem(KEY) === "yes"; } catch { return false; } };
const write = () => { try { localStorage.setItem(KEY, "yes"); } catch { /* private window: asked again next visit */ } };

/** Eligibility attestation, remembered in this browser. It is a statement by the visitor, not a verification, and there
 *  is deliberately no geographic block: a static page cannot know where a visitor is, and no restricted jurisdiction has
 *  been identified for this project. If one is identified, a block needs a server or edge check, not code in this page. */
export function Gate({ children }: { children: ReactNode }) {
  const [ok, setOk] = useState(read);
  const [checked, setChecked] = useState(false);
  if (ok) return <>{children}</>;
  return (
    <div className="gate"><div className="gatebox">
      <h1>Before you continue</h1>
      <p>Own Index is software for holding tokenized equities in a vault you control. It is not an investment product, gives no advice, and does not manage anything for you.</p>
      <p>Tokenized stocks are restricted in some places. You are responsible for checking whether you are allowed to use them where you live.</p>
      <label className="check"><input type="checkbox" checked={checked} onChange={(e) => setChecked(e.target.checked)} />
        <span>I have checked that I am allowed to hold and trade tokenized equities where I live. I understand smart contracts can fail and that nothing here is advice.</span>
      </label>
      <button className="primary" disabled={!checked} onClick={() => { write(); setOk(true); }}>Continue</button>
    </div></div>
  );
}
