"""
recalibrate_distribution_filter.py -- Grid search dos thresholds do detector.

Train: 2014-2022 (DANGER={2018,2021,2022}, SAFE=rest)
Holdout: 2023-2025 (DANGER={2025}, SAFE={2023,2024})

Decisao:
  PASS              : F1_holdout >= 0.70 AND positive_years_pct (filtrado) >= 80%
  FAIL_OVERFIT      : F1_train - F1_holdout > 0.15 (gap forte)
  FAIL_INSUFFICIENT : F1_holdout < 0.70 OU positive_years_pct < 80%
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, Sequence, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from distribution_phase_detector import (  # noqa: E402
    _sma,
    ath_drawdown_pct,
    fetch_btc_daily_closes,
    nupl_proxy_score,
    nupl_trajectory,
    pi_cycle_state,
    wma_200_context,
)


# ──────────────────────────────────────────────────────────────────────────────
# Ground truth + particoes
# ──────────────────────────────────────────────────────────────────────────────

GROUND_TRUTH_LABELS: Dict[int, str] = {
    2014: "SAFE",
    2015: "SAFE",
    2016: "SAFE",
    2017: "SAFE",
    2018: "DANGER",
    2019: "SAFE",
    2020: "SAFE",
    2021: "DANGER",
    2022: "DANGER",
    2023: "SAFE",
    2024: "SAFE",
    2025: "DANGER",
}

TRAIN_YEARS = set(range(2014, 2023))   # 2014..2022
HOLDOUT_YEARS = set(range(2023, 2026)) # 2023..2025


def is_train_year(y: int) -> bool:
    return y in TRAIN_YEARS


def is_holdout_year(y: int) -> bool:
    return y in HOLDOUT_YEARS


# ──────────────────────────────────────────────────────────────────────────────
# Grid de parametros
# ──────────────────────────────────────────────────────────────────────────────

DETECTOR_PARAM_GRID: List[Dict] = []
for ath_w in (20, 25, 30):
    for ath_th in (-20.0, -25.0, -30.0):
        for danger_th in (55, 60, 65, 70):
            for warning_th in (30, 35, 40):
                for sem_ratio in (0.80, 0.85, 0.90):
                    DETECTOR_PARAM_GRID.append({
                        "ath_dd_severe_weight": ath_w,
                        "ath_dd_severe_threshold": ath_th,
                        "danger_threshold": danger_th,
                        "warning_threshold": warning_th,
                        "semantic_ratio": sem_ratio,
                    })


# ──────────────────────────────────────────────────────────────────────────────
# Detector parameterizado
# ──────────────────────────────────────────────────────────────────────────────

def detect_with_config(daily_closes: Sequence[float], cfg: Dict,
                       fear_greed: int = 50, funding_rate_8h: float = 0.0) -> str:
    """Detector com thresholds customizados. Retorna apenas state."""
    if not daily_closes or len(daily_closes) < 220:
        return "SAFE"

    closes = list(daily_closes)
    score = 0.0

    # Pi cycle semantico custom
    full_window = closes[-365:] if len(closes) >= 365 else closes
    ath_recent = max(full_window)
    ath_idx_from_end = len(full_window) - 1 - max(
        i for i, v in enumerate(full_window) if v == ath_recent
    )
    current = closes[-1]
    semantic_post_peak = (
        ath_idx_from_end >= 21
        and current < ath_recent * cfg["semantic_ratio"]
    )
    if semantic_post_peak:
        score += 25

    # ATH DD com peso parametrizado
    dd = ath_drawdown_pct(closes)
    if dd <= -50.0:
        score += 35
    elif dd <= cfg["ath_dd_severe_threshold"]:
        score += cfg["ath_dd_severe_weight"]
    elif dd <= -15.0:
        score += 18
    elif dd <= -10.0:
        score += 12
    elif dd <= -5.0:
        score += 5

    # Return 30d
    if len(closes) >= 31 and closes[-31] > 0:
        ret_30 = (closes[-1] / closes[-31] - 1.0) * 100.0
        if ret_30 <= -25.0:
            score += 25
        elif ret_30 <= -15.0:
            score += 18
        elif ret_30 <= -7.0:
            score += 8

    # Sustained-below (consecutivos)
    if ath_recent > 0 and len(closes) >= 60:
        threshold_price = ath_recent * 0.85
        consecutive = 0
        for c in reversed(closes[-60:]):
            if c < threshold_price:
                consecutive += 1
            else:
                break
        if consecutive >= 25:
            score += 22
        elif consecutive >= 15:
            score += 15

    # WMA context
    wma = wma_200_context(closes)
    if wma["status"] == "ABOVE_FAR" and wma["trend"] == "down":
        score += 15
    elif wma["status"] == "BELOW_FAR":
        score += 10

    # Classifica
    if dd <= -50.0:
        return "BEAR_CONFIRMED"
    if score >= cfg["danger_threshold"]:
        return "DANGER"
    if score >= cfg["warning_threshold"]:
        return "WARNING"
    return "SAFE"


# ──────────────────────────────────────────────────────────────────────────────
# F1 evaluation
# ──────────────────────────────────────────────────────────────────────────────

def _binarize(state: str) -> str:
    return "DANGER" if state in ("DANGER", "BEAR_CONFIRMED") else "SAFE"


def evaluate_f1(predictions: Sequence[str], labels: Sequence[str]) -> float:
    """F1 score binario para classe DANGER."""
    if len(predictions) != len(labels):
        raise ValueError("len mismatch")
    if not predictions:
        return 0.0
    tp = sum(1 for p, l in zip(predictions, labels) if _binarize(p) == "DANGER" and l == "DANGER")
    fp = sum(1 for p, l in zip(predictions, labels) if _binarize(p) == "DANGER" and l == "SAFE")
    fn = sum(1 for p, l in zip(predictions, labels) if _binarize(p) == "SAFE" and l == "DANGER")
    if tp + fp == 0 or tp + fn == 0:
        return 0.0
    precision = tp / (tp + fp)
    recall = tp / (tp + fn)
    if precision + recall == 0:
        return 0.0
    return 2 * precision * recall / (precision + recall)


# ──────────────────────────────────────────────────────────────────────────────
# Grid search
# ──────────────────────────────────────────────────────────────────────────────

def grid_search_train(
    train_data: Dict[int, Tuple[List[float], str]],
    grid: List[Dict],
) -> Tuple[Dict, float, List[Dict]]:
    """Para cada cfg, computa F1 agregado em todos os dias de train.

    train_data[year] = (closes_for_year_with_220_history, label).
    Predicao corre dia-a-dia.
    """
    all_results: List[Dict] = []
    best_cfg = grid[0]
    best_f1 = -1.0

    for cfg in grid:
        all_preds: List[str] = []
        all_labels: List[str] = []
        for year, (closes, label) in train_data.items():
            # closes deve ter >= 220 + N_days_year, classifica dia a dia
            for i in range(220, len(closes)):
                state = detect_with_config(closes[i - 220:i + 1], cfg)
                all_preds.append(state)
                all_labels.append(label)
        f1 = evaluate_f1(all_preds, all_labels)
        all_results.append({**cfg, "f1": round(f1, 4)})
        if f1 > best_f1:
            best_f1 = f1
            best_cfg = cfg

    return best_cfg, best_f1, all_results


def evaluate_on_data(
    data: Dict[int, Tuple[List[float], str]],
    cfg: Dict,
) -> Tuple[float, Dict[int, Dict]]:
    """Predicao + F1 sobre dataset, com breakdown por ano."""
    all_preds: List[str] = []
    all_labels: List[str] = []
    by_year: Dict[int, Dict] = {}
    for year, (closes, label) in data.items():
        year_preds: List[str] = []
        for i in range(220, len(closes)):
            state = detect_with_config(closes[i - 220:i + 1], cfg)
            year_preds.append(state)
        year_labels = [label] * len(year_preds)
        all_preds.extend(year_preds)
        all_labels.extend(year_labels)
        # Distribuicao
        n_danger = sum(1 for p in year_preds if _binarize(p) == "DANGER")
        n_total = len(year_preds)
        by_year[year] = {
            "label": label,
            "danger_pct": n_danger / max(1, n_total),
            "n_days": n_total,
            "f1": evaluate_f1(year_preds, year_labels) if n_total > 0 else 0.0,
        }
    return evaluate_f1(all_preds, all_labels), by_year


# ──────────────────────────────────────────────────────────────────────────────
# Filtro aplicado + positive_years
# ──────────────────────────────────────────────────────────────────────────────

def compute_filtered_positive_years_pct(
    cfg: Dict,
    closes_all: List[float],
    baseline_by_year: List[Dict],
) -> float:
    """Aplica filtro com cfg e calcula positive_years_pct.

    Sizing: SAFE=100%, WARNING=50%, DANGER/BEAR=0%.
    Ano e positivo se exp_filtered > 0.
    """
    end_date = datetime.now(timezone.utc).date()
    n_total = len(closes_all)
    pos = 0
    total = 0
    for row in baseline_by_year:
        year = row["year"]
        if year not in GROUND_TRUTH_LABELS:
            continue
        # Classifica dias do ano
        states: List[str] = []
        for i in range(220, n_total):
            d = end_date - timedelta(days=(n_total - 1 - i))
            if d.year != year:
                continue
            states.append(detect_with_config(closes_all[i - 220:i + 1], cfg))
        if not states:
            continue
        n_safe = sum(1 for s in states if s == "SAFE")
        n_warn = sum(1 for s in states if s == "WARNING")
        n_states = len(states)
        avg_sizing = (n_safe + 0.5 * n_warn) / n_states
        operating_pct = (n_safe + n_warn) / n_states
        if operating_pct == 0:
            # Ano todo filtrado -> considerar neutro (positivo: exp = 0 nao conta)
            total += 1
            continue
        exp_filtered = row["expectancy_r"] * (avg_sizing / operating_pct)
        total += 1
        if exp_filtered > 0:
            pos += 1
    return (pos / total) * 100.0 if total > 0 else 0.0


# ──────────────────────────────────────────────────────────────────────────────
# Decisao
# ──────────────────────────────────────────────────────────────────────────────

@dataclass
class DecisionResult:
    decision: str          # PASS | FAIL_OVERFIT | FAIL_INSUFFICIENT
    f1_train: float
    f1_holdout: float
    positive_years_pct: float
    reason: str


def decide_outcome(f1_train: float, f1_holdout: float, positive_years_pct: float) -> DecisionResult:
    if f1_holdout >= 0.70 and positive_years_pct >= 80.0:
        return DecisionResult(
            decision="PASS",
            f1_train=f1_train, f1_holdout=f1_holdout,
            positive_years_pct=positive_years_pct,
            reason="F1 holdout >= 0.70 e positive_years_pct >= 80%",
        )
    if f1_train - f1_holdout > 0.15:
        return DecisionResult(
            decision="FAIL_OVERFIT",
            f1_train=f1_train, f1_holdout=f1_holdout,
            positive_years_pct=positive_years_pct,
            reason=f"Gap F1 train-holdout {f1_train - f1_holdout:.3f} > 0.15",
        )
    return DecisionResult(
        decision="FAIL_INSUFFICIENT",
        f1_train=f1_train, f1_holdout=f1_holdout,
        positive_years_pct=positive_years_pct,
        reason=f"F1 holdout {f1_holdout:.3f} < 0.70 ou positive_years_pct {positive_years_pct:.1f}% < 80%",
    )


# ──────────────────────────────────────────────────────────────────────────────
# Builder de datasets train/holdout
# ──────────────────────────────────────────────────────────────────────────────

def build_year_dataset(closes_all: List[float], years: Sequence[int]) -> Dict[int, Tuple[List[float], str]]:
    """Para cada year, junta 220 dias de historico + dias do ano."""
    end_date = datetime.now(timezone.utc).date()
    n_total = len(closes_all)
    # Mapear idx -> date
    idx_dates = [end_date - timedelta(days=(n_total - 1 - i)) for i in range(n_total)]

    out: Dict[int, Tuple[List[float], str]] = {}
    for y in years:
        label = GROUND_TRUTH_LABELS.get(y)
        if label is None:
            continue
        # Indices do ano
        year_idxs = [i for i, d in enumerate(idx_dates) if d.year == y]
        if not year_idxs:
            continue
        first = year_idxs[0]
        last = year_idxs[-1]
        start_idx = max(0, first - 220)
        sub = closes_all[start_idx:last + 1]
        if len(sub) < 220 + 10:
            continue
        out[y] = (sub, label)
    return out


# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

BASELINE_14Y_JSON = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "journal", "benchmark_long_14y_results.json"
)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "journal", "task1b_recalibrated_filter.json"
    ))
    parser.add_argument("--grid-limit", type=int, default=0,
                        help="Limita grid pra testes (0=full)")
    args = parser.parse_args()

    print("[1/5] Carregando closes BTC diarios (Bitstamp)...")
    closes = fetch_btc_daily_closes()
    print(f"  closes={len(closes)}")

    print("[2/5] Construindo train e holdout...")
    train_data = build_year_dataset(closes, sorted(TRAIN_YEARS))
    holdout_data = build_year_dataset(closes, sorted(HOLDOUT_YEARS))
    print(f"  train years={sorted(train_data.keys())}, holdout years={sorted(holdout_data.keys())}")

    grid = DETECTOR_PARAM_GRID
    if args.grid_limit > 0:
        grid = grid[:args.grid_limit]
    print(f"[3/5] Grid search {len(grid)} combinacoes em train...")
    best_cfg, best_f1_train, all_results = grid_search_train(train_data, grid)
    print(f"  best F1 train = {best_f1_train:.4f}")
    print(f"  best_cfg = {best_cfg}")

    print("[4/5] Avaliando holdout (sem re-tunar)...")
    f1_holdout, holdout_breakdown = evaluate_on_data(holdout_data, best_cfg)
    f1_train, train_breakdown = evaluate_on_data(train_data, best_cfg)
    print(f"  F1 train = {f1_train:.4f}")
    print(f"  F1 holdout = {f1_holdout:.4f}")

    print("[5/5] Calculando positive_years_pct com filtro...")
    with open(BASELINE_14Y_JSON, "r", encoding="utf-8") as f:
        baseline = json.load(f)
    pos_years_pct = compute_filtered_positive_years_pct(best_cfg, closes, baseline["by_year"])
    print(f"  positive_years_pct filtered = {pos_years_pct:.1f}%")

    decision = decide_outcome(f1_train, f1_holdout, pos_years_pct)
    print(f"\n  decision = {decision.decision}")

    # Top 10 configs por f1
    top10 = sorted(all_results, key=lambda r: r["f1"], reverse=True)[:10]

    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "best_thresholds": best_cfg,
        "f1_train": round(f1_train, 4),
        "f1_holdout": round(f1_holdout, 4),
        "positive_years_pct": round(pos_years_pct, 1),
        "decision": decision.decision,
        "decision_reason": decision.reason,
        "train_breakdown": {str(k): v for k, v in train_breakdown.items()},
        "holdout_breakdown": {str(k): v for k, v in holdout_breakdown.items()},
        "top10_train_configs": top10,
        "grid_size": len(grid),
    }

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print(f"\n[OK] saved: {args.output}\n")
    print(json.dumps({
        "best_thresholds": report["best_thresholds"],
        "f1_train": report["f1_train"],
        "f1_holdout": report["f1_holdout"],
        "positive_years_pct": report["positive_years_pct"],
        "decision": report["decision"],
        "reason": report["decision_reason"],
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
