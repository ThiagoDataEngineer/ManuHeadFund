"""
optimize_walkforward.py — Optuna walk-forward com ergodicity_score como objetivo
Referências: Melão/Saturno V (ergodicidade), Optuna (Akiba et al. 2019)

Uso:
    python backtest/optimize_walkforward.py --market BTCUSDT --n_trials 100
    python backtest/optimize_walkforward.py --journal journal/gem_signals.csv --n_trials 50
"""

import argparse
import csv
import json
import math
import os
import sys
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple

try:
    import optuna
    optuna.logging.set_verbosity(optuna.logging.WARNING)
except ImportError:
    print("Optuna não instalado. Execute: pip install optuna")
    sys.exit(1)

from metrics import calc_metrics_by_regime, RegimeBreakdown

# ─────────────────────────────────────────────────────────────────────────────
# Estruturas de dados
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class TradeResult:
    timestamp: str
    market: str
    score: int
    spike_ratio: float
    pct_change: float
    gate_failed: str
    regime: str          # bull / bear / sideways (classificado por BTC price)
    r_outcome: float     # resultado em R — preenchido após o trade fechar


@dataclass
class WalkForwardResult:
    window_id: int
    train_start: str
    train_end: str
    test_start: str
    test_end: str
    best_params: Dict
    train_ergodicity: float
    test_ergodicity: float
    test_trades: int
    test_win_rate: float


# ─────────────────────────────────────────────────────────────────────────────
# Leitura do journal
# ─────────────────────────────────────────────────────────────────────────────

def load_journal(path: str) -> List[TradeResult]:
    """Lê gem_signals.csv e retorna trades com outcome real (pct_exit conhecido)."""
    if not os.path.exists(path):
        print(f"Journal não encontrado: {path}")
        return []

    trades = []
    with open(path, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                score = int(float(row.get("score", 0)))
                spike = float(row.get("spike_ratio", 0))
                pct   = float(row.get("pct_change_today", 0))
                gate  = row.get("gate_failed", "")
                ts    = row.get("timestamp", "")

                # outcome_r: se tiver price_exit no CSV usa-o; senão usa pct_change como proxy
                # (proxy válido para backtesting inicial — substituir por preço real quando disponível)
                price_entry = float(row.get("price_at_scan") or 0)
                r_outcome   = float(row.get("r_outcome") or 0)

                trades.append(TradeResult(
                    timestamp=ts,
                    market=row.get("market", ""),
                    score=score,
                    spike_ratio=spike,
                    pct_change=pct,
                    gate_failed=gate,
                    regime=row.get("regime", "sideways"),   # enriquecido externamente
                    r_outcome=r_outcome,
                ))
            except (ValueError, KeyError):
                continue

    return trades


# ─────────────────────────────────────────────────────────────────────────────
# Simulação com parâmetros do trial
# ─────────────────────────────────────────────────────────────────────────────

def simulate_with_params(
    trades: List[TradeResult],
    score_min: int,
    spike_min: float,
    pct_change_min: float,
) -> Tuple[List[float], List[str]]:
    """
    Filtra trades pelos parâmetros e retorna (r_series, regimes).
    Apenas trades aprovados (gate_failed vazio) e que passam nos thresholds.
    """
    r_series = []
    regimes  = []

    for t in trades:
        if t.gate_failed:
            continue   # bloqueado — não é um sinal de entrada
        if t.score < score_min:
            continue
        if t.spike_ratio < spike_min:
            continue
        if t.pct_change < pct_change_min:
            continue

        r_series.append(t.r_outcome)
        regimes.append(t.regime if t.regime in {"bull","bear","sideways"} else "sideways")

    return r_series, regimes


# ─────────────────────────────────────────────────────────────────────────────
# Objetivo Optuna: maximizar ergodicity_score
# ─────────────────────────────────────────────────────────────────────────────

def make_objective(train_trades: List[TradeResult]):
    def objective(trial: optuna.Trial) -> float:
        score_min     = trial.suggest_int("score_min", 60, 90)
        spike_min     = trial.suggest_float("spike_min", 1.5, 4.0, step=0.1)
        pct_change_min= trial.suggest_float("pct_change_min", -5.0, 20.0, step=1.0)

        r_series, regimes = simulate_with_params(train_trades, score_min, spike_min, pct_change_min)

        if len(r_series) < 5:
            return 0.0   # dados insuficientes — penaliza trial

        try:
            breakdown: RegimeBreakdown = calc_metrics_by_regime(r_series, regimes)
        except ValueError:
            return 0.0

        ergodicity = breakdown.ergodicity_score

        # Penaliza estratégias com poucos trades (overfitting em poucos sinais)
        trade_penalty = max(0.0, 1.0 - (10 / max(len(r_series), 1)))
        # Penaliza expectância negativa mesmo com alta ergodicidade
        expectancy_penalty = 1.0 if breakdown.combined.expectancy_r >= 0 else 0.5

        return ergodicity * trade_penalty * expectancy_penalty

    return objective


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
    """
    Walk-forward:
      - Janela treino: train_days dias
      - Janela teste: test_days dias
      - Avança step_days por iteração
    """
    if not trades:
        print("Nenhum trade no journal com outcome real.")
        return []

    # Ordenar por timestamp
    def parse_ts(t: TradeResult):
        try:
            return datetime.strptime(t.timestamp[:19], "%Y-%m-%d %H:%M:%S")
        except ValueError:
            return datetime.min

    trades_sorted = sorted(trades, key=parse_ts)
    if not trades_sorted:
        return []

    start_dt = parse_ts(trades_sorted[0])
    end_dt   = parse_ts(trades_sorted[-1])

    results = []
    window_id = 0
    cursor = start_dt

    while cursor + timedelta(days=train_days + test_days) <= end_dt:
        train_start = cursor
        train_end   = cursor + timedelta(days=train_days)
        test_start  = train_end
        test_end    = train_end + timedelta(days=test_days)

        train_trades = [t for t in trades_sorted if train_start <= parse_ts(t) < train_end]
        test_trades  = [t for t in trades_sorted if test_start  <= parse_ts(t) < test_end ]

        if len(train_trades) < 5:
            cursor += timedelta(days=step_days)
            continue

        print(f"[Window {window_id}] Train: {train_start.date()} → {train_end.date()}  "
              f"({len(train_trades)} trades)  |  Test: {test_start.date()} → {test_end.date()} "
              f"({len(test_trades)} trades)")

        study = optuna.create_study(direction="maximize")
        study.optimize(make_objective(train_trades), n_trials=n_trials, show_progress_bar=False)

        best = study.best_params
        train_ergodicity = study.best_value

        # Avaliar no teste com os melhores params
        test_r, test_reg = simulate_with_params(
            test_trades,
            score_min=best["score_min"],
            spike_min=best["spike_min"],
            pct_change_min=best["pct_change_min"],
        )

        test_ergodicity = 0.0
        test_wr         = 0.0
        if len(test_r) >= 2:
            try:
                tb = calc_metrics_by_regime(test_r, test_reg)
                test_ergodicity = tb.ergodicity_score
                test_wr         = tb.combined.win_rate
            except ValueError:
                pass

        results.append(WalkForwardResult(
            window_id=window_id,
            train_start=str(train_start.date()),
            train_end=str(train_end.date()),
            test_start=str(test_start.date()),
            test_end=str(test_end.date()),
            best_params=best,
            train_ergodicity=round(train_ergodicity, 3),
            test_ergodicity=round(test_ergodicity, 3),
            test_trades=len(test_r),
            test_win_rate=round(test_wr, 1),
        ))

        cursor += timedelta(days=step_days)
        window_id += 1

    return results


# ─────────────────────────────────────────────────────────────────────────────
# Relatório
# ─────────────────────────────────────────────────────────────────────────────

def print_report(results: List[WalkForwardResult]) -> None:
    if not results:
        print("Nenhum resultado de walk-forward.")
        return

    print("\n" + "=" * 70)
    print("  WALK-FORWARD REPORT — ergodicity_score como objetivo")
    print("=" * 70)
    print(f"{'Win':<4} {'Train':<12} {'Test':<12} {'score_min':<10} {'spike':<7} {'pct_min':<8} {'Train E':<9} {'Test E':<9} {'WR%'}")
    print("-" * 70)

    for r in results:
        p = r.best_params
        flag = "✓" if r.test_ergodicity >= 0.70 else "·"
        print(f"{flag:<4} {r.train_start:<12} {r.test_start:<12} "
              f"{p.get('score_min','-'):<10} {p.get('spike_min','-'):<7} "
              f"{p.get('pct_change_min','-'):<8} {r.train_ergodicity:<9} "
              f"{r.test_ergodicity:<9} {r.test_win_rate}")

    # Parâmetros mais robustos: mediana dos windows com test_ergodicity >= 0.70
    robust = [r for r in results if r.test_ergodicity >= 0.70]
    if robust:
        def median(lst): s = sorted(lst); n = len(s); return s[n//2] if n%2 else (s[n//2-1]+s[n//2])/2
        print(f"\n  Parâmetros robustos (mediana, {len(robust)}/{len(results)} windows ≥ 0.70):")
        print(f"  score_min     = {int(median([r.best_params['score_min']     for r in robust]))}")
        print(f"  spike_min     = {round(median([r.best_params['spike_min']     for r in robust]),1)}")
        print(f"  pct_change_min= {round(median([r.best_params['pct_change_min'] for r in robust]),1)}")
    else:
        print("\n  Nenhum window atingiu ergodicity ≥ 0.70. Dados insuficientes ou parâmetros a revisar.")

    print("=" * 70)


def save_results(results: List[WalkForwardResult], out_path: str) -> None:
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump([asdict(r) for r in results], f, indent=2, ensure_ascii=False)
    print(f"\n  Resultados salvos em: {out_path}")


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Optuna walk-forward com ergodicity_score")
    parser.add_argument("--journal",    default="journal/gem_signals.csv", help="Caminho do journal CSV")
    parser.add_argument("--n_trials",   type=int, default=50,  help="Trials Optuna por janela")
    parser.add_argument("--train_days", type=int, default=30,  help="Dias de treino por janela")
    parser.add_argument("--test_days",  type=int, default=7,   help="Dias de teste por janela")
    parser.add_argument("--step_days",  type=int, default=7,   help="Avanço entre janelas")
    parser.add_argument("--out",        default="journal/walkforward_results.json", help="Arquivo de saída JSON")
    args = parser.parse_args()

    print(f"Carregando journal: {args.journal}")
    trades = load_journal(args.journal)
    print(f"  {len(trades)} registros carregados")

    trades_with_outcome = [t for t in trades if t.r_outcome != 0]
    print(f"  {len(trades_with_outcome)} com outcome real (r_outcome ≠ 0)")

    if len(trades_with_outcome) < 10:
        print("\n  AVISO: Journal tem menos de 10 trades com outcome real.")
        print("  O walk-forward precisa de dados reais acumulados para ser significativo.")
        print("  Continue acumulando trades por pelo menos 30 dias antes de otimizar.")
        sys.exit(0)

    results = run_walkforward(
        trades_with_outcome,
        train_days=args.train_days,
        test_days=args.test_days,
        n_trials=args.n_trials,
        step_days=args.step_days,
    )

    print_report(results)
    if results:
        save_results(results, args.out)
