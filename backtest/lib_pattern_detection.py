#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
lib_pattern_detection.py -- Biblioteca compartilhada de detecção de patterns

FILOSOFIA: DRY (Don't Repeat Yourself)
- Centralizar lógica de detecção de patterns
- Evitar duplicação de código
- Facilitar manutenção e testes

PATTERNS IMPLEMENTADOS:
1. Vol Climax (LONG) - selling climax com rejection
2. Tori Proximity (LONG) - trendline bounce
3. Buying Climax (SHORT) - buying climax com rejection

VALIDATED: 2026-05-23 TDD
"""

import numpy as np


# ============================================================================
# VOL CLIMAX (LONG) - Selling Climax
# ============================================================================

def detect_vol_climax(highs, lows, closes, volumes,
                     climax_mult=2.5,
                     rejection_min=0.5,
                     lookback=20):
    """
    Detect volume climax (LONG) - selling climax pattern
    
    VALIDATED: 2026-05-23 TDD
    - rejection_min=0.3: -3.12% edge ❌
    - rejection_min=0.5: +3.63% edge ✅
    
    Pattern (3-AND gate):
    1. Volume spike >= climax_mult × average
    2. New low (quebra mínimo recente)
    3. Close rejection >= rejection_min (wick inferior)
    
    Args:
        highs: Array of high prices
        lows: Array of low prices
        closes: Array of close prices
        volumes: Array of volumes
        climax_mult: Volume multiplier threshold (default 2.5)
        rejection_min: Minimum rejection ratio (default 0.5 = 50%)
        lookback: Lookback period (default 20)
    
    Returns:
        (detected, vol_ratio, rejection, details)
    """
    if len(closes) < lookback + 1:
        return False, 0, 0, {}
    
    # 1. Volume spike
    recent_vols = volumes[-lookback-1:-1]
    avg_vol = np.mean(recent_vols)
    current_vol = volumes[-1]
    vol_ratio = current_vol / avg_vol if avg_vol > 0 else 0
    
    vol_spike = vol_ratio >= climax_mult
    
    # 2. New low (selling climax)
    recent_lows = lows[-lookback-1:-1]
    min_low = np.min(recent_lows)
    current_low = lows[-1]
    
    new_low = current_low <= min_low
    
    # 3. Close rejection (wick inferior)
    candle_range = highs[-1] - lows[-1]
    if candle_range > 0:
        rejection = (closes[-1] - lows[-1]) / candle_range
    else:
        rejection = 0
    
    close_rejection = rejection >= rejection_min
    
    # Detection (3-AND gate)
    detected = vol_spike and new_low and close_rejection
    
    details = {
        'vol_spike': vol_spike,
        'vol_ratio': float(vol_ratio),
        'new_low': new_low,
        'close_rejection': close_rejection,
        'rejection': float(rejection),
        'climax_mult': climax_mult,
        'rejection_min': rejection_min
    }
    
    return detected, float(vol_ratio), float(rejection), details


# ============================================================================
# TORI PROXIMITY (LONG) - Trendline Bounce
# ============================================================================

def detect_tori_proximity(highs, lows, closes, volumes,
                         slope_min=5.0,
                         slope_max=35.0,
                         proximity_min=-3.0,
                         proximity_max=5.0,
                         rsi_max=40.0,
                         vol_ratio_max=0.7,
                         min_touches=3,
                         lookback=20):
    """
    Detect Tori proximity pattern (LONG) - trendline bounce
    
    Tori = Ascending support trendline
    Proximity = Price approaching the trendline
    
    Pattern (5-AND gate):
    1. Valid trendline (slope 5-35 degrees, >=3 touches)
    2. Proximity -3% to +5% (price near trendline)
    3. RSI < 40 (oversold)
    4. Volume drying (recent < 70% of prior)
    5. All conditions met
    
    Args:
        highs: Array of high prices
        lows: Array of low prices
        closes: Array of close prices
        volumes: Array of volumes
        slope_min: Minimum slope in degrees (default 5.0)
        slope_max: Maximum slope in degrees (default 35.0)
        proximity_min: Minimum proximity % (default -3.0)
        proximity_max: Maximum proximity % (default 5.0)
        rsi_max: Maximum RSI (default 40.0)
        vol_ratio_max: Maximum volume ratio (default 0.7)
        min_touches: Minimum touches (default 3)
        lookback: Lookback period (default 20)
    
    Returns:
        (detected, proximity_pct, slope_deg, rsi, vol_drying)
    """
    if len(closes) < lookback + 1:
        return False, 0, 0, 0, False
    
    # 1. Linear regression on lows (action line)
    recent_lows = lows[-lookback:]
    x = np.arange(len(recent_lows))
    
    # Fit line: y = slope * x + intercept
    coeffs = np.polyfit(x, recent_lows, 1)
    slope = coeffs[0]
    intercept = coeffs[1]
    
    # Convert slope to degrees
    slope_deg = np.degrees(np.arctan(slope / recent_lows[-1] * 100))
    
    # Check slope range (5-35 degrees)
    if slope_deg < slope_min or slope_deg > slope_max:
        return False, 0, slope_deg, 0, False
    
    # 2. Count touches (lows within 1.5% of line)
    touches = 0
    for i, low in enumerate(recent_lows):
        line_val = intercept + slope * i
        if line_val > 0:
            diff_pct = abs(low - line_val) / line_val * 100
            if diff_pct <= 1.5:
                touches += 1
    
    if touches < min_touches:
        return False, 0, slope_deg, 0, False
    
    # 3. Proximity (current price vs action line)
    current_price = closes[-1]
    line_current = intercept + slope * (len(recent_lows) - 1)
    
    if line_current > 0:
        proximity_pct = (current_price - line_current) / line_current * 100
    else:
        proximity_pct = 0
    
    if proximity_pct < proximity_min or proximity_pct > proximity_max:
        return False, proximity_pct, slope_deg, 0, False
    
    # 4. RSI oversold
    from lib_backtest_rsi_fixed import calculate_rsi
    rsi_val = calculate_rsi(closes)
    if isinstance(rsi_val, (list, np.ndarray)):
        rsi_val = rsi_val[-1] if len(rsi_val) > 0 else 50.0
    
    if rsi_val > rsi_max:
        return False, proximity_pct, slope_deg, rsi_val, False
    
    # 5. Volume drying (recent < 70% of prior)
    if len(volumes) >= 10:
        recent_vol = np.mean(volumes[-3:])
        prior_vol = np.mean(volumes[-10:-3])
        vol_drying = (recent_vol / prior_vol) < vol_ratio_max if prior_vol > 0 else False
    else:
        vol_drying = False
    
    # All conditions met
    detected = vol_drying
    
    return detected, float(proximity_pct), float(slope_deg), float(rsi_val), vol_drying


# ============================================================================
# BUYING CLIMAX (SHORT) - Buying Climax
# ============================================================================

def detect_buying_climax(highs, lows, closes, volumes,
                        climax_mult=2.5,
                        rsi_min=70,
                        rejection_min=0.3,
                        lookback=20):
    """
    Detect buying climax (SHORT) - buying climax pattern
    
    VALIDATED: 2026-05-23 TDD
    - Edge: -14.77% (NEGATIVE) ❌
    - Conclusion: Pattern does NOT work
    
    Pattern (4-AND gate):
    1. Volume spike >= climax_mult × average
    2. New high (quebra máximo recente)
    3. Close rejection >= rejection_min (wick superior)
    4. RSI > rsi_min (overbought)
    
    Args:
        highs: Array of high prices
        lows: Array of low prices
        closes: Array of close prices
        volumes: Array of volumes
        climax_mult: Volume multiplier threshold (default 2.5)
        rsi_min: Minimum RSI (default 70)
        rejection_min: Minimum rejection ratio (default 0.3)
        lookback: Lookback period (default 20)
    
    Returns:
        (detected, vol_ratio, rejection, rsi)
    """
    if len(closes) < lookback + 1:
        return False, 0, 0, 0
    
    # 1. Volume spike
    recent_vols = volumes[-lookback-1:-1]
    avg_vol = np.mean(recent_vols)
    current_vol = volumes[-1]
    vol_ratio = current_vol / avg_vol if avg_vol > 0 else 0
    
    vol_spike = vol_ratio >= climax_mult
    
    # 2. New high (buying climax)
    recent_highs = highs[-lookback-1:-1]
    max_high = np.max(recent_highs)
    current_high = highs[-1]
    
    new_high = current_high >= max_high
    
    # 3. Close rejection (wick superior)
    candle_range = highs[-1] - lows[-1]
    if candle_range > 0:
        rejection = (highs[-1] - closes[-1]) / candle_range
    else:
        rejection = 0
    
    close_rejection = rejection >= rejection_min
    
    # 4. RSI overbought
    from lib_backtest_rsi_fixed import calculate_rsi
    rsi_val = calculate_rsi(closes)
    if isinstance(rsi_val, (list, np.ndarray)):
        rsi_val = rsi_val[-1] if len(rsi_val) > 0 else 50.0
    
    rsi_overbought = rsi_val > rsi_min
    
    # Detection (4-AND gate)
    detected = vol_spike and new_high and close_rejection and rsi_overbought
    
    return detected, float(vol_ratio), float(rejection), float(rsi_val)


# ============================================================================
# CONVENIENCE FUNCTIONS
# ============================================================================

def detect_all_patterns(highs, lows, closes, volumes):
    """
    Detect all patterns at once
    
    Returns:
        Dict with results for each pattern
    """
    results = {}
    
    # Vol Climax (LONG)
    vc_detected, vc_vol_ratio, vc_rejection, vc_details = detect_vol_climax(
        highs, lows, closes, volumes
    )
    results['vol_climax'] = {
        'detected': vc_detected,
        'vol_ratio': vc_vol_ratio,
        'rejection': vc_rejection,
        'details': vc_details
    }
    
    # Tori Proximity (LONG)
    tori_detected, tori_proximity, tori_slope, tori_rsi, tori_vol_dry = detect_tori_proximity(
        highs, lows, closes, volumes
    )
    results['tori_proximity'] = {
        'detected': tori_detected,
        'proximity': tori_proximity,
        'slope': tori_slope,
        'rsi': tori_rsi,
        'vol_drying': tori_vol_dry
    }
    
    # Buying Climax (SHORT)
    bc_detected, bc_vol_ratio, bc_rejection, bc_rsi = detect_buying_climax(
        highs, lows, closes, volumes
    )
    results['buying_climax'] = {
        'detected': bc_detected,
        'vol_ratio': bc_vol_ratio,
        'rejection': bc_rejection,
        'rsi': bc_rsi
    }
    
    return results
