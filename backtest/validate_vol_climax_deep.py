#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
validate_vol_climax_deep.py -- Análise PROFUNDA vol climax (TDD)

OBJETIVO: Avaliar profundamente vol climax e evoluir o pattern

METODOLOGIA TDD:
1. Testar vol climax PURO (sem RSI)
2. Testar com diferentes thresholds (climax_mult)
3. Testar com regime gate
4. Testar com rejection threshold
5. Encontrar configuração ÓTIMA

HIPÓTESE:
- Vol climax original (+20.7pp) era artifact do RSI bug
- Mas vol climax PURO pode ter edge
- Precisamos encontrar thresholds ótimos
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))

from lib_data_fetcher import fetch_ohlcv
from lib_backtest_rsi_fixed import *
import pandas as pd
import numpy as np


def detect_vol_climax_configurable(highs, lows, closes, volumes,
                                   climax_mult=2.5,
                                   rejection_min=0.3,
                                   lookback=20):
    """
    Detect volume climax (LONG) with configurable thresholds
    
    Returns:
        (detected, vol_ratio, rejection, details)
    """
    if len(closes) < lookback + 1:
        return False, 0, 0, {}
    
    # 1. Volume spike
    recent_vols = volumes[-lookback-1:-1]
    avg_vol = np.mean(recent_vols)
    current_vol = volumes[-1]
    vol_ratio = current_vol / avg_vol if avg_vol > 0 else 0
    
    vol_spike = vol_ratio >= climax_mult
    
    # 2. New low (selling climax)
    recent_lows = lows[-lookback-1:-1]
    min_low = np.min(recent_lows)
    current_low = lows[-1]
    
    new_low = current_low <= min_low
    
    # 3. Close rejection (wick inferior)
    candle_range = highs[-1] - lows[-1]
    if candle_range > 0:
        rejection = (closes[-1] - lows[-1]) / candle_range
    else:
        rejection = 0
    
    close_rejection = rejection >= rejection_min
    
    detected = vol_spike and new_low and close_rejection
    
    details = {
        'vol_spike': vol_spike,
        'vol_ratio': vol_ratio,
        'new_low': new_low,
        'close_rejection': close_rejection,
        'rejection': rejection
    }
    
    return detected, vol_ratio, rejection, details


def scan_vol_climax_optimized(df, climax_mult=2.5, rejection_min=0.3, 
                              regime_filter=None, min_window=30):
    """
    Scan vol climax with optimized performance
    
    Args:
        df: DataFrame with OHLCV
        climax_mult: Volume multiplier threshold
        rejection_min: Minimum rejection ratio
        regime_filter: List of regimes to filter (e.g., ['BEAR_STRONG', 'BEAR_WEAK'])
        min_window: Minimum candles before scanning
    
    Returns:
        List of signals
    """
    signals = []
    
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
            print(f"  Progress: {pct}% - Signals: {len(signals)}", end='\r')
            last_progress = progress
        
        # Detect regime (if filter enabled)
        if regime_filter:
            regime = detect_regime_simple(closes[:i+1])
            if regime not in regime_filter:
                continue
        
        # Detect vol climax
        detected, vol_ratio, rejection, details = detect_vol_climax_configurable(
            highs[:i+1], lows[:i+1], closes[:i+1], volumes[:i+1],
            climax_mult=climax_mult,
            rejection_min=rejection_min
        )
        
        if not detected:
            continue
        
        # Signal detected!
        entry_price = closes[i]
        entry_date = timestamps[i]
        
        # Forward returns
        h20_return = 0
        h24_return = 0
        
        if i + 20 < total:
            h20_return = (h20_prices[i] - entry_price) / entry_price * 100  # LONG
        
        if i + 24 < total:
            h24_return = (h24_prices[i] - entry_price) / entry_price * 100  # LONG
        
        signals.append({
            'date': entry_date,
            'entry_price': float(entry_price),
            'vol_ratio': float(vol_ratio),
            'rejection': float(rejection),
            'climax_mult': climax_mult,
            'rejection_min': rejection_min,
            'h20_return': float(h20_return),
            'h24_return': float(h24_return),
            'hit_h20': h20_return > 0,
            'hit_h24': h24_return > 0,
        })
    
    print(f"\n  Completed: {len(signals)} signals detected")
    
    return signals


def main():
    """Main execution"""
    print("="*60)
    print("VOL CLIMAX DEEP VALIDATION (TDD)")
    print("Análise profunda + evolução do pattern")
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
    
    # ========================================================================
    # EXPERIMENT 1: Baseline (original thresholds, no filters)
    # ========================================================================
    print(f"\n{'='*60}")
    print("EXPERIMENT 1: BASELINE (climax_mult=2.5, rejection=0.3)")
    print(f"{'='*60}")
    
    signals_baseline = scan_vol_climax_optimized(df, climax_mult=2.5, rejection_min=0.3)
    df_baseline = pd.DataFrame(signals_baseline) if signals_baseline else None
    
    if df_baseline is not None and len(df_baseline) > 0:
        print(f"\nSignals: {len(df_baseline)}")
        print(f"Edge (h20): {df_baseline['h20_return'].mean():.2f}%")
        print(f"Win rate (h20): {df_baseline['hit_h20'].mean()*100:.1f}%")
    else:
        print("\nNO SIGNALS")
    
    # ========================================================================
    # EXPERIMENT 2: Relaxed thresholds (climax_mult=2.0)
    # ========================================================================
    print(f"\n{'='*60}")
    print("EXPERIMENT 2: RELAXED (climax_mult=2.0, rejection=0.3)")
    print(f"{'='*60}")
    
    signals_relaxed = scan_vol_climax_optimized(df, climax_mult=2.0, rejection_min=0.3)
    df_relaxed = pd.DataFrame(signals_relaxed) if signals_relaxed else None
    
    if df_relaxed is not None and len(df_relaxed) > 0:
        print(f"\nSignals: {len(df_relaxed)}")
        print(f"Edge (h20): {df_relaxed['h20_return'].mean():.2f}%")
        print(f"Win rate (h20): {df_relaxed['hit_h20'].mean()*100:.1f}%")
    else:
        print("\nNO SIGNALS")
    
    # ========================================================================
    # EXPERIMENT 3: Strict thresholds (climax_mult=3.0)
    # ========================================================================
    print(f"\n{'='*60}")
    print("EXPERIMENT 3: STRICT (climax_mult=3.0, rejection=0.3)")
    print(f"{'='*60}")
    
    signals_strict = scan_vol_climax_optimized(df, climax_mult=3.0, rejection_min=0.3)
    df_strict = pd.DataFrame(signals_strict) if signals_strict else None
    
    if df_strict is not None and len(df_strict) > 0:
        print(f"\nSignals: {len(df_strict)}")
        print(f"Edge (h20): {df_strict['h20_return'].mean():.2f}%")
        print(f"Win rate (h20): {df_strict['hit_h20'].mean()*100:.1f}%")
    else:
        print("\nNO SIGNALS")
    
    # ========================================================================
    # EXPERIMENT 4: Higher rejection (climax_mult=2.5, rejection=0.5)
    # ========================================================================
    print(f"\n{'='*60}")
    print("EXPERIMENT 4: HIGH REJECTION (climax_mult=2.5, rejection=0.5)")
    print(f"{'='*60}")
    
    signals_high_rej = scan_vol_climax_optimized(df, climax_mult=2.5, rejection_min=0.5)
    df_high_rej = pd.DataFrame(signals_high_rej) if signals_high_rej else None
    
    if df_high_rej is not None and len(df_high_rej) > 0:
        print(f"\nSignals: {len(df_high_rej)}")
        print(f"Edge (h20): {df_high_rej['h20_return'].mean():.2f}%")
        print(f"Win rate (h20): {df_high_rej['hit_h20'].mean()*100:.1f}%")
    else:
        print("\nNO SIGNALS")
    
    # ========================================================================
    # EXPERIMENT 5: Regime gate (BEAR only)
    # ========================================================================
    print(f"\n{'='*60}")
    print("EXPERIMENT 5: REGIME GATE (BEAR_STRONG + BEAR_WEAK only)")
    print(f"{'='*60}")
    
    signals_regime = scan_vol_climax_optimized(
        df, climax_mult=2.5, rejection_min=0.3,
        regime_filter=['BEAR_STRONG', 'BEAR_WEAK']
    )
    df_regime = pd.DataFrame(signals_regime) if signals_regime else None
    
    if df_regime is not None and len(df_regime) > 0:
        print(f"\nSignals: {len(df_regime)}")
        print(f"Edge (h20): {df_regime['h20_return'].mean():.2f}%")
        print(f"Win rate (h20): {df_regime['hit_h20'].mean()*100:.1f}%")
    else:
        print("\nNO SIGNALS")
    
    # ========================================================================
    # COMPARISON
    # ========================================================================
    print(f"\n{'='*60}")
    print("COMPARISON")
    print(f"{'='*60}")
    
    experiments = [
        ('Baseline (2.5x, 0.3)', df_baseline),
        ('Relaxed (2.0x, 0.3)', df_relaxed),
        ('Strict (3.0x, 0.3)', df_strict),
        ('High Rejection (2.5x, 0.5)', df_high_rej),
        ('Regime Gate (BEAR only)', df_regime),
    ]
    
    results_summary = []
    
    for name, df_exp in experiments:
        if df_exp is not None and len(df_exp) > 0:
            edge = df_exp['h20_return'].mean()
            win_rate = df_exp['hit_h20'].mean() * 100
            signals = len(df_exp)
            
            results_summary.append({
                'name': name,
                'signals': signals,
                'edge': edge,
                'win_rate': win_rate
            })
            
            print(f"\n{name}:")
            print(f"  Signals: {signals}")
            print(f"  Edge: {edge:+.2f}%")
            print(f"  Win rate: {win_rate:.1f}%")
    
    # Find best configuration
    if results_summary:
        best = max(results_summary, key=lambda x: x['edge'])
        
        print(f"\n{'='*60}")
        print("BEST CONFIGURATION")
        print(f"{'='*60}")
        
        print(f"\n{best['name']}:")
        print(f"  Signals: {best['signals']}")
        print(f"  Edge: {best['edge']:+.2f}%")
        print(f"  Win rate: {best['win_rate']:.1f}%")
    
    # Save results
    output_dir = Path(__file__).parent.parent / "journal"
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    results = {
        'timestamp': datetime.now().isoformat(),
        'period': f'{df["timestamp"].min()} to {df["timestamp"].max()}',
        'years': float((df['timestamp'].max() - df['timestamp'].min()).days / 365.25),
        'experiments': results_summary,
        'best_config': best if results_summary else None,
        'original_result': {
            'edge': 20.7,
            'note': 'Original +20.7pp era artifact do RSI bug'
        }
    }
    
    save_results(results, output_dir / f"vol_climax_deep_validation_{timestamp}.json")
    
    # Verdict
    print(f"\n{'='*60}")
    print("VERDICT")
    print(f"{'='*60}")
    
    if results_summary:
        best_edge = best['edge']
        
        if best_edge > 2.0:
            print(f"\n✅ VOL CLIMAX WORKS: Best edge {best_edge:+.2f}%")
            print(f"   Configuration: {best['name']}")
            print(f"   Recommendation: DEPLOY with best config")
        elif best_edge > 0:
            print(f"\n⚠️  VOL CLIMAX MARGINAL: Best edge {best_edge:+.2f}%")
            print(f"   Configuration: {best['name']}")
            print(f"   Recommendation: Deploy com cautela")
        else:
            print(f"\n❌ VOL CLIMAX DOESN'T WORK: Best edge {best_edge:+.2f}%")
            print(f"   Original +20.7pp era 100% artifact do RSI bug")
            print(f"   Recommendation: REMOVE vol climax pattern")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
