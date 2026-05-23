"""
walk_forward_purged.py — Walk-forward k-fold com purge + embargo (LdP cap 7).

Detecta overfit de "best params" descoberto via grid search.

Metodologia:
1. Split temporal k-fold (default k=5)
2. PURGE: remove trades de treino que sobreponham com período de teste
3. EMBARGO: gap entre fim do treino e início do teste (evita lookahead)
4. Para cada fold: simula com os params dados, mede Sharpe out-of-sample
5. Reporta Sharpe in-sample vs out-of-sample folds

Se OOS Sharpe << IS Sharpe → overfit dos params.
"""
from __future__ import annotations

from datetime import datetime
from typing import Dict, List


def _parse(ts: str) -> datetime:
    return datetime.fromisoformat(ts.replace("Z", "+00:00")).replace(tzinfo=None)


def split_temporal_kfold(trades: List[Dict], k: int = 5,
                          embargo_days: int = 7) -> List[Dict]:
    """
    Split trades em k folds temporais, retorna folds com purge + embargo.

    Returns:
        list of folds: {fold_idx, train_idxs, test_idxs, train_period, test_period}
    """
    if not trades:
        return []
    sorted_trades = sorted(enumerate(trades), key=lambda x: _parse(x[1]["entry_ts"]))
    n = len(sorted_trades)
    fold_size = n // k
    folds = []
    embargo_secs = embargo_days * 86400

    for f in range(k):
        test_start = f * fold_size
        test_end = (f + 1) * fold_size if f < k - 1 else n
        test_pairs = sorted_trades[test_start:test_end]

        if not test_pairs:
            continue

        test_first_ts = _parse(test_pairs[0][1]["entry_ts"])
        test_last_ts = _parse(test_pairs[-1][1]["entry_ts"])

        # Train = todos os trades EXCETO test, com embargo
        train_idxs = []
        for orig_idx, t in sorted_trades:
            t_ts = _parse(t["entry_ts"])
            # Embargo: skip se entry_ts está dentro de embargo_secs antes/depois do test
            delta_to_first = (test_first_ts - t_ts).total_seconds()
            delta_to_last = (t_ts - test_last_ts).total_seconds()
            in_test = test_start <= sorted_trades.index((orig_idx, t)) < test_end
            if in_test:
                continue
            # Purge embargo: skip se < embargo_secs antes/depois do test window
            if 0 <= delta_to_first < embargo_secs:
                continue
            if 0 <= delta_to_last < embargo_secs:
                continue
            train_idxs.append(orig_idx)

        test_idxs = [orig_idx for orig_idx, _ in test_pairs]

        folds.append({
            "fold_idx": f,
            "train_idxs": train_idxs,
            "test_idxs": test_idxs,
            "n_train": len(train_idxs),
            "n_test": len(test_idxs),
            "test_period": (test_first_ts.strftime("%Y-%m-%d"),
                             test_last_ts.strftime("%Y-%m-%d")),
        })
    return folds


def evaluate_fold_metrics(trades_subset: List[Dict], risk_pct: float = 0.01,
                           n_trials: int = 50,
                           sample_var: float = 0.5) -> Dict:
    """Calcula Sharpe/PSR/DSR de um subset de trades."""
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parent))

    from equity_curve_from_trades import build_equity_curve, daily_returns_from_equity
    from metrics_pct_returns import (
        sharpe_from_daily_returns,
        psr_from_daily_returns,
        dsr_from_daily_returns,
    )

    if len(trades_subset) < 30:
        return {"valid": False, "n_trades": len(trades_subset)}

    eq = build_equity_curve(trades_subset, risk_pct=risk_pct)
    rets = daily_returns_from_equity(eq)
    if len(rets) < 30:
        return {"valid": False, "n_returns": len(rets)}

    sharpe = sharpe_from_daily_returns(rets)
    psr = psr_from_daily_returns(rets, sharpe_benchmark=0.0)
    dsr = dsr_from_daily_returns(rets, n_trials=n_trials,
                                  sharpe_benchmark=0.0,
                                  sample_variance_sharpes=sample_var)
    mean_r = sum(t["result_r"] for t in trades_subset) / len(trades_subset)
    win = sum(1 for t in trades_subset if t["result_r"] > 0) / len(trades_subset) * 100
    dates = sorted(eq.keys())
    return {
        "valid": True,
        "n_trades": len(trades_subset),
        "n_days": len(eq),
        "sharpe": round(sharpe, 4),
        "psr": round(psr, 4),
        "dsr": round(dsr, 4),
        "mean_r": round(mean_r, 4),
        "win_rate_pct": round(win, 2),
        "final_equity": round(eq[dates[-1]], 6),
    }


def walk_forward_evaluate(trades: List[Dict], k: int = 5,
                           embargo_days: int = 7,
                           risk_pct: float = 0.01) -> Dict:
    """
    Aplica walk-forward purged k-fold sobre trades já gerados.

    Como trades já vêm de um run com params fixos, isto mede consistência
    do edge ao longo de períodos out-of-sample.
    """
    folds = split_temporal_kfold(trades, k=k, embargo_days=embargo_days)

    in_sample = evaluate_fold_metrics(trades, risk_pct=risk_pct)

    fold_results = []
    for f in folds:
        train_subset = [trades[i] for i in f["train_idxs"]]
        test_subset = [trades[i] for i in f["test_idxs"]]
        train_m = evaluate_fold_metrics(train_subset, risk_pct=risk_pct)
        test_m = evaluate_fold_metrics(test_subset, risk_pct=risk_pct)
        fold_results.append({
            "fold_idx": f["fold_idx"],
            "test_period": f["test_period"],
            "n_train": f["n_train"],
            "n_test": f["n_test"],
            "train_metrics": train_m,
            "test_metrics": test_m,
        })

    # Aggregate test (OOS) metrics
    valid_test_sharpes = [fr["test_metrics"]["sharpe"]
                          for fr in fold_results
                          if fr["test_metrics"].get("valid")]
    valid_test_dsrs = [fr["test_metrics"]["dsr"]
                       for fr in fold_results
                       if fr["test_metrics"].get("valid")]
    positive_folds = sum(1 for s in valid_test_sharpes if s > 0)

    oos_summary = {
        "n_folds_valid": len(valid_test_sharpes),
        "mean_test_sharpe": round(sum(valid_test_sharpes)/len(valid_test_sharpes), 4)
                             if valid_test_sharpes else None,
        "min_test_sharpe": round(min(valid_test_sharpes), 4)
                            if valid_test_sharpes else None,
        "max_test_sharpe": round(max(valid_test_sharpes), 4)
                            if valid_test_sharpes else None,
        "mean_test_dsr": round(sum(valid_test_dsrs)/len(valid_test_dsrs), 4)
                          if valid_test_dsrs else None,
        "positive_sharpe_folds": positive_folds,
        "total_folds": len(fold_results),
    }

    # Verdict
    flags = []
    if in_sample.get("valid") and oos_summary["mean_test_sharpe"] is not None:
        is_sharpe = in_sample["sharpe"]
        oos_mean = oos_summary["mean_test_sharpe"]
        if oos_mean < 0:
            flags.append(f"OOS Sharpe médio negativo ({oos_mean})")
        elif oos_mean < 0.5 * is_sharpe:
            flags.append(f"OOS Sharpe {oos_mean} < 50% do IS Sharpe {is_sharpe} — overfit suspect")
        if positive_folds < (len(fold_results) // 2):
            flags.append(f"Apenas {positive_folds}/{len(fold_results)} folds com Sharpe > 0")

    verdict = "ROBUST ✅" if not flags else "OVERFIT/FRAGILE ⚠️"

    return {
        "verdict": verdict,
        "flags": flags,
        "k_folds": k,
        "embargo_days": embargo_days,
        "in_sample": in_sample,
        "oos_summary": oos_summary,
        "fold_results": fold_results,
    }
