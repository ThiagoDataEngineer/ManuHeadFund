"""
test_cycle_recalibrate.py -- TDD para Task 3b: Recalibracao do Current Cycle
                             Analyzer com validacao direcional pura em holdout.

Contrato (modulo: cycle_recalibrate):
    FEATURE_NAMES                                    -> tuple[str,...] (5 features)
    weighted_similarity(a, b, weights)               -> float 0..1
    find_analogs(query, candidates, weights, k, ...) -> list[dict]
    predict_direction(analogs, ...)                  -> "bull"|"sideways"|"bear"
    realized_direction(r_60d, ...)                   -> "bull"|"sideways"|"bear"
    compute_hit_rate(subset, candidates, weights, k) -> float 0..1
    grid_search_weights(train, k, grid)              -> dict {weights, hit_rate}
    validate_holdout(holdout, train, weights, k)     -> dict
    decide(train_hit, holdout_hit, ...)              -> "PASS"|"FAIL_OVERFIT"|"FAIL_NO_EDGE"
    recalibrate(task2_matrix, history, current, ...) -> dict (schema task3b)
"""
from __future__ import annotations

import json
import os
import sys
from datetime import date, timedelta

import numpy as np
import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from cycle_recalibrate import (  # noqa: E402
    FEATURE_NAMES,
    compute_hit_rate,
    decide,
    find_analogs,
    grid_search_weights,
    predict_direction,
    realized_direction,
    recalibrate,
    validate_holdout,
    weighted_similarity,
)


# ─────────────────────────────────────────────────────────────────────────────
# Fixtures
# ─────────────────────────────────────────────────────────────────────────────

def _feat(price_action=0.0, nupl=0.5, ath_dd=-20.0, wma=10.0, momentum=0.0):
    return {
        "price_action": price_action,
        "nupl_proxy":   nupl,
        "ath_dd":       ath_dd,
        "wma_distance": wma,
        "momentum":     momentum,
    }


def _hist_predictive(n=400, seed=42, holdout_drift=False):
    """
    Historico em que `realized_60d_pct` depende fortemente de NUPL e momentum.
    holdout_drift=True altera a relacao apos 2023 (estresse de overfit).
    """
    rng = np.random.default_rng(seed)
    start = date(2014, 1, 1)
    out = []
    for i in range(n):
        d = start + timedelta(days=i * 12)  # ~13 anos em 400 pontos
        nupl     = float(rng.uniform(0.10, 0.95))
        momentum = float(rng.uniform(-50, 50))
        ath_dd   = float(rng.uniform(-80, -3))
        wma      = float(rng.uniform(-40, 80))
        price_a  = float(rng.uniform(-25, 25))

        # Padrao predictivo: NUPL alto -> queda; momentum positivo -> alta
        base = -40.0 * (nupl - 0.5) + 0.4 * momentum
        # Drift no holdout: inverte sinal apos 2023 (sabotagem para test_decide_fail_overfit)
        if holdout_drift and d >= date(2023, 1, 1):
            base = -base
        r60 = base + float(rng.normal(0, 4))

        out.append({
            "date":          d.isoformat(),
            "features":      _feat(price_a, nupl, ath_dd, wma, momentum),
            "realized_60d_pct": r60,
        })
    return out


def _matrix_stub():
    return {
        "matrix": [
            {"regime": "BULL_STRONG", "best_direction": "LONG"},
            {"regime": "BEAR_STRONG", "best_direction": "AVOID"},
        ],
        "operational_summary": {"regimes_long_only": ["BULL_STRONG"]},
        "go_criterion": {"passed": False},
    }


# ═══════════════════════════════════════════════════════════════════════════════
# 1. Similarity ponderada
# ═══════════════════════════════════════════════════════════════════════════════
def test_weighted_similarity_identity_is_one():
    f = _feat(1, 0.5, -20, 10, 5)
    w = {n: 0.2 for n in FEATURE_NAMES}
    assert weighted_similarity(f, f, w) == pytest.approx(1.0, abs=1e-6)


def test_weighted_similarity_zero_weight_ignores_feature():
    # Diferenca grande SO em 'momentum'
    a = _feat(0, 0.5, -20, 10, 0)
    b = _feat(0, 0.5, -20, 10, 50)
    w_all = {n: 0.2 for n in FEATURE_NAMES}
    w_no_mom = {**w_all, "momentum": 0.0}
    sim_all    = weighted_similarity(a, b, w_all)
    sim_no_mom = weighted_similarity(a, b, w_no_mom)
    assert sim_no_mom > sim_all  # ignorando a diferenca, fica mais parecido
    assert sim_no_mom == pytest.approx(1.0, abs=1e-6)


# ═══════════════════════════════════════════════════════════════════════════════
# 2. find_analogs
# ═══════════════════════════════════════════════════════════════════════════════
def test_find_analogs_returns_top_k_sorted():
    history = _hist_predictive(60)
    query   = history[10]["features"]
    w = {n: 0.2 for n in FEATURE_NAMES}
    analogs = find_analogs(query, history, weights=w, k=5,
                           exclude_dates=[history[10]["date"]], exclude_buffer_days=0)
    assert len(analogs) == 5
    sims = [a["similarity_score"] for a in analogs]
    assert sims == sorted(sims, reverse=True)


def test_find_analogs_excludes_leakage_window():
    history = _hist_predictive(60)
    target  = history[10]
    w = {n: 0.2 for n in FEATURE_NAMES}
    # Buffer 90 dias: candidatos dentro de +/- 90d do alvo devem ser excluidos
    analogs = find_analogs(target["features"], history, weights=w, k=5,
                           exclude_dates=[target["date"]], exclude_buffer_days=90)
    target_d = date.fromisoformat(target["date"])
    for a in analogs:
        ad = date.fromisoformat(a["date"])
        assert abs((ad - target_d).days) > 90


# ═══════════════════════════════════════════════════════════════════════════════
# 3. Predicao e ground-truth direcionais
# ═══════════════════════════════════════════════════════════════════════════════
def test_predict_direction_bull_bear_sideways():
    bull = [{"realized_60d_pct": 25}, {"realized_60d_pct": 15}, {"realized_60d_pct": 20}]
    bear = [{"realized_60d_pct": -25}, {"realized_60d_pct": -30}]
    side = [{"realized_60d_pct": 2}, {"realized_60d_pct": -3}, {"realized_60d_pct": 5}]
    assert predict_direction(bull) == "bull"
    assert predict_direction(bear) == "bear"
    assert predict_direction(side) == "sideways"


def test_realized_direction_thresholds():
    assert realized_direction( 15.0) == "bull"
    assert realized_direction(-15.0) == "bear"
    assert realized_direction(  3.0) == "sideways"
    assert realized_direction( 10.0, bull_threshold=10, bear_threshold=-10) == "sideways"  # strict >


# ═══════════════════════════════════════════════════════════════════════════════
# 4. Hit rate
# ═══════════════════════════════════════════════════════════════════════════════
def test_hit_rate_high_when_features_are_predictive():
    # Pesos enfatizando NUPL e momentum (que governam o realized no fixture)
    history = _hist_predictive(300, seed=42)
    train = [h for h in history if date.fromisoformat(h["date"]) < date(2023, 1, 1)]
    w = {"price_action": 0.0, "nupl_proxy": 0.5, "ath_dd": 0.0, "wma_distance": 0.0, "momentum": 0.5}
    hr = compute_hit_rate(train, train, weights=w, k=5, exclude_buffer_days=60)
    assert hr >= 0.5  # melhor que aleatorio (~0.33)


# ═══════════════════════════════════════════════════════════════════════════════
# 5. Grid search
# ═══════════════════════════════════════════════════════════════════════════════
def test_grid_search_returns_best_weights():
    history = _hist_predictive(250, seed=42)
    train = [h for h in history if date.fromisoformat(h["date"]) < date(2023, 1, 1)]
    out = grid_search_weights(train, k=5, grid_step=0.5, exclude_buffer_days=60)
    assert "best_weights" in out
    assert "hit_rate_train" in out
    assert 0.0 <= out["hit_rate_train"] <= 1.0
    # Pesos somam a aproximadamente 1.0
    s = sum(out["best_weights"].values())
    assert s == pytest.approx(1.0, abs=0.05)


# ═══════════════════════════════════════════════════════════════════════════════
# 6. validate_holdout
# ═══════════════════════════════════════════════════════════════════════════════
def test_validate_holdout_returns_metrics():
    history = _hist_predictive(300, seed=42)
    train   = [h for h in history if date.fromisoformat(h["date"]) <  date(2023, 1, 1)]
    holdout = [h for h in history if date.fromisoformat(h["date"]) >= date(2023, 1, 1)]
    w = {"price_action": 0.0, "nupl_proxy": 0.5, "ath_dd": 0.0, "wma_distance": 0.0, "momentum": 0.5}
    out = validate_holdout(holdout, train, weights=w, k=5)
    for k in ("hit_rate_holdout", "n_holdout"):
        assert k in out
    assert 0.0 <= out["hit_rate_holdout"] <= 1.0


# ═══════════════════════════════════════════════════════════════════════════════
# 7. decide: PASS / FAIL_OVERFIT / FAIL_NO_EDGE
# ═══════════════════════════════════════════════════════════════════════════════
def test_decide_pass():
    assert decide(train_hit=0.78, holdout_hit=0.70) == "PASS"


def test_decide_fail_overfit():
    # gap > 15pp mas train acima de threshold
    assert decide(train_hit=0.85, holdout_hit=0.55) == "FAIL_OVERFIT"


def test_decide_fail_no_edge_low_train():
    assert decide(train_hit=0.55, holdout_hit=0.50) == "FAIL_NO_EDGE"


def test_decide_fail_no_edge_low_holdout():
    assert decide(train_hit=0.72, holdout_hit=0.59) == "FAIL_NO_EDGE"


# ═══════════════════════════════════════════════════════════════════════════════
# 8. recalibrate -- pipeline completo + schema
# ═══════════════════════════════════════════════════════════════════════════════
def test_recalibrate_full_pipeline_schema(tmp_path):
    history = _hist_predictive(280, seed=42)
    current = {
        "btc_price": 79000,
        "regime":   "TRANSITION_DOWN",
        "features": _feat(price_action=-10, nupl=0.42, ath_dd=-27, wma=35, momentum=-15),
    }
    out = recalibrate(
        task2_matrix=_matrix_stub(),
        history=history,
        current_state=current,
        train_end_iso="2023-01-01",
        holdout_end_iso="2026-01-01",
        k=5,
        grid_step=0.5,
    )
    # Schema obrigatorio
    for key in (
        "timestamp", "best_weights",
        "hit_rate_train", "hit_rate_holdout", "gap",
        "current_state", "scenarios_60d", "prediction",
        "decision", "honest_note",
    ):
        assert key in out, f"falta '{key}'"
    # Decision e label valido
    assert out["decision"] in ("PASS", "FAIL_OVERFIT", "FAIL_NO_EDGE")
    # scenarios somam 100
    sc = out["scenarios_60d"]
    total = sc["bull_probability"] + sc["sideways_probability"] + sc["bear_probability"]
    assert total == pytest.approx(100, abs=0.5)
    # honest_note nao vazio
    assert isinstance(out["honest_note"], str) and len(out["honest_note"]) > 20
    # Serializa JSON
    json.dumps(out, default=str)


def test_recalibrate_detects_overfit_when_holdout_pattern_inverts():
    history = _hist_predictive(280, seed=42, holdout_drift=True)
    current = {"btc_price": 79000, "regime": "TRANSITION_DOWN",
               "features": _feat(price_action=-10, nupl=0.42, ath_dd=-27, wma=35, momentum=-15)}
    out = recalibrate(
        task2_matrix=_matrix_stub(),
        history=history,
        current_state=current,
        train_end_iso="2023-01-01",
        holdout_end_iso="2026-01-01",
        k=5, grid_step=0.5,
    )
    # Drift forte deve aparecer como FAIL_OVERFIT ou FAIL_NO_EDGE no holdout
    assert out["decision"] in ("FAIL_OVERFIT", "FAIL_NO_EDGE")
    assert out["gap"] != 0.0


def test_recalibrate_honest_note_mentions_decision():
    history = _hist_predictive(200, seed=42)
    current = {"btc_price": 79000, "regime": "TRANSITION_DOWN",
               "features": _feat(price_action=-10, nupl=0.42, ath_dd=-27, wma=35, momentum=-15)}
    out = recalibrate(
        task2_matrix=_matrix_stub(),
        history=history, current_state=current,
        train_end_iso="2023-01-01", holdout_end_iso="2026-01-01",
        k=5, grid_step=0.5,
    )
    note = out["honest_note"].lower()
    # Menciona o veredito ou o gap explicitamente
    assert ("pass" in note or "fail" in note or "edge" in note or "overfit" in note
            or "gap" in note or "holdout" in note)
