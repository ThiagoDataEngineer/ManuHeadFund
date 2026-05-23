"""
test_pump_buy_gate.py -- Python mirror dos tests Pester lib_pump_buy_gate.

Garante paridade exata: mesma formula, mesmos thresholds.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from pump_buy_gate import check_pump_buy_gate, peak_7d_from_candles  # noqa: E402


class TestCanonical:
    def test_5pct_below_passes(self):
        r = check_pump_buy_gate(current_price=95, peak_7d=100)
        assert r["passes"] is True

    def test_10pct_below_passes(self):
        r = check_pump_buy_gate(current_price=90, peak_7d=100)
        assert r["passes"] is True

    def test_at_peak_blocks(self):
        r = check_pump_buy_gate(current_price=100, peak_7d=100)
        assert r["passes"] is False

    def test_2pct_below_blocks(self):
        r = check_pump_buy_gate(current_price=98, peak_7d=100)
        assert r["passes"] is False

    def test_above_peak_blocks(self):
        r = check_pump_buy_gate(current_price=105, peak_7d=100)
        assert r["passes"] is False


class TestCustomThreshold:
    def test_threshold_minus10_blocks_5pct(self):
        r = check_pump_buy_gate(current_price=95, peak_7d=100, max_dist_from_peak_pct=-10)
        assert r["passes"] is False

    def test_threshold_minus10_passes_10pct(self):
        r = check_pump_buy_gate(current_price=90, peak_7d=100, max_dist_from_peak_pct=-10)
        assert r["passes"] is True

    def test_threshold_minus3_permissive(self):
        r = check_pump_buy_gate(current_price=96.5, peak_7d=100, max_dist_from_peak_pct=-3)
        assert r["passes"] is True


class TestEdgeCases:
    def test_peak_zero(self):
        r = check_pump_buy_gate(current_price=100, peak_7d=0)
        assert r["passes"] is False
        assert "invalid" in r["reason"]

    def test_current_zero(self):
        r = check_pump_buy_gate(current_price=0, peak_7d=100)
        assert r["passes"] is False

    def test_returns_required_fields(self):
        r = check_pump_buy_gate(current_price=95, peak_7d=100)
        for field in ("passes", "dist_pct", "current_price", "peak_7d", "reason", "threshold"):
            assert field in r


class TestPeak7dFromCandles:
    def test_max_high_returned(self):
        candles = [{"high": 100}, {"high": 105}, {"high": 110}, {"high": 95}]
        assert peak_7d_from_candles(candles) == 110

    def test_empty_list(self):
        assert peak_7d_from_candles([]) == 0
