"""
optimizer.py — Optuna walk-forward com ergodicity_score como objetivo
Refactor de optimize_walkforward.py com API testavel e separacao de responsabilidades.

Uso:
    python backtest/optimizer.py --journal journal/gem_signals.csv --n_trials 50
"""

import argparse
import json
import os
import sys
from dataclasses import dataclass, asdict, field
from datetime import datetime, timedelta
from typing import Dict, List, Tuple

try:
    import optuna
    optuna.logging.set_verbosity(optuna.logging.WARNING)
except ImportError:
    print("Optuna nao instalado. Execute: pip install optuna")
    sys.exit(1)

from optimize_walkforward import TradeResult, WalkForwardResult, load_journal
from metrics import calc_metrics_by_regime, RegimeBreakdown

# ─────────────────────────────────────────────────────────────────────────────
# Parametros do espaco de busca
# ─────────────────────────────────────────────────────────────────────────────

PARAM_BOUNDS = {
    "score_min":      (60,   90),
    "spike_min":      (1.5,  4.0),
    "pct_change_min": (-5.0, 20.0),
}

MIN_TRADES_THRESHOLD = 5   # minimo de trades para avaliar uma janela


# ─────────────────────────────────────────────────────────────────────────────
# Simulacao
# ─────────────────────────────────────────────────────────────────────────────

def simulate(
    trades: List[TradeResult],
    score_min: int,
    spike_min: float,
    pct_change_min: float,
) -> Tuple[List[float], List[str]]:
    """Filtra trades pelos parametros e retorna (r_series, regimes)."""
    r_series, regimes = [], []
    for t in trades:
        if t.gate_failed:
            continue
        if t.score < score_min:
            continue
        if t.spike_ratio < spike_min:
            continue
        if t.pct_change < pct_change_min:
            continue
        r_series.append(t.r_outcome)
        regimes.append(t.regime if t.regime in {"bull", "bear", "sideways"} else "sideways")
    return r_series, regimes


# ─────────────────────────────────────────────────────────────────────────────
# Objetivo Optuna
# ─────────────────────────────────────────────────────────────────────────────

def ergodicity_objective(
    trades: List[TradeResult],
    score_min: int,
    spike_min: float,
    pct_change_min: float,
) -> float:
    """
    Calcula o objetivo (ergodicity_score penalizado) para um conjunto de parametros.
    Retorna float em [0, 1]. Testavel diretamente sem Optuna Trial.
    """
    r_series, regimes = simulate(trades, score_min, spike_min, pct_change_min)

    if len(r_series) < MIN_TRADES_THRESHOLD:
        return 0.0

    try:
        breakdown: RegimeBreakdown = calc_metrics_by_regime(r_series, regimes)
    except ValueError:
        return 0.0

    ergodicity = breakdown.ergodicity_score
    trade_penalty      = max(0.0, 1.0 - (10 / max(len(r_series), 1)))
    expectancy_penalty = 1.0 if breakdown.combined.expectancy_r >= 0 else 0.5

    return ergodicity * trade_penalty * expectancy_penalty


def make_objective(train_trades: List[TradeResult]):
    """Retorna funcao objetivo compativel com optuna.Study.optimize."""
    def objective(trial: optuna.Trial) -> float:
        score_min      = trial.suggest_int("score_min",      *PARAM_BOUNDS["score_min"])
        spike_min      = trial.suggest_float("spike_min",    *PARAM_BOUNDS["spike_min"],      step=0.1)
        pct_change_min = trial.suggest_float("pct_change_min", *PARAM_BOUNDS["pct_change_min"], step=1.0)
        return ergodicity_objective(train_trades, score_min, spike_min, pct_change_min)
    return objective


# ─────────────────────────────────────────────────────────────────────────────
# Walk-forward splits
# ─────────────────────────────────────────────────────────────────────────────

def build_splits(
    trades: List[TradeResult],
    train_days: int = 30,
    test_days: int  = 7,
    step_days: int  = 7,
) -> List[Tuple[List[TradeResult], List[TradeResult], datetime, datetime, datetime, datetime]]:
    """
    Gera janelas (train, test, train_start, train_end, test_start, test_end).
    Testavel sem chamar Optuna.
    """
    if not trades:
        return []

    def parse_ts(t: TradeResult) -> datetime:
        try:
            return datetime.strptime(t.timestamp[:19], "%Y-%m-%d %H:%M:%S")
        except ValueError:
            return datetime.min

    sorted_trades = sorted(trades, key=parse_ts)
    start_dt = parse_ts(sorted_trades[0])
    end_dt   = parse_ts(sorted_trades[-1])

    splits = []
    cursor = start_dt
    while cursor + timedelta(days=train_days + test_days) <= end_dt:
        tr_start = cursor
        tr_end   = cursor + timedelta(days=train_days)
        te_start = tr_end
        te_end   = tr_end + timedelta(days=test_days)

        train = [t for t in sorted_trades if tr_start <= parse_ts(t) < tr_end]
        test  = [t for t in sorted_trades if te_start <= parse_ts(t) < te_end]

        if len(train) >= MIN_TRADES_THRESHOLD:
            splits.append((train, test, tr_start, tr_end, te_start, te_end))

        cursor += timedelta(days=step_days)

    return splits


# ─────────────────────────────────────────────────────────────────────────────
# Walk-forward engine
# ─────────────────────────────────────────────────────────────────────────────

def run_walkforward(
    trades: List[TradeResult],
    train_days: int = 30,
    test_days: int  = 7,
    n_trials: int   = 50,
    step_days: int  = 7,
) -> List[WalkForwardResult]:
    splits = build_splits(trades, train_days, test_days, step_days)
    if not splits:
        print("Nenhuma janela valida. Dados insuficientes.")
        return []

    results = []
    for i, (train, test, tr_start, tr_end, te_start, te_end) in enumerate(splits):
        print(f"[Window {i}] Train: {tr_start.date()} -> {tr_end.date()} "
              f"({len(train)} trades) | Test: {te_start.date()} -> {te_end.date()} ({len(test)} trades)")

        study = optuna.create_study(direction="maximize")
        study.optimize(make_objective(train), n_trials=n_trials, show_progress_bar=False)

        best             = study.best_params
        train_ergodicity = study.best_value

        test_r, test_reg = simulate(test, **best)
        test_ergodicity  = 0.0
        test_wr          = 0.0
        if len(test_r) >= 2:
            try:
                tb = calc_metrics_by_regime(test_r, test_reg)
                test_ergodicity = tb.ergodicity_score
                test_wr         = tb.combined.win_rate
            except ValueError:
                pass

        results.append(WalkForwardResult(
            window_id        = i,
            train_start      = str(tr_start.date()),
            train_end        = str(tr_end.date()),
            test_start       = str(te_start.date()),
            test_end         = str(te_end.date()),
            best_params      = best,
            train_ergodicity = round(train_ergodicity, 3),
            test_ergodicity  = round(test_ergodicity,  3),
            test_trades      = len(test_r),
            test_win_rate    = round(test_wr, 1),
        ))

    return results


def detect_overfitting(results: List[WalkForwardResult], threshold: float = 0.20) -> List[int]:
    """Retorna indices de janelas onde test_ergodicity < train_ergodicity - threshold."""
    return [
        r.window_id for r in results
        if r.train_ergodicity - r.test_ergodicity > threshold
    ]


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Optuna walk-forward com ergodicity_score")
    parser.add_argument("--journal",    default="journal/gem_signals.csv")
    parser.add_argument("--n_trials",   type=int, default=50)
    parser.add_argument("--train_days", type=int, default=30)
    parser.add_argument("--test_days",  type=int, default=7)
    parser.add_argument("--step_days",  type=int, default=7)
    parser.add_argument("--out",        default="journal/optimizer_results.json")
    args = parser.parse_args()

    from optimize_walkforward import print_report, save_results

    trades = load_journal(args.journal)
    trades_with_outcome = [t for t in trades if t.r_outcome != 0]
    print(f"  {len(trades)} registros | {len(trades_with_outcome)} com outcome real")

    if len(trades_with_outcome) < 10:
        print("  Dados insuficientes para walk-forward (minimo 10 trades com outcome).")
        sys.exit(0)

    results = run_walkforward(
        trades_with_outcome,
        train_days=args.train_days,
        test_days=args.test_days,
        n_trials=args.n_trials,
        step_days=args.step_days,
    )

    print_report(results)
    overfit = detect_overfitting(results)
    if overfit:
        print(f"  Atencao: overfitting detectado nas janelas {overfit}")

    if results:
        save_results(results, args.out)
