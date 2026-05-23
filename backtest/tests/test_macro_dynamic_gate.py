"""
test_macro_dynamic_gate.py -- TDD para gate macro DINAMICO (deltas, nao niveis).
"""
from __future__ import annotations

import json
import os
import sys

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from macro_dynamic_gate import (  # noqa: E402
    DXY_CHANGE_THRESHOLDS,
    REAL_RATE_THRESHOLDS,
    BTC_GOLD_CHANGE_THRESHOLDS,
    SINGLE_FEATURE_GRID,
    COMBO_2_GRID,
    DecisionResult,
    annotate_dynamic_features,
    apply_dynamic_gate,
    compute_btc_gold_ratio_change_60d,
    compute_dxy_change_30d,
    compute_real_rate_at_date,
    decide_outcome,
    exclusion_increases_in_2025,
    exp_r,
    grid_search_single,
    grid_search_combos,
)


# ── Feature computations ────────────────────────────────────────────────────

def test_compute_dxy_change_30d_positive():
    series = [("2024-01-01", 100.0), ("2024-02-01", 105.0)]
    val = compute_dxy_change_30d(series, "2024-02-01")
    assert val == pytest.approx(5.0, abs=0.1)


def test_compute_dxy_change_30d_negative():
    series = [("2024-01-01", 100.0), ("2024-02-01", 95.0)]
    val = compute_dxy_change_30d(series, "2024-02-01")
    assert val == pytest.approx(-5.0, abs=0.1)


def test_compute_real_rate_at_date():
    # FRED-style: monthly, ja em pct
    series = [("2023-01-01", 1.5), ("2023-04-01", 2.0), ("2023-07-01", 2.2)]
    assert compute_real_rate_at_date(series, "2023-05-15") == 2.0
    assert compute_real_rate_at_date(series, "2023-08-15") == 2.2


def test_compute_btc_gold_ratio_change_60d_risk_on():
    btc_series = [("2024-01-01", 40000.0), ("2024-03-02", 60000.0)]
    gold_series = [("2024-01-01", 2000.0), ("2024-03-02", 2050.0)]
    # ratio_now = 60000/2050 ~ 29.27; ratio_60d_ago = 40000/2000 = 20.0
    # delta = (29.27/20 - 1)*100 = +46%
    val = compute_btc_gold_ratio_change_60d(btc_series, gold_series, "2024-03-02")
    assert val > 30  # risk-on


def test_compute_btc_gold_ratio_change_60d_risk_off():
    btc_series = [("2024-01-01", 60000.0), ("2024-03-02", 40000.0)]
    gold_series = [("2024-01-01", 2000.0), ("2024-03-02", 2100.0)]
    val = compute_btc_gold_ratio_change_60d(btc_series, gold_series, "2024-03-02")
    assert val < -20


# ── Annotation ──────────────────────────────────────────────────────────────

def test_annotate_dynamic_features_basic():
    trades = [{"entry_ts": "2024-03-01", "result_r": 1.0, "year": 2024}]
    dxy = [("2024-01-30", 100.0), ("2024-03-01", 102.0)]
    real_rates = [("2024-01-01", 1.0), ("2024-03-01", 1.5)]
    btc = [("2023-12-31", 40000.0), ("2024-03-01", 50000.0)]
    gold = [("2023-12-31", 2000.0), ("2024-03-01", 2050.0)]
    out = annotate_dynamic_features(trades, dxy, real_rates, btc, gold)
    assert "dxy_change_30d_pct" in out[0]
    assert "real_rate_10y" in out[0]
    assert "btc_gold_change_60d_pct" in out[0]
    assert out[0]["real_rate_10y"] == pytest.approx(1.5)


# ── Gate ────────────────────────────────────────────────────────────────────

def test_apply_dynamic_gate_filters():
    trades = [
        {"dxy_change_30d_pct": -2.0, "real_rate_10y": 0.5, "btc_gold_change_60d_pct": 20.0, "result_r": 1},
        {"dxy_change_30d_pct": 5.0,  "real_rate_10y": 2.5, "btc_gold_change_60d_pct": -5.0, "result_r": -1},
        {"dxy_change_30d_pct": 0.0,  "real_rate_10y": 1.0, "btc_gold_change_60d_pct": 10.0, "result_r": 0.5},
    ]
    gate = {"dxy_change_max": 3.0, "real_rate_max": 2.0}
    kept = apply_dynamic_gate(trades, gate)
    assert len(kept) == 2  # 1st and 3rd


# ── Grid search ─────────────────────────────────────────────────────────────

def test_grid_search_single_returns_top_per_feature():
    trades = [
        {"dxy_change_30d_pct": -3.0, "real_rate_10y": 1.0, "btc_gold_change_60d_pct": 15.0, "result_r": 2.0, "year": 2018},
        {"dxy_change_30d_pct": 5.0,  "real_rate_10y": 2.5, "btc_gold_change_60d_pct": -10.0, "result_r": -1.0, "year": 2018},
        {"dxy_change_30d_pct": -1.0, "real_rate_10y": 0.5, "btc_gold_change_60d_pct": 25.0, "result_r": 1.5, "year": 2019},
    ] * 10
    result = grid_search_single(trades)
    assert "dxy_change_30d_pct" in result
    assert "real_rate_10y" in result
    assert "btc_gold_change_60d_pct" in result
    for feat, r in result.items():
        assert "best_threshold" in r
        assert "exp" in r


def test_grid_search_combos_2_features():
    trades = [
        {"dxy_change_30d_pct": -3.0, "real_rate_10y": 0.5, "btc_gold_change_60d_pct": 20.0, "result_r": 2.0, "year": 2018},
        {"dxy_change_30d_pct": 5.0,  "real_rate_10y": 2.5, "btc_gold_change_60d_pct": -10.0, "result_r": -1.0, "year": 2018},
    ] * 30
    best = grid_search_combos(trades, max_features=2)
    assert "features" in best
    assert len(best["features"]) <= 2
    assert "thresholds" in best
    assert "exp" in best


# ── Decision logic ──────────────────────────────────────────────────────────

def test_decision_pass():
    r = decide_outcome(
        exp_train_baseline=0.35,
        exp_train_filtered=0.50,
        exp_holdout_filtered=0.40,
        holdout_excluded_pct=30.0,
        excl_2025=0.40,
        excl_2023=0.20,
    )
    assert r.decision == "PASS"


def test_decision_fail_overfit():
    r = decide_outcome(
        exp_train_baseline=0.35,
        exp_train_filtered=0.60,
        exp_holdout_filtered=0.40,
        holdout_excluded_pct=30.0,
        excl_2025=0.40,
        excl_2023=0.20,
    )
    assert r.decision == "FAIL_OVERFIT"  # gap 0.20 >= 0.15


def test_decision_fail_no_improvement_train():
    r = decide_outcome(
        exp_train_baseline=0.35,
        exp_train_filtered=0.40,  # uplift +0.05 < +0.10
        exp_holdout_filtered=0.40,
        holdout_excluded_pct=30.0,
        excl_2025=0.40,
        excl_2023=0.20,
    )
    assert r.decision == "FAIL_NO_IMPROVEMENT"


def test_decision_fail_holdout_100pct():
    # Sanity: se holdout exclui 100%, FAIL
    r = decide_outcome(
        exp_train_baseline=0.35,
        exp_train_filtered=0.50,
        exp_holdout_filtered=0.0,
        holdout_excluded_pct=100.0,
        excl_2025=1.0,
        excl_2023=1.0,
    )
    assert r.decision == "FAIL_NO_IMPROVEMENT"


def test_decision_fail_2025_not_more_excluded():
    # Gate exclui MENOS em 2025 que em 2023 -> nao separa pos-tightening
    r = decide_outcome(
        exp_train_baseline=0.35,
        exp_train_filtered=0.50,
        exp_holdout_filtered=0.40,
        holdout_excluded_pct=30.0,
        excl_2025=0.10,  # exclui pouco em 2025
        excl_2023=0.50,  # exclui muito em 2023 (errado)
    )
    assert r.decision in ("FAIL_NO_IMPROVEMENT", "FAIL_OVERFIT")


def test_exclusion_increases_in_2025_true():
    assert exclusion_increases_in_2025(excl_2025=0.5, excl_2023=0.2) is True


def test_exclusion_increases_in_2025_false():
    assert exclusion_increases_in_2025(excl_2025=0.1, excl_2023=0.3) is False


# ── Param grids ─────────────────────────────────────────────────────────────

def test_param_grids_have_expected_values():
    assert -5.0 in DXY_CHANGE_THRESHOLDS or -5 in DXY_CHANGE_THRESHOLDS
    assert 6.0 in DXY_CHANGE_THRESHOLDS or 6 in DXY_CHANGE_THRESHOLDS
    assert 0.0 in REAL_RATE_THRESHOLDS
    assert -10.0 in BTC_GOLD_CHANGE_THRESHOLDS or -10 in BTC_GOLD_CHANGE_THRESHOLDS
    assert len(SINGLE_FEATURE_GRID) > 0
    assert len(COMBO_2_GRID) > 5


# ── exp_r reuse ─────────────────────────────────────────────────────────────

def test_exp_r_handles_empty():
    assert exp_r([]) == 0.0


def test_exp_r_basic():
    assert exp_r([{"result_r": 2.0}, {"result_r": -1.0}]) == pytest.approx(0.5, abs=1e-6)
