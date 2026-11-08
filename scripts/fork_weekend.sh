#!/usr/bin/env bash
# Local fork only. Jumps the running fork to Saturday 2026-11-07 12:00 UTC (window closed, WEEKEND) and records a
# MARKET_CLOSED refusal in the dev vault. Time only moves forward: run `make setup-fork` to get back to the session.
set -euo pipefail
cd "$(dirname "$0")/.."
RPC=${FORK_RPC:-http://127.0.0.1:8545}
CAST=${CAST:-base-cast}
J=.fork/addresses.json
[ -f "$J" ] || { echo "no $J: run make setup-fork first"; exit 1; }
[ "$($CAST chain-id --rpc-url "$RPC")" = 8453 ] && [ -n "$($CAST rpc anvil_nodeInfo --rpc-url "$RPC" 2>/dev/null)" ] || { echo "not an anvil fork at $RPC"; exit 1; }
T=1794052800 # Sat 2026-11-07 12:00 UTC
now=$($CAST block latest -f timestamp --rpc-url "$RPC")
[ "$now" -lt "$T" ] || { echo "fork is already past Saturday 12:00 UTC (time only moves forward)"; exit 1; }
VAULT=$(python3 -c "import json;print(json.load(open('$J'))['vault'])")
OWNER=$(python3 -c "import json;print(json.load(open('$J'))['owner'])")
$CAST rpc evm_setNextBlockTimestamp $T --rpc-url "$RPC" >/dev/null
$CAST rpc evm_mine --rpc-url "$RPC" >/dev/null
$CAST send "$VAULT" "tryRebalance(bytes[])" "[]" --from "$OWNER" --unlocked --rpc-url "$RPC" >/dev/null
echo "fork at $($CAST block latest -f timestamp --rpc-url "$RPC") (Sat 12:00 UTC). refusals: $($CAST call "$VAULT" 'refusalCount()(uint256)' --rpc-url "$RPC")"
