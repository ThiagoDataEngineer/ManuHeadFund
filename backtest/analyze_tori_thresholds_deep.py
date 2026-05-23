#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
analyze_tori_thresholds_deep.py -- Análise profunda de thresholds Tori

OBJETIVO: Identificar ONDE os thresholds estão bloqueando signals

METODOLOGIA TDD:
1. Testar cada threshold individualmente
2. Identificar gargalos (qual threshold bloqueia mais)
3. Propor thresholds otimizados
4. Validar edge com novos thresholds

VALIDATED: 2026-05-23 TDD
"""

import json
import numpy as np
from datetime import datetime
from lib_data_fetcher import fetch_ohlcv
from lib_backtest_rsi_fixed import calculate_rsi


def analyze_tori_thresholds():
    """
    Analyze Tori thresholds to identify bottlenecks
    """
    print("="*60)
    print("TORI THRESHOLD ANALYSIS (TDD)")
    print("Identifying bottlenecks in pattern detection")
    print("="*60)
    
    # Load data
    print("\nLoading historical data...")
    df = fetch_ohlcv('BTCUSDT', '1d')
    
    if df is None or len(df) == 0:
        print("[ERROR] Failed to load data")
        return
    
    print(f"  [OK] Loaded {len(df)} candles")
    print(f"  Date range: {df['timestamp'].iloc[0]} to {df['timestamp'].iloc[-1]}")
    
    years = (df['timestamp'].iloc[-1] - df['timestamp'].iloc[0]).days / 365.25
    print(f"  Period: {years:.1f} years")
    
    # Extract arrays
    highs = df['high'].values
    lows = df['low'].values
    closes = df['close'].values
    volumes = df['volume'].values
    
    # Thresholds to test
    lookback = 20
    min_touches = 3
    
    print("\n" + "="*60)
    print("THRESHOLD ANALYSIS")
    print("="*60)
    
    # Track statistics
    stats = {
        'total_candles': 0,
        'valid_trendline': 0,
        'valid_slope': 0,
        'valid_touches': 0,
        'valid_proximity': 0,
        'valid_rsi': 0,
        'valid_vol_drying': 0,
        'all_conditions': 0
    }
    
    # Detailed breakdown
    slope_distribution = []
    touches_distribution = []
    proximity_distribution = []
    rsi_distribution = []
    vol_ratio_distribution = []
    
    # Scan all candles
    print(f"\nScanning {len(closes)} candles...")
    
    for i in range(lookback, len(closes)):
        if i % 500 == 0:
            pct = int(i / len(closes) * 100)
            print(f"  Progress: {pct}% ({i}/{len(closes)})", end='\r')
        
        stats['total_candles'] += 1
        
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
        slope_distribution.append(slope_deg)
        
        # Check slope range (5-35 degrees)
        slope_ok = 5.0 <= slope_deg <= 35.0
        if slope_ok:
            stats['valid_slope'] += 1
        
        # 2. Count touches
        touches = 0
        for j, low in enumerate(window_lows):
            line_val = intercept + slope * j
            if line_val > 0:
                diff_pct = abs(low - line_val) / line_val * 100
                if diff_pct <= 1.5:
                    touches += 1
        
        touches_distribution.append(touches)
        
        touches_ok = touches >= min_touches
        if touches_ok:
            stats['valid_touches'] += 1
        
        # Trendline valid = slope + touches
        trendline_valid = slope_ok and touches_ok
        if trendline_valid:
            stats['valid_trendline'] += 1
        
        # 3. Proximity
        current_price = window_closes[-1]
        line_current = intercept + slope * (len(window_lows) - 1)
        
        if line_current > 0:
            proximity_pct = (current_price - line_current) / line_current * 100
        else:
            proximity_pct = 0
        
        proximity_distribution.append(proximity_pct)
        
        proximity_ok = -3.0 <= proximity_pct <= 5.0
        if proximity_ok:
            stats['valid_proximity'] += 1
        
        # 4. RSI
        rsi_val = calculate_rsi(window_closes)
        if isinstance(rsi_val, (list, np.ndarray)):
            rsi_val = rsi_val[-1] if len(rsi_val) > 0 else 50.0
        
        rsi_distribution.append(rsi_val)
        
        rsi_ok = rsi_val < 40.0
        if rsi_ok:
            stats['valid_rsi'] += 1
        
        # 5. Volume drying
        if len(window_volumes) >= 10:
            recent_vol = np.mean(window_volumes[-3:])
            prior_vol = np.mean(window_volumes[-10:-3])
            vol_ratio = recent_vol / prior_vol if prior_vol > 0 else 1.0
        else:
            vol_ratio = 1.0
        
        vol_ratio_distribution.append(vol_ratio)
        
        vol_drying = vol_ratio < 0.7
        if vol_drying:
            stats['valid_vol_drying'] += 1
        
        # All conditions
        all_ok = trendline_valid and proximity_ok and rsi_ok and vol_drying
        if all_ok:
            stats['all_conditions'] += 1
    
    print(f"\n  Completed: {len(closes)} candles scanned")
    
    # Results
    print("\n" + "="*60)
    print("BOTTLENECK ANALYSIS")
    print("="*60)
    
    total = stats['total_candles']
    
    print(f"\nTotal candles analyzed: {total}")
    print(f"\nCondition pass rates:")
    print(f"  1. Valid slope (5-35°):     {stats['valid_slope']:5d} ({stats['valid_slope']/total*100:5.1f}%)")
    print(f"  2. Valid touches (>=3):     {stats['valid_touches']:5d} ({stats['valid_touches']/total*100:5.1f}%)")
    print(f"  3. Valid trendline (1+2):   {stats['valid_trendline']:5d} ({stats['valid_trendline']/total*100:5.1f}%)")
    print(f"  4. Valid proximity (-3/+5): {stats['valid_proximity']:5d} ({stats['valid_proximity']/total*100:5.1f}%)")
    print(f"  5. Valid RSI (<40):         {stats['valid_rsi']:5d} ({stats['valid_rsi']/total*100:5.1f}%)")
    print(f"  6. Vol drying (<70%):       {stats['valid_vol_drying']:5d} ({stats['valid_vol_drying']/total*100:5.1f}%)")
    print(f"  7. ALL conditions (5-AND):  {stats['all_conditions']:5d} ({stats['all_conditions']/total*100:5.1f}%)")
    
    # Identify bottleneck
    print("\n" + "="*60)
    print("BOTTLENECK IDENTIFICATION")
    print("="*60)
    
    bottlenecks = [
        ('Valid trendline', stats['valid_trendline'], stats['valid_trendline']/total*100),
        ('Valid proximity', stats['valid_proximity'], stats['valid_proximity']/total*100),
        ('Valid RSI', stats['valid_rsi'], stats['valid_rsi']/total*100),
        ('Vol drying', stats['valid_vol_drying'], stats['valid_vol_drying']/total*100),
    ]
    
    bottlenecks.sort(key=lambda x: x[2])
    
    print("\nConditions sorted by pass rate (LOWEST = BOTTLENECK):")
    for i, (name, count, pct) in enumerate(bottlenecks, 1):
        emoji = "🔴" if i == 1 else "🟡" if i == 2 else "🟢"
        print(f"  {emoji} {i}. {name:20s}: {pct:5.1f}% ({count} candles)")
    
    # Distribution analysis
    print("\n" + "="*60)
    print("DISTRIBUTION ANALYSIS")
    print("="*60)
    
    print("\nSlope distribution (degrees):")
    print(f"  Min:    {np.min(slope_distribution):7.2f}°")
    print(f"  P10:    {np.percentile(slope_distribution, 10):7.2f}°")
    print(f"  P25:    {np.percentile(slope_distribution, 25):7.2f}°")
    print(f"  Median: {np.percentile(slope_distribution, 50):7.2f}°")
    print(f"  P75:    {np.percentile(slope_distribution, 75):7.2f}°")
    print(f"  P90:    {np.percentile(slope_distribution, 90):7.2f}°")
    print(f"  Max:    {np.max(slope_distribution):7.2f}°")
    print(f"  Current threshold: 5-35° (captures {stats['valid_slope']/total*100:.1f}%)")
    
    print("\nTouches distribution:")
    print(f"  Min:    {np.min(touches_distribution):7.0f}")
    print(f"  P10:    {np.percentile(touches_distribution, 10):7.0f}")
    print(f"  P25:    {np.percentile(touches_distribution, 25):7.0f}")
    print(f"  Median: {np.percentile(touches_distribution, 50):7.0f}")
    print(f"  P75:    {np.percentile(touches_distribution, 75):7.0f}")
    print(f"  P90:    {np.percentile(touches_distribution, 90):7.0f}")
    print(f"  Max:    {np.max(touches_distribution):7.0f}")
    print(f"  Current threshold: >=3 (captures {stats['valid_touches']/total*100:.1f}%)")
    
    print("\nProximity distribution (%):")
    print(f"  Min:    {np.min(proximity_distribution):7.2f}%")
    print(f"  P10:    {np.percentile(proximity_distribution, 10):7.2f}%")
    print(f"  P25:    {np.percentile(proximity_distribution, 25):7.2f}%")
    print(f"  Median: {np.percentile(proximity_distribution, 50):7.2f}%")
    print(f"  P75:    {np.percentile(proximity_distribution, 75):7.2f}%")
    print(f"  P90:    {np.percentile(proximity_distribution, 90):7.2f}%")
    print(f"  Max:    {np.max(proximity_distribution):7.2f}%")
    print(f"  Current threshold: -3% to +5% (captures {stats['valid_proximity']/total*100:.1f}%)")
    
    print("\nRSI distribution:")
    print(f"  Min:    {np.min(rsi_distribution):7.2f}")
    print(f"  P10:    {np.percentile(rsi_distribution, 10):7.2f}")
    print(f"  P25:    {np.percentile(rsi_distribution, 25):7.2f}")
    print(f"  Median: {np.percentile(rsi_distribution, 50):7.2f}")
    print(f"  P75:    {np.percentile(rsi_distribution, 75):7.2f}")
    print(f"  P90:    {np.percentile(rsi_distribution, 90):7.2f}")
    print(f"  Max:    {np.max(rsi_distribution):7.2f}")
    print(f"  Current threshold: <40 (captures {stats['valid_rsi']/total*100:.1f}%)")
    
    print("\nVolume ratio distribution:")
    print(f"  Min:    {np.min(vol_ratio_distribution):7.2f}")
    print(f"  P10:    {np.percentile(vol_ratio_distribution, 10):7.2f}")
    print(f"  P25:    {np.percentile(vol_ratio_distribution, 25):7.2f}")
    print(f"  Median: {np.percentile(vol_ratio_distribution, 50):7.2f}")
    print(f"  P75:    {np.percentile(vol_ratio_distribution, 75):7.2f}")
    print(f"  P90:    {np.percentile(vol_ratio_distribution, 90):7.2f}")
    print(f"  Max:    {np.max(vol_ratio_distribution):7.2f}")
    print(f"  Current threshold: <0.7 (captures {stats['valid_vol_drying']/total*100:.1f}%)")
    
    # Recommendations
    print("\n" + "="*60)
    print("RECOMMENDATIONS")
    print("="*60)
    
    print("\nBased on bottleneck analysis:")
    
    # Find most restrictive
    most_restrictive = bottlenecks[0]
    print(f"\n🔴 MOST RESTRICTIVE: {most_restrictive[0]} ({most_restrictive[2]:.1f}%)")
    
    if 'trendline' in most_restrictive[0].lower():
        print("   → Relax slope range (e.g., 3-40°)")
        print("   → Reduce min touches (e.g., 2)")
    elif 'proximity' in most_restrictive[0].lower():
        print("   → Widen proximity range (e.g., -5% to +10%)")
    elif 'rsi' in most_restrictive[0].lower():
        print("   → Increase RSI threshold (e.g., <50)")
        print("   → Or REMOVE RSI filter (may be unnecessary)")
    elif 'vol' in most_restrictive[0].lower():
        print("   → Relax vol drying (e.g., <0.8)")
        print("   → Or REMOVE vol filter (may be unnecessary)")
    
    # Save results
    results = {
        'timestamp': datetime.now().isoformat(),
        'market': 'BTCUSDT',
        'period': '1d',
        'candles': len(df),
        'years': float(years),
        'stats': stats,
        'bottlenecks': [
            {'name': name, 'count': count, 'pct': float(pct)}
            for name, count, pct in bottlenecks
        ],
        'distributions': {
            'slope': {
                'min': float(np.min(slope_distribution)),
                'p10': float(np.percentile(slope_distribution, 10)),
                'p25': float(np.percentile(slope_distribution, 25)),
                'median': float(np.percentile(slope_distribution, 50)),
                'p75': float(np.percentile(slope_distribution, 75)),
                'p90': float(np.percentile(slope_distribution, 90)),
                'max': float(np.max(slope_distribution))
            },
            'touches': {
                'min': int(np.min(touches_distribution)),
                'p10': int(np.percentile(touches_distribution, 10)),
                'p25': int(np.percentile(touches_distribution, 25)),
                'median': int(np.percentile(touches_distribution, 50)),
                'p75': int(np.percentile(touches_distribution, 75)),
                'p90': int(np.percentile(touches_distribution, 90)),
                'max': int(np.max(touches_distribution))
            },
            'proximity': {
                'min': float(np.min(proximity_distribution)),
                'p10': float(np.percentile(proximity_distribution, 10)),
                'p25': float(np.percentile(proximity_distribution, 25)),
                'median': float(np.percentile(proximity_distribution, 50)),
                'p75': float(np.percentile(proximity_distribution, 75)),
                'p90': float(np.percentile(proximity_distribution, 90)),
                'max': float(np.max(proximity_distribution))
            },
            'rsi': {
                'min': float(np.min(rsi_distribution)),
                'p10': float(np.percentile(rsi_distribution, 10)),
                'p25': float(np.percentile(rsi_distribution, 25)),
                'median': float(np.percentile(rsi_distribution, 50)),
                'p75': float(np.percentile(rsi_distribution, 75)),
                'p90': float(np.percentile(rsi_distribution, 90)),
                'max': float(np.max(rsi_distribution))
            },
            'vol_ratio': {
                'min': float(np.min(vol_ratio_distribution)),
                'p10': float(np.percentile(vol_ratio_distribution, 10)),
                'p25': float(np.percentile(vol_ratio_distribution, 25)),
                'median': float(np.percentile(vol_ratio_distribution, 50)),
                'p75': float(np.percentile(vol_ratio_distribution, 75)),
                'p90': float(np.percentile(vol_ratio_distribution, 90)),
                'max': float(np.max(vol_ratio_distribution))
            }
        }
    }
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = f"journal/tori_threshold_analysis_{timestamp}.json"
    
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"\n[OK] Results saved: {output_file}")
    
    print("\n" + "="*60)
    print("ANALYSIS COMPLETE")
    print("="*60)


if __name__ == '__main__':
    analyze_tori_thresholds()
