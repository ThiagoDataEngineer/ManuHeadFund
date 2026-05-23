"""Coleta candles INJUSDT + TIAUSDT pra cross_asset_matrix."""
import json, sys, time
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "journal" / "candles_coinex"

def fetch(url, timeout=15):
    with urlopen(Request(url, headers={"User-Agent":"c/1"}), timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))

for market in ["INJUSDT","TIAUSDT"]:
    print(f"=== {market} ===")
    all_candles = []
    end_ts = None
    for page in range(5):  # 5 pages × 1000 = 5000 candles max
        url = f"https://api.coinex.com/v2/spot/kline?market={market}&period=1day&limit=1000"
        if end_ts: url += f"&end_time={end_ts}"
        try:
            d = fetch(url)
            data = d.get("data") or []
            if not data: break
            for k in data:
                all_candles.append({
                    "ts": k.get("created_at"),
                    "open": float(k["open"]), "high": float(k["high"]),
                    "low": float(k["low"]), "close": float(k["close"]),
                    "volume": float(k.get("volume", 0)),
                })
            print(f"  page {page+1}: +{len(data)} (total {len(all_candles)})")
            if len(data) < 1000: break
            end_ts = data[0].get("created_at")
            time.sleep(0.5)
        except Exception as e:
            print(f"  err: {e}"); break
    # Dedup + sort ASC by ts
    seen = set(); dedup = []
    for c in all_candles:
        if c["ts"] not in seen:
            seen.add(c["ts"]); dedup.append(c)
    dedup.sort(key=lambda x: x["ts"])
    # Convert ts to ISO
    import datetime
    for c in dedup:
        c["ts"] = datetime.datetime.fromtimestamp(int(c["ts"])/1000, tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")
    out_path = OUT / f"{market}_1day.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(dedup, f, ensure_ascii=False)
    print(f"  saved {len(dedup)} candles -> {out_path.name}")
