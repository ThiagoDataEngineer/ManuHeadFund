"""
current_cycle_analyzer.py -- Task 3: now-cast de ciclo com lente historica (TDD).

Pergunta:
    "Onde estamos AGORA? Quais periodos historicos foram mais parecidos?
     O que aconteceu 30/60/90 dias depois deles?"

Pipeline:
    1) build_state_vector  : codifica estado atual em vetor numerico V6.5.
    2) find_similar_periods: distancia euclidiana normalizada -> top_n analogs.
    3) compute_outcomes    : estatistica dos future_returns dos analogs.
    4) compute_scenarios   : prob bull / sideways / bear (somam 100).
    5) compute_confidence  : consistencia direcional dos analogs.
    6) is_unprecedented    : nenhum analog com similarity >= threshold.
    7) recommend           : FAVORABLE_LONG / FAVORABLE_SHORT / MIXED / AVOID / UNPRECEDENTED.

CLI:
    python backtest/current_cycle_analyzer.py
    python backtest/current_cycle_analyzer.py --top-n 5 --output journal/task3_current_cycle_analysis.json
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

import numpy as np


# ─────────────────────────────────────────────────────────────────────────────
# Codificacao de features categoricas (mantida estavel para reproducibilidade)
# ─────────────────────────────────────────────────────────────────────────────

_REGIME_CODE = {
    "BULL":             2.0,
    "TRANSITION_UP":    1.5,
    "SIDEWAYS":         1.0,
    "NEUTRAL":          1.0,
    "TRANSITION_DOWN":  0.5,
    "BEAR":             0.0,
}

_PI_CODE = {
    "NEUTRAL":   0.0,
    "BEFORE":    1.0,
    "TRIGGERED": 2.0,
    "POST_PEAK": 2.5,
}

_MACRO_CODE = {
    "BEARISH": 0.0,
    "NEUTRAL": 1.0,
    "BULLISH": 2.0,
}

# Escalas para normalizar componentes continuos antes do calculo de distancia.
# Ordem: [regime, pi, ath_dd, nupl, wma_200, macro]
_FEATURE_SCALES = np.array([2.0, 2.5, 80.0, 1.0, 80.0, 2.0])

# DRIFT-6 cross-ref 2026-05-16: source of truth = backtest/constants.py::DEFAULT_BULL_THRESHOLD
DEFAULT_BULL_THRESHOLD = 10.0   # % return acima disso = bull
DEFAULT_BEAR_THRESHOLD = -10.0
DEFAULT_UNPRECEDENTED_THRESHOLD = 0.3


# ─────────────────────────────────────────────────────────────────────────────
# 1. State vector
# ─────────────────────────────────────────────────────────────────────────────

def build_state_vector(state: Dict) -> np.ndarray:
    """Codifica estado em vetor V6.5: [regime, pi, ath_dd, nupl, wma_200, macro]."""
    return np.array([
        _REGIME_CODE.get(str(state.get("regime", "NEUTRAL")).upper(),     1.0),
        _PI_CODE.get(   str(state.get("pi_cycle", "NEUTRAL")).upper(),    0.0),
        float(state.get("ath_dd_pct",           0.0)),
        float(state.get("nupl_proxy",           0.5)),
        float(state.get("wma_200_distance_pct", 0.0)),
        _MACRO_CODE.get(str(state.get("macro_bias", "NEUTRAL")).upper(),  1.0),
    ], dtype=float)


# ─────────────────────────────────────────────────────────────────────────────
# 2. Similarity (0..1)
# ─────────────────────────────────────────────────────────────────────────────

def similarity(vec_a: np.ndarray, vec_b: np.ndarray) -> float:
    """Distancia euclidiana normalizada -> similarity em 0..1."""
    a = np.asarray(vec_a, dtype=float) / _FEATURE_SCALES
    b = np.asarray(vec_b, dtype=float) / _FEATURE_SCALES
    dist = float(np.linalg.norm(a - b))
    # exp(-d): identidade=1.0, decai rapido em estados muito divergentes
    return float(np.exp(-dist))


# ─────────────────────────────────────────────────────────────────────────────
# 3. Find similar periods
# ─────────────────────────────────────────────────────────────────────────────

def find_similar_periods(current_state: Dict,
                         history: Sequence[Dict],
                         top_n: int = 5) -> List[Dict]:
    """
    history: lista de { date, state, future_returns:{30d,60d,90d} }.
    Retorna top_n entradas com similarity_score (decrescente).
    """
    cur_vec = build_state_vector(current_state)
    scored: List[Tuple[float, Dict]] = []
    for h in history:
        st = h.get("state") or {}
        s  = similarity(cur_vec, build_state_vector(st))
        scored.append((s, h))
    scored.sort(key=lambda x: x[0], reverse=True)

    out: List[Dict] = []
    for sim, h in scored[:top_n]:
        fr = h.get("future_returns") or {}
        r60 = float(fr.get("60d", 0.0))
        label = _outcome_label(r60)
        out.append({
            "period_start":    h.get("date"),
            "period_end":      _add_days_iso(h.get("date"), 60),
            "similarity_score": round(sim, 4),
            "outcome_30d_pct": round(float(fr.get("30d", 0.0)), 2),
            "outcome_60d_pct": round(r60, 2),
            "outcome_90d_pct": round(float(fr.get("90d", 0.0)), 2),
            "outcome_label":   label,
            # mantemos future_returns inteiro para outcomes/cenarios
            "future_returns":  {k: float(v) for k, v in fr.items()},
        })
    return out


def _add_days_iso(d_iso: Optional[str], days: int) -> Optional[str]:
    if not d_iso:
        return None
    try:
        from datetime import date as _date
        return (_date.fromisoformat(str(d_iso)[:10]) + (
            __import__("datetime").timedelta(days=days)
        )).isoformat()
    except Exception:
        return None


def _outcome_label(r60: float) -> str:
    if r60 >=  DEFAULT_BULL_THRESHOLD: return "BULL_PROGRESSION"
    if r60 <=  DEFAULT_BEAR_THRESHOLD: return "BEAR_PROGRESSION"
    return "SIDEWAYS"


# ─────────────────────────────────────────────────────────────────────────────
# 4. Outcomes per horizon
# ─────────────────────────────────────────────────────────────────────────────

def compute_outcomes(analogs: Sequence[Dict],
                     horizons: Iterable[str] = ("30d", "60d", "90d")) -> Dict[str, Dict]:
    """Para cada horizon, retorna mean/std/win_rate/max_dd entre os analogs."""
    out: Dict[str, Dict] = {}
    for h in horizons:
        rs = np.array(
            [float((a.get("future_returns") or {}).get(h, 0.0)) for a in analogs],
            dtype=float,
        )
        if rs.size == 0:
            out[h] = {"mean": 0.0, "std": 0.0, "win_rate": 0.0, "max_dd": 0.0}
            continue
        equity = np.cumsum(rs)
        peaks  = np.maximum.accumulate(equity)
        out[h] = {
            "mean":     round(float(rs.mean()), 3),
            "std":      round(float(rs.std()),  3),
            "win_rate": round(float((rs > 0).sum()) / rs.size, 3),
            "max_dd":   round(float((peaks - equity).max()), 3),
        }
    return out


# ─────────────────────────────────────────────────────────────────────────────
# 5. Probabilistic scenarios (bull/sideways/bear) -- somam 100
# ─────────────────────────────────────────────────────────────────────────────

def compute_scenarios(analogs: Sequence[Dict], horizon: str = "60d",
                      bull_threshold: float = DEFAULT_BULL_THRESHOLD,
                      bear_threshold: float = DEFAULT_BEAR_THRESHOLD) -> Dict[str, float]:
    rs = np.array(
        [float((a.get("future_returns") or {}).get(horizon, 0.0)) for a in analogs],
        dtype=float,
    )
    if rs.size == 0:
        return {"bull_probability": 0.0, "sideways_probability": 100.0, "bear_probability": 0.0}

    n = rs.size
    bull = int((rs >  bull_threshold).sum())
    bear = int((rs <  bear_threshold).sum())
    side = n - bull - bear

    # Arredonda mantendo soma = 100 (largest remainder method)
    raw = np.array([bull, side, bear], dtype=float) / n * 100.0
    floor = np.floor(raw).astype(int)
    remainder = raw - floor
    deficit = 100 - floor.sum()
    if deficit > 0:
        # distribui o deficit pelos maiores residuos
        order = np.argsort(-remainder)
        for i in range(deficit):
            floor[order[i % 3]] += 1
    return {
        "bull_probability":     float(floor[0]),
        "sideways_probability": float(floor[1]),
        "bear_probability":     float(floor[2]),
    }


# ─────────────────────────────────────────────────────────────────────────────
# 6. Confidence: consistencia direcional + similaridade dos analogs
# ─────────────────────────────────────────────────────────────────────────────

def compute_confidence(analogs: Sequence[Dict], horizon: str = "60d") -> float:
    if not analogs:
        return 0.0
    rs = np.array(
        [float((a.get("future_returns") or {}).get(horizon, 0.0)) for a in analogs],
        dtype=float,
    )
    sims = np.array([float(a.get("similarity_score", 0.0)) for a in analogs])
    sim_avg = float(sims.mean()) if sims.size else 0.0
    if rs.size == 0:
        return 0.0

    mean = float(rs.mean())
    if mean == 0:
        direction_consistency = 0.0
    else:
        same_sign = float((rs > 0).sum() if mean > 0 else (rs < 0).sum())
        direction_consistency = same_sign / rs.size

    # Penaliza dispersao alta relativa a magnitude do mean
    cv = float(rs.std() / (abs(mean) + 1e-9))
    magnitude_consistency = max(0.0, 1.0 - min(cv, 1.0))

    score = 0.5 * direction_consistency + 0.3 * magnitude_consistency + 0.2 * sim_avg
    return float(round(max(0.0, min(1.0, score)), 3))


# ─────────────────────────────────────────────────────────────────────────────
# 7. Unprecedented detection
# ─────────────────────────────────────────────────────────────────────────────

def is_unprecedented(analogs: Sequence[Dict],
                     threshold: float = DEFAULT_UNPRECEDENTED_THRESHOLD) -> bool:
    if not analogs:
        return True
    top_sim = max(float(a.get("similarity_score", 0.0)) for a in analogs)
    return bool(top_sim < threshold)


# ─────────────────────────────────────────────────────────────────────────────
# 8. Recommendation
# ─────────────────────────────────────────────────────────────────────────────

def recommend(current_state: Dict, scenarios: Dict[str, float],
              confidence: float, unprecedented: bool) -> str:
    if unprecedented:
        return "AVOID"

    bull = float(scenarios.get("bull_probability", 0))
    bear = float(scenarios.get("bear_probability", 0))

    high_conf = confidence >= 0.6

    if bull >= 60 and high_conf:
        return "FAVORABLE_LONG"
    if bear >= 60 and high_conf:
        return "FAVORABLE_SHORT"

    # MIXED com inclinacao se diferenca razoavel
    diff = bull - bear
    if diff >=  15: return "MIXED_LEAN_BULL"
    if diff <= -15: return "MIXED_LEAN_BEAR"
    if confidence < 0.4:
        return "AVOID"
    return "MIXED"


# ─────────────────────────────────────────────────────────────────────────────
# 9. analyze_current -- pipeline completo
# ─────────────────────────────────────────────────────────────────────────────

def _operational_advice(rec: str, state: Dict, scenarios: Dict[str, float]) -> Dict:
    long_ok  = rec in ("FAVORABLE_LONG", "MIXED_LEAN_BULL")
    short_ok = rec in ("FAVORABLE_SHORT", "MIXED_LEAN_BEAR")
    wait_for: List[str] = []
    if not long_ok:
        wait_for.append("BTC > SMA200 confirmation")
    if state.get("nupl_proxy", 0.5) < 0.35:
        wait_for.append("NUPL recovery")
    if scenarios.get("bear_probability", 0) >= 40:
        wait_for.append("bear scenario invalidation")
    if not wait_for:
        wait_for.append("manter posicoes existentes; aguardar nova confluencia")
    return {
        "should_operate_long":  bool(long_ok),
        "should_operate_short": ("transition_up_only" if rec == "MIXED_LEAN_BEAR" else bool(short_ok)),
        "wait_for":             wait_for,
    }


def analyze_current(current_state: Dict, history: Sequence[Dict],
                    top_n: int = 5) -> Dict:
    analogs   = find_similar_periods(current_state, history, top_n=top_n)
    scenarios = compute_scenarios(analogs, horizon="60d")
    conf      = compute_confidence(analogs, horizon="60d")
    unprec    = is_unprecedented(analogs)
    rec       = recommend(current_state, scenarios, conf, unprec)
    outcomes  = compute_outcomes(analogs, horizons=("30d", "60d", "90d"))

    # Remove future_returns interno antes de serializar (mantem JSON enxuto)
    public_analogs = []
    for a in analogs:
        a_pub = {k: v for k, v in a.items() if k != "future_returns"}
        public_analogs.append(a_pub)

    return {
        "timestamp":           datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "current_state":       current_state,
        "historical_analogs":  public_analogs,
        "outcomes":            outcomes,
        "scenarios_60d":       scenarios,
        "confidence":          conf,
        "unprecedented":       unprec,
        "recommendation":      rec,
        "operational_advice":  _operational_advice(rec, current_state, scenarios),
    }


# ─────────────────────────────────────────────────────────────────────────────
# CLI: estado atual hardcoded como default + historico sintetico de fallback
# ─────────────────────────────────────────────────────────────────────────────

_CURRENT_STATE_DEFAULT = {
    "btc_price":            79000,
    "regime":               "TRANSITION_DOWN",
    "pi_cycle":             "BEFORE",
    "ath_dd_pct":           -27.0,
    "nupl_proxy":           0.42,
    "wma_200_distance_pct":  35.0,
    "macro_bias":           "NEUTRAL",
}


def _synthetic_history(n: int = 250, seed: int = 7) -> List[Dict]:
    rng     = np.random.default_rng(seed)
    regimes = ["BULL", "BEAR", "SIDEWAYS", "TRANSITION_DOWN", "TRANSITION_UP"]
    pis     = ["NEUTRAL", "BEFORE", "TRIGGERED", "POST_PEAK"]
    macros  = ["BULLISH", "NEUTRAL", "BEARISH"]
    from datetime import date, timedelta
    start = date(2014, 1, 1)
    out: List[Dict] = []
    for i in range(n):
        d = start + timedelta(days=i * 20)
        regime = regimes[int(rng.integers(0, len(regimes)))]
        if   regime == "BULL":            r60 = float(rng.normal( 18, 10))
        elif regime == "BEAR":            r60 = float(rng.normal(-22, 10))
        elif regime == "SIDEWAYS":        r60 = float(rng.normal(  0,  5))
        elif regime == "TRANSITION_DOWN": r60 = float(rng.normal(-14, 12))
        else:                              r60 = float(rng.normal( 10, 10))
        out.append({
            "date": d.isoformat(),
            "state": {
                "regime":               regime,
                "pi_cycle":             pis[int(rng.integers(0, len(pis)))],
                "ath_dd_pct":           float(rng.uniform(-80, -3)),
                "nupl_proxy":           float(rng.uniform(0.1, 0.95)),
                "wma_200_distance_pct": float(rng.uniform(-45, 80)),
                "macro_bias":           macros[int(rng.integers(0, len(macros)))],
            },
            "future_returns": {"30d": r60 / 2, "60d": r60, "90d": r60 * 1.4},
        })
    return out


def _load_history(path: Optional[str]) -> List[Dict]:
    if path and os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return list(json.load(f).get("history", []))
    sys.stderr.write("[CurrentCycle] Historico real ausente -- usando sintetico 14y (~250 pontos).\n")
    return _synthetic_history()


def _load_current_state(path: Optional[str]) -> Dict:
    if path and os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    return dict(_CURRENT_STATE_DEFAULT)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Now-cast de ciclo via analogos historicos")
    parser.add_argument("--top-n",   type=int, default=5)
    parser.add_argument("--current", default=None, help="JSON com estado atual (opcional)")
    parser.add_argument("--history", default=None, help="JSON com {history:[...]} (opcional)")
    parser.add_argument("--output",  default=os.path.join("journal", "task3_current_cycle_analysis.json"))
    args = parser.parse_args(argv)

    state   = _load_current_state(args.current)
    history = _load_history(args.history)
    result  = analyze_current(state, history, top_n=args.top_n)

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, default=str)

    sys.stdout.write(
        f"[CurrentCycle] rec={result['recommendation']} conf={result['confidence']} "
        f"unprec={result['unprecedented']} "
        f"bull/side/bear={result['scenarios_60d']['bull_probability']}/"
        f"{result['scenarios_60d']['sideways_probability']}/"
        f"{result['scenarios_60d']['bear_probability']}. -> {args.output}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
