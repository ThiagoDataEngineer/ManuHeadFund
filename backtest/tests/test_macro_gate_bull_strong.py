"""
test_macro_gate_bull_strong.py -- TDD para gate macro (DXY+M2) em BULL_STRONG.
"""
from __future__ import annotations

import json
import os
import sys

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from macro_gate_bull_strong import (  # noqa: E402
    annotate_trades_with_macro,
    apply_macro_gate,
    classify_bull_strong_day,
    DXY_M2_PARAM_GRID,
    DecisionOutcome,
    build_proxy_trades_from_closes,
    compute_exclusions_by_year,
    decide_outcome,
    exp_r,
    fetch_fred_series,
    grid_search,
    parse_fred_csv,
)


# ── BULL_STRONG day classifier ──────────────────────────────────────────────

def test_classify_bull_strong_day_uptrend():
    # 250 closes em uptrend forte
    closes = [100.0 + i * 0.5 for i in range(250)]
    assert classify_bull_strong_day(closes) is True


def test_classify_bull_strong_day_downtrend_not_bull():
    closes = [200.0 - i * 0.5 for i in range(250)]
    assert classify_bull_strong_day(closes) is False


def test_classify_bull_strong_day_insufficient_history():
    closes = [100.0, 101.0, 102.0]
    assert classify_bull_strong_day(closes) is False


# ── Proxy trades from closes ────────────────────────────────────────────────

def test_build_proxy_trades_from_closes_returns_list():
    closes = [100.0 + i * 0.3 for i in range(300)]
    dates = [(2020, 1, 1)] * 300  # placeholder
    trades = build_proxy_trades_from_closes(closes, dates, lookahead=5)
    assert len(trades) > 0
    for t in trades:
        assert "entry_ts" in t
        assert "result_r" in t
        assert t["regime"] == "BULL_STRONG"


# ── FRED CSV parsing ────────────────────────────────────────────────────────

def test_parse_fred_csv_basic():
    csv = "DATE,VALUE\n2020-01-01,100.5\n2020-02-01,101.0\n2020-03-01,.\n"
    series = parse_fred_csv(csv)
    assert ("2020-01-01", 100.5) in series
    assert ("2020-02-01", 101.0) in series
    # Linhas com "." (missing) sao puladas
    assert not any(d == "2020-03-01" for d, _ in series)


def test_parse_fred_csv_handles_header_only():
    csv = "DATE,VALUE\n"
    assert parse_fred_csv(csv) == []


# ── Annotate trades ─────────────────────────────────────────────────────────

def test_annotate_trades_with_macro():
    trades = [{"entry_ts": "2020-06-15", "result_r": 1.0, "regime": "BULL_STRONG"}]
    dxy_series = [("2020-06-15", 96.5), ("2020-05-15", 99.0)]
    m2_series = [("2020-06-01", 18000.0), ("2019-06-01", 14800.0)]
    out = annotate_trades_with_macro(trades, dxy_series, m2_series)
    assert "dxy_level" in out[0]
    assert "dxy_mom_change_pct" in out[0]
    assert "m2_yoy_change_pct" in out[0]
    assert out[0]["dxy_level"] == pytest.approx(96.5)
    # m2 yoy: 18000 vs 14800 = +21.6%
    assert out[0]["m2_yoy_change_pct"] == pytest.approx(21.621, abs=0.1)


# ── Apply gate ─────────────────────────────────────────────────────────────

def test_apply_macro_gate_filters():
    trades = [
        {"dxy_level": 95.0, "m2_yoy_change_pct": 10.0, "result_r": 1.0},
        {"dxy_level": 105.0, "m2_yoy_change_pct": 1.0, "result_r": -1.0},
        {"dxy_level": 90.0, "m2_yoy_change_pct": 15.0, "result_r": 2.0},
    ]
    gate = {"dxy_max": 100.0, "m2_yoy_min": 5.0}
    kept = apply_macro_gate(trades, gate)
    assert len(kept) == 2
    assert all(t["result_r"] > 0 for t in kept)


# ── exp_r ─────────────────────────────────────────────────────────────────

def test_exp_r_basic():
    trades = [{"result_r": 1.0}, {"result_r": -1.0}, {"result_r": 2.0}]
    assert exp_r(trades) == pytest.approx(2.0 / 3.0, abs=1e-6)


def test_exp_r_empty():
    assert exp_r([]) == 0.0


# ── Grid search ────────────────────────────────────────────────────────────

def test_grid_search_finds_best():
    trades_train = [
        {"dxy_level": 95.0, "m2_yoy_change_pct": 10.0, "result_r": 1.0, "year": 2018},
        {"dxy_level": 105.0, "m2_yoy_change_pct": 1.0, "result_r": -1.0, "year": 2018},
        {"dxy_level": 90.0, "m2_yoy_change_pct": 15.0, "result_r": 2.0, "year": 2019},
    ] * 10
    grid = [
        {"dxy_max": 100.0, "m2_yoy_min": 5.0},
        {"dxy_max": 200.0, "m2_yoy_min": 0.0},  # No filter -> baixo exp
    ]
    best, best_exp, all_results = grid_search(trades_train, grid)
    assert best["dxy_max"] == 100.0
    assert best_exp > 1.0


# ── Exclusions by year ─────────────────────────────────────────────────────

def test_compute_exclusions_by_year():
    trades = [
        {"year": 2023, "dxy_level": 95.0, "m2_yoy_change_pct": 10.0},  # keep
        {"year": 2023, "dxy_level": 105.0, "m2_yoy_change_pct": 1.0},  # exclude
        {"year": 2025, "dxy_level": 110.0, "m2_yoy_change_pct": 0.0},  # exclude
        {"year": 2025, "dxy_level": 102.0, "m2_yoy_change_pct": 2.0},  # exclude
    ]
    gate = {"dxy_max": 100.0, "m2_yoy_min": 5.0}
    excl = compute_exclusions_by_year(trades, gate)
    assert excl[2023]["excluded"] == 1
    assert excl[2023]["total"] == 2
    assert excl[2025]["excluded"] == 2
    assert excl[2025]["total"] == 2


# ── Decision ───────────────────────────────────────────────────────────────

def test_decide_outcome_pass():
    r = decide_outcome(exp_train_baseline=0.35, exp_train_filtered=0.50,
                       exp_holdout_filtered=0.35)
    assert r.decision == "PASS"


def test_decide_outcome_fail_overfit():
    # Train improves a lot, holdout does not (gap > 0.20)
    r = decide_outcome(exp_train_baseline=0.35, exp_train_filtered=0.80,
                       exp_holdout_filtered=0.40)
    assert r.decision == "FAIL_OVERFIT"


def test_decide_outcome_fail_no_improvement():
    # Train barely improves (< +0.10)
    r = decide_outcome(exp_train_baseline=0.35, exp_train_filtered=0.40,
                       exp_holdout_filtered=0.35)
    assert r.decision == "FAIL_NO_IMPROVEMENT"


def test_decide_outcome_fail_holdout_too_low():
    # Train improves enough, holdout below +0.30
    r = decide_outcome(exp_train_baseline=0.35, exp_train_filtered=0.55,
                       exp_holdout_filtered=0.20)
    assert r.decision == "FAIL_NO_IMPROVEMENT"


# ── Param grid sanity ──────────────────────────────────────────────────────

def test_param_grid_not_empty_and_has_keys():
    assert len(DXY_M2_PARAM_GRID) >= 8
    for cfg in DXY_M2_PARAM_GRID:
        assert "dxy_max" in cfg
        assert "m2_yoy_min" in cfg


# ── FRED fetch (network) -- skippable ──────────────────────────────────────

def test_fetch_fred_series_returns_list_or_skip():
    try:
        s = fetch_fred_series("DTWEXBGS")
    except Exception:
        pytest.skip("Sem rede FRED")
    if not s:
        pytest.skip("FRED retornou vazio")
    assert isinstance(s, list)
    assert len(s) > 10
