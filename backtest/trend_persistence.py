"""
trend_persistence.py -- Hurst-proxy + Kaufman Efficiency Ratio para detectar
trends persistentes (alvo: entry boost em mercados trend-following genuinos).

Two metrics:
  1. Hurst exponent (rescaled range R/S analysis) — 0.5 = random walk;
     >0.6 = persistent trend; <0.4 = mean-reverting
  2. Kaufman Efficiency Ratio (KER) = |net price change| / sum(|daily changes|)
     1.0 = perfectly trending; 0.0 = pure noise. >0.3 = useful trend.

Combinados: alto KER + alto Hurst = trend genuino (entry boost).
Baixo KER + Hurst ~0.5 = ruido (NO boost).

Usage:
    python trend_persistence.py BTCUSDT
    python trend_persistence.py --markets BTC,ETH,INJ
"""
from __future__ import annotations
import argparse, json, math, os, sys
from pathlib import Path
from typing import List, Optional

ROOT = Path(__file__).resolve().parent.parent
CANDLES = ROOT / "journal" / "candles_coinex"


def load_closes(market: str) -> List[float]:
    f = CANDLES / f"{market}_1day.json"
    if not f.exists(): return []
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
        if isinstance(data, dict) and "candles" in data: data = data["candles"]
        return [float(c["close"]) for c in data if isinstance(c, dict) and c.get("close")]
    except: return []


def hurst_rs(returns: List[float], min_window: int = 8) -> Optional[float]:
    """Rescaled Range analysis. Returns Hurst exponent estimate (0..1)."""
    n = len(returns)
    if n < min_window * 4: return None
    log_n = []
    log_rs = []
    for w in (8, 16, 32, 64):
        if n < w: break
        # Slice em chunks de tamanho w; compute R/S per chunk; medio
        rs_list = []
        n_chunks = n // w
        for i in range(n_chunks):
            chunk = returns[i*w:(i+1)*w]
            mean_c = sum(chunk) / w
            dev = [r - mean_c for r in chunk]
            cum = []
            s = 0
            for d in dev:
                s += d
                cum.append(s)
            R = max(cum) - min(cum)
            var = sum(d*d for d in dev) / w
            S = math.sqrt(var) if var > 0 else 0
            if S > 0:
                rs_list.append(R / S)
        if rs_list:
            mean_rs = sum(rs_list) / len(rs_list)
            if mean_rs > 0:
                log_n.append(math.log(w))
                log_rs.append(math.log(mean_rs))
    if len(log_n) < 2: return None
    # Linear regression log(R/S) = H * log(n) + c
    n_pts = len(log_n)
    mean_x = sum(log_n) / n_pts
    mean_y = sum(log_rs) / n_pts
    num = sum((log_n[i] - mean_x) * (log_rs[i] - mean_y) for i in range(n_pts))
    den = sum((log_n[i] - mean_x) ** 2 for i in range(n_pts))
    if den == 0: return None
    return num / den


def kaufman_efficiency(closes: List[float], window: int = 20) -> Optional[float]:
    """KER = |net change| / sum(|daily change|) nas ultimas N closes."""
    if len(closes) < window + 1: return None
    sub = closes[-(window+1):]
    net = abs(sub[-1] - sub[0])
    total = sum(abs(sub[i] - sub[i-1]) for i in range(1, len(sub)))
    if total == 0: return None
    return net / total


def trend_persistence_score(market: str) -> dict:
    closes = load_closes(market)
    if len(closes) < 64:
        return {"market": market, "error": "insufficient_history", "score": None}
    returns = [(closes[i]-closes[i-1])/closes[i-1] for i in range(1,len(closes)) if closes[i-1]>0]
    H = hurst_rs(returns)
    KER20 = kaufman_efficiency(closes, 20)
    KER60 = kaufman_efficiency(closes, 60)
    # Composite score: weighted avg, normalize Hurst (0.5=neutral->0; 1.0->1; 0->-1)
    h_norm = (H - 0.5) * 2 if H is not None else 0
    ker_score = KER20 if KER20 is not None else 0
    # Combined: 50% Hurst-norm (-1 to 1), 50% KER (0 to 1)
    score = (h_norm * 0.5) + (ker_score * 0.5)
    # Interpretation
    if score >= 0.5:    label = "STRONG_TREND"
    elif score >= 0.25: label = "MODERATE_TREND"
    elif score >= 0.0:  label = "WEAK_TREND"
    elif score >= -0.25:label = "NOISE"
    else:               label = "MEAN_REVERTING"
    return {
        "market": market,
        "hurst": round(H, 3) if H is not None else None,
        "ker_20d": round(KER20, 3) if KER20 is not None else None,
        "ker_60d": round(KER60, 3) if KER60 is not None else None,
        "score": round(score, 3),
        "label": label,
    }


def build_cache(markets=None, out_path=None):
    """Compute trend persistence for all (or specified) markets + save to JSON cache."""
    if markets is None:
        markets = sorted({f.stem.replace("_1day","") for f in CANDLES.glob("*_1day.json")
                          if "summary" not in f.stem.lower()})
    cache = {}
    for m in markets:
        r = trend_persistence_score(m)
        if "error" not in r:
            cache[m] = {
                "label": r["label"],
                "score": r["score"],
                "hurst": r["hurst"],
                "ker_20d": r["ker_20d"],
                "ker_60d": r["ker_60d"],
            }
    out = out_path or str(ROOT / "journal" / "trend_persistence_cache.json")
    from datetime import datetime, timezone
    payload = {
        "computed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "window_days": 60,
        **cache,
    }
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    Path(out).write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return out, len(cache)


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument("market", nargs="?")
    p.add_argument("--markets", help="comma-separated")
    p.add_argument("--json", action="store_true")
    p.add_argument("--build-cache", action="store_true", help="Build cache JSON for all candles markets")
    args = p.parse_args(argv)

    if args.build_cache:
        markets = None
        if args.markets:
            markets = [m.strip().upper() for m in args.markets.split(",") if m.strip()]
        out, n = build_cache(markets)
        print(f"[trend_cache] {n} markets -> {out}")
        return 0

    if args.markets:
        mkts = [m.strip().upper() for m in args.markets.split(",") if m.strip()]
    elif args.market:
        mkts = [args.market.upper()]
    else:
        p.error("Forneca market, --markets, ou --build-cache"); return 2
    results = [trend_persistence_score(m) for m in mkts]
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print(f'{"Market":<14} {"Hurst":>7} {"KER20":>7} {"KER60":>7} {"Score":>7} {"Label"}')
        for r in results:
            if "error" in r:
                print(f'{r["market"]:<14} ERROR: {r["error"]}'); continue
            h = f'{r["hurst"]:.3f}' if r["hurst"] is not None else '-'
            k20 = f'{r["ker_20d"]:.3f}' if r["ker_20d"] is not None else '-'
            k60 = f'{r["ker_60d"]:.3f}' if r["ker_60d"] is not None else '-'
            print(f'{r["market"]:<14} {h:>7} {k20:>7} {k60:>7} {r["score"]:>7.3f} {r["label"]}')
    return 0


if __name__ == "__main__":
    sys.exit(main())
