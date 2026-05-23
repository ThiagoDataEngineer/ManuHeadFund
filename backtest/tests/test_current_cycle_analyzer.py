"""
test_current_cycle_analyzer.py -- TDD para Now-cast de ciclo.

Contrato (modulo: current_cycle_analyzer):
    build_state_vector(state_dict)               -> np.ndarray (V6.5 features)
    similarity(vec_a, vec_b)                     -> float 0..1
    find_similar_periods(current, history, top_n)-> list[dict]
    compute_outcomes(analogs, horizons)          -> dict[horizon_label, stats]
    compute_scenarios(analogs, horizon)          -> dict (probs somam 100)
    compute_confidence(analogs, horizon)         -> float 0..1
    is_unprecedented(analogs)                    -> bool
    recommend(state, scenarios, confidence, unprec) -> str
    analyze_current(current_state, history, top_n) -> dict (JSON schema)
"""
from __future__ import annotations

import json
import os
import sys
from datetime import date, timedelta

import numpy as np
import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from current_cycle_analyzer import (  # noqa: E402
    analyze_current,
    build_state_vector,
    compute_confidence,
    compute_outcomes,
    compute_scenarios,
    find_similar_periods,
    is_unprecedented,
    recommend,
    similarity,
)


# ─────────────────────────────────────────────────────────────────────────────
# Fixtures
# ─────────────────────────────────────────────────────────────────────────────

def _state(regime="TRANSITION_DOWN", pi="BEFORE", dd=-27.0,
           nupl=0.42, wma=35.0, macro="NEUTRAL", price=79000):
    return {
        "btc_price":            price,
        "regime":               regime,
        "pi_cycle":             pi,
        "ath_dd_pct":           dd,
        "nupl_proxy":           nupl,
        "wma_200_distance_pct": wma,
        "macro_bias":           macro,
    }


def _historical(n=200, seed=42):
    """Gera n estados historicos sinteticos com future returns ja anotados."""
    rng = np.random.default_rng(seed)
    regimes = ["BULL", "BEAR", "SIDEWAYS", "TRANSITION_DOWN", "TRANSITION_UP"]
    pis     = ["NEUTRAL", "BEFORE", "TRIGGERED", "POST_PEAK"]
    macros  = ["BULLISH", "NEUTRAL", "BEARISH"]
    start   = date(2014, 1, 1)
    hist    = []
    for i in range(n):
        d = start + timedelta(days=i * 25)
        regime = regimes[int(rng.integers(0, len(regimes)))]
        # outcome direcional condicionado ao regime (sinal mais simples para testar)
        if regime == "BULL":
            r60 = float(rng.normal(20, 10))
        elif regime == "BEAR":
            r60 = float(rng.normal(-25, 10))
        elif regime == "SIDEWAYS":
            r60 = float(rng.normal(0, 5))
        elif regime == "TRANSITION_DOWN":
            r60 = float(rng.normal(-15, 12))
        else:
            r60 = float(rng.normal(12, 10))
        hist.append({
            "date":      d.isoformat(),
            "state":     _state(
                regime=regime,
                pi=pis[int(rng.integers(0, len(pis)))],
                dd=float(rng.uniform(-80, -5)),
                nupl=float(rng.uniform(0.1, 0.95)),
                wma=float(rng.uniform(-40, 80)),
                macro=macros[int(rng.integers(0, len(macros)))],
                price=float(rng.uniform(3000, 100000)),
            ),
            "future_returns": {
                "30d": r60 / 2,
                "60d": r60,
                "90d": r60 * 1.4,
            },
        })
    return hist


# ─────────────────────────────────────────────────────────────────────────────
# 1. analyze_current retorna estrutura com cycle_phase, regime, recommendation
# ─────────────────────────────────────────────────────────────────────────────
def test_returns_current_state():
    out = analyze_current(_state(), _historical(100), top_n=5)
    for k in ("current_state", "historical_analogs", "scenarios_60d",
              "confidence", "recommendation"):
        assert k in out
    assert out["current_state"]["regime"] == "TRANSITION_DOWN"
    assert isinstance(out["recommendation"], str)


# ─────────────────────────────────────────────────────────────────────────────
# 2. find_similar_periods retorna top_n com similarity score
# ─────────────────────────────────────────────────────────────────────────────
def test_finds_historical_analogs():
    history = _historical(200)
    analogs = find_similar_periods(_state(), history, top_n=5)
    assert len(analogs) == 5
    for a in analogs:
        assert "similarity_score" in a
        assert 0.0 <= a["similarity_score"] <= 1.0
        assert "period_start" in a
        assert "outcome_60d_pct" in a
    # Ordenado decrescente por similarity
    scores = [a["similarity_score"] for a in analogs]
    assert scores == sorted(scores, reverse=True)


# ─────────────────────────────────────────────────────────────────────────────
# 3. compute_outcomes 30/60/90 dias
# ─────────────────────────────────────────────────────────────────────────────
def test_outcome_distribution_per_horizon():
    history = _historical(100)
    analogs = find_similar_periods(_state(), history, top_n=10)
    outcomes = compute_outcomes(analogs, horizons=("30d", "60d", "90d"))
    for h in ("30d", "60d", "90d"):
        assert h in outcomes
        for k in ("mean", "std", "win_rate", "max_dd"):
            assert k in outcomes[h]


# ─────────────────────────────────────────────────────────────────────────────
# 4. Cenarios probabilisticos somam 100
# ─────────────────────────────────────────────────────────────────────────────
def test_probabilistic_scenarios():
    history = _historical(200)
    analogs = find_similar_periods(_state(), history, top_n=10)
    sc = compute_scenarios(analogs, horizon="60d")
    for k in ("bull_probability", "sideways_probability", "bear_probability"):
        assert k in sc
        assert 0 <= sc[k] <= 100
    total = sc["bull_probability"] + sc["sideways_probability"] + sc["bear_probability"]
    assert total == pytest.approx(100, abs=0.5)


# ─────────────────────────────────────────────────────────────────────────────
# 5. Recomendacao operacional retorna label valido
# ─────────────────────────────────────────────────────────────────────────────
def test_operational_recommendation():
    sc_bull = {"bull_probability": 75, "sideways_probability": 15, "bear_probability": 10}
    sc_bear = {"bull_probability": 10, "sideways_probability": 15, "bear_probability": 75}
    sc_mix  = {"bull_probability": 33, "sideways_probability": 34, "bear_probability": 33}
    assert recommend(_state(),                          sc_bull, confidence=0.8, unprecedented=False) == "FAVORABLE_LONG"
    assert recommend(_state(regime="TRANSITION_DOWN"),  sc_bear, confidence=0.8, unprecedented=False) == "FAVORABLE_SHORT"
    assert recommend(_state(),                          sc_mix,  confidence=0.4, unprecedented=False) in ("MIXED", "AVOID", "MIXED_LEAN_BEAR", "MIXED_LEAN_BULL")
    assert recommend(_state(),                          sc_bull, confidence=0.8, unprecedented=True)  == "AVOID"


# ─────────────────────────────────────────────────────────────────────────────
# 6. State vector inclui indicadores V6.5
# ─────────────────────────────────────────────────────────────────────────────
def test_uses_v6_5_indicators():
    vec = build_state_vector(_state())
    assert isinstance(vec, np.ndarray)
    # 6 features mapeadas: regime, pi_cycle, ath_dd, nupl, wma_200, macro
    assert vec.size >= 6
    # similarity entre identicos = 1.0
    assert similarity(vec, vec) == pytest.approx(1.0, abs=1e-6)


# ─────────────────────────────────────────────────────────────────────────────
# 7. Estado sem analogos -> UNPRECEDENTED + cautela
# ─────────────────────────────────────────────────────────────────────────────
def test_handles_unprecedented_state():
    # Estado completamente atipico: NUPL altissimo + DD profundo + transition_up.
    weird = _state(regime="TRANSITION_UP", pi="TRIGGERED",
                   dd=-78.0, nupl=0.99, wma=-35.0, macro="BEARISH")
    # historico oposto (so regime BULL com NUPL baixo e WMA acima)
    rng = np.random.default_rng(0)
    fake_hist = []
    for i in range(50):
        fake_hist.append({
            "date":  (date(2018, 1, 1) + timedelta(days=i*20)).isoformat(),
            "state": _state(regime="BULL", pi="NEUTRAL", dd=-2, nupl=0.20,
                            wma=60, macro="BULLISH",
                            price=float(rng.uniform(3000, 100000))),
            "future_returns": {"30d": 5, "60d": 10, "90d": 15},
        })
    analogs = find_similar_periods(weird, fake_hist, top_n=5)
    assert is_unprecedented(analogs, threshold=0.3) is True
    out = analyze_current(weird, fake_hist, top_n=5)
    assert out["recommendation"] in ("AVOID", "UNPRECEDENTED")
    assert out.get("unprecedented") is True


# ─────────────────────────────────────────────────────────────────────────────
# 8. Confidence score baseado em consistencia
# ─────────────────────────────────────────────────────────────────────────────
def test_returns_confidence_score():
    # Todos analogs com mesmo sinal -> confidence alta
    consistent = [{"future_returns": {"60d": 15.0}, "similarity_score": 0.9}] * 5
    # Sinais misturados -> confidence baixa
    mixed = [
        {"future_returns": {"60d":  15.0}, "similarity_score": 0.9},
        {"future_returns": {"60d": -20.0}, "similarity_score": 0.9},
        {"future_returns": {"60d":  10.0}, "similarity_score": 0.9},
        {"future_returns": {"60d": -15.0}, "similarity_score": 0.9},
        {"future_returns": {"60d":   2.0}, "similarity_score": 0.9},
    ]
    c_high = compute_confidence(consistent, horizon="60d")
    c_low  = compute_confidence(mixed,      horizon="60d")
    assert 0.0 <= c_high <= 1.0
    assert 0.0 <= c_low  <= 1.0
    assert c_high > c_low
    assert c_high >= 0.7


# ─────────────────────────────────────────────────────────────────────────────
# 9. JSON schema valido
# ─────────────────────────────────────────────────────────────────────────────
def test_json_schema_validates():
    out = analyze_current(_state(), _historical(150), top_n=5)
    for k in ("timestamp", "current_state", "historical_analogs",
              "scenarios_60d", "confidence", "recommendation",
              "operational_advice"):
        assert k in out
    assert isinstance(out["historical_analogs"], list)
    assert len(out["historical_analogs"]) == 5
    for a in out["historical_analogs"]:
        for k in ("period_start", "period_end", "similarity_score",
                  "outcome_60d_pct", "outcome_label"):
            assert k in a
    adv = out["operational_advice"]
    for k in ("should_operate_long", "should_operate_short", "wait_for"):
        assert k in adv
    # Deve serializar
    parsed = json.loads(json.dumps(out, default=str))
    assert parsed["recommendation"] == out["recommendation"]
