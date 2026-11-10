# Submission: WeekendMark and Own Index

Base Builder Quest, Stocks Maxxing Season, Programmable Stock Markets track.
Repository: https://github.com/xam-dev-ux/own-index

## What this is
Two contracts for tokenized stocks on Base.

- **WeekendMark** (`SessionOracle`) turns a Chainlink equity feed into a verdict: is this price usable right now, and if not, why. A weekend, a holiday or an early close is reported as closed, which is normal. A feed that goes quiet while the market is open is reported as a fault, which is not. It also keeps a public, onchain ledger of how far each price moved across every closure.
- **Own Index** is a factory of self-custodial index vaults. The owner picks components and weights. The vault refuses to trade against any price that is not fresh, says exactly why, and can always be emptied in kind.

It is not a fund: no pooled token, share or NAV, no fees, no advice, nothing managed for anyone. WeekendMark is reference data and is explicitly not a liquidation oracle. The contracts are not audited.

## Deployed on Base mainnet (2026-11-09), source verified on BaseScan
| Contract | Address |
|---|---|
| SessionOracle | [0x516A9C36E0D3f49Ed51E93cDa7B236D5A7a89951](https://basescan.org/address/0x516A9C36E0D3f49Ed51E93cDa7B236D5A7a89951#code) |
| SlipstreamAdapter | [0x6d6C9449862B0188c746e029069C05b1B59c7c04](https://basescan.org/address/0x6d6C9449862B0188c746e029069C05b1B59c7c04#code) |
| IndexVaultFactory | [0xf41FA301b6B7A487f83C3fadaeD4DEC097d9d42a](https://basescan.org/address/0xf41FA301b6B7A487f83C3fadaeD4DEC097d9d42a#code) |
| IndexVault (clone implementation) | [0xD07E6e32f91Cf70c14A30B2bAeB5D7103f23bCe7](https://basescan.org/address/0xD07E6e32f91Cf70c14A30B2bAeB5D7103f23bCe7#code) |

`make verify-mainnet` reads the deployed contracts from the chain (not from the deploy script) and matched every check.

## Token set and size caps
Ten tokenized equities: AAPL, AMZN, GOOGL, META, MSFT, MSTR, NVDA, SNDK, SPCX, TSLA. It started as twelve. INTC and CRCL were removed after a measurement showed their pools were usable at one block and unusable at two others, and the rule fixed beforehand is the minimum over session blocks.

Caps are immutable and set in the factory: MSFT 20,000 USDC, NVDA, SNDK and SPCX 30,000, TSLA 7,500, the other five 50,000. Those five are the ceiling of the sweep, which is where measurement stopped, not a measured limit. A cap describes the state of a pool at the blocks measured; it is an upper bound, not a promise of execution. Evidence: `docs/liquidity-in-session.md`, `data/impact_sweep_session.csv`.

## What was tested, and against what
- 82 local tests (oracle, vault, adapter, calldata suffix) and 15 mainnet-fork tests with real feeds, real B20 tokens and real Slipstream pools.
- The oracle's comparison states (`COMPARED`, `PRINTS_TOO_FAR_APART`) run against real Chainlink prints from four blocks of 2026-11-09.
- A Base Sepolia rehearsal of the deployment flow, read back from the chain: oracle verdicts and the vault side (adapter, factory, vaults, recorded refusals, in-kind withdrawal), over mocks.
- A web app that drives all of it, checked against a mainnet fork and against the live deployment: all ten tokens read FRESH during the 2026-11-09 session.

## Decisions that came from evidence (full account in BUILD-LOG.md)
- One staleness threshold lies on weekends, so freshness became two questions: is the market supposed to be open (a calendar), and is the feed delivering while it should (a silence threshold counted in open time).
- A reverted call leaves no log, so a refusal has two entry points: `rebalance` reverts with the reason, `tryRebalance` records it onchain. A fuzz test checks they always agree.
- My liquidity estimate was wrong in both directions against real swaps, and I said so. Caps come from real `pool.swap` calls.
- The calendar is confirmed only until 2026-12-24, on purpose: the oracle refuses to claim a calendar it has not loaded.
- The silence threshold is one conservative bound (14 h of open time), not a percentile, because the data could not support a percentile.

## Limits, stated plainly
- The weekly-window close offset is inferred, not measured; the recorder can correct it with `setWindow`, proven on a fork.
- The unit of `effectiveAt()` is assumed (seconds) and not observed on a live token. Safety does not depend on it: a vault refuses if `uiMultiplier()` changed.
- Slippage is checked on the batch, not per swap. Sell-direction impact, the dynamic fee and the MEV-tax module were not measured. The Base block gas limit was not checked against the worst case.
- The gap ledger only fills with real weekends. TO FILL: first recorded gap, with transaction.
- Onchain activity so far: one vault created through the web app, [0xecc1692c68917127f9c1f7a207a4038871161cc0](https://basescan.org/address/0xecc1692c68917127f9c1f7a207a4038871161cc0), by wallet 0x85e7FC9c7E3834d9bE8d60d1e3718a24d1F96678, in transaction [0xceb12e2e…171d7e](https://basescan.org/tx/0xceb12e2e6c8b029d2b77160c72a6d04c5e1925c86934f16f328332f360171d7e) (block 55292580, 2026-11-09). That wallet is the author's own, not an independent user. The call carries the ERC-8021 Builder Code suffix. The first successful deposit into it: 0.01 USDC for AAPL through the adapter and the real Slipstream pool, transaction [0x698db910…bf07](https://basescan.org/tx/0x698db910f77e78ebcbdd95e196be185d56124ea361ea3f48e2af500e1db6bf07) (block 55752870, gas limit set by hand to 1,300,000, 573,876 used). Three earlier attempts reverted, and the cause is in BUILD-LOG item 19. TO FILL: the first `snapshotAll` calls.

## Prior work
`src/BaseTimeLib.sol`, its mock and its tests come from BaseTimeKit and are **code that existed before the Quest Period**. They give the millisecond clock of the BaseTime predeploy. Everything else in the repository was written during the Quest Period.

## Build in public
TO FILL: links to posts. BUILD-LOG.md is the written account of what the design reacted to, including where I was wrong.

## Eligibility
Own Index is software. The web app asks each visitor to attest that they are allowed to hold tokenized equities where they live. There is no geographic block, and no restricted jurisdiction has been identified for this project.
