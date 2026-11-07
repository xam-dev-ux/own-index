# IndexVault: refusal policy and shape

## Principles
1. The vault trusts the oracle's verdict. It trades only against FRESH marks and never reclassifies a verdict. There is no setting to trade while stale.
2. A basket is atomic. One refusing component refuses the whole operation. A partly executed index is a mis-weighted index.
3. Withdrawal is never gated. `withdraw`, `withdrawAllInKind` and `depositInKind` do not touch the oracle, a router or a feed.
4. The vault has no knowledge of Builder Codes. Attribution is a calldata suffix added by whatever builds the transaction. Tests show the suffix is inert for dynamic arrays, structs and proxied calls (test/CalldataSuffix.t.sol).

## Mapping from Mark to refusal
| Mark session | Mark cause | Refusal kind | Revert error |
|---|---|---|---|
| FRESH | NONE | none | |
| CLOSED | WEEKEND, HOLIDAY, EARLY_CLOSE | MARKET_CLOSED | `MarketClosed(token, cause)` |
| STALE_IN_SESSION | AWAITING_FIRST_PRINT | AWAITING_FIRST_PRINT | `AwaitingFirstPrint(token)` |
| STALE_IN_SESSION | FEED_NOT_UPDATING, HEARTBEAT_EXCEEDED | FEED_FAULT | `FeedFault(token, cause)` |
| PAUSED | REGISTRY_PAUSED | CORPORATE_ACTION_PAUSE | `CorporateActionPause(token)` |
| UNKNOWN | FEED_INVALID, CALENDAR_NOT_LOADED, NOT_CONFIGURED | FEED_FAULT | `FeedFault(token, cause)` |
Added by the vault, not the oracle: MULTIPLIER_CHANGE_IMMINENT (a component's `effectiveAt()` inside the window), NO_DRIFT, TOO_SOON.

`AWAITING_FIRST_PRINT` has its own error because it is not a fault: it is stale and possibly wrong, expected after every reopen, and a dry refusal.

## Finding: a reverted call leaves no record
The original spec has `rebalance()` revert with `FeedNotFresh` and also record `RebalanceRefused` onchain. Both cannot happen in one call: a revert discards its logs and state. So there are two entry points:
- `rebalance` reverts with the specific error. Clean for simulation and for wallets, but a wallet that simulates first never sends it, so nothing reaches the chain.
- `tryRebalance` applies the same checks and, on refusal, does not revert. It increments `refusalCount`, emits one `RebalanceRefused` per offending component, and returns false. The traction dashboard, the "declined N times" figure and the demo refusal transaction all depend on this path.

## Deviations from the original spec (for review)
- Removed `Rules.requireFreshFeeds` and `Rules.maxStaleGapBps`. Trading on a stale mark is not offered, so the toggle and the gap cap have nothing to do.
- Replaced the string `reason` in `rebalanceStatus` with a structured `Refusal[]`.
- `deposit(usdc, swapCalldata)` is gated like a rebalance because it trades. `depositInKind` is not.

## Open decision: `maxImpactBps`
The vault cannot measure pool impact itself without reading the pool. The slippage check against the oracle price already bounds the executed price, impact included, within `maxSlippageBps` (hard cap 500). For thin pools (INTC, CRCL) a size cap per swap is a property of the pool. Options:
1. Drop `maxImpactBps`; rely on the oracle-referenced slippage bound.
2. A per-token swap-size cap held by the factory, immutable per deployment, derived from docs/liquidity-evidence.md. A new factory is needed to change it.
3. A per-token cap held by an operator-owned registry. Rejected unless needed: it gives the deployer a parameter that changes vault behaviour.
The fork check showed the single-range estimate understates impact at $1,000 and overstates it at $10,000, so any cap derived from it should be set knowing that.

## Not decided here
Valuation details, the drift calculation, and the swap-outcome validation arithmetic. They follow once the refusal shape is agreed.
