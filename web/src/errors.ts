import { BaseError, ContractFunctionRevertedError } from "viem";
import { CAUSE } from "./abi";
import { TOKENS } from "./tokens";

const sym = (a: unknown) => TOKENS.find((t) => t.address.toLowerCase() === String(a).toLowerCase())?.symbol ?? String(a);
const usd = (v: unknown) => `$${(Number(v) / 1e6).toLocaleString(undefined, { maximumFractionDigits: 2 })}`;
const cause = (c: unknown) => (CAUSE[Number(c)] ?? "").toLowerCase().replace(/_/g, " ");

/** Turns a failed simulation into a sentence in the contract's own vocabulary: the vault would refuse, and this says why. */
export function explainRevert(e: unknown): string {
  if (e instanceof BaseError) {
    const r = e.walk((x) => x instanceof ContractFunctionRevertedError);
    if (r instanceof ContractFunctionRevertedError) {
      const a = (r.data?.args ?? []) as readonly unknown[];
      switch (r.data?.errorName) {
        case "MarketClosed": return `Refused: market closed for ${sym(a[0])} (${cause(a[1])}). Normal outside the trading window.`;
        case "AwaitingFirstPrint": return `Refused: ${sym(a[0])} has not printed since the market reopened. Expected right after a reopen.`;
        case "FeedFault": return `Refused: feed problem on ${sym(a[0])} (${cause(a[1])}). The market is open and the feed is not delivering.`;
        case "CorporateActionPause": return `Refused: ${sym(a[0])} is paused for a corporate action.`;
        case "MultiplierChangeImminent": return `Refused: a multiplier change is about to take effect on ${sym(a[0])}.`;
        case "MultiplierChanged": return `Refused: the multiplier of ${sym(a[0])} changed recently; waiting for the settle window.`;
        case "NoDriftDetected": return "Nothing to rebalance: no component drifted past your threshold.";
        case "RebalanceTooSoon": return `Too soon: next rebalance allowed at ${new Date(Number(a[0]) * 1000).toISOString()}.`;
        case "SlippageExceeded": return `Slippage guard: the batch would lose ${usd(a[1])} on ${usd(a[0])} traded, more than your limit of ${usd(a[2])}.`;
        case "ImpactCapExceeded": return `Size cap: ${sym(a[0])} would move ${usd(a[1])}, above its immutable cap of ${usd(a[2])}.`;
        case "NotOwner": return "Only the vault owner can do this.";
        case "TokenNotAllowed": return `${sym(a[0])} is not allowed by this factory.`;
        case undefined: return r.reason ?? r.shortMessage;
        default: return `Refused: ${r.data?.errorName}.`;
      }
    }
    return e.shortMessage;
  }
  return String(e);
}
