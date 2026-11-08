import { CAUSE, SESSION } from "./abi";

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
