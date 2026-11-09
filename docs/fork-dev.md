# Local fork for UI development

`make setup-fork` starts a Base fork at block 53934124 (Fri 2026-11-06 15:00 UTC, US session open), deploys oracle,
adapter and factory with `deploy/fork.params.env`, funds anvil's first dev account with test USDC, creates a vault,
sets the 10 components at 10% each, deposits 8,000 USDC through the real Slipstream pools and records one `NO_DRIFT` refusal.
Addresses go to `.fork/addresses.json`. `make stop-fork` stops it. No keystore, no private key, nothing touches mainnet.

- Deployer is impersonated (`--auto-impersonate`); the vault owner is anvil account 0 (public dev key, fork only).
- `deploy/fork.params.env` holds test values. They are not measurements and must not be copied to `mainnet.params.env`.
- Broadcast artifacts go to `broadcast-fork/` (git-ignored, deleted at the end), never next to real deployments.
- The fork runs on the public RPC, which rate-limits. Prefer `MAINNET_RPC` with your own endpoint if it throttles.

## The dev vault holds all ten components
INTC and CRCL were dropped from the index (docs/liquidity-in-session.md). At this Friday session block their pools were nearly
empty and a 12-component deposit was refused with `SlippageExceeded`, as designed. With the ten remaining tokens the
deposit goes through cleanly: 7,998 USDC of value, every component FRESH. The caps are an upper bound for a pool state,
not a promise of execution.
