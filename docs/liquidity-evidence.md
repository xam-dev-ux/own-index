# Liquidity measurement, 2026-11-07

Method: `scripts/measure_impact.py`. For each token with a Chainlink feed and a minted B20, find USDC pools in the Aero CL factory (`0x9CB22058...7a76`) and the older CL factory (`0xf8f2eB49...61Ef`), take the pool with the most USDC, and compute the price impact of a USDC -> token swap from `slot0()` and `liquidity()`. Output: `data/impact.json`.

The standard Aerodrome QuoterV2 reverts on these custom-factory pools, so it is not used.

## Limits of the method

- Single-range approximation: current in-range liquidity is assumed for the whole trade; tick crossings are ignored. Not yet cross-checked against a swap (fork simulation pending).
- Impact excludes the pool fee.
- Reliable at $100 and $1,000. Optimistic at $10,000.

## Eligibility gate

The gate is **price impact under 1% at a $1,000 swap**. "Passes" means passes at that size only.

At $10,000, INTC (109.6 bps) and CRCL (51.5 bps) are not within the gate by this method, and INTC is above 1%. Their only pools hold about $108k and $107k USDC.

Per-swap size limits for pools like these are a property of the pool and are enforced in the contract validation layer (`maxImpactBps`), not in the UI.

## COIN

A Chainlink feed for COIN exists, but no COIN token appears in the Coinbase API. It is excluded from the oracle registry until a token exists.

## Fork verification (block 54457318)

`docs/fork-check/ImpactCheck.t.sol` executes a real `pool.swap` on a `base-forge` fork of Base mainnet pinned at block 54457318 and compares the output with the single-range prediction computed from the same block's `slot0()` and `liquidity()`. B20 transfers ran on the real precompile; no mock code was etched.

`impact.json` did not record its source block, so the comparison is made inside the fork block, not against the earlier file. The figures below are a property of the pool state at that block, not a live-chain execution. They are not validated for production.

Impact vs spot, fee excluded, in bps:

| Pool | Size | Real swap | Single-range prediction |
|---|---|---|---|
| INTC | $100 | 1.2 | 1.2 |
| INTC | $1,000 | 14.5 | 11.1 |
| INTC | $10,000 | 73.1 | 109.7 |
| CRCL | $1,000 | 5.2 | 5.2 |
| CRCL | $10,000 | 48.2 | 51.6 |
| AMZN | $1,000 | 0.1 | 0.1 |

At $1,000 the approximation understated INTC impact by 3.4 bps (optimistic direction). INTC total cost at $1,000 is about 14.5 bps plus the 5 bps fee, against the 100 bps gate. At $10,000 the approximation overstated impact (pessimistic), because liquidity deepens beyond the current tick. The earlier statement that the method is optimistic at $10k was wrong for these pools.
