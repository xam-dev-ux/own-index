import { CAUSE, REFUSAL, SESSION } from "./abi";

/** What a viewer should feel about a verdict. The point of the oracle's cause model is that these are NOT the same. */
export type Tone = "fresh" | "closed" | "expected" | "paused" | "fault";

export interface Verdict {
  tone: Tone;
  label: string;
  explain: string;
}

const CLOSED_TEXT: Record<string, string> = {
  WEEKEND: "Outside the weekly trading window. Normal.",
  HOLIDAY: "Declared market holiday. Normal.",
  EARLY_CLOSE: "After the shortened close of a half day. Normal.",
};

export function verdictOf(sessionId: number, causeId: number): Verdict {
  const session = SESSION[sessionId] ?? "UNKNOWN";
  const cause = CAUSE[causeId] ?? "NONE";
  switch (session) {
    case "FRESH":
      return { tone: "fresh", label: "Fresh", explain: "In session and the print is recent enough." };
    case "CLOSED":
      return { tone: "closed", label: `Closed · ${cause.toLowerCase().replace("_", " ")}`, explain: CLOSED_TEXT[cause] ?? "Market closed." };
    case "PAUSED":
      return { tone: "paused", label: "Paused", explain: "Corporate-action pause flagged by the registry. The vault will not trade this token." };
    case "STALE_IN_SESSION":
      if (cause === "AWAITING_FIRST_PRINT")
        return { tone: "expected", label: "Awaiting first print", explain: "The market reopened and the held print predates it. Expected right after a reopen, not a fault. Trading is refused until a new print arrives." };
      return {
        tone: "fault",
        label: cause === "HEARTBEAT_EXCEEDED" ? "Feed fault · heartbeat exceeded" : "Feed fault · not updating",
        explain: "The market is open and the feed has gone quiet. Something may be wrong. Trading is refused.",
      };
    default:
      return { tone: "fault", label: `Unknown · ${cause.toLowerCase().replace(/_/g, " ")}`, explain: "The verdict cannot be classified. Nothing should be inferred from this price." };
  }
}

export interface RefusalView { tone: Tone; label: string; explain: string }

/** Refusal kinds, same vocabulary as the contract. Market states keep the tone of the oracle verdict they come from. */
export function refusalView(kindId: number, causeId: number): RefusalView {
  const kind = REFUSAL[kindId] ?? "NONE";
  switch (kind) {
    case "MARKET_CLOSED": return { tone: "closed", label: "Market closed", explain: verdictOf(1, causeId).explain };
    case "AWAITING_FIRST_PRINT": return { tone: "expected", label: "Awaiting first print", explain: "Market reopened, no new print yet. Expected." };
    case "FEED_FAULT": return { tone: "fault", label: "Feed fault", explain: `Open market, feed not delivering (${(CAUSE[causeId] ?? "").toLowerCase().replace(/_/g, " ")}).` };
    case "CORPORATE_ACTION_PAUSE": return { tone: "paused", label: "Corporate-action pause", explain: "Flagged by the registry." };
    case "MULTIPLIER_CHANGE_IMMINENT": return { tone: "paused", label: "Multiplier change imminent", explain: "A corporate-action multiplier change is about to take effect." };
    case "MULTIPLIER_CHANGED": return { tone: "paused", label: "Multiplier changed", explain: "The multiplier changed recently; waiting for the settle window." };
    case "NO_DRIFT": return { tone: "closed", label: "Nothing to do", explain: "No component drifted past your threshold." };
    case "TOO_SOON": return { tone: "closed", label: "Too soon", explain: "Your minimum interval between rebalances has not passed." };
    case "SLIPPAGE_EXCEEDED": return { tone: "expected", label: "Slippage guard", explain: "The batch lost more than your maximum slippage against oracle prices." };
    case "IMPACT_CAP_EXCEEDED": return { tone: "expected", label: "Size cap", explain: "A leg moved more than the token's immutable size cap." };
    default: return { tone: "closed", label: kind, explain: "" };
  }
}
