"""
mce_filter.py -- Python mirror de lib_market_context_engine.ps1.

Para uso retroativo em backtests: aplica context filter em trades historicos
e compara Sharpe/DSR antes vs depois.

Referencia canonica: knowledge/MARKET_TIMING_BRT.md
"""
from __future__ import annotations

from datetime import datetime, timedelta

HALVING_2024 = datetime(2024, 4, 19)

FOMC_2026 = [
    datetime(2026, 1, 28), datetime(2026, 3, 18), datetime(2026, 4, 29),
    datetime(2026, 6, 17), datetime(2026, 7, 29), datetime(2026, 9, 16),
    datetime(2026, 10, 28), datetime(2026, 12, 9),
]

# Historical FOMC dates 2013-2025 (approximate, for retroactive backtests)
FOMC_HISTORICAL = [
    # 2013-2024 average 8 FOMC/year. Hardcode key dates around year boundaries.
    # Per ano: jan/mar/abr-mai/jun/jul-ago/set/out-nov/dez
    # Simplificado: bloco mar/jun/set/dez como aproximacao (datas exatas variam)
]
# Helper: aproximacao FOMC = todo 3o mes (Mar/Jun/Sep/Dec), 3a quarta-feira
def _is_fomc_approx(date_obj):
    """Aproximacao FOMC: 3a quarta-feira de Mar/Jun/Sep/Dec ou Jan/Apr/Jul/Nov."""
    fomc_months = {1, 3, 4, 6, 7, 9, 10, 12}
    if date_obj.month not in fomc_months:
        return False
    # 3a quarta-feira
    # day 15-21 + DayOfWeek=Wednesday (2 in datetime weekday)
    return (15 <= date_obj.day <= 21) and date_obj.weekday() == 2


DOW_FACTOR = {
    0: 1.2,  # Monday
    1: 1.0,  # Tuesday
    2: 0.9,  # Wednesday
    3: 0.4,  # Thursday
    4: 1.0,  # Friday
    5: 0.7,  # Saturday
    6: 0.8,  # Sunday
}

SEASON_FACTOR = {
    1: 1.2, 2: 1.3, 3: 1.1, 4: 1.4,
    5: 0.5, 6: 0.6, 7: 1.1, 8: 0.7,
    9: 0.4, 10: 1.3, 11: 1.5, 12: 1.0,
}


def dow_factor(date_obj):
    return DOW_FACTOR.get(date_obj.weekday(), 1.0)


def season_factor(date_obj):
    return SEASON_FACTOR.get(date_obj.month, 1.0)


def halving_factor(date_obj):
    """Para datas pre-2024 halving: usa halving anterior 2020-05-11."""
    if date_obj >= HALVING_2024:
        delta = (date_obj - HALVING_2024).days / 30.44
    elif date_obj >= datetime(2020, 5, 11):
        delta = (date_obj - datetime(2020, 5, 11)).days / 30.44
    elif date_obj >= datetime(2016, 7, 9):
        delta = (date_obj - datetime(2016, 7, 9)).days / 30.44
    elif date_obj >= datetime(2012, 11, 28):
        delta = (date_obj - datetime(2012, 11, 28)).days / 30.44
    else:
        return 0.5
    months = int(delta)
    if months < 0:    return 0.5
    if months <= 6:   return 0.8
    if months <= 12:  return 1.3
    if months <= 18:  return 1.5
    if months <= 24:  return 0.7
    if months <= 36:  return 0.3
    return 0.5


def session_factor(date_obj):
    """For daily candles entries, default to 1.0 (assume entry happens golden hours)."""
    h = date_obj.hour
    if 9 <= h < 13:  return 1.0
    if 13 <= h < 16: return 0.9
    if 16 <= h < 19: return 0.7
    if 19 <= h < 22: return 0.5
    if h >= 22 or h < 2: return 0.6
    if 2 <= h < 4:   return 0.4
    return 0.8


def macro_event_factor(date_obj):
    # FOMC 2026
    for fomc in FOMC_2026:
        if abs((date_obj.date() - fomc.date()).days) <= 1:
            return 0.0
    # FOMC historico aproximado
    if _is_fomc_approx(date_obj):
        return 0.0
    # CPI window
    if 10 <= date_obj.day <= 15:
        return 0.7
    # NFP (1a sexta do mes)
    if date_obj.weekday() == 4 and date_obj.day <= 7:
        return 0.7
    return 1.0


REGIME_FACTOR = {
    "BULL_STRONG": 1.5, "BULL_WEAK": 1.0, "TRANSITION_UP": 1.2,
    "SIDEWAYS": 0.5, "TRANSITION_DOWN": 0.3,
    "BEAR_WEAK": 0.2, "BEAR_STRONG": 0.0, "CAPITULATION": 0.0,
}


def regime_factor(regime):
    if not regime: return 0.5
    return REGIME_FACTOR.get(regime, 0.5)


def context_score(date_obj, regime="BULL_WEAK"):
    """Computa score de contexto pra uma data + regime."""
    f = {
        "dow": dow_factor(date_obj),
        "season": season_factor(date_obj),
        "halving": halving_factor(date_obj),
        "session": session_factor(date_obj),
        "macro": macro_event_factor(date_obj),
        "regime": regime_factor(regime),
    }
    score = 1.0
    for v in f.values(): score *= v
    return {"score": round(score, 4), "factors": f}


def context_action(score):
    if score < 0.20: return "BLOCK"
    if score < 0.50: return "PAPER_ONLY"
    if score < 1.00: return "LIVE_REDUCED"
    return "LIVE_FULL"


def apply_context_filter(trades, threshold=0.50, regime_default="BULL_WEAK"):
    """
    Filtra trades historicos por context score.

    trades: lista de dicts com chaves entry_ts (ISO), result_r, etc.
    threshold: score minimo para keep (>= threshold mantem).
    regime_default: usado se trade nao tem regime explicito.

    Returns: (kept, filtered_out, stats)
    """
    kept = []
    filtered = []
    for t in trades:
        ts = t.get("entry_ts")
        if isinstance(ts, str):
            try:
                date_obj = datetime.fromisoformat(ts.replace("Z","+00:00")).replace(tzinfo=None)
            except: continue
        elif isinstance(ts, datetime):
            date_obj = ts
        else: continue
        regime = t.get("regime", regime_default)
        ctx = context_score(date_obj, regime)
        t_with_ctx = dict(t)
        t_with_ctx["context_score"] = ctx["score"]
        t_with_ctx["context_action"] = context_action(ctx["score"])
        if ctx["score"] >= threshold:
            kept.append(t_with_ctx)
        else:
            filtered.append(t_with_ctx)
    return kept, filtered


def compare_metrics(trades_before, trades_after):
    """Compara stats antes vs depois do context filter."""
    def stats(trades):
        if not trades: return {"n": 0, "mean_r": 0, "win_pct": 0, "total_r": 0}
        n = len(trades)
        rs = [float(t.get("result_r", 0)) for t in trades]
        wins = sum(1 for r in rs if r > 0)
        mean_r = sum(rs) / n
        return {
            "n": n,
            "mean_r": round(mean_r, 4),
            "win_pct": round(wins / n * 100, 2),
            "total_r": round(sum(rs), 2),
            "sharpe_proxy": round(mean_r / (sum((r-mean_r)**2 for r in rs)/max(1,n-1))**0.5 * (252**0.5), 2) if n>1 else 0,
        }
    return {
        "before": stats(trades_before),
        "after": stats(trades_after),
    }
