#!/usr/bin/env bash
# Local fork only. Produces states the fork does not show on its own, so the REAL oracle classifies them and the UI shows
# what it classified (not text we wrote). Time only moves forward, so run the stages in this order, once each:
#   pause    swap the oracle's registry for a mock and pause AAPL      -> PAUSED
#   stale    jump 3 h inside the session                               -> STALE_IN_SESSION / FEED_NOT_UPDATING
#   reopen   thresholds to 12 h, jump to Monday 01:10 UTC              -> STALE_IN_SESSION / AWAITING_FIRST_PRINT
# Afterwards run `make setup-fork` to get a clean fork. The deployer is impersonated by the fork; no key is involved.
set -euo pipefail
cd "$(dirname "$0")/.."
RPC=${FORK_RPC:-http://127.0.0.1:8545}; CAST=${CAST:-base-cast}; FORGE=${FORGE:-base-forge}
J=.fork/addresses.json
[ -f "$J" ] || { echo "no $J: run make setup-fork first"; exit 1; }
[ -n "$($CAST rpc anvil_nodeInfo --rpc-url "$RPC" 2>/dev/null)" ] || { echo "not an anvil fork at $RPC"; exit 1; }
get() { python3 -c "import json;print(json.load(open('$J'))['$1'])"; }
ORACLE=$(get oracle); DEPLOYER=0x8F058fE6b568D97f85d517Ac441b52B95722fDDe
AAPL=0xb200000000000000000000C2e324d24d7eEcd1fb
TOKENS="$AAPL 0xb200000000000000000000d9192b6B456483C2E8 0xb2000000000000000000002D0BA3164cc74f58B7 0xb2000000000000000000008bC8786B856E61707C 0xB200000000000000000000Ab99cFa739E253872B 0xb2000000000000000000004884b426556b92883d 0xb20000000000000000000078ee7ce2fE4908108C 0xb200000000000000000000397293Cb8cda9a10c5 0xb2000000000000000000007b9fcbd005511aCBd5 0xb2000000000000000000001e800a7f5189430cD0 0xB2000000000000000000004AFF16039bA04bdFBc 0xB20000000000000000000019f6E7C675b73C2e4D"
jump() { $CAST rpc evm_setNextBlockTimestamp "$1" --rpc-url "$RPC" >/dev/null; $CAST rpc evm_mine --rpc-url "$RPC" >/dev/null; }
now() { $CAST block latest -f timestamp --rpc-url "$RPC"; }
show() { for t in $AAPL 0xb200000000000000000000d9192b6B456483C2E8; do $CAST call "$ORACLE" 'markOf(address)((int256,uint8,uint8,uint32,uint16,uint64,uint8,int256,int256,uint32))' $t --rpc-url "$RPC" 2>/dev/null | tr -d '\n' | cut -c1-110; echo; done; }
case "${1:-}" in
  pause)
    REG=$($FORGE create src/testing/MockFeed.sol:MockRegistry --rpc-url "$RPC" --unlocked --from $DEPLOYER --broadcast 2>/dev/null | awk '/Deployed to/{print $3}')
    [ -n "$REG" ] || { echo "could not deploy the mock registry"; exit 1; }
    $CAST send "$ORACLE" "setRegistry(address)" "$REG" --from $DEPLOYER --unlocked --rpc-url "$RPC" >/dev/null
    $CAST send "$REG" "setPaused(address,bool)" $AAPL true --from $DEPLOYER --unlocked --rpc-url "$RPC" >/dev/null
    echo "AAPL paused through a mock registry ($REG)";;
  stale)
    jump $(( $(now) + 10800 )); echo "moved 3 h forward, now $(now)";;
  reopen)
    for t in $TOKENS; do $CAST send "$ORACLE" "setThreshold(address,uint32)" $t 43200 --from $DEPLOYER --unlocked --rpc-url "$RPC" >/dev/null; done
    T=1794186600 # Mon 2026-11-09 01:10 UTC
    [ "$(now)" -lt "$T" ] || { echo "fork is already past Monday 01:10 UTC"; exit 1; }
    jump $T; echo "thresholds 12 h, now $(now) (Mon 01:10 UTC)";;
  *) echo "usage: $0 pause|stale|reopen"; exit 1;;
esac
show
