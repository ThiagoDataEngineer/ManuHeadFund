"""stablecoin_overlay_14y.py — Overlay regime stablecoin no backtest BTC 2w/14y.

Pergunta: regime WARNING/CONTRACTION/CRISIS precedeu drawdowns conhecidos?
"""
import json
import os
import urllib.request
from datetime import datetime, timedelta, timezone
from typing import Dict

from dotenv import load_dotenv
load_dotenv()

from db import Database
from stablecoin_regime import regime_at, classify_regime, compute_supply_change
from backtest_2w_14y import MARKET, PERIOD_1D, START, END

# DeFiLlama: USDT (id=1)
USDT_CHART_URL = "https://stablecoins.llama.fi/stablecoincharts/all?stablecoin=1"


def fetch_stablecoin_supply() -> Dict[str, float]:
    """Retorna dict[date_iso] = total_circulating_USD do USDT."""
    print("  Fetching DeFiLlama USDT supply...", end=" ", flush=True)
    resp = urllib.request.urlopen(USDT_CHART_URL, timeout=20)
    data = json.loads(resp.read().decode())
    out = {}
    for row in data:
        ts = int(row["date"])
        date = datetime.fromtimestamp(ts, tz=timezone.utc).date().isoformat()
        peg = row.get("totalCirculatingUSD", {})
        val = peg.get("peggedUSD") if isinstance(peg, dict) else None
        if val:
            out[date] = float(val)
    print(f"{len(out)} dias ({min(out)} -> {max(out)})")
    return out


def future_drawdown(daily: Dict[str, float], target_date: str, days: int = 60) -> float:
    """Maior drawdown nos proximos N dias a partir do close de target_date."""
    if target_date not in daily:
        return 0.0
    base = daily[target_date]
    target_dt = datetime.fromisoformat(target_date).date()
    lows = []
    for d in range(1, days + 1):
        future_date = (target_dt + timedelta(days=d)).isoformat()
        if future_date in daily:
            lows.append(daily[future_date])
    if not lows:
        return 0.0
    min_close = min(lows)
    return ((min_close - base) / base) * 100


def main():
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    daily = db.get_candles(MARKET, PERIOD_1D, START, END)
    daily_map = {c["ts"][:10]: float(c["close"]) for c in daily}

    supply = fetch_stablecoin_supply()
    print(f"  BTC candles: {len(daily_map)} | Supply days: {len(supply)}")

    # Classifica regime a cada 15 dias e mede drawdown 60d forward
    from collections import Counter
    regime_counts = Counter()
    regime_dd_60d: Dict[str, list] = {}
    rows = []
    sorted_dates = sorted(supply.keys())
    for i, date in enumerate(sorted_dates):
        if i % 15 != 0:
            continue
        r = regime_at(supply, date)
        if r["regime"] == "UNKNOWN":
            continue
        regime_counts[r["regime"]] += 1
        dd = future_drawdown(daily_map, date, days=60)
        regime_dd_60d.setdefault(r["regime"], []).append(dd)
        rows.append({
            "date": date, "regime": r["regime"],
            "supply_change_30d": r["supply_change_30d_pct"],
            "btc_close": daily_map.get(date),
            "dd_60d_pct": dd,
        })

    sep = "=" * 80
    print(f"\n{sep}")
    print("  DISTRIBUICAO DE REGIMES (sample a cada 15 dias)")
    print(sep)
    for k in ("EXPANSION", "NEUTRAL", "WARNING", "CONTRACTION", "CRISIS"):
        n = regime_counts.get(k, 0)
        avg_dd = sum(regime_dd_60d.get(k, [0])) / max(len(regime_dd_60d.get(k, [1])), 1)
        worst_dd = min(regime_dd_60d.get(k, [0]))
        print(f"  {k:<12}  n={n:3d}  avg_dd_60d={avg_dd:+6.2f}%  worst={worst_dd:+6.2f}%")
    print(sep)

    print("\n  MOMENTOS CRITICOS — regime CONTRACTION/CRISIS no historico:")
    critical = [r for r in rows if r["regime"] in ("CONTRACTION", "CRISIS")]
    for r in critical:
        btc = r["btc_close"] or 0
        print(f"  {r['date']}  {r['regime']:<12}  supply={r['supply_change_30d']:+6.2f}%  "
              f"BTC=${btc:>9,.0f}  dd_60d={r['dd_60d_pct']:+6.2f}%")

    # Top 10 worst drawdowns 60d e regime nesses momentos
    print(f"\n  TOP 10 WORST DRAWDOWNS 60d — regime nesses momentos:")
    rows_sorted = sorted(rows, key=lambda r: r["dd_60d_pct"])[:10]
    for r in rows_sorted:
        btc = r["btc_close"] or 0
        print(f"  {r['date']}  dd_60d={r['dd_60d_pct']:+6.2f}%  regime={r['regime']:<12}  "
              f"supply={r['supply_change_30d']:+6.2f}%  BTC=${btc:>9,.0f}")

    # Veredito: regime "ruim" prediz drawdowns?
    dd_in_warning = regime_dd_60d.get("WARNING", []) + regime_dd_60d.get("CONTRACTION", []) + regime_dd_60d.get("CRISIS", [])
    dd_in_good   = regime_dd_60d.get("EXPANSION", []) + regime_dd_60d.get("NEUTRAL", [])
    avg_warn = sum(dd_in_warning) / max(len(dd_in_warning), 1) if dd_in_warning else 0
    avg_good = sum(dd_in_good) / max(len(dd_in_good), 1) if dd_in_good else 0
    print(f"\n{sep}")
    print("  VEREDITO ESTATISTICO")
    print(sep)
    print(f"  Avg dd_60d em regime WARNING+:    {avg_warn:+.2f}%  (n={len(dd_in_warning)})")
    print(f"  Avg dd_60d em regime EXPAN/NEUT:  {avg_good:+.2f}%  (n={len(dd_in_good)})")
    diff = avg_warn - avg_good
    if diff < -5:
        print(f"  -> EDGE REAL: regime ruim antecipa drawdowns {-diff:.1f}pp piores em media")
    elif diff < -1:
        print(f"  -> SINAL FRACO: regime ruim antecipa ligeira piora ({-diff:.1f}pp)")
    else:
        print(f"  -> SEM SINAL: regime nao discrimina ({diff:+.1f}pp)")
    print(sep)


if __name__ == "__main__":
    main()
