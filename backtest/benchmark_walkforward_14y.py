"""
benchmark_walkforward_14y.py -- Walk-forward Rolling Validation (Benchmarking V2 — Chat 4 Parte A)

Pergunta respondida:
    "A edge se mantem em janelas rolantes de 12 meses ao longo de 14 anos?
     Ou foi resultado de uma janela sortuda?"

Metodo:
    Rolling windows 12mo / step 6mo de 2014-2025. Em cada janela calcula
    expectancy, PF, max DD; agrega ergodicidade entre janelas.

Entrada (input JSON):
    {
      "windows": [
        { "id", "period_start", "period_end", "trades_r": [...], "regime_dominant" },
        ...
      ]
    }
    Se input ausente, gera sintetico determinista para popular o JSON.

Saida (default: journal/benchmark_walkforward_14y_results.json):
    Ver test_json_schema_valid em tests/.

CLI:
    python backtest/benchmark_walkforward_14y.py
    python backtest/benchmark_walkforward_14y.py --input <p> --output <p> --start 2014-01-01 --end 2025-12-31
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date, datetime, timezone
from typing import Dict, Iterable, List, Optional, Sequence

import numpy as np


DEFAULT_INPUT  = os.path.join("journal", "benchmark_walkforward_14y_input.json")
DEFAULT_OUTPUT = os.path.join("journal", "benchmark_walkforward_14y_results.json")
# 2026-05-16 DRIFT-2 fix: renomeado de GO_CRITERION_POSITIVE_PCT para clarificar.
# Critério WINDOWS (walk-forward fine-grained), diferente de POSITIVE_YEARS_PCT em long_14y.
GO_CRITERION_POSITIVE_WINDOWS_PCT = 60.0   # >= 60% windows positivas
GO_CRITERION_POSITIVE_PCT  = GO_CRITERION_POSITIVE_WINDOWS_PCT   # alias backward-compat
GO_CRITERION_MAX_STREAK    = 4      # streak negativo curto
GO_CRITERION_ERGODICITY    = 0.40   # consistencia minima


# ─────────────────────────────────────────────────────────────────────────────
# Geracao de janelas
# ─────────────────────────────────────────────────────────────────────────────

def _add_months(d: date, months: int) -> date:
    total = d.year * 12 + (d.month - 1) + months
    year, month = divmod(total, 12)
    # PRESERVA o dia se possivel; senao usa ultimo dia valido do mes
    month = month + 1
    day = min(d.day, [31, 29 if (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) else 28,
                      31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1])
    return date(year, month, day)


def generate_windows(start: date, end: date, window_months: int = 12,
                     step_months: int = 6) -> List[Dict]:
    """Lista de janelas {id, start, end} com window/step em meses."""
    windows: List[Dict] = []
    cursor = start
    i = 0
    while True:
        wend = _add_months(cursor, window_months)
        if wend > end:
            break
        windows.append({
            "id":    f"w{i:02d}",
            "start": cursor,
            "end":   wend,
        })
        cursor = _add_months(cursor, step_months)
        i += 1
    return windows


def filter_trades_for_window(trades: Sequence[Dict], window: Dict) -> List[Dict]:
    """Filtra trades cujo `ts` cai dentro de [window.start, window.end]."""
    ws, we = window["start"], window["end"]
    out = []
    for t in trades:
        ts = t.get("ts")
        if ts is None:
            continue
        if ws <= ts <= we:
            out.append(t)
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Metricas por janela
# ─────────────────────────────────────────────────────────────────────────────

def compute_window_metrics(trades_r: Sequence[float]) -> Dict:
    """trades, exp (mean R), pf (gross profit / gross loss), max_dd_r (sempre >=0)."""
    arr = np.asarray(trades_r, dtype=float)
    if arr.size == 0:
        return {"trades": 0, "exp": 0.0, "pf": 0.0, "max_dd_r": 0.0}
    gross_profit = float(arr[arr > 0].sum())
    gross_loss   = float(-arr[arr < 0].sum())
    pf = gross_profit / gross_loss if gross_loss > 0 else (gross_profit if gross_profit > 0 else 0.0)
    equity = np.cumsum(arr)
    peaks  = np.maximum.accumulate(equity)
    max_dd = float((peaks - equity).max()) if equity.size else 0.0
    return {
        "trades":   int(arr.size),
        "exp":      round(float(arr.mean()), 4),
        "pf":       round(float(pf), 4),
        "max_dd_r": round(max_dd, 4),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Agregados entre janelas
# ─────────────────────────────────────────────────────────────────────────────

def ergodicity_score(expectancies: Iterable[float]) -> float:
    """
    Combina consistencia de sinal + estabilidade de magnitude:
      1.0 => todas iguais; 0.0 => sinais opostos balanceados / mean ~ 0.
    """
    arr = np.asarray(list(expectancies), dtype=float)
    if arr.size == 0:
        return 0.0
    mean = float(arr.mean())
    if mean == 0.0:
        return 0.0
    same_sign = float((arr > 0).sum() if mean > 0 else (arr < 0).sum())
    base = same_sign / arr.size  # 0..1
    cv = float(arr.std() / (abs(mean) + 1e-9))  # coeficiente de variacao
    score = max(0.0, base - 0.2 * min(cv, 1.0))
    return float(round(min(1.0, score), 4))


def positive_windows_pct(metrics_list: Sequence[Dict]) -> float:
    if not metrics_list:
        return 0.0
    pos = sum(1 for m in metrics_list if m.get("exp", 0) > 0)
    return float(round(pos / len(metrics_list) * 100.0, 2))


def max_losing_streak_windows(expectancies: Iterable[float]) -> int:
    best = cur = 0
    for v in expectancies:
        if v < 0:
            cur += 1
            best = max(best, cur)
        else:
            cur = 0
    return int(best)


def identify_worst_window(windows: Sequence[Dict]) -> Dict:
    """Janela com menor exp + macro context inferido por periodo/regime."""
    if not windows:
        return {"period": None, "exp": 0.0, "context": "no_windows"}
    worst = min(windows, key=lambda w: float(w.get("exp", 0)))
    ps = worst.get("period_start") or worst.get("start")
    pe = worst.get("period_end")   or worst.get("end")
    period = f"{ps} -> {pe}"
    regime = worst.get("regime_dominant", "unknown")
    ctx = f"regime={regime}; period={period}"
    out = dict(worst)
    out["period"]  = period
    out["context"] = ctx
    return out


def aggregate_metrics(windows: Sequence[Dict]) -> Dict:
    exps = [float(w.get("exp", 0.0)) for w in windows]
    arr  = np.asarray(exps, dtype=float)
    return {
        "expectancy_mean":          round(float(arr.mean()), 4) if arr.size else 0.0,
        "expectancy_std":           round(float(arr.std()),  4) if arr.size else 0.0,
        "ergodicity_score":         ergodicity_score(exps),
        "positive_windows_pct":     positive_windows_pct([{"exp": e} for e in exps]),
        "max_losing_streak_windows": max_losing_streak_windows(exps),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Pipeline end-to-end
# ─────────────────────────────────────────────────────────────────────────────

def _coerce_date_field(v):
    if isinstance(v, date):
        return v
    if isinstance(v, str):
        try:
            return date.fromisoformat(v[:10])
        except Exception:
            return None
    return None


def run_walkforward(windows_input: List[Dict], start: str = "", end: str = "") -> Dict:
    """Pipeline: para cada window com trades_r, computa metrics + agrega."""
    enriched: List[Dict] = []
    for w in windows_input:
        trades = list(w.get("trades_r", []) or [])
        m = compute_window_metrics(trades)
        ps = _coerce_date_field(w.get("period_start"))
        pe = _coerce_date_field(w.get("period_end"))
        period = f"{ps.isoformat() if ps else '?'} -> {pe.isoformat() if pe else '?'}"
        enriched.append({
            "id":              w.get("id", "w?"),
            "period":          period,
            "period_start":    ps.isoformat() if ps else None,
            "period_end":      pe.isoformat() if pe else None,
            "trades":          m["trades"],
            "exp":             m["exp"],
            "pf":              m["pf"],
            "max_dd_r":        m["max_dd_r"],
            "regime_dominant": w.get("regime_dominant", "unknown"),
        })

    cons   = aggregate_metrics(enriched)
    worst  = identify_worst_window(enriched)

    # GO criterion: positive% >= 60, streak <= 4, ergodicity >= 0.40
    passed = (
        cons["positive_windows_pct"]     >= GO_CRITERION_POSITIVE_PCT and
        cons["max_losing_streak_windows"] <= GO_CRITERION_MAX_STREAK   and
        cons["ergodicity_score"]          >= GO_CRITERION_ERGODICITY
    )

    return {
        "timestamp":   datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "start":       start,
        "end":         end,
        "n_windows":   len(enriched),
        "windows":     enriched,
        "consistency": cons,
        "worst_window": {
            "id":       worst.get("id"),
            "period":   worst.get("period"),
            "exp":      worst.get("exp"),
            "context":  worst.get("context"),
        },
        "go_criterion": {
            "rule":   (f"positive_windows_pct >= {GO_CRITERION_POSITIVE_PCT}% "
                       f"AND max_losing_streak <= {GO_CRITERION_MAX_STREAK} "
                       f"AND ergodicity_score >= {GO_CRITERION_ERGODICITY}"),
            "passed": bool(passed),
            "actual": {
                "positive_windows_pct":     cons["positive_windows_pct"],
                "max_losing_streak_windows": cons["max_losing_streak_windows"],
                "ergodicity_score":         cons["ergodicity_score"],
            },
        },
        "go_live_criterion": {
            # alias com schema do consolidator
            "rule":   (f"WF positive>={GO_CRITERION_POSITIVE_PCT}% & streak<={GO_CRITERION_MAX_STREAK} "
                       f"& ergodicity>={GO_CRITERION_ERGODICITY}"),
            "passed": bool(passed),
            "explanation": (
                f"{cons['positive_windows_pct']}% windows positivas; "
                f"streak max negativo {cons['max_losing_streak_windows']}; "
                f"ergodicity {cons['ergodicity_score']}."
            ),
        },
    }


# ─────────────────────────────────────────────────────────────────────────────
# CLI / Input loader
# ─────────────────────────────────────────────────────────────────────────────

def _synthetic_windows(start: date, end: date) -> List[Dict]:
    """Gera ~22 janelas com R-distributions determinitas para popular o JSON."""
    rng = np.random.default_rng(0)
    grid = generate_windows(start, end, 12, 6)
    out: List[Dict] = []
    for i, w in enumerate(grid):
        # Mix de regimes: bear (i 3,7,11), bull (par), sideways (impar)
        if i in (3, 7, 11):
            regime, win_rate, payoff = "bear", 0.42, 1.5
        elif i % 2 == 0:
            regime, win_rate, payoff = "bull", 0.58, 2.0
        else:
            regime, win_rate, payoff = "sideways", 0.50, 1.5
        n = int(rng.integers(40, 80))
        trades = rng.choice([payoff, -1.0], size=n, p=[win_rate, 1 - win_rate]).tolist()
        out.append({
            "id":            w["id"],
            "period_start":  w["start"].isoformat(),
            "period_end":    w["end"].isoformat(),
            "trades_r":      trades,
            "regime_dominant": regime,
        })
    return out


def _load_input(path: str, start: date, end: date) -> List[Dict]:
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return list(data.get("windows", []))
    sys.stderr.write(
        f"[Walkforward] Input nao encontrado em {path} -- gerando janelas sinteticas.\n"
    )
    return _synthetic_windows(start, end)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Walk-forward 14y benchmark")
    parser.add_argument("--input",  default=DEFAULT_INPUT)
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--start",  default="2014-01-01")
    parser.add_argument("--end",    default="2025-12-31")
    parser.add_argument("--window-months", type=int, default=12)
    parser.add_argument("--step-months",   type=int, default=6)
    args = parser.parse_args(argv)

    start = date.fromisoformat(args.start)
    end   = date.fromisoformat(args.end)
    windows_input = _load_input(args.input, start, end)
    result = run_walkforward(windows_input, start=args.start, end=args.end)

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, default=str)

    sys.stdout.write(
        f"[Walkforward] {result['n_windows']} windows. passed="
        f"{result['go_criterion']['passed']} pos%="
        f"{result['consistency']['positive_windows_pct']} "
        f"streak={result['consistency']['max_losing_streak_windows']} "
        f"erg={result['consistency']['ergodicity_score']}. -> {args.output}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
