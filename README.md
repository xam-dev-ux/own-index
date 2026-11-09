# Own Index and WeekendMark

Two contracts for tokenized stocks on Base.

- **WeekendMark** (`SessionOracle`) turns a Chainlink equity feed into a *verdict*: is this price usable right now, and if not, why? It tells a closed market (a weekend, a holiday, an early close) apart from a feed that has gone quiet while it should be updating. It also keeps a public ledger of how far each price moved across every closure.
- **Own Index** is a factory of self-custodial index vaults. You choose the components and weights. The vault refuses to trade against any price that is not fresh, and says exactly why.

Status: the contracts and the web app are built and tested, on ten tokenized equities (AAPL, AMZN, GOOGL, META, MSFT, MSTR, NVDA, SNDK, SPCX, TSLA). **Nothing is deployed to mainnet yet.** See [BUILD-LOG.md](BUILD-LOG.md) for what is pending and what the design had to react to.

## What it is not
- It is not a fund. There is no pooled token, share or NAV, and nobody manages anything for you.
- It gives no advice or recommendation. Weights, rules and timing are the owner's.
- WeekendMark is **not a liquidation oracle** and must not be used as one. It is reference data.
- There are no Own Index fees. The pools' own swap fees and price impact apply to every trade.
- The contracts are **not audited**.

## How it fits together

```
 Chainlink equity feeds (24/5)      Coinbase registry (pause flag)
 + "(24/7)" feeds for GOOGL/NVDA/TSLA            |
            \                                    |
             v                                   v
        +---------------- SessionOracle (WeekendMark) ----------------+
        |  calendar: weekly window + declared closures                |
        |  markOf(token) -> verdict + cause (never substitutes feeds) |
        |  public gap ledger, written by anyone through snapshot()    |
        +----------------------------+--------------------------------+
                                     | markOf
                                     v
 owner's wallet --> IndexVault (one per user, clone) --> SlipstreamAdapter --> Aero Slipstream pools
                      |  refuses unless every component is FRESH
                      |  per-token size cap (immutable, set in the factory)
                      |  batch slippage check against oracle prices
                      +--  withdrawAllInKind(): no oracle, no router, no feed
```

| Contract | Role | Owner |
|---|---|---|
| `SessionOracle` | Verdicts, calendar, gap ledger | A recorder address that can only change calendar and threshold configuration. It touches no funds. |
| `IndexVaultFactory` | Creates vaults as clones. Holds the oracle, the adapter, the settle window and the per-token caps, all immutable. | None |
| `SlipstreamAdapter` | The vault's only counterparty. Fixed pools, checked against the factory at construction. | None |
| `IndexVault` | One per user. Holds the components. | The user's wallet |

### Verdicts
| Verdict | Meaning | Vault |
|---|---|---|
| `FRESH` | Trading hours and a recent print | May trade |
| `CLOSED` | Weekend, holiday or early close (the cause says which) | Refuses. Normal |
| `STALE_IN_SESSION` | Open, but the feed is silent. `AWAITING_FIRST_PRINT` is the expected case right after a reopen | Refuses |
| `PAUSED` | Corporate action flagged by the registry | Refuses |
| `UNKNOWN` | Cannot be classified (invalid feed, calendar not loaded, not configured) | Refuses |

A refused call that reverts leaves no log, so there are two entry points: `rebalance` reverts with the specific error, and `tryRebalance` records `RebalanceRefused` on chain. They share one evaluation and a fuzz test checks that they agree.

## Run it

You need Foundry (the `base-forge` build is used here), Node 20 and an RPC for Base.

```bash
make test           # local suites: oracle, vault, adapter, calldata suffix
make test-fork      # mainnet-fork suites: real feeds, real B20s, real Slipstream pools
make setup-fork     # local Base fork at a session block with everything deployed and one vault loaded
cd web && npm install && npm run dev
```

`make setup-fork` writes `.fork/addresses.json`, which the web app reads. It uses an impersonated deployer and anvil's public dev account, with no keystore and no real key. More on it in [docs/fork-dev.md](docs/fork-dev.md).

Other fork targets:
- `make fork-weekend` jumps to Saturday and records a `MARKET_CLOSED` refusal.
- `make fork-states STAGE=pause|stale|reopen` makes the real oracle classify paused, fault and awaiting-first-print, in that order. Time only moves forward, so run `make setup-fork` afterwards.

Mainnet deployment, with the pending parameters guarded:

```bash
cp deploy/mainnet.params.env.example deploy/mainnet.params.env   # fill every value; the script refuses placeholders
make deploy-mainnet-dry                                          # simulation, no keystore
make deploy-mainnet                                              # prompts for the keystore password
make verify-mainnet ORACLE=0x... ADAPTER=0x... FACTORY=0x...     # reads the chain and fails on any mismatch
```

## Known limits and assumptions
- **Size caps are immutable and describe a pool state.** They come from real swaps on a fork, with a criterion fixed beforehand. Pool depth varies a lot between blocks, so a cap is an upper bound for the state it was measured in, not a promise of execution. See [docs/liquidity-in-session.md](docs/liquidity-in-session.md).
- **The unit of `effectiveAt()` is assumed to be seconds and has not been observed on a live token.** All 298 listed B20 tokens report 0 (nothing scheduled). The guarantee does not depend on it: a vault refuses if `uiMultiplier()` differs from the last observed value or changed less than the settle window ago. See [docs/vault-design.md](docs/vault-design.md).
- **The gap ledger needs a real weekend.** A fork produces no new prints.
- **The Thanksgiving closures cannot be removed once deployed.** They are declared wide on purpose.
- **Slippage is checked on the batch, not on each swap.**

More in [docs/](docs/): the Mark design, the vault's refusal policy and gates, the liquidity evidence, and the Sepolia rehearsal.

## Credits and prior work
- Stock tokens, feeds and their addresses follow the base-stocks documentation (the unit assumed for `effectiveAt()` comes from it).
- `src/BaseTimeLib.sol` and its mock and tests come from BaseTimeKit and are **code that existed before the Quest Period**. They give the millisecond clock of the BaseTime predeploy (`0x4200000000000000000000000000000000000030`).
- Swaps go through Aero Slipstream's router, with its own factory and pools.
- An optional ERC-8021 Builder Code suffix is added by the web client to every write. The contracts have no knowledge of it, and a test proves a suffix is inert for dynamic arrays, structs and proxy calls.

## Disclaimer
Own Index is software that lets you hold your own tokenized-equity positions in a vault you control. It is not an investment product, offers no advice or recommendation, pools no funds, issues no token or share, and manages nothing on your behalf. You can withdraw everything in kind at any time. Tokenized stocks may not be available to you depending on where you live, and you are responsible for checking whether you are eligible. WeekendMark is reference data and is explicitly not a liquidation oracle. Smart contracts can fail and these ones are not audited. Use at your own risk.
