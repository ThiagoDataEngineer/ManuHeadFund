"""test_correlation_matrix.py -- logic puro Pearson + build_matrix."""
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from correlation_matrix import (  # noqa: E402
    pearson,
    daily_returns,
    build_matrix,
)


class TestPearson:
    def test_perfect_positive(self):
        a = [1, 2, 3, 4, 5]
        b = [2, 4, 6, 8, 10]
        assert abs(pearson(a, b) - 1.0) < 1e-9

    def test_perfect_negative(self):
        a = [1, 2, 3, 4, 5]
        b = [5, 4, 3, 2, 1]
        assert abs(pearson(a, b) - (-1.0)) < 1e-9

    def test_zero_correlation(self):
        a = [1, 2, 3, 4, 5]
        b = [3, 1, 4, 1, 5]
        c = pearson(a, b)
        assert c is not None
        assert abs(c) < 0.5

    def test_insufficient_returns_none(self):
        assert pearson([1, 2], [3, 4]) is None

    def test_zero_variance_returns_none(self):
        assert pearson([1, 1, 1, 1, 1], [2, 3, 4, 5, 6]) is None


class TestDailyReturns:
    def test_window_5(self):
        closes = [100, 110, 99, 105, 100, 95]  # 6 closes -> 5 returns
        r = daily_returns(closes, 5)
        assert len(r) == 5
        assert abs(r[0] - 0.10) < 1e-9

    def test_insufficient_history(self):
        assert daily_returns([100, 110], 5) == []


class TestBuildMatrix:
    def test_two_markets_perfect_correlation(self):
        with tempfile.TemporaryDirectory() as td:
            tdp = Path(td)
            closes_a = [100, 110, 99, 105, 100, 95, 90, 92]
            closes_b = [200, 220, 198, 210, 200, 190, 180, 184]
            (tdp / "AAA_1day.json").write_text(
                json.dumps([{"close": c} for c in closes_a]), encoding="utf-8")
            (tdp / "BBB_1day.json").write_text(
                json.dumps([{"close": c} for c in closes_b]), encoding="utf-8")
            r = build_matrix(["AAA", "BBB"], window=5, candles_dir=tdp)
            assert "AAA" in r["matrix"]
            # AAA e BBB sao multiplos linear: corr ~= 1
            assert abs(r["matrix"]["AAA"]["BBB"] - 1.0) < 0.01

    def test_skipped_market_reported(self):
        with tempfile.TemporaryDirectory() as td:
            tdp = Path(td)
            (tdp / "AAA_1day.json").write_text(
                json.dumps([{"close": c} for c in [100, 110, 105, 102, 98, 95]]), encoding="utf-8")
            r = build_matrix(["AAA", "MISSING"], window=5, candles_dir=tdp)
            assert "MISSING" in r["skipped"]
            assert "AAA" in r["markets"]
