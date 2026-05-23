"""test_funding_preempt_logic.py -- valida preempt funding z-score em weekly_discovery."""
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from funding_zscore import compute_zscore  # noqa: E402


def _make_rows(rates, base_ts=1700000000000, step_ms=28_800_000):
    return [{"funding_time": base_ts + i*step_ms, "funding_rate": str(r)} for i,r in enumerate(rates)]


def _preempt_filter(candidates, history_loader):
    """Reproduz logica do bloco 3.5 do weekly_discovery (inline pra teste)."""
    survived = []
    skipped = []
    for c in candidates:
        mkt = c["market"]
        rows = history_loader(mkt)
        zr = compute_zscore(rows)
        z = zr.get("z")
        if z is not None and z >= 2.0:
            c["preempt_reason"] = f"funding_overheated_z={z:.2f}"
            skipped.append(c)
        else:
            c["funding_z"] = z
            survived.append(c)
    return survived, skipped


class TestFundingPreempt:
    def test_overheated_skipped(self):
        # 49 baixos + spike alto -> z > 2
        def loader(mkt):
            if mkt == "OVERUSDT": return _make_rows([0.0001]*49 + [0.005])
            return []
        candidates = [{"market": "OVERUSDT", "category": "EARLY_BULL"}]
        survived, skipped = _preempt_filter(candidates, loader)
        assert len(skipped) == 1
        assert "overheated" in skipped[0]["preempt_reason"]
        assert len(survived) == 0

    def test_neutral_survives(self):
        def loader(mkt):
            return _make_rows([0.0001]*50)  # constante = z=0
        candidates = [{"market": "NEUTRALUSDT", "category": "EARLY_BULL"}]
        survived, skipped = _preempt_filter(candidates, loader)
        assert len(survived) == 1
        assert survived[0]["funding_z"] == 0.0

    def test_no_history_survives(self):
        def loader(mkt): return []
        candidates = [{"market": "NEWUSDT", "category": "FRESH_CROSS"}]
        survived, skipped = _preempt_filter(candidates, loader)
        # Sem dados = z None = passa (no_baseline)
        assert len(survived) == 1
        assert survived[0]["funding_z"] is None

    def test_mixed_partition(self):
        def loader(mkt):
            if mkt == "HOT": return _make_rows([0.0001]*49 + [0.01])  # spike
            if mkt == "COLD": return _make_rows([0.0001]*49 + [-0.005])  # negative spike
            return _make_rows([0.0001]*50)  # neutral
        candidates = [
            {"market": "HOT"},
            {"market": "COLD"},
            {"market": "MIDDLE"},
        ]
        survived, skipped = _preempt_filter(candidates, loader)
        assert len(survived) == 2  # COLD (z negativo = passa long gate) + MIDDLE
        assert len(skipped) == 1
        assert skipped[0]["market"] == "HOT"

    def test_skip_preserves_original_fields(self):
        def loader(mkt): return _make_rows([0.0001]*49 + [0.005])
        candidates = [{"market": "X", "category": "EARLY_BULL", "vol": 1234.5}]
        survived, skipped = _preempt_filter(candidates, loader)
        assert skipped[0]["category"] == "EARLY_BULL"
        assert skipped[0]["vol"] == 1234.5
