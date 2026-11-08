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

## Decision: per-token swap cap, immutable per factory (`maxImpactBps` is replaced by it)
Chosen: option 2. A per-token cap on the value one component may move in a single operation, held by the factory, fixed in its constructor, with no setter and no owner. Options 1 (oracle-referenced slippage only) and 3 (deployer-owned registry) were rejected: slippage bounds the price but not the size, and the thin pools are the ones that need a size bound; a registry would let the deployer change the behaviour of vaults already deployed.

Calibration versus safety: the oracle threshold is a calibration (statistical, improves with data, `setThreshold`). The cap is a safety property derived from liquidity evidence; it is immutable so a user can verify it and nobody can weaken it afterwards.

**Assumed consequence, not a discovered limitation:** the cap reflects the liquidity at the factory's deployment. If liquidity of a pool changes materially, the remedy is a new factory and new vaults, not an adjustment.

### How the numbers are derived
Criterion (stated before reading the result): the largest swept size whose *real* swap price impact, fee excluded, is at most 50 bps, which is half the 100 bps eligibility gate. Data: `data/impact_sweep.csv`, produced by `docs/fork-check/ImpactSweep.t.sol`, real `pool.swap` on a fork pinned at block 54457318, sizes $500 to $50,000. The sweep ceiling is $50,000; a token that never reaches 50 bps by then gets the ceiling. **For those ten, $50,000 is where the measurement stopped, not a measured safe limit of the pool.** Nothing above $50,000 was measured because nothing needed it.

| Token | Real impact at largest size still under the criterion | Cap (USDC) |
|---|---|---|
| INTC | 46.3 bps at $5,000 ($7,500 gives 62.6) | 5,000 |
| CRCL | 48.2 bps at $10,000 ($15,000 gives 58.9) | 10,000 |
| the other ten | under 6 bps at $50,000 (largest MSTR 5.6) | 50,000 |

Limits of this evidence: one block, buy direction only (USDC in), not the sell direction; the fork is not the live chain. The cap for the ten deep pools is the edge of what was measured, not a property of the pool. Rounding down to a swept size is deliberate: the figures are measured points, not interpolations.

### Order of the gates
In `_checkOutcome` the per-component cap is checked inside the loop, and reverts hard, before the batch slippage is evaluated. They are two gates in series: a component over its cap refuses the whole batch even if the batch as a whole lost nothing (`test_impact_cap_exceeded_rolls_back_whole_batch` has zero aggregate loss and still reverts on the cap). The aggregate cannot dilute the cap.

The cap is compared against **gross** movement, not net. `executeTrade` reads each component's balance before and after every router call and sums the absolute value moved per leg, so buying $8,000 and selling $3,000 of the same component in one batch counts $11,000, not $5,000 (`test_buy_and_sell_of_same_component_do_not_cancel_in_the_cap`). This closes the hole without reading router calldata. A rule of one swap per component was considered and rejected: without interpreting the calldata the vault cannot know which component a swap names. Cost: two balance reads per component per leg.

### What the cap is compared against
The vault does not parse router calldata. After the router calls it values, at oracle prices, the balance change of each component and requires `moved <= cap` for each. Because that happens after the swaps, a breach reverts the whole batch (rolled back as a unit) and `tryRebalance` records it as `IMPACT_CAP_EXCEEDED`.

## Shared evaluation: the entry points cannot diverge
All pre-trade checks live in one internal `_evaluate(action)` returning the set of refusals. `rebalance` reverts with the first, `tryRebalance` records all of them, `rebalanceStatus` returns them. Post-trade checks (cap, slippage) live in one external-self-call `executeTrade`, used by `rebalance`, `tryRebalance` and `deposit`. `testFuzz_entry_points_agree` checks that for every session/cause combination `rebalance` reverts exactly when `tryRebalance` returns false and `rebalanceStatus` says not possible.

## Trading model and its caveats
- The vault calls only the factory's fixed router, with calldata supplied by the owner's client. It trusts none of it: approvals are granted for the batch and reset to zero, and the outcome is checked on balances at oracle prices.
- Slippage is enforced on the batch, not per swap: value lost must be at most `maxSlippageBps` of value bought. A bad single leg inside a good batch can hide under the batch tolerance.
- Rebalance drift is measured over component values only. USDC held in the vault is not part of the weights; initial buying uses `deposit(usdc, swaps)`.
- Withdrawal of everything skips a token whose transfer fails so one bad token cannot block the others; `withdraw(asset, ...)` reaches it individually.

## Open assumption: the unit of `effectiveAt()`
Verified on the live B20s (fork at block 54457318): the functions exist, `uiMultiplier()` is WAD-scaled, `toUIAmount` agrees with `balance * uiMultiplier / 1e18`. **Not verified: the unit of `effectiveAt()`.** All 298 listed tokens return 0 (nothing scheduled), so no live sample exists. It is assumed to be a unix timestamp in seconds, which is what base-stocks documents.

`effectiveAt` is an instant (when the change happens), not a duration, and the check is `effectiveAt - now <= window`. What happens if the unit is not seconds, **without any mitigation**:
- Milliseconds: the value is about 1000 times larger than `now` in seconds, the difference never fits in the window, and the refusal never fires. The vault would trade through a multiplier change without warning. **Unsafe.**
- A block number or any smaller scale: the value is in the past relative to `now`, so it is ignored. **Unsafe.**
Both unit errors fail in the unsafe direction. An earlier version of this section said the milliseconds case "refuses more"; that was wrong (it treated the instant as a duration).

Two defences, neither of which relies on the unit being right:
1. Plausibility: any nonzero `effectiveAt` outside 1.6e9..1e11 is treated as an imminent change and the vault refuses (`test_effectiveAt_in_an_unexpected_unit_refuses_instead_of_trading`). Covers milliseconds and block numbers. A block number would only enter the plausible range after about 1.6 billion blocks.
2. Value check, independent of `effectiveAt` entirely: the vault keeps the last observed `uiMultiplier()` per token. If the current value differs, or it changed less than `multiplierWindowSecs` ago, it refuses with `MULTIPLIER_CHANGED` (`test_multiplier_value_change_refuses_without_effectiveAt`, which never sets `effectiveAt`). `tryRebalance` and the permissionless `observeMultipliers()` persist the observation and start the settle window; `rebalance` refuses on any unacknowledged difference, so the two entry points agree (the fuzz covers it). This catches a change that already happened and one that was never scheduled. The settle window reuses `multiplierWindowSecs` and is provisional like it.

Hierarchy: the value check is the guarantee, the plausibility rule on `effectiveAt` is the early notice (it refuses before the change, the value check only after). If one had to go, the plausibility rule goes, never the value check. The value check assumes no unit, but it is not unconditional:
- It has a baseline: a token first seen after its multiplier already moved is baselined at the moved value.
- The settle window starts when the change is *observed* (by `tryRebalance` or `observeMultipliers`), not when it happened; a change nobody observed is still refused by the value difference, but the settle time only begins at the first observation.
- A token whose `uiMultiplier()` cannot be read is not guarded by it.
- Whether `multiplierWindowSecs` is long enough for the price feed to catch up with a new multiplier is itself an assumption, not measured.

The scheduled-change warning (`effectiveAt`) is therefore only an early notice; safety does not depend on it. The risk is also dormant while no change is scheduled. `scripts/scan_pending_multiplier.sh` exits 1 and prints the raw value the first time any of the 12 tokens has one: that sample closes the unit question. Copy this section to the README.

## Other unverified assumptions
- The B20 selectors the vault reads: `effectiveAt()` for the multiplier-change window and `uiMultiplier()` for display. Written from the interface notes, not yet executed against the live precompile.
- The router the factory is deployed with, and its calldata, are not chosen yet. Tests use a mock router.
- `multiplierWindowSecs` is a constructor value, not yet chosen.

## Not decided here
Router choice and calldata construction (client side), `multiplierWindowSecs`, and the sell-direction impact sweep.
