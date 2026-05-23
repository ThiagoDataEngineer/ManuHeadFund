"""
regime_direction_matrix.py — Matriz Regime × Direção em 14 anos BTCUSD Bitstamp.

Valida (ou refuta) achados do Chat 3 (18 meses):
  - TRANSITION_UP: SHORT exp +0.81R ?
  - SIDEWAYS:      SHORT exp +0.34R ?
  - BULL_WEAK:     AVOID ?

CONTRATO (JSON output):
{
  "matrix": [
    {
      "regime":           str,           # um dos 8 REGIMES
      "days_total_14y":   int,
      "days_pct":         float,
      "long":             {trades, exp, pf, wr},
      "short":            {trades, exp, pf, wr},
      "best_direction":   "LONG" | "SHORT" | "BOTH" | "AVOID",
      "edge_strength":    "STRONG" | "MEDIUM" | "WEAK" | "NONE",
      "confidence":       "HIGH"   (>=100) | "MEDIUM" (30-99) | "LOW" (<30),
      "years_appeared":   [int, ...]
    } x 8
  ],
  "operational_summary": {
    "regimes_long_only":         [str, ...],
    "regimes_short_only":        [str, ...],
    "regimes_both":              [str, ...],
    "regimes_avoid":             [str, ...],
    "total_tradeable_pct_of_time": float
  },
  "go_criterion": {
    "rule":   "...",
    "passed": bool,
    "qualifying_regimes": [str, ...]
  }
}

EDGE STRENGTH thresholds:
  STRONG: exp >= +0.5R
  MEDIUM: +0.3 <= exp < +0.5R
  WEAK:    0.0 <= exp < +0.3R
  NONE:   exp < 0

BEST DIRECTION (priority):
  BOTH:        ambas direções com exp >= +0.3R
  LONG only:   long exp >= +0.3R E short exp < long_exp
  SHORT only:  short exp >= +0.3R E long exp < short_exp
  AVOID:       nenhuma direção atinge +0.3R

CONFIDENCE:
  HIGH:   n_trades >= 100
  MEDIUM: 30 <= n_trades < 100
  LOW:    n_trades < 30 (= INSUFFICIENT_DATA)

GO CRITERION:
  >= 4 regimes com edge MEDIUM+ AND confidence != LOW

NÃO MODIFICA: db.py, signal_generator.py, metrics.py.
Tested in: tests/test_regime_direction_matrix.py (9 testes pytest TDD).
"""
import argparse
import json
import math
import os
from collections import defaultdict
from typing import Dict, Iterable, List, Optional

from metrics import calc_metrics


# Os 8 regimes possíveis (alinha tendência + força + transição)
REGIMES = (
    "BULL_STRONG",
    "BULL_WEAK",
    "TRANSITION_UP",
    "TRANSITION_DOWN",
    "SIDEWAYS",
    "BEAR_WEAK",
    "BEAR_STRONG",
    "CAPITULATION",
)

# Mapa conservador de regimes simples (3-state, SMA200 only) -> 8-state.
# Sem ADX/transição armazenados nos trades, só conseguimos mapear o subset
# que aparece no dataset atual: bull -> BULL_WEAK / bear -> BEAR_WEAK / sideways -> SIDEWAYS.
# Os 5 restantes ficam como INSUFFICIENT_DATA até reclassificação completa com candles.
_3_TO_8_FALLBACK_MAP = {
    "bull":     "BULL_WEAK",
    "bear":     "BEAR_WEAK",
    "sideways": "SIDEWAYS",
}


def normalize_regime_label(raw_regime: Optional[str]) -> Optional[str]:
    """Normaliza regime para o conjunto de 8 estados.

    - Se já é um dos 8 (case-insensitive normalizado), retorna.
    - Se é um dos 3 simples (bull/bear/sideways), usa fallback conservador.
    - Caso contrário, None.
    """
    if not raw_regime:
        return None
    s = str(raw_regime).strip()
    if s.upper() in REGIMES:
        return s.upper()
    return _3_TO_8_FALLBACK_MAP.get(s.lower())


def enrich_trades_with_normalized_regime(trades: List[Dict]) -> List[Dict]:
    """Retorna nova lista com regime normalizado para 8-state. Trades sem regime mapeável são descartados."""
    out = []
    for t in trades:
        n = normalize_regime_label(t.get("regime"))
        if n is None:
            continue
        nt = dict(t)
        nt["regime"] = n
        out.append(nt)
    return out


# ----------------------------------------------------------------------------
# Helpers — extração e filtros
# ----------------------------------------------------------------------------

def _year_of(trade: Dict) -> Optional[int]:
    ts = trade.get("entry_ts") or trade.get("bar_ts") or trade.get("exit_ts")
    if not ts:
        return None
    try:
        return int(str(ts)[:4])
    except (ValueError, TypeError):
        return None


def _day_of(trade: Dict) -> Optional[str]:
    ts = trade.get("entry_ts") or trade.get("bar_ts")
    if not ts:
        return None
    return str(ts)[:10]  # YYYY-MM-DD


def _filter_regime_direction(trades: List[Dict], regime: str, direction: str) -> List[Dict]:
    return [
        t for t in trades
        if t.get("regime") == regime and t.get("direction") == direction and "result_r" in t
    ]


# ----------------------------------------------------------------------------
# Classification helpers
# ----------------------------------------------------------------------------

def classify_edge_strength(exp_r: float) -> str:
    """STRONG/MEDIUM/WEAK/NONE conforme expectancy_r."""
    if exp_r >= 0.5:  return "STRONG"
    if exp_r >= 0.3:  return "MEDIUM"
    if exp_r >= 0.0:  return "WEAK"
    return "NONE"


def classify_confidence(n_trades: int) -> str:
    """HIGH (>=100) / MEDIUM (30-99) / LOW (<30)."""
    if n_trades >= 100: return "HIGH"
    if n_trades >= 30:  return "MEDIUM"
    return "LOW"


def pick_best_direction(long_metrics: Dict, short_metrics: Dict) -> str:
    """Decide a melhor direção dadas métricas LONG e SHORT.
    Threshold de aceitação: exp >= +0.3R (MEDIUM+).
    Empate em ambas com exp >= 0.3: BOTH.
    Ambas < 0.3: AVOID.
    """
    le = long_metrics.get("exp", 0.0)
    se = short_metrics.get("exp", 0.0)
    long_ok  = le >= 0.3
    short_ok = se >= 0.3
    if long_ok and short_ok:
        return "BOTH"
    if long_ok:
        return "LONG"
    if short_ok:
        return "SHORT"
    return "AVOID"


# ----------------------------------------------------------------------------
# Year distribution
# ----------------------------------------------------------------------------

def years_appeared(trades: List[Dict], regime: str) -> List[int]:
    """Lista (ordenada, deduplicada) de anos em que o regime aparece nos trades."""
    yrs = set()
    for t in trades:
        if t.get("regime") != regime:
            continue
        y = _year_of(t)
        if y is not None:
            yrs.add(y)
    return sorted(yrs)


# ----------------------------------------------------------------------------
# Long/Short correlation (alinhamento por dia)
# ----------------------------------------------------------------------------

def long_short_correlation(long_trades: List[Dict], short_trades: List[Dict]) -> float:
    """Correlação de Pearson dos result_r de LONG vs SHORT alinhados por dia.
    Retorna 0.0 se amostra insuficiente."""
    long_by_day  = defaultdict(list)
    short_by_day = defaultdict(list)
    for t in long_trades:
        d = _day_of(t)
        if d: long_by_day[d].append(float(t.get("result_r", 0.0)))
    for t in short_trades:
        d = _day_of(t)
        if d: short_by_day[d].append(float(t.get("result_r", 0.0)))

    common = sorted(set(long_by_day.keys()) & set(short_by_day.keys()))
    if len(common) < 2:
        return 0.0

    xs = [sum(long_by_day[d])  / len(long_by_day[d])  for d in common]
    ys = [sum(short_by_day[d]) / len(short_by_day[d]) for d in common]

    n = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    cov = sum((xs[i] - mx) * (ys[i] - my) for i in range(n)) / n
    vx  = sum((x - mx) ** 2 for x in xs) / n
    vy  = sum((y - my) ** 2 for y in ys) / n
    if vx <= 0 or vy <= 0:
        return 0.0
    return cov / math.sqrt(vx * vy)


# ----------------------------------------------------------------------------
# Aggregate por (regime, direção)
# ----------------------------------------------------------------------------

def aggregate_direction_metrics(trades: List[Dict], regime: str, direction: str) -> Dict:
    """Métricas (trades, exp, pf, wr) para um par (regime, direção)."""
    filtered = _filter_regime_direction(trades, regime, direction)
    if not filtered:
        return {"trades": 0, "exp": 0.0, "pf": 0.0, "wr": 0.0}

    r_series = [float(t["result_r"]) for t in filtered]
    m = calc_metrics(r_series)
    pf = m.profit_factor if m.profit_factor != float("inf") else None
    return {
        "trades": int(m.total_trades),
        "exp":    round(float(m.expectancy_r), 6),
        "pf":     (round(pf, 4) if pf is not None else None),
        "wr":     round(float(m.win_rate), 4),
    }


# ----------------------------------------------------------------------------
# Build regime entry (uma linha da matriz)
# ----------------------------------------------------------------------------

def build_regime_entry(
    trades: List[Dict],
    regime: str,
    candles_by_day: Optional[Dict[str, Dict]] = None,
    total_days_14y: Optional[int] = None,
) -> Dict:
    long_m  = aggregate_direction_metrics(trades, regime, "LONG")
    short_m = aggregate_direction_metrics(trades, regime, "SHORT")

    best = pick_best_direction(long_m, short_m)
    # edge_strength considera o melhor lado tradeável
    if best == "BOTH":
        best_exp = max(long_m["exp"], short_m["exp"])
    elif best == "LONG":
        best_exp = long_m["exp"]
    elif best == "SHORT":
        best_exp = short_m["exp"]
    else:
        best_exp = max(long_m["exp"], short_m["exp"])  # para classificar mesmo no AVOID
    edge = classify_edge_strength(best_exp)

    total_trades = long_m["trades"] + short_m["trades"]
    confidence = classify_confidence(total_trades)

    years = years_appeared(trades, regime)

    # Days estimate via contagem de dias distintos com trades nesse regime
    days_in_regime = len({
        _day_of(t) for t in trades
        if t.get("regime") == regime and _day_of(t) is not None
    })

    days_pct = 0.0
    if total_days_14y and total_days_14y > 0:
        days_pct = round((days_in_regime / total_days_14y) * 100.0, 2)

    return {
        "regime":           regime,
        "days_total_14y":   int(days_in_regime),
        "days_pct":         days_pct,
        "long":             long_m,
        "short":            short_m,
        "best_direction":   best,
        "edge_strength":    edge,
        "confidence":       confidence,
        "years_appeared":   years,
    }


# ----------------------------------------------------------------------------
# Operational summary + GO criterion
# ----------------------------------------------------------------------------

def _operational_summary(matrix: List[Dict]) -> Dict:
    long_only  = [e["regime"] for e in matrix if e["best_direction"] == "LONG"]
    short_only = [e["regime"] for e in matrix if e["best_direction"] == "SHORT"]
    both       = [e["regime"] for e in matrix if e["best_direction"] == "BOTH"]
    avoid      = [e["regime"] for e in matrix if e["best_direction"] == "AVOID"]

    tradeable_pct = round(sum(
        e.get("days_pct", 0.0) for e in matrix if e["best_direction"] != "AVOID"
    ), 2)

    return {
        "regimes_long_only":           long_only,
        "regimes_short_only":          short_only,
        "regimes_both":                both,
        "regimes_avoid":               avoid,
        "total_tradeable_pct_of_time": tradeable_pct,
    }


def evaluate_matrix_go_criterion(matrix: List[Dict]) -> Dict:
    """GO: >= 4 regimes com edge MEDIUM+ AND confidence != LOW."""
    qualifying = [
        e["regime"] for e in matrix
        if e["edge_strength"] in ("MEDIUM", "STRONG") and e["confidence"] != "LOW"
    ]
    passed = len(qualifying) >= 4
    return {
        "rule":                ">= 4 regimes com edge MEDIUM+ AND confidence != LOW",
        "passed":              bool(passed),
        "qualifying_regimes":  qualifying,
    }


# ----------------------------------------------------------------------------
# Build matrix report
# ----------------------------------------------------------------------------

def build_matrix_report(
    trades: List[Dict],
    candles_by_day: Optional[Dict[str, Dict]] = None,
    total_days_14y: Optional[int] = None,
) -> Dict:
    """Constrói o relatório completo da matriz Regime × Direção."""
    if total_days_14y is None:
        all_days = {_day_of(t) for t in trades if _day_of(t) is not None}
        total_days_14y = len(all_days)

    matrix = []
    for regime in REGIMES:
        entry = build_regime_entry(
            trades, regime,
            candles_by_day=candles_by_day,
            total_days_14y=total_days_14y,
        )
        matrix.append(entry)

    return {
        "matrix":              matrix,
        "operational_summary": _operational_summary(matrix),
        "go_criterion":        evaluate_matrix_go_criterion(matrix),
    }


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------

def _load_trades_paginated(market: str, start: str, end: str) -> List[Dict]:
    """Carrega trades com paginação (contorna limit default PostgREST=1000)."""
    from db import Database
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)

    out: List[Dict] = []
    offset = 0
    page = 1000
    while True:
        params = (
            f"select=*"
            f"&market=eq.{market}"
            f"&entry_ts=gte.{start}"
            f"&entry_ts=lte.{end}"
            f"&order=entry_ts.asc"
            f"&limit={page}&offset={offset}"
        )
        rows = db._get("backtest_trades", params)
        out.extend(rows)
        if len(rows) < page:
            break
        offset += page
    return out


def main():
    parser = argparse.ArgumentParser(description="Matriz Regime x Direção em 14 anos")
    parser.add_argument("--market", default="BTCUSD")
    parser.add_argument("--period", default="1hour")
    parser.add_argument("--start",  default="2014-01-01")
    parser.add_argument("--end",    default="2025-05-01")
    parser.add_argument("--output", default=None)
    parser.add_argument("--reclassify-8state", action="store_true",
                        help="Carrega candles e reclassifica trades para os 8 regimes ADX-aware")
    args = parser.parse_args()

    print(f"Carregando trades {args.market} {args.start} -> {args.end}...")
    trades = _load_trades_paginated(args.market, args.start, args.end)
    print(f"  -> {len(trades)} trades totais")

    trades_with_regime = [t for t in trades if t.get("regime")]
    print(f"  -> {len(trades_with_regime)} com regime classificado (raw)")

    if args.reclassify_8state:
        print(f"\nCarregando candles {args.market} {args.period} para reclassificacao 8-state...")
        from db import Database
        from regime_8state_classifier import reclassify_trades_8state
        key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
        db = Database(url=os.environ["SUPABASE_URL"], key=key)
        candles = db.get_candles(args.market, args.period, args.start, args.end)
        print(f"  -> {len(candles)} candles carregados")
        print("Reclassificando trades para 8-state...")
        enriched = reclassify_trades_8state(trades_with_regime, candles)
        print(f"  -> {len(enriched)} trades reclassificados")
        distinct = sorted({str(t.get('regime', '')) for t in enriched if t.get('regime')})
        print(f"  -> regimes 8-state detectados: {distinct}")
    else:
        enriched = enrich_trades_with_normalized_regime(trades_with_regime)
        print(f"  -> {len(enriched)} apos normalizacao conservadora 3->8")
        raw_distinct = sorted({str(t.get('regime')).strip() for t in trades_with_regime})
        print(f"  -> regimes raw detectados: {raw_distinct}")

    report = build_matrix_report(enriched)

    out_path = args.output
    if out_path is None:
        here = os.path.dirname(os.path.abspath(__file__))
        journal_dir = os.path.abspath(os.path.join(here, "..", "journal"))
        os.makedirs(journal_dir, exist_ok=True)
        out_path = os.path.join(journal_dir, "task2_regime_direction_matrix.json")

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    # Print resumido
    print("\n=== MATRIZ REGIME x DIRECAO ===")
    print(f"{'Regime':<18} | {'L exp':>8} {'L pf':>6} {'L n':>6} | {'S exp':>8} {'S pf':>6} {'S n':>6} | {'best':<6} {'edge':<8} {'conf':<6}")
    print("-" * 110)
    for e in report["matrix"]:
        L = e["long"]; S = e["short"]
        print(f"{e['regime']:<18} | "
              f"{L['exp']:>+8.4f} {str(L['pf']):>6} {L['trades']:>6} | "
              f"{S['exp']:>+8.4f} {str(S['pf']):>6} {S['trades']:>6} | "
              f"{e['best_direction']:<6} {e['edge_strength']:<8} {e['confidence']:<6}")

    op = report["operational_summary"]
    print("\n=== OPERATIONAL SUMMARY ===")
    print(f"  LONG only:  {op['regimes_long_only']}")
    print(f"  SHORT only: {op['regimes_short_only']}")
    print(f"  BOTH:       {op['regimes_both']}")
    print(f"  AVOID:      {op['regimes_avoid']}")
    print(f"  Tradeable % of time: {op['total_tradeable_pct_of_time']}%")

    go = report["go_criterion"]
    print(f"\n=== GO CRITERION ===")
    print(f"  Rule:   {go['rule']}")
    print(f"  Qualifying: {go['qualifying_regimes']}")
    print(f"  Passed: {go['passed']}")
    print(f"\nSaved: {out_path}")


if __name__ == "__main__":
    main()
