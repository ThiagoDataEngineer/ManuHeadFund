"""
transition_up_drilldown.py — Drill-down em TRANSITION_UP (único regime estável cross train/holdout).

Hipótese: dentro de TRANSITION_UP existe sub-setup nicho com edge real.

Metodologia:
  - Carrega trades em TRANSITION_UP (já reclassificado 8-state).
  - Para cada trade, enriquece com contexto da barra de entrada: ADX, RSI, hora_brt, dow, vol_ratio.
  - Segmenta por UMA dimensão por vez (buckets fixos).
  - Para cada bucket no TRAIN: trades/exp/pf/wr.
  - Encontra best sub-setup no train.
  - Aplica MESMO bucket ao holdout (zero recalibração).
  - Decide: VIABLE / NEEDS_MORE_DATA / NO_EDGE.

CRITÉRIO ACEITE (sub-setup VIABLE):
  exp_train >= 0.40R AND exp_holdout >= 0.30R AND n_holdout >= 30

NÃO MODIFICA: db.py, signal_generator.py, metrics.py.
Tested in: tests/test_transition_up_drilldown.py (13 testes pytest TDD).

CLI:
    python transition_up_drilldown.py --dim adx
"""
import argparse
import json
import math
import os
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Dict, Iterable, List, Optional, Tuple

from metrics import calc_metrics


MIN_N_TRADES_PER_BUCKET = 30
TRAIN_THRESHOLD  = 0.40
HOLDOUT_THRESHOLD = 0.30
MIN_HOLDOUT_N    = 30
BRT_OFFSET_HOURS = -3


# ----------------------------------------------------------------------------
# Buckets
# ----------------------------------------------------------------------------

def bucket_adx(value: float) -> str:
    if value < 15: return "<15"
    if value < 20: return "15-20"
    if value < 25: return "20-25"
    return ">25"


def bucket_rsi(value: float) -> str:
    if value < 40: return "<40"
    if value < 60: return "40-60"
    return ">60"


def _parse_ts(ts: str) -> datetime:
    """Aceita ISO 8601 com Z ou +00:00."""
    s = str(ts)
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    return datetime.fromisoformat(s)


def bucket_hour_brt(ts: str) -> int:
    """Converte ts UTC para hora BRT (UTC-3) inteira."""
    dt = _parse_ts(ts)
    brt = dt + timedelta(hours=BRT_OFFSET_HOURS)
    return brt.hour


def bucket_dow(ts: str) -> str:
    dt = _parse_ts(ts)
    return ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][dt.weekday()]


def bucket_volume(ratio: float) -> str:
    if ratio < 0.8: return "<0.8"
    if ratio < 1.2: return "0.8-1.2"
    return ">1.2"


# ----------------------------------------------------------------------------
# Enrichment com contexto de entrada (ADX/RSI/vol_ratio)
# ----------------------------------------------------------------------------

def _build_ts_index(candles: List[Dict]) -> Dict[str, int]:
    idx_map: Dict[str, int] = {}
    for i, c in enumerate(candles):
        ts = c.get("ts")
        if not ts:
            continue
        idx_map[ts] = i
        day = str(ts)[:10]
        if day not in idx_map:
            idx_map[day] = i
    return idx_map


def _find_le(candles: List[Dict], target_ts: str) -> Optional[int]:
    lo, hi = 0, len(candles) - 1
    res = None
    while lo <= hi:
        mid = (lo + hi) // 2
        if str(candles[mid].get("ts", "")) <= str(target_ts):
            res = mid
            lo = mid + 1
        else:
            hi = mid - 1
    return res


def enrich_trades_with_entry_context(trades: List[Dict], candles: List[Dict]) -> List[Dict]:
    """Adiciona _adx_entry, _rsi_entry, _vol_ratio_entry a cada trade.
    Usa indicators.adx e indicators.rsi nas janelas até o bar de entrada.
    Volume relativo = vol_bar / média(vol últimos 20 bars).
    """
    if not candles:
        return [dict(t) for t in trades]

    from indicators import adx as _adx_calc, rsi as _rsi_calc

    sorted_candles = sorted(candles, key=lambda c: str(c.get("ts", "")))
    idx_map = _build_ts_index(sorted_candles)
    closes = [c["close"] for c in sorted_candles]
    vols   = [c.get("volume", 0.0) for c in sorted_candles]

    out: List[Dict] = []
    for t in trades:
        nt = dict(t)
        entry_ts = t.get("entry_ts") or t.get("bar_ts")
        if entry_ts is None:
            out.append(nt)
            continue
        i = idx_map.get(entry_ts) or idx_map.get(str(entry_ts)[:10])
        if i is None:
            i = _find_le(sorted_candles, entry_ts)
        if i is None or i < 30:
            out.append(nt)
            continue

        try:
            adx_res = _adx_calc(sorted_candles[max(0, i - 60):i + 1], period=14)
            nt["_adx_entry"] = float(adx_res.get("adx", 0.0))
        except Exception:
            nt["_adx_entry"] = 0.0

        try:
            nt["_rsi_entry"] = float(_rsi_calc(closes[max(0, i - 40):i + 1], period=14))
        except Exception:
            nt["_rsi_entry"] = 50.0

        # Volume ratio: vol[i] / mean(vol[i-20:i])
        if i >= 20:
            window = vols[i - 20:i]
            avg = sum(window) / 20 if window else 1.0
            nt["_vol_ratio_entry"] = (vols[i] / avg) if avg > 0 else 1.0
        else:
            nt["_vol_ratio_entry"] = 1.0

        out.append(nt)
    return out


# ----------------------------------------------------------------------------
# Segmentação por dimensão
# ----------------------------------------------------------------------------

DIM_FN = {
    "adx":    ("_adx_entry",       bucket_adx),
    "rsi":    ("_rsi_entry",       bucket_rsi),
    "hour":   (None,                None),    # uses entry_ts directly
    "dow":    (None,                None),    # uses entry_ts directly
    "volume": ("_vol_ratio_entry", bucket_volume),
}


def _bucket_of(trade: Dict, dim: str) -> Optional[str]:
    if dim == "hour":
        ts = trade.get("entry_ts") or trade.get("bar_ts")
        return f"h{bucket_hour_brt(ts):02d}" if ts else None
    if dim == "dow":
        ts = trade.get("entry_ts") or trade.get("bar_ts")
        return bucket_dow(ts) if ts else None
    key, fn = DIM_FN.get(dim, (None, None))
    if key is None or fn is None:
        return None
    v = trade.get(key)
    if v is None:
        return None
    return fn(float(v))


def segment_by_bucket(trades: List[Dict], dim: str) -> Dict[str, List[Dict]]:
    out: Dict[str, List[Dict]] = defaultdict(list)
    for t in trades:
        b = _bucket_of(t, dim)
        if b is not None:
            out[b].append(t)
    return dict(out)


# ----------------------------------------------------------------------------
# Métricas por bucket
# ----------------------------------------------------------------------------

def metrics_per_bucket(trades_by_bucket: Dict[str, List[Dict]]) -> Dict[str, Dict]:
    out: Dict[str, Dict] = {}
    for bucket, trades in trades_by_bucket.items():
        r_series = [float(t["result_r"]) for t in trades if "result_r" in t]
        if not r_series:
            out[bucket] = {"trades": 0, "exp": 0.0, "pf": 0.0, "wr": 0.0}
            continue
        m = calc_metrics(r_series)
        pf = m.profit_factor if m.profit_factor != float("inf") else None
        out[bucket] = {
            "trades": int(m.total_trades),
            "exp":    round(float(m.expectancy_r), 6),
            "pf":     (round(pf, 4) if pf is not None else None),
            "wr":     round(float(m.win_rate), 4),
        }
    return out


# ----------------------------------------------------------------------------
# Find best sub-setup
# ----------------------------------------------------------------------------

def find_best_subsetup(per_bucket: Dict[str, Dict], min_trades: int = MIN_N_TRADES_PER_BUCKET) -> Dict:
    """Bucket com maior exp respeitando min_trades."""
    candidates = [(b, m) for b, m in per_bucket.items() if m.get("trades", 0) >= min_trades]
    if not candidates:
        return {"bucket": None, "exp": 0.0, "trades": 0, "pf": None, "wr": 0.0}
    best_bucket, best_m = max(candidates, key=lambda x: x[1].get("exp", 0.0))
    return {
        "bucket": best_bucket,
        "exp":    best_m.get("exp", 0.0),
        "trades": best_m.get("trades", 0),
        "pf":     best_m.get("pf"),
        "wr":     best_m.get("wr", 0.0),
    }


# ----------------------------------------------------------------------------
# Apply subsetup filter (holdout sem otimização)
# ----------------------------------------------------------------------------

def apply_subsetup_filter(trades: List[Dict], dim: str, bucket: str) -> List[Dict]:
    return [t for t in trades if _bucket_of(t, dim) == bucket]


# ----------------------------------------------------------------------------
# Decisão
# ----------------------------------------------------------------------------

def decide_subsetup(train_exp: float, holdout_exp: float, holdout_n: int) -> str:
    if train_exp < TRAIN_THRESHOLD:
        return "NO_EDGE"
    # Train passou. Checa holdout.
    if holdout_n < MIN_HOLDOUT_N and holdout_exp >= HOLDOUT_THRESHOLD:
        return "NEEDS_MORE_DATA"
    if holdout_exp < HOLDOUT_THRESHOLD:
        return "NO_EDGE"
    if holdout_n < MIN_HOLDOUT_N:
        return "NEEDS_MORE_DATA"
    return "VIABLE"


# ----------------------------------------------------------------------------
# Build report
# ----------------------------------------------------------------------------

def build_subsetup_report(
    train_trades: List[Dict],
    holdout_trades: List[Dict],
    dim: str,
) -> Dict:
    train_seg     = segment_by_bucket(train_trades, dim)
    holdout_seg   = segment_by_bucket(holdout_trades, dim)
    train_metrics = metrics_per_bucket(train_seg)
    holdout_metrics = metrics_per_bucket(holdout_seg)

    best = find_best_subsetup(train_metrics)

    if best["bucket"] is None:
        decision = "NO_EDGE"
        holdout_validation = {"bucket": None, "trades": 0, "exp": 0.0, "pf": None, "wr": 0.0}
        honest = "Sem bucket no train com trades suficientes (min={})".format(MIN_N_TRADES_PER_BUCKET)
    else:
        # Aplica mesmo bucket ao holdout (sem recalibrar)
        holdout_bucket_metrics = holdout_metrics.get(best["bucket"], {
            "trades": 0, "exp": 0.0, "pf": None, "wr": 0.0
        })
        holdout_validation = {
            "bucket": best["bucket"],
            "trades": holdout_bucket_metrics.get("trades", 0),
            "exp":    holdout_bucket_metrics.get("exp", 0.0),
            "pf":     holdout_bucket_metrics.get("pf"),
            "wr":     holdout_bucket_metrics.get("wr", 0.0),
        }
        decision = decide_subsetup(
            train_exp=best["exp"],
            holdout_exp=holdout_validation["exp"],
            holdout_n=holdout_validation["trades"],
        )
        honest = _honest_note(decision, best, holdout_validation)

    return {
        "dimension":          dim,
        "train_buckets":      train_metrics,
        "holdout_buckets":    holdout_metrics,
        "best_subsetup":      best,
        "holdout_validation": holdout_validation,
        "decision":           decision,
        "honest_note":        honest,
    }


def _honest_note(decision: str, best: Dict, holdout: Dict) -> str:
    if decision == "VIABLE":
        return (f"Sub-setup '{best['bucket']}' tem edge no train ({best['exp']:+.3f}R) "
                f"E confirma no holdout ({holdout['exp']:+.3f}R, n={holdout['trades']}). "
                f"Pode ser tradeable com cautela.")
    if decision == "NEEDS_MORE_DATA":
        return (f"Sub-setup '{best['bucket']}' passa no train ({best['exp']:+.3f}R) mas "
                f"holdout tem amostra insuficiente (n={holdout['trades']}<{MIN_HOLDOUT_N}). "
                f"Aguardar mais dados para validar.")
    if decision == "NO_EDGE":
        return (f"Nenhum sub-setup atinge train>={TRAIN_THRESHOLD}R E holdout>={HOLDOUT_THRESHOLD}R. "
                f"Best train: '{best.get('bucket')}' {best.get('exp', 0):+.3f}R; "
                f"holdout: {holdout.get('exp', 0):+.3f}R (n={holdout.get('trades', 0)}). "
                f"TRANSITION_UP não tem nicho generalizável nesta dimensão.")
    return ""


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------

def _load_trades_paginated(market: str, start: str, end: str) -> List[Dict]:
    from db import Database
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    out: List[Dict] = []
    offset = 0
    page = 1000
    while True:
        params = (
            f"select=*&market=eq.{market}"
            f"&entry_ts=gte.{start}&entry_ts=lte.{end}"
            f"&order=entry_ts.asc&limit={page}&offset={offset}"
        )
        rows = db._get("backtest_trades", params)
        out.extend(rows)
        if len(rows) < page:
            break
        offset += page
    return out


def main():
    parser = argparse.ArgumentParser(description="Drill-down TRANSITION_UP por sub-dimensão")
    parser.add_argument("--market", default="BTCUSD")
    parser.add_argument("--period", default="1hour")
    parser.add_argument("--start",  default="2014-01-01")
    parser.add_argument("--end",    default="2025-05-01")
    parser.add_argument("--train-end", type=int, default=2022)
    parser.add_argument("--holdout-start", type=int, default=2023)
    parser.add_argument("--output", default=None)
    args = parser.parse_args()

    print(f"Carregando trades {args.market} {args.start} -> {args.end}...")
    trades = _load_trades_paginated(args.market, args.start, args.end)
    print(f"  -> {len(trades)} trades totais")

    # Reclassificar 8-state + filtrar TRANSITION_UP LONG
    from db import Database
    from regime_8state_classifier import reclassify_trades_8state
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    print(f"Carregando candles {args.market} {args.period}...")
    candles = db.get_candles(args.market, args.period, args.start, args.end)
    print(f"  -> {len(candles)} candles")

    print("Reclassificando trades 8-state...")
    enriched = reclassify_trades_8state(trades, candles)
    transition_up = [t for t in enriched
                     if t.get("regime") == "TRANSITION_UP" and t.get("direction") == "LONG"]
    print(f"  -> {len(transition_up)} trades em TRANSITION_UP LONG")

    print("Enriquecendo trades com contexto de entrada (ADX/RSI/vol)...")
    enriched_ctx = enrich_trades_with_entry_context(transition_up, candles)
    print(f"  -> {len(enriched_ctx)} enriched")

    # Split train/holdout
    def _year(t):
        ts = t.get("entry_ts", "")
        try: return int(str(ts)[:4])
        except: return None
    train   = [t for t in enriched_ctx if (_year(t) or 9999) <= args.train_end]
    holdout = [t for t in enriched_ctx if (_year(t) or 0) >= args.holdout_start]
    print(f"  -> {len(train)} train | {len(holdout)} holdout")

    # Rodar drill-down em cada dimensão
    full_report = {
        "dataset": {
            "market": args.market,
            "period": args.period,
            "start":  args.start,
            "end":    args.end,
            "train_end": args.train_end,
            "holdout_start": args.holdout_start,
            "n_transition_up_long_train":   len(train),
            "n_transition_up_long_holdout": len(holdout),
        },
        "dimensions": {},
    }

    for dim in ("adx", "rsi", "hour", "dow", "volume"):
        print(f"\n=== Dim: {dim} ===")
        report = build_subsetup_report(train, holdout, dim)
        full_report["dimensions"][dim] = report
        b = report["best_subsetup"]
        h = report["holdout_validation"]
        print(f"  Best train: bucket={b['bucket']} exp={b['exp']:+.3f}R n={b['trades']}")
        print(f"  Holdout:    bucket={h['bucket']} exp={h['exp']:+.3f}R n={h['trades']}")
        print(f"  Decision:   {report['decision']}")
        print(f"  Note:       {report['honest_note']}")

    # Decisão global: VIABLE se QUALQUER dimensão VIABLE
    decisions = [r["decision"] for r in full_report["dimensions"].values()]
    if "VIABLE" in decisions:
        full_report["overall_decision"] = "VIABLE"
    elif "NEEDS_MORE_DATA" in decisions:
        full_report["overall_decision"] = "NEEDS_MORE_DATA"
    else:
        full_report["overall_decision"] = "NO_EDGE"

    out_path = args.output
    if out_path is None:
        here = os.path.dirname(os.path.abspath(__file__))
        journal_dir = os.path.abspath(os.path.join(here, "..", "journal"))
        os.makedirs(journal_dir, exist_ok=True)
        out_path = os.path.join(journal_dir, "task2a_transition_up_subsetups.json")

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(full_report, f, indent=2, ensure_ascii=False)

    print(f"\n=== OVERALL DECISION: {full_report['overall_decision']} ===")
    print(f"Saved: {out_path}")


if __name__ == "__main__":
    main()
