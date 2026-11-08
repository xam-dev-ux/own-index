export const erc20Abi = [
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ type: "address" }, { type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "bool" }] },
] as const;

export const factoryAbi = [
  { type: "function", name: "vaultsOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "address[]" }] },
  { type: "function", name: "capOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "createVault", stateMutability: "nonpayable", inputs: [], outputs: [{ type: "address" }] },
] as const;

export const adapterAbi = [
  { type: "function", name: "buy", stateMutability: "nonpayable", inputs: [{ name: "token", type: "address" }, { name: "usdcIn", type: "uint256" }, { name: "minOut", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "sell", stateMutability: "nonpayable", inputs: [{ name: "token", type: "address" }, { name: "tokenIn", type: "uint256" }, { name: "minOut", type: "uint256" }], outputs: [{ type: "uint256" }] },
] as const;

const err = (name: string, ...inputs: [string, string][]) =>
  ({ type: "error", name, inputs: inputs.map(([n, t]) => ({ name: n, type: t })) }) as const;

/** Vault write functions plus every vault error, so a failed simulation decodes into a name and arguments. */
export const vaultWriteAbi = [
  { type: "function", name: "deposit", stateMutability: "nonpayable", inputs: [{ name: "usdcAmount", type: "uint256" }, { name: "swapCalldata", type: "bytes[]" }], outputs: [] },
  { type: "function", name: "rebalance", stateMutability: "nonpayable", inputs: [{ name: "swapCalldata", type: "bytes[]" }], outputs: [] },
  { type: "function", name: "tryRebalance", stateMutability: "nonpayable", inputs: [{ name: "swapCalldata", type: "bytes[]" }], outputs: [{ name: "executed", type: "bool" }] },
  { type: "function", name: "setComponents", stateMutability: "nonpayable", inputs: [{ name: "components", type: "tuple[]", components: [{ name: "token", type: "address" }, { name: "targetWeightBps", type: "uint16" }] }], outputs: [] },
  { type: "function", name: "setRules", stateMutability: "nonpayable", inputs: [{ name: "rules", type: "tuple", components: [{ name: "driftThresholdBps", type: "uint16" }, { name: "minRebalanceInterval", type: "uint32" }, { name: "maxSlippageBps", type: "uint16" }] }], outputs: [] },
  { type: "function", name: "withdrawAllInKind", stateMutability: "nonpayable", inputs: [{ name: "to", type: "address" }], outputs: [] },
  err("NotOwner"), err("WeightsMustSumTo10000"),
  err("MarketClosed", ["token", "address"], ["cause", "uint8"]), err("AwaitingFirstPrint", ["token", "address"]),
  err("FeedFault", ["token", "address"], ["cause", "uint8"]), err("CorporateActionPause", ["token", "address"]),
  err("MultiplierChangeImminent", ["token", "address"], ["effectiveAt", "uint256"]),
  err("MultiplierChanged", ["token", "address"], ["observed", "uint256"], ["current", "uint256"]),
  err("NoDriftDetected"), err("RebalanceTooSoon", ["nextEligibleAt", "uint64"]),
  err("SlippageExceeded", ["traded", "uint256"], ["loss", "uint256"], ["maxLossAllowed", "uint256"]),
  err("ImpactCapExceeded", ["token", "address"], ["movedValue", "uint256"], ["cap", "uint256"]),
  err("SlippageCapExceeded", ["requested", "uint16"]), err("InvalidRules"), err("BadComponents"),
  err("TokenNotAllowed", ["token", "address"]), err("SwapFailed", ["index", "uint256"]), err("NotSelf"), err("Reentrancy"),
  err("AlreadyInitialized"), err("LengthMismatch"),
] as const;
