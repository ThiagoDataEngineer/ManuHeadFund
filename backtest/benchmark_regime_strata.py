"""benchmark_regime_strata.py — Analise estratificada de performance por regime.

Toma trades com regime+direction+result_r e produz:
  - Metricas LONG/SHORT por regime (n, exp, pf)
  - Melhor direcao por regime (LONG/SHORT/BOTH/AVOID)
  - Edge strength categorizado (STRONG/MEDIUM/WEAK/NONE)
  - JSON final com criterio GO/NO-GO

Usado para decisao multi-regime: "em que regime opero e em que direcao?"
"""
from typing import List, Dict


# Edge strength thresholds (em R)
EDGE_STRONG_MIN = 0.50
EDGE_MEDIUM_MIN = 0.30
EDGE_WEAK_MIN = 0.10

# Best direction thresholds
DIRECTION_MIN_EDGE = 0.30   # exp >= 0.30R para considerar "tem edge"

# GO criterion: minimo de regimes com edge MEDIUM ou maior
GO_MIN_REGIMES_WITH_EDGE = 3


def _calc_metrics(rs: List[float]) -> Dict:
    """Calcula trades/exp/pf de uma lista de resultados em R."""
    if not rs:
        return {"trades": 0, "exp": 0.0, "pf": 0.0}
    wins = [r for r in rs if r > 0]
    losses = [r for r in rs if r < 0]
    gross_win = sum(wins)
    gross_loss = abs(sum(losses))
    pf = gross_win / gross_loss if gross_loss > 0 else (float("inf") if gross_win > 0 else 0.0)
    return {
        "trades": len(rs),
        "exp": sum(rs) / len(rs),
        "pf": pf,
    }


def metrics_per_regime(trades: List[Dict]) -> Dict:
    """Agrupa trades por regime e direcao, retorna metricas isoladas.
    trades: [{regime, direction, result_r}, ...]
    """
    grouped: Dict[str, Dict[str, List[float]]] = {}
    for t in trades:
        reg = t["regime"]
        direc = t["direction"]
        grouped.setdefault(reg, {}).setdefault(direc, []).append(t["result_r"])

    result: Dict[str, Dict[str, Dict]] = {}
    for reg, by_dir in grouped.items():
        result[reg] = {}
        for direc, rs in by_dir.items():
            result[reg][direc] = _calc_metrics(rs)
    return result


def best_direction(long_exp: float, short_exp: float, min_edge: float = DIRECTION_MIN_EDGE) -> str:
    """Decide melhor direcao no regime:
      BOTH  — ambos >= min_edge
      LONG  — long >= min_edge AND long > short
      SHORT — short >= min_edge AND short > long
      AVOID — nenhum >= min_edge
    """
    long_has = long_exp >= min_edge
    short_has = short_exp >= min_edge

    if long_has and short_has:
        return "BOTH"
    if long_has and long_exp > short_exp:
        return "LONG"
    if short_has and short_exp > long_exp:
        return "SHORT"
    return "AVOID"


def edge_strength(exp: float) -> str:
    """Categoriza edge:
      STRONG >= +0.50R
      MEDIUM >= +0.30R
      WEAK   >= +0.10R
      NONE   < +0.10R (inclui negativos)
    """
    if exp >= EDGE_STRONG_MIN:
        return "STRONG"
    if exp >= EDGE_MEDIUM_MIN:
        return "MEDIUM"
    if exp >= EDGE_WEAK_MIN:
        return "WEAK"
    return "NONE"


def aggregate_results(regime_days: Dict[str, int], regime_metrics: Dict[str, Dict]) -> Dict:
    """Agrega tudo num JSON com schema:
      {by_regime: [...], go_criterion: {...}}
    """
    total_days = sum(regime_days.values()) if regime_days else 0
    by_regime = []

    for regime, days_total in regime_days.items():
        m = regime_metrics.get(regime, {})
        long_m = m.get("LONG", {"trades": 0, "exp": 0.0, "pf": 0.0})
        short_m = m.get("SHORT", {"trades": 0, "exp": 0.0, "pf": 0.0})
        long_exp = long_m["exp"]
        short_exp = short_m["exp"]
        best = best_direction(long_exp, short_exp)
        # edge_strength usa o lado dominante (ou 0 se AVOID)
        dom_exp = max(long_exp, short_exp) if best != "AVOID" else 0.0
        strength = edge_strength(dom_exp)

        by_regime.append({
            "regime": regime,
            "days_total": days_total,
            "days_pct": (days_total / total_days * 100.0) if total_days > 0 else 0.0,
            "long_metrics": long_m,
            "short_metrics": short_m,
            "best_direction": best,
            "edge_strength": strength,
        })

    # GO criterion: minimo de N regimes com edge MEDIUM+
    regimes_with_edge = sum(1 for r in by_regime if r["edge_strength"] in ("STRONG", "MEDIUM"))
    passed = regimes_with_edge >= GO_MIN_REGIMES_WITH_EDGE

    return {
        "by_regime": by_regime,
        "go_criterion": {
            "rule": f">= {GO_MIN_REGIMES_WITH_EDGE} regimes com edge MEDIUM+ (exp >= +0.30R)",
            "regimes_with_edge": regimes_with_edge,
            "regimes_total": len(by_regime),
            "passed": passed,
        },
    }


def validate_json_schema(data: Dict) -> bool:
    """Validacao defensiva do schema esperado."""
    if not isinstance(data, dict):
        return False
    if "by_regime" not in data or "go_criterion" not in data:
        return False
    if not isinstance(data["by_regime"], list):
        return False
    required_fields_by_regime = {
        "regime", "days_total", "days_pct",
        "long_metrics", "short_metrics",
        "best_direction", "edge_strength",
    }
    for r in data["by_regime"]:
        if not required_fields_by_regime.issubset(r.keys()):
            return False
        for mkey in ("long_metrics", "short_metrics"):
            if not {"trades", "exp", "pf"}.issubset(r[mkey].keys()):
                return False
    required_go = {"rule", "regimes_with_edge", "regimes_total", "passed"}
    if not required_go.issubset(data["go_criterion"].keys()):
        return False
    return True
