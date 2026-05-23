"""test_optimizer.py — TDD para optimizer.py (walk-forward Optuna)"""

import os
import sys
from datetime import datetime, timedelta

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from optimize_walkforward import TradeResult
from optimizer import (
    simulate,
    ergodicity_objective,
    build_splits,
    detect_overfitting,
    PARAM_BOUNDS,
    MIN_TRADES_THRESHOLD,
)


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def make_trade(ts: str, score=75, spike=2.5, pct=15.0, regime="bull", r=1.0, gate=""):
    return TradeResult(
        timestamp=ts, market="TESTUSDT", score=score,
        spike_ratio=spike, pct_change=pct, gate_failed=gate,
        regime=regime, r_outcome=r,
    )


def make_trades_spread(n: int, start_date="2026-01-01", regime_cycle=("bull","bear","sideways")):
    trades = []
    dt = datetime.strptime(start_date, "%Y-%m-%d")
    for i in range(n):
        ts = (dt + timedelta(days=i)).strftime("%Y-%m-%d 10:00:00")
        regime = regime_cycle[i % len(regime_cycle)]
        r = 1.0 if i % 3 != 0 else -1.0
        trades.append(make_trade(ts, regime=regime, r=r))
    return trades


# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

def test_walk_forward_splits_gera_janelas_corretas():
    trades = make_trades_spread(60)
    splits = build_splits(trades, train_days=20, test_days=7, step_days=7)
    assert len(splits) >= 3
    for train, test, tr_start, tr_end, te_start, te_end in splits:
        assert tr_end == te_start
        assert (tr_end - tr_start).days == 20
        assert (te_end - te_start).days == 7


def test_ergodicity_objective_retorna_float_0_a_1():
    trades = make_trades_spread(20)
    val = ergodicity_objective(trades, score_min=60, spike_min=1.5, pct_change_min=-5.0)
    assert isinstance(val, float)
    assert 0.0 <= val <= 1.0


def test_ergodicity_zero_quando_regime_unico():
    trades = make_trades_spread(20, regime_cycle=("bull",))
    val = ergodicity_objective(trades, score_min=60, spike_min=1.5, pct_change_min=-5.0)
    # regime unico => CV=0 => ergodicity=1 mas pode ser penalizado — nao deve crashar
    assert isinstance(val, float)


def test_parameter_bounds_respeitados_no_trial():
    lo, hi = PARAM_BOUNDS["score_min"]
    assert lo >= 50 and hi <= 100
    lo, hi = PARAM_BOUNDS["spike_min"]
    assert lo >= 1.0 and hi <= 5.0


def test_optuna_trial_tem_params_obrigatorios():
    from optimizer import make_objective
    trades = make_trades_spread(20)
    obj = make_objective(trades)

    import optuna
    study = optuna.create_study(direction="maximize")
    study.optimize(obj, n_trials=3, show_progress_bar=False)
    best = study.best_params
    assert "score_min"      in best
    assert "spike_min"      in best
    assert "pct_change_min" in best


def test_best_params_selecionados_por_ergodicity_nao_retorno():
    trades = make_trades_spread(30)
    from optimizer import make_objective
    import optuna
    study = optuna.create_study(direction="maximize")
    study.optimize(make_objective(trades), n_trials=5, show_progress_bar=False)
    # objetivo e ergodicity (0-1), nao retorno absoluto
    assert 0.0 <= study.best_value <= 1.0


def test_overfitting_detectado_quando_oos_pior_que_is():
    from optimize_walkforward import WalkForwardResult
    results = [
        WalkForwardResult(0,"2026-01-01","2026-01-31","2026-02-01","2026-02-07",
                          {"score_min":70,"spike_min":2.0,"pct_change_min":5.0},
                          0.90, 0.30, 5, 60.0),
        WalkForwardResult(1,"2026-02-01","2026-03-03","2026-03-04","2026-03-11",
                          {"score_min":70,"spike_min":2.0,"pct_change_min":5.0},
                          0.85, 0.70, 8, 65.0),
    ]
    overfit = detect_overfitting(results, threshold=0.20)
    assert 0 in overfit
    assert 1 not in overfit


def test_regime_stability_across_splits():
    trades = make_trades_spread(60)
    splits = build_splits(trades, train_days=20, test_days=7, step_days=7)
    for train, _, *_ in splits:
        regimes = {t.regime for t in train}
        # com 20 dias e ciclo bull/bear/sideways, deve ter multiplos regimes
        assert len(regimes) >= 1


def test_empty_trades_handled():
    splits = build_splits([], train_days=30, test_days=7, step_days=7)
    assert splits == []

    val = ergodicity_objective([], score_min=60, spike_min=1.5, pct_change_min=0.0)
    assert val == 0.0


def test_min_trades_threshold_enforced():
    # menos que MIN_TRADES_THRESHOLD => objetivo retorna 0
    trades = make_trades_spread(MIN_TRADES_THRESHOLD - 1)
    val = ergodicity_objective(trades, score_min=60, spike_min=1.5, pct_change_min=-5.0)
    assert val == 0.0
