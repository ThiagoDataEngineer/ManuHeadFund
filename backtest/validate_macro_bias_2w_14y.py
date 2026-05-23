"""
validate_macro_bias_2w_14y.py — Reconstroi macro_bias historico via FRED (DXY/M2/Yields/Fed)
e valida se filtrar trades por macro_bias melhora o resultado em 14 anos.

Replica a logica de lib_macro.ps1:
  DXY trend: subindo=-20, caindo=+20  (threshold 0.5% vs 14d atras)
  M2 trend:  expansao=+20, contracao=-20 (threshold 0.2% vs 14d atras)
  Yield curve: invertida (Y2>Y10)=-15, normal=+10
  Fed rate: <=3.0=+10, >=5.0=-10
  score>=60 BULLISH, <=40 BEARISH, else NEUTRAL
"""
import io
import os
import urllib.request
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, Tuple

from dotenv import load_dotenv
load_dotenv()

from db import Database
from signal_generator import generate_signal
from trade_simulator import simulate_trade
from metrics import calc_metrics, calc_metrics_by_regime
from backtest_2w_14y import (
    MARKET, PERIOD_1D, START, END, RESAMPLE_DAYS,
    MAX_BARS_FORWARD, FEE_PCT, CYCLES,
    resample_to_2w, classify_by_sma, in_cycle,
)

FRED_CACHE = os.path.join(os.path.dirname(__file__), ".fred_cache.json")

FRED_SERIES = {
    "DXY":  "DTWEXBGS",
    "M2":   "WM2NS",
    "Y10":  "DGS10",
    "Y2":   "DGS2",
    "FED":  "DFEDTARU",
}


def fetch_fred(series_id: str, start: str = "2011-01-01", end: str = "2026-12-31") -> Dict[str, float]:
    """Baixa CSV publico FRED e retorna dict[date_iso] = value."""
    url = f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={series_id}&cosd={start}&coed={end}"
    print(f"  Fetching {series_id}...", end=" ", flush=True)
    resp = urllib.request.urlopen(url, timeout=20)
    data = resp.read().decode()
    out: Dict[str, float] = {}
    for i, line in enumerate(data.strip().split("\n")):
        if i == 0:
            continue
        parts = line.split(",")
        if len(parts) < 2 or parts[1] in (".", ""):
            continue
        try:
            out[parts[0]] = float(parts[1])
        except ValueError:
            continue
    print(f"{len(out)} obs")
    return out


def value_on_or_before(series: Dict[str, float], target_date: str) -> Optional[float]:
    """Retorna o valor da serie na data alvo ou na data mais recente anterior."""
    if target_date in series:
        return series[target_date]
    # search backward up to 30 days
    dt = datetime.fromisoformat(target_date).date()
    for delta in range(1, 31):
        prev = (dt - timedelta(days=delta)).isoformat()
        if prev in series:
            return series[prev]
    return None


def macro_bias_at(ts_iso: str, fred: Dict[str, Dict[str, float]]) -> Tuple[str, int, Dict]:
    """Computa macro_bias para uma data, replicando lib_macro.ps1."""
    date = ts_iso[:10]
    date_dt = datetime.fromisoformat(date).date()
    date_prev_14d = (date_dt - timedelta(days=14)).isoformat()

    dxy_now  = value_on_or_before(fred["DXY"], date)
    dxy_prev = value_on_or_before(fred["DXY"], date_prev_14d)
    m2_now   = value_on_or_before(fred["M2"],  date)
    m2_prev  = value_on_or_before(fred["M2"],  date_prev_14d)
    y10      = value_on_or_before(fred["Y10"], date)
    y2       = value_on_or_before(fred["Y2"],  date)
    fed      = value_on_or_before(fred["FED"], date)

    # DXY trend (threshold 0.5%)
    if dxy_now is not None and dxy_prev:
        change = (dxy_now - dxy_prev) / dxy_prev
        dxy_trend = "subindo" if change > 0.005 else "caindo" if change < -0.005 else "lateral"
    else:
        dxy_trend = "lateral"

    # M2 trend (threshold 0.2%)
    if m2_now is not None and m2_prev:
        change = (m2_now - m2_prev) / m2_prev
        m2_trend = "expansao" if change > 0.002 else "contracao" if change < -0.002 else "lateral"
    else:
        m2_trend = "lateral"

    # Yield curve
    if y10 is not None and y2 is not None:
        yield_curve = "invertida" if y2 > y10 else "normal"
    else:
        yield_curve = "plana"

    # Fed rate (fallback 5.0 = bearish quando indisponivel)
    fed_val = fed if fed is not None else 5.0

    score = 50
    score += {"caindo": 20, "subindo": -20}.get(dxy_trend, 0)
    score += {"expansao": 20, "contracao": -20}.get(m2_trend, 0)
    score += {"normal": 10, "invertida": -15}.get(yield_curve, 0)
    if fed_val <= 3.0: score += 10
    elif fed_val >= 5.0: score -= 10
    score = max(0, min(100, score))

    bias = "BULLISH" if score >= 60 else "BEARISH" if score <= 40 else "NEUTRAL"
    info = {
        "dxy_trend": dxy_trend, "m2_trend": m2_trend,
        "yield_curve": yield_curve, "fed_rate": fed_val,
        "dxy_now": dxy_now, "m2_now": m2_now,
    }
    return bias, score, info


def main():
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    daily = db.get_candles(MARKET, PERIOD_1D, START, END)
    twoweek = resample_to_2w(daily, RESAMPLE_DAYS)
    print(f"  {len(daily)} candles 1d -> {len(twoweek)} candles 2w")

    # ── Fetch FRED ──────────────────────────────────────────────────────────
    print(f"\n  Baixando series FRED 2011-2026:")
    fred = {name: fetch_fred(sid) for name, sid in FRED_SERIES.items()}

    # ── Compute macro_bias for each 2w bar ──────────────────────────────────
    print(f"\n  Reconstruindo macro_bias por candle 2w...")
    macro_per_ts: Dict[str, Tuple[str, int]] = {}
    for c in twoweek:
        bias, score, info = macro_bias_at(c["ts"], fred)
        macro_per_ts[c["ts"]] = (bias, score)

    # Distribuicao macro
    from collections import Counter
    dist = Counter(b for b, _ in macro_per_ts.values())
    print(f"  Distribuicao macro_bias nos 385 candles 2w:")
    for k in ("BULLISH", "NEUTRAL", "BEARISH"):
        n = dist.get(k, 0)
        print(f"    {k:<8} {n:4d}  ({n/len(macro_per_ts)*100:5.1f}%)")

    # ── Gera sinais + simula trades, anotando macro_bias da data ────────────
    trades = []
    for i in range(35, len(twoweek)):
        window = twoweek[: i + 1]
        result = generate_signal(window)
        if not result.is_actionable:
            continue
        forward = twoweek[i + 1 : i + 1 + MAX_BARS_FORWARD]
        if not forward:
            continue
        direction = "LONG" if result.signal == "COMPRA" else "SHORT"
        sim = simulate_trade(direction=direction, entry=result.entry_price,
                             stop=result.stop_loss, target=result.take_profit,
                             candles=forward, fee_pct=FEE_PCT)
        macro_bias, macro_score = macro_per_ts[twoweek[i]["ts"]]
        trades.append({
            "ts": twoweek[i]["ts"], "direction": direction,
            "result_r": sim.result_r,
            "regime": classify_by_sma(window),
            "macro_bias": macro_bias, "macro_score": macro_score,
        })

    # ── Compare filtros ──────────────────────────────────────────────────────
    def summarize(label: str, ts: List[Dict]) -> None:
        if not ts:
            print(f"  {label:<35}  sem trades")
            return
        rs = [t["result_r"] for t in ts]
        m = calc_metrics(rs)
        print(f"  {label:<35} n={m.total_trades:3d}  win={m.win_rate:5.1f}%  "
              f"exp={m.expectancy_r:+.3f}R  PF={m.profit_factor:5.2f}  "
              f"DD={m.max_drawdown_r:5.2f}R")

    sep = "=" * 90
    print(f"\n{sep}")
    print(f"  VALIDACAO macro_bias historico — 14 anos / BTCUSD 2w")
    print(sep)

    # SHORT trades viram problema em bull macro (sistema vai contra a tendencia)
    longs = [t for t in trades if t["direction"] == "LONG"]
    shorts = [t for t in trades if t["direction"] == "SHORT"]
    print(f"\n  Total trades: {len(trades)}  (LONG={len(longs)}, SHORT={len(shorts)})")

    print(f"\n  COMPARATIVO: filtros sobre o universo completo (LONG+SHORT)")
    summarize("baseline (sem filtro)",        trades)
    summarize("so BULLISH",                   [t for t in trades if t["macro_bias"] == "BULLISH"])
    summarize("BULLISH ou NEUTRAL",            [t for t in trades if t["macro_bias"] != "BEARISH"])
    summarize("nao BEARISH (= bull+neutral)",  [t for t in trades if t["macro_bias"] != "BEARISH"])

    print(f"\n  COMPARATIVO: LONG ONLY (regra de ouro: nao SHORT BTC em bull macro)")
    summarize("LONG baseline",                 longs)
    summarize("LONG + macro BULLISH",          [t for t in longs if t["macro_bias"] == "BULLISH"])
    summarize("LONG + macro NEUTRAL",          [t for t in longs if t["macro_bias"] == "NEUTRAL"])
    summarize("LONG + macro BEARISH",          [t for t in longs if t["macro_bias"] == "BEARISH"])
    summarize("LONG nao BEARISH",              [t for t in longs if t["macro_bias"] != "BEARISH"])

    print(f"\n  COMPARATIVO: SHORT ONLY")
    summarize("SHORT baseline",                shorts)
    summarize("SHORT + macro BEARISH",         [t for t in shorts if t["macro_bias"] == "BEARISH"])
    summarize("SHORT nao BULLISH",             [t for t in shorts if t["macro_bias"] != "BULLISH"])

    print(sep)


if __name__ == "__main__":
    main()
