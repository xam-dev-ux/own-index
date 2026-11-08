#!/usr/bin/env bash
# Runs scan_pending_multiplier.sh every 30 minutes until the unix time given as $1, appending to
# data/pending_multiplier.log. A line starting PENDING is the first live sample of effectiveAt's unit.
until_ts="${1:?usage: watch_pending_multiplier.sh <until-unix-ts>}"
dir="$(cd "$(dirname "$0")" && pwd)"
while [ "$(date +%s)" -lt "$until_ts" ]; do
  out=$("$dir/scan_pending_multiplier.sh"); rc=$?
  echo "$(date -u +%FT%TZ) rc=$rc $out" >> "$dir/../data/pending_multiplier.log"
  sleep 1800
done
