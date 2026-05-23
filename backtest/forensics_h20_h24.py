"""forensics_h20_h24.py -- Analise forense profunda h20 vs h24 p3_bear.

Hipotese: edge h24 +23pp pos-gate eh real. h20 -7 a +1pp aparentemente nao.
Mas h20 NAO sera descartado — vamos investigar POR QUE difere.

Perguntas:
  1. Per-day breakdown: quais dias dispararam? clustered? spread?
  2. Per-market contribution: 1-2 markets dominam? distribuido?
  3. BTC context at signal: DD%, vol_20d, regime feature
  4. Outcome distribution: assymetric (few big wins)? symmetric noise?
  5. Post-signal price curve: bounce-and-fade vs bounce-and-trend?
  6. Sub-regimes within h20 / h24: meses iniciais vs finais diferentes?
"""
from __future__ import annotations
import sys
from collections import defaultdict, Counter
sys.path.insert(0, "backtest")
from regime_gate_alpha import (build_btc_regime_index, build_cross_corr_index,
                                load_candles, walk_signals, hit_rate,
                                CANDLES_DIR, EXT_DIR, WINDOW_BARS, THRESHOLD_PCT, COSTS_PCT)
from pathlib import Path
import json


def forensic_dump(phase_name, sig_events, btc_regime):
    """Dump structured analysis for a single phase."""
    by_day = defaultdict(list)
    for e in sig_events:
        by_day[e['ts'][:10]].append(e)
    days = sorted(by_day.keys())

    print(f"\n===== {phase_name} FORENSE =====")
    print(f"Total events: {len(sig_events)} | Distinct days: {len(days)}")
    print()

    # Per-day breakdown with outcomes
    print(f"{'date':<12} {'mkts':>4} {'avg_out':>8} {'win_rate':>9} {'btc_dd':>7} {'btc_vol':>8} markets")
    print("-"*100)
    day_wins = []
    for d in days:
        evs = by_day[d]
        outs = [e['outcome'] for e in evs]
        avg = sum(outs)/len(outs)
        wins = sum(1 for o in outs if o >= 1.6)  # net threshold
        wr = wins/len(outs)*100
        day_wins.append(wins >= len(outs)/2)
        btc = btc_regime.get(d, {})
        dd = btc.get('drawdown_pct', None)
        vol = btc.get('vol_20d', None)
        dd_s = f"{dd:+5.1f}%" if dd is not None else "  n/a"
        vol_s = f"{vol:.2f}%" if vol is not None else "  n/a"
        mkts = ",".join([e['market'].replace("USDT","").replace("USD","") for e in evs[:5]])
        if len(evs) > 5: mkts += f"+{len(evs)-5}"
        print(f"{d:<12} {len(evs):>4} {avg:>+7.2f}% {wr:>7.0f}%   {dd_s:>7} {vol_s:>7}  {mkts}")

    # Win/loss distribution
    print()
    outs = [e['outcome'] for e in sig_events]
    wins = [o for o in outs if o >= 1.6]
    losses = [o for o in outs if o < 1.6]
    print(f"Outcome distribution:")
    print(f"  Wins (>=+1.6%): {len(wins):>3}  avg={sum(wins)/len(wins) if wins else 0:+.2f}%  max={max(wins) if wins else 0:+.2f}%")
    print(f"  Losses (<+1.6%): {len(losses):>3}  avg={sum(losses)/len(losses) if losses else 0:+.2f}%  min={min(losses) if losses else 0:+.2f}%")

    # Per-market
    print()
    print(f"Per-market contribution:")
    by_mkt = defaultdict(list)
    for e in sig_events: by_mkt[e['market']].append(e['outcome'])
    rows = sorted([(m, len(o), sum(1 for x in o if x>=1.6), sum(o)/len(o))
                   for m,o in by_mkt.items()], key=lambda x: -x[1])
    for m, n, w, avg in rows[:15]:
        print(f"  {m:<14} n={n:>2} wins={w:>2} ({w/n*100:>3.0f}%) avg={avg:+.2f}%")

    # Day-level winners (>50% wins)
    print()
    print(f"Day-level: {sum(day_wins)}/{len(days)} days majority-win ({sum(day_wins)/len(days)*100:.0f}%)")

    return by_day


def sub_regime_analysis(phase_name, sig_events):
    """Split phase events by month-bucket to detect sub-regimes."""
    print(f"\n----- {phase_name} sub-regime (3-month buckets) -----")
    by_bucket = defaultdict(list)
    for e in sig_events:
        # YYYY-MM bucket
        d = e['ts'][:7]
        by_bucket[d].append(e['outcome'])
    months = sorted(by_bucket.keys())
    # Group into 3-month buckets
    triples = defaultdict(list)
    for m in months:
        y, mo = m.split('-')
        bucket_mo = ((int(mo)-1)//3)*3 + 1
        bkey = f"{y}-Q{(bucket_mo-1)//3+1}"
        triples[bkey].extend(by_bucket[m])
    for bk in sorted(triples):
        outs = triples[bk]
        if len(outs) == 0: continue
        wins = sum(1 for o in outs if o >= 1.6)
        avg = sum(outs)/len(outs)
        print(f"  {bk}: n={len(outs):>2} wins={wins} ({wins/len(outs)*100:>3.0f}%) avg={avg:+.2f}%")


def main():
    btc = build_btc_regime_index()
    cc  = build_cross_corr_index()

    md = []
    for f in sorted(CANDLES_DIR.glob("*_1day.json")):
        d = load_candles(f.stem.replace("_1day",""))
        if d and len(d) >= 300: md.append((f.stem.replace("_1day",""), d))
    for f in sorted(EXT_DIR.glob("*_BITSTAMP_1day.json")):
        market = f.stem.replace("_BITSTAMP_1day","")
        if market in ("BTCUSD","ETHUSD"): continue
        d = load_candles(market, src="bitstamp")
        if d and len(d) >= 1500: md.append((market, d))

    print(f"Universe: {len(md)} markets")
    all_e = walk_signals(md, btc, cc, window=WINDOW_BARS)
    sig = [e for e in all_e if e['signal']=='v']

    h20 = [e for e in sig if e['phase']=='h20_p3_bear']
    h24 = [e for e in sig if e['phase']=='h24_p3_bear']

    print(f"\nh20 events: {len(h20)} ({len(set(e['ts'][:10] for e in h20))} days)")
    print(f"h24 events: {len(h24)} ({len(set(e['ts'][:10] for e in h24))} days)")

    forensic_dump("h24_p3_bear", h24, btc)
    sub_regime_analysis("h24_p3_bear", h24)

    forensic_dump("h20_p3_bear", h20, btc)
    sub_regime_analysis("h20_p3_bear", h20)

    # Comparativo BTC regime
    print("\n===== BTC REGIME at signal time: h20 vs h24 =====")
    def stats(events):
        dds = [e['btc_drawdown'] for e in events if e['btc_drawdown'] is not None]
        vols= [e['btc_vol_20d']  for e in events if e['btc_vol_20d']  is not None]
        return {
            'dd_mean': sum(dds)/len(dds) if dds else None,
            'dd_min':  min(dds) if dds else None,
            'dd_max':  max(dds) if dds else None,
            'vol_mean':sum(vols)/len(vols) if vols else None,
            'vol_min': min(vols) if vols else None,
            'vol_max': max(vols) if vols else None,
        }
    h20s = stats(h20); h24s = stats(h24)
    print(f"  h20 BTC DD: mean={h20s['dd_mean']:+.1f}% range=[{h20s['dd_min']:+.1f}%, {h20s['dd_max']:+.1f}%]")
    print(f"  h24 BTC DD: mean={h24s['dd_mean']:+.1f}% range=[{h24s['dd_min']:+.1f}%, {h24s['dd_max']:+.1f}%]")
    print(f"  h20 BTC VOL: mean={h20s['vol_mean']:.2f}% range=[{h20s['vol_min']:.2f}%, {h20s['vol_max']:.2f}%]")
    print(f"  h24 BTC VOL: mean={h24s['vol_mean']:.2f}% range=[{h24s['vol_min']:.2f}%, {h24s['vol_max']:.2f}%]")


if __name__ == "__main__":
    main()
