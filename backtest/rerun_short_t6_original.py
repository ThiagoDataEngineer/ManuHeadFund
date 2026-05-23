#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rerun_short_t6_original.py -- Re-rodar SHORT T6 original com RSI CORRIGIDO

OBJETIVO: Validar se edge +2.85pp é real ou artefato do RSI bug
PATTERN: SHORT buying climax (T6 original)
ORIGINAL: +2.85pp edge, n=505 signals em 14 anos (com RSI bugado)
EXPECTED: Edge pode mudar (RSI estava bugado)

Este script usa lib_backtest_rsi_fixed.py (RSI corrigido)
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))

from lib_backtest_rsi_fixed import *
from lib_data_fetcher import fetch_ohlcv

def main():
    """Main backtest execution"""
    print("="*60)
    print("SHORT T6 ORIGINAL RE-RUN")
    print("RSI FIXED 2026-05-23")
    print("="*60)
    
    symbol = "BTCUSDT"
    
    print(f"\nPattern: SHORT buying climax (T6 original)")
    print("Original: +2.85pp edge, n=505 signals em 14 anos (com RSI bugado)")
    print("Expected: Edge pode mudar\n")
    
    # Fetch FULL historical data (unified fetcher: CoinEx → Binance → Bitstamp)
    print("Fetching FULL historical data (unified fetcher, 2011-2026)...")
    df = fetch_ohlcv(symbol, timeframe='1d', 
                     start_date='2011-01-01', end_date='2026-12-31')
    
    if df is None or len(df) < 100:
        print(f"ERROR: Failed to fetch data")
        return 1
    
    print(f"Data points: {len(df)}")
    print(f"Date range: {df['timestamp'].min()} to {df['timestamp'].max()}")
    print(f"Price range: ${df['close'].min():.0f} to ${df['close'].max():.0f}")
    print(f"Years: {(df['timestamp'].max() - df['timestamp'].min()).days / 365.25:.1f}")
    
    # Run baseline (T6 original thresholds)
    print(f"\n{'='*60}")
    print("BASELINE (T6 original thresholds)")
    print(f"{'='*60}")
    print("Thresholds: climax_mult=2.5, rsi_min=70")
    
    baseline_signals = []
    for i in range(30, len(df)):
        highs = df['high'].values[:i+1]
        lows = df['low'].values[:i+1]
        closes = df['close'].values[:i+1]
        volumes = df['volume'].values[:i+1]
        
        detected, vol_ratio, rejection, rsi_val = detect_short_signal(
            highs, lows, closes, volumes,
            climax_mult=2.5,
            rsi_min=70
        )
        
        if detected:
            entry_price = closes[-1]
            entry_date = df.iloc[i]['timestamp']
            
            # Forward returns
            fwd_returns = compute_forward_returns_short(df, i, horizons=[20, 24])
            
            baseline_signals.append({
                'date': entry_date,
                'entry_price': entry_price,
                'vol_ratio': vol_ratio,
                'rsi': rsi_val,
                'climax_mult': 2.5,
                'rsi_min': 70,
                **fwd_returns
            })
    
    baseline_df = pd.DataFrame(baseline_signals) if baseline_signals else None
    print_summary(baseline_df, "BASELINE (T6 original)")
    
    # Run adaptive (regime-specific thresholds)
    print(f"\n{'='*60}")
    print("ADAPTIVE (regime-specific thresholds)")
    print(f"{'='*60}")
    
    adaptive_signals = []
    for i in range(30, len(df)):
        highs = df['high'].values[:i+1]
        lows = df['low'].values[:i+1]
        closes = df['close'].values[:i+1]
        volumes = df['volume'].values[:i+1]
        
        # Detect regime
        regime = detect_regime_simple(closes)
        thresholds = REGIME_THRESHOLDS_SHORT.get(regime, BASELINE_THRESHOLDS_SHORT)
        
        detected, vol_ratio, rejection, rsi_val = detect_short_signal(
            highs, lows, closes, volumes,
            climax_mult=thresholds["climax_mult"],
            rsi_min=thresholds["rsi_min"]
        )
        
        if detected:
            entry_price = closes[-1]
            entry_date = df.iloc[i]['timestamp']
            
            # Forward returns
            fwd_returns = compute_forward_returns_short(df, i, horizons=[20, 24])
            
            adaptive_signals.append({
                'date': entry_date,
                'regime': regime,
                'entry_price': entry_price,
                'vol_ratio': vol_ratio,
                'rsi': rsi_val,
                'climax_mult': thresholds["climax_mult"],
                'rsi_min': thresholds["rsi_min"],
                **fwd_returns
            })
    
    adaptive_df = pd.DataFrame(adaptive_signals) if adaptive_signals else None
    print_summary(adaptive_df, "ADAPTIVE")
    
    # Compare
    if baseline_df is not None and adaptive_df is not None:
        print(f"\n{'='*60}")
        print("COMPARISON")
        print(f"{'='*60}")
        
        baseline_edge = baseline_df['h20_return'].mean()
        adaptive_edge = adaptive_df['h20_return'].mean()
        improvement = adaptive_edge - baseline_edge
        
        print(f"\nEdge (h20 avg return):")
        print(f"  Baseline (T6): {baseline_edge:.2f}%")
        print(f"  Adaptive: {adaptive_edge:.2f}%")
        print(f"  Improvement: {improvement:+.2f}%")
        
        print(f"\nSample size:")
        print(f"  Baseline: {len(baseline_df)} signals")
        print(f"  Adaptive: {len(adaptive_df)} signals")
        print(f"  Original T6: 505 signals (reference)")
        
        print(f"\nWin rate (h20):")
        print(f"  Baseline: {baseline_df['hit_h20'].mean()*100:.1f}%")
        print(f"  Adaptive: {adaptive_df['hit_h20'].mean()*100:.1f}%")
        
        # Analyze by market phase
        if 'regime' in adaptive_df.columns:
            print(f"\n{'='*60}")
            print("BY REGIME (Adaptive)")
            print(f"{'='*60}")
            for regime in sorted(adaptive_df['regime'].unique()):
                regime_df = adaptive_df[adaptive_df['regime'] == regime]
                edge = regime_df['h20_return'].mean()
                win_rate = regime_df['hit_h20'].mean() * 100
                print(f"\n{regime} (n={len(regime_df)}):")
                print(f"  Edge: {edge:+.2f}%")
                print(f"  Win rate: {win_rate:.1f}%")
        
        # Save results
        output_dir = Path(__file__).parent.parent / "journal"
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        results = {
            'timestamp': datetime.now().isoformat(),
            'period': f'{df["timestamp"].min()} to {df["timestamp"].max()}',
            'years': float((df['timestamp'].max() - df['timestamp'].min()).days / 365.25),
            'rsi_status': 'FIXED 2026-05-23',
            'original_t6': {
                'edge': 2.85,
                'signals': 505,
                'note': 'Original T6 result (com RSI bugado)'
            },
            'baseline_rerun': {
                'signals': len(baseline_df),
                'edge_h20': float(baseline_edge),
                'win_rate_h20': float(baseline_df['hit_h20'].mean()),
                'signals_data': baseline_df.to_dict('records')
            },
            'adaptive': {
                'signals': len(adaptive_df),
                'edge_h20': float(adaptive_edge),
                'win_rate_h20': float(adaptive_df['hit_h20'].mean()),
                'signals_data': adaptive_df.to_dict('records')
            },
            'comparison': {
                'edge_delta_vs_original': float(baseline_edge - 2.85),
                'edge_delta_adaptive': float(improvement),
                'signals_delta_vs_original': len(baseline_df) - 505
            }
        }
        
        save_results(results, output_dir / f"short_t6_rerun_{timestamp}.json")
        
        # Verdict
        print(f"\n{'='*60}")
        print("VERDICT")
        print(f"{'='*60}")
        
        print(f"\nOriginal T6 (RSI bugado): +2.85% edge, n=505")
        print(f"Baseline re-run (RSI corrigido): {baseline_edge:+.2f}% edge, n={len(baseline_df)}")
        print(f"Delta: {baseline_edge - 2.85:+.2f}%")
        
        if abs(baseline_edge - 2.85) < 0.5:
            print(f"\n✅ ORIGINAL RESULT CONFIRMED: Edge is similar (~{baseline_edge:.2f}%)")
            print(f"   RSI bug did NOT significantly affect T6 results")
            print(f"   Recommendation: Original T6 findings are VALID")
        elif baseline_edge > 2.85:
            print(f"\n✅ EDGE IMPROVED: New edge {baseline_edge:+.2f}% > original +2.85%")
            print(f"   RSI fix IMPROVED results")
            print(f"   Recommendation: Deploy SHORT with confidence")
        elif baseline_edge > 0:
            print(f"\n⚠️  EDGE DECREASED: New edge {baseline_edge:+.2f}% < original +2.85%")
            print(f"   Original result was partially artifact of RSI bug")
            print(f"   Recommendation: Deploy with caution, monitor closely")
        else:
            print(f"\n❌ EDGE NEGATIVE: New edge {baseline_edge:+.2f}%")
            print(f"   Original +2.85% was artifact of RSI bug")
            print(f"   Recommendation: DO NOT deploy SHORT")
        
        if improvement > 1.0:
            print(f"\n✅ ADAPTIVE THRESHOLDS WORK: Improvement {improvement:+.2f}%")
            print(f"   Recommendation: Use regime-specific thresholds")
        
    return 0


if __name__ == "__main__":
    sys.exit(main())
