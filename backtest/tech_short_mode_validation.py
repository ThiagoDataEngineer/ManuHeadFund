"""
tech_short_mode_validation.py — Valida extensao do TechAgent com short_bias mode.

Compara 3 estrategias sobre BTCUSD 14 anos:
  A. long_bias 2w (baseline atual)
  B. long_bias 2w + short_bias 1w (multi-TF, sem filtro macro)
  C. long_bias 2w + short_bias 1w + filtro macro_bias (short so em BEARISH/NEUTRAL + price < SMA50 1M)

Foca em:
  - Performance global (expectancy, PF, DD)
  - Captura dos 4 topos macro (2013/2017/2021/2024)
"""
import os
import urllib.request
from datetime import datetime, timedelta
from typing import Dict, List, Optional

from dotenv import load_dotenv
load_dotenv()

from db import Database
from indicators import ema, rsi, atr, macd, bollinger, adx
from signal_generator import (
    SignalResult, generate_signal,
    ATR_STOP_MULT, RR_DEFAULT, SCORE_THRESHOLD, MIN_CANDLES,
    calc_stop_atr, calc_target,
)
from trade_simulator import simulate_trade
from metrics import calc_metrics
from backtest_2w_14y import (
    MARKET, PERIOD_1D, START, END,
    MAX_BARS_FORWARD, FEE_PCT,
    resample_to_2w,
)
from validate_macro_bias_2w_14y import FRED_SERIES, fetch_fred, macro_bias_at

FEE_PCT_USE = FEE_PCT


# ─── Resample helpers ────────────────────────────────────────────────────────

def resample_calendar_month(daily: List[Dict]) -> List[Dict]:
    """Agrega 1d em candles 1M baseado no mes calendario (YYYY-MM)."""
    from collections import defaultdict
    buckets = defaultdict(list)
    for c in daily:
        key = c["ts"][:7]  # YYYY-MM
        buckets[key].append(c)
    out = []
    for key in sorted(buckets.keys()):
        rows = sorted(buckets[key], key=lambda r: r["ts"])
        out.append({
            "market": rows[0]["market"], "period": "1month",
            "ts":     rows[0]["ts"],
            "open":   float(rows[0]["open"]),
            "high":   max(float(r["high"]) for r in rows),
            "low":    min(float(r["low"]) for r in rows),
            "close":  float(rows[-1]["close"]),
            "volume": sum(float(r["volume"]) for r in rows),
        })
    return out


# ─── Short-bias signal logic ─────────────────────────────────────────────────

def detect_rsi_bearish_divergence(candles: List[Dict], lookback: int = 10) -> bool:
    """Detecta divergencia bearish: price HH + RSI LH nos ultimos 2 swing highs."""
    if len(candles) < lookback * 2 + 14:
        return False
    closes = [c["close"] for c in candles]
    # Two recent price highs
    seg1 = closes[-2 * lookback : -lookback]
    seg2 = closes[-lookback:]
    p_high1 = max(seg1); p_high2 = max(seg2)
    if p_high2 <= p_high1:
        return False
    # RSI nos mesmos pontos
    idx_h1 = (len(closes) - 2 * lookback) + seg1.index(p_high1)
    idx_h2 = (len(closes) - lookback) + seg2.index(p_high2)
    rsi_h1 = rsi(closes[: idx_h1 + 1], 14)
    rsi_h2 = rsi(closes[: idx_h2 + 1], 14)
    return rsi_h2 < rsi_h1 - 3  # RSI caiu apesar do preco subir


def detect_volume_divergence(candles: List[Dict], lookback: int = 5) -> bool:
    """Rally com volume caindo: ultimos 3 candles verdes + volume menor que media 5 anteriores."""
    if len(candles) < lookback + 3:
        return False
    recent = candles[-3:]
    if not all(c["close"] > c["open"] for c in recent):
        return False
    recent_vol = sum(c["volume"] for c in recent) / 3
    prior_vol = sum(c["volume"] for c in candles[-(lookback + 3):-3]) / lookback
    return recent_vol < prior_vol * 0.85


def generate_short_signal(candles: List[Dict]) -> SignalResult:
    """Score baseado em EXAUSTAO (RSI extremo, divergencias, parabolico) — nao em continuacao."""
    entry = candles[-1]["close"] if candles else 0.0
    neutral = SignalResult(signal="NEUTRO", score=50.0, entry_price=entry,
                           stop_loss=entry * 1.02, take_profit=entry * 0.94, atr=0.0)
    if len(candles) < MIN_CANDLES:
        return neutral

    closes = [c["close"] for c in candles]
    score = 0
    max_points = 0

    # 1. RSI extremo overbought (>75 = exaustao real)
    try:
        r = rsi(closes, 14)
        if r > 80:   score += 30
        elif r > 75: score += 20
        elif r > 70: score += 10
        max_points += 30
    except Exception:
        pass

    # 2. Divergencia bearish (RSI LH em price HH)
    try:
        if detect_rsi_bearish_divergence(candles):
            score += 25
        max_points += 25
    except Exception:
        pass

    # 3. Parabolico — distancia muito alta de SMA50
    try:
        if len(closes) >= 50:
            sma50 = sum(closes[-50:]) / 50
            dist = (entry - sma50) / sma50
            if dist > 0.60: score += 20
            elif dist > 0.40: score += 15
            elif dist > 0.25: score += 8
            max_points += 20
    except Exception:
        pass

    # 4. EMA cross bearish (peso reduzido — bears bouncam)
    try:
        e9, e21 = ema(closes, 9), ema(closes, 21)
        if e9 < e21: score += 10
        max_points += 10
    except Exception:
        pass

    # 5. MACD < 0 com momento perdendo
    try:
        m = macd(closes)
        if m["histogram"] < 0 and m["macd"] < m["signal"]: score += 8
        max_points += 8
    except Exception:
        pass

    # 6. Volume divergence
    try:
        if detect_volume_divergence(candles):
            score += 15
        max_points += 15
    except Exception:
        pass

    # 7. Preco no upper Bollinger
    try:
        bb = bollinger(closes[-20:] if len(closes) >= 20 else closes, period=min(20, len(closes)))
        if entry >= bb["upper"] * 1.02:  # 2% acima do upper band
            score += 12
        max_points += 12
    except Exception:
        pass

    if max_points == 0:
        return neutral
    score_pct = (score / max_points) * 100

    # Threshold mais alto pra short (so abrir em alta confluencia)
    if score_pct < 60:
        return SignalResult(signal="NEUTRO", score=round(score_pct, 1),
                            entry_price=entry, stop_loss=entry * 1.02,
                            take_profit=entry * 0.94, atr=0.0)

    # Stop/target: ATR×1.5 (aperta) + RR 1:3
    try:
        atr_val = atr(candles, period=14)
    except Exception:
        atr_val = entry * 0.01
    stop = entry + 1.5 * atr_val
    risk = abs(entry - stop)
    target = entry - 3.0 * risk  # RR 1:3
    return SignalResult(signal="VENDA", score=round(score_pct, 1),
                        entry_price=entry, stop_loss=round(stop, 6),
                        take_profit=round(target, 6), atr=round(atr_val, 6))


# ─── Topos macro ─────────────────────────────────────────────────────────────

def find_macro_tops(daily: List[Dict]) -> List[str]:
    """Acha os topos macro: argmax(close) em janelas de ±90 dias em torno das datas conhecidas."""
    known = ["2013-12-01", "2017-12-15", "2021-11-10", "2024-03-14"]
    tops = []
    for target in known:
        target_dt = datetime.fromisoformat(target).date()
        window = [c for c in daily
                  if abs((datetime.fromisoformat(c["ts"][:10]).date() - target_dt).days) <= 90]
        if not window:
            continue
        peak = max(window, key=lambda c: c["close"])
        tops.append(peak["ts"][:10])
    return tops


# ─── Engine ──────────────────────────────────────────────────────────────────

def run_strategy(
    twoweek: List[Dict],
    weekly: List[Dict],
    monthly: List[Dict],
    macro_per_2w: Dict[str, str],
    macro_per_1w: Dict[str, str],
    enable_short: bool,
    macro_filter: bool,
) -> List[Dict]:
    """Roda estrategia: longs em 2w (baseline) + shorts opcionais em 1w."""
    trades = []

    # ── Longs em 2w (baseline TechAgent) ──────────────────────────────────────
    for i in range(MIN_CANDLES, len(twoweek)):
        window = twoweek[: i + 1]
        result = generate_signal(window)
        if not result.is_actionable or result.signal != "COMPRA":
            continue
        forward = twoweek[i + 1 : i + 1 + MAX_BARS_FORWARD]
        if not forward:
            continue
        sim = simulate_trade(direction="LONG", entry=result.entry_price,
                             stop=result.stop_loss, target=result.take_profit,
                             candles=forward, fee_pct=FEE_PCT_USE)
        trades.append({"ts": twoweek[i]["ts"], "tf": "2w", "direction": "LONG",
                       "result_r": sim.result_r, "score": result.score})

    if not enable_short:
        return trades

    # ── Shorts em 1w com short_bias (exaustao) ────────────────────────────────
    SMA50_MONTHLY = {}
    for i, c in enumerate(monthly):
        if i < 50:
            continue
        sma50 = sum(m["close"] for m in monthly[i - 50:i]) / 50
        SMA50_MONTHLY[c["ts"][:7]] = sma50

    def price_below_sma50_monthly(ts_iso: str, close: float) -> bool:
        ym = ts_iso[:7]
        sma = SMA50_MONTHLY.get(ym)
        return sma is not None and close < sma

    MAX_BARS_FWD_1W = 12  # 12 weeks ~= 3 meses pra short trabalhar
    for i in range(MIN_CANDLES, len(weekly)):
        window = weekly[: i + 1]
        result = generate_short_signal(window)
        if result.signal != "VENDA":
            continue

        # Filtro macro (estrategia C)
        if macro_filter:
            bias = macro_per_1w.get(weekly[i]["ts"], "NEUTRAL")
            if bias == "BULLISH":
                continue
            if not price_below_sma50_monthly(weekly[i]["ts"], weekly[i]["close"]):
                continue

        forward = weekly[i + 1 : i + 1 + MAX_BARS_FWD_1W]
        if not forward:
            continue
        sim = simulate_trade(direction="SHORT", entry=result.entry_price,
                             stop=result.stop_loss, target=result.take_profit,
                             candles=forward, fee_pct=FEE_PCT_USE)
        trades.append({"ts": weekly[i]["ts"], "tf": "1w", "direction": "SHORT",
                       "result_r": sim.result_r, "score": result.score})

    return trades


def proximity_to_tops(trades: List[Dict], tops: List[str], days: int = 90) -> Dict:
    """Quantos shorts caem em janela ±N dias dos topos macro."""
    shorts = [t for t in trades if t["direction"] == "SHORT"]
    if not shorts:
        return {"near_tops": 0, "total_shorts": 0, "tops_captured": 0}
    near = []
    tops_set = set()
    for s in shorts:
        s_dt = datetime.fromisoformat(s["ts"][:10]).date()
        for top in tops:
            t_dt = datetime.fromisoformat(top).date()
            delta = (s_dt - t_dt).days
            if -days <= delta <= days:
                near.append((s, top, delta))
                tops_set.add(top)
                break
    return {
        "near_tops":     len(near),
        "total_shorts":  len(shorts),
        "tops_captured": len(tops_set),
        "details":       near,
    }


def summarize(label: str, trades: List[Dict]) -> None:
    longs  = [t for t in trades if t["direction"] == "LONG"]
    shorts = [t for t in trades if t["direction"] == "SHORT"]
    rs = [t["result_r"] for t in trades]
    if not rs:
        print(f"  {label:<35}  sem trades")
        return
    m = calc_metrics(rs)
    print(f"  {label:<35} n={m.total_trades:3d} "
          f"(L={len(longs):3d}/S={len(shorts):3d})  win={m.win_rate:5.1f}%  "
          f"exp={m.expectancy_r:+.3f}R  PF={m.profit_factor:5.2f}  DD={m.max_drawdown_r:5.2f}R")


def main():
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    daily = db.get_candles(MARKET, PERIOD_1D, START, END)
    twoweek = resample_to_2w(daily, days=14)
    weekly  = resample_to_2w(daily, days=7)
    monthly = resample_calendar_month(daily)
    print(f"  {len(daily)} candles 1d | 2w={len(twoweek)} | 1w={len(weekly)} | 1M={len(monthly)}")

    tops = find_macro_tops(daily)
    print(f"  Topos macro detectados: {tops}")

    print(f"\n  Baixando FRED...")
    fred = {name: fetch_fred(sid) for name, sid in FRED_SERIES.items()}

    print(f"  Reconstruindo macro_bias por 2w e 1w...")
    macro_2w = {c["ts"]: macro_bias_at(c["ts"], fred)[0] for c in twoweek}
    macro_1w = {c["ts"]: macro_bias_at(c["ts"], fred)[0] for c in weekly}

    sep = "=" * 100
    print(f"\n{sep}")
    print("  EXTENSAO TechAgent — long_bias 2w + short_bias 1w (modo exaustao)")
    print(sep)

    # A. Long-only baseline
    A = run_strategy(twoweek, weekly, monthly, macro_2w, macro_1w,
                     enable_short=False, macro_filter=False)
    # B. Long + Short sem filtro
    B = run_strategy(twoweek, weekly, monthly, macro_2w, macro_1w,
                     enable_short=True, macro_filter=False)
    # C. Long + Short COM filtro macro + SMA50 1M
    C = run_strategy(twoweek, weekly, monthly, macro_2w, macro_1w,
                     enable_short=True, macro_filter=True)

    print("  ESTRATEGIAS")
    summarize("A. long-only baseline", A)
    summarize("B. long 2w + short 1w (sem filtro)", B)
    summarize("C. long 2w + short 1w + filtro macro", C)

    # Captura dos topos
    print(f"\n  CAPTURA DOS TOPOS MACRO (±90 dias de cada topo):")
    for label, trades in [("B", B), ("C", C)]:
        prox = proximity_to_tops(trades, tops, days=90)
        print(f"  Estrategia {label}: {prox['near_tops']}/{prox['total_shorts']} shorts perto de topo  "
              f"|  {prox['tops_captured']}/{len(tops)} topos capturados")
        for det in prox.get("details", []):
            s, t, d = det
            print(f"     short {s['ts'][:10]}  (topo {t}, delta {d:+d}d, "
                  f"r={s['result_r']:+.2f}R, score={s['score']})")

    # Veredito
    print(f"\n{sep}")
    print("  VEREDITO")
    a_exp = calc_metrics([t["result_r"] for t in A]).expectancy_r if A else 0
    b_exp = calc_metrics([t["result_r"] for t in B]).expectancy_r if B else 0
    c_exp = calc_metrics([t["result_r"] for t in C]).expectancy_r if C else 0
    print(f"  Expectancy A (long-only):     {a_exp:+.3f}R")
    print(f"  Expectancy B (sem filtro):    {b_exp:+.3f}R  ({'melhora' if b_exp > a_exp else 'piora'} vs A)")
    print(f"  Expectancy C (com filtro):    {c_exp:+.3f}R  ({'melhora' if c_exp > a_exp else 'piora'} vs A)")
    if c_exp > a_exp + 0.1:
        print("  -> EDGE REAL EM SHORTS. Codificar short_bias no signal_generator.py oficial.")
    elif c_exp > a_exp - 0.05:
        print("  -> NEUTRO. Shorts nao destroem nem ajudam — manter long-only.")
    else:
        print("  -> SHORTS AINDA DESTROEM. Stack de exaustao insuficiente sem on-chain/sentiment.")
    print(sep)


if __name__ == "__main__":
    main()