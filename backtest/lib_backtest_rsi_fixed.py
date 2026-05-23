#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
lib_backtest_rsi_fixed.py -- Core backtest library com RSI CORRIGIDO

FIXED 2026-05-23: RSI calculation corrigido (estava retornando 0.0)

Este módulo centraliza:
1. RSI calculation (FIXED)
2. Data fetching (CoinEx + Binance)
3. Signal detection (SHORT + LONG)
4. Regime detection
5. Backtest execution engine

Todos os backtests devem importar deste módulo para garantir consistência.
"""

import json
import pandas as pd
import numpy as np
import requests
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ============================================================================
# FIXED RSI CALCULATION (2026-05-23)
# Bug: Original implementation had index out of bounds in loop
# Fix: Properly calculate first RSI value, then iterate correctly
# ============================================================================

def calculate_rsi(closes, period=14):
    """
    Calculate RSI - FIXED 2026-05-23
    
    Args:
        closes: Array of closing prices
        period: RSI period (default 14)
    
    Returns:
        Array of RSI values (same length as closes)
    """
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
# DATA FETCHING
# ============================================================================

def fetch_ohlcv_coinex(symbol, timeframe='1day', limit=1000):
    """
    Fetch OHLCV from CoinEx API
    
    Args:
        symbol: Market symbol (e.g., 'BTCUSDT')
        timeframe: Timeframe ('1day', '4hour', '1hour')
        limit: Number of candles to fetch
    
    Returns:
        DataFrame with columns: timestamp, open, high, low, close, volume
    """
    url = f"https://api.coinex.com/v2/spot/kline?market={symbol}&period={timeframe}&limit={limit}"
    try:
        r = requests.get(url, timeout=10)
        data = r.json()
        if data['code'] == 0 and data['data']:
            df = pd.DataFrame(data['data'])
            df['timestamp'] = pd.to_datetime(df['created_at'].astype(float), unit='ms')
            df['open'] = df['open'].astype(float)
            df['high'] = df['high'].astype(float)
            df['low'] = df['low'].astype(float)
            df['close'] = df['close'].astype(float)
            df['volume'] = df['volume'].astype(float)
            return df[['timestamp', 'open', 'high', 'low', 'close', 'volume']]
    except Exception as e:
        print(f"ERROR fetching CoinEx data: {e}")
    return None


def fetch_ohlcv_binance(symbol, timeframe='1d', start_date=None, end_date=None):
    """
    Fetch OHLCV from Binance API (para dados históricos mais antigos)
    
    Args:
        symbol: Market symbol (e.g., 'BTCUSDT')
        timeframe: Timeframe ('1d', '4h', '1h')
        start_date: Start date string 'YYYY-MM-DD'
        end_date: End date string 'YYYY-MM-DD'
    
    Returns:
        DataFrame with columns: timestamp, open, high, low, close, volume
    """
    url = "https://api.binance.com/api/v3/klines"
    
    # Convert dates to timestamps
    if start_date:
        start_ts = int(datetime.strptime(start_date, '%Y-%m-%d').timestamp() * 1000)
    else:
        start_ts = None
    
    if end_date:
        end_ts = int(datetime.strptime(end_date, '%Y-%m-%d').timestamp() * 1000)
    else:
        end_ts = None
    
    all_data = []
    current_start = start_ts
    
    while True:
        params = {
            'symbol': symbol,
            'interval': timeframe,
            'limit': 1000
        }
        
        if current_start:
            params['startTime'] = current_start
        if end_ts:
            params['endTime'] = end_ts
        
        try:
            r = requests.get(url, params=params, timeout=10)
            data = r.json()
            
            if not data or len(data) == 0:
                break
            
            all_data.extend(data)
            
            # Check if we got all data
            if len(data) < 1000:
                break
            
            # Update start time for next batch
            current_start = data[-1][0] + 1
            
            # Check if we reached end date
            if end_ts and current_start >= end_ts:
                break
                
        except Exception as e:
            print(f"ERROR fetching Binance data: {e}")
            break
    
    if not all_data:
        return None
    
    # Convert to DataFrame
    df = pd.DataFrame(all_data, columns=[
        'timestamp', 'open', 'high', 'low', 'close', 'volume',
        'close_time', 'quote_volume', 'trades', 'taker_buy_base',
        'taker_buy_quote', 'ignore'
    ])
    
    df['timestamp'] = pd.to_datetime(df['timestamp'].astype(float), unit='ms')
    df['open'] = df['open'].astype(float)
    df['high'] = df['high'].astype(float)
    df['low'] = df['low'].astype(float)
    df['close'] = df['close'].astype(float)
    df['volume'] = df['volume'].astype(float)
    
    return df[['timestamp', 'open', 'high', 'low', 'close', 'volume']]


# ============================================================================
# REGIME DETECTION
# ============================================================================

def detect_regime_simple(btc_closes, lookback=90):
    """
    Detect regime based on BTC drawdown
    
    BEAR_STRONG: DD < -20%
    BEAR_WEAK: DD -10% to -20%
    TRANSITION_DOWN: DD -5% to -10%
    BULL_WEAK: DD -2% to -5%
    BULL_STRONG: DD > -2%
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
    elif dd < -2:
        return "BULL_WEAK"
    else:
        return "BULL_STRONG"


# ============================================================================
# SIGNAL DETECTION
# ============================================================================

def detect_short_signal(highs, lows, closes, volumes, 
                       climax_mult=2.5, rsi_min=70, lookback=20):
    """
    Detect SHORT buying climax signal (FIXED RSI)
    
    Args:
        highs, lows, closes, volumes: Price/volume arrays
        climax_mult: Volume spike multiplier
        rsi_min: Minimum RSI for overbought
        lookback: Lookback period for volume average
    
    Returns:
        (detected, vol_ratio, rejection, rsi_val)
    """
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


def detect_long_signal(highs, lows, closes, volumes,
                      climax_mult=2.5, rsi_max=30, lookback=20):
    """
    Detect LONG selling climax signal (FIXED RSI)
    
    Args:
        highs, lows, closes, volumes: Price/volume arrays
        climax_mult: Volume spike multiplier
        rsi_max: Maximum RSI for oversold
        lookback: Lookback period for volume average
    
    Returns:
        (detected, vol_ratio, rejection, rsi_val)
    """
    if len(closes) < lookback + 1:
        return False, 0, 0, 0
    
    # Vol spike
    vol_avg = np.mean(volumes[-lookback-1:-1])
    vol_ratio = volumes[-1] / vol_avg if vol_avg > 0 else 0
    
    if vol_ratio < climax_mult:
        return False, vol_ratio, 0, 0
    
    # New low
    prior_lows = lows[-lookback-1:-1]
    min_prior = np.min(prior_lows)
    
    if lows[-1] >= min_prior:
        return False, vol_ratio, 0, 0
    
    # Close rejection (bounce from low)
    rng = highs[-1] - lows[-1]
    if rng == 0:
        return False, vol_ratio, 0, 0
    
    rejection = (closes[-1] - lows[-1]) / rng
    if rejection < 0.3:
        return False, vol_ratio, 0, 0
    
    # RSI oversold (FIXED: calculate RSI properly)
    rsi_array = calculate_rsi(closes, period=14)
    rsi_val = rsi_array[-1]
    
    if rsi_val >= rsi_max:
        return False, vol_ratio, rejection, rsi_val
    
    return True, vol_ratio, rejection, rsi_val


# ============================================================================
# BACKTEST ENGINE
# ============================================================================

def compute_forward_returns(df, entry_idx, horizons=[20, 24]):
    """
    Compute forward returns for LONG position
    
    Args:
        df: DataFrame with price data
        entry_idx: Entry index
        horizons: List of forward horizons (in bars)
    
    Returns:
        Dict with {h20_return, h24_return, hit_h20, hit_h24}
    """
    entry_price = df.iloc[entry_idx]['close']
    results = {}
    
    for h in horizons:
        if entry_idx + h < len(df):
            exit_price = df.iloc[entry_idx + h]['close']
            ret = (exit_price - entry_price) / entry_price * 100
            results[f'h{h}_return'] = ret
            results[f'hit_h{h}'] = ret > 0
        else:
            results[f'h{h}_return'] = 0
            results[f'hit_h{h}'] = False
    
    return results


def compute_forward_returns_short(df, entry_idx, horizons=[20, 24]):
    """
    Compute forward returns for SHORT position
    
    Args:
        df: DataFrame with price data
        entry_idx: Entry index
        horizons: List of forward horizons (in bars)
    
    Returns:
        Dict with {h20_return, h24_return, hit_h20, hit_h24}
    """
    entry_price = df.iloc[entry_idx]['close']
    results = {}
    
    for h in horizons:
        if entry_idx + h < len(df):
            exit_price = df.iloc[entry_idx + h]['close']
            # SHORT: profit when price drops
            ret = (entry_price - exit_price) / entry_price * 100
            results[f'h{h}_return'] = ret
            results[f'hit_h{h}'] = ret > 0
        else:
            results[f'h{h}_return'] = 0
            results[f'hit_h{h}'] = False
    
    return results


# ============================================================================
# REGIME-SPECIFIC THRESHOLDS
# ============================================================================

REGIME_THRESHOLDS_SHORT = {
    "BEAR_STRONG": {"climax_mult": 2.0, "rsi_min": 75},
    "BEAR_WEAK": {"climax_mult": 2.5, "rsi_min": 70},
    "TRANSITION_DOWN": {"climax_mult": 3.0, "rsi_min": 65},
    "BULL_WEAK": {"climax_mult": 3.5, "rsi_min": 70},
    "BULL_STRONG": {"climax_mult": 4.0, "rsi_min": 75},
    "UNKNOWN": {"climax_mult": 3.0, "rsi_min": 70},
}

REGIME_THRESHOLDS_LONG = {
    "BEAR_STRONG": {"climax_mult": 2.0, "rsi_max": 25},
    "BEAR_WEAK": {"climax_mult": 2.5, "rsi_max": 30},
    "TRANSITION_DOWN": {"climax_mult": 3.0, "rsi_max": 35},
    "BULL_WEAK": {"climax_mult": 3.5, "rsi_max": 30},
    "BULL_STRONG": {"climax_mult": 4.0, "rsi_max": 25},
    "UNKNOWN": {"climax_mult": 2.5, "rsi_max": 30},
}

BASELINE_THRESHOLDS_SHORT = {"climax_mult": 2.5, "rsi_min": 70}
BASELINE_THRESHOLDS_LONG = {"climax_mult": 2.5, "rsi_max": 30}


# ============================================================================
# UTILITIES
# ============================================================================

def save_results(results, output_path):
    """Save backtest results to JSON file"""
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Convert pandas Timestamps to strings
    def convert_timestamps(obj):
        if isinstance(obj, pd.Timestamp):
            return obj.isoformat()
        elif isinstance(obj, dict):
            return {k: convert_timestamps(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [convert_timestamps(item) for item in obj]
        return obj
    
    results = convert_timestamps(results)
    
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    
    print(f"\nResults saved: {output_path}")


def print_summary(signals_df, mode_name):
    """Print backtest summary"""
    if signals_df is None or len(signals_df) == 0:
        print(f"\n{mode_name}: NO SIGNALS")
        return
    
    print(f"\n{'='*60}")
    print(f"{mode_name} RESULTS")
    print(f"{'='*60}")
    print(f"Total signals: {len(signals_df)}")
    print(f"Date range: {signals_df['date'].min()} to {signals_df['date'].max()}")
    
    # Overall stats
    print(f"\nOVERALL:")
    print(f"  h20 hit rate: {signals_df['hit_h20'].mean()*100:.1f}%")
    print(f"  h20 avg return: {signals_df['h20_return'].mean():.2f}%")
    print(f"  h24 hit rate: {signals_df['hit_h24'].mean()*100:.1f}%")
    print(f"  h24 avg return: {signals_df['h24_return'].mean():.2f}%")
    
    # By regime (if available)
    if 'regime' in signals_df.columns:
        print(f"\nBY REGIME:")
        for regime in signals_df['regime'].unique():
            regime_df = signals_df[signals_df['regime'] == regime]
            print(f"\n  {regime} (n={len(regime_df)}):")
            print(f"    h20 hit: {regime_df['hit_h20'].mean()*100:.1f}%")
            print(f"    h20 avg: {regime_df['h20_return'].mean():.2f}%")
