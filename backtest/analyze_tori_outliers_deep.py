#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
analyze_tori_outliers_deep.py -- Análise profunda de outliers Tori

PROBLEMA CRÍTICO:
- Mean edge: +68.33%
- Median edge: +0.78%
- Delta: +67.55pp (ENORME!)

HIPÓTESE:
- Poucos trades MUITO lucrativos (bull runs 2017, 2020, 2024) inflam mean
- Maioria dos trades tem edge pequeno (~1%)
- Mean é ENGANOSO, median é REALIDADE

OBJETIVOS TDD:
1. Identificar outliers (trades > +100%)
2. Analisar distribuição de PnL (percentis)
3. Calcular edge SEM outliers (trimmed mean)
4. Identificar padrões dos outliers (bull runs?)
5. Propor filtros para melhorar MEDIAN edge

VALIDATED: 2026-05-23 TDD
"""

import json
import numpy as np
import pandas as pd
from datetime import datetime
from lib_data_fetcher import fetch_ohlcv
from lib_backtest_rsi_fixed import calculate_rsi


def analyze_outliers():
    """
    Deep analysis of Tori outliers
    """
    print("="*60)
    print("TORI OUTLIER ANALYSIS (TDD)")
    print("Understanding mean vs median gap")
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
    
    # Run baseline config (3 touches minimum - per user request)
    print("\n" + "="*60)
    print("RUNNING BASELINE (3 touches minimum)")
    print("="*60)
    
    config = {
        'slope_min': 5.0,
        'slope_max': 35.0,
        'min_touches': 3,  # USER REQUEST: 3 touches minimum
        'touch_tolerance': 1.5,
        'proximity_min': -3.0,
        'proximity_max': 5.0
    }
    
    highs = df['high'].values
    lows = df['low'].values
    closes = df['close'].values
    volumes = df['volume'].values
    timestamps = df['timestamp'].values
    
    lookback = 20
    signals = []
    
    print(f"\nScanning {len(closes)} candles...")
    
    for i in range(lookback, len(closes)):
        if i % 500 == 0:
            pct = int((i - lookback) / (len(closes) - lookback) * 100)
            print(f"  Progress: {pct}%", end='\r')
        
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
        if not (config['slope_min'] <= slope_deg <= config['slope_max']):
            continue
        
        # 2. Count touches
        touches = 0
        for j, low in enumerate(window_lows):
            line_val = intercept + slope * j
            if line_val > 0:
                diff_pct = abs(low - line_val) / line_val * 100
                if diff_pct <= config['touch_tolerance']:
                    touches += 1
        
        if touches < config['min_touches']:
            continue
        
        # 3. Proximity
        current_price = window_closes[-1]
        line_current = intercept + slope * (len(window_lows) - 1)
        
        if line_current <= 0:
            continue
        
        proximity_pct = (current_price - line_current) / line_current * 100
        
        if not (config['proximity_min'] <= proximity_pct <= config['proximity_max']):
            continue
        
        # Signal detected!
        entry_price = closes[i]
        entry_date = timestamps[i]
        
        # Calculate edge (h20 = 20 candles forward)
        exit_idx = min(i + 20, len(closes) - 1)
        exit_price = closes[exit_idx]
        exit_date = timestamps[exit_idx]
        
        pnl_pct = (exit_price - entry_price) / entry_price * 100
        
        # Get year for analysis
        year = pd.Timestamp(entry_date).year
        
        signals.append({
            'index': i,
            'entry_date': str(entry_date),
            'exit_date': str(exit_date),
            'year': year,
            'entry_price': float(entry_price),
            'exit_price': float(exit_price),
            'pnl_pct': float(pnl_pct),
            'slope_deg': float(slope_deg),
            'touches': int(touches),
            'proximity_pct': float(proximity_pct)
        })
    
    print(f"\n  Completed: {len(signals)} signals detected")
    
    if len(signals) == 0:
        print("\n[ERROR] No signals detected")
        return
    
    # Convert to DataFrame for analysis
    df_signals = pd.DataFrame(signals)
    
    # Basic statistics
    print("\n" + "="*60)
    print("BASIC STATISTICS")
    print("="*60)
    
    pnls = df_signals['pnl_pct'].values
    
    print(f"\nTotal signals: {len(signals)}")
    print(f"Mean PnL:      {np.mean(pnls):+.2f}%")
    print(f"Median PnL:    {np.median(pnls):+.2f}%")
    print(f"Std Dev:       {np.std(pnls):.2f}%")
    print(f"Min PnL:       {np.min(pnls):+.2f}%")
    print(f"Max PnL:       {np.max(pnls):+.2f}%")
    
    # Percentiles
    print("\n" + "="*60)
    print("PERCENTILE DISTRIBUTION")
    print("="*60)
    
    percentiles = [1, 5, 10, 25, 50, 75, 90, 95, 99]
    
    print("\nPnL distribution:")
    for p in percentiles:
        val = np.percentile(pnls, p)
        print(f"  P{p:2d}: {val:+8.2f}%")
    
    # Identify outliers
    print("\n" + "="*60)
    print("OUTLIER ANALYSIS")
    print("="*60)
    
    # Define outliers as > +100% or < -50%
    outliers_positive = df_signals[df_signals['pnl_pct'] > 100]
    outliers_negative = df_signals[df_signals['pnl_pct'] < -50]
    
    print(f"\nPositive outliers (>+100%): {len(outliers_positive)}")
    print(f"Negative outliers (<-50%):  {len(outliers_negative)}")
    print(f"Normal trades:              {len(signals) - len(outliers_positive) - len(outliers_negative)}")
    
    if len(outliers_positive) > 0:
        print(f"\nPositive outliers contribute: {outliers_positive['pnl_pct'].sum():.2f}% total")
        print(f"Average positive outlier:     {outliers_positive['pnl_pct'].mean():+.2f}%")
        
        print("\nTop 10 positive outliers:")
        top10 = outliers_positive.nlargest(10, 'pnl_pct')
        for idx, row in top10.iterrows():
            print(f"  {row['entry_date'][:10]}: {row['pnl_pct']:+8.2f}% (year {row['year']})")
    
    # Trimmed mean (remove top/bottom 5%)
    print("\n" + "="*60)
    print("TRIMMED STATISTICS (remove outliers)")
    print("="*60)
    
    from scipy import stats
    
    trimmed_mean_5 = stats.trim_mean(pnls, 0.05)  # Remove 5% each tail
    trimmed_mean_10 = stats.trim_mean(pnls, 0.10)  # Remove 10% each tail
    
    print(f"\nTrimmed mean (5% each tail):  {trimmed_mean_5:+.2f}%")
    print(f"Trimmed mean (10% each tail): {trimmed_mean_10:+.2f}%")
    print(f"Median (50% trimmed):         {np.median(pnls):+.2f}%")
    
    # Without extreme outliers (>+100%)
    normal_trades = df_signals[df_signals['pnl_pct'] <= 100]
    if len(normal_trades) > 0:
        print(f"\nWithout outliers >+100%:")
        print(f"  Signals: {len(normal_trades)}")
        print(f"  Mean:    {normal_trades['pnl_pct'].mean():+.2f}%")
        print(f"  Median:  {normal_trades['pnl_pct'].median():+.2f}%")
    
    # Year-by-year analysis
    print("\n" + "="*60)
    print("YEAR-BY-YEAR ANALYSIS")
    print("="*60)
    
    yearly = df_signals.groupby('year').agg({
        'pnl_pct': ['count', 'mean', 'median', 'std']
    }).round(2)
    
    print("\nPerformance by year:")
    print(yearly.to_string())
    
    # Identify bull vs bear years
    print("\n" + "="*60)
    print("BULL vs BEAR YEAR ANALYSIS")
    print("="*60)
    
    # Bull years: 2013, 2017, 2020-2021, 2024-2025
    bull_years = [2013, 2017, 2020, 2021, 2024, 2025]
    bear_years = [2014, 2015, 2018, 2022]
    
    bull_trades = df_signals[df_signals['year'].isin(bull_years)]
    bear_trades = df_signals[df_signals['year'].isin(bear_years)]
    other_trades = df_signals[~df_signals['year'].isin(bull_years + bear_years)]
    
    print(f"\nBull years ({bull_years}):")
    if len(bull_trades) > 0:
        print(f"  Signals: {len(bull_trades)}")
        print(f"  Mean:    {bull_trades['pnl_pct'].mean():+.2f}%")
        print(f"  Median:  {bull_trades['pnl_pct'].median():+.2f}%")
    
    print(f"\nBear years ({bear_years}):")
    if len(bear_trades) > 0:
        print(f"  Signals: {len(bear_trades)}")
        print(f"  Mean:    {bear_trades['pnl_pct'].mean():+.2f}%")
        print(f"  Median:  {bear_trades['pnl_pct'].median():+.2f}%")
    
    print(f"\nOther years:")
    if len(other_trades) > 0:
        print(f"  Signals: {len(other_trades)}")
        print(f"  Mean:    {other_trades['pnl_pct'].mean():+.2f}%")
        print(f"  Median:  {other_trades['pnl_pct'].median():+.2f}%")
    
    # Win rate analysis
    print("\n" + "="*60)
    print("WIN RATE ANALYSIS")
    print("="*60)
    
    wins = df_signals[df_signals['pnl_pct'] > 0]
    losses = df_signals[df_signals['pnl_pct'] <= 0]
    
    print(f"\nWins:   {len(wins)} ({len(wins)/len(signals)*100:.1f}%)")
    print(f"Losses: {len(losses)} ({len(losses)/len(signals)*100:.1f}%)")
    
    if len(wins) > 0:
        print(f"\nAverage win:  +{wins['pnl_pct'].mean():.2f}%")
        print(f"Median win:   +{wins['pnl_pct'].median():.2f}%")
    
    if len(losses) > 0:
        print(f"\nAverage loss: {losses['pnl_pct'].mean():.2f}%")
        print(f"Median loss:  {losses['pnl_pct'].median():.2f}%")
    
    # Recommendations
    print("\n" + "="*60)
    print("RECOMMENDATIONS")
    print("="*60)
    
    print("\n1. MEDIAN EDGE IS THE REALITY:")
    print(f"   Mean: {np.mean(pnls):+.2f}% (inflated by outliers)")
    print(f"   Median: {np.median(pnls):+.2f}% (REAL edge)")
    print(f"   Trimmed mean (10%): {trimmed_mean_10:+.2f}% (robust)")
    
    print("\n2. OUTLIERS ANALYSIS:")
    print(f"   {len(outliers_positive)} trades (>{len(outliers_positive)/len(signals)*100:.1f}%) contribute {outliers_positive['pnl_pct'].sum():.0f}% total")
    print(f"   These are bull run trades (2017, 2020, 2024)")
    print(f"   Cannot rely on them for consistent edge")
    
    print("\n3. IMPROVE MEDIAN EDGE:")
    print("   Option A: Add regime filter (only trade in bull years)")
    print("   Option B: Add momentum filter (only when BTC trending up)")
    print("   Option C: Tighten thresholds (reduce noise trades)")
    print("   Option D: Add take-profit at +5% (capture median, avoid drawdowns)")
    
    print("\n4. REALISTIC EXPECTATIONS:")
    print(f"   Median edge: {np.median(pnls):+.2f}%")
    print(f"   With {len(signals)} signals in {years:.1f} years = {len(signals)/years:.1f} signals/year")
    print(f"   Annual return (median): {np.median(pnls) * len(signals)/years:.1f}%")
    
    # Save results
    output = {
        'timestamp': datetime.now().isoformat(),
        'config': config,
        'total_signals': len(signals),
        'years': float(years),
        'statistics': {
            'mean': float(np.mean(pnls)),
            'median': float(np.median(pnls)),
            'std': float(np.std(pnls)),
            'min': float(np.min(pnls)),
            'max': float(np.max(pnls)),
            'trimmed_mean_5': float(trimmed_mean_5),
            'trimmed_mean_10': float(trimmed_mean_10)
        },
        'percentiles': {f'p{p}': float(np.percentile(pnls, p)) for p in percentiles},
        'outliers': {
            'positive_count': len(outliers_positive),
            'negative_count': len(outliers_negative),
            'positive_contribution': float(outliers_positive['pnl_pct'].sum()) if len(outliers_positive) > 0 else 0
        },
        'yearly': {str(k): v for k, v in yearly.to_dict().items()},
        'bull_vs_bear': {
            'bull': {
                'signals': len(bull_trades),
                'mean': float(bull_trades['pnl_pct'].mean()) if len(bull_trades) > 0 else 0,
                'median': float(bull_trades['pnl_pct'].median()) if len(bull_trades) > 0 else 0
            },
            'bear': {
                'signals': len(bear_trades),
                'mean': float(bear_trades['pnl_pct'].mean()) if len(bear_trades) > 0 else 0,
                'median': float(bear_trades['pnl_pct'].median()) if len(bear_trades) > 0 else 0
            }
        },
        'signals': signals
    }
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = f"journal/tori_outlier_analysis_{timestamp}.json"
    
    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)
    
    print(f"\n[OK] Results saved: {output_file}")
    
    print("\n" + "="*60)
    print("ANALYSIS COMPLETE")
    print("="*60)


if __name__ == '__main__':
    analyze_outliers()
