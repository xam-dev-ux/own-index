// The ten tokenized equities the oracle is configured for (same list as script/MainnetConfig.sol).
export const TOKENS = [
  { symbol: "AAPL", address: "0xb200000000000000000000C2e324d24d7eEcd1fb" },
  { symbol: "AMZN", address: "0xb200000000000000000000d9192b6B456483C2E8" },
  { symbol: "GOOGL", address: "0xb2000000000000000000002D0BA3164cc74f58B7" },
  { symbol: "META", address: "0xb2000000000000000000008bC8786B856E61707C" },
  { symbol: "MSFT", address: "0xB200000000000000000000Ab99cFa739E253872B" },
  { symbol: "MSTR", address: "0xb2000000000000000000004884b426556b92883d" },
  { symbol: "NVDA", address: "0xb20000000000000000000078ee7ce2fE4908108C" },
  { symbol: "SNDK", address: "0xb200000000000000000000397293Cb8cda9a10c5" },
  { symbol: "SPCX", address: "0xb2000000000000000000007b9fcbd005511aCBd5" },
  { symbol: "TSLA", address: "0xb2000000000000000000001e800a7f5189430cD0" },
] as const satisfies readonly { symbol: string; address: `0x${string}` }[];
