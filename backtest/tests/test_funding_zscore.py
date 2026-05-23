"""test_funding_zscore.py -- z-score logic puro (sem hit Binance)."""
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from funding_zscore import compute_zscore, load_funding  # noqa: E402


def _make_rows(rates, base_ts=1700000000000, step_ms=28_800_000):
    """28_800_000 = 8h em ms (Binance funding interval)."""
    return [
        {"symbol": "TEST", "funding_time": base_ts + i * step_ms, "funding_rate": str(r)}
        for i, r in enumerate(rates)
    ]


class TestZScoreCompute:
    def test_empty_returns_no_data(self):
        r = compute_zscore([])
        assert r["z"] is None
        assert r["reason"] == "no_data"

    def test_insufficient_baseline_flagged(self):
        rows = _make_rows([0.0001] * 5)
        r = compute_zscore(rows, baseline_days=90)
        assert r["z"] is None
        assert r["reason"] == "insufficient_baseline"

    def test_constant_returns_z_zero(self):
        rows = _make_rows([0.0001] * 50)
        r = compute_zscore(rows)
        assert r["z"] == 0.0

    def test_spike_high_z(self):
        # 49 baixos + 1 spike no fim
        rates = [0.0001] * 49 + [0.005]
        rows = _make_rows(rates)
        r = compute_zscore(rows)
        assert r["z"] is not None
        assert r["z"] > 3.0  # spike claramente alto

    def test_negative_spike_low_z(self):
        rates = [0.0001] * 49 + [-0.003]
        rows = _make_rows(rates)
        r = compute_zscore(rows)
        assert r["z"] is not None
        assert r["z"] < -2.0


class TestLoadFunding:
    def test_missing_file_returns_empty(self):
        with tempfile.TemporaryDirectory() as td:
            assert load_funding("NOPE", Path(td)) == []

    def test_loads_and_sorts(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "BTC.jsonl"
            with p.open("w", encoding="utf-8") as f:
                f.write(json.dumps({"funding_time": 2, "funding_rate": "0.002"}) + "\n")
                f.write(json.dumps({"funding_time": 1, "funding_rate": "0.001"}) + "\n")
            rows = load_funding("BTC", Path(td))
            assert len(rows) == 2
            assert rows[0]["funding_time"] == 1
            assert rows[1]["funding_time"] == 2
