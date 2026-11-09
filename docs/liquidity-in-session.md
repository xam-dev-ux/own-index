# Depth during the session vs the block the caps came from

The caps in `docs/vault-design.md` come from a sweep at block 54457318, a Saturday. The same sweep at two Friday session
blocks (`data/impact_sweep_session.csv`) gives different answers. Criterion unchanged: largest swept size whose impact is
at most 50 bps (500 in the file's units), fee excluded, buy direction only.

| token | cap now (Sat block) | Fri 15:00 UTC | Fri 19:00 UTC | Mon 18:04 UTC (live) | minimum over the three session blocks |
|-------|--------------------:|--------------:|--------------:|--------------:|--------------------------------:|
| AAPL  | 50,000 (ceiling)    | 50,000 (ceiling) | 50,000 (ceiling) | 50,000 (ceiling) | 50,000 (ceiling) |
| AMZN  | 50,000 (ceiling)    | 50,000 (ceiling) | 50,000 (ceiling) | 50,000 (ceiling) | 50,000 (ceiling) |
| GOOGL | 50,000 (ceiling)    | 50,000 (ceiling) | 50,000 (ceiling) | 50,000 (ceiling) | 50,000 (ceiling) |
| META  | 50,000 (ceiling)    | 50,000 (ceiling) | 50,000 (ceiling) | 50,000 (ceiling) | 50,000 (ceiling) |
| MSFT  | 50,000 (ceiling)    | 20,000 | 50,000 (ceiling) | 50,000 (ceiling) | 20,000 |
| MSTR  | 50,000 (ceiling)    | 50,000 (ceiling) | 50,000 (ceiling) | 50,000 (ceiling) | 50,000 (ceiling) |
| NVDA  | 50,000 (ceiling)    | 30,000 | 30,000 | 50,000 (ceiling) | 30,000 |
| SNDK  | 50,000 (ceiling)    | 30,000 | 30,000 | 50,000 (ceiling) | 30,000 |
| SPCX  | 50,000 (ceiling)    | 30,000 | 30,000 | 50,000 (ceiling) | 30,000 |
| TSLA  | 50,000 (ceiling)    | 7,500  | 50,000 (ceiling) | 50,000 (ceiling) | 7,500 |
| INTC  | 5,000               | none: 500 USDC already costs 94 bps | none: 105 bps at 500 | 3,000 (37 bps at 500) | none |
| CRCL  | 10,000              | none: 500 USDC costs 99.9% | none | 30,000 (14.7 bps at 500) | none |

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

## Decision (2026-11-09)
Per-token caps are immutable per factory, so they are fixed at deploy. The sweep was repeated at a live Monday session
block (55285569, 18:04 UTC). The rule is the **minimum over the session blocks, never the Saturday block**. Result:

- AAPL, AMZN, GOOGL, META, MSTR: 50,000 (the sweep ceiling). MSFT 20,000. NVDA, SNDK, SPCX 30,000. TSLA 7,500.
- **INTC and CRCL leave the index (12 to 10 tokens).** At the Monday block both looked usable (INTC 37 bps at 500 USDC,
  CRCL 14.7 bps), but at the Friday session blocks INTC cost 94 to 105 bps at 500 and CRCL's in-range liquidity was
  almost nil. The same pools in two states. The cap has to protect against the bad state, and the rule exists so that a
  good block does not decide it. Three session blocks are still a small sample, which is why the rule is the minimum.
- The deployed caps are in `script/MainnetConfig.sol` and are checked by `make verify-mainnet`.

The size caps remain an upper bound for a pool state, not a promise of execution.
