#!/usr/bin/env bash
# Read-only. Warns when the oracle's confirmed calendar horizon is close, because past it the oracle answers
# CALENDAR_NOT_LOADED and every vault refuses to trade. Exit 0 = comfortable, 1 = act now, 2 = could not read.
# Usage: scripts/check_calendar_horizon.sh <oracle-address> [days-of-margin=14] [rpc-url]
set -uo pipefail
ORACLE=${1:?usage: check_calendar_horizon.sh <oracle> [days=14] [rpc]}
DAYS=${2:-14}; RPC=${3:-https://mainnet.base.org}; CAST=${CAST:-base-cast}
until=$($CAST call "$ORACLE" 'confirmedUntil()(uint64)' --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
[[ "$until" =~ ^[0-9]+$ ]] || { echo "could not read confirmedUntil"; exit 2; }
left=$(( (until - $(date +%s)) / 86400 ))
if [ "$left" -lt "$DAYS" ]; then
  echo "ACT NOW: calendar confirmed only until $(date -u -d @"$until" +%F) ($left days). Declare the next closures, then confirmCalendarUntil."; exit 1
fi
echo "ok: calendar confirmed until $(date -u -d @"$until" +%F) ($left days left)"
