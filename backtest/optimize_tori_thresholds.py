#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
optimize_tori_thresholds.py -- Otimização de thresholds Tori (TDD)

OBJETIVO: Encontrar thresholds que maximizem edge

ESTRATÉGIA:
1. Baseline (current): 5-AND gate (vol_drying + RSI + trendline + proximity)
2. Remove vol_drying: 4-AND gate
3. Remove RSI: 4-AND gate
4. Remove both: 3-AND gate (trendline + proximity only)
5. Relax vol_drying: <0.8 instead of <0.7
6. Relax RSI: <50 instead of <40

VALIDATED: 2026-05-23 TDD
"""

import json
import numpy as np
from datetime import datetime
from lib_data_fetcher import fetch_ohlcv
from lib_backtest_rsi_fixed import calculate_rsi


def backtest_tori(df, config):
    """
    Backtest Tori with given config
    
    Args:
        df: DataFrame with OHLCV data
        config: Dict with thresholds
    
    Returns:
        Dict with results
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
    proximity_min = config.get('proximity_min', -3.0)
    proximity_max = config.get('proximity_max', 5.0)
    rsi_max = config.get('rsi_max', None)  # None = disabled
    vol_ratio_max = config.get('vol_ratio_max', None)  # None = disabled
    
    signals = []
    
    for i in range(lookback, len(closes)):
        # Get window
        window_lows = lows[i-lookback:i+1]
        window_closes = closes[i-lookback:i+1]
        window_volumes = volumes[i-lookback:i+1]
        
        # 1. Linear regression on lows
        x = np.arange(len(window_lows))
        coeffs = np.polyfit(x, window_lows, 1)
        slope = coeffs[0]
        intercept = coeffs[1]
        
        # Convert slope to degrees
        slope_deg = np.degrees(np.arctan(slope / window_lows[-1] * 100))
        
        # Check slope range
        if not (slope_min <= slope_deg <= slope_max):
            continue
        
        # 2. Count touches
        touches = 0
        for j, low in enumerate(window_lows):
            line_val = intercept + slope * j
            if line_val > 0:
                diff_pct = abs(low - line_val) / line_val * 100
                if diff_pct <= 1.5:
                    touches += 1
        
        if touches < min_touches:
            continue
        
        # 3. Proximity
        current_price = window_closes[-1]
        line_current = intercept + slope * (len(window_lows) - 1)
        
        if line_current <= 0:
            continue
        
        proximity_pct = (current_price - line_current) / line_current * 100
        
        if not (proximity_min <= proximity_pct <= proximity_max):
            continue
        
        # 4. RSI (optional)
        if rsi_max is not None:
            rsi_val = calculate_rsi(window_closes)
            if isinstance(rsi_val, (list, np.ndarray)):
                rsi_val = rsi_val[-1] if len(rsi_val) > 0 else 50.0
            
            if rsi_val >= rsi_max:
                continue
        else:
            rsi_val = None
        
        # 5. Volume drying (optional)
        if vol_ratio_max is not None:
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
            'signals_list': []
        }
    
    pnls = [s['pnl_pct'] for s in signals]
    wins = [p for p in pnls if p > 0]
    losses = [p for p in pnls if p <= 0]
    
    return {
        'signals': len(signals),
        'edge': float(np.mean(pnls)),
        'win_rate': float(len(wins) / len(signals) * 100),
        'avg_win': float(np.mean(wins)) if wins else 0,
        'avg_loss': float(np.mean(losses)) if losses else 0,
        'signals_list': signals
    }


def optimize_tori():
    """
    Optimize Tori thresholds
    """
    print("="*60)
    print("TORI THRESHOLD OPTIMIZATION (TDD)")
    print("Finding optimal thresholds for maximum edge")
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
    
    # Experiments
    experiments = [
        {
            'name': 'Baseline (5-AND)',
            'description': 'Current implementation (all filters)',
            'config': {
                'slope_min': 5.0,
                'slope_max': 35.0,
                'min_touches': 3,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'rsi_max': 40.0,
                'vol_ratio_max': 0.7
            }
        },
        {
            'name': 'Remove vol_drying (4-AND)',
            'description': 'No volume filter',
            'config': {
                'slope_min': 5.0,
                'slope_max': 35.0,
                'min_touches': 3,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'rsi_max': 40.0,
                'vol_ratio_max': None
            }
        },
        {
            'name': 'Remove RSI (4-AND)',
            'description': 'No RSI filter',
            'config': {
                'slope_min': 5.0,
                'slope_max': 35.0,
                'min_touches': 3,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'rsi_max': None,
                'vol_ratio_max': 0.7
            }
        },
        {
            'name': 'Remove both (3-AND)',
            'description': 'Trendline + proximity only',
            'config': {
                'slope_min': 5.0,
                'slope_max': 35.0,
                'min_touches': 3,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'rsi_max': None,
                'vol_ratio_max': None
            }
        },
        {
            'name': 'Relax vol_drying (5-AND)',
            'description': 'Vol ratio <0.8 (was <0.7)',
            'config': {
                'slope_min': 5.0,
                'slope_max': 35.0,
                'min_touches': 3,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'rsi_max': 40.0,
                'vol_ratio_max': 0.8
            }
        },
        {
            'name': 'Relax RSI (5-AND)',
            'description': 'RSI <50 (was <40)',
            'config': {
                'slope_min': 5.0,
                'slope_max': 35.0,
                'min_touches': 3,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'rsi_max': 50.0,
                'vol_ratio_max': 0.7
            }
        },
        {
            'name': 'Relax both filters (5-AND)',
            'description': 'RSI <50 + vol <0.8',
            'config': {
                'slope_min': 5.0,
                'slope_max': 35.0,
                'min_touches': 3,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'rsi_max': 50.0,
                'vol_ratio_max': 0.8
            }
        },
        {
            'name': 'Widen proximity (3-AND)',
            'description': 'Proximity -5% to +10% (was -3% to +5%)',
            'config': {
                'slope_min': 5.0,
                'slope_max': 35.0,
                'min_touches': 3,
                'proximity_min': -5.0,
                'proximity_max': 10.0,
                'rsi_max': None,
                'vol_ratio_max': None
            }
        },
        {
            'name': 'Relax slope (3-AND)',
            'description': 'Slope 3-40° (was 5-35°)',
            'config': {
                'slope_min': 3.0,
                'slope_max': 40.0,
                'min_touches': 3,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'rsi_max': None,
                'vol_ratio_max': None
            }
        },
        {
            'name': 'Reduce touches (3-AND)',
            'description': 'Min touches = 2 (was 3)',
            'config': {
                'slope_min': 5.0,
                'slope_max': 35.0,
                'min_touches': 2,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'rsi_max': None,
                'vol_ratio_max': None
            }
        }
    ]
    
    # Run experiments
    results = []
    
    for i, exp in enumerate(experiments, 1):
        print(f"\n{'='*60}")
        print(f"EXPERIMENT {i}/{len(experiments)}: {exp['name']}")
        print(f"{'='*60}")
        print(f"Description: {exp['description']}")
        
        result = backtest_tori(df, exp['config'])
        
        print(f"\nResults:")
        print(f"  Signals:   {result['signals']}")
        print(f"  Edge (h20): {result['edge']:+.2f}%", end='')
        
        if result['edge'] > 0:
            print(" ✅")
        else:
            print(" ❌")
        
        print(f"  Win rate:  {result['win_rate']:.1f}%")
        
        if result['signals'] > 0:
            print(f"  Avg win:   +{result['avg_win']:.2f}%")
            print(f"  Avg loss:  {result['avg_loss']:.2f}%")
            print(f"  Frequency: {result['signals'] / years:.2f} signals/year")
        
        results.append({
            'name': exp['name'],
            'description': exp['description'],
            'config': exp['config'],
            'results': result
        })
    
    # Summary
    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)
    
    # Sort by edge
    results_sorted = sorted(results, key=lambda x: x['results']['edge'], reverse=True)
    
    print("\nExperiments sorted by edge (BEST FIRST):")
    for i, r in enumerate(results_sorted, 1):
        emoji = "🥇" if i == 1 else "🥈" if i == 2 else "🥉" if i == 3 else "  "
        edge = r['results']['edge']
        signals = r['results']['signals']
        
        print(f"{emoji} {i:2d}. {r['name']:30s}: {edge:+6.2f}% ({signals:3d} signals)")
    
    # Best config
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
    print(f"  Signals:   {best['results']['signals']}")
    print(f"  Edge (h20): {best['results']['edge']:+.2f}% ✅")
    print(f"  Win rate:  {best['results']['win_rate']:.1f}%")
    print(f"  Avg win:   +{best['results']['avg_win']:.2f}%")
    print(f"  Avg loss:  {best['results']['avg_loss']:.2f}%")
    print(f"  Frequency: {best['results']['signals'] / years:.2f} signals/year")
    
    # Save results
    output = {
        'timestamp': datetime.now().isoformat(),
        'market': 'BTCUSDT',
        'period': '1d',
        'candles': len(df),
        'years': float(years),
        'experiments': results,
        'best': best
    }
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = f"journal/tori_optimization_{timestamp}.json"
    
    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)
    
    print(f"\n[OK] Results saved: {output_file}")
    
    print("\n" + "="*60)
    print("OPTIMIZATION COMPLETE")
    print("="*60)


if __name__ == '__main__':
    optimize_tori()
