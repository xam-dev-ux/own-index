# Own Index and WeekendMark: verified signatures

Checked against the deployed contracts on Base (chain id 8453) by calling each read function.

## SessionOracle `0x516A9C36E0D3f49Ed51E93cDa7B236D5A7a89951`

```solidity
struct Mark {
    int256 price;              // 8 decimals, Total Return Value, multiplier included
    uint8 session;             // 0 FRESH, 1 CLOSED, 2 STALE_IN_SESSION, 3 PAUSED, 4 UNKNOWN
    uint8 cause;               // see SKILL.md
    uint32 stalenessSecs;
    uint16 confidenceBps;
    uint64 timestampMs;
    uint8 divergenceStatus;    // 0 NO_SECONDARY .. 5 COMPARED
    int256 divergenceBps;
    int256 secondaryPrice;
    uint32 printLagSecs;
}
function markOf(address token) view returns (Mark);
function marksOf(address[] tokens) view returns (Mark[]);
function isFresh(address token) view returns (bool);
function openAt(uint256 t) view returns (bool open, uint8 cause);
function tokenCount() view returns (uint256);
function closureCount() view returns (uint256);
function gapCount(address token) view returns (uint256);
function snapshot(address token);   // permissionless, moves no funds
function snapshotAll();             // permissionless, moves no funds
```

## IndexVaultFactory `0xf41FA301b6B7A487f83C3fadaeD4DEC097d9d42a`

```solidity
function allowedTokens() view returns (address[]);
function vaultsOf(address owner) view returns (address[]);
function vaultCount() view returns (uint256);
function allVaults(uint256 offset, uint256 limit) view returns (address[]);
function createVault() returns (address vault);   // creates a vault owned by the caller
```

## IndexVault (each vault is a clone)

```solidity
function owner() view returns (address);
function totalValue() view returns (uint256 value, bool allFresh);
function currentWeights() view returns (uint16[]);
function rebalanceStatus() view returns (bool possible, (uint8 kind, address token, uint8 cause)[] refusals, uint64 nextEligibleAt, uint16 maxDriftBps);
function refusalCount() view returns (uint256);
function rebalanceCount() view returns (uint256);
function observeMultipliers();                     // permissionless
function withdrawAllInKind(address to);            // onlyOwner, unconditional exit
// onlyOwner and need swap calldata from the web app: deposit, rebalance, tryRebalance,
// depositInKind, withdraw, setComponents, setRules
```
