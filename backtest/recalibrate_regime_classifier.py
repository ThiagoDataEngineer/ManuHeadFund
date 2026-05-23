"""
recalibrate_regime_classifier.py — Grid search dos thresholds do classificador 8-state.

Hipótese investigada:
  - BULL_WEAK pode estar sobre-incluindo dias de transição.
  - SHORT em TRANSITION_DOWN pode ter edge com threshold mais conservador.

Metodologia:
  - Split: train 2014-2022 / holdout 2023-2025.
  - Grid sobre thresholds (ADX_STRONG, TRANSITION_BARS, SIDEWAYS_BAND, CAPITULATION).
  - Métrica: count de regimes com edge MEDIUM+ (exp >= +0.3R) E confidence != LOW.
  - Critério aceite: >= 3 regimes MEDIUM+ no TRAIN E confirmado no HOLDOUT.
  - Holdout NÃO recalibra (aplica thresholds escolhidos no train).

Decisão:
  PASS           : train_count >= 3 E holdout_count >= 3
  FAIL_OVERFIT   : train_count >= 3 E holdout_count < 3
  FAIL_NO_EDGE   : train_count < 3 (regardless of holdout)

NÃO MODIFICA: db.py, signal_generator.py, metrics.py.
Tested in: tests/test_recalibrate_regime_classifier.py (10 testes pytest TDD).

CLI:
    python recalibrate_regime_classifier.py
"""
import argparse
import json
import os
from itertools import product
from typing import Dict, Iterable, List, Optional, Tuple

from regime_8state_classifier import reclassify_trades_8state
from regime_direction_matrix import build_matrix_report


MIN_REGIMES_MEDIUM_PLUS = 3
MEDIUM_THRESHOLD = 0.3


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

def _year_of(trade: Dict) -> Optional[int]:
    ts = trade.get("entry_ts") or trade.get("bar_ts") or trade.get("exit_ts")
    if not ts:
        return None
    try:
        return int(str(ts)[:4])
    except (ValueError, TypeError):
        return None


# ----------------------------------------------------------------------------
# Split train/holdout
# ----------------------------------------------------------------------------

def split_train_holdout(
    trades: List[Dict],
    train_end_year: int = 2022,
    holdout_start_year: int = 2023,
) -> Tuple[List[Dict], List[Dict]]:
    """train = year <= train_end_year; holdout = year >= holdout_start_year."""
    train, holdout = [], []
    for t in trades:
        y = _year_of(t)
        if y is None:
            continue
        if y <= train_end_year:
            train.append(t)
        elif y >= holdout_start_year:
            holdout.append(t)
    return train, holdout


# ----------------------------------------------------------------------------
# Grid de thresholds
# ----------------------------------------------------------------------------

def generate_threshold_grid(
    adx_values: Iterable[float] = (20.0, 25.0, 30.0, 35.0),
    transition_bars_values: Iterable[int] = (10, 20, 30),
    sideways_band_values: Iterable[float] = (0.01, 0.02, 0.03),
    capitulation_values: Iterable[float] = (0.20, 0.25, 0.30),
) -> List[Dict]:
    """Produto cartesiano de thresholds → lista de combos."""
    grid = []
    for adx, tb, sb, cap in product(adx_values, transition_bars_values, sideways_band_values, capitulation_values):
        grid.append({
            "adx_strong":      float(adx),
            "transition_bars": int(tb),
            "sideways_band":   float(sb),
            "capitulation":    float(cap),
        })
    return grid


# ----------------------------------------------------------------------------
# Conta regimes MEDIUM+
# ----------------------------------------------------------------------------

def count_medium_plus_regimes(matrix: List[Dict]) -> int:
    """Conta regimes onde a melhor direção tem exp >= +0.3R E confidence != LOW."""
    n = 0
    for entry in matrix:
        if entry.get("confidence") == "LOW":
            continue
        long_exp  = entry.get("long",  {}).get("exp", 0.0) or 0.0
        short_exp = entry.get("short", {}).get("exp", 0.0) or 0.0
        best_exp = max(long_exp, short_exp)
        if best_exp >= MEDIUM_THRESHOLD:
            n += 1
    return n


# ----------------------------------------------------------------------------
# Evaluate combo: reclassifica + monta matriz + conta MEDIUM+
# ----------------------------------------------------------------------------

def evaluate_combo_on_trades(
    trades: List[Dict],
    candles: List[Dict],
    combo: Dict,
) -> Dict:
    """Aplica combo de thresholds, reclassifica trades e retorna matriz + count."""
    enriched = reclassify_trades_8state(
        trades,
        candles,
        adx_strong=combo["adx_strong"],
        transition_bars=combo["transition_bars"],
        sideways_band=combo["sideways_band"],
        capitulation=combo["capitulation"],
    )
    # Filtra para só os 8 regimes oficiais
    enriched_clean = []
    for t in enriched:
        r = t.get("regime")
        if r and r.startswith(("BULL_", "BEAR_", "TRANS", "SIDE", "CAPI")):
            enriched_clean.append(t)

    report = build_matrix_report(enriched_clean)
    matrix = report["matrix"]
    n = count_medium_plus_regimes(matrix)
    return {
        "combo":          combo,
        "matrix":         matrix,
        "n_medium_plus":  n,
    }


# ----------------------------------------------------------------------------
# Pick best
# ----------------------------------------------------------------------------

def pick_best_thresholds(evaluations: List[Dict]) -> Dict:
    """Escolhe o combo com maior n_medium_plus. Empate: menor adx_strong (mais inclusivo)."""
    if not evaluations:
        raise ValueError("evaluations vazio")
    return max(evaluations, key=lambda e: (e["n_medium_plus"], -e["combo"].get("adx_strong", 0)))


# ----------------------------------------------------------------------------
# Decisão
# ----------------------------------------------------------------------------

def decide_outcome(train_count: int, holdout_count: int) -> str:
    """PASS / FAIL_OVERFIT / FAIL_NO_EDGE conforme contagens."""
    if train_count < MIN_REGIMES_MEDIUM_PLUS:
        return "FAIL_NO_EDGE"
    if holdout_count < MIN_REGIMES_MEDIUM_PLUS:
        return "FAIL_OVERFIT"
    return "PASS"


# ----------------------------------------------------------------------------
# Build report completo
# ----------------------------------------------------------------------------

def _extract_tradeable_regimes(matrix: List[Dict]) -> List[str]:
    """Lista de regimes com edge MEDIUM+ E confidence != LOW (tradeable)."""
    out = []
    for entry in matrix:
        if entry.get("confidence") == "LOW":
            continue
        long_exp  = entry.get("long",  {}).get("exp", 0.0) or 0.0
        short_exp = entry.get("short", {}).get("exp", 0.0) or 0.0
        if max(long_exp, short_exp) >= MEDIUM_THRESHOLD:
            out.append(entry["regime"])
    return out


def build_recalibrated_report(
    train_trades: List[Dict],
    holdout_trades: List[Dict],
    candles: List[Dict],
    grid_adx: Iterable[float] = (20.0, 25.0, 30.0, 35.0),
    grid_transition_bars: Iterable[int] = (10, 20, 30),
    grid_sideways_band: Iterable[float] = (0.01, 0.02, 0.03),
    grid_capitulation: Iterable[float] = (0.20, 0.25, 0.30),
    verbose: bool = False,
) -> Dict:
    """Pipeline completo: grid search no train, aplica no holdout, decide."""
    grid = generate_threshold_grid(
        adx_values=grid_adx,
        transition_bars_values=grid_transition_bars,
        sideways_band_values=grid_sideways_band,
        capitulation_values=grid_capitulation,
    )

    # Evaluate TRAIN over the grid
    train_evals: List[Dict] = []
    if train_trades and candles:
        for i, combo in enumerate(grid):
            ev = evaluate_combo_on_trades(train_trades, candles, combo)
            train_evals.append(ev)
            if verbose:
                print(f"  combo {i+1}/{len(grid)} adx={combo['adx_strong']} "
                      f"tb={combo['transition_bars']} sb={combo['sideways_band']} "
                      f"cap={combo['capitulation']} -> MEDIUM+={ev['n_medium_plus']}", flush=True)

    if train_evals:
        best = pick_best_thresholds(train_evals)
        best_combo = best["combo"]
        train_matrix = best["matrix"]
        train_n = best["n_medium_plus"]
    else:
        # Sem dados: usa o primeiro combo do grid e zera resultados
        best_combo = grid[0] if grid else {
            "adx_strong": 25.0, "transition_bars": 20, "sideways_band": 0.02, "capitulation": 0.25,
        }
        train_matrix = []
        train_n = 0

    # Apply SAME thresholds to holdout (NO recalibration)
    if holdout_trades and candles:
        holdout_eval = evaluate_combo_on_trades(holdout_trades, candles, best_combo)
        holdout_matrix = holdout_eval["matrix"]
        holdout_n = holdout_eval["n_medium_plus"]
    else:
        holdout_matrix = []
        holdout_n = 0

    decision = decide_outcome(train_n, holdout_n)
    tradeable_train   = _extract_tradeable_regimes(train_matrix)
    tradeable_holdout = _extract_tradeable_regimes(holdout_matrix)

    return {
        "best_thresholds":         best_combo,
        "holdout_thresholds":      dict(best_combo),  # idêntico (não recalibra)
        "train_matrix":            train_matrix,
        "holdout_matrix":          holdout_matrix,
        "train_n_medium_plus":     int(train_n),
        "holdout_n_medium_plus":   int(holdout_n),
        "regimes_tradeable_novo":  {
            "train":   tradeable_train,
            "holdout": tradeable_holdout,
            "stable":  sorted(set(tradeable_train) & set(tradeable_holdout)),
        },
        "decision":                decision,
    }


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------

def _load_trades_paginated(market: str, start: str, end: str) -> List[Dict]:
    from db import Database
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    out: List[Dict] = []
    offset = 0
    page = 1000
    while True:
        params = (
            f"select=*&market=eq.{market}"
            f"&entry_ts=gte.{start}&entry_ts=lte.{end}"
            f"&order=entry_ts.asc&limit={page}&offset={offset}"
        )
        rows = db._get("backtest_trades", params)
        out.extend(rows)
        if len(rows) < page:
            break
        offset += page
    return out


def main():
    parser = argparse.ArgumentParser(description="Recalibra thresholds do classificador 8-state via grid search train/holdout")
    parser.add_argument("--market", default="BTCUSD")
    parser.add_argument("--period", default="1hour")
    parser.add_argument("--start",  default="2014-01-01")
    parser.add_argument("--end",    default="2025-05-01")
    parser.add_argument("--train-end", type=int, default=2022)
    parser.add_argument("--holdout-start", type=int, default=2023)
    parser.add_argument("--output", default=None)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    print(f"Carregando trades {args.market} {args.start} -> {args.end}...")
    trades = _load_trades_paginated(args.market, args.start, args.end)
    print(f"  -> {len(trades)} trades totais")

    from db import Database
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    print(f"Carregando candles {args.market} {args.period}...")
    candles = db.get_candles(args.market, args.period, args.start, args.end)
    print(f"  -> {len(candles)} candles")

    train, holdout = split_train_holdout(trades, args.train_end, args.holdout_start)
    print(f"  -> {len(train)} trades train | {len(holdout)} trades holdout")

    print("\nGrid search nos thresholds (pode demorar)...")
    report = build_recalibrated_report(
        train_trades=train,
        holdout_trades=holdout,
        candles=candles,
        verbose=args.verbose,
    )

    out_path = args.output
    if out_path is None:
        here = os.path.dirname(os.path.abspath(__file__))
        journal_dir = os.path.abspath(os.path.join(here, "..", "journal"))
        os.makedirs(journal_dir, exist_ok=True)
        out_path = os.path.join(journal_dir, "task2b_recalibrated_matrix.json")

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    bt = report["best_thresholds"]
    print(f"\n=== BEST THRESHOLDS (train) ===")
    print(f"  ADX_STRONG:      {bt['adx_strong']}")
    print(f"  TRANSITION_BARS: {bt['transition_bars']}")
    print(f"  SIDEWAYS_BAND:   {bt['sideways_band']}")
    print(f"  CAPITULATION:    {bt['capitulation']}")

    print(f"\n=== RESULTADOS ===")
    print(f"  Train MEDIUM+ regimes:   {report['train_n_medium_plus']}")
    print(f"  Holdout MEDIUM+ regimes: {report['holdout_n_medium_plus']}")
    print(f"  Tradeable train:   {report['regimes_tradeable_novo']['train']}")
    print(f"  Tradeable holdout: {report['regimes_tradeable_novo']['holdout']}")
    print(f"  Stable (intersection): {report['regimes_tradeable_novo']['stable']}")
    print(f"\n=== DECISION: {report['decision']} ===")
    print(f"Saved: {out_path}")


if __name__ == "__main__":
    main()
