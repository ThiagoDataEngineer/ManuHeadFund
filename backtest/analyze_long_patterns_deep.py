#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
analyze_long_patterns_deep.py -- Análise PROFUNDA dos patterns LONG (TDD)

OBJETIVO: Investigar patterns LONG já validados e encontrar melhorias

PATTERNS A INVESTIGAR:
1. Tori Proximity (trendline bounce)
2. Vol Climax (optimized, rejection=0.5)
3. Combined (Tori + Vol Climax)

METODOLOGIA TDD:
1. Importar funções validadas (DRY principle)
2. Medir edge, win rate, frequency
3. Testar combinações
4. Encontrar configuração ÓTIMA
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))

from lib_data_fetcher import fetch_ohlcv
from lib_backtest_rsi_fixed import *
from lib_pattern_detection import detect_vol_climax, detect_tori_proximity
import pandas as pd
import numpy as np

print("✓ Imported from lib_pattern_detection (DRY principle)")
print("  - detect_vol_climax")
print("  - detect_tori_proximity")


def detect_tori_proximity_simple(highs, lows, closes, volumes,
                                 slope_min=5.0, slope_max=35.0,
                                 proximity_min=-3.0, proximity_max=5.0,
                                 rsi_max=40.0, vol_ratio_max=0.7,
                                 min_touches=3, lookback=20):
    """
    Wrapper for detect_tori_proximity from lib_pattern_detection
    Kept for backwards compatibility
    """
    return detect_tori_proximity(
        highs, lows, closes, volumes,
        slope_min, slope_max,
        proximity_min, proximity_max,
        rsi_max, vol_ratio_max,
        min_touches, lookback
    )


def scan_long_patterns_optimized(df, min_window=30):
    """
    Scan LONG patterns with optimized performance
    
    Patterns:
    1. Tori Proximity (trendline bounce)
    2. Vol Climax (rejection=0.5)
    3. Combined (Tori + Vol Climax)
    
    Returns:
        Dict with signals for each pattern
    """
    results = {
        'tori': [],
        'vol_climax': [],
        'combined': []
    }
    
    # Pre-compute arrays
    timestamps = df['timestamp'].values
    opens = df['open'].values
    highs = df['high'].values
    lows = df['low'].values
    closes = df['close'].values
    volumes = df['volume'].values
    
    # Pre-compute forward returns
    h20_prices = np.roll(closes, -20)
    h24_prices = np.roll(closes, -24)
    
    total = len(df)
    last_progress = 0
    
    for i in range(min_window, total):
        # Progress
        progress = int(i / total * 50)
        if progress > last_progress:
            pct = progress * 2
            print(f"  Progress: {pct}% - Tori: {len(results['tori'])}, VolClimax: {len(results['vol_climax'])}, Combined: {len(results['combined'])}", end='\r')
            last_progress = progress
        
        # 1. Tori Proximity
        tori_detected, proximity, slope, rsi, vol_dry = detect_tori_proximity_simple(
            highs[:i+1], lows[:i+1], closes[:i+1], volumes[:i+1]
        )
        
        # 2. Vol Climax (rejection=0.5)
        vc_detected, vol_ratio, rejection, vc_details = detect_vol_climax(
            highs[:i+1], lows[:i+1], closes[:i+1], volumes[:i+1],
            climax_mult=2.5,
            rejection_min=0.5
        )
        
        # Forward returns
        entry_price = closes[i]
        entry_date = timestamps[i]
        
        h20_return = 0
        h24_return = 0
        
        if i + 20 < total:
            h20_return = (h20_prices[i] - entry_price) / entry_price * 100  # LONG
        
        if i + 24 < total:
            h24_return = (h24_prices[i] - entry_price) / entry_price * 100  # LONG
        
        # Store Tori signals
        if tori_detected:
            results['tori'].append({
                'date': entry_date,
                'entry_price': float(entry_price),
                'proximity': float(proximity),
                'slope': float(slope),
                'rsi': float(rsi),
                'vol_dry': vol_dry,
                'h20_return': float(h20_return),
                'h24_return': float(h24_return),
                'hit_h20': h20_return > 0,
                'hit_h24': h24_return > 0,
            })
        
        # Store Vol Climax signals
        if vc_detected:
            results['vol_climax'].append({
                'date': entry_date,
                'entry_price': float(entry_price),
                'vol_ratio': float(vol_ratio),
                'rejection': float(rejection),
                'h20_return': float(h20_return),
                'h24_return': float(h24_return),
                'hit_h20': h20_return > 0,
                'hit_h24': h24_return > 0,
            })
        
        # Store Combined signals (Tori AND Vol Climax)
        if tori_detected and vc_detected:
            results['combined'].append({
                'date': entry_date,
                'entry_price': float(entry_price),
                'proximity': float(proximity),
                'slope': float(slope),
                'rsi': float(rsi),
                'vol_ratio': float(vol_ratio),
                'rejection': float(rejection),
                'h20_return': float(h20_return),
                'h24_return': float(h24_return),
                'hit_h20': h20_return > 0,
                'hit_h24': h24_return > 0,
            })
    
    print(f"\n  Completed: Tori={len(results['tori'])}, VolClimax={len(results['vol_climax'])}, Combined={len(results['combined'])}")
    
    return results


def main():
    """Main execution"""
    print("="*60)
    print("LONG PATTERNS DEEP ANALYSIS (TDD)")
    print("Investigating validated LONG patterns")
    print("="*60)
    
    symbol = "BTCUSDT"
    
    # Fetch FULL historical data
    print("\nFetching FULL historical data...")
    df = fetch_ohlcv(symbol, timeframe='1d', start_date='2011-01-01', end_date='2026-12-31')
    
    if df is None or len(df) < 100:
        print("ERROR: Failed to fetch data")
        return 1
    
    print(f"\nTotal data: {len(df)} candles")
    print(f"Date range: {df['timestamp'].min()} to {df['timestamp'].max()}")
    print(f"Years: {(df['timestamp'].max() - df['timestamp'].min()).days / 365.25:.1f}")
    
    # Scan patterns
    print(f"\n{'='*60}")
    print("SCANNING LONG PATTERNS")
    print(f"{'='*60}")
    
    results = scan_long_patterns_optimized(df)
    
    # Analyze results
    print(f"\n{'='*60}")
    print("RESULTS")
    print(f"{'='*60}")
    
    patterns = ['tori', 'vol_climax', 'combined']
    summary = {}
    
    for pattern in patterns:
        signals = results[pattern]
        
        if signals:
            df_pattern = pd.DataFrame(signals)
            
            edge = df_pattern['h20_return'].mean()
            win_rate = df_pattern['hit_h20'].mean() * 100
            
            summary[pattern] = {
                'signals': len(df_pattern),
                'edge': edge,
                'win_rate': win_rate
            }
            
            print(f"\n{pattern.upper()}:")
            print(f"  Signals: {len(df_pattern)}")
            print(f"  Edge (h20): {edge:+.2f}%")
            print(f"  Win rate: {win_rate:.1f}%")
        else:
            print(f"\n{pattern.upper()}: NO SIGNALS")
            summary[pattern] = {'signals': 0, 'edge': 0, 'win_rate': 0}
    
    # Find best pattern
    if any(s['signals'] > 0 for s in summary.values()):
        best = max(summary.items(), key=lambda x: x[1]['edge'] if x[1]['signals'] > 0 else -999)
        
        print(f"\n{'='*60}")
        print("BEST PATTERN")
        print(f"{'='*60}")
        
        print(f"\n{best[0].upper()}:")
        print(f"  Signals: {best[1]['signals']}")
        print(f"  Edge: {best[1]['edge']:+.2f}%")
        print(f"  Win rate: {best[1]['win_rate']:.1f}%")
    
    # Save results
    output_dir = Path(__file__).parent.parent / "journal"
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    # Convert to JSON-serializable format
    def make_serializable(obj):
        """Convert numpy/pandas types to JSON-serializable types"""
        if isinstance(obj, (np.integer, np.floating)):
            return float(obj)
        elif isinstance(obj, np.ndarray):
            return obj.tolist()
        elif isinstance(obj, (pd.Timestamp, np.datetime64)):
            return str(obj)
        elif isinstance(obj, (np.bool_, bool)):
            return bool(obj)
        elif isinstance(obj, dict):
            return {k: make_serializable(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [make_serializable(item) for item in obj]
        return obj
    
    results_serializable = make_serializable(results)
    
    results_json = {
        'timestamp': datetime.now().isoformat(),
        'period': f'{df["timestamp"].min()} to {df["timestamp"].max()}',
        'years': float((df['timestamp'].max() - df['timestamp'].min()).days / 365.25),
        'patterns': summary,
        'best_pattern': best[0] if any(s['signals'] > 0 for s in summary.values()) else None,
        'signals_data': results_serializable
    }
    
    save_results(results_json, output_dir / f"long_patterns_deep_analysis_{timestamp}.json")
    
    # Verdict
    print(f"\n{'='*60}")
    print("VERDICT")
    print(f"{'='*60}")
    
    if best[1]['edge'] > 3.0:
        print(f"\n✅ BEST PATTERN WORKS: {best[0].upper()} ({best[1]['edge']:+.2f}% edge)")
        print(f"   Recommendation: DEPLOY {best[0].upper()}")
    elif best[1]['edge'] > 0:
        print(f"\n⚠️  MARGINAL EDGE: {best[0].upper()} ({best[1]['edge']:+.2f}% edge)")
        print(f"   Recommendation: Deploy com cautela")
    else:
        print(f"\n❌ NO POSITIVE EDGE FOUND")
        print(f"   Recommendation: Continue investigation")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
