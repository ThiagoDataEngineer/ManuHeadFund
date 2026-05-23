"""
indicators.py — Port dos indicadores do TechAgent (PowerShell → Python)
Referências: Murphy, Elder, Wilder, Bollinger, Appel
"""
import math
from typing import List, Dict


def ema(closes: List[float], period: int) -> float:
    if len(closes) < period:
        raise ValueError(f"EMA requer mínimo {period} candles, recebeu {len(closes)}")
    k = 2.0 / (period + 1)
    value = closes[0]
    for c in closes[1:]:
        value = c * k + value * (1 - k)
    return value


def rsi(closes: List[float], period: int = 14) -> float:
    if len(closes) < period + 1:
        raise ValueError(f"RSI requer mínimo {period + 1} candles, recebeu {len(closes)}")
    gains, losses = 0.0, 0.0
    for i in range(1, period + 1):
        delta = closes[i] - closes[i - 1]
        if delta > 0:
            gains += delta
        else:
            losses += abs(delta)
    avg_gain = gains / period
    avg_loss = losses / period
    for i in range(period + 1, len(closes)):
        delta = closes[i] - closes[i - 1]
        if delta > 0:
            avg_gain = (avg_gain * (period - 1) + delta) / period
            avg_loss = avg_loss * (period - 1) / period
        else:
            avg_gain = avg_gain * (period - 1) / period
            avg_loss = (avg_loss * (period - 1) + abs(delta)) / period
    if avg_loss == 0:
        return 100.0
    rs = avg_gain / avg_loss
    return 100.0 - (100.0 / (1 + rs))


def atr(candles: List[Dict], period: int = 14) -> float:
    if len(candles) < period + 1:
        raise ValueError(f"ATR requer mínimo {period + 1} candles, recebeu {len(candles)}")
    tr_values = []
    for i in range(1, len(candles)):
        c, p = candles[i], candles[i - 1]
        tr = max(
            c["high"] - c["low"],
            abs(c["high"] - p["close"]),
            abs(c["low"] - p["close"])
        )
        tr_values.append(tr)
    return sum(tr_values[-period:]) / period


def macd(closes: List[float], fast: int = 12, slow: int = 26, signal: int = 9) -> Dict:
    if len(closes) < slow + signal:
        raise ValueError(f"MACD requer mínimo {slow + signal} candles, recebeu {len(closes)}")
    macd_values = []
    for i in range(slow - 1, len(closes)):
        fast_ema = ema(closes[max(0, i - fast * 3):i + 1], fast)
        slow_ema = ema(closes[max(0, i - slow * 3):i + 1], slow)
        macd_values.append(fast_ema - slow_ema)
    signal_line = ema(macd_values, signal)
    macd_line = macd_values[-1]
    histogram = macd_line - signal_line
    return {"macd_line": macd_line, "signal_line": signal_line, "histogram": histogram}


def bollinger(closes: List[float], period: int = 20, std_dev: float = 2.0) -> Dict:
    if len(closes) < period:
        raise ValueError(f"Bollinger requer mínimo {period} candles, recebeu {len(closes)}")
    window = closes[-period:]
    middle = sum(window) / period
    variance = sum((x - middle) ** 2 for x in window) / period
    std = math.sqrt(variance)
    return {
        "upper": middle + std_dev * std,
        "middle": middle,
        "lower": middle - std_dev * std,
    }


def adx(candles: List[Dict], period: int = 14) -> Dict:
    if len(candles) < period + 1:
        raise ValueError(f"ADX requer mínimo {period + 1} candles, recebeu {len(candles)}")
    tr_list, pdm_list, ndm_list = [], [], []
    for i in range(1, len(candles)):
        c, p = candles[i], candles[i - 1]
        tr = max(
            c["high"] - c["low"],
            abs(c["high"] - p["close"]),
            abs(c["low"] - p["close"])
        )
        up = c["high"] - p["high"]
        dn = p["low"] - c["low"]
        tr_list.append(tr)
        pdm_list.append(up if up > dn and up > 0 else 0.0)
        ndm_list.append(dn if dn > up and dn > 0 else 0.0)

    def smoothed_sum(values):
        s = sum(values[:period])
        for v in values[period:]:
            s = s - s / period + v
        return s

    atr_s = smoothed_sum(tr_list)
    pdm_s = smoothed_sum(pdm_list)
    ndm_s = smoothed_sum(ndm_list)

    if atr_s == 0:
        return {"adx": 0.0, "pdi": 0.0, "ndi": 0.0}

    pdi = 100.0 * pdm_s / atr_s
    ndi = 100.0 * ndm_s / atr_s
    dx = 100.0 * abs(pdi - ndi) / (pdi + ndi) if (pdi + ndi) > 0 else 0.0

    dx_values = []
    tr_smooth, pdm_smooth, ndm_smooth = sum(tr_list[:period]), sum(pdm_list[:period]), sum(ndm_list[:period])
    for i in range(period, len(tr_list)):
        tr_smooth = tr_smooth - tr_smooth / period + tr_list[i]
        pdm_smooth = pdm_smooth - pdm_smooth / period + pdm_list[i]
        ndm_smooth = ndm_smooth - ndm_smooth / period + ndm_list[i]
        if tr_smooth == 0:
            continue
        _pdi = 100.0 * pdm_smooth / tr_smooth
        _ndi = 100.0 * ndm_smooth / tr_smooth
        _dx = 100.0 * abs(_pdi - _ndi) / (_pdi + _ndi) if (_pdi + _ndi) > 0 else 0.0
        dx_values.append(_dx)

    adx_val = sum(dx_values) / len(dx_values) if dx_values else dx
    return {"adx": adx_val, "pdi": pdi, "ndi": ndi}
