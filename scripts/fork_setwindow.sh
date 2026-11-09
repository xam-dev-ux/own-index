#!/usr/bin/env bash
# Local fork only. Proves the safety net behind an INFERRED close offset: if the weekly window turns out to be wrong on
# mainnet, the recorder can correct it live with setWindow and the verdict follows, with no redeploy.
#   1. the fork is in session, AAPL reads FRESH
#   2. setWindow with a deliberately wrong close (Friday 00:00 UTC) -> the real oracle now reads CLOSED
#   3. setWindow back to the intended close (Saturday 01:00 UTC)    -> FRESH again
# Does not move time, so it can be repeated. Needs the fork before `make fork-weekend` / `make fork-states`.
# The deployer (the oracle's recorder) is impersonated by the fork; no key is involved.
set -euo pipefail
cd "$(dirname "$0")/.."
RPC=${FORK_RPC:-http://127.0.0.1:8545}; CAST=${CAST:-base-cast}
J=.fork/addresses.json
[ -f "$J" ] || { echo "no $J: run make setup-fork first"; exit 1; }
[ -n "$($CAST rpc anvil_nodeInfo --rpc-url "$RPC" 2>/dev/null)" ] || { echo "not an anvil fork at $RPC"; exit 1; }
ORACLE=$(python3 -c "import json;print(json.load(open('$J'))['oracle'])")
DEPLOYER=0x8F058fE6b568D97f85d517Ac441b52B95722fDDe
AAPL=0xb200000000000000000000C2e324d24d7eEcd1fb
OPEN=3600; GOOD_CLOSE=435600; WRONG_CLOSE=345600

session() { # 0 FRESH, 1 CLOSED, 2 STALE_IN_SESSION, 3 PAUSED, 4 UNKNOWN
  $CAST call "$ORACLE" 'markOf(address)((int256,uint8,uint8,uint32,uint16,uint64,uint8,int256,int256,uint32))' $AAPL --rpc-url "$RPC" 2>/dev/null \
    | tr -d '()' | tr ',' '\n' | sed -n 2p | awk '{print $1}'
}
set_window() { $CAST send "$ORACLE" "setWindow(uint32,uint32)" $OPEN "$1" --from $DEPLOYER --unlocked --rpc-url "$RPC" >/dev/null; }
restore() { set_window $GOOD_CLOSE || true; }
trap restore EXIT

s0=$(session); echo "1. intended window (close $GOOD_CLOSE): AAPL session = $s0 (0 = FRESH)"
[ "$s0" = 0 ] || { echo "the fork is not in a FRESH session now; run make setup-fork first"; exit 1; }
set_window $WRONG_CLOSE
s1=$(session); echo "2. wrong close ($WRONG_CLOSE, Friday 00:00 UTC): AAPL session = $s1 (1 = CLOSED)"
set_window $GOOD_CLOSE
s2=$(session); echo "3. corrected close ($GOOD_CLOSE): AAPL session = $s2 (0 = FRESH)"
if [ "$s1" = 1 ] && [ "$s2" = 0 ]; then echo "OK: setWindow corrected the verdict live"; else echo "FAILED"; exit 1; fi
