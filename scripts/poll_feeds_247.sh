#!/usr/bin/env bash
# Poll Chainlink equity feeds every 30s; append CSV. Usage: poll_feeds.sh <end_epoch>
R=https://mainnet.base.org
OUT="$(dirname "$0")/../data/feed_samples_247.csv"
END=${1:?end epoch}
FEEDS="GOOGL247:0xdD9b9EC942477AA672a15adF91AC5089BD86cD85 NVDA247:0x48D9731AF6cc55b879FE76a4Bd1A6c2C0bDaf944 TSLA247:0xa5Ccd0315346b9A8A1D0AFEcD7Cc4e820e405e96 GOOGL:0x5bF49E0ffA937CE2FfF033c739aD7C634c4D34F2 TSLA:0xFaf869185383a24F8cb00e27BdA6b63B9905DCb4"
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
