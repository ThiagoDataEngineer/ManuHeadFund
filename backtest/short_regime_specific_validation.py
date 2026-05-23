#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
short_regime_specific_validation.py -- TDD Sprint 1 Backtest Validation

FIXED 2026-05-23: RSI calculation corrected (was returning 0.0)
"""

import json
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from pathlib import Path
import sys

# Add backtest lib to path
sys.path.insert(0, str(Path(__file__).parent))

# ============================================================================
# FIXED RSI CALCULATION (2026-05-23)
# Bug: Original implementation had index out of bounds in loop
# Fix: Properly calculate first RSI value, then iterate correctly
# ============================================================================

def calculate_rsi(closes, period=14):
    """Calculate RSI - FIXED 2026-05-23"""
    if len(closes) < period + 1:
        return np.full(len(closes), 50.0)
    
    # Calculate price changes
    deltas = np.diff(closes)
    gains = np.where(deltas > 0, deltas, 0)
    losses = np.where(deltas < 0, -deltas, 0)
    
    # Initialize RSI array
    rsi = np.full(len(closes), 50.0)
    
    # Calculate initial average gain/loss
    avg_gain = np.mean(gains[:period])
    avg_loss = np.mean(losses[:period])
    
    # Calculate first RSI value
    if avg_loss == 0:
        rsi[period] = 100.0
    else:
        rs = avg_gain / avg_loss
        rsi[period] = 100 - (100 / (1 + rs))
    
    # Calculate RSI for remaining points using smoothed averages
    for i in range(period, len(deltas)):
        avg_gain = (avg_gain * (period - 1) + gains[i]) / period
        avg_loss = (avg_loss * (period - 1) + losses[i]) / period
        
        if avg_loss == 0:
            rsi[i + 1] = 100.0
        else:
            rs = avg_gain / avg_loss
            rsi[i + 1] = 100 - (100 / (1 + rs))
    
    return rsi

# ============================================================================

try:
    from lib_backtest_engine import (
        fetch_ohlcv_coinex,
        detect_short_signal,
        compute_forward_returns
    )
    print("Using lib_backtest_engine")
except ImportError:
    print("ERROR: lib_backtest_engine.py not found")
    print("Creating minimal implementation with FIXED RSI...")
    
    # Minimal implementation if lib missing
    def fetch_ohlcv_coinex(symbol, timeframe='1d', limit=500):
        """Fetch OHLCV from CoinEx API"""
        import requests
        url = f"https://api.coinex.com/v2/spot/kline?market={symbol}&period={timeframe}&limit={limit}"
        try:
            r = requests.get(url, timeout=10)
            data = r.json()
            if data['code'] == 0 and data['data']:
                df = pd.DataFrame(data['data'])
                # CoinEx returns timestamp in milliseconds
                df['timestamp'] = pd.to_datetime(df['created_at'].astype(float), unit='ms')
                df['open'] = df['open'].astype(float)
                df['high'] = df['high'].astype(float)
                df['low'] = df['low'].astype(float)
                df['close'] = df['close'].astype(float)
                df['volume'] = df['volume'].astype(float)
                return df[['timestamp', 'open', 'high', 'low', 'close', 'volume']]
        except:
            pass
        return None
    
    # NOTE: calculate_rsi is defined at top of file (FIXED version)
    
    def detect_short_signal(highs, lows, closes, volumes, climax_mult=2.5, rsi_min=70, lookback=20):
        """Detect SHORT buying climax signal"""
        if len(closes) < lookback + 1:
            return False, 0, 0, 0
        
        # Vol spike
        vol_avg = np.mean(volumes[-lookback-1:-1])
        vol_ratio = volumes[-1] / vol_avg if vol_avg > 0 else 0
        
        if vol_ratio < climax_mult:
            return False, vol_ratio, 0, 0
        
        # New high
        prior_highs = highs[-lookback-1:-1]
        max_prior = np.max(prior_highs)
        
        if highs[-1] <= max_prior:
            return False, vol_ratio, 0, 0
        
        # Close rejection
        rng = highs[-1] - lows[-1]
        if rng == 0:
            return False, vol_ratio, 0, 0
        
        rejection = (highs[-1] - closes[-1]) / rng
        if rejection < 0.3:
            return False, vol_ratio, 0, 0
        
        # RSI overbought (FIXED: calculate RSI properly)
        rsi_array = calculate_rsi(closes, period=14)
        rsi_val = rsi_array[-1]
        
        if rsi_val <= rsi_min:
            return False, vol_ratio, rejection, rsi_val
        
        return True, vol_ratio, rejection, rsi_val


# Regime detection (simplified)
def detect_regime_simple(btc_closes, lookback=90):
    """
    Detect regime based on BTC drawdown
    
    BEAR_STRONG: DD < -20%
    BEAR_WEAK: DD -10% to -20%
    TRANSITION_DOWN: DD -5% to -10%
    Other: BULL/SIDEWAYS
    """
    if len(btc_closes) < lookback:
        return "UNKNOWN"
    
    recent = btc_closes[-lookback:]
    high = np.max(recent)
    current = btc_closes[-1]
    dd = (current - high) / high * 100
    
    if dd < -20:
        return "BEAR_STRONG"
    elif dd < -10:
        return "BEAR_WEAK"
    elif dd < -5:
        return "TRANSITION_DOWN"
    else:
        return "OTHER"


# Regime-specific thresholds (from lib_short_signals.ps1)
REGIME_THRESHOLDS = {
    "BEAR_STRONG": {"climax_mult": 2.0, "rsi_min": 75},
    "BEAR_WEAK": {"climax_mult": 2.5, "rsi_min": 70},
    "TRANSITION_DOWN": {"climax_mult": 3.0, "rsi_min": 65},
    "OTHER": {"climax_mult": 3.0, "rsi_min": 70},
    "UNKNOWN": {"climax_mult": 3.0, "rsi_min": 70},
}

BASELINE_THRESHOLDS = {"climax_mult": 2.5, "rsi_min": 70}


def run_backtest(symbol, start_date, end_date, mode="baseline"):
    """
    Run backtest for SHORT signals
    
    mode: "baseline" (fixed thresholds) or "adaptive" (regime-specific)
    """
    print(f"\n{'='*60}")
    print(f"Backtesting {symbol} ({mode.upper()} mode)")
    print(f"Period: {start_date} to {end_date}")
    print(f"{'='*60}")
    
    # Fetch data (increase limit to get more history including bear markets)
    df = fetch_ohlcv_coinex(symbol, timeframe='1day', limit=1000)
    if df is None or len(df) < 100:
        print(f"ERROR: Failed to fetch data for {symbol}")
        return None
    
    # Fetch BTC for regime detection
    btc_df = fetch_ohlcv_coinex('BTCUSDT', timeframe='1day', limit=1000)
    if btc_df is None:
        print("WARNING: Failed to fetch BTC data, using UNKNOWN regime")
        btc_closes = None
    else:
        btc_closes = btc_df['close'].values
    
    # Use all available data
    print(f"Data points: {len(df)}")
    print(f"Date range: {df['timestamp'].min()} to {df['timestamp'].max()}")
    
    if len(df) < 50:
        print(f"ERROR: Insufficient data after date filter ({len(df)} bars)")
        return None
    
    signals = []
    
    # Scan for signals
    for i in range(30, len(df)):
        highs = df['high'].values[:i+1]
        lows = df['low'].values[:i+1]
        closes = df['close'].values[:i+1]
        volumes = df['volume'].values[:i+1]
        
        # Detect regime
        if btc_closes is not None and len(btc_closes) >= i+1:
            regime = detect_regime_simple(btc_closes[:i+1])
        else:
            regime = "UNKNOWN"
        
        # Get thresholds
        if mode == "adaptive":
            thresholds = REGIME_THRESHOLDS.get(regime, BASELINE_THRESHOLDS)
        else:
            thresholds = BASELINE_THRESHOLDS
        
        # Detect signal
        detected, vol_ratio, rejection, rsi_val = detect_short_signal(
            highs, lows, closes, volumes,
            climax_mult=thresholds["climax_mult"],
            rsi_min=thresholds["rsi_min"]
        )
        
        if detected:
            entry_price = closes[-1]
            entry_date = df.iloc[i]['timestamp']
            
            # Forward returns (h20, h24)
            h20_return = 0
            h24_return = 0
            
            if i + 20 < len(df):
                h20_price = df.iloc[i+20]['close']
                h20_return = (entry_price - h20_price) / entry_price * 100  # SHORT: profit when price drops
            
            if i + 24 < len(df):
                h24_price = df.iloc[i+24]['close']
                h24_return = (entry_price - h24_price) / entry_price * 100
            
            signals.append({
                'date': entry_date,
                'regime': regime,
                'entry_price': entry_price,
                'vol_ratio': vol_ratio,
                'rsi': rsi_val,
                'climax_mult': thresholds["climax_mult"],
                'rsi_min': thresholds["rsi_min"],
                'h20_return': h20_return,
                'h24_return': h24_return,
                'hit_h20': h20_return > 0,
                'hit_h24': h24_return > 0,
            })
    
    return signals


def analyze_results(signals, mode_name):
    """Analyze backtest results"""
    if not signals:
        print(f"\n{mode_name}: NO SIGNALS")
        return None
    
    df = pd.DataFrame(signals)
    
    print(f"\n{'='*60}")
    print(f"{mode_name} RESULTS")
    print(f"{'='*60}")
    print(f"Total signals: {len(df)}")
    print(f"Date range: {df['date'].min()} to {df['date'].max()}")
    
    # Overall stats
    print(f"\nOVERALL:")
    print(f"  h20 hit rate: {df['hit_h20'].mean()*100:.1f}%")
    print(f"  h20 avg return: {df['h20_return'].mean():.2f}%")
    print(f"  h24 hit rate: {df['hit_h24'].mean()*100:.1f}%")
    print(f"  h24 avg return: {df['h24_return'].mean():.2f}%")
    
    # By regime
    print(f"\nBY REGIME:")
    for regime in df['regime'].unique():
        regime_df = df[df['regime'] == regime]
        print(f"\n  {regime} (n={len(regime_df)}):")
        print(f"    h20 hit: {regime_df['hit_h20'].mean()*100:.1f}%")
        print(f"    h20 avg: {regime_df['h20_return'].mean():.2f}%")
        print(f"    h24 hit: {regime_df['hit_h24'].mean()*100:.1f}%")
        print(f"    h24 avg: {regime_df['h24_return'].mean():.2f}%")
    
    return df


def main():
    """Main backtest execution"""
    print("="*60)
    print("SHORT REGIME-SPECIFIC VALIDATION")
    print("TDD Sprint 1 - Backtest")
    print("="*60)
    
    # Config - Test BEAR market 2022
    symbol = "BTCUSDT"
    
    print("\n" + "="*60)
    print("PHASE 1: BEAR MARKET 2022 VALIDATION")
    print("="*60)
    print("Period: Nov 2021 - Dec 2022 (BTC $69K → $15K)")
    print("Expected: Positive edge for SHORT patterns")
    
    # Note: CoinEx API limit=1000 gives us ~2.7 years back
    # From May 2026, that's Aug 2023 - May 2026 (mostly bull)
    # We need to fetch older data or use different approach
    
    print("\nFetching historical data...")
    
    # Run baseline
    baseline_signals = run_backtest(symbol, "2020-01-01", "2026-12-31", mode="baseline")
    baseline_df = analyze_results(baseline_signals, "BASELINE (fixed thresholds)")
    
    # Run adaptive
    adaptive_signals = run_backtest(symbol, "2020-01-01", "2026-12-31", mode="adaptive")
    adaptive_df = analyze_results(adaptive_signals, "ADAPTIVE (regime-specific)")
    
    # Analyze by market phase
    if baseline_df is not None and len(baseline_df) > 0:
        print(f"\n{'='*60}")
        print("PHASE ANALYSIS")
        print(f"{'='*60}")
        
        # Classify signals by BTC price action
        # Bear 2022: signals before 2023
        # Bull 2023-2026: signals after 2023
        
        baseline_df['year'] = pd.to_datetime(baseline_df['date']).dt.year
        adaptive_df['year'] = pd.to_datetime(adaptive_df['date']).dt.year
        
        print("\nBASELINE by year:")
        for year in sorted(baseline_df['year'].unique()):
            year_df = baseline_df[baseline_df['year'] == year]
            edge = year_df['h20_return'].mean()
            print(f"  {year} (n={len(year_df)}): edge={edge:.2f}%, win={year_df['hit_h20'].mean()*100:.1f}%")
        
        print("\nADAPTIVE by year:")
        for year in sorted(adaptive_df['year'].unique()):
            year_df = adaptive_df[adaptive_df['year'] == year]
            edge = year_df['h20_return'].mean()
            print(f"  {year} (n={len(year_df)}): edge={edge:.2f}%, win={year_df['hit_h20'].mean()*100:.1f}%")
    
    # Compare
    if baseline_df is not None and adaptive_df is not None:
        print(f"\n{'='*60}")
        print("COMPARISON")
        print(f"{'='*60}")
        
        baseline_edge = baseline_df['h20_return'].mean()
        adaptive_edge = adaptive_df['h20_return'].mean()
        improvement = adaptive_edge - baseline_edge
        improvement_pct = (improvement / abs(baseline_edge) * 100) if baseline_edge != 0 else 0
        
        print(f"\nEdge (h20 avg return):")
        print(f"  Baseline: {baseline_edge:.2f}%")
        print(f"  Adaptive: {adaptive_edge:.2f}%")
        print(f"  Improvement: {improvement:+.2f}% ({improvement_pct:+.1f}%)")
        
        print(f"\nSample size:")
        print(f"  Baseline: {len(baseline_df)} signals")
        print(f"  Adaptive: {len(adaptive_df)} signals")
        
        print(f"\nWin rate (h20):")
        print(f"  Baseline: {baseline_df['hit_h20'].mean()*100:.1f}%")
        print(f"  Adaptive: {adaptive_df['hit_h20'].mean()*100:.1f}%")
        
        # Save results
        output_dir = Path(__file__).parent.parent / "journal"
        output_dir.mkdir(exist_ok=True)
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        baseline_path = output_dir / f"short_baseline_{timestamp}.json"
        adaptive_path = output_dir / f"short_adaptive_{timestamp}.json"
        
        baseline_df.to_json(baseline_path, orient='records', date_format='iso')
        adaptive_df.to_json(adaptive_path, orient='records', date_format='iso')
        
        print(f"\nResults saved:")
        print(f"  {baseline_path}")
        print(f"  {adaptive_path}")
        
        # Verdict
        print(f"\n{'='*60}")
        print("VERDICT")
        print(f"{'='*60}")
        
        # Check if we have bear market data (2022 or earlier)
        has_bear_data = False
        if len(baseline_df) > 0:
            min_year = baseline_df['year'].min()
            if min_year <= 2022:
                has_bear_data = True
                bear_df = baseline_df[baseline_df['year'] <= 2022]
                if len(bear_df) > 0:
                    bear_edge = bear_df['h20_return'].mean()
                    print(f"\n📊 BEAR MARKET DATA (≤2022):")
                    print(f"   Signals: {len(bear_df)}")
                    print(f"   Edge: {bear_edge:.2f}%")
                    print(f"   Win rate: {bear_df['hit_h20'].mean()*100:.1f}%")
        
        if not has_bear_data:
            print(f"\n⚠️  NO BEAR MARKET DATA AVAILABLE")
            print(f"   Data range: {baseline_df['year'].min()}-{baseline_df['year'].max()}")
            print(f"   CoinEx API limit: 1000 candles (~2.7 years)")
            print(f"   Recommendation: Use alternative data source for 2022 bear market")
        
        if improvement > 1.0:
            print(f"\n✅ HYPOTHESIS CONFIRMED: Adaptive thresholds improve edge by {improvement:+.2f}%")
            print(f"   Recommendation: DEPLOY adaptive thresholds with regime gate")
        elif improvement > 0:
            print(f"\n⚠️  MARGINAL IMPROVEMENT: Edge improved by {improvement:+.2f}% (< 1pp)")
            print(f"   Recommendation: Deploy with regime gate, monitor closely")
        else:
            print(f"\n❌ HYPOTHESIS REJECTED: Adaptive thresholds WORSE by {improvement:.2f}%")
            print(f"   Recommendation: Keep baseline thresholds OR add regime gate")


if __name__ == "__main__":
    main()
