# Local fork for UI development

`make setup-fork` starts a Base fork at block 53934124 (Fri 2026-11-06 15:00 UTC, US session open), deploys oracle,
adapter and factory with `deploy/fork.params.env`, funds anvil's first dev account with test USDC, creates a vault,
sets 11 components, deposits 8,800 USDC through the real Slipstream pools and records one `NO_DRIFT` refusal.
Addresses go to `.fork/addresses.json`. `make stop-fork` stops it. No keystore, no private key, nothing touches mainnet.

- Deployer is impersonated (`--auto-impersonate`); the vault owner is anvil account 0 (public dev key, fork only).
- `deploy/fork.params.env` holds test values. They are not measurements and must not be copied to `mainnet.params.env`.
- Broadcast artifacts go to `broadcast-fork/` (git-ignored, deleted at the end), never next to real deployments.
- The fork runs on the public RPC, which rate-limits. Prefer `MAINNET_RPC` with your own endpoint if it throttles.

## CRCL is left out of the dev vault, and why it matters
At this block the CRCL pool had in-range liquidity of 571,692 units for the whole Friday session: 800 USDC bought
0.0066 CRCL. The vault refused the 12-component deposit with `SlippageExceeded`, as designed. Depth appears only on
Saturday (liquidity 6.5e10 at 2026-11-07 18:00 UTC). The caps were derived from a sweep at block 54457318 (a Saturday),
so they describe the pool at that time. Pool depth is not stable, and the caps are an upper bound for a given state,
not a promise. The sweep was not repeated on other days.
