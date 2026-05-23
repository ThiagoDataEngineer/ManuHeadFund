"""stablecoin_regime.py — Classifica regime macro de capital crypto via stablecoin supply.

Tese: stablecoin marketcap = funding pool do bull. Contracao = drenagem de capital,
sem buyers marginais. Bulls morrem por falta de combustivel.

Regimes (baseado em 30d change da supply):
  EXPANSION    >= +3%     combustivel abundante (sustenta bull, vetar SHORT)
  NEUTRAL      -0.5% a +3% sem sinal direcional
  WARNING      -2% a -0.5% drenagem lenta (reduzir LONG, habilitar SHORT alt)
  CONTRACTION  -5% a -2%  drenagem real (reduzir LONG, habilitar SHORT BTC)
  CRISIS       <= -5%     pânico (bloquear LONG novo, SHORT com convicção)
"""
from typing import Dict, List, Optional


def classify_regime(supply_change_30d_pct: Optional[float]) -> str:
    """Retorna regime string a partir do % change 30d da supply."""
    if supply_change_30d_pct is None:
        return "UNKNOWN"
    if supply_change_30d_pct >= 3.0:
        return "EXPANSION"
    if supply_change_30d_pct >= -0.5:
        return "NEUTRAL"
    if supply_change_30d_pct >= -2.0:
        return "WARNING"
    if supply_change_30d_pct >= -5.0:
        return "CONTRACTION"
    return "CRISIS"


def compute_supply_change(supply_series: Dict[str, float], target_date: str,
                          days: int = 30) -> Optional[float]:
    """Retorna % change da supply entre target_date e (target_date - days).

    supply_series: dict[date_iso] = float. Toleta date_prev faltando ate +-3d.
    """
    if target_date not in supply_series:
        return None
    from datetime import datetime, timedelta
    target_dt = datetime.fromisoformat(target_date).date()
    target_val = supply_series[target_date]
    if target_val <= 0:
        return None

    for delta in range(days, days + 4):  # tolerancia +-3d
        prev_date = (target_dt - timedelta(days=delta)).isoformat()
        if prev_date in supply_series and supply_series[prev_date] > 0:
            prev_val = supply_series[prev_date]
            return ((target_val - prev_val) / prev_val) * 100

    for delta in range(days - 1, max(days - 4, 0), -1):
        prev_date = (target_dt - timedelta(days=delta)).isoformat()
        if prev_date in supply_series and supply_series[prev_date] > 0:
            prev_val = supply_series[prev_date]
            return ((target_val - prev_val) / prev_val) * 100

    return None


def regime_at(supply_series: Dict[str, float], target_date: str,
              days: int = 30) -> Dict:
    """Helper que retorna dict com regime + metricas no target_date."""
    change = compute_supply_change(supply_series, target_date, days)
    regime = classify_regime(change)
    return {
        "date": target_date,
        "supply_change_30d_pct": change,
        "regime": regime,
    }


def is_short_allowed(regime: str) -> bool:
    """Gate: SHORT BTC so permitido em WARNING+."""
    return regime in {"WARNING", "CONTRACTION", "CRISIS"}


def long_sizing_multiplier(regime: str) -> float:
    """Modulador de sizing para LONG baseado no regime."""
    return {
        "EXPANSION":   1.2,
        "NEUTRAL":     1.0,
        "WARNING":     0.7,
        "CONTRACTION": 0.4,
        "CRISIS":      0.0,
        "UNKNOWN":     1.0,
    }.get(regime, 1.0)
