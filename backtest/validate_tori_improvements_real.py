#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
validate_tori_improvements_real.py -- Validação REAL de melhorias Tori

PROBLEMA: Análise anterior fez SUPOSIÇÕES sem dados reais
- "Regime filter melhora edge" - NÃO TESTADO!
- "Take-profit melhora edge" - NÃO TESTADO!
- "ROI +76pp/ano" - FANTASIA!

SOLUÇÃO: Testar TUDO com dados reais (TDD)

EXPERIMENTOS:
1. Baseline (3 touches, slope 5-35°)
2. + Regime filter (only bull years)
3. + Regime filter (only bear years)
4. + Regime filter (only other years)
5. + Take-profit at +5%
6. + Take-profit at +10%
7. + Take-profit at +15%
8. + Momentum filter (close > SMA200)
9. + Combined (best filters)

METODOLOGIA TDD:
- Testar CADA hipótese separadamente
- Medir edge REAL (median + mean + trimmed)
- Comparar com baseline
- SEM SUPOSIÇÕES, só dados

VALIDATED: 2026-05-23 TDD
"""

import json
import numpy as np
import pandas as pd
from datetime import datetime
from lib_data_fetcher import fetch_ohlcv
from scipy import stats


def backtest_tori_with_filters(df, config):
    """
    Backtest Tori with filters
    
    Returns:
        signals: list of signals
        stats: dict with statistics
    """
    highs = df['high'].values
    lows = df['low'].values
    closes = df['close'].values
    volumes = df['volume'].values
    timestamps = df['timestamp'].values
    
    # Config
    lookback = config.get('lookback', 20)
    slope_min = config.get('slope_min', 5.0)
    slope_max = config.get('slope_max', 35.0)
    min_touches = config.get('min_touches', 3)
    touch_tolerance = config.get('touch_tolerance', 1.5)
    proximity_min = config.get('proximity_min', -3.0)
    proximity_max = config.get('proximity_max', 5.0)
    
    # Filters
    regime_filter = config.get('regime_filter', None)  # 'bull', 'bear', 'other', None
    momentum_filter = config.get('momentum_filter', False)
    take_profit = config.get('take_profit', None)  # None, 5, 10, 15
    
    # Calculate SMA200 for momentum filter
    sma200 = None
    if momentum_filter:
        sma200 = pd.Series(closes).rolling(200).mean().values
    
    signals = []
    
    for i in range(lookback, len(closes)):
        # Get window
        window_lows = lows[i-lookback:i+1]
        window_closes = closes[i-lookback:i+1]
        
        # 1. Linear regression on lows
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
        
        # 2. Count touches
        touches = 0
        for j, low in enumerate(window_lows):
            line_val = intercept + slope * j
            if line_val > 0:
                diff_pct = abs(low - line_val) / line_val * 100
                if diff_pct <= touch_tolerance:
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
        
        # 4. Regime filter
        entry_date = pd.Timestamp(timestamps[i])
        year = entry_date.year
        
        if regime_filter == 'bull':
            bull_years = [2013, 2017, 2020, 2021, 2024, 2025]
            if year not in bull_years:
                continue
        elif regime_filter == 'bear':
            bear_years = [2014, 2015, 2018, 2022]
            if year not in bear_years:
                continue
        elif regime_filter == 'other':
            bull_years = [2013, 2017, 2020, 2021, 2024, 2025]
            bear_years = [2014, 2015, 2018, 2022]
            if year in bull_years or year in bear_years:
                continue
        
        # 5. Momentum filter
        if momentum_filter:
            if sma200 is None or i < 200:
                continue
            if closes[i] <= sma200[i]:
                continue
        
        # Signal detected!
        entry_price = closes[i]
        
        # Calculate exit
        if take_profit is not None:
            # Find first candle that hits TP or h20, whichever comes first
            exit_idx = i + 1
            exit_price = entry_price
            
            for j in range(i + 1, min(i + 21, len(closes))):
                # Check if TP hit
                pnl_pct = (closes[j] - entry_price) / entry_price * 100
                if pnl_pct >= take_profit:
                    exit_idx = j
                    exit_price = entry_price * (1 + take_profit / 100)
                    break
                exit_idx = j
                exit_price = closes[j]
        else:
            # h20 (20 candles forward)
            exit_idx = min(i + 20, len(closes) - 1)
            exit_price = closes[exit_idx]
        
        pnl_pct = (exit_price - entry_price) / entry_price * 100
        
        signals.append({
            'index': i,
            'entry_date': str(entry_date),
            'year': year,
            'entry_price': float(entry_price),
            'exit_price': float(exit_price),
            'exit_idx': exit_idx,
            'pnl_pct': float(pnl_pct),
            'slope_deg': float(slope_deg),
            'touches': int(touches),
            'proximity_pct': float(proximity_pct)
        })
    
    # Calculate statistics
    if len(signals) == 0:
        return signals, {
            'count': 0,
            'mean': 0,
            'median': 0,
            'trimmed_mean_10': 0,
            'std': 0,
            'min': 0,
            'max': 0,
            'win_rate': 0,
            'avg_win': 0,
            'avg_loss': 0
        }
    
    pnls = [s['pnl_pct'] for s in signals]
    wins = [p for p in pnls if p > 0]
    losses = [p for p in pnls if p <= 0]
    
    return signals, {
        'count': len(signals),
        'mean': float(np.mean(pnls)),
        'median': float(np.median(pnls)),
        'trimmed_mean_10': float(stats.trim_mean(pnls, 0.10)),
        'std': float(np.std(pnls)),
        'min': float(np.min(pnls)),
        'max': float(np.max(pnls)),
        'win_rate': float(len(wins) / len(signals) * 100),
        'avg_win': float(np.mean(wins)) if wins else 0,
        'avg_loss': float(np.mean(losses)) if losses else 0
    }


def validate_improvements():
    """
    Validate ALL improvement hypotheses with REAL data
    """
    print("="*60)
    print("TORI IMPROVEMENTS VALIDATION (TDD)")
    print("Testing ALL hypotheses with REAL data")
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
            'name': 'Baseline (3 touches)',
            'description': 'No filters',
            'config': {
                'min_touches': 3,
                'slope_min': 5.0,
                'slope_max': 35.0,
                'proximity_min': -3.0,
                'proximity_max': 5.0
            }
        },
        {
            'name': 'Regime: Bull years only',
            'description': 'Only trade in bull years (2013, 2017, 2020, 2021, 2024, 2025)',
            'config': {
                'min_touches': 3,
                'slope_min': 5.0,
                'slope_max': 35.0,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'regime_filter': 'bull'
            }
        },
        {
            'name': 'Regime: Bear years only',
            'description': 'Only trade in bear years (2014, 2015, 2018, 2022)',
            'config': {
                'min_touches': 3,
                'slope_min': 5.0,
                'slope_max': 35.0,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'regime_filter': 'bear'
            }
        },
        {
            'name': 'Regime: Other years only',
            'description': 'Only trade in other years (consolidation)',
            'config': {
                'min_touches': 3,
                'slope_min': 5.0,
                'slope_max': 35.0,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'regime_filter': 'other'
            }
        },
        {
            'name': 'Take-Profit: +5%',
            'description': 'Exit at +5% or h20, whichever comes first',
            'config': {
                'min_touches': 3,
                'slope_min': 5.0,
                'slope_max': 35.0,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'take_profit': 5.0
            }
        },
        {
            'name': 'Take-Profit: +10%',
            'description': 'Exit at +10% or h20, whichever comes first',
            'config': {
                'min_touches': 3,
                'slope_min': 5.0,
                'slope_max': 35.0,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'take_profit': 10.0
            }
        },
        {
            'name': 'Take-Profit: +15%',
            'description': 'Exit at +15% or h20, whichever comes first',
            'config': {
                'min_touches': 3,
                'slope_min': 5.0,
                'slope_max': 35.0,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'take_profit': 15.0
            }
        },
        {
            'name': 'Momentum: Close > SMA200',
            'description': 'Only trade when price above SMA200',
            'config': {
                'min_touches': 3,
                'slope_min': 5.0,
                'slope_max': 35.0,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'momentum_filter': True
            }
        },
        {
            'name': 'Combined: Other years + TP5%',
            'description': 'Best regime + best TP',
            'config': {
                'min_touches': 3,
                'slope_min': 5.0,
                'slope_max': 35.0,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'regime_filter': 'other',
                'take_profit': 5.0
            }
        },
        {
            'name': 'Combined: Momentum + TP5%',
            'description': 'Momentum + TP',
            'config': {
                'min_touches': 3,
                'slope_min': 5.0,
                'slope_max': 35.0,
                'proximity_min': -3.0,
                'proximity_max': 5.0,
                'momentum_filter': True,
                'take_profit': 5.0
            }
        }
    ]
    
    # Run experiments
    print("\n" + "="*60)
    print("RUNNING EXPERIMENTS")
    print("="*60)
    
    results = []
    baseline_stats = None
    
    for i, exp in enumerate(experiments, 1):
        print(f"\n[{i}/{len(experiments)}] {exp['name']}")
        print(f"  {exp['description']}")
        
        signals, stats_dict = backtest_tori_with_filters(df, exp['config'])
        
        if i == 1:
            baseline_stats = stats_dict
        
        print(f"\n  Results:")
        print(f"    Signals:         {stats_dict['count']}")
        print(f"    Mean:            {stats_dict['mean']:+.2f}%")
        print(f"    Median:          {stats_dict['median']:+.2f}%", end='')
        
        if baseline_stats and i > 1:
            delta = stats_dict['median'] - baseline_stats['median']
            print(f" (Δ {delta:+.2f}pp)", end='')
        
        if stats_dict['median'] > 0:
            print(" ✅")
        else:
            print(" ❌")
        
        print(f"    Trimmed mean 10%: {stats_dict['trimmed_mean_10']:+.2f}%")
        print(f"    Win rate:        {stats_dict['win_rate']:.1f}%")
        
        if stats_dict['count'] > 0:
            print(f"    Frequency:       {stats_dict['count'] / years:.1f} signals/year")
        
        results.append({
            'name': exp['name'],
            'description': exp['description'],
            'config': exp['config'],
            'stats': stats_dict,
            'signals': signals
        })
    
    # Analysis
    print("\n" + "="*60)
    print("COMPARATIVE ANALYSIS")
    print("="*60)
    
    # Sort by median
    results_sorted = sorted(results, key=lambda x: x['stats']['median'], reverse=True)
    
    print("\nSorted by MEDIAN edge (REAL edge):")
    for i, r in enumerate(results_sorted, 1):
        emoji = "🥇" if i == 1 else "🥈" if i == 2 else "🥉" if i == 3 else "  "
        median = r['stats']['median']
        count = r['stats']['count']
        
        # Delta vs baseline
        if r['name'] == 'Baseline (3 touches)':
            delta_str = "(baseline)"
        else:
            delta = median - baseline_stats['median']
            delta_str = f"(Δ {delta:+.2f}pp)"
        
        print(f"{emoji} {i:2d}. {r['name']:30s}: {median:+6.2f}% {delta_str:15s} ({count:3d} signals)")
    
    # Best improvement
    best = results_sorted[0]
    baseline = [r for r in results if r['name'] == 'Baseline (3 touches)'][0]
    
    print("\n" + "="*60)
    print("BEST IMPROVEMENT")
    print("="*60)
    
    print(f"\nBest: {best['name']}")
    print(f"Description: {best['description']}")
    
    print(f"\nBaseline:")
    print(f"  Median: {baseline['stats']['median']:+.2f}%")
    print(f"  Signals: {baseline['stats']['count']}")
    print(f"  Frequency: {baseline['stats']['count'] / years:.1f}/year")
    
    print(f"\nBest:")
    print(f"  Median: {best['stats']['median']:+.2f}%")
    print(f"  Signals: {best['stats']['count']}")
    print(f"  Frequency: {best['stats']['count'] / years:.1f}/year")
    
    improvement = best['stats']['median'] - baseline['stats']['median']
    print(f"\nImprovement:")
    print(f"  Median edge: {improvement:+.2f}pp")
    print(f"  Signals: {best['stats']['count'] - baseline['stats']['count']:+d}")
    
    # Statistical significance
    print("\n" + "="*60)
    print("STATISTICAL SIGNIFICANCE")
    print("="*60)
    
    if best['stats']['count'] >= 30 and baseline['stats']['count'] >= 30:
        # T-test
        best_pnls = [s['pnl_pct'] for s in best['signals']]
        baseline_pnls = [s['pnl_pct'] for s in baseline['signals']]
        
        from scipy.stats import ttest_ind
        t_stat, p_value = ttest_ind(best_pnls, baseline_pnls)
        
        print(f"\nT-test (best vs baseline):")
        print(f"  t-statistic: {t_stat:.4f}")
        print(f"  p-value: {p_value:.4f}")
        
        if p_value < 0.05:
            print(f"  Result: STATISTICALLY SIGNIFICANT (p < 0.05) ✅")
        else:
            print(f"  Result: NOT significant (p >= 0.05) ⚠️")
    else:
        print("\n⚠️  Sample size too small for statistical test")
        print(f"  Best: {best['stats']['count']} signals")
        print(f"  Baseline: {baseline['stats']['count']} signals")
        print(f"  Need: 30+ signals each")
    
    # Save results
    output = {
        'timestamp': datetime.now().isoformat(),
        'market': 'BTCUSDT',
        'period': '1d',
        'candles': len(df),
        'years': float(years),
        'experiments': results,
        'best': best,
        'baseline': baseline,
        'improvement': {
            'median_delta': float(improvement),
            'signals_delta': best['stats']['count'] - baseline['stats']['count']
        }
    }
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = f"journal/tori_improvements_validation_{timestamp}.json"
    
    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)
    
    print(f"\n[OK] Results saved: {output_file}")
    
    print("\n" + "="*60)
    print("VALIDATION COMPLETE")
    print("="*60)


if __name__ == '__main__':
    validate_improvements()
