import { useEffect, useState, type ReactNode } from "react";

const KEY = "own-index-eligibility-v1";
const GEO_URL = import.meta.env.VITE_GEO_CHECK_URL as string | undefined;

const read = () => { try { return localStorage.getItem(KEY) === "yes"; } catch { return false; } };
const write = () => { try { localStorage.setItem(KEY, "yes"); } catch { /* private window: asked again next visit */ } };

/** Two checks before anything else is shown.
 *  1. Region: asks an endpoint you operate (VITE_GEO_CHECK_URL, expected to answer {"blocked":boolean}). A static page cannot
 *     know where a visitor is, so without that endpoint there is NO geographic block, only the attestation below.
 *  2. Eligibility attestation, remembered in this browser. It is a statement by the visitor, not a verification. */
export function Gate({ children }: { children: ReactNode }) {
  const [ok, setOk] = useState(read);
  const [checked, setChecked] = useState(false);
  const [blocked, setBlocked] = useState(false);
  useEffect(() => {
    if (!GEO_URL) return;
    fetch(GEO_URL).then((r) => r.json()).then((j) => setBlocked(!!j.blocked)).catch(() => { /* endpoint down: attestation still applies */ });
  }, []);
  if (blocked) {
    return <div className="gate"><div className="gatebox"><h1>Not available in your region</h1><p>Tokenized stocks and this software are not offered where you appear to be.</p></div></div>;
  }
  if (!ok) {
    return (
      <div className="gate"><div className="gatebox">
        <h1>Before you continue</h1>
        <p>Own Index is software for holding tokenized equities in a vault you control. It is not an investment product, gives no advice, and does not manage anything for you.</p>
        <p>Tokenized stocks are restricted in some places. You are responsible for checking whether you are allowed to use them where you live.</p>
        <label className="check"><input type="checkbox" checked={checked} onChange={(e) => setChecked(e.target.checked)} />
          <span>I am not located in, and am not a resident of, a jurisdiction where holding or trading tokenized equities is prohibited or restricted for me. I understand smart contracts can fail and that nothing here is advice.</span>
        </label>
        <button disabled={!checked} onClick={() => { write(); setOk(true); }}>Continue</button>
      </div></div>
    );
  }
  return <>{children}</>;
}
