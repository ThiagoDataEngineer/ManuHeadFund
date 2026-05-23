"""
vol_threshold_net.py -- Calibracao com Sharpe LIQUIDO (fees + slippage por bucket).

Diferenca chave do vol_threshold_calibration.py: aqui penalizamos cada return
com fee + slippage realista que depende do bucket de volume.

Modelo de slippage (literatura: Cont/Stoikov order book, adaptado crypto):
  slippage_per_trade_pct = 0.001 + (1 / sqrt(daily_vol_usd)) * k

onde k=10 para CoinEx-like books (calibrado por observacao em vol 1M = ~0.10%).

Fee CoinEx: 0.075% spot, 0.05% futures (assume futures = mais provavel).
Round-trip cost: 2 × fee + 2 × slippage por trade.

Hipotese turnover: assume 1 trade-cycle por week (~52/ano). Sharpe penalty =
custo annualizado.

Apos isso, Sharpe LIQUIDO = Sharpe_bruto - cost_annualized_per_unit_volatility.
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

FEE_PCT = 0.05  # futures CoinEx 0.05%
SLIP_K = 10     # constante slippage; calibre se quiser
TRADES_PER_YEAR = 52  # weekly turnover proxy


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
                vol_quote = float(c.get('value', close * float(c.get('volume', 0))))
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


def slippage_pct(daily_vol_usd):
    """Slippage proxy ~ k / sqrt(vol). Vol 1M -> 0.01% (k=10); vol 10K -> 0.10%; vol 1K -> 0.32%."""
    if daily_vol_usd <= 0: return 0.5  # cap em 0.5%
    return min(0.5, SLIP_K / math.sqrt(daily_vol_usd))


def cost_per_trade_pct(daily_vol_usd):
    """Round trip: 2x fee + 2x slippage (entry + exit)."""
    return 2 * FEE_PCT + 2 * slippage_pct(daily_vol_usd)


def annualized_cost_drag(daily_vol_usd, trades_per_year=TRADES_PER_YEAR):
    """Custo anualizado em pct (multiplica trades_per_year)."""
    return cost_per_trade_pct(daily_vol_usd) * trades_per_year / 100  # converte pct -> decimal


def calibrate(min_history=120, vol_window=30, sharpe_window=60):
    markets = sorted({f.stem.replace('_1day','') for f in CANDLES.glob('*_1day.json')
                       if 'summary' not in f.stem.lower()})
    samples = []

    for m in markets:
        candles = load_market(m)
        if len(candles) < min_history: continue
        closes = [c['close'] for c in candles]
        vols = [c['vol_usd'] for c in candles]

        for d in range(vol_window, len(candles) - sharpe_window):
            vol_avg = mean(vols[d-vol_window:d])
            if vol_avg <= 0: continue
            forward_closes = closes[d:d+sharpe_window+1]
            forward_rets = daily_returns(forward_closes)
            sh_gross = sharpe(forward_rets)
            if sh_gross is None: continue
            # Volatility implied pra normalizar cost drag
            mean_r = mean(forward_rets)
            var_r = sum((r-mean_r)**2 for r in forward_rets)/max(1,len(forward_rets)-1)
            ann_vol = math.sqrt(var_r) * math.sqrt(365) if var_r > 0 else None
            if ann_vol is None or ann_vol == 0:
                sh_net = sh_gross
            else:
                cost_drag = annualized_cost_drag(vol_avg)
                # Sharpe penalty = cost_drag (return penalty) / ann_vol (per unit vol)
                sh_net = sh_gross - cost_drag / ann_vol
            samples.append((vol_avg, sh_gross, sh_net, m))

    print(f'Total samples: {len(samples)} (from {len(markets)} markets)')
    print(f'Fee={FEE_PCT}% futures + Slippage k={SLIP_K}/sqrt(vol) + Turnover {TRADES_PER_YEAR}/year')
    print()

    print(f'{"Bucket":<12} {"N":>6} {"med S_gross":>12} {"med S_net":>12} {"%pos net":>9} {"med slip":>9} {"med cost":>9}')
    print('-'*80)
    for (label, lo, hi) in BUCKETS:
        b = [(v,sg,sn) for v,sg,sn,_ in samples if lo <= v < hi]
        if not b:
            print(f'{label:<12} {"-":>6}')
            continue
        n = len(b)
        med_g = median(sg for _,sg,_ in b)
        med_n = median(sn for _,_,sn in b)
        pos_n = sum(1 for _,_,sn in b if sn > 0) / n * 100
        med_v = median(v for v,_,_ in b)
        med_slip = slippage_pct(med_v)
        med_cost = cost_per_trade_pct(med_v)
        print(f'{label:<12} {n:>6} {med_g:>12.2f} {med_n:>12.2f} {pos_n:>8.0f}% {med_slip:>8.3f}% {med_cost:>8.3f}%')

    # Fine sweep with net
    print()
    print('=== Fine sweep com Sharpe NET (cost drag aplicado) ===')
    fine = [10_000, 25_000, 50_000, 75_000, 100_000, 150_000, 200_000, 300_000, 500_000, 1_000_000]
    print(f'{"Threshold":<14} {"N":>8} {"med S_net":>10} {"%pos":>7} {"avg slip":>10}')
    print('-'*60)
    prev_med = None
    for thr in fine:
        above = [(sn, v) for v,_,sn,_ in samples if v >= thr]
        n = len(above)
        if not n:
            print(f'>=${thr/1000:.0f}K{"":<6}        -')
            continue
        med = median(sn for sn,_ in above)
        pos = sum(1 for sn,_ in above if sn > 0)/n*100
        avg_v = mean(v for _,v in above)
        avg_slip = slippage_pct(avg_v)
        delta = (med - prev_med) if prev_med is not None else 0
        flag = ' BREAK!' if prev_med is not None and (med - prev_med) > 0.10 else ''
        print(f'>=${thr/1000:.0f}K{"":<6}  {n:>8} {med:>10.2f} {pos:>6.0f}% {avg_slip:>9.3f}%{flag}')
        prev_med = med


if __name__ == '__main__':
    calibrate()
