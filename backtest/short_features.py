"""
short_features.py — Feature engineering específico SHORT em BTC daily.

Cada feature é input pra rule_a/b/c/d em short_rules.py. Computado por candle index.

Reusa stack existente:
  - ATR, SMA via cálculo numpy puro (sem dep extra)
  - Halving date BTC: 2024-04-19
  - Mining cost estimate: $55k (consensus pós-halving 2024)
"""
from __future__ import annotations

from datetime import datetime
from typing import Dict, List, Optional


HALVING_2024 = datetime(2024, 4, 19)
MINING_COST_ESTIMATE = 55000.0


def _parse_ts(ts_str: str) -> datetime:
    return datetime.fromisoformat(str(ts_str).replace("Z", "+00:00")).replace(tzinfo=None)


def _sma(values: List[float], window: int) -> Optional[float]:
    if len(values) < window:
        return None
    return sum(values[-window:]) / window


def _tr(c_high: float, c_low: float, prev_close: float) -> float:
    return max(c_high - c_low, abs(c_high - prev_close), abs(c_low - prev_close))


def _atr(candles: List[Dict], period: int = 14) -> Optional[float]:
    if len(candles) < period + 1:
        return None
    trs = []
    for i in range(1, len(candles)):
        trs.append(_tr(candles[i]["high"], candles[i]["low"], candles[i - 1]["close"]))
    return sum(trs[-period:]) / period


def _adx(candles: List[Dict], period: int = 14) -> Dict:
    """Retorna {adx, plus_di, minus_di} ou None se sample insuficiente."""
    if len(candles) < period * 2 + 1:
        return {"adx": None, "plus_di": None, "minus_di": None}
    plus_dms, minus_dms, trs = [], [], []
    for i in range(1, len(candles)):
        up_move = candles[i]["high"] - candles[i - 1]["high"]
        down_move = candles[i - 1]["low"] - candles[i]["low"]
        plus_dm = up_move if (up_move > down_move and up_move > 0) else 0
        minus_dm = down_move if (down_move > up_move and down_move > 0) else 0
        plus_dms.append(plus_dm)
        minus_dms.append(minus_dm)
        trs.append(_tr(candles[i]["high"], candles[i]["low"], candles[i - 1]["close"]))

    atr_w = sum(trs[-period:]) / period if len(trs) >= period else 0
    if atr_w == 0:
        return {"adx": 0, "plus_di": 0, "minus_di": 0}
    plus_di = 100 * (sum(plus_dms[-period:]) / period) / atr_w
    minus_di = 100 * (sum(minus_dms[-period:]) / period) / atr_w
    dx = 100 * abs(plus_di - minus_di) / (plus_di + minus_di + 1e-9)
    return {"adx": round(dx, 2), "plus_di": round(plus_di, 2), "minus_di": round(minus_di, 2)}


def compute_features(candles: List[Dict], idx: int) -> Optional[Dict]:
    """
    Retorna dict com features no índice idx. None se candles insuficientes.
    candles ordenados ASC por tempo.
    """
    if idx < 50 or idx >= len(candles):
        return None
    window = candles[max(0, idx - 250):idx + 1]
    if len(window) < 50:
        return None

    closes = [c["close"] for c in window]
    cur_close = closes[-1]
    sma50 = _sma(closes, 50)
    sma200 = _sma(closes, 200) if len(closes) >= 200 else None
    sma20_vol = _sma([c["volume"] for c in window], 20)
    cur_vol = window[-1]["volume"]

    dist_sma200 = None
    if sma200 and sma200 > 0:
        dist_sma200 = (cur_close - sma200) / sma200

    adx_data = _adx(window, period=14)
    atr_val = _atr(window, period=14)

    # Volume ratio vs SMA20
    vol_ratio = (cur_vol / sma20_vol) if (sma20_vol and sma20_vol > 0) else 1.0

    # Months pós-halving 2024
    try:
        cur_dt = _parse_ts(candles[idx]["ts"])
        months_post = (cur_dt - HALVING_2024).days / 30.44
    except Exception:
        months_post = 0.0

    # Mining ratio estimate (preço/cost)
    mining_ratio = cur_close / MINING_COST_ESTIMATE if MINING_COST_ESTIMATE > 0 else 1.0

    # Consecutive red days (close < open) últimos 7
    consec_red = 0
    for i in range(idx, max(0, idx - 7), -1):
        if candles[i]["close"] < candles[i]["open"]:
            consec_red += 1
        else:
            break

    # Rally strength últimos 3 dias (% maior gain)
    rally_3d = 0.0
    if idx >= 3:
        for i in range(idx - 2, idx + 1):
            c_open = candles[i]["open"]
            c_high = candles[i]["high"]
            if c_open > 0:
                pct = (c_high - c_open) / c_open
                if pct > rally_3d:
                    rally_3d = pct

    return {
        "close": cur_close,
        "sma50": sma50,
        "sma200": sma200,
        "dist_sma200": dist_sma200,
        "adx": adx_data["adx"],
        "plus_di": adx_data["plus_di"],
        "minus_di": adx_data["minus_di"],
        "di_diff": (adx_data["minus_di"] - adx_data["plus_di"]) if (adx_data["minus_di"] is not None and adx_data["plus_di"] is not None) else None,
        "atr": atr_val,
        "vol_ratio_20d": vol_ratio,
        "months_post_halving": round(months_post, 1),
        "mining_ratio": round(mining_ratio, 3),
        "consecutive_red_days": consec_red,
        "rally_strength_3d": round(rally_3d, 4),
    }
