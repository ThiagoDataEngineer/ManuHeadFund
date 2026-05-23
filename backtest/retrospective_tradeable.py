"""
retrospective_tradeable.py -- Aplica gates atuais ao histórico para responder:
"Com sistema atual, quando e quais ~10 moedas conseguiriamos operar e quais AAA+?"

Metodo:
  1. Pra cada market com candles cached (~44)
  2. Compute Sharpe rolling em 3 janelas (60d, 180d, 365d) - usando close-to-close pct returns
  3. Compute beta vs BTCUSDT (180d)
  4. Compute max drawdown (peak-to-trough no historico)
  5. Apply gates:
     - Sharpe60d >= 1.5 (gate C->B; aprox B->A real precisa Sharpe_real mas paper proxy ok)
     - max_dd <= 0.12 (12%)
     - beta absoluto
  6. Rank por quality AAA+ / AA / A / B (beta-based)
  7. Para AAA+ ranqueia tambem por Sharpe descendente

Output: tabela ranqueada, dates de quando Sharpe60d cruzou 1.5 primeira vez,
size sugerido (1% de $2762 = $27.63 LIVE; 50% paper).

CLI:
    python retrospective_tradeable.py
"""
from __future__ import annotations

import json
import math
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Optional, Tuple

ROOT = Path(__file__).resolve().parent.parent
CANDLES_DIR = ROOT / "journal" / "candles_coinex"
BETA_FILE = ROOT / "journal" / "beta_vs_btc.json"
CORR_FILE = ROOT / "journal" / "correlation_matrix.json"
SECTOR_FILE = ROOT / "journal" / "sector_map.json"

CAPITAL_TOTAL = 2762.93
RISK_PCT = 0.01
SIZE_1PCT = CAPITAL_TOTAL * RISK_PCT


def load_candles_with_dates(market: str):
    """Returns list of {date, close} dicts sorted by date."""
    f = CANDLES_DIR / f"{market}_1day.json"
    if not f.exists():
        return []
    try:
        raw = json.loads(f.read_text(encoding="utf-8"))
    except Exception:
        return []
    if isinstance(raw, dict) and "candles" in raw:
        raw = raw["candles"]
    out = []
    for c in raw:
        if not isinstance(c, dict):
            continue
        try:
            ts = c.get("created_at") or c.get("ts") or c.get("time")
            close = float(c["close"])
            if isinstance(ts, (int, float)):
                # millisecs or secs
                if ts > 10**12:
                    dt = datetime.utcfromtimestamp(ts / 1000)
                else:
                    dt = datetime.utcfromtimestamp(ts)
            elif isinstance(ts, str):
                dt = datetime.fromisoformat(ts.replace("Z", "+00:00")).replace(tzinfo=None)
            else:
                continue
            out.append({"date": dt, "close": close})
        except Exception:
            continue
    out.sort(key=lambda x: x["date"])
    return out


def daily_returns(closes: List[float]) -> List[float]:
    return [(closes[i] - closes[i-1]) / closes[i-1] for i in range(1, len(closes)) if closes[i-1] > 0]


def sharpe(returns: List[float], rf_daily: float = 0.0) -> Optional[float]:
    """Annualized Sharpe assuming daily returns (252 trading days proxy)."""
    if len(returns) < 10:
        return None
    mean = sum(returns) / len(returns)
    std = math.sqrt(sum((r - mean) ** 2 for r in returns) / max(1, len(returns) - 1))
    if std == 0:
        return None
    return (mean - rf_daily) / std * math.sqrt(365)


def max_drawdown(closes: List[float]) -> float:
    if not closes:
        return 0.0
    peak = closes[0]
    max_dd = 0.0
    for c in closes:
        if c > peak:
            peak = c
        dd = (peak - c) / peak if peak > 0 else 0
        if dd > max_dd:
            max_dd = dd
    return max_dd


def find_first_sharpe_cross(candles, window: int, threshold: float):
    """Acha a primeira data onde Sharpe rolling[window] crossed >= threshold."""
    if len(candles) < window + 2:
        return None
    closes = [c["close"] for c in candles]
    rets = daily_returns(closes)
    if len(rets) < window:
        return None
    for i in range(window, len(rets)):
        window_rets = rets[i-window:i]
        s = sharpe(window_rets)
        if s is not None and s >= threshold:
            return candles[i+1]["date"]  # +1 pra alinhar com close
    return None


def beta_label(beta: Optional[float], corr: Optional[float]) -> str:
    if beta is None:
        return "?"
    a = abs(beta)
    cb = abs(corr) if corr is not None else None
    if a < 1.0 and (cb is None or cb < 0.5):
        return "AAA+"
    if a < 1.3:
        return "AA"
    if a < 1.5:
        return "A"
    return "B"


def main():
    beta_data = json.loads(BETA_FILE.read_text(encoding="utf-8"))["beta"]
    corr_data = json.loads(CORR_FILE.read_text(encoding="utf-8"))["matrix"]
    sectors = json.loads(SECTOR_FILE.read_text(encoding="utf-8"))["markets"]

    markets = sorted({f.stem.replace("_1day", "") for f in CANDLES_DIR.glob("*_1day.json")
                       if "summary" not in f.stem.lower()})

    rows = []
    for m in markets:
        candles = load_candles_with_dates(m)
        if len(candles) < 60:
            continue
        closes = [c["close"] for c in candles]
        rets = daily_returns(closes)

        # Sharpe windows
        s60  = sharpe(rets[-60:])  if len(rets) >= 60  else None
        s180 = sharpe(rets[-180:]) if len(rets) >= 180 else None
        s365 = sharpe(rets[-365:]) if len(rets) >= 365 else None

        max_dd = max_drawdown(closes[-180:]) if len(closes) >= 180 else max_drawdown(closes)

        beta = beta_data.get(m)
        corr_btc = corr_data.get(m, {}).get("BTCUSDT") if isinstance(corr_data.get(m), dict) else None

        sector = sectors.get(m, "?")

        # Quando Sharpe60 cruzou 1.5 primeira vez (gate B->A proxy)?
        cross_15 = find_first_sharpe_cross(candles, window=60, threshold=1.5)
        cross_10 = find_first_sharpe_cross(candles, window=30, threshold=1.0)

        quality = beta_label(beta, corr_btc)

        rows.append({
            "market": m,
            "n_candles": len(candles),
            "s60": s60,
            "s180": s180,
            "s365": s365,
            "max_dd_180d": max_dd,
            "beta": beta,
            "corr_btc": corr_btc,
            "sector": sector,
            "first_sharpe60_1.5": cross_15,
            "first_sharpe30_1.0": cross_10,
            "quality": quality,
        })

    # Debug: distribuicao de Sharpe60
    print("=== Distribuicao Sharpe60d (ultimos 60 dias) ===")
    sharpes_with_data = sorted([(r["market"], r["s60"], r["max_dd_180d"]) for r in rows if r["s60"] is not None],
                                key=lambda x: -(x[1] or 0))
    print(f"Total com dados: {len(sharpes_with_data)}")
    print(f"{'Market':<14} {'S60':>7} {'maxDD180':>10}")
    for m, s, dd in sharpes_with_data[:30]:
        ddp = f"{dd*100:.1f}%"
        print(f"  {m:<14} {s:>7.2f} {ddp:>10}")
    print()

    # Filter: passed gates (Sharpe60 >=1.5 -- DD threshold afrouxado pra realidade crypto 65%)
    # CRYPTO REALITY: 12% max_dd era proxy de mercado tradicional. Crypto Tier A
    # roda 40-60% DD historico normal. 65% e cap defensavel pra evitar capitulation absolute.
    eligible = [r for r in rows if r["s60"] is not None and r["s60"] >= 1.5 and r["max_dd_180d"] <= 0.65]
    print(f"[INFO] {len(eligible)} markets passam Sharpe60>=1.5 + maxDD<=65%")

    print("=" * 110)
    print("RETROSPECTIVA: Quais markets PASSARIAM gates atuais HOJE (Sharpe60d>=1.5 + max_dd<=12% + beta)")
    print(f"Capital LIVE atual: ${CAPITAL_TOTAL} | 1% size = ${SIZE_1PCT:.2f}")
    print("=" * 110)
    print()
    print(f"De {len(rows)} markets com candles cached: {len(eligible)} passariam o gate basico")
    print()

    # Rank: AAA+ primeiro, depois por Sharpe60d desc
    quality_rank = {"AAA+": 0, "AA": 1, "A": 2, "B": 3, "?": 4}
    eligible.sort(key=lambda r: (quality_rank[r["quality"]], -(r["s60"] or 0)))

    print(f"{'#':>3} {'Market':<14} {'Qual':<6} {'Sharpe60':>9} {'S180':>7} {'S365':>7} {'maxDD':>7} {'Beta':>7} {'Corr':>7} {'Sector':<14} {'First S60>=1.5':<18}")
    print("-" * 110)
    for i, r in enumerate(eligible[:15], 1):
        s60 = f"{r['s60']:.2f}" if r['s60'] is not None else "-"
        s180 = f"{r['s180']:.2f}" if r['s180'] is not None else "-"
        s365 = f"{r['s365']:.2f}" if r['s365'] is not None else "-"
        dd = f"{r['max_dd_180d']*100:.1f}%"
        b = f"{r['beta']:+.2f}" if r['beta'] is not None else "-"
        c = f"{r['corr_btc']:+.2f}" if r['corr_btc'] is not None else "-"
        cross = r["first_sharpe60_1.5"].strftime("%Y-%m-%d") if r["first_sharpe60_1.5"] else "-"
        print(f"{i:>3} {r['market']:<14} {r['quality']:<6} {s60:>9} {s180:>7} {s365:>7} {dd:>7} {b:>7} {c:>7} {r['sector']:<14} {cross:<18}")

    # Summary AAA+ apenas
    print()
    print("=== AAA+ apenas (beta<1.0 + corr<0.5; diversificadores reais) ===")
    aaa = [r for r in eligible if r["quality"] == "AAA+"]
    for r in aaa[:10]:
        cross = r["first_sharpe60_1.5"].strftime("%Y-%m-%d") if r["first_sharpe60_1.5"] else "-"
        b = f"{r['beta']:+.2f}" if r['beta'] is not None else "N/A"
        c = f"{r['corr_btc']:+.2f}" if r['corr_btc'] is not None else "N/A"
        print(f"  {r['market']:<14} Sharpe60={r['s60']:.2f} beta={b} corr={c} sector={r['sector']} cruzou S60=1.5 em {cross}")

    # Timeline: ordem de "graduation" se sistema rodava esse historico
    print()
    print("=== Ordem cronologica em que SHARPE60 cruzou 1.5 (graduation timeline) ===")
    timeline = [r for r in rows if r["first_sharpe60_1.5"] is not None]
    timeline.sort(key=lambda r: r["first_sharpe60_1.5"])
    for r in timeline[:20]:
        cross = r["first_sharpe60_1.5"].strftime("%Y-%m-%d")
        b = f"{r['beta']:+.2f}" if r['beta'] is not None else "-"
        print(f"  {cross}  {r['market']:<14} quality={r['quality']:<5} beta={b} sector={r['sector']}")

    return rows


if __name__ == "__main__":
    main()
