"""
vol_threshold_calibration.py -- Calibra threshold de volume empiricamente.

Pergunta: em qual vol threshold o Sharpe forward DEGRADA significativamente?

Metodo (rolling 30d windows, ultimos 365 dias):
  1. Pra cada market + cada dia D:
     - vol_avg_30d at D (USD daily, close * volume aprox)
     - sharpe_forward_60d (Sharpe dos returns de D ate D+60)
  2. Bucket por vol bucket ($10K/$30K/$50K/$100K/$200K/$500K/$1M)
  3. Computa: median Sharpe, %positive_sharpe, P5/P95 distribution
  4. Threshold OTIMO = onde median Sharpe estabiliza + %positive >= 50%

Output:
  - tabela bucket vs sharpe stats
  - recomendacao "break point" empirico
"""
from __future__ import annotations
import json, math, os
from pathlib import Path
from statistics import median, mean

ROOT = Path('.')
CANDLES = ROOT / 'journal' / 'candles_coinex'

BUCKETS = [
    ('<10K',    0,      10_000),
    ('10-30K',  10_000, 30_000),
    ('30-50K',  30_000, 50_000),
    ('50-100K', 50_000, 100_000),
    ('100-200K',100_000,200_000),
    ('200-500K',200_000,500_000),
    ('500K-1M', 500_000,1_000_000),
    ('1M-10M',  1_000_000,10_000_000),
    ('>10M',    10_000_000, float('inf')),
]


def load_market(m):
    f = CANDLES / f'{m}_1day.json'
    if not f.exists(): return []
    try:
        data = json.loads(f.read_text(encoding='utf-8'))
        if isinstance(data, dict) and 'candles' in data: data = data['candles']
        out = []
        for c in data:
            if not isinstance(c, dict): continue
            try:
                close = float(c['close'])
                vol_native = float(c.get('volume', 0))
                # USD vol = close * volume nativo (USDT pairs ja sao USD-denom mas vol pode ser em token)
                # Heuristica: se vol_native > 1e6 e close < 1, vol provavel ja USDT; senao multiplica
                # Mais seguro: usa 'value' se disponivel (CoinEx campo de vol em quote currency)
                vol_quote = float(c.get('value', close * vol_native))
                out.append({'close': close, 'vol_usd': vol_quote})
            except: continue
        return out
    except: return []


def daily_returns(closes):
    return [(closes[i]-closes[i-1])/closes[i-1] for i in range(1,len(closes)) if closes[i-1]>0]


def sharpe(rets):
    if len(rets) < 5: return None
    m = mean(rets); var = sum((r-m)**2 for r in rets)/max(1,len(rets)-1)
    if var <= 0: return None
    return m / math.sqrt(var) * math.sqrt(365)


def calibrate(min_history=120, vol_window=30, sharpe_window=60):
    """Rolling windows: at each day D, take vol_avg(D-30..D) and Sharpe(D..D+60)."""
    markets = sorted({f.stem.replace('_1day','') for f in CANDLES.glob('*_1day.json')
                       if 'summary' not in f.stem.lower()})
    samples = []  # (vol_avg, sharpe_forward, market, day_idx)

    for m in markets:
        candles = load_market(m)
        if len(candles) < min_history: continue
        closes = [c['close'] for c in candles]
        vols = [c['vol_usd'] for c in candles]

        # Walk: for each valid day D, compute vol_avg(D-30..D) e sharpe(D..D+60)
        for d in range(vol_window, len(candles) - sharpe_window):
            vol_avg = mean(vols[d-vol_window:d])
            if vol_avg <= 0: continue
            forward_closes = closes[d:d+sharpe_window+1]
            forward_rets = daily_returns(forward_closes)
            sh = sharpe(forward_rets)
            if sh is None: continue
            samples.append((vol_avg, sh, m, d))

    print(f'Total samples: {len(samples)} (from {len(markets)} markets)')
    print()

    # Bucket
    print(f'{"Vol bucket":<12} {"N":>6} {"median S":>10} {"mean S":>10} {"%pos":>7} {"P25":>7} {"P75":>7}')
    print('-'*70)
    for (label, lo, hi) in BUCKETS:
        b = [s for v,s,_,_ in samples if lo <= v < hi]
        if not b:
            print(f'{label:<12} {"-":>6}')
            continue
        n = len(b)
        med = median(b)
        avg = mean(b)
        pos = sum(1 for x in b if x > 0) / n * 100
        b_sorted = sorted(b)
        p25 = b_sorted[int(n*0.25)]
        p75 = b_sorted[int(n*0.75)]
        print(f'{label:<12} {n:>6} {med:>10.2f} {avg:>10.2f} {pos:>6.0f}% {p25:>7.2f} {p75:>7.2f}')

    # Granular fine-grained sweep for break point
    print()
    print('=== Fine sweep around critical zone (30K-500K) ===')
    fine_steps = [25_000, 50_000, 75_000, 100_000, 150_000, 200_000, 250_000, 300_000, 400_000, 500_000]
    print(f'{"Threshold":<12} {"N>=thr":>8} {"median S":>10} {"%pos":>7} {"break?":<8}')
    print('-'*60)
    prev_med = None
    for thr in fine_steps:
        above = [s for v,s,_,_ in samples if v >= thr]
        n = len(above)
        if not n:
            print(f'>={thr/1000:.0f}K        0')
            continue
        med = median(above)
        pos = sum(1 for x in above if x > 0)/n*100
        delta = (med - prev_med) if prev_med else 0
        flag = 'BREAK' if prev_med and (med - prev_med) > 0.15 else ''
        print(f'>=${thr/1000:.0f}K{"":<6} {n:>8} {med:>10.2f} {pos:>6.0f}% {flag:<8}')
        prev_med = med


if __name__ == '__main__':
    calibrate()
