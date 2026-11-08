#!/usr/bin/env bash
# One command: a local Base fork with the whole system live, for UI development. Fork only: nothing here touches
# mainnet, no keystore, no private key. Anvil impersonates the deployer and uses its own public dev account as owner.
#   scripts/setup_fork.sh          start (or restart) the fork and set everything up
#   scripts/setup_fork.sh stop
set -euo pipefail
cd "$(dirname "$0")/.."
RPC=${FORK_RPC:-http://127.0.0.1:8545}
UPSTREAM=${MAINNET_RPC:-https://mainnet.base.org}
# Fri 2026-11-06 15:00 UTC (US market open): the real feeds are in session, so the oracle reads FRESH.
FORK_BLOCK=${FORK_BLOCK_SESSION:-53934124}
DEPLOYER=0x8F058fE6b568D97f85d517Ac441b52B95722fDDe
OWNER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
USDC=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
FORGE=${FORGE:-base-forge}; CAST=${CAST:-base-cast}; ANVIL=${ANVIL:-base-anvil}
mkdir -p .fork

stop() {
  if [ -f .fork/anvil.pid ]; then
    pid=$(cat .fork/anvil.pid)
    if [ -d "/proc/$pid" ] && tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q anvil; then kill "$pid"; sleep 1; fi
    rm -f .fork/anvil.pid
  fi
}
[ "${1:-}" = stop ] && { stop; echo "fork stopped"; exit 0; }

stop
$ANVIL --fork-url "$UPSTREAM" --fork-block-number "$FORK_BLOCK" --chain-id 8453 --auto-impersonate --port "${RPC##*:}" --silent > .fork/anvil.log 2>&1 &
echo $! > .fork/anvil.pid
for _ in $(seq 1 40); do $CAST block-number --rpc-url "$RPC" >/dev/null 2>&1 && break; sleep 1; done
$CAST block-number --rpc-url "$RPC" >/dev/null || { echo "anvil did not start, see .fork/anvil.log"; exit 1; }

# The broadcast artifacts of this run must never sit next to real deployments (they carry chain id 8453).
export FOUNDRY_BROADCAST=broadcast-fork
rm -rf broadcast-fork

# 1. oracle + adapter + factory, with the FORK-ONLY parameters
set -a; . deploy/fork.params.env; set +a
out=$($FORGE script script/DeployMainnet.s.sol --rpc-url "$RPC" --broadcast --unlocked --sender $DEPLOYER 2>&1) || { echo "$out"; exit 1; }
addr() { echo "$out" | grep -E "^ *$1 " | awk '{print $NF}' | tail -1; }
ORACLE=$(addr SessionOracle); ADAPTER=$(addr SlipstreamAdapter); FACTORY=$(addr IndexVaultFactory)
[ -n "$ORACLE" ] && [ -n "$ADAPTER" ] && [ -n "$FACTORY" ] || { echo "$out"; echo "could not read addresses"; exit 1; }

# 2. test USDC for the owner: write the balance slot (FiatToken balances mapping is slot 9), then check it took
slot=$($CAST index address $OWNER 9)
$CAST rpc anvil_setStorageAt $USDC "$slot" 0x$(printf '%064x' 100000000000) --rpc-url "$RPC" >/dev/null
bal=$($CAST call $USDC "balanceOf(address)(uint256)" $OWNER --rpc-url "$RPC" | awk '{print $1}')
[ "$bal" = 100000000000 ] || { echo "USDC funding failed (balance $bal)"; exit 1; }

# 3. vault, components, deposit through the real pools, one recorded refusal
export FACTORY_ADDRESS=$FACTORY
$FORGE script script/SetupForkVault.s.sol --rpc-url "$RPC" --broadcast --unlocked --sender $OWNER > .fork/vault.log 2>&1 || { cat .fork/vault.log; exit 1; }
VAULT=$($CAST call $FACTORY "vaultsOf(address)(address[])" $OWNER --rpc-url "$RPC" | tr -d '[]' | awk -F', ' '{print $NF}')

cat > .fork/addresses.json <<J
{
  "chainId": 8453,
  "rpc": "$RPC",
  "forkBlock": $FORK_BLOCK,
  "owner": "$OWNER",
  "oracle": "$ORACLE",
  "adapter": "$ADAPTER",
  "factory": "$FACTORY",
  "vault": "$VAULT",
  "usdc": "$USDC"
}
J
rm -rf broadcast-fork
echo "fork ready at $RPC (block $FORK_BLOCK, Fri 2026-11-06 15:00 UTC). Addresses: .fork/addresses.json"
cat .fork/addresses.json
echo "vault refusals: $($CAST call "$VAULT" 'refusalCount()(uint256)' --rpc-url "$RPC")  rebalances: $($CAST call "$VAULT" 'rebalanceCount()(uint256)' --rpc-url "$RPC")"
echo "oracle verdict AAPL: $($CAST call "$ORACLE" 'markOf(address)((uint8,uint8,int256,uint32,uint16,uint8,int256,uint32,int256))' 0xb200000000000000000000C2e324d24d7eEcd1fb --rpc-url "$RPC" 2>&1 | head -c 200)"
