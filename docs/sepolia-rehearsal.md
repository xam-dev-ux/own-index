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
3. The verdict checks inside the script run against the simulated state. After broadcasting, read the deployed oracles directly on chain to confirm, for example `base-cast call <oracle> "markOf(address)" <mock token> --rpc-url https://sepolia.base.org`, for each mock token printed in the broadcast file.
