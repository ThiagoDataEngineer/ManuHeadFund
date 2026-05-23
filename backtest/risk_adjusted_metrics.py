"""
risk_adjusted_metrics.py — Métricas risk-adjusted universais para benchmarking.

Adiciona Sharpe + Calmar anualizados (Sortino já existe em metrics.py) num
formato compatível para comparação com S&P 500, hedge funds e lendas (Renaissance,
Druckenmiller). NÃO modifica metrics.py — só importa quando necessário.

CONTRATO (JSON output):
  Ver schema completo no docstring de build_aggregate_report.

FÓRMULAS (clássicas, sem invenção):
  Sharpe   = (mean_R - rf_R) / std_R * sqrt(periods_per_year)
  Sortino  = (mean_R - rf_R) / downside_std_R * sqrt(periods_per_year)
  Calmar   = annualized_return_pct / max_drawdown_pct
  ppy      = (n_trades / period_days) * 365

CLASSIFICATION:
  EXCEPTIONAL (suspeito de overfit): Sharpe > 3.0
  ELITE:                              2.0 <= Sharpe <= 3.0
  PROFESSIONAL:                       1.0 <= Sharpe < 2.0
  RETAIL:                             Sharpe < 1.0

CLI:
  python backtest/risk_adjusted_metrics.py --runs all
"""
import argparse
import json
import math
import os
import sys
from datetime import datetime, timezone
from typing import Dict, List, Optional


COMPARISON_TABLE = {
    "sp500_typical":         "0.5-0.7",
    "hedge_fund_median":     "0.8-1.2",
    "hedge_fund_top_decile": "1.5-2.5",
    "renaissance_medallion": "2.5",
    "druckenmiller_career":  "~2.0",
}

DEFAULT_DISCOUNT_FACTOR = 0.5
GO_LIVE_THRESHOLD       = 1.5


def periods_per_year(n_trades: int, period_days: int) -> float:
    """ppy = (n_trades / period_days) * 365. Período zero => retorna 1 (safe fallback)."""
    if period_days <= 0:
        return 1
    return (n_trades / period_days) * 365.0


def _mean(xs: List[float]) -> float:
    return sum(xs) / len(xs) if xs else 0.0


def _std(xs: List[float]) -> float:
    if len(xs) < 2:
        return 0.0
    m = _mean(xs)
    var = sum((x - m) ** 2 for x in xs) / (len(xs) - 1)
    return math.sqrt(var)


def _downside_std(xs: List[float], target: float = 0.0) -> float:
    """Std somente dos retornos abaixo do target (downside deviation)."""
    downside = [x - target for x in xs if x < target]
    if len(downside) < 2:
        return 0.0
    # Downside deviation usa squared deviations from target (Sortino original)
    var = sum(d ** 2 for d in downside) / len(downside)
    return math.sqrt(var)


def sharpe_annualized(
    r_series: List[float],
    n_trades: int,
    period_days: int,
    rf_rate: float = 0.0,
) -> float:
    """Sharpe ratio anualizado.

    rf_rate é a TAXA POR TRADE (não anualizada). Para risk-free anual A,
    aproxime rf_rate = A / ppy.
    """
    if not r_series:
        return 0.0
    mean_r = _mean(r_series)
    std_r  = _std(r_series)
    excess = mean_r - rf_rate
    ppy    = periods_per_year(n_trades, period_days)

    if std_r == 0:
        if excess > 0:
            return float("inf")
        if excess < 0:
            return float("-inf")
        return 0.0

    return (excess / std_r) * math.sqrt(ppy)


def sortino_annualized(
    r_series: List[float],
    n_trades: int,
    period_days: int,
    rf_rate: float = 0.0,
) -> float:
    """Sortino ratio anualizado (penaliza apenas downside vol)."""
    if not r_series:
        return 0.0
    mean_r       = _mean(r_series)
    downside_std = _downside_std(r_series, target=rf_rate)
    excess       = mean_r - rf_rate
    ppy          = periods_per_year(n_trades, period_days)

    if downside_std == 0:
        if excess > 0:
            return float("inf")
        return 0.0

    return (excess / downside_std) * math.sqrt(ppy)


def calmar_annualized(annualized_return_pct: float, max_drawdown_pct: float) -> float:
    """Calmar = retorno anualizado / max drawdown (ambos em %)."""
    if max_drawdown_pct <= 0:
        return float("inf") if annualized_return_pct > 0 else 0.0
    return annualized_return_pct / max_drawdown_pct


def classify_sharpe(sharpe: float) -> str:
    """Bucket de classificação universal.
    Bordas: 1.0 e 2.0 são PROFESSIONAL; 3.0 é ELITE; > 3.0 é EXCEPTIONAL (suspeito).
    """
    if sharpe > 3.0:
        return "EXCEPTIONAL"
    if sharpe > 2.0:
        return "ELITE"
    if sharpe >= 1.0:
        return "PROFESSIONAL"
    return "RETAIL"


def overfit_warning(sharpe: float) -> Dict:
    """Sharpe > 3 acende alerta de overfitting."""
    above = sharpe > 3.0
    if above:
        interp = (
            "Sharpe > 3 é suspeito de overfit ou viés de seleção. "
            "Renaissance Medallion ~2.5 — qualquer coisa acima exige walk-forward rigoroso e dados out-of-sample."
        )
    else:
        interp = "Sharpe dentro de faixa realista — sem alerta de overfit."
    return {
        "sharpe_above_3":  bool(above),
        "interpretation":  interp,
    }


def discounted_sharpe(sharpe_raw: float, factor: float = DEFAULT_DISCOUNT_FACTOR) -> float:
    """Aplica desconto conservador (anti-overfit). Default factor = 0.5."""
    return sharpe_raw * factor


def _median(values: List[float]) -> float:
    if not values:
        return 0.0
    s = sorted(values)
    n = len(s)
    mid = n // 2
    if n % 2 == 1:
        return s[mid]
    return (s[mid - 1] + s[mid]) / 2.0


def build_run_report(
    run_id: str,
    r_series: List[float],
    period_days: int,
    max_drawdown_r: float,
    annualized_return_pct: float,
    max_drawdown_pct: float,
    rf_rate: float = 0.0,
) -> Dict:
    """Constrói o dict de um run conforme contrato."""
    n_trades = len(r_series)

    sh = sharpe_annualized(r_series, n_trades, period_days, rf_rate)
    so = sortino_annualized(r_series, n_trades, period_days, rf_rate)
    cm = calmar_annualized(annualized_return_pct, max_drawdown_pct)

    return {
        "run_id":      run_id,
        "n_trades":    n_trades,
        "period_days": period_days,
        "ratios": {
            "sharpe_annualized":  _round_safe(sh, 4),
            "sortino_annualized": _round_safe(so, 4),
            "calmar_annualized":  _round_safe(cm, 4),
        },
        "comparison_table": dict(COMPARISON_TABLE),
        "classification":   classify_sharpe(sh),
        "overfit_warning":  overfit_warning(sh),
    }


def _round_safe(v: float, ndigits: int = 4):
    """Round que sobrevive a inf/nan (JSON-safe: retorna None se não-finito)."""
    if v is None:
        return None
    if isinstance(v, float) and (math.isinf(v) or math.isnan(v)):
        return None
    return round(v, ndigits)


def build_aggregate_report(runs: List[Dict], discount_factor: float = DEFAULT_DISCOUNT_FACTOR) -> Dict:
    """
    Agrega métricas dos N runs:
      - mediana de Sharpe/Sortino/Calmar
      - classificação da mediana
      - critério go-live (mediana descontada >= GO_LIVE_THRESHOLD)
    """
    sharpe_vals = []
    sortino_vals = []
    calmar_vals = []
    for r in runs:
        ratios = r.get("ratios", {})
        if ratios.get("sharpe_annualized")  is not None: sharpe_vals.append(ratios["sharpe_annualized"])
        if ratios.get("sortino_annualized") is not None: sortino_vals.append(ratios["sortino_annualized"])
        if ratios.get("calmar_annualized")  is not None: calmar_vals.append(ratios["calmar_annualized"])

    median_sharpe  = _median(sharpe_vals)
    median_sortino = _median(sortino_vals)
    median_calmar  = _median(calmar_vals)
    median_class   = classify_sharpe(median_sharpe)

    discounted = discounted_sharpe(median_sharpe, factor=discount_factor)
    passed     = discounted >= GO_LIVE_THRESHOLD

    explanation = (
        f"Sharpe descontado {_round_safe(discounted, 4)} "
        f"{'>=' if passed else '<'} {GO_LIVE_THRESHOLD} threshold"
    )

    return {
        "median": {
            "sharpe":         _round_safe(median_sharpe, 4),
            "sortino":        _round_safe(median_sortino, 4),
            "calmar":         _round_safe(median_calmar, 4),
            "classification": median_class,
        },
        "go_live_criterion": {
            "rule":                    f"Sharpe descontado >= {GO_LIVE_THRESHOLD} em mediana dos {len(runs)} runs",
            "discount_factor":         discount_factor,
            "median_sharpe_raw":       _round_safe(median_sharpe, 4),
            "median_sharpe_discounted": _round_safe(discounted, 4),
            "passed":                  bool(passed),
            "explanation":             explanation,
        },
    }


# ============================================================================
# CLI
# ============================================================================

def _dummy_runs_for_demo() -> List[Dict]:
    """Runs sintéticos para demonstrar o output do CLI (substituir por leitura real do DB)."""
    return [
        build_run_report(
            run_id="btc_in_sample",
            r_series=[0.5, -0.3, 1.2, -0.4, 0.8, 0.2, -0.5, 1.0, 0.3, -0.2,
                      0.6, -0.4, 0.9, 0.1, -0.3, 0.7, 0.4, -0.5, 1.1, 0.0] * 4,
            period_days=181,
            max_drawdown_r=2.5,
            annualized_return_pct=45.0,
            max_drawdown_pct=12.0,
        ),
        build_run_report(
            run_id="btc_out_of_sample",
            r_series=[0.3, -0.4, 0.8, -0.5, 0.5, 0.1, -0.3, 0.7, 0.2, -0.2,
                      0.4, -0.5, 0.6, 0.0, -0.4, 0.5, 0.3, -0.6, 0.8, -0.1] * 3,
            period_days=120,
            max_drawdown_r=3.0,
            annualized_return_pct=20.0,
            max_drawdown_pct=15.0,
        ),
        build_run_report(
            run_id="eth_in_sample",
            r_series=[0.4, -0.2, 1.0, -0.3, 0.7, 0.3, -0.4, 0.9, 0.4, -0.1,
                      0.5, -0.3, 0.8, 0.2, -0.2, 0.6, 0.5, -0.4, 1.0, 0.1] * 4,
            period_days=181,
            max_drawdown_r=2.0,
            annualized_return_pct=55.0,
            max_drawdown_pct=10.0,
        ),
    ]


def main():
    parser = argparse.ArgumentParser(description="Risk-adjusted metrics universais (Sharpe/Sortino/Calmar)")
    parser.add_argument("--runs", default="all",
                        help="'all' para gerar runs sintéticos demo. Em prod, ler do DB/journal.")
    parser.add_argument("--output", default=None,
                        help="Path do JSON. Default: journal/benchmark_risk_adjusted_results.json")
    parser.add_argument("--discount-factor", type=float, default=DEFAULT_DISCOUNT_FACTOR)
    args = parser.parse_args()

    runs = _dummy_runs_for_demo()

    agg = build_aggregate_report(runs, discount_factor=args.discount_factor)

    report = {
        "timestamp":         datetime.now(tz=timezone.utc).isoformat(),
        "runs":              runs,
        "median":            agg["median"],
        "go_live_criterion": agg["go_live_criterion"],
    }

    out_path = args.output
    if out_path is None:
        here = os.path.dirname(os.path.abspath(__file__))
        journal_dir = os.path.abspath(os.path.join(here, "..", "journal"))
        os.makedirs(journal_dir, exist_ok=True)
        out_path = os.path.join(journal_dir, "benchmark_risk_adjusted_results.json")

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print(f"\n=== RISK-ADJUSTED METRICS — {len(runs)} runs ===\n")
    for r in runs:
        rt = r["ratios"]
        print(f"{r['run_id']:<25} | Sharpe={rt['sharpe_annualized']:>6} | "
              f"Sortino={rt['sortino_annualized']:>6} | Calmar={rt['calmar_annualized']:>6} | "
              f"{r['classification']}")

    print("\nMedian:")
    print(f"  Sharpe  = {agg['median']['sharpe']}  ({agg['median']['classification']})")
    print(f"  Sortino = {agg['median']['sortino']}")
    print(f"  Calmar  = {agg['median']['calmar']}")

    gl = agg["go_live_criterion"]
    print("\nGo-Live Criterion:")
    print(f"  Rule:        {gl['rule']}")
    print(f"  Raw:         {gl['median_sharpe_raw']}")
    print(f"  Discounted:  {gl['median_sharpe_discounted']}")
    print(f"  Passed:      {gl['passed']}")
    print(f"  {gl['explanation']}")

    print(f"\nSaved: {out_path}")


if __name__ == "__main__":
    main()
