"""drilldown_bull_by_year.py — Investiga quebra de BULL_STRONG/BULL_WEAK em 2023-2025.

Input: lista de trades com {entry_ts, regime, direction, result_r, entry_price, ...}
Output: relatorio diagnostico com metricas por ano + padrao de losers.

Diagnostico:
  - MILD_REGIME_ARTIFACT: so o ano mais recente quebra, anteriores OK
  - STRUCTURAL_BREAK:     todos os anos do holdout quebram
  - MIXED:                quebra em alguns anos mas nao no padrao temporal

Nao toca: db.py, signal_generator.py, metrics.py.
"""
from collections import defaultdict
from typing import Dict, List, Optional


BULL_REGIMES = ("BULL_STRONG", "BULL_WEAK")
DEGRADATION_THRESHOLD = 0.10   # exp do ano < (train_exp - 0.10) = quebra
TRAIN_YEARS = list(range(2014, 2023))   # 2014-2022 inclusive
HOLDOUT_YEARS = [2023, 2024, 2025]


# ── Filtros e splits ────────────────────────────────────────────────────────

def _year_of(trade: Dict) -> Optional[int]:
    ts = trade.get("entry_ts") or trade.get("bar_ts") or trade.get("exit_ts")
    if not ts:
        return None
    try:
        return int(str(ts)[:4])
    except (ValueError, TypeError):
        return None


def filter_bull_regimes(trades: List[Dict]) -> List[Dict]:
    """Mantem apenas trades em BULL_STRONG e BULL_WEAK."""
    return [t for t in trades if t.get("regime") in BULL_REGIMES]


def split_by_year(trades: List[Dict]) -> Dict[int, List[Dict]]:
    buckets: Dict[int, List[Dict]] = defaultdict(list)
    for t in trades:
        y = _year_of(t)
        if y is not None:
            buckets[y].append(t)
    return dict(buckets)


# ── Metricas ───────────────────────────────────────────────────────────────

def metrics_for(trades: List[Dict]) -> Dict:
    """Calcula trades/exp/pf/wr de uma lista de trades."""
    if not trades:
        return {"trades": 0, "exp": 0.0, "pf": 0.0, "wr": 0.0}
    rs = [t.get("result_r", 0.0) for t in trades]
    wins = [r for r in rs if r > 0]
    losses = [r for r in rs if r < 0]
    gw = sum(wins); gl = abs(sum(losses))
    pf = (gw / gl) if gl > 0 else (float("inf") if gw > 0 else 0.0)
    wr = (len(wins) / len(rs)) * 100.0 if rs else 0.0
    return {
        "trades": len(rs),
        "exp": sum(rs) / len(rs),
        "pf": pf,
        "wr": wr,
    }


# ── Compare holdout vs train ────────────────────────────────────────────────

def compare_holdout_vs_train(train_metrics: Dict, holdout_metrics: Dict) -> Dict:
    """Calcula deltas e marca se degradou (holdout pior que train)."""
    delta_exp = holdout_metrics["exp"] - train_metrics["exp"]
    delta_pf = holdout_metrics["pf"] - train_metrics["pf"]
    degraded = holdout_metrics["exp"] < train_metrics["exp"]
    return {
        "delta_exp": delta_exp,
        "delta_pf": delta_pf,
        "degraded": degraded,
    }


# ── Diagnostico de padrao ──────────────────────────────────────────────────

def diagnose_break_pattern(per_year: Dict[int, Dict], train_exp: float) -> str:
    """Decide se a quebra e MILD_REGIME_ARTIFACT, STRUCTURAL_BREAK ou MIXED.

    Regra:
      - 'broken' = exp_ano < (train_exp - DEGRADATION_THRESHOLD) OR exp_ano < 0
      - Todos os anos broken → STRUCTURAL_BREAK
      - Apenas o ultimo ano broken (anteriores OK) → MILD_REGIME_ARTIFACT
      - Resto → MIXED
    """
    if not per_year:
        return "MIXED"
    years_sorted = sorted(per_year.keys())
    threshold = train_exp - DEGRADATION_THRESHOLD
    broken = {y: (per_year[y]["exp"] < threshold or per_year[y]["exp"] < 0) for y in years_sorted}

    if all(broken.values()):
        return "STRUCTURAL_BREAK"
    # Padrao MILD: apenas o ano mais recente quebrou
    last_year = years_sorted[-1]
    if broken[last_year] and not any(broken[y] for y in years_sorted[:-1]):
        return "MILD_REGIME_ARTIFACT"
    return "MIXED"


# ── Loser pattern extractor ────────────────────────────────────────────────

def extract_loser_pattern(losers: List[Dict]) -> str:
    """Resume padrao comum dos trades perdedores em texto descritivo."""
    if not losers:
        return "Nenhum trade perdedor identificado."

    n = len(losers)
    avg_r = sum(t.get("result_r", 0.0) for t in losers) / n
    # Hora do dia
    hours = []
    for t in losers:
        ts = t.get("entry_ts") or ""
        try:
            hours.append(int(ts[11:13]))
        except (ValueError, IndexError):
            pass
    hour_summary = ""
    if hours:
        from collections import Counter
        top_hours = Counter(hours).most_common(3)
        hour_summary = f" Top horas de entrada (UTC): {[h for h, _ in top_hours]}."

    # Distribuicao por regime
    regimes = [t.get("regime") for t in losers]
    from collections import Counter as C
    regime_dist = dict(C(regimes))

    # Stop vs target outcome
    stops = sum(1 for t in losers if t.get("exit_reason") == "STOP")
    timeouts = sum(1 for t in losers if t.get("exit_reason") == "TIMEOUT")

    # Faixa de preco (proxy de fase do ciclo)
    prices = [t.get("entry_price", 0.0) for t in losers if t.get("entry_price", 0.0) > 0]
    price_summary = ""
    if prices:
        price_summary = f" Faixa de entry_price: {min(prices):.0f}-{max(prices):.0f}, mediana {sorted(prices)[len(prices)//2]:.0f}."

    return (
        f"n={n} perdas, avg_r={avg_r:+.3f}R. "
        f"Regimes: {regime_dist}. "
        f"Stops: {stops}/{n} ({100*stops/n:.0f}%), timeouts: {timeouts}/{n} ({100*timeouts/n:.0f}%)."
        + hour_summary + price_summary
    )


# ── Build full report ──────────────────────────────────────────────────────

def build_drilldown_report(trades_train: List[Dict], trades_holdout: List[Dict]) -> Dict:
    """Monta relatorio completo para BULL_STRONG e BULL_WEAK separadamente."""
    report: Dict = {
        "metricas_por_ano": {},
        "ano_pior": None,
        "razao": "",
        "padrao_trades_perdedores": "",
        "diagnostico": "MIXED",
        "train_baseline_aggregate": {},
    }

    # Train aggregate por regime
    train_filtered = filter_bull_regimes(trades_train)
    for regime in BULL_REGIMES:
        sub = [t for t in train_filtered if t.get("regime") == regime]
        report["train_baseline_aggregate"][regime] = metrics_for(sub)

    # Holdout split por ano x regime
    holdout_filtered = filter_bull_regimes(trades_holdout)
    by_year = split_by_year(holdout_filtered)

    per_year_per_regime: Dict[str, Dict[int, Dict]] = {r: {} for r in BULL_REGIMES}
    for year in HOLDOUT_YEARS:
        year_trades = by_year.get(year, [])
        report["metricas_por_ano"][str(year)] = {}
        for regime in BULL_REGIMES:
            sub = [t for t in year_trades if t.get("regime") == regime]
            m = metrics_for(sub)
            train_m = report["train_baseline_aggregate"][regime]
            cmp = compare_holdout_vs_train(train_m, m) if train_m["trades"] > 0 else {
                "delta_exp": 0.0, "delta_pf": 0.0, "degraded": False
            }
            report["metricas_por_ano"][str(year)][regime] = {**m, "delta_vs_train": cmp}
            per_year_per_regime[regime][year] = m

    # Diagnostico por regime (combinacao)
    diagnostics_per_regime = {}
    for regime in BULL_REGIMES:
        train_exp = report["train_baseline_aggregate"][regime]["exp"]
        per_year = per_year_per_regime[regime]
        if any(m["trades"] > 0 for m in per_year.values()):
            diagnostics_per_regime[regime] = diagnose_break_pattern(per_year, train_exp)
        else:
            diagnostics_per_regime[regime] = "INSUFFICIENT_DATA"
    report["diagnostico_por_regime"] = diagnostics_per_regime

    # Diagnostico agregado: se ambos sao STRUCTURAL_BREAK → STRUCTURAL_BREAK
    diag_values = [v for v in diagnostics_per_regime.values() if v != "INSUFFICIENT_DATA"]
    if not diag_values:
        report["diagnostico"] = "INSUFFICIENT_DATA"
    elif all(v == "STRUCTURAL_BREAK" for v in diag_values):
        report["diagnostico"] = "STRUCTURAL_BREAK"
    elif all(v == "MILD_REGIME_ARTIFACT" for v in diag_values):
        report["diagnostico"] = "MILD_REGIME_ARTIFACT"
    else:
        report["diagnostico"] = "MIXED"

    # Ano pior (pior exp agregado entre BULL_STRONG+BULL_WEAK)
    year_aggregates = {}
    for year in HOLDOUT_YEARS:
        year_trades = by_year.get(year, [])
        if year_trades:
            year_aggregates[year] = metrics_for(year_trades)

    if year_aggregates:
        worst_year = min(year_aggregates.keys(), key=lambda y: year_aggregates[y]["exp"])
        report["ano_pior"] = worst_year
        wm = year_aggregates[worst_year]
        report["razao"] = (
            f"Ano {worst_year}: exp={wm['exp']:+.3f}R, pf={wm['pf']:.2f}, "
            f"wr={wm['wr']:.1f}%, n={wm['trades']}. "
            f"Pior degradacao agregada entre os anos do holdout."
        )
        # Padrao de losers do pior ano
        worst_year_trades = by_year.get(worst_year, [])
        losers = [t for t in worst_year_trades if t.get("result_r", 0.0) < 0]
        report["padrao_trades_perdedores"] = extract_loser_pattern(losers)

    return report


# ── Schema validation ──────────────────────────────────────────────────────

def validate_schema(report: Dict) -> bool:
    required = {"metricas_por_ano", "ano_pior", "razao",
                "padrao_trades_perdedores", "diagnostico"}
    if not isinstance(report, dict) or not required.issubset(report.keys()):
        return False
    if report["diagnostico"] not in (
        "MILD_REGIME_ARTIFACT", "STRUCTURAL_BREAK", "MIXED", "INSUFFICIENT_DATA"
    ):
        return False
    return True
