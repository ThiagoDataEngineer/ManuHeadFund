"""
trade_concentration.py — Análise de concentração de PnL em backtests.

Detecta overfit/tail-dependence quantificando que % dos trades produz que %
do equity total (Gini, top-N contribution, % concentrado em 1 ano, etc).

Sinais de concentração problemática:
- Top 1% dos trades > 50% do equity = strategy é tail-play, não edge tactical
- 1 ano contribui > 70% do equity = não-estacionário, viés de período
- > 90% do PnL em < 10 trades = lottery effect
"""
from __future__ import annotations

from collections import defaultdict
from typing import Dict, List


def equity_from_pnl_sequence(pnls: List[float]) -> List[float]:
    """Equity multiplicativa a partir de PnL pct sequence."""
    eq = 1.0
    out = []
    for p in pnls:
        eq *= (1.0 + p)
        out.append(eq)
    return out


def top_n_contribution_pct(trades: List[Dict], risk_pct: float = 0.01,
                            top_n_pct: float = 0.01) -> Dict:
    """
    Calcula % do equity contribuído pelos top N% trades por PnL absoluto.

    Args:
        trades: lista com result_r
        risk_pct: % do capital arriscado por trade
        top_n_pct: 0.01 = top 1%, 0.10 = top 10%

    Returns:
        {n_total, n_top, top_pnl_pct_log, top_pnl_pct_arith, ...}
    """
    n = len(trades)
    if n == 0:
        return {"n_total": 0, "valid": False}

    # PnL pct por trade (em escala % do capital, usando log returns para somar)
    pnls_pct = [t["result_r"] * risk_pct for t in trades]
    # log returns somam: total log return = sum(log(1+r))
    import math
    log_rets = [math.log(1 + p) if p > -0.999 else math.log(0.001) for p in pnls_pct]
    total_log = sum(log_rets)

    # Top N% por |log_return|
    n_top = max(1, int(n * top_n_pct))
    log_rets_sorted_abs = sorted(zip(log_rets, range(n)), key=lambda x: abs(x[0]),
                                  reverse=True)
    top_indices = [i for _, i in log_rets_sorted_abs[:n_top]]
    top_log_sum = sum(log_rets[i] for i in top_indices)
    top_log_sum_winners_only = sum(log_rets[i] for i in top_indices if log_rets[i] > 0)
    total_log_winners = sum(r for r in log_rets if r > 0)

    return {
        "valid": True,
        "n_total": n,
        "n_top": n_top,
        "top_n_pct": top_n_pct,
        "total_log_return": round(total_log, 6),
        "total_equity_x": round(math.exp(total_log), 6),
        "top_log_contribution": round(top_log_sum, 6),
        "top_pct_of_total_log": round(100 * top_log_sum / total_log, 2)
                                 if total_log != 0 else None,
        "top_winners_only_log": round(top_log_sum_winners_only, 6),
        "top_pct_of_winners_only": round(100 * top_log_sum_winners_only /
                                          total_log_winners, 2)
                                    if total_log_winners > 0 else None,
    }


def annual_contribution(trades: List[Dict], risk_pct: float = 0.01) -> List[Dict]:
    """% do equity total contribuído por cada ano."""
    import math
    by_year = defaultdict(list)
    for t in trades:
        ts = t.get("entry_ts", "")
        if not ts:
            continue
        year = ts[:4]
        pnl_pct = t["result_r"] * risk_pct
        log_ret = math.log(1 + pnl_pct) if pnl_pct > -0.999 else math.log(0.001)
        by_year[year].append(log_ret)

    if not by_year:
        return []

    total_log = sum(sum(rs) for rs in by_year.values())
    out = []
    for year in sorted(by_year.keys()):
        rs = by_year[year]
        year_log = sum(rs)
        out.append({
            "year": year,
            "n_trades": len(rs),
            "log_return": round(year_log, 6),
            "equity_x": round(math.exp(year_log), 6),
            "pct_of_total": round(100 * year_log / total_log, 2)
                            if total_log != 0 else None,
        })
    return out


def gini_coefficient(values: List[float]) -> float:
    """Gini coefficient sobre |PnL| absoluto (0 = igualdade, 1 = total concentração)."""
    abs_vals = sorted(abs(v) for v in values)
    n = len(abs_vals)
    if n < 2:
        return 0.0
    total = sum(abs_vals)
    if total == 0:
        return 0.0
    cumsum = 0
    for i, v in enumerate(abs_vals, 1):
        cumsum += i * v
    return (2 * cumsum) / (n * total) - (n + 1) / n


def analyze_concentration(trades: List[Dict], risk_pct: float = 0.01) -> Dict:
    """Análise consolidada de concentração de PnL."""
    top1 = top_n_contribution_pct(trades, risk_pct, top_n_pct=0.01)
    top5 = top_n_contribution_pct(trades, risk_pct, top_n_pct=0.05)
    top10 = top_n_contribution_pct(trades, risk_pct, top_n_pct=0.10)
    annual = annual_contribution(trades, risk_pct)
    pnls = [t["result_r"] * risk_pct for t in trades]
    gini = gini_coefficient(pnls)

    # Max single year contribution
    max_year_pct = max((y["pct_of_total"] or 0) for y in annual) if annual else 0

    # Verdict
    flags = []
    if top1.get("top_pct_of_total_log", 0) is not None and \
       abs(top1["top_pct_of_total_log"]) > 50:
        flags.append(f"Top 1% trades = {top1['top_pct_of_total_log']:.1f}% do equity")
    if max_year_pct > 70:
        flags.append(f"1 ano contribui {max_year_pct:.1f}% do equity")
    if gini > 0.85:
        flags.append(f"Gini {gini:.3f} > 0.85 (concentração extrema)")

    verdict = "CONCENTRATED ⚠️" if flags else "DISTRIBUTED ✅"

    return {
        "verdict": verdict,
        "concentration_flags": flags,
        "gini_pnl": round(gini, 4),
        "top_1pct": top1,
        "top_5pct": top5,
        "top_10pct": top10,
        "annual_breakdown": annual,
        "max_year_pct": round(max_year_pct, 2),
    }
