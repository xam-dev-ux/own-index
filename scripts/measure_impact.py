#!/usr/bin/env python3
"""Price impact for USDC->token swaps on Aero/Aerodrome CL pools, computed from slot0() and liquidity().
Single-range approximation: assumes current in-range liquidity across the trade (ignores tick crossings)."""
import json,subprocess,sys,time
R='https://mainnet.base.org'
U='0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913'
FACT={'aero':'0x9CB220581b91b0C83223012FE69688b92aD07a76','old':'0xf8f2eB4940CFE7d13603DDDD87f123820Fc061Ef'}
TS=[1,10,50,100,200,2000]
TOK={'AAPL':'0xb200000000000000000000C2e324d24d7eEcd1fb','AMZN':'0xb200000000000000000000d9192b6B456483C2E8','GOOGL':'0xb2000000000000000000002D0BA3164cc74f58B7','META':'0xb2000000000000000000008bC8786B856E61707C','MSFT':'0xB200000000000000000000Ab99cFa739E253872B','MSTR':'0xb2000000000000000000004884b426556b92883d','NVDA':'0xb20000000000000000000078ee7ce2fE4908108C','SNDK':'0xb200000000000000000000397293Cb8cda9a10c5','SPCX':'0xb2000000000000000000007b9fcbd005511aCBd5','TSLA':'0xb2000000000000000000001e800a7f5189430cD0','INTC':'0xB2000000000000000000004AFF16039bA04bdFBc','CRCL':'0xB20000000000000000000019f6E7C675b73C2e4D'}
def call(a,sig,*args):
    for i in range(5):
        r=subprocess.run(['base-cast','call',a,sig,*args,'--rpc-url',R],capture_output=True,text=True)
        if r.returncode==0: return r.stdout.split('\n')
        if 'limit' not in r.stderr and 'rate' not in r.stderr.lower(): return None
        time.sleep(2*(i+1))
    return None
Z='0x'+'0'*40
out={}
for s,t in TOK.items():
    best=None
    for fn,f in FACT.items():
        for ts in TS:
            r=call(f,'getPool(address,address,int24)(address)',U,t,str(ts))
            if not r or r[0]==Z: continue
            p=r[0]
            s0=call(p,'slot0()(uint160,int24,uint16,uint16,uint16,bool)'); L=call(p,'liquidity()(uint128)'); fee=call(p,'fee()(uint24)')
            if not s0 or not L: continue
            sq=int(s0[0].split()[0]); liq=int(L[0].split()[0]); feep=int(fee[0].split()[0]) if fee else 0
            t0=call(p,'token0()(address)')[0].lower()
            if t0!=U.lower(): print('unexpected token order',s,p); continue
            bal=call(U,'balanceOf(address)(uint256)',p); usdc=int(bal[0].split()[0])/1e6
            row=dict(factory=fn,ts=ts,pool=p,liq=liq,fee_ppm=feep,usdc_bal=usdc,sq=sq)
            Q=2**96
            res={}
            for amt in (100,1000,10000):
                dx=amt*10**6*(1-feep/1e6)
                sqn=liq*sq/(liq+dx*sq/Q)       # token0 in -> sqrtP falls
                dy=liq*(sq-sqn)/Q
                spot=(sq/Q)**2
                exec_=dy/dx
                res[amt]=round((1-exec_/spot)*1e4,1)   # bps, excl. fee
            row['impact_bps_ex_fee']=res
            if best is None or usdc>best['usdc_bal']: best=row
    out[s]=best
    if best: print(f"{s:6} {best['factory']:5} ts={best['ts']:<4} fee={best['fee_ppm']/1e4:.2f}% usdc_in_pool=${best['usdc_bal']:>10,.0f} impact(bps,ex-fee) $100={best['impact_bps_ex_fee'][100]} $1k={best['impact_bps_ex_fee'][1000]} $10k={best['impact_bps_ex_fee'][10000]} {best['pool']}",flush=True)
    else: print(s,'no pool',flush=True)
json.dump(out,open(sys.argv[1] if len(sys.argv)>1 else '/dev/null','w'),indent=1)
