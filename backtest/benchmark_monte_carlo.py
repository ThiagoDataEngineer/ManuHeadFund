"""
benchmark_monte_carlo.py -- Monte Carlo Drawdown Simulation (Benchmarking V2 — Chat 3)

Pergunta respondida:
    "O DD que observei em backtest foi tipico, sorte ou azar?
     Que DD esperar nos piores cenarios?"

Metodo:
    Para cada run (btc_in_sample, etc), embaralha os trades 10.000x e mede
    DD maximo de cada permutacao. A distribuicao de DDs revela P50/P75/P95/P99.

Entrada (input JSON, default: journal/benchmark_baseline_v2_results.json):
    {
      "runs": [
        { "run_id": "btc_in_sample", "trades_r": [+1.0, -1.0, +2.5, ...] },
        ...
      ]
    }

Saida (default: journal/benchmark_monte_carlo_results.json):
    Schema completo descrito em AGENTS.md / spec da missao.

CLI:
    python backtest/benchmark_monte_carlo.py --simulations 10000 --runs all
    python backtest/benchmark_monte_carlo.py --input <path> --output <path>
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from typing import Dict, Iterable, List, Sequence

import numpy as np


DEFAULT_INPUT  = os.path.join("journal", "benchmark_baseline_v2_results.json")
DEFAULT_OUTPUT = os.path.join("journal", "benchmark_monte_carlo_results.json")
DEFAULT_SEED   = 42
DEFAULT_N_SIMS = 10_000
DD_THRESHOLDS  = (15, 20, 25, 30)
GO_LIVE_DD_THRESHOLD_R = 20.0  # criterio: P95 DD <= 20R em todos os runs


# ─────────────────────────────────────────────────────────────────────────────
# Numericos puros (testaveis sem IO)
# ─────────────────────────────────────────────────────────────────────────────

def compute_max_dd(equity_curve: np.ndarray) -> float:
    """Maximum drawdown (em R) de uma curva de equity acumulada. Sempre >= 0."""
    if equity_curve.size == 0:
        return 0.0
    peaks = np.maximum.accumulate(equity_curve)
    return float((peaks - equity_curve).max())


def simulate_max_dds(trades_r: Sequence[float], n_sims: int = DEFAULT_N_SIMS,
                     seed: int = DEFAULT_SEED) -> np.ndarray:
    """
    Embaralha trades n_sims vezes e retorna array (n_sims,) de DDs maximos.
    Trades vazios -> array de zeros (handles_zero_trades_gracefully).
    """
    arr = np.asarray(trades_r, dtype=float)
    if arr.size == 0:
        return np.zeros(n_sims, dtype=float)

    rng = np.random.default_rng(seed)
    dds = np.empty(n_sims, dtype=float)
    for i in range(n_sims):
        shuffled = rng.permutation(arr)
        equity   = np.cumsum(shuffled)
        peaks    = np.maximum.accumulate(equity)
        dds[i]   = (peaks - equity).max()
    return dds


def compute_probabilities(mc_dds: np.ndarray,
                          thresholds: Iterable[int] = DD_THRESHOLDS) -> Dict[str, float]:
    """P(DD > threshold) para cada threshold em R."""
    n = max(mc_dds.size, 1)
    out: Dict[str, float] = {}
    for t in thresholds:
        out[f"p_dd_above_{int(t)}R"] = float((mc_dds > t).sum()) / n
    return out


def classify_verdict(original_dd: float, mc_dds: np.ndarray) -> str:
    """
    DD_LUCKY    : DD original < P25 da distribuicao MC
    DD_UNLUCKY  : DD original > P75
    DD_TYPICAL  : entre P25 e P75
    """
    if mc_dds.size == 0:
        return "DD_TYPICAL"
    p25 = float(np.percentile(mc_dds, 25))
    p75 = float(np.percentile(mc_dds, 75))
    if original_dd < p25:
        return "DD_LUCKY"
    if original_dd > p75:
        return "DD_UNLUCKY"
    return "DD_TYPICAL"


def _percentile_rank(value: float, sample: np.ndarray) -> float:
    """Percentil do `value` dentro de `sample` (0-100)."""
    if sample.size == 0:
        return 50.0
    return float((sample <= value).sum()) / sample.size * 100.0


# ─────────────────────────────────────────────────────────────────────────────
# Pipeline
# ─────────────────────────────────────────────────────────────────────────────

def _analyse_run(run: Dict, n_sims: int, seed: int) -> Dict:
    run_id   = run.get("run_id", "unnamed")
    trades_r = list(run.get("trades_r", []) or [])

    # DD historico (caminho real observado)
    if trades_r:
        equity_hist = np.cumsum(np.asarray(trades_r, dtype=float))
        original_dd = compute_max_dd(equity_hist)
    else:
        original_dd = 0.0

    mc = simulate_max_dds(trades_r, n_sims=n_sims, seed=seed)

    return {
        "run_id":         run_id,
        "original_trades": len(trades_r),
        "original_dd_R":  round(original_dd, 3),
        "monte_carlo": {
            "dd_p50":  round(float(np.percentile(mc, 50)), 3) if mc.size else 0.0,
            "dd_p75":  round(float(np.percentile(mc, 75)), 3) if mc.size else 0.0,
            "dd_p95":  round(float(np.percentile(mc, 95)), 3) if mc.size else 0.0,
            "dd_p99":  round(float(np.percentile(mc, 99)), 3) if mc.size else 0.0,
            "dd_max":  round(float(mc.max()),  3) if mc.size else 0.0,
            "dd_mean": round(float(mc.mean()), 3) if mc.size else 0.0,
            "probabilities": compute_probabilities(mc, DD_THRESHOLDS),
            "rank_original_dd_percentile": round(_percentile_rank(original_dd, mc), 1),
        },
        "verdict": classify_verdict(original_dd, mc),
    }


def run_monte_carlo(runs_input: List[Dict], n_sims: int = DEFAULT_N_SIMS,
                    seed: int = DEFAULT_SEED) -> Dict:
    """Pipeline completo: cada run -> percentis + verdict; agrega summary + criterio."""
    runs_out = [_analyse_run(r, n_sims=n_sims, seed=seed) for r in runs_input]

    p95s = [r["monte_carlo"]["dd_p95"] for r in runs_out] or [0.0]
    p99s = [r["monte_carlo"]["dd_p99"] for r in runs_out] or [0.0]
    max_p95 = float(max(p95s))
    passed  = max_p95 <= GO_LIVE_DD_THRESHOLD_R

    # Robustness: fracao de runs onde P95 <= criterio.
    n_runs   = max(len(runs_out), 1)
    robust_n = sum(1 for v in p95s if v <= GO_LIVE_DD_THRESHOLD_R)
    robustness_score = round(robust_n / n_runs, 3)

    return {
        "timestamp":      datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "n_simulations":  n_sims,
        "random_seed":    seed,
        "runs":           runs_out,
        "summary": {
            "median_p95_dd_R":  round(float(np.median(p95s)), 3),
            "max_p99_dd_R":     round(float(max(p99s)), 3),
            "robustness_score": robustness_score,
        },
        "go_live_criterion": {
            "rule":                f"P95 DD <= {int(GO_LIVE_DD_THRESHOLD_R)}R em todos os runs",
            "max_p95_across_runs": round(max_p95, 3),
            "passed":              bool(passed),
            "explanation": (
                f"Em 95% das simulacoes, DD fica abaixo de {int(GO_LIVE_DD_THRESHOLD_R)}R."
                if passed
                else f"Pelo menos um run tem P95 acima de {int(GO_LIVE_DD_THRESHOLD_R)}R -- nao liberar live."
            ),
        },
    }


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def _load_runs(input_path: str) -> List[Dict]:
    if not os.path.exists(input_path):
        # Fallback demo: sintetico para o output ser inspecionavel mesmo sem Chat 1/2
        rng = np.random.default_rng(0)
        runs = []
        for run_id, n, win_rate in [
            ("btc_in_sample",  86,  0.55),
            ("btc_out_sample", 42,  0.50),
            ("eth_in_sample",  64,  0.52),
        ]:
            outcomes = rng.choice([2.0, -1.0], size=n, p=[win_rate, 1 - win_rate])
            runs.append({"run_id": run_id, "trades_r": outcomes.tolist()})
        sys.stderr.write(
            f"[MonteCarlo] Input nao encontrado em {input_path} -- usando dados sinteticos demo.\n"
        )
        return runs

    with open(input_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    runs = data.get("runs", [])
    if not isinstance(runs, list):
        raise ValueError(f"Formato invalido em {input_path}: esperado 'runs' (lista)")
    return runs


def _filter_runs(runs: List[Dict], selector: str) -> List[Dict]:
    if selector == "all":
        return runs
    wanted = {s.strip() for s in selector.split(",")}
    return [r for r in runs if r.get("run_id") in wanted]


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--simulations", type=int, default=DEFAULT_N_SIMS,
                        help=f"Numero de permutacoes Monte Carlo (default {DEFAULT_N_SIMS})")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--input",  default=DEFAULT_INPUT)
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--runs",   default="all",
                        help="'all' ou lista CSV de run_ids (ex: btc_in_sample,btc_out_sample)")
    args = parser.parse_args(argv)

    runs_input = _filter_runs(_load_runs(args.input), args.runs)
    if not runs_input:
        sys.stderr.write("[MonteCarlo] Nenhum run para processar.\n")
        return 2

    result = run_monte_carlo(runs_input, n_sims=args.simulations, seed=args.seed)

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    sys.stdout.write(
        f"[MonteCarlo] {len(runs_input)} run(s), {args.simulations} sims. "
        f"Criterio passed={result['go_live_criterion']['passed']} "
        f"(max_p95={result['go_live_criterion']['max_p95_across_runs']}R). "
        f"-> {args.output}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
