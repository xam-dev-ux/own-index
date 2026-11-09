# Build log

Two contracts for the Programmable Stock Markets track: **WeekendMark**, a price oracle that knows whether a market is open and keeps a public ledger of what weekends do to prices, and **Own Index**, self-custodial index vaults that refuse to trade against a price that is not fresh.

This is not a list of commits. It is what I found while building, and what I changed because of it. Where I was wrong, I say so.

## What the design reacted to

### 1. A single staleness threshold lies on weekends
My first idea was one number: a price older than N hours is stale. I measured it on 2026-11-07. A flat 26-hour threshold labels Friday's last print FRESH for the whole of Saturday, because it is less than 26 hours old. The market is closed and the price is a day old in every way that matters.

So freshness became two questions. *Is the market supposed to be open?* is answered by a calendar (weekly window plus declared holidays and early closes). *Is the feed delivering while it should?* is answered by a per-token silence threshold counted only in open time. The oracle now answers with a verdict (fresh, closed, stale in session, paused, unknown) and a cause, so a closed market and a broken feed are never the same answer.

### 2. These feeds print on movement, not on a clock
The feeds update on a 0.5% deviation or a 24-hour heartbeat. A flat stock can go hours without a print inside a session: AAPL printed at 19:58 UTC on 2026-11-06 and then nothing. A short global threshold would call that a fault. The threshold is therefore per token, and it is set from the measured distribution of gaps between prints, not guessed. That measurement runs on two pollers until 2026-11-09 16:00 UTC, which is why the mainnet parameters are still pending.

### 3. The first print after a reopen can be wrong
After a weekend the held price is not just old. News over the weekend can make it wrong, and the first print after the open can jump by several percent. I added a state for it, `AWAITING_FIRST_PRINT`, and made it a refusal with no degraded mode. It is shown as expected rather than as a fault, because right after a reopen it is exactly that.

### 4. A reverted call leaves no log
The original idea was that a refused rebalance both reverts and records `RebalanceRefused` on chain. A revert discards its own logs, so it cannot do both. There are two entry points. `rebalance` reverts with the specific error, which is right for simulation and wallets. `tryRebalance` runs the same checks, and on refusal records the reason and returns false. Both are fed by one internal evaluation, and a fuzz test checks that for every verdict they agree: `rebalance` reverts exactly when `tryRebalance` returns false.

### 5. My liquidity estimate was wrong, in two directions
I first estimated price impact from `slot0()` and `liquidity()` alone. Checked against real `pool.swap` calls on a fork, the estimate understated INTC at $1,000 (11.1 bps predicted, 14.5 real) and overstated it at $10,000 (109.7 predicted, 73.1 real). I had written that the method was optimistic at $10,000. That was wrong for these pools, and I corrected the note. Caps are now derived from real swaps, with the criterion fixed before looking at the data: the largest swept size with at most 50 bps of impact.

### 6. A cap that checks the net movement can be bypassed
The per-token size cap first compared the net change in a token's balance. A batch that buys and sells the same token in one transaction nets to almost nothing and passes. The check now uses gross movement per leg, summed in value at oracle prices.

### 7. I cannot read what the router will do
A vault cannot verify arbitrary router calldata. The fix was structural: a small adapter that is the vault's only counterparty, over exactly the ten pools I measured, with the pool-to-token correspondence checked in its constructor. The cap evidence then describes the pools the vault can actually reach, not just the pools I happened to look at.

### 8. I reasoned the wrong way about an unknown unit
B20 tokens expose `effectiveAt()` for a scheduled multiplier change. All 298 listed tokens return 0, so there is no live sample and I could not confirm its unit. I wrote that if the unit were milliseconds the vault would just refuse more, which is safe. That was backwards. `effectiveAt` is an instant, so a millisecond value looks like a date thousands of years away, the "imminent" check never fires, and the vault trades through a multiplier change. The failure is unsafe. The guarantee is now a unit-independent value check: if `uiMultiplier()` differs from the last observed value, or changed less than the settle window ago, the vault refuses. A plausibility rule on `effectiveAt` stays as an early warning only. A background watcher alarms the first time any token's `effectiveAt` becomes nonzero, so the unit can finally be read from a live sample.

### 9. The deploy script's own check proved nothing
At the end of a deployment script, reading state reads the simulation, not the chain. I learned this on a Sepolia rehearsal, where the simulation and the chain could have disagreed. Verification is a separate script that reads the deployed contracts from the chain. The rehearsal checked nine verdicts against the chain and they all matched. The mainnet deploy script refuses to run while any parameter is missing or still marked pending, and refuses to deploy without the Thanksgiving closures.

### 10. Thanksgiving, and a closure that cannot be undone
Closures are append-only. The oracle has no function to remove or shorten one. I had said a wide closure could be narrowed later; it cannot. And a half day left undeclared is not safely refused: a print from the early close still counts as fresh until the token's silence threshold runs out. So the closures are declared wide, the whole of 26 and 27 November, and that decision is final at deploy. The cost is availability on two days, never safety.

### 11. The Saturday block flattered the pools
My caps came from a sweep at a Saturday block. I re-ran it at two Friday session blocks and the picture changed. MSFT, NVDA, SNDK, SPCX and TSLA could move price by more than the 50 bps the cap was meant to bound. INTC cost 94 to 105 bps at $500, and CRCL's pool held in-range liquidity of 571,692 units, so 800 USDC bought 0.0066 CRCL, about 45 cents. At a third block, an hour before the window closed, both were usable again. So what the data shows is that pool depth varies a lot between blocks and that one block of any day is not a distribution. I did not find the cause. The cap table was rebuilt as the minimum over the session blocks, and INTC and CRCL left the index (items 13 and 14).

### 12. The interface showed me bugs the contract tests could not
Driving the interface against a mainnet fork found two. A deposit whose simulation passed ran out of gas when sent, because the gas estimate is too tight for eleven nested swaps; sends now carry 30% headroom. And the rebalance panel proposed nine trades of $1 to $19 when no weight had drifted past the threshold, which invites an action the vault would refuse. It now proposes trades only past the threshold.

### 13. Thresholds: the data could not support the number I wanted
I planned a per-token silence threshold from a high percentile of the gaps between prints. When the pollers ended, the data did not hold that: they covered 6 of the 12 tokens, one weekend and one Monday, and AAPL printed 5 times in the whole period. A percentile over that looks rigorous and is not. What the data does give is one hard observation: AAPL stayed silent for 13.5 hours with the market open (Monday 01:00 to 14:30 UTC). So the threshold is a single conservative bound, 14 hours of open time for all ten tokens, anchored on that observation and backed by the 24-hour heartbeat as the hard limit. It is not a measured percentile and I do not present it as one. The recorder can change it with `setThreshold` once weeks of data across several market regimes exist, without touching the gap ledger. A feed that updates on deviation and goes quiet is also telling you the price moved less than 0.5%, so silence is information, not only absence of it.

### 14. Twelve tokens became ten
A live Monday-session sweep (18:04 UTC) showed INTC and CRCL usable: 37 bps and 14.7 bps at 500 USDC. At two Friday session blocks the same pools cost 94 to 105 bps and almost nothing respectively. The rule fixed beforehand is the minimum over session blocks, so both leave the index; a good block does not say anything about the worst case. The caps that remain: MSFT 20,000, NVDA, SNDK and SPCX 30,000, TSLA 7,500, the other five at the sweep ceiling of 50,000, which is where measurement stopped. With ten tokens the development vault deposits 8,000 USDC through the real pools with no slippage refusal, which the twelve-token vault could not.

### 15. A calendar that stops where my knowledge stops
`CALENDAR_CONFIRMED_UNTIL` is 2026-12-24, not March. I declared Thanksgiving and nothing later, and with a 14-hour silence threshold an undeclared holiday could read FRESH for hours: the vault would trade against a day-old price on a closed market. So the oracle is told not to claim a calendar it has not loaded; past the date it answers "calendar not loaded" and the vaults refuse. That is a deliberate decision, not a limitation: it is the same rule as everywhere else, refuse rather than guess. It does create a dated obligation. On 2026-12-24 the oracle refuses everything unless Christmas and New Year closures are declared and the horizon is extended. Safe, but a cliff. `scripts/check_calendar_horizon.sh <oracle>` exits 1 when fewer than 14 days remain; it must run on a schedule from early December, because on the day nobody will remember this was decided on 2026-11-09.

### 16. The divergence states, against real prints
`COMPARED` and `PRINTS_TOO_FAR_APART` had only been seen with mocks. `test/SessionOracle.realprints.fork.t.sol` forks four historical blocks of Monday 2026-11-09, deploys the oracle with the mainnet parameters, and reads the real Chainlink prints. GOOGL prints 410 s apart compare at 28 bps (the 24/7 price 0.29% above the 24/5 price); TSLA at 356 s compares too; GOOGL at 3,942 s and TSLA at 4,769 s apart are reported as lag, not disagreement, with both verdicts still FRESH. Each test first asserts that the chain holds the same print times the poller recorded. It is four blocks of one day, not a distribution, but the mechanism now ran on real data.

### 17. A close offset I inferred needs a way back
The weekly window's open offset was measured once (Monday 01:00 UTC); the close offset (Saturday 01:00 UTC) is inferred, since quiet feeds cannot show a close. It is reconfigurable by the recorder with `setWindow`, and `make fork-setwindow` proves it on the fork: a deliberately wrong close turns the real oracle's verdict to CLOSED, correcting it turns it back to FRESH, no redeploy. A mistake in the window would still produce wrong verdicts until the recorder notices, so the first Friday close after deployment is the real test.

### 18. Deployed, and read back from the chain
The three contracts went to Base mainnet on 2026-11-09 (blocks 55289704 to 55289762, 0.000058 ETH). `make verify-mainnet` read them from the chain, not from the deployment script, and matched every check; the dry run's addresses were identical because an address depends only on the deployer and its nonce. The interface, built against those addresses, read the real oracle: all ten tokens FRESH during the Monday session, the 24/7 feeds shown as "not comparable new" for their first hour. A fault shown on screen would have been a real one. The source of all four contracts (the three plus the vault implementation the factory creates) was then verified on BaseScan.

### 19. The first real deposit failed, and the simulation said it would not
A deposit of 0.01 USDC sent from the web app reverted on mainnet (transaction 0x8bb190b1…f12b, block 55307051), using 557,326 gas of a limit of 869,921. An `eth_call` of the exact same calldata, with and without the Builder Code suffix, at the previous block and at the latest, passed. A trace of the real transaction (`cast run`) ended inside the AAPL pool's hook: `afterSwap` reverted with the two-letter message `IG`. Replayed on a fork of the previous block, every gas limit up to 869,921 failed with the identical gas used, and every limit from 875,000 up succeeded, using 573,890. So the swap reverts when the transaction has too little gas left, although it uses far less than the limit, and a simulation, which runs with a huge gas allowance, cannot show it. A second failed deposit (block 55313080, limit 884,071) confirmed the rule: replayed on a fork it fails at 884,071 and succeeds at 1,000,000, using 584,291. In both cases the limit has to exceed the gas the call actually uses by roughly 300,000. The priority fee has no effect: tips from 1 wei to 30 million wei gave the same result. The estimate the web app obtained (about 669,000) was below the true threshold, and 30% headroom put the limit just under it. I did not read the hook's source, so I do not know what `IG` stands for; the behaviour is a revert that depends on the gas limit. Funds were never at risk: the transaction reverted whole. The app now sends the estimate plus 30% plus 400,000 gas; unused gas is refunded. This is the failure mode item 12 found on a fork with a different symptom, and it is the second time a real chain disagreed with a passing simulation. The contracts cannot change, so any other client has to give deposits the same headroom.

## Limits I know about
- **Caps are an upper bound for a pool state, not a promise.** Depth moved between blocks. The sweep is a single block per sample, buy direction only, and ignores the dynamic fee and the MEV-tax module on these pools.
- **The unit of `effectiveAt` is assumed, not observed.** Seconds is what the documentation says. It is mitigated by the value check but not verified live.
- **The silence threshold is a bound, not a percentile** (item 13), and the comparison window, heartbeat margin and multiplier window are chosen values, not fitted ones. They are marked as such in `deploy/mainnet.params.env`.
- **The size cap is only as good as its sample.** Several tokens sit at the sweep ceiling of $50,000, which is where measurement stopped, not a limit I measured.
- **The weekend gap ledger needs a real weekend.** A fork produces no new prints, so the ledger is empty until mainnet has a reopen.
- **Slippage is checked on the whole batch, not per swap.** A bad single leg inside a good batch can hide under the batch tolerance.
- **The Base block gas limit was not checked.** A 10-leg batch measured 4.86 million gas on the fork, and I make no claim about headroom.
- **The contracts are not audited.**

## What the fork now proves
A local fork of Base is pinned at a session block, with the whole system deployed. The real oracle classifies every state on screen, not just text I wrote: fresh, closed on a weekend, paused (through a mock registry that replaces the real one on the fork), feed not updating after three hours, and awaiting first print after a Monday reopen. A deposit, a refused rebalance recorded on chain, and a withdrawal with the market closed all run through the interface.

## Still to do
- The close-of-week offset is inferred (Friday 20:00 ET), not measured; the open offset was measured once, in winter time.
- A scheduled check of the calendar horizon, due early December (item 15). `scripts/check_calendar_horizon.sh` exists; running it on a schedule does not yet.
- The first week of public data, the first real weekend in the gap ledger, and the scheduled calendar check.
