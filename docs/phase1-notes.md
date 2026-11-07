# Phase 1 design notes

## Decisions already made
- Session classification: market calendar for open/closed, short threshold for failure inside a session. States: FRESH, CLOSED, STALE_IN_SESSION, PAUSED, UNKNOWN. A flat 26h threshold labels Friday prices FRESH all Saturday (measured 2026-11-07).
- Holiday list is updatable by RECORDER, bounded; documented as the only maintained piece. Needed for the window: 2026-11-26 (closed), 2026-11-27 (half day), 2026-12-25.
- `secondaryFeed` per token and `divergenceBps` on `Mark`. Chainlink publishes separate "(24/7)" feeds for GOOGL, NVDA and TSLA.
- A feed registered late has no history. `divergenceBps` must not fire because of a feed's own novelty: compare only when both feeds have a print inside the comparison window; otherwise report no divergence data, not zero.
- `configureToken(token, feed)` requires a token, so an orphan feed (COIN) cannot be registered.
- Multiplier API: `uiMultiplier()`, `newUIMultiplier()`, `effectiveAt()`. A scheduled multiplier change within a window is a refusal reason in the vault.

## maxImpactBps
Fork check (docs/liquidity-evidence.md): the single-range estimate understates impact at $1,000 (INTC by 3.4 bps) and overstates it at $10,000 (INTC 109.7 vs 73.1 real). Calibrating the cap with that estimate caps thin pools more strictly than necessary. That is acceptable for a safety limit, but is a decision to take knowingly.

## Builder Code (ERC-8021)
Optional field until the spec has been read. Not a `require`.

## Open items
- Poller CSVs already carry the block number per row. `scripts/measure_impact.py` did not record its block; fixed to stamp it on the next run.
- Spain eligibility and Builder Code registration: owner's.
