// Read surface of SessionOracle beyond markOf: gap ledger, calendar and configuration. Mirrors src/SessionOracle.sol.
const u = <N extends string, T extends string>(name: N, type: T) => ({ name, type }) as const;

export const oracleSystemAbi = [
  { type: "function", name: "gapStats", stateMutability: "view", inputs: [u("token", "address")],
    outputs: [u("meanAbsGapBps", "uint256"), u("maxAbsGapBps", "uint256"), u("meanClosureSecs", "uint256"), u("count", "uint256")] },
  { type: "function", name: "gapCount", stateMutability: "view", inputs: [u("token", "address")], outputs: [u("", "uint256")] },
  { type: "function", name: "gapsPage", stateMutability: "view", inputs: [u("token", "address"), u("offset", "uint256"), u("limit", "uint256")],
    outputs: [{ name: "", type: "tuple[]", components: [
      u("closePrintAt", "uint64"), u("closePrice", "int256"), u("reopenPrintAt", "uint64"), u("reopenPrice", "int256"),
      u("observedAtMs", "uint64"), u("gapBps", "int256"), u("closureSecs", "uint32"), u("observedBlock", "uint64"),
    ] }] },
  { type: "function", name: "snapshotAll", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "weekOpenOffset", stateMutability: "view", inputs: [], outputs: [u("", "uint32")] },
  { type: "function", name: "weekCloseOffset", stateMutability: "view", inputs: [], outputs: [u("", "uint32")] },
  { type: "function", name: "heartbeatSecs", stateMutability: "view", inputs: [], outputs: [u("", "uint32")] },
  { type: "function", name: "heartbeatMarginSecs", stateMutability: "view", inputs: [], outputs: [u("", "uint32")] },
  { type: "function", name: "comparisonWindowSecs", stateMutability: "view", inputs: [], outputs: [u("", "uint32")] },
  { type: "function", name: "confirmedUntil", stateMutability: "view", inputs: [], outputs: [u("", "uint64")] },
  { type: "function", name: "closureCount", stateMutability: "view", inputs: [], outputs: [u("", "uint256")] },
  { type: "function", name: "closureAt", stateMutability: "view", inputs: [u("i", "uint256")],
    outputs: [{ name: "", type: "tuple", components: [u("start", "uint64"), u("end", "uint64"), u("kind", "uint8")] }] },
  { type: "function", name: "configOf", stateMutability: "view", inputs: [u("token", "address")],
    outputs: [u("feed", "address"), u("secondaryFeed", "address"), u("inSessionThresholdSecs", "uint32"), u("registeredAt", "uint64"), u("secondaryRegisteredAt", "uint64"), u("active", "bool")] },
] as const;

export const factorySystemAbi = [
  { type: "function", name: "multiplierWindowSecs", stateMutability: "view", inputs: [], outputs: [u("", "uint32")] },
  { type: "function", name: "vaultCount", stateMutability: "view", inputs: [], outputs: [u("", "uint256")] },
] as const;
