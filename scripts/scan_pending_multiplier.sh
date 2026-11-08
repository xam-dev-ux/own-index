#!/usr/bin/env bash
# Alarm for the unverified unit of B20 effectiveAt(). Every value has been 0 so far (no change scheduled on any of
# the 298 listed tokens at block 54457318). The first nonzero value is the first live sample of the unit:
# record it in docs/vault-design.md. Exit status 1 when any token has a pending change, so it can sit in a cron.
# Usage: scripts/scan_pending_multiplier.sh [rpc-url]   (the 12 tokens a vault may hold)
set -u
RPC="${1:-https://mainnet.base.org}"
TOKENS="
AAPL:0xb200000000000000000000C2e324d24d7eEcd1fb
AMZN:0xb200000000000000000000d9192b6B456483C2E8
GOOGL:0xb2000000000000000000002D0BA3164cc74f58B7
META:0xb2000000000000000000008bC8786B856E61707C
MSFT:0xB200000000000000000000Ab99cFa739E253872B
MSTR:0xb2000000000000000000004884b426556b92883d
NVDA:0xb20000000000000000000078ee7ce2fE4908108C
SNDK:0xb200000000000000000000397293Cb8cda9a10c5
SPCX:0xb2000000000000000000007b9fcbd005511aCBd5
TSLA:0xb2000000000000000000001e800a7f5189430cD0
INTC:0xB2000000000000000000004AFF16039bA04bdFBc
CRCL:0xB20000000000000000000019f6E7C675b73C2e4D
"
found=0
for row in $TOKENS; do
  sym="${row%%:*}"; addr="${row##*:}"
  at=$(base-cast call "$addr" 'effectiveAt()(uint256)' --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
  if [ -z "$at" ]; then echo "$sym: read failed"; continue; fi
  if [ "$at" != "0" ]; then
    new=$(base-cast call "$addr" 'newUIMultiplier()(uint256)' --rpc-url "$RPC" | awk '{print $1}')
    cur=$(base-cast call "$addr" 'uiMultiplier()(uint256)' --rpc-url "$RPC" | awk '{print $1}')
    echo "PENDING $sym effectiveAt=$at newUIMultiplier=$new uiMultiplier=$cur now=$(date +%s)"
    found=1
  fi
done
[ "$found" = 0 ] && echo "no pending multiplier change on the 12 tokens"
exit $found
