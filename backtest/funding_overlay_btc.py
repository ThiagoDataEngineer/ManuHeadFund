"""funding_overlay_btc.py — Valida funding_peak signals contra drawdowns BTC 2019+."""
import json
import os
import sys
import time
import urllib.request
from datetime import datetime, timedelta, timezone
from typing import Dict

try: sys.stdout.reconfigure(encoding="utf-8")
except Exception: pass

from dotenv import load_dotenv
load_dotenv()

from db import Database
from funding_peak import scan_signals
from backtest_2w_14y import MARKET, PERIOD_1D


def fetch_coinex_funding_full(symbol: str = "BTCUSDT", max_pages: int = 200) -> Dict[str, float]:
    """Fetch funding rate completo CoinEx via paginacao por page."""
    print("  Fetching CoinEx funding (full history)...", flush=True)
    all_rows = []
    page = 1
    while page <= max_pages:
        url = (f"https://api.coinex.com/v2/futures/funding-rate-history?"
               f"market={symbol}&limit=100&page={page}")
        try:
            resp = urllib.request.urlopen(url, timeout=15)
            data = json.loads(resp.read().decode())
        except Exception as e:
            print(f"    ERR page {page}: {e}")
            break
        batch = data.get("data", [])
        if not batch:
            break
        all_rows.extend(batch)
        if page % 10 == 0:
            oldest = min(r["funding_time"] for r in batch)
            print(f"    page {page}: {len(all_rows)} samples, oldest "
                  f"{datetime.fromtimestamp(oldest/1000, tz=timezone.utc).strftime('%Y-%m-%d')}", flush=True)
        if not data.get("pagination", {}).get("has_next"):
            break
        page += 1
        time.sleep(0.12)
    by_day = {}
    for r in all_rows:
        date = datetime.fromtimestamp(r["funding_time"] / 1000, tz=timezone.utc).date().isoformat()
        rate_pct = float(r["actual_funding_rate"]) * 100
        by_day.setdefault(date, []).append(rate_pct)
    daily = {d: sum(v) / len(v) for d, v in by_day.items()}
    if daily:
        print(f"  {len(daily)} dias ({min(daily)} -> {max(daily)}, {len(all_rows)} samples)")
    return daily


def fetch_binance_funding_full(symbol: str = "BTCUSDT") -> Dict[str, float]:
    """Fetch funding rate completo Binance via paginacao forward."""
    print("  Fetching Binance funding (full history, forward pagination)...", flush=True)
    all_rows = []
    end_ms = int(datetime.now(tz=timezone.utc).timestamp() * 1000)
    cursor = int(datetime(2019, 9, 1, tzinfo=timezone.utc).timestamp() * 1000)
    page = 0
    while cursor < end_ms:
        url = (f"https://fapi.binance.com/fapi/v1/fundingRate?symbol={symbol}"
               f"&limit=1000&startTime={cursor}")
        try:
            resp = urllib.request.urlopen(url, timeout=15)
            batch = json.loads(resp.read().decode())
        except Exception as e:
            print(f"    ERR {e}")
            break
        if not batch:
            break
        all_rows.extend(batch)
        newest = max(r["fundingTime"] for r in batch)
        page += 1
        if page % 5 == 0:
            print(f"    page {page}: {len(all_rows)} samples, newest "
                  f"{datetime.fromtimestamp(newest/1000, tz=timezone.utc).strftime('%Y-%m-%d')}", flush=True)
        if newest <= cursor:  # no forward progress
            break
        cursor = newest + 1
        time.sleep(0.15)
    by_day = {}
    for r in all_rows:
        date = datetime.fromtimestamp(r["fundingTime"] / 1000, tz=timezone.utc).date().isoformat()
        rate_pct = float(r["fundingRate"]) * 100
        by_day.setdefault(date, []).append(rate_pct)
    daily = {d: sum(v) / len(v) for d, v in by_day.items()}
    print(f"  {len(daily)} dias ({min(daily)} -> {max(daily)}, {len(all_rows)} samples)")
    return daily


def future_extremes(daily_btc: Dict[str, float], target_date: str, days: int = 10):
    """Retorna (max_pct, min_pct, max_drawdown_pct) nos proximos N dias."""
    if target_date not in daily_btc:
        return None
    base = daily_btc[target_date]
    target_dt = datetime.fromisoformat(target_date).date()
    fut = []
    for d in range(1, days + 1):
        future_date = (target_dt + timedelta(days=d)).isoformat()
        if future_date in daily_btc:
            fut.append(daily_btc[future_date])
    if not fut:
        return None
    return {
        "max_pct":  ((max(fut) - base) / base) * 100,
        "min_pct":  ((min(fut) - base) / base) * 100,
        "end_pct":  ((fut[-1] - base) / base) * 100,
    }


def main():
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    daily = db.get_candles(MARKET, PERIOD_1D, "2019-01-01", "2026-12-31")
    daily_btc = {c["ts"][:10]: float(c["close"]) for c in daily}
    print(f"  BTC candles: {len(daily_btc)} ({min(daily_btc)} -> {max(daily_btc)})")

    # CoinEx primario (fonte preferida); Binance fallback
    import sys as _sys
    source = "coinex" if "--binance" not in _sys.argv else "binance"
    funding = fetch_coinex_funding_full() if source == "coinex" else fetch_binance_funding_full()
    print(f"  [fonte: {source}]")

    print("\n  Scanning funding_peak signals...")
    triggers = scan_signals(funding, hot_threshold=0.05, drop_pct=0.30,
                            lookback_days=14, min_gap_days=14)
    print(f"  {len(triggers)} triggers detectados\n")

    if not triggers:
        print("  Nenhum trigger. Tente reduzir hot_threshold.")
        return

    sep = "=" * 100
    print(sep)
    print("  TRIGGERS de SHORT (funding peak + drop 30%) — outcome 10 dias")
    print(sep)
    print(f"  {'date':<12} {'peak%':>7} {'curr%':>7} {'drop':>5} {'BTC$':>10} "
          f"{'max+%':>7} {'min+%':>7} {'end+%':>7}  outcome")
    print("-" * 100)
    wins = losses = 0
    pnl_R_sum = 0.0
    short_target_R = 3.0
    short_stop_R = 1.0
    for t in triggers:
        fut = future_extremes(daily_btc, t["date"], days=10)
        if fut is None:
            continue
        # Simula short: stop loss em max_pct (BTC subiu), target em min_pct (BTC caiu)
        # Stop ATR 1.5 ~= 5% acima | Target -15% (RR 1:3)
        if fut["max_pct"] >= 5:
            outcome = "STOP"; pnl_R = -short_stop_R; losses += 1
        elif fut["min_pct"] <= -15:
            outcome = "TARGET"; pnl_R = +short_target_R; wins += 1
        else:
            # close em 10d
            pnl_R = -fut["end_pct"] / 5  # rough scaling
            outcome = "TIMEOUT"
            if pnl_R > 0: wins += 1
            else: losses += 1
        pnl_R_sum += pnl_R
        btc_price = daily_btc.get(t["date"], 0)
        print(f"  {t['date']:<12} {t['peak_value']:>6.3f}% {t['current_value']:>6.3f}% "
              f"{t['drop_pct_actual']*100:>4.0f}% ${btc_price:>8,.0f} "
              f"{fut['max_pct']:>+6.2f}% {fut['min_pct']:>+6.2f}% {fut['end_pct']:>+6.2f}%  {outcome} ({pnl_R:+.2f}R)")
    print(sep)
    total = wins + losses
    if total:
        win_rate = wins / total * 100
        exp = pnl_R_sum / total
        print(f"  RESULTADO: {total} trades, win {win_rate:.1f}%, exp {exp:+.3f}R")
        if exp > 0.3:
            print("  -> EDGE REAL em funding peak signals. Considerar producao.")
        elif exp > 0:
            print("  -> EDGE FRACA. Refinar parametros antes de producao.")
        else:
            print("  -> SEM EDGE. Sinal nao se sustenta historicamente.")
    print(sep)


if __name__ == "__main__":
    main()
