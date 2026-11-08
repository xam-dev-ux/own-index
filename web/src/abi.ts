// Mirrors src/ISessionOracle.sol. Enum order matters: it is the on-chain order.
export const SESSION = ["FRESH", "CLOSED", "STALE_IN_SESSION", "PAUSED", "UNKNOWN"] as const;
export const CAUSE = [
  "NONE", "WEEKEND", "HOLIDAY", "EARLY_CLOSE", "AWAITING_FIRST_PRINT", "FEED_NOT_UPDATING",
  "HEARTBEAT_EXCEEDED", "REGISTRY_PAUSED", "FEED_INVALID", "CALENDAR_NOT_LOADED", "NOT_CONFIGURED",
] as const;
export const DIVERGENCE = [
  "NO_SECONDARY", "NOT_COMPARABLE_CLOSED", "NOT_COMPARABLE_FAULT", "NOT_COMPARABLE_NEW", "PRINTS_TOO_FAR_APART", "COMPARED",
] as const;

const markComponents = [
  { name: "price", type: "int256" },
  { name: "session", type: "uint8" },
  { name: "cause", type: "uint8" },
  { name: "stalenessSecs", type: "uint32" },
  { name: "confidenceBps", type: "uint16" },
  { name: "timestampMs", type: "uint64" },
  { name: "divergenceStatus", type: "uint8" },
  { name: "divergenceBps", type: "int256" },
  { name: "secondaryPrice", type: "int256" },
  { name: "printLagSecs", type: "uint32" },
] as const;

export const oracleAbi = [
  {
    type: "function", name: "marksOf", stateMutability: "view",
    inputs: [{ name: "tokens", type: "address[]" }],
    outputs: [{ name: "", type: "tuple[]", components: markComponents }],
  },
] as const;
