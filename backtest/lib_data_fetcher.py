#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
lib_data_fetcher.py -- Unified data fetching com fallback automático

FILOSOFIA:
1. CoinEx PRIMEIRO (nossa exchange, dados mais recentes)
2. Binance FALLBACK (histórico antigo, gratuito, confiável)
3. Bitstamp/Kraken FALLBACK (BTC histórico desde 2011)
4. Cache LOCAL (evita re-fetch, acelera backtests)

FEATURES:
- Auto-fallback entre sources
- Cache inteligente (JSON local)
- Merge de múltiplas sources (enriquecimento)
- Validação de dados (gaps, outliers)
- Retry com backoff exponencial
"""

import json
import requests
import pandas as pd
import numpy as np
from pathlib import Path
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Tuple
import time

# ============================================================================
# CONFIGURATION
# ============================================================================

CACHE_DIR = Path(__file__).parent / ".cache"
CACHE_DIR.mkdir(exist_ok=True)

# Timeouts (seconds)
TIMEOUT_COINEX = 10
TIMEOUT_BINANCE = 10
TIMEOUT_BITSTAMP = 15
TIMEOUT_KRAKEN = 15

# Retry config
MAX_RETRIES = 3
RETRY_DELAY = 2  # seconds

# Data validation
MAX_PRICE_CHANGE_PCT = 50  # Flag if price changes >50% in 1 candle
MIN_VOLUME = 0.001  # Flag if volume < this


# ============================================================================
# CACHE MANAGEMENT
# ============================================================================

def get_cache_path(source: str, symbol: str, timeframe: str) -> Path:
    """Get cache file path for given params"""
    filename = f"{source}_{symbol}_{timeframe}.json"
    return CACHE_DIR / filename


def load_from_cache(source: str, symbol: str, timeframe: str, 
                    max_age_hours: int = 24) -> Optional[pd.DataFrame]:
    """
    Load data from cache if exists and not too old
    
    Args:
        source: Data source name
        symbol: Market symbol
        timeframe: Timeframe
        max_age_hours: Max cache age in hours (default 24h)
    
    Returns:
        DataFrame or None if cache miss/expired
    """
    cache_path = get_cache_path(source, symbol, timeframe)
    
    if not cache_path.exists():
        return None
    
    # Check age
    age_hours = (time.time() - cache_path.stat().st_mtime) / 3600
    if age_hours > max_age_hours:
        print(f"  Cache expired ({age_hours:.1f}h old)")
        return None
    
    try:
        with open(cache_path, 'r') as f:
            data = json.load(f)
        
        df = pd.DataFrame(data['candles'])
        df['timestamp'] = pd.to_datetime(df['timestamp'])
        
        print(f"  ✅ Cache hit: {len(df)} candles ({age_hours:.1f}h old)")
        return df
    except Exception as e:
        print(f"  Cache load error: {e}")
        return None


def save_to_cache(df: pd.DataFrame, source: str, symbol: str, timeframe: str):
    """Save DataFrame to cache"""
    cache_path = get_cache_path(source, symbol, timeframe)
    
    try:
        # Convert to JSON-serializable format
        data = {
            'source': source,
            'symbol': symbol,
            'timeframe': timeframe,
            'cached_at': datetime.now().isoformat(),
            'candles': df.to_dict('records')
        }
        
        # Convert timestamps to ISO format
        for candle in data['candles']:
            if isinstance(candle['timestamp'], pd.Timestamp):
                candle['timestamp'] = candle['timestamp'].isoformat()
        
        with open(cache_path, 'w') as f:
            json.dump(data, f)
        
        print(f"  💾 Cached {len(df)} candles")
    except Exception as e:
        print(f"  Cache save error: {e}")


# ============================================================================
# DATA FETCHERS
# ============================================================================

def fetch_coinex(symbol: str, timeframe: str = '1day', limit: int = 1000) -> Optional[pd.DataFrame]:
    """
    Fetch from CoinEx API
    
    Pros: Nossa exchange, dados mais recentes
    Cons: Histórico limitado (~1000 candles)
    """
    url = f"https://api.coinex.com/v2/spot/kline?market={symbol}&period={timeframe}&limit={limit}"
    
    for attempt in range(MAX_RETRIES):
        try:
            r = requests.get(url, timeout=TIMEOUT_COINEX)
            data = r.json()
            
            if data['code'] == 0 and data['data']:
                df = pd.DataFrame(data['data'])
                df['timestamp'] = pd.to_datetime(df['created_at'].astype(float), unit='ms')
                df['open'] = df['open'].astype(float)
                df['high'] = df['high'].astype(float)
                df['low'] = df['low'].astype(float)
                df['close'] = df['close'].astype(float)
                df['volume'] = df['volume'].astype(float)
                df = df[['timestamp', 'open', 'high', 'low', 'close', 'volume']]
                df = df.sort_values('timestamp').reset_index(drop=True)
                return df
        except Exception as e:
            if attempt < MAX_RETRIES - 1:
                time.sleep(RETRY_DELAY * (attempt + 1))
            else:
                print(f"  CoinEx error: {e}")
    
    return None


def fetch_binance(symbol: str, timeframe: str = '1d', 
                 start_date: Optional[str] = None, 
                 end_date: Optional[str] = None) -> Optional[pd.DataFrame]:
    """
    Fetch from Binance API
    
    Pros: Histórico longo (desde 2017), gratuito, confiável
    Cons: Não tem dados pré-2017
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
    
    for attempt in range(MAX_RETRIES):
        try:
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
                
                r = requests.get(url, params=params, timeout=TIMEOUT_BINANCE)
                data = r.json()
                
                if not data or len(data) == 0:
                    break
                
                all_data.extend(data)
                
                if len(data) < 1000:
                    break
                
                current_start = data[-1][0] + 1
                
                if end_ts and current_start >= end_ts:
                    break
                
                time.sleep(0.5)  # Rate limit
            
            if all_data:
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
                df = df[['timestamp', 'open', 'high', 'low', 'close', 'volume']]
                df = df.sort_values('timestamp').reset_index(drop=True)
                return df
            
            break
        except Exception as e:
            if attempt < MAX_RETRIES - 1:
                time.sleep(RETRY_DELAY * (attempt + 1))
            else:
                print(f"  Binance error: {e}")
    
    return None


def fetch_bitstamp(symbol: str = 'btcusd', timeframe: str = '86400',
                  start_date: Optional[str] = None) -> Optional[pd.DataFrame]:
    """
    Fetch from Bitstamp API (BTC only, desde 2011)
    
    Pros: Histórico MUITO longo (desde 2011), gratuito
    Cons: Apenas BTC, API limitada
    
    Note: timeframe em seconds (86400 = 1 day)
    """
    url = f"https://www.bitstamp.net/api/v2/ohlc/{symbol}/"
    
    params = {
        'step': timeframe,
        'limit': 1000
    }
    
    if start_date:
        start_ts = int(datetime.strptime(start_date, '%Y-%m-%d').timestamp())
        params['start'] = start_ts
    
    for attempt in range(MAX_RETRIES):
        try:
            r = requests.get(url, params=params, timeout=TIMEOUT_BITSTAMP)
            data = r.json()
            
            if data and 'data' in data and 'ohlc' in data['data']:
                candles = data['data']['ohlc']
                
                df = pd.DataFrame(candles)
                df['timestamp'] = pd.to_datetime(df['timestamp'].astype(int), unit='s')
                df['open'] = df['open'].astype(float)
                df['high'] = df['high'].astype(float)
                df['low'] = df['low'].astype(float)
                df['close'] = df['close'].astype(float)
                df['volume'] = df['volume'].astype(float)
                df = df[['timestamp', 'open', 'high', 'low', 'close', 'volume']]
                df = df.sort_values('timestamp').reset_index(drop=True)
                return df
        except Exception as e:
            if attempt < MAX_RETRIES - 1:
                time.sleep(RETRY_DELAY * (attempt + 1))
            else:
                print(f"  Bitstamp error: {e}")
    
    return None


# ============================================================================
# DATA VALIDATION
# ============================================================================

def validate_data(df: pd.DataFrame, symbol: str) -> Tuple[pd.DataFrame, List[str]]:
    """
    Validate and clean data
    
    Returns:
        (cleaned_df, warnings)
    """
    warnings = []
    
    if df is None or len(df) == 0:
        return df, ["Empty dataset"]
    
    # Check for duplicates
    dups = df.duplicated(subset=['timestamp']).sum()
    if dups > 0:
        warnings.append(f"Removed {dups} duplicate timestamps")
        df = df.drop_duplicates(subset=['timestamp'], keep='first')
    
    # Check for gaps
    df = df.sort_values('timestamp').reset_index(drop=True)
    time_diffs = df['timestamp'].diff()
    median_diff = time_diffs.median()
    large_gaps = (time_diffs > median_diff * 2).sum()
    if large_gaps > 0:
        warnings.append(f"Found {large_gaps} time gaps (>2x median)")
    
    # Check for price outliers
    df['price_change_pct'] = df['close'].pct_change() * 100
    outliers = (df['price_change_pct'].abs() > MAX_PRICE_CHANGE_PCT).sum()
    if outliers > 0:
        warnings.append(f"Found {outliers} price outliers (>{MAX_PRICE_CHANGE_PCT}% change)")
    
    # Check for zero/negative prices
    invalid_prices = ((df['open'] <= 0) | (df['high'] <= 0) | 
                     (df['low'] <= 0) | (df['close'] <= 0)).sum()
    if invalid_prices > 0:
        warnings.append(f"Found {invalid_prices} invalid prices (<=0)")
        df = df[(df['open'] > 0) & (df['high'] > 0) & 
                (df['low'] > 0) & (df['close'] > 0)]
    
    # Check for low volume
    low_vol = (df['volume'] < MIN_VOLUME).sum()
    if low_vol > 0:
        warnings.append(f"Found {low_vol} low volume candles (<{MIN_VOLUME})")
    
    return df, warnings


# ============================================================================
# UNIFIED FETCHER (with auto-fallback)
# ============================================================================

def fetch_ohlcv(symbol: str, timeframe: str = '1d',
               start_date: Optional[str] = None,
               end_date: Optional[str] = None,
               use_cache: bool = True,
               cache_max_age_hours: int = 24) -> Optional[pd.DataFrame]:
    """
    Unified OHLCV fetcher com auto-fallback
    
    Strategy:
    1. Try cache (if enabled)
    2. Try CoinEx (recent data, nossa exchange)
    3. Try Binance (historical data, gratuito)
    4. Try Bitstamp (BTC only, desde 2011)
    5. Merge sources if needed (enriquecimento)
    
    Args:
        symbol: Market symbol (e.g., 'BTCUSDT')
        timeframe: Timeframe ('1d', '4h', '1h')
        start_date: Start date 'YYYY-MM-DD' (optional)
        end_date: End date 'YYYY-MM-DD' (optional)
        use_cache: Use cached data if available
        cache_max_age_hours: Max cache age in hours
    
    Returns:
        DataFrame with OHLCV data or None
    """
    print(f"\n{'='*60}")
    print(f"Fetching {symbol} {timeframe}")
    if start_date:
        print(f"Period: {start_date} to {end_date or 'now'}")
    print(f"{'='*60}")
    
    # Try cache first
    if use_cache:
        print("\n1. Trying cache...")
        df_cache = load_from_cache('unified', symbol, timeframe, cache_max_age_hours)
        if df_cache is not None:
            # Filter by date range if specified
            if start_date:
                start_dt = pd.to_datetime(start_date)
                df_cache = df_cache[df_cache['timestamp'] >= start_dt]
            if end_date:
                end_dt = pd.to_datetime(end_date)
                df_cache = df_cache[df_cache['timestamp'] <= end_dt]
            
            if len(df_cache) > 0:
                df_cache, warnings = validate_data(df_cache, symbol)
                if warnings:
                    print(f"  ⚠️  Warnings: {', '.join(warnings)}")
                return df_cache
    
    # Try CoinEx (recent data)
    print("\n2. Trying CoinEx...")
    df_coinex = fetch_coinex(symbol, timeframe)
    
    # Try Binance (historical data)
    print("\n3. Trying Binance...")
    df_binance = fetch_binance(symbol, timeframe, start_date, end_date)
    
    # Try Bitstamp (BTC only, muito antigo)
    df_bitstamp = None
    if symbol.upper().startswith('BTC') and timeframe == '1d':
        print("\n4. Trying Bitstamp (BTC historical)...")
        bitstamp_symbol = 'btcusd'
        df_bitstamp = fetch_bitstamp(bitstamp_symbol, '86400', start_date)
    
    # Merge sources (enriquecimento)
    dfs = [df for df in [df_bitstamp, df_binance, df_coinex] if df is not None]
    
    if not dfs:
        print("\n❌ All sources failed")
        return None
    
    print(f"\n5. Merging {len(dfs)} sources...")
    df_merged = pd.concat(dfs, ignore_index=True)
    df_merged = df_merged.drop_duplicates(subset=['timestamp'], keep='last')
    df_merged = df_merged.sort_values('timestamp').reset_index(drop=True)
    
    # Filter by date range
    if start_date:
        start_dt = pd.to_datetime(start_date)
        df_merged = df_merged[df_merged['timestamp'] >= start_dt]
    if end_date:
        end_dt = pd.to_datetime(end_date)
        df_merged = df_merged[df_merged['timestamp'] <= end_dt]
    
    # Validate
    df_merged, warnings = validate_data(df_merged, symbol)
    
    print(f"\n✅ Fetched {len(df_merged)} candles")
    print(f"   Date range: {df_merged['timestamp'].min()} to {df_merged['timestamp'].max()}")
    print(f"   Price range: ${df_merged['close'].min():.0f} to ${df_merged['close'].max():.0f}")
    
    if warnings:
        print(f"   ⚠️  Warnings: {', '.join(warnings)}")
    
    # Cache result
    if use_cache and len(df_merged) > 0:
        save_to_cache(df_merged, 'unified', symbol, timeframe)
    
    return df_merged


# ============================================================================
# CONVENIENCE FUNCTIONS
# ============================================================================

def clear_cache(symbol: Optional[str] = None):
    """Clear cache for symbol or all"""
    if symbol:
        for f in CACHE_DIR.glob(f"*{symbol}*.json"):
            f.unlink()
            print(f"Deleted {f.name}")
    else:
        for f in CACHE_DIR.glob("*.json"):
            f.unlink()
        print(f"Cleared all cache ({CACHE_DIR})")


def get_cache_info():
    """Get cache statistics"""
    files = list(CACHE_DIR.glob("*.json"))
    total_size = sum(f.stat().st_size for f in files)
    
    print(f"\nCache info:")
    print(f"  Location: {CACHE_DIR}")
    print(f"  Files: {len(files)}")
    print(f"  Total size: {total_size / 1024 / 1024:.2f} MB")
    
    if files:
        print(f"\n  Recent files:")
        for f in sorted(files, key=lambda x: x.stat().st_mtime, reverse=True)[:5]:
            age_hours = (time.time() - f.stat().st_mtime) / 3600
            size_kb = f.stat().st_size / 1024
            print(f"    {f.name} ({size_kb:.1f} KB, {age_hours:.1f}h old)")


# ============================================================================
# CLI
# ============================================================================

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Fetch OHLCV data")
    parser.add_argument("symbol", help="Market symbol (e.g., BTCUSDT)")
    parser.add_argument("--timeframe", default="1d", help="Timeframe (default: 1d)")
    parser.add_argument("--start", help="Start date YYYY-MM-DD")
    parser.add_argument("--end", help="End date YYYY-MM-DD")
    parser.add_argument("--no-cache", action="store_true", help="Disable cache")
    parser.add_argument("--clear-cache", action="store_true", help="Clear cache")
    parser.add_argument("--cache-info", action="store_true", help="Show cache info")
    
    args = parser.parse_args()
    
    if args.clear_cache:
        clear_cache(args.symbol if args.symbol != "all" else None)
    elif args.cache_info:
        get_cache_info()
    else:
        df = fetch_ohlcv(
            args.symbol,
            args.timeframe,
            args.start,
            args.end,
            use_cache=not args.no_cache
        )
        
        if df is not None:
            print(f"\n{df.head()}")
            print(f"\n{df.tail()}")
