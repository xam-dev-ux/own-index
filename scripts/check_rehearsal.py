#!/usr/bin/env python3
"""Read the nine rehearsal verdicts from the chain (not from simulation).
Usage: check_rehearsal.py <broadcast run-latest.json> [rpc-url]
Expected order of contract creations in the broadcast: openOracle, MockRegistry, 8 x (MockFeed, MockStock),
closedOracle, MockFeed, MockStock."""
import json,subprocess,sys
SESS=['FRESH','CLOSED','STALE_IN_SESSION','PAUSED','UNKNOWN']
CAUSE=['NONE','WEEKEND','HOLIDAY','EARLY_CLOSE','AWAITING_FIRST_PRINT','FEED_NOT_UPDATING','HEARTBEAT_EXCEEDED','REGISTRY_PAUSED','FEED_INVALID','CALENDAR_NOT_LOADED','NOT_CONFIGURED']
EXPECT=[('FRESH','NONE'),('STALE_IN_SESSION','AWAITING_FIRST_PRINT'),('STALE_IN_SESSION','FEED_NOT_UPDATING'),('STALE_IN_SESSION','HEARTBEAT_EXCEEDED'),('UNKNOWN','FEED_INVALID'),('UNKNOWN','FEED_INVALID'),('PAUSED','REGISTRY_PAUSED'),('UNKNOWN','FEED_INVALID'),('CLOSED','WEEKEND')]
rpc=sys.argv[2] if len(sys.argv)>2 else 'https://sepolia.base.org'
d=json.load(open(sys.argv[1]))
creates=[t['contractAddress'] for t in d['transactions'] if t['transactionType']=='CREATE']
assert len(creates)==21, f'expected 21 creations, got {len(creates)}'
openO,closedO=creates[0],creates[18]
tokens=[(openO,creates[3+2*i]) for i in range(8)]+[(closedO,creates[20])]
ok=True
for i,((o,t),(es,ec)) in enumerate(zip(tokens,EXPECT)):
    r=subprocess.run(['base-cast','call',o,'markOf(address)((int256,uint8,uint8,uint32,uint16,uint64,uint8,int256,int256,uint32))',t,'--rpc-url',rpc],capture_output=True,text=True)
    if r.returncode: print(i,'CALL FAILED',r.stderr.strip()); ok=False; continue
    f=[x.strip() for x in r.stdout.strip().strip('()').split(',')]
    s,c=SESS[int(f[1])],CAUSE[int(f[2])]
    print(i,o[:10],t[:10],s,c,'OK' if (s,c)==(es,ec) else f'MISMATCH expected {es}/{ec}'); ok&=(s,c)==(es,ec)
print('ALL MATCH' if ok else 'DIVERGENCE: investigate before mainnet')
