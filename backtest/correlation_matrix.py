"""
correlation_matrix.py -- Compute 30d returns correlation matrix offline.

Le candles ja coletados em journal/candles_coinex/<MARKET>_1day.json
(schema: lista de candles com 'close' key) e produz matriz de Pearson correlation
entre returns diarios.

Output: journal/correlation_matrix.json
{
  "computed_at": "2026-05-19T...",
  "window_days": 30,
  "markets": ["BTCUSDT","ETHUSDT",...],
  "matrix": {"BTCUSDT": {"ETHUSDT": 0.83, ...}, ...}
}

Substitui o proxy 'mesmo setor' usado por Test-CrossAssetCorrelation no PS.
PS gate consome este JSON; fallback ao sector_map quando matriz ausente.

CLI:
    python correlation_matrix.py                              # auto: top Tier A/B
    python correlation_matrix.py --markets BTC,ETH,INJ        # explicito
    python correlation_matrix.py --window 60                  # baseline 60d
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional

ROOT = Path(__file__).resolve().parent.parent
CANDLES_DIR = ROOT / "journal" / "candles_coinex"
OUTPUT_FILE = ROOT / "journal" / "correlation_matrix.json"
DEFAULT_WINDOW = 30


def load_closes(market: str, candles_dir: Path = CANDLES_DIR) -> List[float]:
    f = candles_dir / f"{market}_1day.json"
    if not f.exists():
        return []
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
    except Exception:
        return []
    # data eh lista de candles; tenta 'close' (string ou float)
    if isinstance(data, dict) and "candles" in data:
        data = data["candles"]
    closes = []
    for c in data:
        if isinstance(c, dict):
            v = c.get("close")
        elif isinstance(c, (list, tuple)) and len(c) >= 5:
            v = c[4]  # OHLCV: assume close em idx 4
        else:
            v = None
        if v is None:
            continue
        try:
            closes.append(float(v))
        except Exception:
            continue
    return closes


def daily_returns(closes: List[float], window: int) -> List[float]:
    """Legacy. Mantido para compat. Para correlacao alinhada por data, usar
    daily_returns_with_dates + date_aligned_pearson."""
    if len(closes) < window + 1:
        return []
    tail = closes[-(window + 1):]
    return [(tail[i] - tail[i - 1]) / tail[i - 1] for i in range(1, len(tail)) if tail[i - 1] > 0]


def load_closes_with_dates(market: str, candles_dir: Path = CANDLES_DIR):
    """Retorna [(date_str, close_float), ...] em ordem temporal.

    FASE 3+ fix 2026-05-21: necessario para correlation alinhada por DATA.
    Bug paralelo a build_beta_cache: align por INDEX gera shift quando candles
    de markets terminam em datas diferentes (BTC 2026-05-19 vs ETH 2026-05-18).
    """
    f = candles_dir / f"{market}_1day.json"
    if not f.exists():
        return []
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
    except Exception:
        return []
    if isinstance(data, dict) and "candles" in data:
        data = data["candles"]
    out = []
    for c in data:
        if not isinstance(c, dict):
            continue
        ts = c.get("ts") or c.get("timestamp") or c.get("time")
        close = c.get("close")
        if ts is None or close is None:
            continue
        if isinstance(ts, (int, float)):
            from datetime import datetime as _dt
            dt = _dt.fromtimestamp(ts / 1000 if ts > 1e12 else ts)
            date = dt.strftime("%Y-%m-%d")
        else:
            date = str(ts)[:10]
        try:
            out.append((date, float(close)))
        except Exception:
            continue
    return out


def daily_returns_with_dates(market: str, window: int, candles_dir: Path = CANDLES_DIR):
    """Retorna {date_str: return_float} para os ultimos `window` dias com gap=1d.

    Cada return eh para a data D (close_D / close_{D-1} - 1), so se gap exato 1 dia.
    """
    series = load_closes_with_dates(market, candles_dir)
    if len(series) < 2:
        return {}
    series.sort(key=lambda x: x[0])
    from datetime import datetime as _dt
    rets = {}
    for i in range(1, len(series)):
        d_prev, p_prev = series[i-1]
        d_cur,  p_cur  = series[i]
        try:
            gap = (_dt.strptime(d_cur, "%Y-%m-%d") - _dt.strptime(d_prev, "%Y-%m-%d")).days
        except Exception:
            continue
        if gap != 1 or p_prev <= 0:
            continue
        rets[d_cur] = (p_cur - p_prev) / p_prev
    # Keep last `window` dates only (by key sorted)
    if len(rets) > window:
        last_dates = sorted(rets.keys())[-window:]
        rets = {d: rets[d] for d in last_dates}
    return rets


def date_aligned_pearson(rets_a: dict, rets_b: dict) -> Optional[float]:
    """Calcula pearson em datas comuns. None se < 5 pares."""
    common = sorted(set(rets_a.keys()) & set(rets_b.keys()))
    if len(common) < 5:
        return None
    a = [rets_a[d] for d in common]
    b = [rets_b[d] for d in common]
    return pearson(a, b)


def pearson(a: List[float], b: List[float]) -> Optional[float]:
    if len(a) != len(b) or len(a) < 5:
        return None
    n = len(a)
    mean_a = sum(a) / n
    mean_b = sum(b) / n
    num = sum((a[i] - mean_a) * (b[i] - mean_b) for i in range(n))
    var_a = sum((x - mean_a) ** 2 for x in a)
    var_b = sum((x - mean_b) ** 2 for x in b)
    denom = math.sqrt(var_a * var_b)
    if denom == 0:
        return None
    return num / denom


def build_matrix(markets: List[str], window: int = DEFAULT_WINDOW,
                 candles_dir: Path = CANDLES_DIR) -> dict:
    # FASE 3+ fix 2026-05-21: align por DATA, nao por INDEX. Anti-spurious-correlation
    # gerada quando candles de markets terminam em datas diferentes.
    returns = {}
    for m in markets:
        r = daily_returns_with_dates(m, window, candles_dir)
        if r:
            returns[m] = r
    used_markets = list(returns.keys())
    skipped = [m for m in markets if m not in returns]
    matrix = {}
    for a in used_markets:
        matrix[a] = {}
        for b in used_markets:
            if a == b:
                matrix[a][b] = 1.0
            else:
                c = date_aligned_pearson(returns[a], returns[b])
                matrix[a][b] = None if c is None else round(c, 4)
    return {
        "computed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "window_days": window,
        "markets": used_markets,
        "skipped": skipped,
        "matrix": matrix,
    }


def discover_default_markets() -> List[str]:
    """Tenta ler per_asset_whitelist mais recente; cai pros Tier A LIVE conhecidos."""
    journal = ROOT / "journal"
    wl_files = sorted(journal.glob("per_asset_whitelist_*.json"),
                      key=lambda p: p.stat().st_mtime, reverse=True)
    if wl_files:
        try:
            data = json.loads(wl_files[0].read_text(encoding="utf-8"))
            tier_a = [e["market"] for e in data.get("TIER_A_LIVE", []) if e.get("market")]
            tier_b = [e["market"] for e in data.get("TIER_B_PAPER", []) if e.get("market")]
            return sorted(set(tier_a + tier_b))
        except Exception:
            pass
    # Fallback hardcoded
    return ["BTCUSDT", "ETHUSDT", "INJUSDT", "RENDERUSDT", "CFGUSDT",
            "ZECUSDT", "PENDLEUSDT", "SOLUSDT"]


def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(description="Build offline correlation matrix.")
    p.add_argument("--markets", help="Lista comma-separated (default: per_asset_whitelist)")
    p.add_argument("--window", type=int, default=DEFAULT_WINDOW)
    p.add_argument("--candles-dir", default=str(CANDLES_DIR))
    p.add_argument("--out", default=str(OUTPUT_FILE))
    args = p.parse_args(argv)

    if args.markets:
        markets = [m.strip().upper() for m in args.markets.split(",") if m.strip()]
    else:
        markets = discover_default_markets()

    result = build_matrix(markets, args.window, Path(args.candles_dir))
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"[correlation_matrix] {len(result['markets'])} markets, window={args.window}d -> {out}")
    if result["skipped"]:
        print(f"[correlation_matrix] skipped (sem candles): {result['skipped']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
