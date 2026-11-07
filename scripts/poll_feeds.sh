#!/usr/bin/env bash
# Poll Chainlink equity feeds every 30s; append CSV. Usage: poll_feeds.sh <end_epoch>
R=https://mainnet.base.org
OUT="$(dirname "$0")/../data/feed_samples.csv"
END=${1:?end epoch}
FEEDS="AAPL:0x787f13dEa48Db0897CbCDD985de77809D837F988 NVDA:0x04689a41629776563E6822F76f2e57D148d28513 META:0x6526aE6797A76123638b863AeE4dD27Ba4E4b27D SPCX:0x6A634B235903C4ad6376892180d6fF8612e3Fa68"
[ -f "$OUT" ] || echo "sym,roundId,answer,updatedAt,blockNumber,blockTimestamp,timestampMs,staleness" > "$OUT"
while [ "$(date +%s)" -lt "$END" ]; do
  bn=$(base-cast block-number --rpc-url $R 2>/dev/null) || { sleep 30; continue; }
  bts=$(base-cast block "$bn" -f timestamp --rpc-url $R 2>/dev/null)
  tms=$(base-cast call 0x4200000000000000000000000000000000000030 "timestampMs()(uint256)" --rpc-url $R --block "$bn" 2>/dev/null | awk '{print $1}')
  for p in $FEEDS; do
    s=${p%%:*}; a=${p#*:}
    read -r rid ans _ upd _ < <(base-cast call "$a" 'latestRoundData()(uint80,int256,uint256,uint256,uint80)' --rpc-url $R --block "$bn" 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
    echo "$s,$rid,$ans,$upd,$bn,$bts,$tms,$((bts-upd))" >> "$OUT"
  done
  sleep 30
done
