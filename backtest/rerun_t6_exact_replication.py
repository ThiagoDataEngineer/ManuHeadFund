#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rerun_t6_exact_replication.py -- Replicar T6 EXATO com signal_generator

OBJETIVO: Validar se T6 original estava correto (505 signals, +2.85% edge)

METODOLOGIA TDD:
1. Usar signal_generator.generate_signal() (EXATO como T6)
2. Usar data fetcher unificado (histórico completo)
3. Testar em 2018 + 2022 (bear markets, como T6)
4. Comparar com T6 original

HIPÓTESE:
- Se signals ~505: T6 estava correto, signal_generator tem edge
- Se signals ~13: T6 tinha outro bug
- Se intermediário: Diferença é data source ou período
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


def scan_with_signal_generator(df, start_date, end_date, min_window=60):
    """
    Scan usando signal_generator.generate_signal() (EXATO como T6)
    
    Returns:
        List of signals with forward returns
    """
    # Filter by date range
    df_period = df[(df['timestamp'] >= start_date) & (df['timestamp'] <= end_date)].copy()
    df_period = df_period.reset_index(drop=True)
    
    print(f"\nScanning {start_date} to {end_date}")
    print(f"Data points: {len(df_period)}")
    
    signals = []
    
    for i in range(min_window, len(df_period)):
        # Prepare candles window (como T6 faz)
        window = []
        for j in range(max(0, i - 200), i + 1):
            candle = {
                'timestamp': df_period.iloc[j]['timestamp'].timestamp(),
                'open': df_period.iloc[j]['open'],
                'high': df_period.iloc[j]['high'],
                'low': df_period.iloc[j]['low'],
                'close': df_period.iloc[j]['close'],
                'volume': df_period.iloc[j]['volume'],
            }
            window.append(candle)
        
        # Generate signal
        try:
            sig = generate_signal(window)
        except Exception as e:
            continue
        
        # Check if SHORT signal
        if sig.signal != "VENDA":
            continue
        
        # Signal detected!
        entry_price = df_period.iloc[i]['close']
        entry_date = df_period.iloc[i]['timestamp']
        
        # Forward returns (h20, h24)
        h20_return = 0
        h24_return = 0
        
        if i + 20 < len(df_period):
            h20_price = df_period.iloc[i + 20]['close']
            h20_return = (entry_price - h20_price) / entry_price * 100  # SHORT
        
        if i + 24 < len(df_period):
            h24_price = df_period.iloc[i + 24]['close']
            h24_return = (entry_price - h24_price) / entry_price * 100  # SHORT
        
        signals.append({
            'date': entry_date,
            'entry_price': entry_price,
            'score': sig.score,
            'indicators': sig.indicators,
            'h20_return': h20_return,
            'h24_return': h24_return,
            'hit_h20': h20_return > 0,
            'hit_h24': h24_return > 0,
        })
    
    return signals


def main():
    """Main execution"""
    print("="*60)
    print("T6 EXACT REPLICATION")
    print("Using signal_generator.generate_signal()")
    print("="*60)
    
    symbol = "BTCUSDT"
    
    # Fetch FULL historical data (usando data fetcher unificado)
    print("\nFetching historical data...")
    df = fetch_ohlcv(symbol, timeframe='1d', start_date='2011-01-01', end_date='2026-12-31')
    
    if df is None or len(df) < 100:
        print("ERROR: Failed to fetch data")
        return 1
    
    print(f"\nTotal data: {len(df)} candles")
    print(f"Date range: {df['timestamp'].min()} to {df['timestamp'].max()}")
    print(f"Years: {(df['timestamp'].max() - df['timestamp'].min()).days / 365.25:.1f}")
    
    # Test Period 1: Bear 2018 (como T6 original)
    print(f"\n{'='*60}")
    print("PERIOD 1: BEAR 2018")
    print(f"{'='*60}")
    
    signals_2018 = scan_with_signal_generator(
        df, 
        pd.to_datetime('2018-01-01'),
        pd.to_datetime('2018-12-31')
    )
    
    df_2018 = pd.DataFrame(signals_2018) if signals_2018 else None
    
    if df_2018 is not None and len(df_2018) > 0:
        print(f"\nSignals: {len(df_2018)}")
        print(f"Edge (h20): {df_2018['h20_return'].mean():.2f}%")
        print(f"Win rate (h20): {df_2018['hit_h20'].mean()*100:.1f}%")
        print(f"Edge (h24): {df_2018['h24_return'].mean():.2f}%")
        print(f"Win rate (h24): {df_2018['hit_h24'].mean()*100:.1f}%")
    else:
        print("\nNO SIGNALS")
    
    # Test Period 2: Bear 2022 (como T6 original)
    print(f"\n{'='*60}")
    print("PERIOD 2: BEAR 2022")
    print(f"{'='*60}")
    
    signals_2022 = scan_with_signal_generator(
        df,
        pd.to_datetime('2022-01-01'),
        pd.to_datetime('2022-12-31')
    )
    
    df_2022 = pd.DataFrame(signals_2022) if signals_2022 else None
    
    if df_2022 is not None and len(df_2022) > 0:
        print(f"\nSignals: {len(df_2022)}")
        print(f"Edge (h20): {df_2022['h20_return'].mean():.2f}%")
        print(f"Win rate (h20): {df_2022['hit_h20'].mean()*100:.1f}%")
        print(f"Edge (h24): {df_2022['h24_return'].mean():.2f}%")
        print(f"Win rate (h24): {df_2022['hit_h24'].mean()*100:.1f}%")
    else:
        print("\nNO SIGNALS")
    
    # Combined results
    print(f"\n{'='*60}")
    print("COMBINED RESULTS (2018 + 2022)")
    print(f"{'='*60}")
    
    all_signals = signals_2018 + signals_2022
    df_all = pd.DataFrame(all_signals) if all_signals else None
    
    if df_all is not None and len(df_all) > 0:
        print(f"\nTotal signals: {len(df_all)}")
        print(f"Edge (h20): {df_all['h20_return'].mean():.2f}%")
        print(f"Win rate (h20): {df_all['hit_h20'].mean()*100:.1f}%")
        print(f"Edge (h24): {df_all['h24_return'].mean():.2f}%")
        print(f"Win rate (h24): {df_all['hit_h24'].mean()*100:.1f}%")
        
        # Save results
        output_dir = Path(__file__).parent.parent / "journal"
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        results = {
            'timestamp': datetime.now().isoformat(),
            'method': 'signal_generator.generate_signal()',
            'periods': ['2018', '2022'],
            'total_signals': len(df_all),
            'edge_h20': float(df_all['h20_return'].mean()),
            'win_rate_h20': float(df_all['hit_h20'].mean()),
            'edge_h24': float(df_all['h24_return'].mean()),
            'win_rate_h24': float(df_all['hit_h24'].mean()),
            'period_2018': {
                'signals': len(df_2018) if df_2018 is not None else 0,
                'edge_h20': float(df_2018['h20_return'].mean()) if df_2018 is not None else 0,
                'win_rate_h20': float(df_2018['hit_h20'].mean()) if df_2018 is not None else 0,
            },
            'period_2022': {
                'signals': len(df_2022) if df_2022 is not None else 0,
                'edge_h20': float(df_2022['h20_return'].mean()) if df_2022 is not None else 0,
                'win_rate_h20': float(df_2022['hit_h20'].mean()) if df_2022 is not None else 0,
            },
            't6_original': {
                'signals': 505,
                'edge': 2.85,
                'note': 'T6 original result (com RSI bugado)'
            },
            'signals_data': df_all.to_dict('records')
        }
        
        save_results(results, output_dir / f"t6_exact_replication_{timestamp}.json")
        
        # Comparison with T6 original
        print(f"\n{'='*60}")
        print("COMPARISON WITH T6 ORIGINAL")
        print(f"{'='*60}")
        
        print(f"\nT6 Original (RSI bugado):")
        print(f"  Signals: 505")
        print(f"  Edge: +2.85%")
        
        print(f"\nT6 Replication (RSI corrigido):")
        print(f"  Signals: {len(df_all)}")
        print(f"  Edge: {df_all['h20_return'].mean():+.2f}%")
        
        delta_signals = len(df_all) - 505
        delta_edge = df_all['h20_return'].mean() - 2.85
        
        print(f"\nDelta:")
        print(f"  Signals: {delta_signals:+d} ({delta_signals/505*100:+.1f}%)")
        print(f"  Edge: {delta_edge:+.2f}%")
        
        # Verdict
        print(f"\n{'='*60}")
        print("VERDICT")
        print(f"{'='*60}")
        
        if abs(len(df_all) - 505) < 50:  # Within 10%
            print(f"\n✅ SIGNAL COUNT MATCHES (~{len(df_all)} vs 505)")
            print(f"   T6 original estava correto")
            
            if df_all['h20_return'].mean() > 2.0:
                print(f"\n✅ EDGE CONFIRMED ({df_all['h20_return'].mean():+.2f}% vs +2.85%)")
                print(f"   signal_generator tem edge real")
                print(f"   Recommendation: Deploy SHORT com signal_generator")
            elif df_all['h20_return'].mean() > 0:
                print(f"\n⚠️  EDGE DECREASED ({df_all['h20_return'].mean():+.2f}% vs +2.85%)")
                print(f"   RSI fix reduziu edge mas ainda positivo")
                print(f"   Recommendation: Deploy com cautela")
            else:
                print(f"\n❌ EDGE NEGATIVE ({df_all['h20_return'].mean():+.2f}%)")
                print(f"   Original +2.85% era artefato do RSI bug")
                print(f"   Recommendation: DO NOT deploy")
        else:
            print(f"\n❌ SIGNAL COUNT MISMATCH ({len(df_all)} vs 505)")
            print(f"   Discrepância: {abs(delta_signals)} signals ({abs(delta_signals)/505*100:.1f}%)")
            
            if len(df_all) < 100:
                print(f"\n   Possíveis causas:")
                print(f"   1. Data source diferente (Bitstamp+Binance vs T6 original)")
                print(f"   2. RSI bug afetou signal_generator")
                print(f"   3. T6 original tinha outro bug")
            else:
                print(f"\n   signal_generator gera signals mas quantidade diferente")
                print(f"   Pode ser data source ou período exato")
    else:
        print("\nNO SIGNALS DETECTED")
        print("\n❌ CRITICAL: signal_generator não detectou SHORT signals")
        print("   Possíveis causas:")
        print("   1. signal_generator quebrado")
        print("   2. Data incompatível")
        print("   3. Período errado")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
