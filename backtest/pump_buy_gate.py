"""
pump_buy_gate.py -- Python mirror de agents/lib_pump_buy_gate.ps1.

Anti-pump-buy gate: bloqueia promocao Tier A se preco muito perto do peak 7d.
Mantem paridade exata com PS lib.
"""
from __future__ import annotations

from typing import Dict, List, Optional

DEFAULT_MAX_DIST_FROM_PEAK_PCT = -5.0


def check_pump_buy_gate(current_price: float, peak_7d: float,
                        max_dist_from_peak_pct: float = DEFAULT_MAX_DIST_FROM_PEAK_PCT) -> Dict:
    """
    Gate anti-pump-buy.

    Retorna dict com:
        passes: bool — True se preco esta a >= |max_dist|% abaixo do peak
        dist_pct: float — distancia atual em %
        current_price, peak_7d, threshold, reason
    """
    if peak_7d <= 0 or current_price <= 0:
        return {
            "passes": False,
            "dist_pct": 0,
            "current_price": current_price,
            "peak_7d": peak_7d,
            "reason": "invalid_input",
            "threshold": max_dist_from_peak_pct,
        }

    dist_pct = ((current_price - peak_7d) / peak_7d) * 100
    passes = dist_pct <= max_dist_from_peak_pct

    if passes:
        reason = "ok_pullback"
    elif dist_pct >= 0:
        reason = "at_or_above_peak"
    else:
        reason = "no_pullback"

    return {
        "passes": passes,
        "dist_pct": round(dist_pct, 2),
        "current_price": current_price,
        "peak_7d": peak_7d,
        "reason": reason,
        "threshold": max_dist_from_peak_pct,
    }


def peak_7d_from_candles(candles: List[Dict]) -> float:
    """Helper: extrai max(high) de array de candles."""
    if not candles:
        return 0
    return max(float(c.get("high", 0)) for c in candles)


def format_telegram_report(market: str, gate_result: Dict) -> str:
    """Formata mensagem Telegram quando gate bloqueia."""
    if gate_result["passes"]:
        return f"✅ {market}: anti-pump-buy OK (dist {gate_result['dist_pct']}% do peak)"
    return (
        f"🚫 <b>{market}</b> bloqueado pelo anti-pump-buy gate\n"
        f"Atual: ${gate_result['current_price']}\n"
        f"Peak 7d: ${gate_result['peak_7d']}\n"
        f"Distancia: {gate_result['dist_pct']}% (threshold: {gate_result['threshold']}%)\n"
        f"Razao: {gate_result['reason']}\n"
        f"Aguardar pullback antes de promover."
    )
