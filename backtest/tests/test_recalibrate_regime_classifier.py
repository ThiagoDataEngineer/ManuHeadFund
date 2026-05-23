"""
test_recalibrate_regime_classifier.py — TDD strict para recalibrate_regime_classifier.py

PHASE 1 — RED: 10 testes ANTES da implementação.

Cobertura:
  - Split train (2014-2022) / holdout (2023-2025)
  - Grid de thresholds (ADX, transition_bars, sideways_band, capitulation)
  - Evaluate combo no train → métricas por (regime, direção)
  - Pick best thresholds (maximiza regimes MEDIUM+)
  - Holdout NÃO recalibra — usa thresholds escolhidos no train
  - Decisão PASS / FAIL_OVERFIT / FAIL_NO_EDGE
  - Schema JSON do output

NÃO MODIFICA: db.py, signal_generator.py, metrics.py.
"""
import pytest
from typing import Dict, List

from recalibrate_regime_classifier import (
    split_train_holdout,
    generate_threshold_grid,
    count_medium_plus_regimes,
    evaluate_combo_on_trades,
    pick_best_thresholds,
    decide_outcome,
    build_recalibrated_report,
)


def _trade(year: int, regime_raw: str = "bull", direction: str = "LONG", r: float = 0.3) -> Dict:
    return {
        "entry_ts":  f"{year}-06-15T12:00:00+00:00",
        "exit_ts":   f"{year}-06-16T12:00:00+00:00",
        "result_r":  r,
        "direction": direction,
        "regime":    regime_raw,
    }


def _candle(ts: str, close: float) -> Dict:
    return {"ts": ts, "open": close, "high": close * 1.01, "low": close * 0.99, "close": close, "volume": 1000.0}


# ============================================================================
# TEST 1 — Split train/holdout por ano
# ============================================================================
def test_train_holdout_split_by_year():
    trades = []
    for y in range(2014, 2026):
        for _ in range(5):
            trades.append(_trade(y))
    train, holdout = split_train_holdout(trades, train_end_year=2022, holdout_start_year=2023)
    # 2014-2022 = 9 anos × 5 = 45 train
    assert len(train) == 45
    # 2023-2025 = 3 anos × 5 = 15 holdout
    assert len(holdout) == 15
    # Verifica anos
    train_years = {int(t["entry_ts"][:4]) for t in train}
    assert train_years == set(range(2014, 2023))
    holdout_years = {int(t["entry_ts"][:4]) for t in holdout}
    assert holdout_years == {2023, 2024, 2025}


# ============================================================================
# TEST 2 — Grid combinatório dos thresholds
# ============================================================================
def test_grid_generates_all_combos():
    grid = generate_threshold_grid(
        adx_values=[20, 25, 30],
        transition_bars_values=[10, 20],
        sideways_band_values=[0.01, 0.02],
        capitulation_values=[0.20, 0.25],
    )
    # 3 × 2 × 2 × 2 = 24
    assert len(grid) == 24
    for combo in grid:
        assert "adx_strong" in combo
        assert "transition_bars" in combo
        assert "sideways_band" in combo
        assert "capitulation" in combo


# ============================================================================
# TEST 3 — Conta regimes com edge MEDIUM+ (exp >= +0.3R)
# ============================================================================
def test_count_medium_plus_regimes():
    matrix = [
        {"regime": "BULL_STRONG", "best_direction": "LONG", "long":  {"exp": 0.4},  "short": {"exp": -0.1}, "confidence": "HIGH"},
        {"regime": "BULL_WEAK",   "best_direction": "LONG", "long":  {"exp": 0.5},  "short": {"exp": -0.2}, "confidence": "HIGH"},
        {"regime": "BEAR_STRONG", "best_direction": "AVOID","long":  {"exp": -0.2}, "short": {"exp": 0.1},  "confidence": "HIGH"},
        {"regime": "TRANSITION_UP","best_direction": "SHORT","long": {"exp": 0.05}, "short": {"exp": 0.45}, "confidence": "MEDIUM"},
        {"regime": "SIDEWAYS",    "best_direction": "AVOID","long":  {"exp": 0.0},  "short": {"exp": 0.0},  "confidence": "LOW"},
    ]
    n = count_medium_plus_regimes(matrix)
    # BULL_STRONG (LONG +0.4), BULL_WEAK (+0.5), TRANSITION_UP (SHORT +0.45) = 3
    # SIDEWAYS exclude por LOW confidence
    assert n == 3


# ============================================================================
# TEST 4 — Evaluate combo: thresholds custom afetam classificação
# ============================================================================
def test_evaluate_combo_on_trades_returns_metrics():
    """Sintético: 100 trades + 250 candles uptrend forte. Combo deve retornar dict com matrix."""
    candles = []
    for i in range(250):
        candles.append(_candle(f"2020-01-{(i % 30) + 1:02d}T00:00:00", 100 + i * 2.0))
    trades = []
    last_ts = candles[-1]["ts"]
    for _ in range(50):
        trades.append({
            "entry_ts": last_ts, "result_r": 0.5, "direction": "LONG", "regime": "bull",
        })
    combo = {"adx_strong": 25.0, "transition_bars": 20, "sideways_band": 0.02, "capitulation": 0.25}
    result = evaluate_combo_on_trades(trades, candles, combo)
    assert "matrix" in result
    assert "n_medium_plus" in result
    assert "combo" in result
    assert result["combo"] == combo


# ============================================================================
# TEST 5 — Pick best thresholds (maximiza MEDIUM+ no train)
# ============================================================================
def test_pick_best_thresholds():
    """Dado 3 combos com counts 1, 3, 2 → pick deve retornar o de count 3."""
    combos = [
        {"combo": {"adx_strong": 20.0}, "n_medium_plus": 1},
        {"combo": {"adx_strong": 25.0}, "n_medium_plus": 3},
        {"combo": {"adx_strong": 30.0}, "n_medium_plus": 2},
    ]
    best = pick_best_thresholds(combos)
    assert best["combo"]["adx_strong"] == 25.0
    assert best["n_medium_plus"] == 3


# ============================================================================
# TEST 6 — Holdout usa thresholds do train, NÃO otimiza
# ============================================================================
def test_holdout_uses_train_thresholds_not_optimized():
    """Holdout deve receber thresholds FIXOS do train, não gerar grid próprio."""
    train_trades = []
    holdout_trades = []
    candles = []
    # Cenário stub: build_recalibrated_report retorna train_best e holdout_eval com os MESMOS thresholds
    report = build_recalibrated_report(
        train_trades=train_trades,
        holdout_trades=holdout_trades,
        candles=candles,
        grid_adx=[25.0],
        grid_transition_bars=[20],
        grid_sideways_band=[0.02],
        grid_capitulation=[0.25],
    )
    assert "best_thresholds" in report
    assert "train_matrix" in report
    assert "holdout_matrix" in report
    # holdout aplicou os mesmos thresholds
    assert report["holdout_thresholds"] == report["best_thresholds"]


# ============================================================================
# TEST 7 — Decisão PASS: train >= 3 E holdout >= 3
# ============================================================================
def test_decision_PASS_when_3plus_regimes_in_both():
    decision = decide_outcome(train_count=4, holdout_count=3)
    assert decision == "PASS"


# ============================================================================
# TEST 8 — Decisão FAIL_OVERFIT: train passa mas holdout falha
# ============================================================================
def test_decision_FAIL_OVERFIT_when_train_passes_holdout_fails():
    decision = decide_outcome(train_count=5, holdout_count=1)
    assert decision == "FAIL_OVERFIT"


# ============================================================================
# TEST 9 — Decisão FAIL_NO_EDGE: train não atinge threshold
# ============================================================================
def test_decision_FAIL_NO_EDGE_when_train_below_threshold():
    decision = decide_outcome(train_count=2, holdout_count=2)
    assert decision == "FAIL_NO_EDGE"


# ============================================================================
# TEST 10 — Schema JSON output
# ============================================================================
def test_json_schema_recalibrated_output():
    report = build_recalibrated_report(
        train_trades=[],
        holdout_trades=[],
        candles=[],
        grid_adx=[25.0],
        grid_transition_bars=[20],
        grid_sideways_band=[0.02],
        grid_capitulation=[0.25],
    )
    for k in ("best_thresholds", "train_matrix", "holdout_matrix",
              "train_n_medium_plus", "holdout_n_medium_plus",
              "regimes_tradeable_novo", "decision", "holdout_thresholds"):
        assert k in report, f"Falta '{k}' no schema"
    assert report["decision"] in ("PASS", "FAIL_OVERFIT", "FAIL_NO_EDGE")
    import json
    json.dumps(report)  # serializável
