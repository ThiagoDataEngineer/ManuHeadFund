"""
drilldown_2025.py -- Por que 2025 difere de 2018/2021/2022?

Extrai 6 features dia-a-dia para os 4 anos negativos, compara distribuicoes
2025 vs (2018+2021+2022) via Welch t-test. Identifica top features que separam.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Sequence, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from distribution_phase_detector import (  # noqa: E402
    _sma,
    ath_drawdown_pct,
    fetch_btc_daily_closes,
    nupl_proxy_score,
)


NEGATIVE_YEARS = [2018, 2021, 2022, 2025]
FEATURE_NAMES = [
    "ath_dd_pct",
    "sma200_dist_pct",
    "return_30d_pct",
    "ath_age_days",
    "nupl_proxy",
    "sma111_to_sma350_ratio",
]


# ──────────────────────────────────────────────────────────────────────────────
# Feature extraction (puras)
# ──────────────────────────────────────────────────────────────────────────────

def extract_daily_features(daily_closes: Sequence[float], history_window: int = 220) -> List[Dict]:
    """Para cada dia (a partir de history_window), computa 6 features."""
    out: List[Dict] = []
    closes = list(daily_closes)
    for i in range(history_window, len(closes)):
        window = closes[max(0, i - history_window):i + 1]
        current = closes[i]

        ath = max(window)
        ath_idx = max(j for j, v in enumerate(window) if v == ath)
        ath_age = len(window) - 1 - ath_idx

        ath_dd = (current / ath - 1.0) * 100.0 if ath > 0 else 0.0

        sma200 = _sma(window, 200)
        sma200_dist = (current / sma200 - 1.0) * 100.0 if sma200 else 0.0

        if i >= 30 and closes[i - 30] > 0:
            ret_30 = (current / closes[i - 30] - 1.0) * 100.0
        else:
            ret_30 = 0.0

        nupl = nupl_proxy_score(50, sma200_dist, 0.0)

        sma111 = _sma(window, 111)
        sma350 = _sma(window, 350) if len(window) >= 350 else None
        if sma111 and sma350 and sma350 > 0:
            pi_ratio = sma111 / sma350
        else:
            pi_ratio = 1.0  # neutro

        out.append({
            "ath_dd_pct": ath_dd,
            "sma200_dist_pct": sma200_dist,
            "return_30d_pct": ret_30,
            "ath_age_days": ath_age,
            "nupl_proxy": nupl,
            "sma111_to_sma350_ratio": pi_ratio,
        })
    return out


def aggregate_distribution_stats(features: Sequence[Dict], key: str) -> Dict:
    vals = [f[key] for f in features if key in f]
    if not vals:
        return {"mean": 0.0, "min": 0.0, "max": 0.0, "std": 0.0, "n": 0}
    n = len(vals)
    mean = sum(vals) / n
    var = sum((v - mean) ** 2 for v in vals) / max(1, n - 1)
    return {
        "mean": mean,
        "min": min(vals),
        "max": max(vals),
        "std": math.sqrt(var),
        "n": n,
    }


# ──────────────────────────────────────────────────────────────────────────────
# Welch's t-test (sem scipy)
# ──────────────────────────────────────────────────────────────────────────────

def welch_t_test(sample_a: Sequence[float], sample_b: Sequence[float]) -> Tuple[float, float]:
    """Welch's t-test. Retorna (t_stat, p_value approx).

    p-value via aproximacao normal (valido para n>=30 cada lado).
    """
    if len(sample_a) < 2 or len(sample_b) < 2:
        return 0.0, 1.0
    n_a, n_b = len(sample_a), len(sample_b)
    mean_a = sum(sample_a) / n_a
    mean_b = sum(sample_b) / n_b
    var_a = sum((x - mean_a) ** 2 for x in sample_a) / (n_a - 1)
    var_b = sum((x - mean_b) ** 2 for x in sample_b) / (n_b - 1)
    se = math.sqrt(var_a / n_a + var_b / n_b)
    if se == 0:
        return 0.0, 1.0
    t = (mean_a - mean_b) / se
    # Aproximacao normal two-tailed
    p = 2.0 * (1.0 - _normal_cdf(abs(t)))
    return t, p


def _normal_cdf(x: float) -> float:
    """CDF normal padrao via erf."""
    return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))


# ──────────────────────────────────────────────────────────────────────────────
# Comparacao + ranking
# ──────────────────────────────────────────────────────────────────────────────

def compare_distributions(
    features_a: Sequence[Dict],
    features_b: Sequence[Dict],
    feature_names: Sequence[str],
) -> Dict[str, Dict]:
    out: Dict[str, Dict] = {}
    for name in feature_names:
        vals_a = [f[name] for f in features_a if name in f]
        vals_b = [f[name] for f in features_b if name in f]
        t, p = welch_t_test(vals_a, vals_b)
        stats_a = aggregate_distribution_stats(features_a, name)
        stats_b = aggregate_distribution_stats(features_b, name)
        out[name] = {
            "t_stat": round(t, 4),
            "p_value": round(p, 6),
            "mean_a": round(stats_a["mean"], 4),
            "mean_b": round(stats_b["mean"], 4),
            "delta": round(stats_a["mean"] - stats_b["mean"], 4),
            "std_a": round(stats_a["std"], 4),
            "std_b": round(stats_b["std"], 4),
            "n_a": stats_a["n"],
            "n_b": stats_b["n"],
        }
    return out


def rank_top_separators(comparison: Dict[str, Dict], top_n: int = 5) -> List[Dict]:
    items = [{"feature": k, **v} for k, v in comparison.items()]
    items.sort(key=lambda r: r["p_value"])
    return items[:top_n]


# ──────────────────────────────────────────────────────────────────────────────
# Report builder
# ──────────────────────────────────────────────────────────────────────────────

def _format_hypothesis(top: List[Dict]) -> str:
    if not top:
        return "Sem dados suficientes para diferenciar 2025."
    lines = []
    for r in top[:3]:
        direction = "menor" if r["delta"] < 0 else "maior"
        lines.append(
            f"{r['feature']}: 2025 ({r['mean_a']:.2f}) {direction} que 2018/21/22 "
            f"({r['mean_b']:.2f}), delta={r['delta']:.2f}, p={r['p_value']:.4g}"
        )
    return "Em 2025, " + "; ".join(lines) + "."


def _format_recommendation(top: List[Dict]) -> str:
    feats = [r["feature"] for r in top[:3]]
    parts = []
    if "ath_dd_pct" in feats:
        parts.append(
            "ATH DD em 2025 e mais shallow (-20 a -30%) versus -50 a -80% nos demais; "
            "DXY/M2 macro pode confirmar regime nao-capitulacao"
        )
    if "sma200_dist_pct" in feats or "nupl_proxy" in feats:
        parts.append(
            "Distancia SMA200 ainda alta (price > SMA200) em 2025: indica bull intacto. "
            "Sinal externo necessario: ETF flows + funding rate prolongado (>0.05%)"
        )
    if "return_30d_pct" in feats:
        parts.append(
            "Momentum 30d em 2025 mais positivo (recuperando) vs sustentadamente negativo. "
            "Adicionar feature: rolling 60d-Sharpe negativo + breadth altcoins"
        )
    if not parts:
        parts.append("Considerar features macro: DXY trend, M2 growth YoY, funding rate persistente.")
    return " | ".join(parts)


def build_report(
    features_2025: List[Dict],
    features_others_combined: List[Dict],
    feature_names_used: Sequence[str],
) -> Dict:
    comparison = compare_distributions(features_2025, features_others_combined, feature_names_used)
    top5 = rank_top_separators(comparison, top_n=5)
    distinctas = [
        {"feature": k, "p_value": v["p_value"], "delta": v["delta"],
         "mean_2025": v["mean_a"], "mean_others": v["mean_b"]}
        for k, v in comparison.items()
        if v["p_value"] < 0.05
    ]
    distinctas.sort(key=lambda r: r["p_value"])

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "features_distinctas_2025": distinctas,
        "top5_separadoras": top5,
        "hipotese_textual": _format_hypothesis(top5),
        "recomendacao": _format_recommendation(top5),
        "full_comparison": comparison,
        "n_samples": {
            "2025": len(features_2025),
            "others_combined": len(features_others_combined),
        },
    }


# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

def _features_for_year(closes_all: List[float], year: int) -> List[Dict]:
    end_date = datetime.now(timezone.utc).date()
    n_total = len(closes_all)
    idx_dates = [end_date - timedelta(days=(n_total - 1 - i)) for i in range(n_total)]
    year_idxs = [i for i, d in enumerate(idx_dates) if d.year == year]
    if not year_idxs:
        return []
    first = year_idxs[0]
    last = year_idxs[-1]
    start = max(0, first - 220)
    sub = closes_all[start:last + 1]
    all_feats = extract_daily_features(sub, history_window=220)
    # Filtra apenas dias do ano
    n_history = first - start
    # Em extract, primeiro feature corresponde ao index history_window = 220 de sub.
    # Se start = first - 220, entao sub[220] = closes_all[first] = primeiro dia do ano.
    # So pegamos dias do ano: indices em all_feats sao 0-indexed em (sub - 220)
    # primeiro feature = sub[220] = first day of year (se start = first - 220 funcionou)
    # Mas se first < 220, comecamos no day 220 que ja eh dentro do ano. Adjust.
    if start == 0 and first < 220:
        # Sem historia suficiente; pega o que conseguir
        n_year_days = last - first + 1
        return all_feats[:n_year_days]
    return all_feats[:last - first + 1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "journal", "task1b_drilldown_2025.json"
    ))
    args = parser.parse_args()

    print("[1/3] Carregando closes BTC diarios (Bitstamp)...")
    closes = fetch_btc_daily_closes()
    print(f"  closes={len(closes)}")

    print("[2/3] Extraindo features por ano...")
    feats_2025 = _features_for_year(closes, 2025)
    feats_2018 = _features_for_year(closes, 2018)
    feats_2021 = _features_for_year(closes, 2021)
    feats_2022 = _features_for_year(closes, 2022)
    feats_others = feats_2018 + feats_2021 + feats_2022
    print(f"  2025: {len(feats_2025)} dias")
    print(f"  2018+2021+2022: {len(feats_others)} dias")

    print("[3/3] Comparando distribuicoes...")
    report = build_report(feats_2025, feats_others, FEATURE_NAMES)
    # Acrescenta breakdown por ano (sem comparar)
    report["per_year_stats"] = {
        "2018": {name: aggregate_distribution_stats(feats_2018, name) for name in FEATURE_NAMES},
        "2021": {name: aggregate_distribution_stats(feats_2021, name) for name in FEATURE_NAMES},
        "2022": {name: aggregate_distribution_stats(feats_2022, name) for name in FEATURE_NAMES},
        "2025": {name: aggregate_distribution_stats(feats_2025, name) for name in FEATURE_NAMES},
    }

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print(f"\n[OK] saved: {args.output}\n")

    print("Top 5 separadoras:")
    for r in report["top5_separadoras"]:
        print(f"  {r['feature']}: p={r['p_value']:.4g}, "
              f"mean_2025={r['mean_a']:.3f}, mean_others={r['mean_b']:.3f}, delta={r['delta']:.3f}")
    print(f"\nHipotese: {report['hipotese_textual']}")
    print(f"\nRecomendacao: {report['recomendacao']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
