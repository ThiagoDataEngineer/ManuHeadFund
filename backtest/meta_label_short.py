"""
meta_label_short.py -- Meta-labeling 2 etapas para SHORT em BEAR_STRONG.

Filosofia (Lopez de Prado AFML cap 3):
    PRIMARY classifier  = direcao (regime_filter ja existente)
    SECONDARY classifier = P(win | features) -> filtra trades ruins

Aplicacao: resgata SHORT BTC que falhou 0/4 no refino 2026-05-18.
Hipotese: SHORT plain em BEAR_STRONG nao tem edge; SHORT + confluence
          (funding extreme + OI capitulation + DoW favoravel) tem.

Modelo: weighted ensemble heuristico (interpretavel).
Em producao, substituir por classifier treinado (RandomForest/Gradient).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Any


DOW_SHORT_BIAS = {
    # Calibrado pra SHORT: dias historicamente fracos pra BTC
    "Monday": -0.05,
    "Tuesday": 0.0,
    "Wednesday": 0.0,
    "Thursday": 0.15,  # Thu historico negativo (-0.16% baseline 14y)
    "Friday": 0.05,
    "Saturday": 0.0,
    "Sunday": -0.05,
}


REGIME_SHORT_BIAS = {
    "BEAR_STRONG": 0.30,
    "BEAR_WEAK": 0.10,
    "TRANSITION_DOWN": 0.20,
    "CAPITULATION": 0.25,
    "SIDEWAYS": 0.0,
    "BULL_WEAK": -0.15,
    "BULL_STRONG": -0.30,
    "TRANSITION_UP": -0.20,
}


@dataclass
class MetaLabelConfig:
    p_win_threshold: float = 0.55


def compute_meta_features(signal: Dict[str, Any]) -> Dict[str, float]:
    """Extrai features pro secondary classifier."""
    regime = signal.get("regime", "SIDEWAYS")
    funding_z = float(signal.get("funding_z", 0.0))
    oi_delta_pct = float(signal.get("oi_delta_pct", 0.0))
    dow = signal.get("dow", "Wednesday")
    atr_pct = float(signal.get("atr_pct", 0.02))

    return {
        "regime_score": REGIME_SHORT_BIAS.get(regime, 0.0),
        "funding_extreme": 1.0 if abs(funding_z) >= 2.0 else 0.0,
        "funding_z_abs": min(abs(funding_z), 5.0),
        "oi_capitulation": 1.0 if oi_delta_pct <= -0.03 else 0.0,
        "dow_score": DOW_SHORT_BIAS.get(dow, 0.0),
        "atr_pct": atr_pct,
    }


def meta_label_predict(features: Dict[str, float]) -> float:
    """
    Retorna P(win) em [0, 1].

    Heuristica weighted (substituir por classifier treinado em producao).
    """
    score = 0.5  # baseline neutro
    score += features["regime_score"]                          # -0.30..+0.30
    score += features["funding_extreme"] * 0.10               # 0 ou +0.10
    score += features["oi_capitulation"] * 0.10               # 0 ou +0.10
    score += features["dow_score"]                            # -0.05..+0.15
    # Clip em [0, 1]
    return max(0.0, min(1.0, score))


def apply_meta_filter(signal: Dict[str, Any], config: MetaLabelConfig = None) -> Dict[str, Any]:
    """
    Pipeline completo: features -> predict -> filter.

    Retorna dict com:
        - p_win: probabilidade estimada
        - passes: bool se P(win) >= threshold
        - features: dict de features computadas
    """
    if config is None:
        config = MetaLabelConfig()
    feats = compute_meta_features(signal)
    p_win = meta_label_predict(feats)
    return {
        "p_win": round(p_win, 4),
        "passes": p_win >= config.p_win_threshold,
        "features": feats,
    }
