"""
run_baseline_v2_strict_v2.py — Compara baseline 14y LONG BTCUSD com/sem regime filter.

Empirical validation: signal_generator.apply_regime_filter mode='off' vs 'strict_v2'.

Estratégia (sem re-rodar backtest pesado):
  1. Carrega LONG trades já gerados (backtest_trades, BTCUSD, 2012-2026).
  2. Carrega daily candles BTCUSD (2011-2026) — usados para classificar regime 8-state.
  3. Reclassifica cada trade para 8-state usando classify_8state_fast (SMA200+ADX).
  4. Aplica apply_regime_filter(signal='COMPRA', regime, mode, day_of_week_brt).
  5. Filtra trades sobreviventes e computa métricas (PF, exp, max_DD, WR, Sharpe).

Output: journal/baseline_v2_strict_v2_comparison.json

Uso:
    python backtest/run_baseline_v2_strict_v2.py
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Dict, List

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dotenv import dotenv_values  # noqa: E402

from db import Database  # noqa: E402
from metrics import calc_metrics  # noqa: E402
from regime_8state_classifier import (  # noqa: E402
    SMA200_PERIOD,
    classify_8state_fast,
    precompute_indicators,
)
from signal_generator import apply_regime_filter  # noqa: E402


JOURNAL_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "journal")
)
OUTPUT_JSON = os.path.join(JOURNAL_DIR, "baseline_v2_strict_v2_comparison.json")


def load_env() -> None:
    env_path = os.path.join(os.path.dirname(__file__), ".env")
    for k, v in dotenv_values(env_path).items():
        if v and not os.environ.get(k):
            os.environ[k] = v


def load_long_trades(db: Database, market: str = "BTCUSD") -> List[Dict]:
    """Carrega todas as LONG trades de BTCUSD via paginação."""
    rows: List[Dict] = []
    offset = 0
    page = 1000
    while True:
        params = (
            f"select=*&market=eq.{market}&direction=eq.LONG"
            f"&order=entry_ts.asc&limit={page}&offset={offset}"
        )
        chunk = db._get("backtest_trades", params)
        rows.extend(chunk)
        if len(chunk) < page:
            break
        offset += page
    return rows


def load_daily_candles(db: Database, market: str = "BTCUSD") -> List[Dict]:
    """Carrega TODAS as daily candles BTCUSD (ordenadas ASC)."""
    out: List[Dict] = []
    offset = 0
    page = 1000
    while True:
        params = (
            f"select=*&market=eq.{market}&period=eq.1day"
            f"&order=ts.asc&limit={page}&offset={offset}"
        )
        chunk = db._get("candles", params)
        out.extend(chunk)
        if len(chunk) < page:
            break
        offset += page
    return out


def build_daily_lookup(candles: List[Dict]) -> Dict[str, int]:
    """Mapa YYYY-MM-DD -> index nas candles ASC."""
    m: Dict[str, int] = {}
    for i, c in enumerate(candles):
        ts = c.get("ts", "")
        day = str(ts)[:10]
        if day and day not in m:
            m[day] = i
    return m


def entry_to_daily_index(entry_ts: str, lookup: Dict[str, int],
                         sorted_days: List[str]) -> int:
    """Maior index tal que candle.date <= entry_ts.date."""
    day = str(entry_ts)[:10]
    if day in lookup:
        return lookup[day]
    # binary search no sorted_days
    lo, hi = 0, len(sorted_days) - 1
    res = -1
    while lo <= hi:
        mid = (lo + hi) // 2
        if sorted_days[mid] <= day:
            res = mid
            lo = mid + 1
        else:
            hi = mid - 1
    if res < 0:
        return -1
    return lookup[sorted_days[res]]


def dow_brt(entry_ts_str: str) -> int:
    """Day of week BRT (UTC-3). Mon=1..Sat=6, Sun=0.
    entry_ts vem ISO em UTC. Converte e devolve weekday no estilo whitelist.
    """
    try:
        # Trim '+00:00' ou 'Z'
        s = entry_ts_str.replace("Z", "+00:00")
        dt_utc = datetime.fromisoformat(s)
        if dt_utc.tzinfo is None:
            dt_utc = dt_utc.replace(tzinfo=timezone.utc)
        dt_brt = dt_utc.astimezone(timezone(timedelta(hours=-3)))
        # Python weekday: Mon=0..Sun=6. apply_regime_filter espera Mon=1, Sun=0.
        # Convertendo:
        py = dt_brt.weekday()  # Mon=0..Sun=6
        # Mapear: Mon=1, Tue=2, ..., Sat=6, Sun=0
        return (py + 1) % 7
    except Exception:
        return -1


def annualize_sharpe(r_series: List[float], trades_per_year: float) -> float:
    """Sharpe anualizado: (mean/std) * sqrt(trades_per_year)."""
    n = len(r_series)
    if n < 2:
        return 0.0
    m = sum(r_series) / n
    var = sum((r - m) ** 2 for r in r_series) / (n - 1)
    std = math.sqrt(var)
    if std == 0:
        return float("inf") if m > 0 else float("-inf") if m < 0 else 0.0
    return (m / std) * math.sqrt(trades_per_year)


def compute_metrics(trades: List[Dict]) -> Dict:
    longs = [t for t in trades if t.get("direction") == "LONG"]
    r_series = [float(t["result_r"]) for t in longs if t.get("result_r") is not None]
    n = len(r_series)
    if n == 0:
        return {
            "n_trades": 0, "exp_r": 0.0, "pf": 0.0, "max_dd": 0.0,
            "wr": 0.0, "sharpe_annual": 0.0, "total_r": 0.0,
        }
    m = calc_metrics(r_series)

    # trades por ano
    years = []
    for t in longs:
        ts = t.get("entry_ts") or ""
        try:
            years.append(int(str(ts)[:4]))
        except Exception:
            pass
    span = (max(years) - min(years) + 1) if years else 1
    tpy = n / max(1, span)
    sh = annualize_sharpe(r_series, tpy)

    pf = m.profit_factor if math.isfinite(m.profit_factor) else None
    return {
        "n_trades": n,
        "exp_r": round(m.expectancy_r, 4),
        "pf": round(pf, 3) if pf is not None else None,
        "max_dd": round(m.max_drawdown_r, 2),
        "wr": round(m.win_rate, 2),
        "sharpe_annual": round(sh, 3) if math.isfinite(sh) else None,
        "total_r": round(sum(r_series), 2),
        "span_years": span,
        "trades_per_year": round(tpy, 1),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--market", default="BTCUSD")
    parser.add_argument("--output", default=OUTPUT_JSON)
    args = parser.parse_args()

    load_env()
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)

    t0 = datetime.now()
    print(f"[1/5] Carregando LONG trades {args.market}...")
    trades = load_long_trades(db, args.market)
    print(f"  -> {len(trades)} trades")

    print(f"[2/5] Carregando daily candles {args.market}...")
    candles = load_daily_candles(db, args.market)
    print(f"  -> {len(candles)} daily candles ({candles[0]['ts'][:10]} -> {candles[-1]['ts'][:10]})")

    print(f"[3/5] Pre-computando indicadores 8-state...")
    precomputed = precompute_indicators(candles)

    lookup = build_daily_lookup(candles)
    sorted_days = sorted(lookup.keys())

    print(f"[4/5] Classificando regime 8-state + dow_brt por trade...")
    n_unclassified = 0
    regime_dist = defaultdict(int)
    dow_dist = defaultdict(int)
    for t in trades:
        entry_ts = t.get("entry_ts") or ""
        idx = entry_to_daily_index(entry_ts, lookup, sorted_days)
        if idx < SMA200_PERIOD:
            t["_regime8"] = "UNKNOWN"
            n_unclassified += 1
        else:
            t["_regime8"] = classify_8state_fast(precomputed, idx)
        t["_dow_brt"] = dow_brt(entry_ts)
        regime_dist[t["_regime8"]] += 1
        dow_dist[t["_dow_brt"]] += 1

    print(f"  -> unclassified: {n_unclassified}")
    print(f"  -> regime dist: {dict(regime_dist)}")
    print(f"  -> dow_brt dist (Mon=1..Sun=0): {dict(dow_dist)}")

    print(f"[5/5] Aplicando apply_regime_filter (off vs strict_v2)...")

    def filter_trades(mode: str) -> List[Dict]:
        out = []
        for t in trades:
            regime = t["_regime8"] if t["_regime8"] != "UNKNOWN" else None
            final_signal, reason = apply_regime_filter(
                "COMPRA", regime, mode=mode, day_of_week_brt=t["_dow_brt"]
            )
            if final_signal != "NEUTRO":
                out.append(t)
        return out

    trades_off = filter_trades("off")
    trades_strict = filter_trades("strict_v2")

    m_off = compute_metrics(trades_off)
    m_strict = compute_metrics(trades_strict)

    print(f"\n=== filter_off ({m_off['n_trades']} trades) ===")
    print(f"  exp={m_off['exp_r']}R  pf={m_off['pf']}  DD={m_off['max_dd']}R  "
          f"WR={m_off['wr']}%  Sharpe(ann)={m_off['sharpe_annual']}  totalR={m_off['total_r']}")
    print(f"\n=== filter_strict_v2 ({m_strict['n_trades']} trades) ===")
    print(f"  exp={m_strict['exp_r']}R  pf={m_strict['pf']}  DD={m_strict['max_dd']}R  "
          f"WR={m_strict['wr']}%  Sharpe(ann)={m_strict['sharpe_annual']}  totalR={m_strict['total_r']}")

    def pct_change(a, b):
        if a == 0 or a is None:
            return None
        return round((b - a) / a * 100, 1) if b is not None else None

    delta = {
        "n_trades_pct": pct_change(m_off["n_trades"], m_strict["n_trades"]),
        "exp_delta_R": round((m_strict["exp_r"] or 0) - (m_off["exp_r"] or 0), 4),
        "pf_delta": round((m_strict["pf"] or 0) - (m_off["pf"] or 0), 3) if m_strict["pf"] and m_off["pf"] else None,
        "dd_delta_R": round((m_strict["max_dd"] or 0) - (m_off["max_dd"] or 0), 2),
        "dd_reduction_pct": pct_change(m_off["max_dd"], m_strict["max_dd"]),
        "wr_delta_pct": round((m_strict["wr"] or 0) - (m_off["wr"] or 0), 2),
        "total_R_delta": round((m_strict["total_r"] or 0) - (m_off["total_r"] or 0), 2),
    }

    # Decisão heurística
    pf_better = (m_strict["pf"] or 0) > (m_off["pf"] or 0)
    dd_better = (m_strict["max_dd"] or 0) < (m_off["max_dd"] or 0)
    exp_better = (m_strict["exp_r"] or 0) > (m_off["exp_r"] or 0)
    if pf_better and dd_better and exp_better:
        decision = "STRICT_V2_WINS"
    elif pf_better or dd_better:
        decision = "STRICT_V2_PARTIAL_WIN"
    elif (m_strict["pf"] or 0) < (m_off["pf"] or 0) * 0.95:
        decision = "STRICT_V2_LOSES"
    else:
        decision = "INCONCLUSIVE"

    honest_note = (
        f"strict_v2 mantém apenas BULL_STRONG+LONG e TRANSITION_UP+LONG+Mon BRT. "
        f"Descartou {len(trades) - m_strict['n_trades']} trades "
        f"({round((1 - m_strict['n_trades']/max(1,len(trades))) * 100, 1)}% do total). "
        f"Trade-off: menos trades = menos oportunidades de capturar edge, "
        f"mas em tese maior consistência. Sharpe NÃO é diretamente comparável "
        f"entre os dois (trades_per_year diferem)."
    )

    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "dataset": {
            "market": args.market,
            "direction": "LONG",
            "period_trades": "1hour (intraday entries)",
            "regime_classifier_period": "1day (SMA200+ADX)",
            "candle_range": f"{candles[0]['ts'][:10]} -> {candles[-1]['ts'][:10]}",
            "n_trades_raw": len(trades),
            "n_trades_unclassified": n_unclassified,
        },
        "filter_off": m_off,
        "filter_strict_v2": m_strict,
        "delta": delta,
        "regime_distribution_raw_trades": dict(regime_dist),
        "decision_hint": decision,
        "honest_note": honest_note,
        "elapsed_seconds": round((datetime.now() - t0).total_seconds(), 1),
    }

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print(f"\n=== DELTA ===")
    print(json.dumps(delta, indent=2))
    print(f"\nDecision: {decision}")
    print(f"\nSaved: {args.output}")
    print(f"Elapsed: {report['elapsed_seconds']}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
