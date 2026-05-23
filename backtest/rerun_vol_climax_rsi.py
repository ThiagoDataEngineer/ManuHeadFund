#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rerun_vol_climax_rsi.py -- Re-rodar vol_climax + RSI confluence com RSI CORRIGIDO

OBJETIVO: Validar se edge +20.7pp é real ou artefato do RSI bug
PATTERN: Vol climax (LONG) + RSI<30 confluence
ORIGINAL: +20.7pp edge em phase_3_bear (com RSI bugado)
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
    print("VOL CLIMAX + RSI CONFLUENCE RE-RUN")
    print("RSI FIXED 2026-05-23")
    print("="*60)
    
    symbol = "BTCUSDT"
    
    print(f"\nPattern: Vol climax (LONG) + RSI<30 confluence")
    print("Original: +20.7pp edge (com RSI bugado)")
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
    
    # Run WITHOUT RSI confluence (baseline)
    print(f"\n{'='*60}")
    print("WITHOUT RSI CONFLUENCE (baseline)")
    print(f"{'='*60}")
    
    baseline_signals = []
    for i in range(30, len(df)):
        highs = df['high'].values[:i+1]
        lows = df['low'].values[:i+1]
        closes = df['close'].values[:i+1]
        volumes = df['volume'].values[:i+1]
        
        detected, vol_ratio, rejection, rsi_val = detect_long_signal(
            highs, lows, closes, volumes,
            climax_mult=BASELINE_THRESHOLDS_LONG["climax_mult"],
            rsi_max=100  # Disable RSI filter
        )
        
        if detected:
            entry_price = closes[-1]
            entry_date = df.iloc[i]['timestamp']
            
            # Forward returns
            fwd_returns = compute_forward_returns(df, i, horizons=[20, 24])
            
            baseline_signals.append({
                'date': entry_date,
                'entry_price': entry_price,
                'vol_ratio': vol_ratio,
                'rsi': rsi_val,
                'rsi_confluence': False,
                **fwd_returns
            })
    
    baseline_df = pd.DataFrame(baseline_signals) if baseline_signals else None
    print_summary(baseline_df, "WITHOUT RSI")
    
    # Run WITH RSI confluence (RSI < 30)
    print(f"\n{'='*60}")
    print("WITH RSI<30 CONFLUENCE (FIXED RSI)")
    print(f"{'='*60}")
    
    confluence_signals = []
    for i in range(30, len(df)):
        highs = df['high'].values[:i+1]
        lows = df['low'].values[:i+1]
        closes = df['close'].values[:i+1]
        volumes = df['volume'].values[:i+1]
        
        detected, vol_ratio, rejection, rsi_val = detect_long_signal(
            highs, lows, closes, volumes,
            climax_mult=BASELINE_THRESHOLDS_LONG["climax_mult"],
            rsi_max=30  # RSI confluence
        )
        
        if detected:
            entry_price = closes[-1]
            entry_date = df.iloc[i]['timestamp']
            
            # Forward returns
            fwd_returns = compute_forward_returns(df, i, horizons=[20, 24])
            
            confluence_signals.append({
                'date': entry_date,
                'entry_price': entry_price,
                'vol_ratio': vol_ratio,
                'rsi': rsi_val,
                'rsi_confluence': True,
                **fwd_returns
            })
    
    confluence_df = pd.DataFrame(confluence_signals) if confluence_signals else None
    print_summary(confluence_df, "WITH RSI<30")
    
    # Compare
    if baseline_df is not None and confluence_df is not None:
        print(f"\n{'='*60}")
        print("COMPARISON")
        print(f"{'='*60}")
        
        baseline_edge = baseline_df['h20_return'].mean()
        confluence_edge = confluence_df['h20_return'].mean()
        improvement = confluence_edge - baseline_edge
        
        print(f"\nEdge (h20 avg return):")
        print(f"  Without RSI: {baseline_edge:.2f}%")
        print(f"  With RSI<30: {confluence_edge:.2f}%")
        print(f"  Improvement: {improvement:+.2f}pp")
        
        print(f"\nSample size:")
        print(f"  Without RSI: {len(baseline_df)} signals")
        print(f"  With RSI<30: {len(confluence_df)} signals")
        print(f"  Filtered: {len(baseline_df) - len(confluence_df)} signals ({(1 - len(confluence_df)/len(baseline_df))*100:.1f}%)")
        
        print(f"\nWin rate (h20):")
        print(f"  Without RSI: {baseline_df['hit_h20'].mean()*100:.1f}%")
        print(f"  With RSI<30: {confluence_df['hit_h20'].mean()*100:.1f}%")
        
        # Save results
        output_dir = Path(__file__).parent.parent / "journal"
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        results = {
            'timestamp': datetime.now().isoformat(),
            'period': f'{df["timestamp"].min()} to {df["timestamp"].max()}',
            'rsi_status': 'FIXED 2026-05-23',
            'original_result': '+20.7pp edge (com RSI bugado)',
            'without_rsi': {
                'signals': len(baseline_df),
                'edge_h20': float(baseline_edge),
                'win_rate_h20': float(baseline_df['hit_h20'].mean()),
                'signals_data': baseline_df.to_dict('records')
            },
            'with_rsi_confluence': {
                'signals': len(confluence_df),
                'edge_h20': float(confluence_edge),
                'win_rate_h20': float(confluence_df['hit_h20'].mean()),
                'signals_data': confluence_df.to_dict('records')
            },
            'improvement': {
                'edge_delta': float(improvement),
                'signals_filtered': len(baseline_df) - len(confluence_df),
                'filter_rate': float((1 - len(confluence_df)/len(baseline_df)) * 100)
            }
        }
        
        save_results(results, output_dir / f"vol_climax_rsi_rerun_{timestamp}.json")
        
        # Verdict
        print(f"\n{'='*60}")
        print("VERDICT")
        print(f"{'='*60}")
        
        print(f"\nOriginal (RSI bugado): +20.7pp edge")
        print(f"New (RSI corrigido): {improvement:+.2f}pp edge improvement")
        
        if improvement > 10.0:
            print(f"\n✅ RSI CONFLUENCE WORKS: Edge improved by {improvement:+.2f}pp")
            print(f"   Original result was VALID (not artifact of bug)")
            print(f"   Recommendation: KEEP RSI confluence in production")
        elif improvement > 5.0:
            print(f"\n⚠️  MARGINAL IMPROVEMENT: Edge improved by {improvement:+.2f}pp")
            print(f"   RSI confluence helps but not as much as original")
            print(f"   Recommendation: Keep RSI confluence, monitor closely")
        elif improvement > 0:
            print(f"\n⚠️  SMALL IMPROVEMENT: Edge improved by {improvement:+.2f}pp")
            print(f"   Original +20.7pp was likely artifact of RSI bug")
            print(f"   Recommendation: RSI confluence still helps, but less than expected")
        else:
            print(f"\n❌ NO IMPROVEMENT: RSI confluence WORSE by {improvement:.2f}pp")
            print(f"   Original +20.7pp was artifact of RSI bug")
            print(f"   Recommendation: REMOVE RSI confluence")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
