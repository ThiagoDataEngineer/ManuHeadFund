"""
pbo_cscv.py — Probability of Backtest Overfitting via Combinatorial Symmetric
Cross-Validation (Bailey, Borwein, Lopez de Prado, Zhu 2014 / AFML cap 11).

Gate científico definitivo: dado grid de N configs testados em T períodos,
PBO mede a probabilidade que o "best IS" seja overfit (rank OOS na metade pior).

PBO > 0.5 → likely overfit
PBO < 0.5 → genuine edge
PBO ≈ 0   → robust edge

Input: matrix (N_configs × T_periods) de Sharpes.
"""
from __future__ import annotations

from itertools import combinations
from math import log
from typing import Dict, List


def _argmax(xs: List[float]) -> int:
    bi, bv = 0, xs[0]
    for i, v in enumerate(xs):
        if v > bv:
            bv = v
            bi = i
    return bi


def _ranks(xs: List[float]) -> List[int]:
    """Ranks descending (0 = highest)."""
    idx = sorted(range(len(xs)), key=lambda i: -xs[i])
    rk = [0] * len(xs)
    for r, i in enumerate(idx):
        rk[i] = r
    return rk


def pbo_score(matrix: List[List[float]]) -> Dict:
    """
    Combinatorial Symmetric Cross-Validation PBO.

    matrix[config_idx][period_idx] = Sharpe daquela config naquele período.

    Returns:
        {pbo, n_combinations, lambda_distribution_metrics}
    """
    if not matrix or not matrix[0]:
        return {"valid": False, "error": "matrix vazia"}
    n_configs = len(matrix)
    n_periods = len(matrix[0])
    if n_periods < 4:
        return {"valid": False, "error": f"need >=4 periods, got {n_periods}"}
    if n_configs < 2:
        return {"valid": False, "error": f"need >=2 configs, got {n_configs}"}

    half = n_periods // 2
    splits = list(combinations(range(n_periods), half))

    overfit_count = 0
    lambdas = []   # logit transform de relative rank OOS
    n_total = 0

    for is_idx in splits:
        is_set = set(is_idx)
        oos_idx = [i for i in range(n_periods) if i not in is_set]
        if not oos_idx:
            continue

        is_means = [sum(matrix[c][p] for p in is_idx)/len(is_idx)
                    for c in range(n_configs)]
        oos_means = [sum(matrix[c][p] for p in oos_idx)/len(oos_idx)
                     for c in range(n_configs)]

        best_is = _argmax(is_means)
        oos_rk  = _ranks(oos_means)[best_is]   # 0 = top OOS
        rel_rank = (oos_rk + 1) / (n_configs + 1)  # in (0,1)

        # Overfit if best IS lands in worse-half OOS
        if oos_rk > (n_configs - 1) / 2:
            overfit_count += 1

        # Lambda = logit(1 - rel_rank) — LdP transform
        x = 1.0 - rel_rank
        if x <= 0: x = 1e-9
        if x >= 1: x = 1 - 1e-9
        lambdas.append(log(x / (1 - x)))
        n_total += 1

    pbo = overfit_count / n_total if n_total > 0 else None
    mean_lambda = sum(lambdas) / len(lambdas) if lambdas else 0
    return {
        "valid": True,
        "pbo": round(pbo, 4) if pbo is not None else None,
        "n_combinations": n_total,
        "n_configs": n_configs,
        "n_periods": n_periods,
        "mean_lambda": round(mean_lambda, 4),
        "verdict": _verdict(pbo),
    }


def _verdict(pbo: float) -> str:
    if pbo is None: return "n/a"
    if pbo < 0.2: return "ROBUST (PBO<0.2)"
    if pbo < 0.4: return "OK (PBO<0.4)"
    if pbo < 0.5: return "MARGINAL (PBO<0.5)"
    return f"OVERFIT (PBO={pbo:.2f}>=0.5)"


def build_period_matrix(trades_per_config: Dict[str, List[Dict]],
                         n_periods: int = 6,
                         risk_pct: float = 0.01) -> Dict:
    """
    Dado dict config_label -> trades, gera matriz N_configs × N_periods de Sharpes
    por período temporal (splits cronológicos).

    Returns:
        {labels: [...], matrix: [[...]], periods: [(start, end), ...]}
    """
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from equity_curve_from_trades import build_equity_curve, daily_returns_from_equity
    from metrics_pct_returns import sharpe_from_daily_returns
    from datetime import datetime

    if not trades_per_config:
        return {"valid": False}

    # Determine global span
    all_trades = []
    for label, trs in trades_per_config.items():
        all_trades.extend(trs)
    if not all_trades:
        return {"valid": False}

    def _parse(ts):
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).replace(tzinfo=None)

    sorted_all = sorted(all_trades, key=lambda t: _parse(t["entry_ts"]))
    first_ts = _parse(sorted_all[0]["entry_ts"])
    last_ts  = _parse(sorted_all[-1]["entry_ts"])
    total_sec = (last_ts - first_ts).total_seconds()
    period_sec = total_sec / n_periods

    boundaries = []
    for p in range(n_periods + 1):
        boundaries.append(first_ts.timestamp() + p * period_sec)

    labels = sorted(trades_per_config.keys())
    matrix = []
    for label in labels:
        trs = trades_per_config[label]
        row = []
        for p in range(n_periods):
            t_start = boundaries[p]
            t_end = boundaries[p + 1]
            subset = [t for t in trs
                      if t_start <= _parse(t["entry_ts"]).timestamp() < t_end]
            if len(subset) < 10:
                row.append(0.0)
                continue
            eq = build_equity_curve(subset, risk_pct=risk_pct)
            rets = daily_returns_from_equity(eq)
            if len(rets) < 5:
                row.append(0.0)
                continue
            try:
                s = sharpe_from_daily_returns(rets)
            except Exception:
                s = 0.0
            row.append(s)
        matrix.append(row)

    periods = []
    for p in range(n_periods):
        s_dt = datetime.fromtimestamp(boundaries[p]).strftime("%Y-%m-%d")
        e_dt = datetime.fromtimestamp(boundaries[p + 1]).strftime("%Y-%m-%d")
        periods.append((s_dt, e_dt))

    return {
        "valid": True,
        "labels": labels,
        "matrix": matrix,
        "periods": periods,
        "n_configs": len(labels),
        "n_periods": n_periods,
    }
