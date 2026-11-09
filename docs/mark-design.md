# Mark: shape and policy

## Rules
1. The primary feed is never replaced. The secondary is reported next to it (`secondaryPrice`, `printLagSecs`, `divergenceBps`), so no state can look FRESH because a second feed covered a hole. There is no `source` flag because there is no substitution. If substitution is wanted later it is a new function with its own return type, not a mode of `markOf`.
2. Every non-FRESH verdict carries one `Cause`. Verdict says what to do; cause says why.
3. `CLOSED` is a correct state, not a fault. Divergence in a closed market is `NOT_COMPARABLE_CLOSED`, never read as an anomaly.

## Vault policy per verdict
| Verdict | Vault | Error |
|---|---|---|
| FRESH | proceeds | |
| CLOSED | refuses | `MarketClosed(token, cause)` |
| STALE_IN_SESSION | refuses | `FeedFault(token, cause)` |
| PAUSED | refuses | `CorporateActionPause(token)` |
| UNKNOWN | refuses | `FeedFault(token, cause)` |
Two refusal classes: "cannot value because the market is closed" and "cannot value because something is failing". `RebalanceRefused` records the cause.

## Calendar
- Classification resolves the schedule for the specific date. A half day (2026-11-27) has its own close time. It does not use a fixed schedule.
- The calendar carries `confirmedUntil`. A date at or before it with no override is a confirmed normal day, so an unloaded holiday cannot happen inside the horizon unless the RECORDER confirmed wrongly. A date beyond it is UNKNOWN with cause `CALENDAR_NOT_LOADED`, not STALE_IN_SESSION.
- Feed hours are not cash-market hours. Observed 2026-11-07: NVDA last printed 21:39 UTC Friday, after the 21:00 cash close; AAPL last printed 19:58 UTC, before it.

## Open question: the in-session threshold
Feeds update on a 0.5% deviation or a 24h heartbeat. A flat stock can legitimately go hours without a print inside a session (AAPL printed at 19:58 UTC and nothing after). A short in-session threshold would label that STALE_IN_SESSION. The threshold per token is therefore configurable and its default is not fixed until the Sunday and Monday data are in.

## Divergence
Compared only if all hold: secondary configured, market open, both feeds FRESH, both registered for longer than the comparison window, and the two prints are within the comparison window of each other. Otherwise the status says which condition failed. Feeds that print far apart report the lag, not a disagreement.

## AWAITING_FIRST_PRINT is stale and possibly wrong
After a closure the held print is not only old. News over the weekend (an earnings release, a futures move) can make it wrong, and the first print after the reopen can jump by several percent. A vault must refuse until the first print of the new session. There is no degraded-but-usable reading of this state.

## What the vault consumes
`markOf` reads live feed state, the registry pause flag and the calendar. It does not read the gap ledger (`gapsOf`, `inClosure`, `closePrint*`); `test_markOf_independent_of_ledger_state` enforces this. The snapshot cron produces evidence, not safety. A missed reopen costs a gap record, never a wrong verdict.

## Ledger fidelity
The feed exposes only its latest round. The recorded reopen print is the latest at observation time, so the quality of a `GapRecord` depends on how soon after the reopen `snapshot` is called. `observedAtMs` has 200 ms resolution and describes the observation, not the feed print, which has one-second resolution.

## Open test debt
`printLagSecs`, `COMPARED` and `PRINTS_TOO_FAR_APART` are also tested against real prints: `test/SessionOracle.realprints.fork.t.sol` (four blocks of Monday 2026-11-09). One day is not a distribution.
