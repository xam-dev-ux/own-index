# Sepolia rehearsal

## Scope
Sepolia validates the deployment flow only: deployer and `--account speedrun`, the order of configuration, `confirmCalendarUntil`, closure loading, and that a configured token yields each expected verdict from a mock that can be put in every state. It does not validate real feed behaviour, real window offsets or real thresholds, because Sepolia has no Chainlink equity feeds and no B20 tokens.

## Disposable parameters
Every window, threshold and closure value in `script/RehearseSepolia.s.sol` is deliberate garbage, marked DISPOSABLE in the source. The window is the whole week so the script works whenever it is run; the thresholds are 2 hours; the closures are placed relative to the run time. None of it may be carried to mainnet. The script refuses to run on chain 8453.

## States covered
`MockFeed` in `src/testing/MockFeed.sol` can produce: fresh, held print inside the threshold after a closure (AWAITING_FIRST_PRINT), silence past the threshold (FEED_NOT_UPDATING), silence past the heartbeat (HEARTBEAT_EXCEEDED), future-dated print, price above 1e20, reverting call, short return data, wrong decimals. The script also covers PAUSED via a mock registry and CLOSED via a second oracle whose window excludes the run time.

Not covered here: DivergenceStatus COMPARED (it needs both feeds registered for longer than the comparison window, which a single run cannot satisfy), HOLIDAY/EARLY_CLOSE at their real dates, and any real gap recording.

## Steps
1. `make rehearse-dry` simulates against a Sepolia fork. No broadcast, no password.
2. `make rehearse-sepolia` broadcasts. It prompts for the keystore password. Estimated cost 0.00018 ETH.
3. The rehearsal is not done at broadcast. The verdict checks inside the script run against simulated state. Run `python3 -I scripts/check_rehearsal.py broadcast/RehearseSepolia.s.sol/84532/run-latest.json` to read the nine verdicts from the deployed contracts on Sepolia. It prints ALL MATCH or DIVERGENCE. Only ALL MATCH completes the rehearsal. The checker itself was exercised end to end on a local fork of Sepolia with real broadcast transactions (not on Sepolia).

## Known gap: one debt, not two
`DivergenceStatus.COMPARED` and `PRINTS_TOO_FAR_APART` are not exercised with real data. Both are settled by the same fixture: the real print sequence (AAPL 19:58 UTC and NVDA 21:39 UTC on 2026-11-06, plus the Monday prints from the poller CSVs). A second Sepolia run built from mocks would prove nothing the unit tests do not already prove. Until that fixture exists, neither status is eligibility evidence.

## Result: 2026-11-07, Base Sepolia (chain 84532), blocks 55808109 to 55808124
Broadcast with `--account speedrun`; all transactions succeeded; total paid 0.000073 ETH.

| Contract | Address |
|---|---|
| openOracle (SessionOracle, 8 tokens) | 0x1F738c57907505650659dF4D9891868bf6eb325e |
| closedOracle (SessionOracle, 1 token) | 0x5322b30b2841aC123D935775bE225fF7570c5c0a |

`scripts/check_rehearsal.py` read the nine verdicts from the deployed contracts: FRESH, AWAITING_FIRST_PRINT, FEED_NOT_UPDATING, HEARTBEAT_EXCEEDED, FEED_INVALID (future-dated), FEED_INVALID (price above 1e20), PAUSED, FEED_INVALID (reverting feed), CLOSED. Output: ALL MATCH, so the simulation and the chain agree.

These addresses equal those of the earlier local-fork run because a contract address depends only on the deployer and its nonce; they were not reused from that run.

Parameters in these deployments are disposable. Do not carry any of them to mainnet.

## Second rehearsal: the vault side
`script/RehearseSepoliaVault.s.sol` deploys what the first one did not: a mock USDC and four mock stocks with mock feeds, a `SessionOracle`, a mock Slipstream router, the real `SlipstreamAdapter`, the real `IndexVaultFactory`, and two vaults. Vault 1 is funded through the adapter, then records two refusals on chain (NO_DRIFT, and FEED_FAULT after one feed is made silent). Vault 2 deposits and withdraws everything in kind.

What it proves: the deployment order and constructors of adapter and factory, the clone creation, the vault flow through the adapter's calldata, `tryRebalance` recording refusals, and the unconditional withdrawal. What it cannot prove: real pools, price impact, real feeds, real caps. The mock router swaps 1:1 in raw units, which at the $100 mock price equals the oracle price. All numbers are disposable.

1. `make rehearse-vault-dry` simulates against a Sepolia fork. No password. Estimated cost 0.00024 ETH.
2. `make rehearse-vault-sepolia` broadcasts and prompts for the keystore password.
3. `make check-vault-rehearsal ORACLE=0x.. FACTORY=0x.. VAULT=0x.. VAULT_OUT=0x..` reads the chain, read-only, with no keystore. Only ALL MATCH completes the rehearsal. The component prints stay FRESH for about 12 hours, so run the check the same day.

Exercised before any real broadcast: simulation passes, and a broadcast on a local fork of Sepolia followed by the checker returned ALL MATCH.

### Result: 2026-11-09, Base Sepolia (chain 84532), block 56234176 and following
Broadcast with `--account speedrun`; every transaction succeeded; total paid 0.000098 ETH. `make check-vault-rehearsal` read the chain and printed ALL MATCH (24 checks).

| Contract | Address |
|---|---|
| SessionOracle | 0x49A3c2D794bE882D8f3feA97d45453cB8d20Bf07 |
| SlipstreamAdapter (over a mock router) | 0xF3c10D18237454D248f1ef9f66Ae70E4b4bfA53b |
| IndexVaultFactory | 0xb7E7bfA005c44922B8AA4073ff0428C1a0e53c25 |
| Vault 1 (funded, two refusals recorded) | 0xBdCac0C7a5178990Ac8B617AdC7fe3F884f133D4 |
| Vault 2 (deposited, withdrawn in kind) | 0xf946F61aa5edB9F3ab3759f2a9F15dC22277f88d |

These addresses equal those of the earlier local run on a fork of Sepolia: a contract address depends only on the deployer and its nonce, and the fork had the same state. Parameters are disposable. The mock feeds stay FRESH about 12 hours, so the checker is only meaningful the same day.
