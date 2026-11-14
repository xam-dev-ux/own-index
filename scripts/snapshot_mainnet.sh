#!/usr/bin/env bash
# Calls snapshotAll() on the mainnet oracle with the keystore account `speedrun` (the password is typed at the prompt).
# Run it twice per weekend: once while the market is CLOSED (records the close prices), once after the Monday reopen and
# first fresh print (writes the gap records). `check` prints what the oracle says now and sends nothing.
#   scripts/snapshot_mainnet.sh check
#   scripts/snapshot_mainnet.sh send
set -euo pipefail
RPC=${RPC:-https://mainnet.base.org}; CAST=${CAST:-base-cast}
ORACLE=0x516A9C36E0D3f49Ed51E93cDa7B236D5A7a89951
SUFFIX=62635f337737677373716c0b0080218021802180218021802180218021   # ERC-8021, Builder Code bc_3w7gssql
TOKENS="AAPL:0xb200000000000000000000C2e324d24d7eEcd1fb AMZN:0xb200000000000000000000d9192b6B456483C2E8 GOOGL:0xb2000000000000000000002D0BA3164cc74f58B7 TSLA:0xb2000000000000000000001e800a7f5189430cD0"
echo "now: $(date -u)"
for kv in $TOKENS; do
  n=${kv%%:*}; a=${kv##*:}
  s=$(timeout 30 $CAST call $ORACLE 'markOf(address)((int256,uint8,uint8,uint32,uint16,uint64,uint8,int256,int256,uint32))' "$a" --rpc-url "$RPC" 2>/dev/null | tr -d '()' | tr ',' '\n' | sed -n 2p | awk '{print $1}')
  echo "  $n session=$s (0 FRESH, 1 CLOSED, 2 STALE_IN_SESSION, 3 PAUSED, 4 UNKNOWN)"
done
DATA=$($CAST calldata 'snapshotAll()')$SUFFIX
echo "simulation:"; timeout 60 $CAST call $ORACLE --data "$DATA" --rpc-url "$RPC" >/dev/null && echo "  ok, snapshotAll would not revert"
echo "gas estimate: $(timeout 60 $CAST estimate $ORACLE "snapshotAll()" --rpc-url "$RPC" 2>/dev/null)"
[ "${1:-check}" = send ] || { echo "check only. Run with 'send' to broadcast."; exit 0; }
$CAST send $ORACLE --data "$DATA" --account speedrun --rpc-url "$RPC"
