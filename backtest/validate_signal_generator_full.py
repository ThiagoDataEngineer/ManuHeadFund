#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
validate_signal_generator_full.py -- Validar signal_generator em período COMPLETO

OBJETIVO: Confirmar se edge +1.23% se mantém em 14.8 anos (2011-2026)

METODOLOGIA TDD:
1. Usar signal_generator.generate_signal() (multi-indicator scoring)
2. Testar em PERÍODO COMPLETO (2011-2026, 3973 candles)
3. Analisar por regime (BULL/BEAR/SIDEWAYS)
4. Comparar com T6 replication (2018+2022 only)

HIPÓTESE:
- Se edge > +1.0%: Deploy SHORT com signal_generator
- Se edge 0-1%: Deploy com cautela
- Se edge < 0%: Abandon SHORT
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))

from lib_data_fetcher import fetch_ohlcv
from lib_backtest_rsi_fixed import *
import pandas as pd
import numpy as np

# Import signal_generator
try:
    from signal_generator import generate_signal
    SIGNAL_GENERATOR_AVAILABLE = True
except ImportError:
    print("ERROR: signal_generator.py not found")
    SIGNAL_GENERATOR_AVAILABLE = False
    sys.exit(1)


def detect_regime_simple(closes, lookback=200):
    """
    Detect market regime (simplified)
    
    Returns:
        'BULL_STRONG', 'BULL_WEAK', 'BEAR_STRONG', 'BEAR_WEAK', 'SIDEWAYS'
    """
    if len(closes) < lookback:
        return 'SIDEWAYS'
    
    sma200 = np.mean(closes[-lookback:])
    price = closes[-1]
    
    # Distance from SMA200
    dist_pct = (price - sma200) / sma200 * 100
    
    # Trend strength (20-day slope)
    if len(closes) >= 20:
        slope = (closes[-1] - closes[-20]) / closes[-20] * 100
    else:
        slope = 0
    
    # Classification
    if dist_pct > 10 and slope > 5:
        return 'BULL_STRONG'
    elif dist_pct > 0 and slope > 0:
        return 'BULL_WEAK'
    elif dist_pct < -10 and slope < -5:
        return 'BEAR_STRONG'
    elif dist_pct < 0 and slope < 0:
        return 'BEAR_WEAK'
    else:
        return 'SIDEWAYS'


def scan_with_signal_generator_full(df, min_window=60):
    """
    Scan FULL period usando signal_generator.generate_signal()
    OPTIMIZED: Pre-compute arrays, vectorized operations, efficient progress
    
    Returns:
        List of signals with forward returns and regime
    """
    print(f"\nScanning FULL period: {df['timestamp'].min()} to {df['timestamp'].max()}")
    print(f"Data points: {len(df)}")
    
    signals = []
    
    # Pre-compute arrays (avoid repeated .values calls)
    timestamps = df['timestamp'].values
    opens = df['open'].values
    highs = df['high'].values
    lows = df['low'].values
    closes = df['close'].values
    volumes = df['volume'].values
    
    # Pre-compute forward returns (vectorized)
    h20_prices = np.roll(closes, -20)
    h24_prices = np.roll(closes, -24)
    
    # Pre-compute volume moving average (for early exit optimization)
    vol_ma = np.convolve(volumes, np.ones(20)/20, mode='same')
    
    total = len(df)
    last_progress = 0
    skipped_low_vol = 0
    
    for i in range(min_window, total):
        # Progress (only every 2%)
        progress = int(i / total * 50)  # 50 steps = 2% each
        if progress > last_progress:
            pct = progress * 2
            print(f"  Progress: {pct}% ({i}/{total}) - Signals: {len(signals)} - Skipped: {skipped_low_vol}", end='\r')
            last_progress = progress
        
        # Early exit: Skip if volume too low (optimization)
        if i >= 20 and volumes[i] < vol_ma[i] * 0.5:
            skipped_low_vol += 1
            continue
        
        # Prepare candles window (optimized: direct array access)
        start_idx = max(0, i - 200)
        window = [
            {
                'timestamp': timestamps[j].timestamp() if hasattr(timestamps[j], 'timestamp') else timestamps[j],
                'open': float(opens[j]),
                'high': float(highs[j]),
                'low': float(lows[j]),
                'close': float(closes[j]),
                'volume': float(volumes[j]),
            }
            for j in range(start_idx, i + 1)
        ]
        
        # Detect regime (optimized: slice once)
        regime = detect_regime_simple(closes[:i+1])
        
        # Generate signal
        try:
            sig = generate_signal(window)
        except Exception:
            continue
        
        # Check if SHORT signal
        if sig.signal != "VENDA":
            continue
        
        # Signal detected!
        entry_price = closes[i]
        entry_date = timestamps[i]
        
        # Forward returns (pre-computed, just access)
        h20_return = 0
        h24_return = 0
        
        if i + 20 < total:
            h20_return = (entry_price - h20_prices[i]) / entry_price * 100  # SHORT
        
        if i + 24 < total:
            h24_return = (entry_price - h24_prices[i]) / entry_price * 100  # SHORT
        
        signals.append({
            'date': entry_date,
            'regime': regime,
            'entry_price': float(entry_price),
            'score': sig.score,
            'indicators': sig.indicators,
            'h20_return': float(h20_return),
            'h24_return': float(h24_return),
            'hit_h20': h20_return > 0,
            'hit_h24': h24_return > 0,
        })
    
    print(f"\n  Completed: {total} candles scanned, {len(signals)} signals detected")
    print(f"  Optimization: Skipped {skipped_low_vol} low-volume candles ({skipped_low_vol/total*100:.1f}%)")
    
    return signals


def main():
    """Main execution"""
    print("="*60)
    print("SIGNAL_GENERATOR FULL PERIOD VALIDATION")
    print("Using signal_generator.generate_signal()")
    print("="*60)
    
    symbol = "BTCUSDT"
    
    # Fetch FULL historical data (unified fetcher)
    print("\nFetching FULL historical data...")
    df = fetch_ohlcv(symbol, timeframe='1d', start_date='2011-01-01', end_date='2026-12-31')
    
    if df is None or len(df) < 100:
        print("ERROR: Failed to fetch data")
        return 1
    
    print(f"\nTotal data: {len(df)} candles")
    print(f"Date range: {df['timestamp'].min()} to {df['timestamp'].max()}")
    print(f"Years: {(df['timestamp'].max() - df['timestamp'].min()).days / 365.25:.1f}")
    
    # Scan FULL period
    print(f"\n{'='*60}")
    print("SCANNING FULL PERIOD (2011-2026)")
    print(f"{'='*60}")
    
    signals = scan_with_signal_generator_full(df)
    
    if not signals:
        print("\n❌ NO SIGNALS DETECTED")
        return 1
    
    df_signals = pd.DataFrame(signals)
    
    # Overall results
    print(f"\n{'='*60}")
    print("OVERALL RESULTS")
    print(f"{'='*60}")
    
    print(f"\nTotal signals: {len(df_signals)}")
    print(f"Date range: {df_signals['date'].min()} to {df_signals['date'].max()}")
    print(f"Edge (h20): {df_signals['h20_return'].mean():.2f}%")
    print(f"Win rate (h20): {df_signals['hit_h20'].mean()*100:.1f}%")
    print(f"Edge (h24): {df_signals['h24_return'].mean():.2f}%")
    print(f"Win rate (h24): {df_signals['hit_h24'].mean()*100:.1f}%")
    
    # By regime
    print(f"\n{'='*60}")
    print("BY REGIME")
    print(f"{'='*60}")
    
    for regime in sorted(df_signals['regime'].unique()):
        regime_df = df_signals[df_signals['regime'] == regime]
        edge = regime_df['h20_return'].mean()
        win_rate = regime_df['hit_h20'].mean() * 100
        print(f"\n{regime} (n={len(regime_df)}):")
        print(f"  Edge (h20): {edge:+.2f}%")
        print(f"  Win rate: {win_rate:.1f}%")
        print(f"  Date range: {regime_df['date'].min()} to {regime_df['date'].max()}")
    
    # By year
    print(f"\n{'='*60}")
    print("BY YEAR")
    print(f"{'='*60}")
    
    df_signals['year'] = pd.to_datetime(df_signals['date']).dt.year
    
    for year in sorted(df_signals['year'].unique()):
        year_df = df_signals[df_signals['year'] == year]
        edge = year_df['h20_return'].mean()
        win_rate = year_df['hit_h20'].mean() * 100
        print(f"\n{year} (n={len(year_df)}):")
        print(f"  Edge (h20): {edge:+.2f}%")
        print(f"  Win rate: {win_rate:.1f}%")
    
    # Compare with T6 replication (2018+2022)
    print(f"\n{'='*60}")
    print("COMPARISON WITH T6 REPLICATION")
    print(f"{'='*60}")
    
    # Filter 2018+2022
    df_2018_2022 = df_signals[
        ((df_signals['year'] == 2018) | (df_signals['year'] == 2022))
    ]
    
    print(f"\nT6 Replication (2018+2022 only):")
    print(f"  Signals: 321 (reference)")
    print(f"  Edge: +1.23%")
    print(f"  Win rate: 44.2%")
    
    print(f"\nFull Period (2011-2026):")
    print(f"  Signals: {len(df_signals)}")
    print(f"  Edge: {df_signals['h20_return'].mean():+.2f}%")
    print(f"  Win rate: {df_signals['hit_h20'].mean()*100:.1f}%")
    
    print(f"\nThis Script 2018+2022 subset:")
    print(f"  Signals: {len(df_2018_2022)}")
    print(f"  Edge: {df_2018_2022['h20_return'].mean():+.2f}%")
    print(f"  Win rate: {df_2018_2022['hit_h20'].mean()*100:.1f}%")
    
    # Save results
    output_dir = Path(__file__).parent.parent / "journal"
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    results = {
        'timestamp': datetime.now().isoformat(),
        'method': 'signal_generator.generate_signal()',
        'period': f'{df["timestamp"].min()} to {df["timestamp"].max()}',
        'years': float((df['timestamp'].max() - df['timestamp'].min()).days / 365.25),
        'total_signals': len(df_signals),
        'edge_h20': float(df_signals['h20_return'].mean()),
        'win_rate_h20': float(df_signals['hit_h20'].mean()),
        'edge_h24': float(df_signals['h24_return'].mean()),
        'win_rate_h24': float(df_signals['hit_h24'].mean()),
        'by_regime': {},
        'by_year': {},
        't6_replication_comparison': {
            't6_2018_2022': {
                'signals': 321,
                'edge': 1.23,
                'win_rate': 44.2
            },
            'full_period': {
                'signals': len(df_signals),
                'edge': float(df_signals['h20_return'].mean()),
                'win_rate': float(df_signals['hit_h20'].mean() * 100)
            },
            'this_script_2018_2022': {
                'signals': len(df_2018_2022),
                'edge': float(df_2018_2022['h20_return'].mean()),
                'win_rate': float(df_2018_2022['hit_h20'].mean() * 100)
            }
        },
        'signals_data': df_signals.to_dict('records')
    }
    
    # By regime
    for regime in sorted(df_signals['regime'].unique()):
        regime_df = df_signals[df_signals['regime'] == regime]
        results['by_regime'][regime] = {
            'signals': len(regime_df),
            'edge_h20': float(regime_df['h20_return'].mean()),
            'win_rate_h20': float(regime_df['hit_h20'].mean() * 100)
        }
    
    # By year
    for year in sorted(df_signals['year'].unique()):
        year_df = df_signals[df_signals['year'] == year]
        results['by_year'][int(year)] = {
            'signals': len(year_df),
            'edge_h20': float(year_df['h20_return'].mean()),
            'win_rate_h20': float(year_df['hit_h20'].mean() * 100)
        }
    
    save_results(results, output_dir / f"signal_generator_full_validation_{timestamp}.json")
    
    # Verdict
    print(f"\n{'='*60}")
    print("VERDICT")
    print(f"{'='*60}")
    
    edge = df_signals['h20_return'].mean()
    win_rate = df_signals['hit_h20'].mean() * 100
    
    if edge > 1.0 and win_rate > 40:
        print(f"\n✅ EDGE CONFIRMED: {edge:+.2f}% edge, {win_rate:.1f}% win rate")
        print(f"   signal_generator tem edge REAL e ROBUSTO")
        print(f"   Recommendation: DEPLOY SHORT com signal_generator")
        print(f"\n   Suggested regime gate:")
        
        # Find best regimes
        regime_edges = []
        for regime in df_signals['regime'].unique():
            regime_df = df_signals[df_signals['regime'] == regime]
            if len(regime_df) >= 10:  # Min sample size
                regime_edge = regime_df['h20_return'].mean()
                regime_edges.append((regime, regime_edge, len(regime_df)))
        
        regime_edges.sort(key=lambda x: x[1], reverse=True)
        
        print(f"   Best regimes (edge > 0):")
        for regime, regime_edge, count in regime_edges:
            if regime_edge > 0:
                print(f"     - {regime}: {regime_edge:+.2f}% (n={count})")
    
    elif edge > 0 and win_rate > 35:
        print(f"\n⚠️  EDGE MARGINAL: {edge:+.2f}% edge, {win_rate:.1f}% win rate")
        print(f"   signal_generator tem edge mas FRACO")
        print(f"   Recommendation: Deploy com CAUTELA, monitor closely")
    
    else:
        print(f"\n❌ EDGE INSUFFICIENT: {edge:+.2f}% edge, {win_rate:.1f}% win rate")
        print(f"   signal_generator NÃO tem edge suficiente")
        print(f"   Recommendation: DO NOT deploy SHORT")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
