#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Test SHORT signal detection end-to-end with RSI fix"""

import numpy as np
import sys
from pathlib import Path

# Add parent to path
sys.path.insert(0, str(Path(__file__).parent))

# Import FIXED calculate_rsi
from test_rsi_fix import calculate_rsi

def detect_short_signal_fixed(highs, lows, closes, volumes, climax_mult=2.5, rsi_min=70, lookback=20):
    """Detect SHORT buying climax signal - WITH FIXED RSI"""
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
    
    # RSI overbought (FIXED: use corrected calculate_rsi)
    rsi_array = calculate_rsi(closes, period=14)
    rsi_val = rsi_array[-1]
    
    print(f"  DEBUG: RSI calculation")
    print(f"    Closes last 5: {closes[-5:]}")
    print(f"    RSI last 5: {rsi_array[-5:]}")
    print(f"    RSI final: {rsi_val:.1f}")
    print(f"    RSI threshold: {rsi_min}")
    print(f"    RSI check: {rsi_val} > {rsi_min} = {rsi_val > rsi_min}")
    
    if rsi_val <= rsi_min:
        return False, vol_ratio, rejection, rsi_val
    
    return True, vol_ratio, rejection, rsi_val


# Test 1: Synthetic buying climax (should detect)
print("="*60)
print("TEST 1: Synthetic Buying Climax")
print("="*60)

# Create uptrend with buying climax at end
closes = np.array([100 + i*2 for i in range(30)])  # Strong uptrend
highs = closes + 2
lows = closes - 2
volumes = np.array([1000.0] * 29 + [3000.0])  # Vol spike at end

# Make last candle a rejection
highs[-1] = closes[-1] + 5  # New high
closes[-1] = closes[-1] - 2  # Close below (rejection)

print(f"Setup:")
print(f"  Closes: {closes[:5]}...{closes[-5:]}")
print(f"  Last high: {highs[-1]:.1f}, close: {closes[-1]:.1f}, low: {lows[-1]:.1f}")
print(f"  Volumes: {volumes[-5:]}")

detected, vol_ratio, rejection, rsi = detect_short_signal_fixed(
    highs, lows, closes, volumes,
    climax_mult=2.5, rsi_min=70
)

print(f"\nResult:")
print(f"  Detected: {detected}")
print(f"  Vol ratio: {vol_ratio:.2f}x")
print(f"  Rejection: {rejection:.2%}")
print(f"  RSI: {rsi:.1f}")

if detected:
    print(f"✅ PASS - Signal detected correctly")
else:
    print(f"❌ FAIL - Signal should have been detected")
    print(f"   Reason: RSI={rsi:.1f} vs threshold={70}")


# Test 2: No RSI overbought (should NOT detect)
print("\n" + "="*60)
print("TEST 2: Vol spike but RSI not overbought")
print("="*60)

# Sideways with vol spike (RSI ~50)
closes2 = np.array([100 + (i % 3) for i in range(30)])
highs2 = closes2 + 2
lows2 = closes2 - 2
volumes2 = np.array([1000.0] * 29 + [3000.0])

# Make last candle look like climax
highs2[-1] = closes2[-1] + 5
closes2[-1] = closes2[-1] - 2

print(f"Setup:")
print(f"  Closes: {closes2[:5]}...{closes2[-5:]}")
print(f"  Volumes: {volumes2[-5:]}")

detected2, vol_ratio2, rejection2, rsi2 = detect_short_signal_fixed(
    highs2, lows2, closes2, volumes2,
    climax_mult=2.5, rsi_min=70
)

print(f"\nResult:")
print(f"  Detected: {detected2}")
print(f"  RSI: {rsi2:.1f}")

if not detected2:
    print(f"✅ PASS - Correctly rejected (RSI not overbought)")
else:
    print(f"❌ FAIL - Should NOT detect (RSI < 70)")


# Summary
print("\n" + "="*60)
print("SUMMARY")
print("="*60)

if detected and not detected2:
    print("✅ ALL TESTS PASSED")
    print("   SHORT signal detection with RSI is working correctly")
else:
    print("❌ TESTS FAILED")
    if not detected:
        print("   Test 1 failed: Should detect buying climax with RSI > 70")
    if detected2:
        print("   Test 2 failed: Should NOT detect when RSI < 70")
