"""
test_benchmark_buy_hold.py -- TDD para benchmark Sistema Baseline V2 vs HODL.
"""
from __future__ import annotations

import json
import os
import sys

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from benchmark_buy_hold import (  # noqa: E402
    BASELINE_V2_RUNS,
    alpha_pct,
    annualized_return_pct,
    build_comparison,
    build_summary,
    classify_verdict,
    hodl_max_dd_pct,
    hodl_return_pct,
    run_benchmark,
    system_return_to_pct,
)


# ── HODL math ────────────────────────────────────────────────────────────────

def test_hodl_return_calculation_basic():
    # 70000 -> 95000 = +35.71%
    r = hodl_return_pct(70000, 95000)
    assert abs(r - 35.7142857) < 1e-6


def test_hodl_max_dd_during_period():
    # Sobe pra 100, cai pra 60 (-40%), volta pra 90
    prices = [50, 80, 100, 70, 60, 90]
    dd = hodl_max_dd_pct(prices)
    assert dd == pytest.approx(-40.0, abs=1e-6)


def test_hodl_max_dd_monotonic_up_is_zero():
    prices = [10, 20, 30, 40]
    assert hodl_max_dd_pct(prices) == 0.0


# ── Alpha ────────────────────────────────────────────────────────────────────

def test_alpha_calculation_positive_case():
    # Sistema 80%, HODL 30% -> alpha = +50pp
    assert alpha_pct(80.0, 30.0) == 50.0


def test_alpha_calculation_negative_case():
    # Sistema 20%, HODL 60% -> alpha = -40pp
    assert alpha_pct(20.0, 60.0) == -40.0


# ── Verdict matrix ───────────────────────────────────────────────────────────

def test_verdict_outperform_lower_risk_returns_correct():
    # sistema retorna mais (100>30) e DD menor (-5 vs -25)
    assert classify_verdict(100.0, 30.0, -5.0, -25.0) == "OUTPERFORM_LOWER_RISK"


def test_verdict_underperform_higher_risk_returns_correct():
    # sistema retorna menos (10<30) e DD maior (-40 vs -25)
    assert classify_verdict(10.0, 30.0, -40.0, -25.0) == "UNDERPERFORM_HIGHER_RISK"


def test_verdict_outperform_higher_risk():
    assert classify_verdict(100.0, 30.0, -50.0, -25.0) == "OUTPERFORM_HIGHER_RISK"


def test_verdict_underperform_lower_risk():
    assert classify_verdict(10.0, 30.0, -5.0, -25.0) == "UNDERPERFORM_LOWER_RISK"


# ── Edge cases ───────────────────────────────────────────────────────────────

def test_handles_empty_candles_gracefully():
    run = BASELINE_V2_RUNS[0]
    out = build_comparison(run, [])
    assert out["hodl"]["data_available"] is False
    assert out["hodl"]["return_pct"] == 0.0
    assert "verdict" in out["comparison_metrics"]


def test_annualized_return_calc():
    # 100% em 365 dias = ~100% anualizado
    val = annualized_return_pct(100.0, 365)
    assert 99.5 < val < 100.5


# ── Schema validation ────────────────────────────────────────────────────────

REQUIRED_TOP_KEYS = {"timestamp", "run_date", "status", "comparison", "summary", "go_live_criterion"}
REQUIRED_RUN_KEYS = {"run_id", "market", "period", "system", "hodl", "comparison_metrics"}
REQUIRED_SUMMARY_KEYS = {
    "all_runs_outperform_hodl", "all_runs_lower_dd_than_hodl",
    "median_alpha_pct", "recommendation", "go_live_criterion_passed",
}


def test_json_output_schema_validates():
    # Run sintetico com closes mockados -- evita rede
    runs = BASELINE_V2_RUNS
    comparisons = []
    for r in runs:
        # Closes sinteticos: 100 -> 130 com leve dip
        prices = [100.0, 110.0, 95.0, 115.0, 130.0]
        comparisons.append(build_comparison(r, prices))
    summary, criterion = build_summary(comparisons)
    result = {
        "timestamp": "2026-05-14T00:00:00+00:00",
        "run_date": "2026-05-14",
        "status": "completed",
        "comparison": comparisons,
        "summary": summary,
        "go_live_criterion": criterion,
    }
    # Top-level schema
    assert REQUIRED_TOP_KEYS.issubset(result.keys())
    # Per-run schema
    for c in result["comparison"]:
        assert REQUIRED_RUN_KEYS.issubset(c.keys())
        assert c["comparison_metrics"]["verdict"] in {
            "OUTPERFORM_LOWER_RISK", "OUTPERFORM_HIGHER_RISK",
            "UNDERPERFORM_LOWER_RISK", "UNDERPERFORM_HIGHER_RISK",
        }
    # Summary schema
    assert REQUIRED_SUMMARY_KEYS.issubset(result["summary"].keys())
    # Serializa sem erro
    json.dumps(result)


def test_build_summary_all_outperform_lower_risk_recommends_dominate():
    fake = [
        {"comparison_metrics": {"verdict": "OUTPERFORM_LOWER_RISK", "alpha_pct": 100.0}},
        {"comparison_metrics": {"verdict": "OUTPERFORM_LOWER_RISK", "alpha_pct": 200.0}},
        {"comparison_metrics": {"verdict": "OUTPERFORM_LOWER_RISK", "alpha_pct": 150.0}},
    ]
    summary, criterion = build_summary(fake)
    assert summary["all_runs_outperform_hodl"] is True
    assert summary["all_runs_lower_dd_than_hodl"] is True
    assert summary["recommendation"] == "SISTEMA_DOMINA_HODL"
    assert summary["go_live_criterion_passed"] is True
    assert criterion["passed"] is True
    assert summary["median_alpha_pct"] == 150.0


def test_system_return_R_to_pct():
    # 136R com 1% risco/trade -> 136%
    assert system_return_to_pct(136.0, 1.0) == 136.0
    assert system_return_to_pct(136.0, 0.5) == 68.0


def test_baseline_v2_has_3_runs():
    assert len(BASELINE_V2_RUNS) == 3
    ids = [r["run_id"] for r in BASELINE_V2_RUNS]
    assert ids == ["btc_in_sample", "btc_oos_temporal", "eth_oos_pair"]
