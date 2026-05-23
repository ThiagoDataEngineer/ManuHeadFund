"""
build_beta_cache.py -- Computa beta vs BTCUSDT pra todos markets com candles cached.

beta = cov(Y, X) / var(X) em returns diarios. Window default 180d (estavel sem
ser demasiado lagged).

Output: journal/beta_vs_btc.json
{
  "computed_at": "...",
  "window_days": 180,
  "base": "BTCUSDT",
  "beta": {"INJUSDT": 1.21, "ZECUSDT": 1.57, ...},
  "n_obs": {"INJUSDT": 180, ...}
}

Consumido por Test-BetaConcentration em lib_promotion_gates.ps1.

CLI:
    python build_beta_cache.py                          # auto: top markets cached
    python build_beta_cache.py --window 90              # janela menor (reage mais rapido)
    python build_beta_cache.py --markets INJ,ZEC,...    # explicit
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional

ROOT = Path(__file__).resolve().parent.parent
CANDLES_DIR = ROOT / "journal" / "candles_coinex"
OUTPUT_FILE = ROOT / "journal" / "beta_vs_btc.json"

sys.path.insert(0, str(ROOT / "backtest"))
from correlation_matrix import load_closes  # noqa: E402  # legacy import (mantido)


def load_closes_with_dates(market: str, candles_dir: Path = CANDLES_DIR):
    """Retorna [(date_str_YYYYMMDD, close_float), ...] em ordem temporal.

    FASE 3 fix 2026-05-21: build_beta_cache antes alinhava por INDEX, mas candles
    de diferentes markets podem terminar em datas diferentes (BTC last 2026-05-19,
    HYPE last 2026-05-18 -> shift 1d -> beta vira ruido aleatorio, signs flip).
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
        # Normalize date
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


def date_aligned_returns(market_series, btc_series):
    """Alinha duas series (date, close) por data comum, depois computa returns
    diarios CONSECUTIVOS (drops gaps).

    Returns: (returns_market, returns_btc) com mesmo len, mesma data.
    """
    btc_by_date = {d: c for d, c in btc_series}
    pairs = [(d, c, btc_by_date[d]) for d, c in market_series if d in btc_by_date]
    pairs.sort(key=lambda x: x[0])
    if len(pairs) < 2:
        return [], []
    ret_m, ret_b = [], []
    for i in range(1, len(pairs)):
        d_prev = pairs[i-1][0]
        d_cur = pairs[i][0]
        # Drop se gap > 1 dia (feriado, candle perdido) -> evita return acumulado em janela larga
        from datetime import datetime as _dt
        try:
            gap = (_dt.strptime(d_cur, "%Y-%m-%d") - _dt.strptime(d_prev, "%Y-%m-%d")).days
        except Exception:
            gap = 1
        if gap != 1:
            continue
        m_prev, m_cur = pairs[i-1][1], pairs[i][1]
        b_prev, b_cur = pairs[i-1][2], pairs[i][2]
        if m_prev <= 0 or b_prev <= 0:
            continue
        ret_m.append((m_cur - m_prev) / m_prev)
        ret_b.append((b_cur - b_prev) / b_prev)
    return ret_m, ret_b


def daily_returns(closes):
    """Legacy. Mantido pra TDD existentes; build() usa date_aligned_returns."""
    return [(closes[i] - closes[i-1]) / closes[i-1] for i in range(1, len(closes)) if closes[i-1] > 0]


def compute_beta(returns_y, returns_x):
    if len(returns_y) != len(returns_x) or len(returns_x) < 10:
        return None
    n = len(returns_x)
    mean_x = sum(returns_x) / n
    mean_y = sum(returns_y) / n
    cov = sum((returns_x[i] - mean_x) * (returns_y[i] - mean_y) for i in range(n)) / n
    var_x = sum((x - mean_x) ** 2 for x in returns_x) / n
    if var_x == 0:
        return None
    return cov / var_x


def build(markets: List[str], window: int = 180, base: str = "BTCUSDT") -> dict:
    btc_series = load_closes_with_dates(base)
    if not btc_series:
        raise RuntimeError(f"Sem candles para {base}")

    betas = {}
    n_obs = {}
    skipped = []
    for m in markets:
        if m == base:
            betas[m] = 1.0
            n_obs[m] = window
            continue
        m_series = load_closes_with_dates(m)
        if not m_series:
            skipped.append({"market": m, "reason": "no_candles"})
            continue
        # FASE 3 fix: alinhar por DATA, nao por index.
        ret_m, ret_b = date_aligned_returns(m_series, btc_series)
        n = min(len(ret_m), window)
        if n < 30:
            skipped.append({"market": m, "reason": f"only_{n}_aligned_returns"})
            continue
        y = ret_m[-n:]
        x = ret_b[-n:]
        beta = compute_beta(y, x)
        if beta is None:
            skipped.append({"market": m, "reason": "compute_failed"})
            continue
        betas[m] = round(beta, 4)
        n_obs[m] = n

    return {
        "computed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "window_days": window,
        "base": base,
        "beta": betas,
        "n_obs": n_obs,
        "skipped": skipped,
    }


def discover_markets() -> List[str]:
    """Markets com candles cached (todos do journal/candles_coinex)."""
    out = []
    for f in CANDLES_DIR.glob("*_1day.json"):
        name = f.stem.replace("_1day", "")
        out.append(name)
    return sorted(set(out))


def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(description="Build beta cache vs BTCUSDT.")
    p.add_argument("--markets", help="comma-separated (default: auto-discover candles cached)")
    p.add_argument("--window", type=int, default=180)
    p.add_argument("--base", default="BTCUSDT")
    p.add_argument("--out", default=str(OUTPUT_FILE))
    args = p.parse_args(argv)

    if args.markets:
        markets = [m.strip().upper() for m in args.markets.split(",") if m.strip()]
    else:
        markets = discover_markets()

    result = build(markets, args.window, args.base)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"[beta_cache] {len(result['beta'])} markets, window={args.window}d base={args.base} -> {out}")
    # Highlight amplifiers
    amps = sorted([(m, b) for m, b in result['beta'].items() if abs(b) >= 1.2], key=lambda x: -abs(x[1]))
    if amps:
        print(f"\nBTC-amplifiers (|beta|>=1.2):")
        for m, b in amps[:15]:
            tag = "AMP+" if b > 0 else "AMP-"
            print(f"  {tag} {m:<14} beta={b:+.3f}")
    if result['skipped']:
        print(f"\nSkipped ({len(result['skipped'])}):", [s['market'] for s in result['skipped'][:5]])
    return 0


if __name__ == "__main__":
    sys.exit(main())
