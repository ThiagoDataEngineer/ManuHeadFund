"""fetch_candles_4h.py -- Fetch CoinEx 4h candles para histórico phase_1_bull.

Phase_1_bull: 2024-04-19 (halving) + 12 meses = ate 2025-04-19.

CoinEx /v2/futures/kline limit=1000 = ~166 dias 4h. Pra 12 meses precisa pagina endTime.
Endpoint pagina por end_time (mais antigo); precisa loop until cobrir periodo.

Output: journal/candles_coinex/{MARKET}_4hour.json  (merged + dedup ts)

Markets: usa per_asset_whitelist atual (Tier A + B = ~11) + extras com candles 1day já existentes.
Idempotente: se ja tem 4h cache, append + dedup; senao cria.
"""
from __future__ import annotations
import json, time, sys, urllib.request, urllib.error
from datetime import datetime, timezone, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CANDLES_DIR = ROOT / "journal" / "candles_coinex"
COINEX_BASE = "https://api.coinex.com/v2"

# Phase_1_bull range
HALVING_2024 = datetime(2024, 4, 19, tzinfo=timezone.utc)
PHASE1_END   = HALVING_2024 + timedelta(days=365)   # 2025-04-19 (mes 12)

PERIOD = "4hour"
LIMIT = 1000
SLEEP_BETWEEN_CALLS = 0.3   # ~3 req/s gentle


def fetch_page(market: str, end_ts_ms: int, market_type: str = "futures") -> list:
    """Fetch ate end_ts_ms; retorna list candles em ordem temporal ASC."""
    url = f"{COINEX_BASE}/{market_type}/kline?market={market}&period={PERIOD}&limit={LIMIT}"
    req = urllib.request.Request(url, headers={"User-Agent": "coinex-ai-fetch/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 429:
            print(f"  [{market}] rate limit, sleep 10s", flush=True)
            time.sleep(10)
            return fetch_page(market, end_ts_ms, market_type)
        return []
    except Exception:
        return []
    if data.get("code") != 0 or not data.get("data"):
        return []
    candles = []
    for c in data["data"]:
        try:
            candles.append({
                "ts": c.get("created_at"),  # ms epoch ou ISO string per CoinEx version
                "open":  float(c["open"]),
                "high":  float(c["high"]),
                "low":   float(c["low"]),
                "close": float(c["close"]),
                "volume": float(c.get("volume", 0)),
            })
        except (KeyError, ValueError, TypeError):
            continue
    return candles


def normalize_ts(ts_value) -> int:
    """Retorna ms epoch (CoinEx pode retornar ms ou ISO)."""
    if isinstance(ts_value, (int, float)):
        # Se valor < 1e12, eh segundos; senao ms
        if ts_value < 1e12:
            return int(ts_value * 1000)
        return int(ts_value)
    if isinstance(ts_value, str):
        try:
            dt = datetime.fromisoformat(ts_value.replace("Z", "+00:00"))
            return int(dt.timestamp() * 1000)
        except ValueError:
            return 0
    return 0


def fetch_market_history(market: str, start_dt: datetime, end_dt: datetime) -> list:
    """Pagina backward de end_dt ate start_dt. Retorna list ASC sem duplicados."""
    all_candles = {}   # ts_ms -> candle
    cursor_ms = int(end_dt.timestamp() * 1000)
    start_ms  = int(start_dt.timestamp() * 1000)
    pages = 0
    while cursor_ms > start_ms and pages < 20:
        # Tenta futures primeiro, fallback spot
        candles = fetch_page(market, cursor_ms, "futures")
        if not candles:
            candles = fetch_page(market, cursor_ms, "spot")
        if not candles:
            break
        # Normalize ts
        for c in candles:
            ms = normalize_ts(c["ts"])
            if ms <= 0: continue
            all_candles[ms] = c
        # Find oldest candle ms in this page pra cursor
        oldest_ms = min(normalize_ts(c["ts"]) for c in candles if normalize_ts(c["ts"]) > 0)
        if oldest_ms >= cursor_ms:
            break   # nao avancou
        cursor_ms = oldest_ms - 1
        pages += 1
        time.sleep(SLEEP_BETWEEN_CALLS)
    # Filter por range + sort ASC
    out = [(ts, c) for ts, c in all_candles.items() if start_ms <= ts <= int(end_dt.timestamp() * 1000)]
    out.sort(key=lambda x: x[0])
    return [c for _, c in out]


def load_existing_4h(market: str):
    p = CANDLES_DIR / f"{market}_4hour.json"
    if not p.exists(): return []
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return []


def save_merged(market: str, candles: list):
    p = CANDLES_DIR / f"{market}_4hour.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(candles, indent=None, separators=(",", ":")), encoding="utf-8")


def main():
    # Decide markets: lista do Tier A + B + alguns 1day cache extras
    markets = []
    wl_files = sorted((ROOT / "journal").glob("per_asset_whitelist_*.json"), reverse=True)
    if wl_files:
        try:
            wl = json.loads(wl_files[0].read_text(encoding="utf-8"))
            markets.extend([e["market"] for e in wl.get("TIER_A_LIVE", []) if e.get("market")])
            markets.extend([e["market"] for e in wl.get("TIER_B_PAPER", []) if e.get("market")])
        except Exception: pass
    # + markets com candles 1day existentes (cobre alts)
    for f in CANDLES_DIR.glob("*_1day.json"):
        m = f.stem.replace("_1day", "")
        if m not in markets: markets.append(m)
    markets = sorted(set(markets))

    print(f"=== Fetch 4h phase_1_bull ({HALVING_2024.date()} -> {PHASE1_END.date()}) ===")
    print(f"Markets to fetch: {len(markets)}")

    ok = 0; fail = 0
    for i, m in enumerate(markets):
        print(f"[{i+1}/{len(markets)}] {m}...", end=" ", flush=True)
        try:
            candles = fetch_market_history(m, HALVING_2024, PHASE1_END)
            if not candles:
                print("0 candles", flush=True); fail += 1; continue
            # Merge com existente (se houver)
            existing = load_existing_4h(m)
            by_ts = {normalize_ts(c["ts"]): c for c in existing if normalize_ts(c["ts"]) > 0}
            for c in candles:
                by_ts[normalize_ts(c["ts"])] = c
            merged = sorted(by_ts.values(), key=lambda c: normalize_ts(c["ts"]))
            save_merged(m, merged)
            print(f"OK ({len(candles)} new, {len(merged)} total)", flush=True)
            ok += 1
        except Exception as e:
            print(f"FAIL {e}", flush=True); fail += 1
        time.sleep(SLEEP_BETWEEN_CALLS)

    print(f"\nDone: {ok} ok / {fail} fail")
    return 0


if __name__ == "__main__":
    sys.exit(main())
