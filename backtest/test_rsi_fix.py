#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Test RSI calculation fix"""

import numpy as np

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


# Test 1: Uptrend (should have high RSI)
print("="*60)
print("TEST 1: Uptrend (expect RSI > 70)")
print("="*60)
uptrend = np.array([100 + i*2 for i in range(30)])
rsi_up = calculate_rsi(uptrend)
print(f"Prices: {uptrend[:5]}...{uptrend[-5:]}")
print(f"RSI last 5: {rsi_up[-5:]}")
print(f"Last RSI: {rsi_up[-1]:.1f}")
print(f"✅ PASS" if rsi_up[-1] > 70 else f"❌ FAIL")

# Test 2: Downtrend (should have low RSI)
print("\n" + "="*60)
print("TEST 2: Downtrend (expect RSI < 30)")
print("="*60)
downtrend = np.array([100 - i*2 for i in range(30)])
rsi_down = calculate_rsi(downtrend)
print(f"Prices: {downtrend[:5]}...{downtrend[-5:]}")
print(f"RSI last 5: {rsi_down[-5:]}")
print(f"Last RSI: {rsi_down[-1]:.1f}")
print(f"✅ PASS" if rsi_down[-1] < 30 else f"❌ FAIL")

# Test 3: Sideways (should have RSI ~50)
print("\n" + "="*60)
print("TEST 3: Sideways (expect RSI ~50)")
print("="*60)
sideways = np.array([100 + (i % 2) for i in range(30)])
rsi_side = calculate_rsi(sideways)
print(f"Prices: {sideways[:10]}...{sideways[-10:]}")
print(f"RSI last 5: {rsi_side[-5:]}")
print(f"Last RSI: {rsi_side[-1]:.1f}")
print(f"✅ PASS" if 40 < rsi_side[-1] < 60 else f"❌ FAIL")

# Test 4: Real BTC-like data
print("\n" + "="*60)
print("TEST 4: Real BTC-like volatility")
print("="*60)
btc_like = np.array([
    100, 102, 101, 105, 103, 108, 106, 110, 108, 112,
    115, 113, 118, 116, 120, 118, 122, 120, 125, 123,
    128, 126, 130, 128, 132, 130, 135, 133, 138, 136
])
rsi_btc = calculate_rsi(btc_like)
print(f"Prices: {btc_like[:5]}...{btc_like[-5:]}")
print(f"RSI last 5: {rsi_btc[-5:]}")
print(f"Last RSI: {rsi_btc[-1]:.1f}")
print(f"✅ PASS (RSI in valid range)" if 0 < rsi_btc[-1] < 100 else f"❌ FAIL")

# Summary
print("\n" + "="*60)
print("SUMMARY")
print("="*60)
all_pass = (
    rsi_up[-1] > 70 and
    rsi_down[-1] < 30 and
    40 < rsi_side[-1] < 60 and
    0 < rsi_btc[-1] < 100
)
if all_pass:
    print("✅ ALL TESTS PASSED - RSI calculation is CORRECT")
else:
    print("❌ SOME TESTS FAILED - RSI calculation still has issues")
