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

// Mirrors src/IIndexVault.sol (RefusalKind order is the on-chain order).
export const REFUSAL = [
  "NONE", "MARKET_CLOSED", "AWAITING_FIRST_PRINT", "FEED_FAULT", "CORPORATE_ACTION_PAUSE", "MULTIPLIER_CHANGE_IMMINENT",
  "NO_DRIFT", "TOO_SOON", "SLIPPAGE_EXCEEDED", "IMPACT_CAP_EXCEEDED", "MULTIPLIER_CHANGED",
] as const;

export const vaultAbi = [
  { type: "function", name: "components", stateMutability: "view", inputs: [],
    outputs: [{ type: "tuple[]", components: [{ name: "token", type: "address" }, { name: "targetWeightBps", type: "uint16" }] }] },
  { type: "function", name: "currentWeights", stateMutability: "view", inputs: [], outputs: [{ type: "uint16[]" }] },
  { type: "function", name: "totalValue", stateMutability: "view", inputs: [], outputs: [{ name: "value", type: "uint256" }, { name: "allFresh", type: "bool" }] },
  { type: "function", name: "rules", stateMutability: "view", inputs: [],
    outputs: [{ name: "driftThresholdBps", type: "uint16" }, { name: "minRebalanceInterval", type: "uint32" }, { name: "maxSlippageBps", type: "uint16" }] },
  { type: "function", name: "refusalCount", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "rebalanceStatus", stateMutability: "view", inputs: [],
    outputs: [
      { name: "possible", type: "bool" },
      { name: "refusals", type: "tuple[]", components: [{ name: "kind", type: "uint8" }, { name: "token", type: "address" }, { name: "cause", type: "uint8" }] },
      { name: "nextEligibleAt", type: "uint64" }, { name: "maxDriftBps", type: "uint16" },
    ] },
] as const;

export const refusedEvent = {
  type: "event", name: "RebalanceRefused",
  inputs: [
    { name: "refusalId", type: "uint256", indexed: true }, { name: "kind", type: "uint8", indexed: false },
    { name: "token", type: "address", indexed: true }, { name: "cause", type: "uint8", indexed: false },
    { name: "timestampMs", type: "uint64", indexed: false },
  ],
} as const;
