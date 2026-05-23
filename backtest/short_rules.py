"""
short_rules.py — 4 regras candidatas SHORT BTC daily.

Cada regra recebe features computadas por short_features.py e retorna bool.
Filosofia: NÃO inverter LONG. Cada regra captura cenário SHORT diferente.

Regras testadas:
  rule_a: SMA200 break confirmado (estrutural)
  rule_b: Rally failure (rally sem volume = trapped longs)
  rule_c: Late cycle + mining stress (halving phase + mining margin fina)
  rule_d: Consecutive weakness (4+ red days)
"""
from __future__ import annotations
from typing import Dict, Optional


def rule_a_sma200_break(features: Optional[Dict]) -> bool:
    """
    SMA200 break confirmado (estrutural).
    SHORT se: preço cruza SMA200 baixo com ADX>25 e -DI>+DI claro.
    """
    if not features: return False
    dist = features.get("dist_sma200")
    adx = features.get("adx")
    di_diff = features.get("di_diff")
    if dist is None or adx is None or di_diff is None:
        return False
    return (dist < -0.02 and dist > -0.20 and  # quebra recente, não capitulação
            adx > 25 and
            di_diff > 5)  # -DI > +DI por margem clara


def rule_b_rally_failure(features: Optional[Dict]) -> bool:
    """
    Rally failure (trapped longs).
    SHORT se: rally 3d > 5% MAS volume < SMA20 (rally sem força).
    Captura blow-off / bull trap.
    """
    if not features: return False
    rally = features.get("rally_strength_3d")
    vol_ratio = features.get("vol_ratio_20d")
    dist = features.get("dist_sma200")
    if rally is None or vol_ratio is None:
        return False
    # Rally significativo mas com volume morrendo
    return (rally > 0.05 and
            vol_ratio < 0.7 and
            (dist is None or dist < 0.10))   # não em hyper-bull


def rule_c_late_cycle_mining_stress(features: Optional[Dict]) -> bool:
    """
    Late cycle + mining stress (halving phase + mining margin fina).
    SHORT só pós mês 18 halving + mining ratio < 1.3 (margem mineradora estreita).
    """
    if not features: return False
    months = features.get("months_post_halving")
    mining = features.get("mining_ratio")
    dist = features.get("dist_sma200")
    if months is None or mining is None:
        return False
    return (months >= 18 and
            mining < 1.3 and
            (dist is None or dist < 0))  # preço já abaixo SMA200


def rule_d_consecutive_weakness(features: Optional[Dict]) -> bool:
    """
    4+ red days consecutivos (momentum bear consolidado).
    SHORT em continuação. Stop 3×ATR pra absorver bounce.
    """
    if not features: return False
    consec = features.get("consecutive_red_days")
    dist = features.get("dist_sma200")
    if consec is None: return False
    return (consec >= 4 and
            (dist is None or dist < 0))   # preço já fraco vs SMA200


ALL_RULES = {
    "rule_a_sma200_break":         rule_a_sma200_break,
    "rule_b_rally_failure":        rule_b_rally_failure,
    "rule_c_late_cycle_mining":    rule_c_late_cycle_mining_stress,
    "rule_d_consecutive_weakness": rule_d_consecutive_weakness,
}


def evaluate_all_rules(features: Optional[Dict]) -> Dict[str, bool]:
    """Avalia todas regras. Retorna dict {nome_regra: bool}."""
    return {name: fn(features) for name, fn in ALL_RULES.items()}
