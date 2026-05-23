"""
test_regime_direction_matrix.py — TDD strict para regime_direction_matrix.py

PHASE 1 — RED: 9 testes escritos ANTES da implementação.

Cobertura:
  - LONG em BULL_STRONG (validação 14y)
  - SHORT em TRANSITION_UP (confirma/refuta Chat 3: +0.81R)
  - AVOID quando ambas direções fracas
  - INSUFFICIENT_DATA quando < 30 trades
  - Matrix completa com 8 regimes
  - Edge strength thresholds (STRONG/MEDIUM/WEAK/NONE)
  - Year distribution per regime (anti viés temporal)
  - Long/Short correlation per regime
  - JSON schema válido

NÃO MODIFICA: db.py, signal_generator.py, metrics.py.
"""
import json
import pytest
from typing import Dict, List

from regime_direction_matrix import (
    REGIMES,
    classify_edge_strength,
    classify_confidence,
    pick_best_direction,
    years_appeared,
    long_short_correlation,
    aggregate_direction_metrics,
    build_regime_entry,
    build_matrix_report,
    evaluate_matrix_go_criterion,
)


# ----------------------------------------------------------------------------
# Helpers — trades sintéticos com regime/direction/ts
# ----------------------------------------------------------------------------

def _trade(year: int, regime: str, direction: str, result_r: float) -> Dict:
    return {
        "entry_ts":  f"{year}-06-15T12:00:00+00:00",
        "exit_ts":   f"{year}-06-16T12:00:00+00:00",
        "regime":    regime,
        "direction": direction,
        "result_r":  result_r,
    }


# ============================================================================
# TEST 1 — LONG em BULL_STRONG é lucrativo em 14y
# ============================================================================
def test_long_in_bull_strong_is_profitable_14y():
    """Trades LONG durante BULL_STRONG em 14y → exp > +0.3R, PF > 1.5."""
    trades = []
    # 200 trades LONG vencedores forte + 50 perdedores
    for y in (2016, 2017, 2020, 2023):
        for _ in range(50):
            trades.append(_trade(y, "BULL_STRONG", "LONG", 0.6))
        for _ in range(12):
            trades.append(_trade(y, "BULL_STRONG", "LONG", -0.4))

    metrics = aggregate_direction_metrics(trades, regime="BULL_STRONG", direction="LONG")
    assert metrics["exp"] > 0.3
    assert metrics["pf"] > 1.5


# ============================================================================
# TEST 2 — SHORT em TRANSITION_UP (validação 14y)
# ============================================================================
def test_short_in_transition_up_validation():
    """Trades SHORT durante TRANSITION_UP em 14y → reporta exp/pf (confirma ou refuta Chat 3)."""
    trades = []
    # Cenário positivo (confirma achado Chat 3): SHORTs ganham na transição
    for y in (2017, 2020, 2023):
        for _ in range(15):
            trades.append(_trade(y, "TRANSITION_UP", "SHORT", 0.8))
        for _ in range(5):
            trades.append(_trade(y, "TRANSITION_UP", "SHORT", -0.4))

    metrics = aggregate_direction_metrics(trades, regime="TRANSITION_UP", direction="SHORT")
    assert "exp" in metrics
    assert "pf" in metrics
    assert "wr" in metrics
    assert "trades" in metrics


# ============================================================================
# TEST 3 — AVOID quando ambas direções fracas
# ============================================================================
def test_avoid_recommendation_consistency():
    """Quando long_exp < +0.2R E short_exp < +0.2R → best_direction = AVOID."""
    long_m  = {"exp": 0.05, "pf": 1.05, "wr": 30, "trades": 200}
    short_m = {"exp": 0.10, "pf": 1.08, "wr": 32, "trades": 180}
    best = pick_best_direction(long_m, short_m)
    assert best == "AVOID"


# ============================================================================
# TEST 4 — Confidence INSUFFICIENT_DATA com < 30 trades
# ============================================================================
def test_minimum_trades_per_regime():
    """Regime com < 30 trades → confidence LOW (INSUFFICIENT_DATA)."""
    assert classify_confidence(15) == "LOW"
    assert classify_confidence(0) == "LOW"
    assert classify_confidence(29) == "LOW"
    assert classify_confidence(30) == "MEDIUM"
    assert classify_confidence(99) == "MEDIUM"
    assert classify_confidence(100) == "HIGH"
    assert classify_confidence(5000) == "HIGH"


# ============================================================================
# TEST 5 — Matrix tem todos os 8 regimes
# ============================================================================
def test_matrix_has_all_regimes():
    """build_matrix_report → exatamente 8 entries, cada uma com long/short/best/edge."""
    trades = []
    # Pelo menos 30 trades em cada regime × direção para evitar LOW confidence em todos
    for regime in REGIMES:
        for direction in ("LONG", "SHORT"):
            for i in range(30):
                trades.append(_trade(2020, regime, direction, 0.2 if i % 2 == 0 else -0.1))

    report = build_matrix_report(trades, candles_by_day=None)
    assert "matrix" in report
    assert len(report["matrix"]) == 8
    regimes_in_report = {e["regime"] for e in report["matrix"]}
    assert regimes_in_report == set(REGIMES)
    for entry in report["matrix"]:
        assert "long" in entry
        assert "short" in entry
        assert "best_direction" in entry
        assert "edge_strength" in entry
        assert "confidence" in entry


# ============================================================================
# TEST 6 — Edge strength thresholds
# ============================================================================
def test_edge_strength_thresholds():
    """STRONG >= +0.5 / MEDIUM +0.3 a +0.5 / WEAK +0.0 a +0.3 / NONE < 0."""
    assert classify_edge_strength(0.6) == "STRONG"
    assert classify_edge_strength(0.5) == "STRONG"
    assert classify_edge_strength(0.35) == "MEDIUM"
    assert classify_edge_strength(0.3) == "MEDIUM"
    assert classify_edge_strength(0.15) == "WEAK"
    assert classify_edge_strength(0.0) == "WEAK"
    assert classify_edge_strength(-0.1) == "NONE"
    assert classify_edge_strength(-0.5) == "NONE"


# ============================================================================
# TEST 7 — Year distribution per regime (anti viés temporal)
# ============================================================================
def test_year_distribution_per_regime():
    """Trades de um regime em vários anos → retorna distribuição/lista dos anos."""
    trades = [
        _trade(2017, "BULL_STRONG", "LONG", 0.5),
        _trade(2017, "BULL_STRONG", "LONG", 0.3),
        _trade(2020, "BULL_STRONG", "LONG", 0.4),
        _trade(2023, "BULL_STRONG", "LONG", 0.6),
        _trade(2024, "BEAR_STRONG", "SHORT", 0.2),  # outro regime
    ]
    years = years_appeared(trades, regime="BULL_STRONG")
    assert sorted(years) == [2017, 2020, 2023]


# ============================================================================
# TEST 8 — Long/Short correlation per regime
# ============================================================================
def test_long_short_correlation_per_regime():
    """Para um regime, computa correlação entre result_r de LONG e SHORT (alinhados por dia)."""
    long_trades = [
        {"entry_ts": "2020-01-01T00:00:00", "result_r":  0.5, "direction": "LONG", "regime": "X"},
        {"entry_ts": "2020-01-02T00:00:00", "result_r": -0.3, "direction": "LONG", "regime": "X"},
        {"entry_ts": "2020-01-03T00:00:00", "result_r":  0.7, "direction": "LONG", "regime": "X"},
    ]
    short_trades = [
        {"entry_ts": "2020-01-01T00:00:00", "result_r": -0.4, "direction": "SHORT", "regime": "X"},
        {"entry_ts": "2020-01-02T00:00:00", "result_r":  0.5, "direction": "SHORT", "regime": "X"},
        {"entry_ts": "2020-01-03T00:00:00", "result_r": -0.6, "direction": "SHORT", "regime": "X"},
    ]
    corr = long_short_correlation(long_trades, short_trades)
    assert -1.0 <= corr <= 1.0
    # LONG e SHORT em mesmo bar tendem a ser ANTI-correlacionados
    assert corr < 0


# ============================================================================
# TEST 9 — JSON schema válido
# ============================================================================
def test_json_schema_validates():
    """build_matrix_report retorna dict serializável com schema completo."""
    trades = []
    for regime in REGIMES:
        for direction in ("LONG", "SHORT"):
            for i in range(30):
                trades.append(_trade(2020 + (i % 4), regime, direction, 0.3 if i % 2 == 0 else -0.2))

    report = build_matrix_report(trades, candles_by_day=None)

    # Schema obrigatório
    assert "matrix" in report
    assert "operational_summary" in report
    assert "go_criterion" in report

    for entry in report["matrix"]:
        for k in ("regime", "days_total_14y", "days_pct", "long", "short",
                  "best_direction", "edge_strength", "confidence", "years_appeared"):
            assert k in entry, f"Falta '{k}' em {entry.get('regime')}"

    op = report["operational_summary"]
    for k in ("regimes_long_only", "regimes_short_only", "regimes_both",
              "regimes_avoid", "total_tradeable_pct_of_time"):
        assert k in op

    go = report["go_criterion"]
    for k in ("rule", "passed"):
        assert k in go

    # Serializa
    json.dumps(report)
