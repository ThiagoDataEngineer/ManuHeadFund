#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
refine_tori_knowledge_based.py -- Refinamento Tori baseado em KNOWLEDGE

OBJETIVO: Encontrar configuração com FREQUÊNCIA + EDGE baseado em fundamentals

KNOWLEDGE BASE (TORI_TRADES.md):
1. Trendline válida: 2-3+ toques, 6+ candles entre toques, 1+ semana dados
2. Inclinação ideal: 20-35° (A+), aceitável: 5-45° (A/B)
3. Setup BOUNCE: trendline = entrada = stop (menor risco)
4. Setup BREAK: 3-touchpoint > 2-touchpoint (mais confiável)
5. HTF alignment: CRÍTICO (nunca contra Daily/Weekly)
6. Qualidade > Frequência: A+ > A > B > C (só operar A+ ou A)

HIPÓTESE:
- Baseline muito restritivo (5-AND gate) = 0 signals
- Relaxar vol_drying = +935% edge com 4 signals (OVERFITTING!)
- Solução: usar APENAS fundamentals Tori (trendline quality)
- Testar múltiplas configurações de slope + touches + proximity
- Buscar sweet spot: 100-1000 signals/ano com edge positivo

METODOLOGIA TDD:
1. Testar configurações baseadas em knowledge
2. Medir edge + sample size + win rate
3. Identificar configuração ótima
4. Validar robustez (não overfit)

VALIDATED: 2026-05-23 TDD
"""

import json
import numpy as np
from datetime import datetime
from lib_data_fetcher import fetch_ohlcv
from lib_backtest_rsi_fixed import calculate_rsi


def backtest_tori_config(df, config, name=""):
    """
    Backtest Tori with given config
    """
    highs = df['high'].values
    lows = df['low'].values
    closes = df['close'].values
    volumes = df['volume'].values
    timestamps = df['timestamp'].values
    
    lookback = config.get('lookback', 20)
    slope_min = config.get('slope_min', 5.0)
    slope_max = config.get('slope_max', 35.0)
    min_touches = config.get('min_touches', 3)
    touch_tolerance = config.get('touch_tolerance', 1.5)
    proximity_min = config.get('proximity_min', -3.0)
    proximity_max = config.get('proximity_max', 5.0)
    use_rsi = config.get('use_rsi', False)
    rsi_max = config.get('rsi_max', 40.0)
    use_vol = config.get('use_vol', False)
    vol_ratio_max = config.get('vol_ratio_max', 0.7)
    
    signals = []
    
    # Progress tracking
    total = len(closes) - lookback
    last_pct = 0
    
    for i in range(lookback, len(closes)):
        # Progress
        pct = int((i - lookback) / total * 100)
        if pct >= last_pct + 10:
            print(f"  {name}: {pct}%", end='\r')
            last_pct = pct
        
        # Get window
        window_lows = lows[i-lookback:i+1]
        window_closes = closes[i-lookback:i+1]
        window_volumes = volumes[i-lookback:i+1]
        
        # 1. Linear regression on lows (BOUNCE setup - support trendline)
        x = np.arange(len(window_lows))
        coeffs = np.polyfit(x, window_lows, 1)
        slope = coeffs[0]
        intercept = coeffs[1]
        
        # Convert slope to degrees
        if window_lows[-1] > 0:
            slope_pct = (slope / window_lows[-1]) * 100
            slope_deg = np.degrees(np.arctan(slope_pct))
        else:
            continue
        
        # Check slope range
        if not (slope_min <= slope_deg <= slope_max):
            continue
        
        # 2. Count touches (CRITICAL per knowledge)
        touches = 0
        for j, low in enumerate(window_lows):
            line_val = intercept + slope * j
            if line_val > 0:
                diff_pct = abs(low - line_val) / line_val * 100
                if diff_pct <= touch_tolerance:
                    touches += 1
        
        if touches < min_touches:
            continue
        
        # 3. Proximity (price near trendline)
        current_price = window_closes[-1]
        line_current = intercept + slope * (len(window_lows) - 1)
        
        if line_current <= 0:
            continue
        
        proximity_pct = (current_price - line_current) / line_current * 100
        
        if not (proximity_min <= proximity_pct <= proximity_max):
            continue
        
        # 4. RSI (optional - knowledge says NOT critical)
        if use_rsi:
            rsi_val = calculate_rsi(window_closes)
            if isinstance(rsi_val, (list, np.ndarray)):
                rsi_val = rsi_val[-1] if len(rsi_val) > 0 else 50.0
            
            if rsi_val >= rsi_max:
                continue
        else:
            rsi_val = None
        
        # 5. Volume drying (optional - knowledge says NOT critical)
        if use_vol:
            if len(window_volumes) >= 10:
                recent_vol = np.mean(window_volumes[-3:])
                prior_vol = np.mean(window_volumes[-10:-3])
                vol_ratio = recent_vol / prior_vol if prior_vol > 0 else 1.0
            else:
                vol_ratio = 1.0
            
            if vol_ratio >= vol_ratio_max:
                continue
        else:
            vol_ratio = None
        
        # Signal detected!
        entry_price = closes[i]
        
        # Calculate edge (h20 = 20 candles forward)
        exit_idx = min(i + 20, len(closes) - 1)
        exit_price = closes[exit_idx]
        
        pnl_pct = (exit_price - entry_price) / entry_price * 100
        
        signals.append({
            'index': i,
            'timestamp': str(timestamps[i]),
            'entry_price': float(entry_price),
            'exit_price': float(exit_price),
            'pnl_pct': float(pnl_pct),
            'slope_deg': float(slope_deg),
            'touches': int(touches),
            'proximity_pct': float(proximity_pct),
            'rsi': float(rsi_val) if rsi_val is not None else None,
            'vol_ratio': float(vol_ratio) if vol_ratio is not None else None
        })
    
    # Calculate statistics
    if len(signals) == 0:
        return {
            'signals': 0,
            'edge': 0,
            'win_rate': 0,
            'avg_win': 0,
            'avg_loss': 0,
            'median_pnl': 0,
            'signals_list': []
        }
    
    pnls = [s['pnl_pct'] for s in signals]
    wins = [p for p in pnls if p > 0]
    losses = [p for p in pnls if p <= 0]
    
    return {
        'signals': len(signals),
        'edge': float(np.mean(pnls)),
        'median_pnl': float(np.median(pnls)),
        'win_rate': float(len(wins) / len(signals) * 100),
        'avg_win': float(np.mean(wins)) if wins else 0,
        'avg_loss': float(np.mean(losses)) if losses else 0,
        'signals_list': signals
    }


def refine_tori():
    """
    Refine Tori based on knowledge fundamentals
    """
    print("="*60)
    print("TORI REFINEMENT - KNOWLEDGE BASED (TDD)")
    print("Finding optimal config with FREQUENCY + EDGE")
    print("="*60)
    
    # Load data
    print("\nLoading historical data...")
    df = fetch_ohlcv('BTCUSDT', '1d')
    
    if df is None or len(df) == 0:
        print("[ERROR] Failed to load data")
        return
    
    print(f"  [OK] Loaded {len(df)} candles")
    
    years = (df['timestamp'].iloc[-1] - df['timestamp'].iloc[0]).days / 365.25
    print(f"  Period: {years:.1f} years")
    
    # Experiments based on KNOWLEDGE
    experiments = [
        # BASELINE: Knowledge fundamentals only (trendline quality)
        {
            'name': 'Knowledge Baseline (3 touches)',
            'description': 'Trendline quality only (slope 5-35°, 3+ touches, proximity)',
            'config': {
                'slope_min': 5.0,
                'slope_max': 35.0,
                'min_touches': 3,
                'touch_tolerance': 1.5,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'use_rsi': False,
                'use_vol': False
            }
        },
        
        # RELAX: 2 touches (knowledge says "minimum 2, ideal 3+")
        {
            'name': 'Knowledge Relaxed (2 touches)',
            'description': 'Min 2 touches (knowledge minimum)',
            'config': {
                'slope_min': 5.0,
                'slope_max': 35.0,
                'min_touches': 2,
                'touch_tolerance': 1.5,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'use_rsi': False,
                'use_vol': False
            }
        },
        
        # A+ ONLY: Ideal slope 20-35° (knowledge A+ range)
        {
            'name': 'A+ Only (20-35° slope)',
            'description': 'Ideal slope range (A+ quality)',
            'config': {
                'slope_min': 20.0,
                'slope_max': 35.0,
                'min_touches': 3,
                'touch_tolerance': 1.5,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'use_rsi': False,
                'use_vol': False
            }
        },
        
        # WIDEN SLOPE: 5-45° (knowledge says <45° acceptable)
        {
            'name': 'Widen Slope (5-45°)',
            'description': 'Acceptable slope range (A/B quality)',
            'config': {
                'slope_min': 5.0,
                'slope_max': 45.0,
                'min_touches': 3,
                'touch_tolerance': 1.5,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'use_rsi': False,
                'use_vol': False
            }
        },
        
        # WIDEN PROXIMITY: -5% to +10% (more anticipatory)
        {
            'name': 'Widen Proximity (-5/+10%)',
            'description': 'Wider proximity range (earlier entries)',
            'config': {
                'slope_min': 5.0,
                'slope_max': 35.0,
                'min_touches': 3,
                'touch_tolerance': 1.5,
                'proximity_min': -5.0,
                'proximity_max': 10.0,
                'use_rsi': False,
                'use_vol': False
            }
        },
        
        # RELAX TOLERANCE: 2.0% (crypto sweeps)
        {
            'name': 'Relax Touch Tolerance (2.0%)',
            'description': 'Wider touch tolerance (crypto sweeps)',
            'config': {
                'slope_min': 5.0,
                'slope_max': 35.0,
                'min_touches': 3,
                'touch_tolerance': 2.0,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'use_rsi': False,
                'use_vol': False
            }
        },
        
        # COMBO: 2 touches + wider proximity
        {
            'name': 'Combo (2 touches + wide prox)',
            'description': '2 touches + proximity -5/+10%',
            'config': {
                'slope_min': 5.0,
                'slope_max': 35.0,
                'min_touches': 2,
                'touch_tolerance': 1.5,
                'proximity_min': -5.0,
                'proximity_max': 10.0,
                'use_rsi': False,
                'use_vol': False
            }
        },
        
        # AGGRESSIVE: 2 touches + wide slope + wide proximity
        {
            'name': 'Aggressive (2t + 5-45° + wide prox)',
            'description': 'Maximum frequency config',
            'config': {
                'slope_min': 5.0,
                'slope_max': 45.0,
                'min_touches': 2,
                'touch_tolerance': 2.0,
                'proximity_min': -5.0,
                'proximity_max': 10.0,
                'use_rsi': False,
                'use_vol': False
            }
        },
        
        # CONSERVATIVE: 3 touches + ideal slope + tight proximity
        {
            'name': 'Conservative (3t + 20-35° + tight)',
            'description': 'Highest quality only',
            'config': {
                'slope_min': 20.0,
                'slope_max': 35.0,
                'min_touches': 3,
                'touch_tolerance': 1.5,
                'proximity_min': -2.0,
                'proximity_max': 3.0,
                'use_rsi': False,
                'use_vol': False
            }
        },
        
        # SWEET SPOT: 2 touches + ideal slope
        {
            'name': 'Sweet Spot (2t + 20-35°)',
            'description': 'Balance frequency + quality',
            'config': {
                'slope_min': 20.0,
                'slope_max': 35.0,
                'min_touches': 2,
                'touch_tolerance': 1.5,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'use_rsi': False,
                'use_vol': False
            }
        }
    ]
    
    # Run experiments
    print("\n" + "="*60)
    print("RUNNING EXPERIMENTS")
    print("="*60)
    
    results = []
    
    for i, exp in enumerate(experiments, 1):
        print(f"\n[{i}/{len(experiments)}] {exp['name']}")
        print(f"  {exp['description']}")
        
        result = backtest_tori_config(df, exp['config'], exp['name'])
        
        print(f"\n  Results:")
        print(f"    Signals:    {result['signals']}")
        print(f"    Edge (h20): {result['edge']:+.2f}%", end='')
        
        if result['edge'] > 0:
            print(" ✅")
        else:
            print(" ❌")
        
        if result['signals'] > 0:
            print(f"    Median PnL: {result['median_pnl']:+.2f}%")
            print(f"    Win rate:   {result['win_rate']:.1f}%")
            print(f"    Avg win:    +{result['avg_win']:.2f}%")
            print(f"    Avg loss:   {result['avg_loss']:.2f}%")
            print(f"    Frequency:  {result['signals'] / years:.1f} signals/year")
        
        results.append({
            'name': exp['name'],
            'description': exp['description'],
            'config': exp['config'],
            'results': result
        })
    
    # Analysis
    print("\n" + "="*60)
    print("ANALYSIS")
    print("="*60)
    
    # Sort by edge
    results_sorted = sorted(results, key=lambda x: x['results']['edge'], reverse=True)
    
    print("\n1. SORTED BY EDGE (best first):")
    for i, r in enumerate(results_sorted[:5], 1):
        emoji = "🥇" if i == 1 else "🥈" if i == 2 else "🥉" if i == 3 else "  "
        edge = r['results']['edge']
        signals = r['results']['signals']
        freq = signals / years if signals > 0 else 0
        
        print(f"{emoji} {i}. {r['name']:35s}: {edge:+6.2f}% ({signals:4d} signals, {freq:6.1f}/year)")
    
    # Sort by frequency
    results_freq = sorted(results, key=lambda x: x['results']['signals'], reverse=True)
    
    print("\n2. SORTED BY FREQUENCY (most signals first):")
    for i, r in enumerate(results_freq[:5], 1):
        emoji = "🔥" if i == 1 else "⚡" if i == 2 else "💫" if i == 3 else "  "
        edge = r['results']['edge']
        signals = r['results']['signals']
        freq = signals / years if signals > 0 else 0
        
        print(f"{emoji} {i}. {r['name']:35s}: {signals:4d} signals ({freq:6.1f}/year), edge {edge:+.2f}%")
    
    # Find sweet spot (edge > 0 + signals > 100)
    sweet_spots = [r for r in results if r['results']['edge'] > 0 and r['results']['signals'] > 100]
    sweet_spots_sorted = sorted(sweet_spots, key=lambda x: x['results']['edge'], reverse=True)
    
    print("\n3. SWEET SPOTS (edge > 0 + signals > 100):")
    if sweet_spots_sorted:
        for i, r in enumerate(sweet_spots_sorted, 1):
            edge = r['results']['edge']
            signals = r['results']['signals']
            freq = signals / years
            win_rate = r['results']['win_rate']
            
            print(f"  {i}. {r['name']:35s}")
            print(f"     Edge: {edge:+.2f}%, Signals: {signals}, Freq: {freq:.1f}/year, WR: {win_rate:.1f}%")
    else:
        print("  [NONE] No configuration meets criteria")
    
    # Best overall
    best = results_sorted[0]
    
    print("\n" + "="*60)
    print("BEST CONFIGURATION")
    print("="*60)
    
    print(f"\nName: {best['name']}")
    print(f"Description: {best['description']}")
    
    print(f"\nConfig:")
    for k, v in best['config'].items():
        print(f"  {k:20s}: {v}")
    
    print(f"\nResults:")
    print(f"  Signals:    {best['results']['signals']}")
    print(f"  Edge (h20): {best['results']['edge']:+.2f}% {'✅' if best['results']['edge'] > 0 else '❌'}")
    print(f"  Median PnL: {best['results']['median_pnl']:+.2f}%")
    print(f"  Win rate:   {best['results']['win_rate']:.1f}%")
    print(f"  Avg win:    +{best['results']['avg_win']:.2f}%")
    print(f"  Avg loss:   {best['results']['avg_loss']:.2f}%")
    print(f"  Frequency:  {best['results']['signals'] / years:.1f} signals/year")
    
    # Recommendation
    print("\n" + "="*60)
    print("RECOMMENDATION")
    print("="*60)
    
    if best['results']['signals'] < 50:
        print("\n⚠️  WARNING: Sample size too small (<50 signals)")
        print("   Edge may be overfitting")
        print("   Recommendation: Use configuration with 100+ signals")
        
        if sweet_spots_sorted:
            rec = sweet_spots_sorted[0]
            print(f"\n   RECOMMENDED: {rec['name']}")
            print(f"   Edge: {rec['results']['edge']:+.2f}%")
            print(f"   Signals: {rec['results']['signals']}")
            print(f"   Frequency: {rec['results']['signals'] / years:.1f}/year")
    else:
        print(f"\n✅ RECOMMENDED: {best['name']}")
        print(f"   Edge: {best['results']['edge']:+.2f}%")
        print(f"   Signals: {best['results']['signals']}")
        print(f"   Frequency: {best['results']['signals'] / years:.1f}/year")
        print(f"   Sample size: ROBUST")
    
    # Save results
    output = {
        'timestamp': datetime.now().isoformat(),
        'market': 'BTCUSDT',
        'period': '1d',
        'candles': len(df),
        'years': float(years),
        'experiments': results,
        'best': best,
        'sweet_spots': sweet_spots_sorted if sweet_spots_sorted else []
    }
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = f"journal/tori_refinement_knowledge_{timestamp}.json"
    
    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)
    
    print(f"\n[OK] Results saved: {output_file}")
    
    print("\n" + "="*60)
    print("REFINEMENT COMPLETE")
    print("="*60)


if __name__ == '__main__':
    refine_tori()
