"""
signal_generator_v2.py — Score refinado com pesos baseados no knowledge base.

Mudanças vs v1 (knowledge base: MENTOR.md, WYCKOFF_SMC.md, TORI_TRADES.md):
  - MTF alignment (4h trend): +25pts (Tudor: nunca contra HTF)
  - ADX strength: ±15 → ±20 (INDICATORS_REFERENCE)
  - Volume confirmation: +10 → +20 (Wyckoff: volume = verdade)
  - BB extremes: ±15 (manter)
  - EMA cross: ±15 → ±10 (lagging)
  - RSI: ±20 → ±10 (lagging)
  - MACD: ±15 → ±10 (lagging)

ADX < 25 segue como hard filter (bloqueia sinal).
"""
from typing import Dict, List, Optional

from indicators import ema, rsi, atr, macd, bollinger, adx
from signal_generator import (
    SignalResult, calc_stop_atr, calc_target,
    MIN_CANDLES, ATR_STOP_MULT, RR_DEFAULT,
)

SCORE_THRESHOLD_V2 = 65.0
HTF_EMA_PERIOD = 50  # EMA do HTF para definir direção macro


def _htf_direction(candles_htf: Optional[List[Dict]]) -> Optional[str]:
    """
    Retorna 'bull' se HTF está em uptrend (preço > EMA50),
            'bear' se downtrend,
            None se sem dado suficiente.
    """
    if not candles_htf or len(candles_htf) < HTF_EMA_PERIOD:
        return None
    closes = [c["close"] for c in candles_htf]
    ema50_htf = ema(closes, HTF_EMA_PERIOD)
    last = closes[-1]
    return "bull" if last > ema50_htf else "bear"


def generate_signal_v2(
    candles: List[Dict],
    candles_htf: Optional[List[Dict]] = None,
) -> SignalResult:
    """
    v2: pesos refinados + MTF alignment opcional via candles_htf (4h).
    Zero lookahead: usa apenas candles fornecidos.
    """
    entry = candles[-1]["close"] if candles else 0.0
    neutral = SignalResult(
        signal="NEUTRO", score=50.0,
        entry_price=entry,
        stop_loss=entry * 0.98,
        take_profit=entry * 1.06,
        atr=0.0, indicators={},
    )

    if len(candles) < MIN_CANDLES:
        return neutral

    closes = [c["close"] for c in candles]
    score_bullish = 0
    score_bearish = 0
    indicators: Dict = {}
    max_points = 0

    # ── MTF alignment (HTF trend filter) — peso 25 ─────────────────────────
    htf_dir = _htf_direction(candles_htf)
    if htf_dir == "bull":
        score_bullish += 25
        indicators["mtf"] = "bull"
        max_points += 25
    elif htf_dir == "bear":
        score_bearish += 25
        indicators["mtf"] = "bear"
        max_points += 25
    else:
        indicators["mtf"] = "n/a"

    # ── ADX — hard filter + peso 20 ────────────────────────────────────────
    try:
        adx_res = adx(candles, period=14)
        indicators["adx"] = round(adx_res["adx"], 1)
        if adx_res["adx"] < 25:
            indicators["adx_blocked"] = True
            neutral.indicators = indicators
            return neutral
        if adx_res["pdi"] > adx_res["ndi"]:
            score_bullish += 20
            indicators["adx_trend"] = "strong_up"
        else:
            score_bearish += 20
            indicators["adx_trend"] = "strong_down"
        max_points += 20
    except Exception:
        pass

    # ── Volume confirmation — peso 20 ──────────────────────────────────────
    vol_confirm = False
    try:
        vols = [c["volume"] for c in candles[-20:]]
        avg_vol = sum(vols[:-1]) / max(len(vols) - 1, 1)
        cur_vol = vols[-1]
        indicators["vol_ratio"] = round(cur_vol / avg_vol, 2) if avg_vol > 0 else 1.0
        if cur_vol > avg_vol * 1.3:
            vol_confirm = True
            indicators["vol_confirm"] = True
            if score_bullish > score_bearish:
                score_bullish += 20
            else:
                score_bearish += 20
        max_points += 20
    except Exception:
        pass

    # ── Bollinger Bands extremes — peso 15 ─────────────────────────────────
    try:
        bb = bollinger(closes[-20:] if len(closes) >= 20 else closes, period=min(20, len(closes)))
        indicators["bb_upper"] = round(bb["upper"], 4)
        indicators["bb_lower"] = round(bb["lower"], 4)
        if entry <= bb["lower"]:
            score_bullish += 15
            indicators["bb_position"] = "below_lower"
        elif entry >= bb["upper"]:
            score_bearish += 15
            indicators["bb_position"] = "above_upper"
        else:
            mid = bb["middle"]
            if entry > mid:
                score_bullish += 5
            else:
                score_bearish += 5
            indicators["bb_position"] = "inside"
        max_points += 15
    except Exception:
        pass

    # ── EMA cross — peso reduzido 10 ───────────────────────────────────────
    try:
        ema9 = ema(closes, 9)
        ema21 = ema(closes, 21)
        indicators["ema9"] = round(ema9, 4)
        indicators["ema21"] = round(ema21, 4)
        if ema9 > ema21:
            score_bullish += 10
            indicators["ema_cross"] = "bullish"
        elif ema9 < ema21:
            score_bearish += 10
            indicators["ema_cross"] = "bearish"
        max_points += 10
    except Exception:
        pass

    # ── RSI — peso reduzido 10 ─────────────────────────────────────────────
    try:
        rsi_val = rsi(closes, 14)
        indicators["rsi"] = round(rsi_val, 1)
        if rsi_val < 35:
            score_bullish += 10
            indicators["rsi_zone"] = "oversold"
        elif rsi_val > 65:
            score_bearish += 10
            indicators["rsi_zone"] = "overbought"
        else:
            if rsi_val > 50:
                score_bullish += 4
            else:
                score_bearish += 4
            indicators["rsi_zone"] = "neutral"
        max_points += 10
    except Exception:
        pass

    # ── MACD — peso reduzido 10 ────────────────────────────────────────────
    try:
        m = macd(closes)
        indicators["macd_hist"] = round(m["histogram"], 4)
        if m["histogram"] > 0:
            score_bullish += 10
            indicators["macd_signal"] = "bullish"
        else:
            score_bearish += 10
            indicators["macd_signal"] = "bearish"
        max_points += 10
    except Exception:
        pass

    # ── Score normalizado 0-100 ────────────────────────────────────────────
    if max_points == 0:
        return neutral

    bull_score = (score_bullish / max_points) * 100
    bear_score = (score_bearish / max_points) * 100

    if bull_score >= SCORE_THRESHOLD_V2 and bull_score > bear_score:
        direction = "LONG"
        signal = "COMPRA"
        score = bull_score
    elif bear_score >= SCORE_THRESHOLD_V2 and bear_score > bull_score:
        direction = "SHORT"
        signal = "VENDA"
        score = bear_score
    else:
        direction = "LONG" if bull_score >= bear_score else "SHORT"
        signal = "NEUTRO"
        score = max(bull_score, bear_score)

    try:
        atr_val = atr(candles, period=14)
    except Exception:
        atr_val = entry * 0.01

    stop = calc_stop_atr(candles, direction, ATR_STOP_MULT)
    take_profit = calc_target(entry, stop, direction, RR_DEFAULT)

    return SignalResult(
        signal=signal,
        score=round(score, 1),
        entry_price=entry,
        stop_loss=round(stop, 6),
        take_profit=round(take_profit, 6),
        atr=round(atr_val, 6),
        indicators=indicators,
    )
