"""
trendline_filter.py -- Python mirror de agents/lib_trendline_filter.ps1.

Mantem paridade exata: mesma formula, mesmos thresholds.
Ver doc canonica: docs/REFINO_REGIMES_2026_05_19.md
"""
from __future__ import annotations

import math
from typing import Dict, List, Tuple


MIN_HISTORY = 20
SLOPE_DEG_MIN = 20.0
SLOPE_DEG_MAX = 35.0
TOUCH_TOLERANCE_PCT = 1.5
MIN_TOUCHES = 3


def _linear_regression(y: List[float]) -> Tuple[float, float]:
    n = len(y)
    if n < 2:
        return 0.0, (y[0] if n == 1 else 0.0)
    sum_x = sum_y = sum_xy = sum_x2 = 0.0
    for i, yi in enumerate(y):
        sum_x += i
        sum_y += yi
        sum_xy += i * yi
        sum_x2 += i * i
    denom = (n * sum_x2) - (sum_x * sum_x)
    if denom == 0:
        return 0.0, sum_y / n
    slope = ((n * sum_xy) - (sum_x * sum_y)) / denom
    intercept = (sum_y - slope * sum_x) / n
    return slope, intercept


def _count_touches(lows: List[float], slope: float, intercept: float,
                   tolerance_pct: float) -> int:
    touches = 0
    for i, lo in enumerate(lows):
        line = intercept + slope * i
        if line <= 0:
            continue
        diff_pct = abs(lo - line) / line * 100
        if diff_pct <= tolerance_pct:
            touches += 1
    return touches


def get_trendline_score(closes: List[float], highs: List[float],
                        lows: List[float]) -> Dict:
    n = len(closes)
    if n < MIN_HISTORY:
        return {"score": 0, "touches": 0, "slope_deg": 0.0,
                "valid": False, "reason": "insufficient_history"}

    slope, intercept = _linear_regression(lows)
    mean_price = sum(closes) / n
    if mean_price <= 0:
        return {"score": 0, "touches": 0, "slope_deg": 0.0,
                "valid": False, "reason": "invalid_price"}

    slope_pct = (slope / mean_price) * 100
    slope_deg = math.degrees(math.atan(slope_pct))
    touches = _count_touches(lows, slope, intercept, TOUCH_TOLERANCE_PCT)

    slope_ok = SLOPE_DEG_MIN <= slope_deg <= SLOPE_DEG_MAX
    touches_ok = touches >= MIN_TOUCHES
    valid = slope_ok and touches_ok

    slope_score = 0
    if slope_ok:
        center = (SLOPE_DEG_MIN + SLOPE_DEG_MAX) / 2
        dist = abs(slope_deg - center)
        half = (SLOPE_DEG_MAX - SLOPE_DEG_MIN) / 2
        slope_score = int(60 * (1 - dist / half))
    touch_score = min(40, touches * 10)
    score = slope_score + touch_score

    if valid:
        reason = "aplus"
    elif not slope_ok:
        reason = "slope_out_of_range"
    else:
        reason = "insufficient_touches"

    return {
        "score": score,
        "touches": touches,
        "slope_deg": round(slope_deg, 2),
        "slope_pct": round(slope_pct, 4),
        "valid": valid,
        "reason": reason,
    }


def is_trendline_aplus(closes: List[float], highs: List[float],
                       lows: List[float]) -> bool:
    return bool(get_trendline_score(closes, highs, lows)["valid"])
