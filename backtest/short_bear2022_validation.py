#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
short_bear2022_validation.py -- Validar SHORT em bear market 2022

OBJETIVO: Provar que SHORT patterns têm edge POSITIVO em bear markets
PERÍODO: Nov 2021 - Dec 2022 (BTC $69K → $15K)
EXPECTED: Edge +5-10%, win rate 55-60%

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
    print("SHORT BEAR MARKET 2022 VALIDATION")
    print("RSI FIXED 2026-05-23")
    print("="*60)
    
    symbol = "BTCUSDT"
    start_date = "2021-11-01"
    end_date = "2022-12-31"
    
    print(f"\nPeriod: {start_date} to {end_date}")
    print("Expected: BTC $69K → $15K (bear market)")
    print("Hypothesis: SHORT patterns have POSITIVE edge in bear\n")
    
    # Fetch data (unified fetcher: CoinEx → Binance → Bitstamp)
    print("Fetching data (unified fetcher)...")
    df = fetch_ohlcv(symbol, timeframe='1d', 
                     start_date=start_date, end_date=end_date)
    
    if df is None or len(df) < 100:
        print(f"ERROR: Failed to fetch data")
        return 1
    
    print(f"Data points: {len(df)}")
    print(f"Date range: {df['timestamp'].min()} to {df['timestamp'].max()}")
    print(f"Price range: ${df['close'].min():.0f} to ${df['close'].max():.0f}")
    
    # Run baseline (fixed thresholds - RELAXED for bear market)
    print(f"\n{'='*60}")
    print("BASELINE (fixed thresholds - RELAXED)")
    print(f"{'='*60}")
    print("Note: Using relaxed thresholds (climax_mult=2.0, rsi_min=60)")
    print("      to detect bear market rallies (SHORT opportunities)")
    
    baseline_signals = []
    debug_stats = {'vol_spike': 0, 'new_high': 0, 'rejection': 0, 'rsi_ok': 0, 'detected': 0}
    
    for i in range(30, len(df)):
        highs = df['high'].values[:i+1]
        lows = df['low'].values[:i+1]
        closes = df['close'].values[:i+1]
        volumes = df['volume'].values[:i+1]
        
        # Debug: check each filter
        lookback = 20
        vol_avg = np.mean(volumes[-lookback-1:-1])
        vol_ratio = volumes[-1] / vol_avg if vol_avg > 0 else 0
        if vol_ratio >= 2.0:
            debug_stats['vol_spike'] += 1
            
            prior_highs = highs[-lookback-1:-1]
            max_prior = np.max(prior_highs)
            if highs[-1] > max_prior:
                debug_stats['new_high'] += 1
                
                rng = highs[-1] - lows[-1]
                if rng > 0:
                    rejection = (highs[-1] - closes[-1]) / rng
                    if rejection >= 0.3:
                        debug_stats['rejection'] += 1
                        
                        rsi_array = calculate_rsi(closes, period=14)
                        rsi_val = rsi_array[-1]
                        if rsi_val > 60:
                            debug_stats['rsi_ok'] += 1
        
        detected, vol_ratio, rejection, rsi_val = detect_short_signal(
            highs, lows, closes, volumes,
            climax_mult=2.0,  # More permissive for bear rallies
            rsi_min=60  # Lower RSI threshold (bear rallies don't reach 70+)
        )
        
        if detected:
            debug_stats['detected'] += 1
        
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
                'climax_mult': 2.0,
                'rsi_min': 60,
                **fwd_returns
            })
    
    baseline_df = pd.DataFrame(baseline_signals) if baseline_signals else None
    
    print(f"\nDEBUG - Filter funnel:")
    print(f"  Vol spike (>2.0x): {debug_stats['vol_spike']}")
    print(f"  + New high: {debug_stats['new_high']}")
    print(f"  + Rejection (>30%): {debug_stats['rejection']}")
    print(f"  + RSI > 60: {debug_stats['rsi_ok']}")
    print(f"  = Detected: {debug_stats['detected']}")
    
    print_summary(baseline_df, "BASELINE")
    
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
        print(f"  Baseline: {baseline_edge:.2f}%")
        print(f"  Adaptive: {adaptive_edge:.2f}%")
        print(f"  Improvement: {improvement:+.2f}%")
        
        print(f"\nSample size:")
        print(f"  Baseline: {len(baseline_df)} signals")
        print(f"  Adaptive: {len(adaptive_df)} signals")
        
        print(f"\nWin rate (h20):")
        print(f"  Baseline: {baseline_df['hit_h20'].mean()*100:.1f}%")
        print(f"  Adaptive: {adaptive_df['hit_h20'].mean()*100:.1f}%")
        
        # Save results
        output_dir = Path(__file__).parent.parent / "journal"
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        results = {
            'timestamp': datetime.now().isoformat(),
            'period': f'{start_date} to {end_date}',
            'market_condition': 'BEAR (BTC $69K → $15K)',
            'rsi_status': 'FIXED 2026-05-23',
            'baseline': {
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
            'improvement': {
                'edge_delta': float(improvement),
                'edge_delta_pct': float(improvement / abs(baseline_edge) * 100) if baseline_edge != 0 else 0
            }
        }
        
        save_results(results, output_dir / f"short_bear2022_{timestamp}.json")
        
        # Verdict
        print(f"\n{'='*60}")
        print("VERDICT")
        print(f"{'='*60}")
        
        if baseline_edge > 2.0:
            print(f"\n✅ HYPOTHESIS CONFIRMED: SHORT has POSITIVE edge in bear market")
            print(f"   Baseline edge: {baseline_edge:+.2f}%")
            print(f"   Adaptive edge: {adaptive_edge:+.2f}%")
            print(f"   Recommendation: DEPLOY SHORT with regime gate")
        elif baseline_edge > 0:
            print(f"\n⚠️  MARGINAL EDGE: SHORT has small positive edge")
            print(f"   Baseline edge: {baseline_edge:+.2f}%")
            print(f"   Recommendation: Deploy with regime gate, monitor closely")
        else:
            print(f"\n❌ HYPOTHESIS REJECTED: SHORT has NEGATIVE edge even in bear")
            print(f"   Baseline edge: {baseline_edge:+.2f}%")
            print(f"   Recommendation: DO NOT deploy SHORT")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
