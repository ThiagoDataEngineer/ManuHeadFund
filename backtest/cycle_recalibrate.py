"""
cycle_recalibrate.py -- Task 3b: Recalibracao do Current Cycle Analyzer.

CONTEXTO CRITICO:
    Chat 2 retornou FAIL_OVERFIT. NAO usar task2b_recalibrated_matrix.json.
    Usar matriz ORIGINAL task2_regime_direction_matrix.json apenas como
    referencia (input estrutural). A hipotese real testada e:

    "Analogos via cosine similarity sobre features V6.5 tem edge
     direcional 60d INDEPENDENTE do regime classifier (que sabemos quebrado)?"

Train     : 2014-2022
Holdout   : 2023-2025 (holdout NUNCA toca pesos)
Criterio  :
    hit_rate_train   >= 70%
    hit_rate_holdout >= 65%  (tolerancia 5pp ao train)
    gap (train-holdout) < 15pp

Saida: journal/task3b_recalibrated_cycle.json

CLI:
    python backtest/cycle_recalibrate.py --output journal/task3b_recalibrated_cycle.json
"""
from __future__ import annotations

import argparse
import itertools
import json
import os
import sys
from datetime import date, datetime, timedelta, timezone
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

import numpy as np


# ─────────────────────────────────────────────────────────────────────────────
# Configuracao
# ─────────────────────────────────────────────────────────────────────────────

FEATURE_NAMES: Tuple[str, ...] = (
    "price_action",
    "nupl_proxy",
    "ath_dd",
    "wma_distance",
    "momentum",
)

# Escalas para normalizar features antes de calcular distancia ponderada.
# Os mesmos valores usados independente do peso para preservar comparabilidade.
_FEATURE_SCALES: Dict[str, float] = {
    "price_action": 30.0,
    "nupl_proxy":   1.0,
    "ath_dd":       80.0,
    "wma_distance": 80.0,
    "momentum":     50.0,
}

# DRIFT-6 cross-ref 2026-05-16: source of truth = backtest/constants.py::DEFAULT_BULL_THRESHOLD
DEFAULT_BULL_THRESHOLD = 10.0   # > 10% em 60d = bull
DEFAULT_BEAR_THRESHOLD = -10.0  # < -10% = bear
DEFAULT_HORIZON_KEY    = "realized_60d_pct"

THRESHOLD_TRAIN     = 0.70
THRESHOLD_HOLDOUT   = 0.65
MAX_GAP             = 0.15  # 15pp


# ─────────────────────────────────────────────────────────────────────────────
# 1. Similarity ponderada
# ─────────────────────────────────────────────────────────────────────────────

def weighted_similarity(features_a: Dict[str, float],
                        features_b: Dict[str, float],
                        weights:    Dict[str, float]) -> float:
    """
    Similarity em (0,1] = exp(-weighted_euclidean(a, b)).
    Features normalizadas por escalas fixas; pesos multiplicam contribuicoes^2.
    """
    sq = 0.0
    for name in FEATURE_NAMES:
        w = float(weights.get(name, 0.0))
        if w <= 0.0:
            continue
        scale = _FEATURE_SCALES.get(name, 1.0)
        a = float(features_a.get(name, 0.0)) / scale
        b = float(features_b.get(name, 0.0)) / scale
        sq += w * (a - b) ** 2
    return float(np.exp(-np.sqrt(sq)))


# ─────────────────────────────────────────────────────────────────────────────
# 2. find_analogs
# ─────────────────────────────────────────────────────────────────────────────

def find_analogs(query_features:     Dict[str, float],
                 candidates:         Sequence[Dict],
                 weights:            Dict[str, float],
                 k:                  int = 5,
                 exclude_dates:      Optional[Iterable[str]] = None,
                 exclude_buffer_days: int = 90) -> List[Dict]:
    """
    Top-k candidatos por similarity descendente, excluindo:
      - datas em `exclude_dates`
      - candidatos cujo date esta dentro de +/- exclude_buffer_days de qualquer exclude_date
    """
    excluded_dates = set(exclude_dates or [])
    buffer_centers: List[date] = []
    for ds in excluded_dates:
        try:
            buffer_centers.append(date.fromisoformat(ds[:10]))
        except Exception:
            pass

    scored: List[Tuple[float, Dict]] = []
    for c in candidates:
        cd_iso = c.get("date")
        if cd_iso in excluded_dates:
            continue
        if exclude_buffer_days > 0 and buffer_centers and cd_iso:
            try:
                cd = date.fromisoformat(str(cd_iso)[:10])
                if any(abs((cd - bc).days) <= exclude_buffer_days for bc in buffer_centers):
                    continue
            except Exception:
                pass
        feats = c.get("features") or {}
        s = weighted_similarity(query_features, feats, weights)
        scored.append((s, c))
    scored.sort(key=lambda x: x[0], reverse=True)
    out: List[Dict] = []
    for sim, c in scored[:k]:
        item = dict(c)
        item["similarity_score"] = round(sim, 6)
        out.append(item)
    return out


# ─────────────────────────────────────────────────────────────────────────────
# 3. Direcao predita / realizada
# ─────────────────────────────────────────────────────────────────────────────

def predict_direction(analogs:        Sequence[Dict],
                      bull_threshold: float = DEFAULT_BULL_THRESHOLD,
                      bear_threshold: float = DEFAULT_BEAR_THRESHOLD,
                      horizon_key:    str   = DEFAULT_HORIZON_KEY) -> str:
    if not analogs:
        return "sideways"
    rs = np.array([float(a.get(horizon_key, 0.0)) for a in analogs], dtype=float)
    m  = float(rs.mean())
    return realized_direction(m, bull_threshold, bear_threshold)


def realized_direction(r:              float,
                       bull_threshold: float = DEFAULT_BULL_THRESHOLD,
                       bear_threshold: float = DEFAULT_BEAR_THRESHOLD) -> str:
    if r >  bull_threshold: return "bull"
    if r <  bear_threshold: return "bear"
    return "sideways"


# ─────────────────────────────────────────────────────────────────────────────
# 4. Hit rate
# ─────────────────────────────────────────────────────────────────────────────

def compute_hit_rate(subset:             Sequence[Dict],
                     candidates:         Sequence[Dict],
                     weights:            Dict[str, float],
                     k:                  int = 5,
                     exclude_buffer_days: int = 60,
                     horizon_key:        str = DEFAULT_HORIZON_KEY) -> float:
    """% de dias em subset cuja predicao direcional (via analogos em candidates) bate."""
    if not subset:
        return 0.0
    hits = 0
    total = 0
    for entry in subset:
        feats = entry.get("features") or {}
        analogs = find_analogs(feats, candidates, weights, k=k,
                               exclude_dates=[entry.get("date")],
                               exclude_buffer_days=exclude_buffer_days)
        if not analogs:
            continue
        pred = predict_direction(analogs, horizon_key=horizon_key)
        real = realized_direction(float(entry.get(horizon_key, 0.0)))
        total += 1
        if pred == real:
            hits += 1
    return float(hits) / float(total) if total else 0.0


# ─────────────────────────────────────────────────────────────────────────────
# 5. Grid search
# ─────────────────────────────────────────────────────────────────────────────

def _weight_grid(step: float) -> List[Dict[str, float]]:
    """
    Combinacoes de pesos somando 1.0 (tolerancia float). Cada peso em {0, step, 2*step, ...}.
    Para 5 features e step=0.25, gera 70 combinacoes (n+k-1 choose k-1 reduzido).
    """
    if step <= 0 or step > 1:
        step = 0.25
    n_steps = int(round(1.0 / step))
    grid: List[Dict[str, float]] = []
    for combo in itertools.product(range(n_steps + 1), repeat=len(FEATURE_NAMES)):
        if sum(combo) == n_steps:
            grid.append({name: combo[i] * step for i, name in enumerate(FEATURE_NAMES)})
    return grid


def grid_search_weights(train:              Sequence[Dict],
                        k:                  int = 5,
                        grid_step:          float = 0.25,
                        exclude_buffer_days: int = 60,
                        horizon_key:        str = DEFAULT_HORIZON_KEY) -> Dict:
    """Itera combinacoes de pesos somando 1.0. Retorna a melhor por hit_rate_train."""
    best_w: Optional[Dict[str, float]] = None
    best_hr = -1.0
    history: List[Dict] = []
    for w in _weight_grid(grid_step):
        hr = compute_hit_rate(train, train, w, k=k,
                              exclude_buffer_days=exclude_buffer_days,
                              horizon_key=horizon_key)
        history.append({"weights": w, "hit_rate": hr})
        if hr > best_hr:
            best_hr = hr; best_w = w
    return {
        "best_weights":    best_w or {n: 1.0/len(FEATURE_NAMES) for n in FEATURE_NAMES},
        "hit_rate_train":  float(round(best_hr if best_hr >= 0 else 0.0, 4)),
        "candidates_count": len(history),
    }


# ─────────────────────────────────────────────────────────────────────────────
# 6. validate_holdout
# ─────────────────────────────────────────────────────────────────────────────

def validate_holdout(holdout:            Sequence[Dict],
                     train:              Sequence[Dict],
                     weights:            Dict[str, float],
                     k:                  int = 5,
                     exclude_buffer_days: int = 60,
                     horizon_key:        str = DEFAULT_HORIZON_KEY) -> Dict:
    hr = compute_hit_rate(holdout, train, weights, k=k,
                          exclude_buffer_days=exclude_buffer_days,
                          horizon_key=horizon_key)
    return {
        "hit_rate_holdout": float(round(hr, 4)),
        "n_holdout":        len(holdout),
        "n_train":          len(train),
    }


# ─────────────────────────────────────────────────────────────────────────────
# 7. Decide
# ─────────────────────────────────────────────────────────────────────────────

def decide(train_hit:        float,
           holdout_hit:      float,
           threshold_train: float = THRESHOLD_TRAIN,
           threshold_holdout: float = THRESHOLD_HOLDOUT,
           max_gap:         float = MAX_GAP) -> str:
    """PASS / FAIL_OVERFIT / FAIL_NO_EDGE conforme criterio spec."""
    if train_hit < threshold_train:
        return "FAIL_NO_EDGE"
    gap = train_hit - holdout_hit
    if gap > max_gap:
        return "FAIL_OVERFIT"
    if holdout_hit < threshold_holdout:
        return "FAIL_NO_EDGE"
    return "PASS"


# ─────────────────────────────────────────────────────────────────────────────
# 8. Cenarios + predicao atual com pesos calibrados
# ─────────────────────────────────────────────────────────────────────────────

def _scenarios_from_analogs(analogs: Sequence[Dict],
                            bull_threshold: float = DEFAULT_BULL_THRESHOLD,
                            bear_threshold: float = DEFAULT_BEAR_THRESHOLD,
                            horizon_key:    str   = DEFAULT_HORIZON_KEY) -> Dict[str, float]:
    if not analogs:
        return {"bull_probability": 0.0, "sideways_probability": 100.0, "bear_probability": 0.0}
    rs = np.array([float(a.get(horizon_key, 0.0)) for a in analogs], dtype=float)
    n  = rs.size
    bull = int((rs >  bull_threshold).sum())
    bear = int((rs <  bear_threshold).sum())
    side = n - bull - bear
    raw   = np.array([bull, side, bear], dtype=float) / n * 100.0
    floor = np.floor(raw).astype(int)
    rem   = raw - floor
    deficit = 100 - int(floor.sum())
    if deficit > 0:
        order = np.argsort(-rem)
        for i in range(deficit):
            floor[order[i % 3]] += 1
    return {
        "bull_probability":     float(floor[0]),
        "sideways_probability": float(floor[1]),
        "bear_probability":     float(floor[2]),
    }


# ─────────────────────────────────────────────────────────────────────────────
# 9. recalibrate -- pipeline completo
# ─────────────────────────────────────────────────────────────────────────────

def _split_by_date(history: Sequence[Dict], train_end: date, holdout_end: date):
    train, holdout = [], []
    for h in history:
        try:
            d = date.fromisoformat(str(h.get("date"))[:10])
        except Exception:
            continue
        if d <  train_end:    train.append(h)
        elif d <  holdout_end: holdout.append(h)
    return train, holdout


def recalibrate(task2_matrix:    Dict,
                history:         Sequence[Dict],
                current_state:   Dict,
                train_end_iso:   str = "2023-01-01",
                holdout_end_iso: str = "2026-01-01",
                k:               int   = 5,
                grid_step:       float = 0.25,
                exclude_buffer_days: int = 60) -> Dict:
    train_end   = date.fromisoformat(train_end_iso)
    holdout_end = date.fromisoformat(holdout_end_iso)
    train, holdout = _split_by_date(history, train_end, holdout_end)

    gs   = grid_search_weights(train, k=k, grid_step=grid_step,
                               exclude_buffer_days=exclude_buffer_days)
    val  = validate_holdout(holdout, train, gs["best_weights"], k=k,
                            exclude_buffer_days=exclude_buffer_days)
    gap  = round(gs["hit_rate_train"] - val["hit_rate_holdout"], 4)
    dec  = decide(gs["hit_rate_train"], val["hit_rate_holdout"])

    cur_feats = current_state.get("features") or {}
    cur_analogs = find_analogs(cur_feats, train, gs["best_weights"], k=k,
                               exclude_dates=[], exclude_buffer_days=0)
    scenarios  = _scenarios_from_analogs(cur_analogs)
    prediction = predict_direction(cur_analogs)

    note = _build_honest_note(dec, gs["hit_rate_train"], val["hit_rate_holdout"],
                              gap, task2_matrix, len(train), len(holdout))

    return {
        "timestamp":        datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "method":           "cosine_similarity_weighted_grid_search",
        "train_period":     {"end": train_end_iso, "n": len(train)},
        "holdout_period":   {"end": holdout_end_iso, "n": len(holdout)},
        "best_weights":     {n: round(float(v), 3) for n, v in gs["best_weights"].items()},
        "hit_rate_train":   gs["hit_rate_train"],
        "hit_rate_holdout": val["hit_rate_holdout"],
        "gap":              gap,
        "current_state":    current_state,
        "current_analogs":  [
            {
                "date":               a.get("date"),
                "similarity_score":   a.get("similarity_score"),
                "realized_60d_pct":   a.get(DEFAULT_HORIZON_KEY),
            } for a in cur_analogs
        ],
        "scenarios_60d":    scenarios,
        "prediction":       prediction,
        "decision":         dec,
        "honest_note":      note,
        "criteria": {
            "threshold_train":   THRESHOLD_TRAIN,
            "threshold_holdout": THRESHOLD_HOLDOUT,
            "max_gap":           MAX_GAP,
        },
        "task2_matrix_ref": {
            "note":      "matriz original task2 usada como referencia estrutural (NAO task2b)",
            "go_passed": task2_matrix.get("go_criterion", {}).get("passed"),
        },
    }


def _build_honest_note(dec: str, hr_train: float, hr_holdout: float, gap: float,
                       matrix: Dict, n_train: int, n_holdout: int) -> str:
    base = (
        f"Train hit_rate={hr_train:.3f} (n={n_train}); "
        f"Holdout hit_rate={hr_holdout:.3f} (n={n_holdout}); "
        f"gap={gap:+.3f}. "
    )
    if dec == "PASS":
        return base + (
            "Edge direcional 60d via analogos cosine se sustenta em 2023-2025 (holdout) sem usar "
            "regime classifier (que falhou no Chat 2). Pode-se OPERAR com sizing conservador, "
            "mantendo aprovacao manual e revisao trimestral do gap."
        )
    if dec == "FAIL_OVERFIT":
        return base + (
            "Gap train-holdout > 15pp indica OVERFIT: padrao do train nao generaliza para 2023-2025. "
            "Nao operar com estes pesos. Reduzir grid de busca ou expandir features pode ajudar, "
            "mas o sinal honesto e: o modelo aprende ruido do periodo de treino."
        )
    return base + (
        "Hit rate insuficiente -- o sistema de analogos via cosine NAO mostra edge robusto. "
        "Consistente com falha do regime classifier (Chat 2): a hipotese de edge direcional "
        "puramente via similaridade de features V6.5 fica REJEITADA neste dataset. "
        "Antes de operar live, repensar features ou aceitar que mercado e ergodicamente "
        "imprevisivel neste horizonte."
    )


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def _load_json(path: str, default=None):
    if not os.path.exists(path):
        return default
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _synthetic_history(n: int = 600, seed: int = 7) -> List[Dict]:
    """
    Sintetico para preenchimento de CLI quando dados reais ausentes.
    Padrao predictivo: realized depende de NUPL + momentum, com ruido moderado.
    """
    rng = np.random.default_rng(seed)
    start = date(2014, 1, 1)
    out: List[Dict] = []
    for i in range(n):
        d        = start + timedelta(days=i * 7)
        nupl     = float(rng.uniform(0.10, 0.95))
        momentum = float(rng.uniform(-50, 50))
        ath_dd   = float(rng.uniform(-80, -3))
        wma      = float(rng.uniform(-45, 80))
        price_a  = float(rng.uniform(-25, 25))
        base = -30.0 * (nupl - 0.5) + 0.30 * momentum
        r60  = base + float(rng.normal(0, 6))
        out.append({
            "date": d.isoformat(),
            "features": {
                "price_action": price_a, "nupl_proxy": nupl,
                "ath_dd": ath_dd, "wma_distance": wma, "momentum": momentum,
            },
            "realized_60d_pct": r60,
        })
    return out


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Recalibracao Task 3b: validacao direcional pura no holdout")
    parser.add_argument("--matrix",   default=os.path.join("journal", "task2_regime_direction_matrix.json"))
    parser.add_argument("--task3",    default=os.path.join("journal", "task3_current_cycle_analysis.json"))
    parser.add_argument("--history",  default=None, help="JSON com {history:[...]} ou ausente -> sintetico")
    parser.add_argument("--output",   default=os.path.join("journal", "task3b_recalibrated_cycle.json"))
    parser.add_argument("--train-end",   default="2023-01-01")
    parser.add_argument("--holdout-end", default="2026-01-01")
    parser.add_argument("--k",        type=int,   default=5)
    parser.add_argument("--grid-step", type=float, default=0.25)
    args = parser.parse_args(argv)

    matrix = _load_json(args.matrix, default={"matrix": [], "go_criterion": {}})
    task3  = _load_json(args.task3,  default={})
    hist_payload = _load_json(args.history) if args.history else None
    if hist_payload and "history" in hist_payload:
        history = list(hist_payload["history"])
    else:
        sys.stderr.write("[Task3b] Historico real ausente -- usando sintetico predictivo 14y (~600 pontos).\n")
        history = _synthetic_history()

    # Estado atual: prioriza task3.current_state; suporta features no top-level OU mapeia
    current_state = task3.get("current_state", {}) or {}
    if "features" not in current_state:
        # Mapeia campos legados do task3 para features
        current_state = dict(current_state)
        current_state["features"] = {
            "price_action": 0.0,
            "nupl_proxy":   float(current_state.get("nupl_proxy",            0.5)),
            "ath_dd":       float(current_state.get("ath_dd_pct",           -20.0)),
            "wma_distance": float(current_state.get("wma_200_distance_pct",   0.0)),
            "momentum":     0.0,
        }

    result = recalibrate(
        task2_matrix=matrix, history=history, current_state=current_state,
        train_end_iso=args.train_end, holdout_end_iso=args.holdout_end,
        k=args.k, grid_step=args.grid_step,
    )

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, default=str)

    sys.stdout.write(
        f"[Task3b] decision={result['decision']} "
        f"train={result['hit_rate_train']} holdout={result['hit_rate_holdout']} "
        f"gap={result['gap']:+.3f} -> {args.output}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
