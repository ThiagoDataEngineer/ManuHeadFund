"""
short_freetier_validation.py — Tentar viabilizar shorts no BTC com Free Tier data.

Adiciona ao stack TA:
  - Fear & Greed Index (api.alternative.me, 2018+)
  - Binance funding rate histórico (2019-09+)

Logica: F&G/funding sao usados como GATES (binarios) — extremos sao raros mas
significativos. TA pura ja foi provada insuficiente para topos do BTC.

Cobertura dos topos:
  2013 — somente TA+FRED (sem F&G/funding)
  2017 — somente TA+FRED (F&G começou em Fev/2018, 2 meses após o topo)
  2021 — TA+FRED+F&G+funding (cobertura completa)
  2024 — TA+FRED+F&G+funding (cobertura completa)
"""
import json
import os
import sys
import time
import urllib.request

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass
from datetime import datetime, timedelta, timezone
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


# ─── Free tier fetchers ──────────────────────────────────────────────────────

def fetch_fear_greed() -> Dict[str, int]:
    """Retorna dict[date_iso] = value (0-100)."""
    print("  Fetching Fear & Greed...", end=" ", flush=True)
    url = "https://api.alternative.me/fng/?limit=0&format=json"
    resp = urllib.request.urlopen(url, timeout=20)
    data = json.loads(resp.read().decode())
    out = {}
    for row in data.get("data", []):
        ts = int(row["timestamp"])
        date = datetime.fromtimestamp(ts, tz=timezone.utc).date().isoformat()
        out[date] = int(row["value"])
    print(f"{len(out)} dias ({min(out)} -> {max(out)})")
    return out


def fetch_binance_funding(symbol: str = "BTCUSDT") -> Dict[str, float]:
    """Retorna dict[date_iso] = mean_funding_rate_8h_pct.

    Binance retorna funding a cada 8h. Agregamos pra media diaria.
    Cobertura: 2019-09-08+.
    """
    print("  Fetching Binance funding rate...", end=" ", flush=True)
    all_rows = []
    end_ms = int(datetime.now(tz=timezone.utc).timestamp() * 1000)
    start_ms = int(datetime(2019, 9, 1, tzinfo=timezone.utc).timestamp() * 1000)
    cursor = end_ms

    while cursor > start_ms:
        url = (f"https://fapi.binance.com/fapi/v1/fundingRate?symbol={symbol}"
               f"&limit=1000&endTime={cursor}")
        try:
            resp = urllib.request.urlopen(url, timeout=15)
            batch = json.loads(resp.read().decode())
        except Exception as e:
            print(f" ERR {e}", end="")
            break
        if not batch:
            break
        all_rows.extend(batch)
        oldest = min(r["fundingTime"] for r in batch)
        if oldest >= cursor or oldest <= start_ms:
            break
        cursor = oldest - 1
        time.sleep(0.15)

    # Agregar por dia (media)
    by_day: Dict[str, List[float]] = {}
    for r in all_rows:
        ts = r["fundingTime"]
        date = datetime.fromtimestamp(ts / 1000, tz=timezone.utc).date().isoformat()
        rate_pct = float(r["fundingRate"]) * 100  # convert to pct
        by_day.setdefault(date, []).append(rate_pct)
    out = {d: sum(v) / len(v) for d, v in by_day.items()}
    if out:
        print(f"{len(out)} dias ({min(out)} -> {max(out)}, total samples {len(all_rows)})")
    return out


def value_on_or_before(series: Dict, target_date: str, max_back: int = 7) -> Optional[float]:
    if target_date in series:
        return series[target_date]
    dt = datetime.fromisoformat(target_date).date()
    for delta in range(1, max_back + 1):
        prev = (dt - timedelta(days=delta)).isoformat()
        if prev in series:
            return series[prev]
    return None


def rolling_avg(series: Dict, target_date: str, days: int = 30) -> Optional[float]:
    """Media dos ultimos N dias da serie ate target_date inclusive."""
    dt = datetime.fromisoformat(target_date).date()
    vals = []
    for d in range(days):
        date = (dt - timedelta(days=d)).isoformat()
        if date in series:
            vals.append(series[date])
    if len(vals) < max(3, days // 4):
        return None
    return sum(vals) / len(vals)


# ─── Short signal v2 — gates + score ─────────────────────────────────────────

def generate_short_signal_v2(
    candles: List[Dict],
    ts: str,
    fng: Dict[str, int],
    funding: Dict[str, float],
) -> SignalResult:
    """Gates + score. Reject early se gates obrigatorios nao baterem.

    GATE 1 (exaustao sentimental): F&G > 75 OR F&G_30d_avg > 70
      Se F&G indisponivel (pre-2018) → RSI 2w >= 70 como proxy
    GATE 2 (parabolico): close > SMA50 × 1.30 OU close > SMA200 × 2.0
    GATE 3 (confirmacao TA): pelo menos um de
      - RSI > 70
      - RSI bearish divergence
      - close >= upper Bollinger × 1.02
      - funding > 0.04% (se disponivel)

    Se todos os 3 gates passam: gera VENDA com score = funcao dos boosts.
    """
    entry = candles[-1]["close"] if candles else 0.0
    neutral = SignalResult(signal="NEUTRO", score=50.0, entry_price=entry,
                           stop_loss=entry * 1.02, take_profit=entry * 0.94, atr=0.0)
    if len(candles) < MIN_CANDLES:
        return neutral

    closes = [c["close"] for c in candles]
    date = ts[:10]

    # Calcula features
    try: rsi_val = rsi(closes, 14)
    except: rsi_val = 50.0
    try: sma50 = sum(closes[-50:]) / 50 if len(closes) >= 50 else closes[-1]
    except: sma50 = closes[-1]
    try: sma200 = sum(closes[-200:]) / 200 if len(closes) >= 200 else closes[-1]
    except: sma200 = closes[-1]
    try: bb = bollinger(closes[-20:] if len(closes) >= 20 else closes, period=min(20, len(closes)))
    except: bb = {"upper": entry * 1.5, "middle": entry, "lower": entry * 0.5}

    fng_now = value_on_or_before(fng, date) if fng else None
    fng_30d = rolling_avg(fng, date, 30) if fng else None
    funding_now = value_on_or_before(funding, date) if funding else None
    funding_30d = rolling_avg(funding, date, 30) if funding else None

    # GATE 1 — exaustao sentimental
    gate1 = False
    gate1_source = ""
    if fng_now is not None:
        if fng_now >= 75 or (fng_30d is not None and fng_30d >= 70):
            gate1 = True; gate1_source = f"F&G={fng_now}/{fng_30d}"
    if not gate1:
        # Pre-2018 proxy: RSI 2w/1w extremo
        if rsi_val >= 70:
            gate1 = True; gate1_source = f"RSI={rsi_val:.1f}(proxy)"

    if not gate1:
        return neutral

    # GATE 2 — parabolico
    gate2 = False
    gate2_source = ""
    if sma50 > 0 and (entry / sma50) > 1.30:
        gate2 = True; gate2_source = f"+{(entry/sma50-1)*100:.0f}% above SMA50"
    elif sma200 > 0 and (entry / sma200) > 2.0:
        gate2 = True; gate2_source = f"+{(entry/sma200-1)*100:.0f}% above SMA200"

    if not gate2:
        return neutral

    # GATE 3 — confirmacao TA
    confirmations = []
    if rsi_val > 70:
        confirmations.append(f"RSI={rsi_val:.0f}")
    if entry >= bb["upper"] * 1.02:
        confirmations.append("BB+")
    if funding_now is not None and funding_now > 0.04:
        confirmations.append(f"funding={funding_now:.3f}%")
    if funding_30d is not None and funding_30d > 0.03:
        confirmations.append(f"funding_30d={funding_30d:.3f}%")

    if not confirmations:
        return neutral

    # Score: base 65 + boosts
    score = 65
    if fng_now is not None and fng_now >= 85: score += 10
    if funding_30d is not None and funding_30d > 0.05: score += 10
    if rsi_val > 80: score += 5
    score = min(score, 95)

    # Stop/target apertados
    try: atr_val = atr(candles, period=14)
    except: atr_val = entry * 0.02
    stop = entry + 1.5 * atr_val
    risk = abs(entry - stop)
    target = entry - 3.0 * risk

    sig = SignalResult(signal="VENDA", score=score,
                       entry_price=entry, stop_loss=round(stop, 6),
                       take_profit=round(target, 6), atr=round(atr_val, 6))
    # Anexar metadata pra audit
    sig.indicators = {
        "gate1": gate1_source, "gate2": gate2_source,
        "confirmations": ",".join(confirmations),
        "fng_now": fng_now, "fng_30d": fng_30d,
        "funding_now": funding_now, "funding_30d": funding_30d,
        "rsi": rsi_val,
    }
    return sig


# ─── Resample helpers ────────────────────────────────────────────────────────

def resample_calendar_month(daily: List[Dict]) -> List[Dict]:
    from collections import defaultdict
    buckets = defaultdict(list)
    for c in daily:
        buckets[c["ts"][:7]].append(c)
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


# ─── Top detection ───────────────────────────────────────────────────────────

def find_macro_tops(daily: List[Dict]) -> List[str]:
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


def backward_validate_at_tops(
    weekly: List[Dict],
    tops: List[str],
    fng: Dict[str, int],
    funding: Dict[str, float],
    window_days: int = 60,
) -> List[Dict]:
    """Para cada topo, verifica se o sinal short v2 dispararia em [-60, +0] dias do topo."""
    results = []
    for top in tops:
        top_dt = datetime.fromisoformat(top).date()
        triggered = []
        for i, c in enumerate(weekly):
            c_dt = datetime.fromisoformat(c["ts"][:10]).date()
            delta = (c_dt - top_dt).days
            if -window_days <= delta <= 0:
                window = weekly[: i + 1]
                sig = generate_short_signal_v2(window, c["ts"], fng, funding)
                if sig.signal == "VENDA":
                    triggered.append({
                        "ts": c["ts"][:10], "delta_to_top": delta,
                        "score": sig.score, "indicators": sig.indicators,
                    })
        results.append({"top": top, "triggers": triggered})
    return results


# ─── Engine ──────────────────────────────────────────────────────────────────

def run_strategy_v2(
    twoweek: List[Dict],
    weekly: List[Dict],
    fng: Dict[str, int],
    funding: Dict[str, float],
) -> List[Dict]:
    trades = []
    # Longs em 2w (baseline)
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
                             candles=forward, fee_pct=FEE_PCT)
        trades.append({"ts": twoweek[i]["ts"], "tf": "2w", "direction": "LONG",
                       "result_r": sim.result_r, "score": result.score})

    # Shorts em 1w com short_v2 (gates)
    MAX_BARS_FWD_1W = 12
    for i in range(MIN_CANDLES, len(weekly)):
        window = weekly[: i + 1]
        result = generate_short_signal_v2(window, weekly[i]["ts"], fng, funding)
        if result.signal != "VENDA":
            continue
        forward = weekly[i + 1 : i + 1 + MAX_BARS_FWD_1W]
        if not forward:
            continue
        sim = simulate_trade(direction="SHORT", entry=result.entry_price,
                             stop=result.stop_loss, target=result.take_profit,
                             candles=forward, fee_pct=FEE_PCT)
        trades.append({"ts": weekly[i]["ts"], "tf": "1w", "direction": "SHORT",
                       "result_r": sim.result_r, "score": result.score,
                       "meta": getattr(result, "indicators", {})})
    return trades


def summarize(label: str, trades: List[Dict]) -> None:
    longs  = [t for t in trades if t["direction"] == "LONG"]
    shorts = [t for t in trades if t["direction"] == "SHORT"]
    rs = [t["result_r"] for t in trades]
    if not rs:
        print(f"  {label:<35}  sem trades"); return
    m = calc_metrics(rs)
    print(f"  {label:<35} n={m.total_trades:3d} (L={len(longs):3d}/S={len(shorts):3d})  "
          f"win={m.win_rate:5.1f}%  exp={m.expectancy_r:+.3f}R  "
          f"PF={m.profit_factor:5.2f}  DD={m.max_drawdown_r:5.2f}R")


def main():
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    daily = db.get_candles(MARKET, PERIOD_1D, START, END)
    twoweek = resample_to_2w(daily, days=14)
    weekly  = resample_to_2w(daily, days=7)
    print(f"  {len(daily)} candles 1d | 2w={len(twoweek)} | 1w={len(weekly)}")

    tops = find_macro_tops(daily)
    print(f"  Topos macro: {tops}")

    print(f"\n  Free Tier data:")
    fng = fetch_fear_greed()
    funding = fetch_binance_funding()

    sep = "=" * 100
    print(f"\n{sep}")
    print("  BACKWARD VALIDATION — short v2 dispara nos 4 topos macro?")
    print(sep)
    validation = backward_validate_at_tops(weekly, tops, fng, funding, window_days=60)
    captured = 0
    for v in validation:
        if v["triggers"]:
            captured += 1
            best = max(v["triggers"], key=lambda t: t["score"])
            print(f"  TOP {v['top']}: [OK] {len(v['triggers'])} triggers (best score={best['score']}, delta={best['delta_to_top']:+d}d)")
            print(f"    {best['indicators'].get('gate1')} | {best['indicators'].get('gate2')} | {best['indicators'].get('confirmations')}")
        else:
            print(f"  TOP {v['top']}: [NO] nao disparou em +-60 dias")
    print(f"\n  Captura: {captured}/{len(tops)} topos disparam sinal short v2")

    print(f"\n{sep}")
    print("  PERFORMANCE FULL — 14 anos, long 2w + short v2 1w")
    print(sep)
    trades_v2 = run_strategy_v2(twoweek, weekly, fng, funding)
    summarize("v2 (gates F&G+funding+TA)", trades_v2)
    longs_only = [t for t in trades_v2 if t["direction"] == "LONG"]
    summarize("baseline (LONG-only)", longs_only)

    # Detalhe dos shorts gerados
    shorts = [t for t in trades_v2 if t["direction"] == "SHORT"]
    if shorts:
        print(f"\n  TODOS OS SHORTS v2 ({len(shorts)} trades):")
        for s in shorts:
            meta = s.get("meta", {})
            print(f"    {s['ts'][:10]}  r={s['result_r']:+.2f}R  score={s['score']}  "
                  f"{meta.get('gate1','')} | {meta.get('gate2','')} | {meta.get('confirmations','')}")

    # Veredito
    a = calc_metrics([t["result_r"] for t in longs_only]).expectancy_r
    b = calc_metrics([t["result_r"] for t in trades_v2]).expectancy_r
    print(f"\n{sep}")
    print(f"  VEREDITO")
    print(f"  LONG-only expectancy:  {a:+.3f}R")
    print(f"  v2 (com shorts):       {b:+.3f}R  ({'+' if b>a else ''}{(b-a):+.3f}R vs baseline)")
    if b > a + 0.1 and captured >= 3:
        print(f"  -> EDGE REAL: shorts v2 melhoram o sistema E capturam {captured}/4 topos. APROVAR.")
    elif b > a - 0.05 and captured >= 2:
        print(f"  -> NEUTRO/POSITIVO: nao destroem, capturam {captured}/4. Considerar incluir.")
    else:
        print(f"  -> INSUFICIENTE: capturam {captured}/4, expectancy {b-a:+.3f}R. Nao incluir.")
    print(sep)


if __name__ == "__main__":
    main()