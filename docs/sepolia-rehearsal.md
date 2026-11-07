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
