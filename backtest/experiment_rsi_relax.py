"""
experiment_rsi_relax.py — Testa relaxar penalty de RSI overbought em BULL macro.

Hipotese: em bull forte (SMA50/2w confirma), penalizar RSI > 65 com -20pts
faz o sistema perder os top winners de 2013/2016 (que entraram com RSI 77-92).
Variantes testadas:
  baseline: RSI > 65 = bearish (-20pts)
  v1:       RSI > 65 em bull = neutro (0pts), em outros regimes = bearish
  v2:       RSI > 65 em bull = bullish leve (+8pts), em outros = bearish
"""
import os
from typing import Dict, List

from dotenv import load_dotenv
load_dotenv()

from db import Database
import signal_generator as sg
from signal_generator import (
    SignalResult, ATR_STOP_MULT, RR_DEFAULT, SCORE_THRESHOLD, MIN_CANDLES,
    calc_stop_atr, calc_target,
)
from indicators import ema, rsi, atr, macd, bollinger, adx
from trade_simulator import simulate_trade
from metrics import calc_metrics, calc_metrics_by_regime
from backtest_2w_14y import (
    MARKET, PERIOD_1D, START, END, RESAMPLE_DAYS,
    MAX_BARS_FORWARD, FEE_PCT, CYCLES,
    resample_to_2w, classify_by_sma, in_cycle,
)


def generate_signal_with_rsi_mode(candles: List[Dict], rsi_mode: str = "baseline",
                                   regime_hint: str = "sideways") -> SignalResult:
    """Versao parametrizavel do generate_signal — varia o tratamento de RSI overbought em bull."""
    entry = candles[-1]["close"] if candles else 0.0
    neutral = SignalResult(signal="NEUTRO", score=50.0, entry_price=entry,
                           stop_loss=entry * 0.98, take_profit=entry * 1.06, atr=0.0)
    if len(candles) < MIN_CANDLES:
        return neutral

    closes = [c["close"] for c in candles]
    score_bullish = 0
    score_bearish = 0
    max_points = 0

    # EMA Cross 9/21
    try:
        e9, e21 = ema(closes, 9), ema(closes, 21)
        e50 = ema(closes[-50:] if len(closes) >= 50 else closes, min(50, len(closes)))
        if e9 > e21: score_bullish += 15
        elif e9 < e21: score_bearish += 15
        max_points += 15
        if entry > e50: score_bullish += 10
        else: score_bearish += 10
        max_points += 10
    except Exception: pass

    # RSI — variante experimental
    try:
        r = rsi(closes, 14)
        if r < 35:
            score_bullish += 20
        elif r > 65:
            if rsi_mode == "v1" and regime_hint == "bull":
                pass  # neutro: 0pts
            elif rsi_mode == "v2" and regime_hint == "bull":
                score_bullish += 8  # mantem direcao em vez de penalizar
            else:
                score_bearish += 20
        else:
            if r > 50: score_bullish += 8
            else: score_bearish += 8
        max_points += 20
    except Exception: pass

    # MACD
    try:
        m_d = macd(closes)
        if m_d["histogram"] > 0: score_bullish += 15
        else: score_bearish += 15
        max_points += 15
    except Exception: pass

    # Bollinger
    try:
        bb = bollinger(closes[-20:] if len(closes) >= 20 else closes, period=min(20, len(closes)))
        if entry <= bb["lower"]: score_bullish += 15
        elif entry >= bb["upper"]: score_bearish += 15
        else:
            if entry > bb["middle"]: score_bullish += 5
            else: score_bearish += 5
        max_points += 15
    except Exception: pass

    # ADX
    try:
        a = adx(candles, period=14)
        if a["adx"] > 25:
            if a["pdi"] > a["ndi"]: score_bullish += 15
            else: score_bearish += 15
        max_points += 15
    except Exception: pass

    # Volume
    try:
        vols = [c["volume"] for c in candles[-20:]]
        avg_vol = sum(vols[:-1]) / max(len(vols) - 1, 1)
        cur_vol = vols[-1]
        if cur_vol > avg_vol * 1.3:
            if score_bullish > score_bearish: score_bullish += 10
            else: score_bearish += 10
        max_points += 10
    except Exception: pass

    if max_points == 0:
        return neutral
    bull_score = (score_bullish / max_points) * 100
    bear_score = (score_bearish / max_points) * 100

    if bull_score >= SCORE_THRESHOLD and bull_score > bear_score:
        direction, signal, score = "LONG", "COMPRA", bull_score
    elif bear_score >= SCORE_THRESHOLD and bear_score > bull_score:
        direction, signal, score = "SHORT", "VENDA", bear_score
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
    return SignalResult(signal=signal, score=round(score, 1),
                        entry_price=entry, stop_loss=round(stop, 6),
                        take_profit=round(take_profit, 6), atr=round(atr_val, 6))


def run_variant(twoweek: List[Dict], rsi_mode: str) -> List[Dict]:
    trades = []
    for i in range(MIN_CANDLES, len(twoweek)):
        window = twoweek[: i + 1]
        regime = classify_by_sma(window)  # classifica ANTES de gerar sinal
        result = generate_signal_with_rsi_mode(window, rsi_mode=rsi_mode, regime_hint=regime)
        if not result.is_actionable:
            continue
        forward = twoweek[i + 1 : i + 1 + MAX_BARS_FORWARD]
        if not forward:
            continue
        direction = "LONG" if result.signal == "COMPRA" else "SHORT"
        sim = simulate_trade(direction=direction, entry=result.entry_price,
                             stop=result.stop_loss, target=result.take_profit,
                             candles=forward, fee_pct=FEE_PCT)
        trades.append({
            "ts": twoweek[i]["ts"], "direction": direction,
            "result_r": sim.result_r, "regime": regime, "score": result.score,
        })
    return trades


def summarize(label: str, trades: List[Dict]) -> None:
    rs = [t["result_r"] for t in trades]
    regs = [t["regime"] for t in trades]
    if not rs:
        print(f"  {label:<10}  sem trades")
        return
    m = calc_metrics(rs)
    br = calc_metrics_by_regime(rs, regs)
    bull = br.bull
    print(f"  {label:<10} n={m.total_trades:3d}  win={m.win_rate:5.1f}%  "
          f"exp={m.expectancy_r:+.3f}R  PF={m.profit_factor:5.2f}  "
          f"DD={m.max_drawdown_r:5.2f}R  |  "
          f"BULL n={bull.total_trades if bull else 0:3d} "
          f"exp={bull.expectancy_r if bull else 0:+.3f}R")


def main():
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    daily = db.get_candles(MARKET, PERIOD_1D, START, END)
    twoweek = resample_to_2w(daily, RESAMPLE_DAYS)
    print(f"  {len(daily)} candles 1d -> {len(twoweek)} candles 2w\n")

    sep = "-" * 90
    print(sep)
    print("  EXPERIMENT: RSI overbought treatment em BULL macro (SMA50/2w)")
    print(sep)
    print(f"  {'Variant':<10} {'Resultado overall + breakdown BULL'}")
    print(sep)
    for mode in ("baseline", "v1", "v2"):
        trades = run_variant(twoweek, rsi_mode=mode)
        summarize(mode, trades)
    print(sep)
    print("  baseline: RSI > 65 = bearish (-20pts) sempre")
    print("  v1: em bull macro, RSI > 65 vira neutro (0pts)")
    print("  v2: em bull macro, RSI > 65 vira bullish leve (+8pts)")


if __name__ == "__main__":
    main()