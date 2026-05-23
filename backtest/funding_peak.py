"""funding_peak.py — Detector de overheating de funding rate.

Tese: funding rate > 0.08%/8h por 5+ dias = longs sobrecarregados pagando 9% ao mes.
Sinal de short = QUEDA do pico (longs comecando a fechar), nao o pico em si.

API:
  rolling_mean_daily(series, days)   -> media diaria do funding
  is_overheated(rolling_5d, ...)     -> bool, funding aquecido
  detect_peak(series, lookback)      -> peak_value / peak_date
  detect_drop(series, peak, ...)     -> bool, queda confirmada
  scan_signals(series, ...)          -> List[trigger dicts]
"""
from typing import Dict, List, Optional


DEFAULT_HOT_THRESHOLD = 0.05   # %/8h ~ 5.5% ao mes
DEFAULT_EXTREME_THRESHOLD = 0.08
DEFAULT_DROP_PCT = 0.30
DEFAULT_LOOKBACK_DAYS = 14
DEFAULT_PEAK_MIN_DAYS = 5


def rolling_mean(series_by_date: Dict[str, float], target_date: str,
                 days: int) -> Optional[float]:
    """Media dos ultimos N dias inclusivos de target_date."""
    from datetime import datetime, timedelta
    if target_date not in series_by_date:
        return None
    target_dt = datetime.fromisoformat(target_date).date()
    vals = []
    for d in range(days):
        date = (target_dt - timedelta(days=d)).isoformat()
        if date in series_by_date:
            vals.append(series_by_date[date])
    if len(vals) < max(2, days // 3):
        return None
    return sum(vals) / len(vals)


def is_overheated(rolling_value: Optional[float],
                  threshold: float = DEFAULT_HOT_THRESHOLD) -> bool:
    if rolling_value is None:
        return False
    return rolling_value >= threshold


def detect_peak(series_by_date: Dict[str, float], target_date: str,
                lookback_days: int = DEFAULT_LOOKBACK_DAYS,
                hot_threshold: float = DEFAULT_HOT_THRESHOLD) -> Optional[Dict]:
    """Em [target_date - lookback, target_date], encontra o max do rolling_5d.

    Retorna {peak_value, peak_date} se o pico cruzou hot_threshold, senao None.
    """
    from datetime import datetime, timedelta
    if target_date not in series_by_date:
        return None
    target_dt = datetime.fromisoformat(target_date).date()
    candidates: List[Dict] = []
    for d in range(lookback_days + 1):
        date = (target_dt - timedelta(days=d)).isoformat()
        rm = rolling_mean(series_by_date, date, days=5)
        if rm is not None:
            candidates.append({"date": date, "value": rm})
    if not candidates:
        return None
    peak = max(candidates, key=lambda c: c["value"])
    if peak["value"] < hot_threshold:
        return None
    return peak


def detect_drop(series_by_date: Dict[str, float], target_date: str,
                peak_value: float, drop_pct: float = DEFAULT_DROP_PCT,
                confirmation_days: int = 2) -> bool:
    """Confirma queda do pico em target_date.

    Trigger: rolling_5d(target_date) <= peak_value * (1 - drop_pct)
             E media dos ultimos confirmation_days dias <= mesmo threshold (nao fake).
    """
    threshold = peak_value * (1 - drop_pct)
    current = rolling_mean(series_by_date, target_date, days=5)
    if current is None or current > threshold:
        return False
    # confirmation: rolling de N dias tambem abaixo
    from datetime import datetime, timedelta
    target_dt = datetime.fromisoformat(target_date).date()
    confirmations = 0
    for d in range(confirmation_days):
        date = (target_dt - timedelta(days=d)).isoformat()
        rm = rolling_mean(series_by_date, date, days=3)
        if rm is not None and rm <= threshold:
            confirmations += 1
    return confirmations >= confirmation_days


def scan_signals(series_by_date: Dict[str, float],
                 hot_threshold: float = DEFAULT_HOT_THRESHOLD,
                 drop_pct: float = DEFAULT_DROP_PCT,
                 lookback_days: int = DEFAULT_LOOKBACK_DAYS,
                 min_gap_days: int = 14) -> List[Dict]:
    """Varre toda a serie e retorna lista de triggers de short.

    Cada trigger: {date, peak_value, peak_date, current_value, drop_pct_actual}.
    Min_gap_days evita triggers consecutivos do mesmo overheating.
    """
    from datetime import datetime, timedelta
    sorted_dates = sorted(series_by_date.keys())
    triggers: List[Dict] = []
    last_trigger_date: Optional[str] = None

    for date in sorted_dates:
        if last_trigger_date is not None:
            d1 = datetime.fromisoformat(date).date()
            d0 = datetime.fromisoformat(last_trigger_date).date()
            if (d1 - d0).days < min_gap_days:
                continue
        peak = detect_peak(series_by_date, date, lookback_days, hot_threshold)
        if peak is None:
            continue
        if not detect_drop(series_by_date, date, peak["value"], drop_pct):
            continue
        current = rolling_mean(series_by_date, date, days=5)
        actual_drop = (peak["value"] - current) / peak["value"] if peak["value"] else 0
        triggers.append({
            "date":            date,
            "peak_value":      round(peak["value"], 6),
            "peak_date":       peak["date"],
            "current_value":   round(current, 6) if current else None,
            "drop_pct_actual": round(actual_drop, 4),
        })
        last_trigger_date = date

    return triggers
