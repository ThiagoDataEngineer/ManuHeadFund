"""
test_trendline_filter.py -- Python mirror dos tests Pester lib_trendline_filter.

Garante paridade com lib_trendline_filter.ps1: mesma formula, mesmo threshold.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from trendline_filter import get_trendline_score, is_trendline_aplus  # noqa: E402


def _linear_series(start: float, slope: float, n: int):
    closes = [start + slope * i for i in range(n)]
    highs = [c * 1.02 for c in closes]
    lows = [c * 0.98 for c in closes]
    return closes, highs, lows


class TestStructure:
    def test_returns_dict_with_keys(self):
        c, h, l = _linear_series(100, 0.5, 30)
        r = get_trendline_score(c, h, l)
        assert "score" in r
        assert "touches" in r
        assert "slope_deg" in r
        assert "valid" in r

    def test_score_in_range(self):
        c, h, l = _linear_series(100, 0.5, 30)
        r = get_trendline_score(c, h, l)
        assert 0 <= r["score"] <= 100


class TestFlatLine:
    def test_flat_returns_slope_near_zero(self):
        c, h, l = _linear_series(100, 0, 30)
        r = get_trendline_score(c, h, l)
        assert abs(r["slope_deg"]) < 1

    def test_flat_not_aplus(self):
        c, h, l = _linear_series(100, 0, 30)
        r = get_trendline_score(c, h, l)
        assert r["valid"] is False


class TestSlope:
    def test_moderate_positive(self):
        c, h, l = _linear_series(100, 0.5, 30)
        r = get_trendline_score(c, h, l)
        assert r["slope_deg"] > 0

    def test_vertical_pump_not_aplus(self):
        c, h, l = _linear_series(100, 5, 30)
        r = get_trendline_score(c, h, l)
        assert r["valid"] is False


class TestInsufficientHistory:
    def test_below_min_returns_invalid(self):
        c, h, l = _linear_series(100, 0.5, 10)
        r = get_trendline_score(c, h, l)
        assert r["valid"] is False
        assert r["score"] == 0


class TestAplusGate:
    def test_slope_05_passes_aplus(self):
        c, h, l = _linear_series(100, 0.5, 30)
        assert is_trendline_aplus(c, h, l) is True

    def test_slope_zero_fails(self):
        c, h, l = _linear_series(100, 0, 30)
        assert is_trendline_aplus(c, h, l) is False

    def test_slope_extreme_fails(self):
        c, h, l = _linear_series(100, 10, 30)
        assert is_trendline_aplus(c, h, l) is False
