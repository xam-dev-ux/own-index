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
