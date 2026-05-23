"""
test_benchmark_monte_carlo.py -- TDD para Monte Carlo Drawdown Simulation.

Contrato testado:
    simulate_max_dds(trades_r, n_sims, seed) -> np.ndarray (n_sims,)
    compute_max_dd(equity_curve)             -> float (>= 0)
    classify_verdict(original_dd, mc_dds)    -> "DD_TYPICAL"|"DD_LUCKY"|"DD_UNLUCKY"
    compute_probabilities(mc_dds, thresholds)-> dict { f"p_dd_above_{t}R": float }
    run_monte_carlo(runs_input, n_sims, seed)-> output JSON dict (schema spec)
"""
from __future__ import annotations

import json
import os
import sys
import numpy as np
import pytest

# Permite importar benchmark_monte_carlo do diretorio pai
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from benchmark_monte_carlo import (  # noqa: E402
    classify_verdict,
    compute_max_dd,
    compute_probabilities,
    run_monte_carlo,
    simulate_max_dds,
)


# ─────────────────────────────────────────────────────────────────────────────
# 1. Shuffle preserva o conjunto de trades
# ─────────────────────────────────────────────────────────────────────────────
def test_shuffle_preserves_trade_set():
    trades = [1.0, -1.0, 2.5, -0.5, 3.0, -2.0]
    rng = np.random.default_rng(42)
    shuffled = rng.permutation(np.asarray(trades, dtype=float))
    assert sorted(shuffled.tolist()) == sorted(trades)


# ─────────────────────────────────────────────────────────────────────────────
# 2. Equity acumulada via cumsum
# ─────────────────────────────────────────────────────────────────────────────
def test_cumulative_equity_correct():
    trades = np.array([1.0, -2.0, 3.0, -1.0])
    equity = np.cumsum(trades)
    assert equity.tolist() == [1.0, -1.0, 2.0, 1.0]


# ─────────────────────────────────────────────────────────────────────────────
# 3. Max DD em sequencia conhecida
#   trades: [+5, -10, +2, -3] -> equity [5, -5, -3, -6] -> peaks [5,5,5,5] -> dd max 11
# ─────────────────────────────────────────────────────────────────────────────
def test_max_dd_known_sequence():
    equity = np.cumsum(np.array([5.0, -10.0, 2.0, -3.0]))
    dd = compute_max_dd(equity)
    assert dd == pytest.approx(11.0)


def test_max_dd_monotonic_up_is_zero():
    equity = np.cumsum(np.array([1.0, 2.0, 3.0]))
    assert compute_max_dd(equity) == pytest.approx(0.0)


# ─────────────────────────────────────────────────────────────────────────────
# 4. Percentis batem com np.percentile
# ─────────────────────────────────────────────────────────────────────────────
def test_percentile_calculation():
    trades = [1.0, -1.0, 2.0, -2.0, 1.5, -0.5]
    mc = simulate_max_dds(trades, n_sims=2000, seed=42)
    p50 = float(np.percentile(mc, 50))
    p95 = float(np.percentile(mc, 95))
    assert p95 >= p50  # invariante de percentis


# ─────────────────────────────────────────────────────────────────────────────
# 5. Seed reproduz resultados
# ─────────────────────────────────────────────────────────────────────────────
def test_seed_reproducibility():
    trades = [1.0, -1.0, 2.5, -0.5, 3.0, -2.0, 0.8, -1.2]
    a = simulate_max_dds(trades, n_sims=500, seed=42)
    b = simulate_max_dds(trades, n_sims=500, seed=42)
    assert np.array_equal(a, b)


def test_different_seed_produces_different_results():
    trades = [1.0, -1.0, 2.5, -0.5, 3.0, -2.0, 0.8, -1.2]
    a = simulate_max_dds(trades, n_sims=500, seed=42)
    b = simulate_max_dds(trades, n_sims=500, seed=999)
    assert not np.array_equal(a, b)


# ─────────────────────────────────────────────────────────────────────────────
# 6. Probabilidade de DD acima de threshold
# ─────────────────────────────────────────────────────────────────────────────
def test_probability_dd_above_threshold():
    mc = np.array([5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 8.0, 12.0])
    probs = compute_probabilities(mc, thresholds=[15, 20, 25, 30])
    # strict >; 15.0/20.0/25.0/30.0 nao contam para seus respectivos thresholds
    # > 15: 20,25,30,35,40 = 5; > 20: 25,30,35,40 = 4; > 25: 30,35,40 = 3; > 30: 35,40 = 2
    assert probs["p_dd_above_15R"] == pytest.approx(0.5)
    assert probs["p_dd_above_20R"] == pytest.approx(0.4)
    assert probs["p_dd_above_25R"] == pytest.approx(0.3)
    assert probs["p_dd_above_30R"] == pytest.approx(0.2)


# ─────────────────────────────────────────────────────────────────────────────
# 7. Verdictos: DD_TYPICAL / DD_LUCKY / DD_UNLUCKY
# ─────────────────────────────────────────────────────────────────────────────
def test_verdict_typical_unlucky_lucky():
    mc = np.linspace(1, 100, 100)  # P25=25.75, P75=75.25
    assert classify_verdict(50.0, mc) == "DD_TYPICAL"
    assert classify_verdict(10.0, mc) == "DD_LUCKY"
    assert classify_verdict(90.0, mc) == "DD_UNLUCKY"


# ─────────────────────────────────────────────────────────────────────────────
# 8. JSON schema valido (run_monte_carlo end-to-end)
# ─────────────────────────────────────────────────────────────────────────────
def test_json_schema_valid(tmp_path):
    runs_input = [
        {"run_id": "btc_in_sample", "trades_r": [1.0, -1.0, 2.0, -0.5, 1.5, -1.5, 0.8, -0.4, 1.2, -0.8]},
        {"run_id": "btc_out_sample", "trades_r": [0.5, -1.0, 1.5, -0.5, 1.0, -0.5, 0.5, -1.5]},
        {"run_id": "eth_in_sample", "trades_r": [1.0, -1.0, 2.0, -1.0, 1.5, -1.0, 0.5, -0.5]},
    ]
    out = run_monte_carlo(runs_input, n_sims=500, seed=42)

    # Top-level
    assert "timestamp" in out
    assert out["n_simulations"] == 500
    assert out["random_seed"] == 42
    assert len(out["runs"]) == 3

    # Run-level
    r = out["runs"][0]
    for key in ("run_id", "original_trades", "original_dd_R", "monte_carlo", "verdict"):
        assert key in r
    mc = r["monte_carlo"]
    for key in ("dd_p50", "dd_p75", "dd_p95", "dd_p99", "dd_max", "dd_mean",
                "probabilities", "rank_original_dd_percentile"):
        assert key in mc
    for k in ("p_dd_above_15R", "p_dd_above_20R", "p_dd_above_25R", "p_dd_above_30R"):
        assert k in mc["probabilities"]

    # Summary + go_live_criterion
    assert "median_p95_dd_R" in out["summary"]
    assert "max_p99_dd_R"    in out["summary"]
    assert "robustness_score" in out["summary"]
    glc = out["go_live_criterion"]
    for key in ("rule", "max_p95_across_runs", "passed", "explanation"):
        assert key in glc

    # Serializa para JSON puro (sem numpy floats)
    text = json.dumps(out)
    parsed = json.loads(text)
    assert parsed["runs"][0]["run_id"] == "btc_in_sample"


# ─────────────────────────────────────────────────────────────────────────────
# 9. Trades vazios nao quebram
# ─────────────────────────────────────────────────────────────────────────────
def test_handles_zero_trades_gracefully():
    out = simulate_max_dds([], n_sims=100, seed=42)
    assert len(out) == 100
    assert np.all(out == 0.0)

    runs_input = [{"run_id": "empty_run", "trades_r": []}]
    full = run_monte_carlo(runs_input, n_sims=100, seed=42)
    r = full["runs"][0]
    assert r["original_trades"] == 0
    assert r["original_dd_R"] == 0.0
    assert r["monte_carlo"]["dd_p95"] == 0.0


def test_p95_below_20R_pass_criterion():
    # Trades pequenos -> DDs pequenos -> P95 << 20
    trades = [0.5, -0.3, 0.4, -0.2, 0.6, -0.4, 0.5, -0.3] * 5
    runs_input = [
        {"run_id": "r1", "trades_r": trades},
        {"run_id": "r2", "trades_r": trades},
    ]
    out = run_monte_carlo(runs_input, n_sims=500, seed=42)
    assert out["go_live_criterion"]["passed"] is True
    assert out["go_live_criterion"]["max_p95_across_runs"] < 20.0
