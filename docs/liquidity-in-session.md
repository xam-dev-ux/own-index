# Depth during the session vs the block the caps came from

The caps in `docs/vault-design.md` come from a sweep at block 54457318, a Saturday. The same sweep at two Friday session
blocks (`data/impact_sweep_session.csv`) gives different answers. Criterion unchanged: largest swept size whose impact is
at most 50 bps (500 in the file's units), fee excluded, buy direction only.

| token | cap now (Sat block) | Fri 15:00 UTC | Fri 19:00 UTC | lower of the two session blocks |
|-------|--------------------:|--------------:|--------------:|--------------------------------:|
| AAPL  | 50,000 (ceiling)    | 50,000 (ceiling) | 50,000 (ceiling) | 50,000 (ceiling) |
| AMZN  | 50,000 (ceiling)    | 50,000 (ceiling) | 50,000 (ceiling) | 50,000 (ceiling) |
| GOOGL | 50,000 (ceiling)    | 50,000 (ceiling) | 50,000 (ceiling) | 50,000 (ceiling) |
| META  | 50,000 (ceiling)    | 50,000 (ceiling) | 50,000 (ceiling) | 50,000 (ceiling) |
| MSFT  | 50,000 (ceiling)    | 20,000 | 50,000 (ceiling) | 20,000 |
| MSTR  | 50,000 (ceiling)    | 50,000 (ceiling) | 50,000 (ceiling) | 50,000 (ceiling) |
| NVDA  | 50,000 (ceiling)    | 30,000 | 30,000 | 30,000 |
| SNDK  | 50,000 (ceiling)    | 30,000 | 30,000 | 30,000 |
| SPCX  | 50,000 (ceiling)    | 30,000 | 30,000 | 30,000 |
| TSLA  | 50,000 (ceiling)    | 7,500  | 50,000 (ceiling) | 7,500 |
| INTC  | 5,000               | none: 500 USDC already costs 94 bps | none: 105 bps at 500 | none |
| CRCL  | 10,000              | none: 500 USDC costs 99.9% | none | none |

"Ceiling" means the sweep stopped there, not that a limit was measured.

## What this does and does not show
- It shows the Saturday-block caps overstate the depth available at two Friday session blocks for MSFT, NVDA, SNDK,
  SPCX, TSLA, INTC and CRCL. With the current caps, a full-size leg on those tokens can move price by more than the
  50 bps the cap was meant to bound. The batch slippage check still bounds loss against the oracle price; only the
  per-token cap loses its stated meaning.
- It does **not** show that depth leaves when the market opens. Three blocks are three samples. At a third block
  (54096122, Fri 19:00 ET, still inside the weekly window) INTC and CRCL were already usable (41 and 31 bps at 5,000), so
  the change happened inside the Friday session or at its end, and the cause (a liquidity provider adding or moving
  range) is not observed. Depth varies a lot between blocks; one block of any day is not a distribution.
- The sweep is a single block per sample and ignores the dynamic fee and MEV tax module.

## Decision pending
Per-token caps are immutable per factory, so they are fixed at deploy. Options: re-run the sweep at more in-session blocks
(including the live Monday session, with the pollers' data) and take the lower value per token; drop INTC and CRCL from the
index if they stay unusable in session. Not decided here.
