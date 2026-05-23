"""
benchmark_long_14y.py — Baseline LONG-only em 11 anos BTCUSD Bitstamp (4 ciclos).

CONTRATO (JSON output):
{
  "total":              {trades, win_rate, expectancy_r, profit_factor,
                         max_dd_r, annualized_return_pct, sharpe_annualized},
  "by_year":            [{year, trades, exp, pf, max_dd_r, regime_dominant}],
  "worst_3_years":      [{year, exp, context}],
  "best_3_years":       [{year, exp, context}],
  "positive_years_pct": 0-100,
  "go_criterion":       {rule, passed, total_pf, positive_years_pct}
}

GO CRITERION:
  - positive_years_pct >= 70
  - total_pf >= 1.5

NÃO MODIFICA: db.py, signal_generator.py, metrics.py (só importa).
Tested in: tests/test_benchmark_long_14y.py (13 testes pytest TDD).

CLI:
    python backtest/benchmark_long_14y.py --output journal/benchmark_long_14y_results.json
"""
import argparse
import json
import math
import os
import sys
from collections import defaultdict
from typing import Dict, Iterable, List, Optional

from metrics import calc_metrics, classify_regime


# 2026-05-16 DRIFT-2 fix: renomeado para clarificar (era GO_CRITERION_POSITIVE_PCT).
# Critério ANOS (year-level), diferente de POSITIVE_WINDOWS_PCT em walkforward_14y.
GO_CRITERION_POSITIVE_YEARS_PCT = 70.0
GO_CRITERION_POSITIVE_PCT       = GO_CRITERION_POSITIVE_YEARS_PCT   # alias backward-compat
GO_CRITERION_TOTAL_PF     = 1.5
SMA200_PERIOD             = 200
REGIME_BAND               = 0.02


# ----------------------------------------------------------------------------
# Helpers — extração de ano e LONG-only filter
# ----------------------------------------------------------------------------

def _year_of(trade: Dict) -> Optional[int]:
    ts = trade.get("entry_ts") or trade.get("bar_ts") or trade.get("exit_ts")
    if not ts:
        return None
    try:
        return int(str(ts)[:4])
    except (ValueError, TypeError):
        return None


def _filter_long(trades: List[Dict]) -> List[Dict]:
    """LONG-only filter (caso o caller misture LONG/SHORT)."""
    return [t for t in trades if t.get("direction", "LONG") == "LONG"]


# ----------------------------------------------------------------------------
# Split por ano
# ----------------------------------------------------------------------------

def split_trades_by_year(trades: List[Dict]) -> Dict[int, List[Dict]]:
    """Distribui trades em buckets por ano usando entry_ts (ou bar_ts/exit_ts)."""
    by_year: Dict[int, List[Dict]] = defaultdict(list)
    for t in trades:
        y = _year_of(t)
        if y is None:
            continue
        by_year[y].append(t)
    return dict(by_year)


# ----------------------------------------------------------------------------
# Sharpe annualizado por ano
# ----------------------------------------------------------------------------

def sharpe_annualized_year(r_series: List[float]) -> float:
    """Sharpe annualizado por ano: mean/std * sqrt(N_trades_per_year).
    rf = 0 (simplificação). Retorna 0 para série vazia ou std=0."""
    if not r_series:
        return 0.0
    n = len(r_series)
    if n < 2:
        return 0.0
    m = sum(r_series) / n
    var = sum((r - m) ** 2 for r in r_series) / (n - 1)
    std = math.sqrt(var)
    if std == 0:
        if m > 0: return float("inf")
        if m < 0: return float("-inf")
        return 0.0
    return (m / std) * math.sqrt(n)


# ----------------------------------------------------------------------------
# Regime dominante por ano
# ----------------------------------------------------------------------------

def classify_regime_dominant(candles: List[Dict]) -> str:
    """Regime majoritário no ano via SMA200 (uppercase BULL/BEAR/SIDEWAYS)."""
    if not candles or len(candles) < SMA200_PERIOD:
        # Sem dados suficientes para SMA200: usa drift simples
        if not candles:
            return "SIDEWAYS"
        first = candles[0]["close"]
        last = candles[-1]["close"]
        if first <= 0:
            return "SIDEWAYS"
        drift = (last - first) / first
        if drift > 0.10:  return "BULL"
        if drift < -0.10: return "BEAR"
        return "SIDEWAYS"

    counts = {"bull": 0, "bear": 0, "sideways": 0}
    closes = [c["close"] for c in candles]
    for i in range(SMA200_PERIOD - 1, len(candles)):
        sma = sum(closes[i - SMA200_PERIOD + 1:i + 1]) / SMA200_PERIOD
        if sma <= 0:
            counts["sideways"] += 1
            continue
        try:
            r = classify_regime(closes[i], sma, threshold=REGIME_BAND)
        except Exception:
            r = "sideways"
        counts[r] = counts.get(r, 0) + 1

    top = max(counts, key=counts.get)
    return top.upper()


# ----------------------------------------------------------------------------
# Métricas agregadas full-period
# ----------------------------------------------------------------------------

def calc_aggregate_metrics(trades: List[Dict]) -> Dict:
    """Agrega métricas full-period a partir dos result_r."""
    longs = _filter_long(trades)
    r_series = [float(t["result_r"]) for t in longs if "result_r" in t]
    if not r_series:
        return {
            "trades":                0,
            "win_rate":              0.0,
            "expectancy_r":          0.0,
            "profit_factor":         0.0,
            "max_drawdown_r":        0.0,
            "annualized_return_pct": 0.0,
            "sharpe_annualized":     0.0,
        }

    m = calc_metrics(r_series)

    # Annualized return: total R / spread anos
    years = sorted({_year_of(t) for t in longs if _year_of(t) is not None})
    n_years = max(1, (years[-1] - years[0] + 1)) if years else 1
    total_r = sum(r_series)
    # Aproximação: total_r em % equivalente (cada R = 1% do capital, regra 1%)
    total_pct = total_r * 1.0
    annualized = total_pct / n_years

    sh = sharpe_annualized_year(r_series)

    pf = m.profit_factor if m.profit_factor != float("inf") else None

    return {
        "trades":                int(m.total_trades),
        "win_rate":              round(float(m.win_rate), 4),
        "expectancy_r":          round(float(m.expectancy_r), 6),
        "profit_factor":         (round(pf, 4) if pf is not None else None),
        "max_drawdown_r":        round(float(m.max_drawdown_r), 4),
        "annualized_return_pct": round(annualized, 4),
        "sharpe_annualized":     (round(sh, 4) if math.isfinite(sh) else None),
    }


# ----------------------------------------------------------------------------
# Métricas por ano
# ----------------------------------------------------------------------------

def calc_per_year_metrics(
    trades_by_year: Dict[int, List[Dict]],
    candles_by_year: Optional[Dict[int, List[Dict]]] = None,
    expected_years: Optional[Iterable[int]] = None,
) -> List[Dict]:
    """Métricas por ano. Marca data_unavailable=True em anos sem trades quando expected_years informado."""
    candles_by_year = candles_by_year or {}
    years_set = set(trades_by_year.keys())
    if expected_years is not None:
        years_set |= set(expected_years)
    years = sorted(years_set)

    out: List[Dict] = []
    for y in years:
        trades = trades_by_year.get(y, [])
        candles = candles_by_year.get(y, [])

        if not trades:
            out.append({
                "year":               y,
                "trades":             0,
                "win_rate":           0.0,
                "expectancy_r":       0.0,
                "profit_factor":      None,
                "max_drawdown_r":     0.0,
                "sharpe_annualized":  None,
                "regime_dominant":    classify_regime_dominant(candles) if candles else "SIDEWAYS",
                "data_unavailable":   True,
            })
            continue

        longs = _filter_long(trades)
        r_series = [float(t["result_r"]) for t in longs if "result_r" in t]
        if not r_series:
            out.append({
                "year":               y,
                "trades":             0,
                "win_rate":           0.0,
                "expectancy_r":       0.0,
                "profit_factor":      None,
                "max_drawdown_r":     0.0,
                "sharpe_annualized":  None,
                "regime_dominant":    classify_regime_dominant(candles) if candles else "SIDEWAYS",
                "data_unavailable":   True,
            })
            continue

        m = calc_metrics(r_series)
        sh = sharpe_annualized_year(r_series)
        pf = m.profit_factor if m.profit_factor != float("inf") else None

        out.append({
            "year":               y,
            "trades":             int(m.total_trades),
            "win_rate":           round(float(m.win_rate), 4),
            "expectancy_r":       round(float(m.expectancy_r), 6),
            "profit_factor":      (round(pf, 4) if pf is not None else None),
            "max_drawdown_r":     round(float(m.max_drawdown_r), 4),
            "sharpe_annualized":  (round(sh, 4) if math.isfinite(sh) else None),
            "regime_dominant":    classify_regime_dominant(candles) if candles else "SIDEWAYS",
        })
    return out


# ----------------------------------------------------------------------------
# Ranking worst / best
# ----------------------------------------------------------------------------

def _years_with_trades(per_year: List[Dict]) -> List[Dict]:
    return [p for p in per_year if not p.get("data_unavailable") and p.get("trades", 0) > 0]


def rank_worst_years(per_year: List[Dict], n: int = 3) -> List[Dict]:
    """Retorna os n anos com menor expectancy_r (ascendente: pior primeiro)."""
    candidates = _years_with_trades(per_year)
    return sorted(candidates, key=lambda p: p.get("expectancy_r", 0.0))[:n]


def rank_best_years(per_year: List[Dict], n: int = 3) -> List[Dict]:
    """Retorna os n anos com maior expectancy_r (descendente: melhor primeiro)."""
    candidates = _years_with_trades(per_year)
    return sorted(candidates, key=lambda p: p.get("expectancy_r", 0.0), reverse=True)[:n]


# ----------------------------------------------------------------------------
# % anos positivos
# ----------------------------------------------------------------------------

def positive_years_pct(per_year: List[Dict]) -> float:
    """% de anos com expectancy_r > 0 (considera só anos com dados)."""
    candidates = _years_with_trades(per_year) or per_year
    if not candidates:
        return 0.0
    positives = sum(1 for p in candidates if p.get("expectancy_r", 0.0) > 0)
    return round((positives / len(candidates)) * 100.0, 1)


# ----------------------------------------------------------------------------
# GO criterion
# ----------------------------------------------------------------------------

def evaluate_go_criterion(positive_pct: float, total_pf: float) -> Dict:
    """GO se positive_years_pct >= 70 E total_pf >= 1.5."""
    passed = (positive_pct >= GO_CRITERION_POSITIVE_PCT) and (total_pf >= GO_CRITERION_TOTAL_PF)
    return {
        "rule":                f"positive_years_pct >= {GO_CRITERION_POSITIVE_PCT} AND total_pf >= {GO_CRITERION_TOTAL_PF}",
        "passed":              bool(passed),
        "total_pf":            float(total_pf),
        "positive_years_pct":  float(positive_pct),
    }


# ----------------------------------------------------------------------------
# Build full report
# ----------------------------------------------------------------------------

def build_long_14y_report(
    trades: List[Dict],
    candles_by_year: Optional[Dict[int, List[Dict]]] = None,
    expected_years: Optional[Iterable[int]] = None,
) -> Dict:
    """Constrói o relatório completo. Filtra LONG-only internamente."""
    longs = _filter_long(trades)
    by_year = split_trades_by_year(longs)

    # Default expected_years = range dos anos presentes
    if expected_years is None and by_year:
        ys = sorted(by_year.keys())
        expected_years = range(ys[0], ys[-1] + 1)

    per_year = calc_per_year_metrics(by_year, candles_by_year=candles_by_year or {}, expected_years=expected_years)
    total = calc_aggregate_metrics(longs)

    def _context(entry: Dict) -> str:
        regime = entry.get("regime_dominant", "?")
        n = entry.get("trades", 0)
        return f"{regime} regime, n={n}"

    worst = [
        {"year": p["year"], "expectancy_r": p["expectancy_r"], "context": _context(p)}
        for p in rank_worst_years(per_year, n=3)
    ]
    best = [
        {"year": p["year"], "expectancy_r": p["expectancy_r"], "context": _context(p)}
        for p in rank_best_years(per_year, n=3)
    ]
    pos_pct = positive_years_pct(per_year)
    total_pf = total.get("profit_factor") or 0.0
    go = evaluate_go_criterion(positive_pct=pos_pct, total_pf=total_pf)

    return {
        "total":              total,
        "by_year":            per_year,
        "worst_3_years":      worst,
        "best_3_years":       best,
        "positive_years_pct": pos_pct,
        "go_criterion":       go,
    }


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------

def _load_trades_from_db(market: str = "BTCUSD", period: str = "1hour",
                         start: str = "2014-01-01", end: str = "2025-05-01") -> List[Dict]:
    """Carrega trades do Supabase paginando para contornar limite default de 1000 rows.
    Filtra LONG (direction='LONG')."""
    from db import Database
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)

    all_rows: List[Dict] = []
    offset = 0
    page = 1000
    while True:
        params = (
            f"select=*"
            f"&market=eq.{market}"
            f"&direction=eq.LONG"
            f"&entry_ts=gte.{start}"
            f"&entry_ts=lte.{end}"
            f"&order=entry_ts.asc"
            f"&limit={page}&offset={offset}"
        )
        rows = db._get("backtest_trades", params)
        all_rows.extend(rows)
        if len(rows) < page:
            break
        offset += page
    return all_rows


def _load_candles_by_year(market: str = "BTCUSD", period: str = "1hour",
                          years: Iterable[int] = ()) -> Dict[int, List[Dict]]:
    """Carrega candles ano-a-ano (paginação já em db.get_candles)."""
    from db import Database
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    out: Dict[int, List[Dict]] = {}
    for y in years:
        cs = db.get_candles(market, period, f"{y}-01-01", f"{y}-12-31")
        if cs:
            out[y] = cs
    return out


def main():
    parser = argparse.ArgumentParser(description="Baseline LONG 11 anos BTCUSD Bitstamp")
    parser.add_argument("--market", default="BTCUSD")
    parser.add_argument("--period", default="1hour")
    parser.add_argument("--start",  default="2014-01-01")
    parser.add_argument("--end",    default="2025-05-01")
    parser.add_argument("--output", default=None)
    parser.add_argument("--skip-candles", action="store_true",
                        help="Pular carga de candles (regime_dominant será SIDEWAYS)")
    args = parser.parse_args()

    print(f"Carregando trades {args.market} {args.period} {args.start} -> {args.end}...")
    trades = _load_trades_from_db(args.market, args.period, args.start, args.end)
    print(f"  -> {len(trades)} trades LONG")

    candles_by_year: Dict[int, List[Dict]] = {}
    if not args.skip_candles and trades:
        ys = sorted({_year_of(t) for t in trades if _year_of(t) is not None})
        if ys:
            print(f"Carregando candles por ano ({ys[0]}-{ys[-1]})...")
            candles_by_year = _load_candles_by_year(args.market, args.period, range(ys[0], ys[-1] + 1))
            print(f"  -> {len(candles_by_year)} anos com candles")

    report = build_long_14y_report(trades, candles_by_year=candles_by_year)

    out_path = args.output
    if out_path is None:
        here = os.path.dirname(os.path.abspath(__file__))
        journal_dir = os.path.abspath(os.path.join(here, "..", "journal"))
        os.makedirs(journal_dir, exist_ok=True)
        out_path = os.path.join(journal_dir, "benchmark_long_14y_results.json")

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print("\n=== TOTAL ===")
    t = report["total"]
    print(f"  Trades: {t['trades']} | Win: {t['win_rate']}% | Exp: {t['expectancy_r']}R | "
          f"PF: {t['profit_factor']} | DD: {t['max_drawdown_r']}R | Sharpe: {t['sharpe_annualized']}")

    print("\n=== POR ANO ===")
    for p in report["by_year"]:
        flag = "[--]" if p.get("data_unavailable") else "[OK]"
        print(f"  {p['year']} {flag} n={p['trades']:>5} | exp={p['expectancy_r']:+.4f}R | "
              f"PF={p['profit_factor']} | DD={p['max_drawdown_r']:.2f}R | regime={p['regime_dominant']}")

    print("\n=== WORST 3 ===")
    for p in report["worst_3_years"]:
        print(f"  {p['year']} exp={p['expectancy_r']:+.4f}R | {p['context']}")
    print("\n=== BEST 3 ===")
    for p in report["best_3_years"]:
        print(f"  {p['year']} exp={p['expectancy_r']:+.4f}R | {p['context']}")

    g = report["go_criterion"]
    print(f"\n=== GO CRITERION ===")
    print(f"  Rule: {g['rule']}")
    print(f"  Positive years: {g['positive_years_pct']}%")
    print(f"  Total PF: {g['total_pf']}")
    print(f"  Passed: {g['passed']}")
    print(f"\nSaved: {out_path}")


if __name__ == "__main__":
    main()
