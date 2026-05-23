"""
test_drilldown_2025.py -- TDD para drilldown: por que 2025 difere de 2018/2021/2022.
"""
from __future__ import annotations

import json
import os
import sys

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from drilldown_2025 import (  # noqa: E402
    FEATURE_NAMES,
    NEGATIVE_YEARS,
    aggregate_distribution_stats,
    build_report,
    compare_distributions,
    extract_daily_features,
    rank_top_separators,
    welch_t_test,
)


def test_feature_names_completeness():
    assert "ath_dd_pct" in FEATURE_NAMES
    assert "sma200_dist_pct" in FEATURE_NAMES
    assert "return_30d_pct" in FEATURE_NAMES
    assert "ath_age_days" in FEATURE_NAMES
    assert "nupl_proxy" in FEATURE_NAMES
    assert len(FEATURE_NAMES) >= 5


def test_extract_daily_features_returns_dict_per_day():
    closes = [100.0 + i * 0.5 for i in range(300)]
    feats = extract_daily_features(closes, history_window=220)
    # 300-220 = 80 dias possiveis (excluindo o ultimo i+1)
    assert len(feats) > 50
    for f in feats:
        for name in FEATURE_NAMES:
            assert name in f


def test_welch_t_test_identifies_difference():
    # Distribuicoes claramente diferentes
    a = [1.0, 1.2, 0.9, 1.1, 1.0] * 20
    b = [5.0, 5.2, 4.9, 5.1, 5.0] * 20
    t, p = welch_t_test(a, b)
    assert p < 0.001  # altamente significativo
    assert abs(t) > 5


def test_welch_t_test_similar_distributions():
    a = [1.0, 1.1, 0.9, 1.0] * 25
    b = [1.0, 1.0, 1.1, 0.9] * 25
    _, p = welch_t_test(a, b)
    assert p > 0.05  # nao significativo


def test_compare_distributions_returns_pvalues():
    feats_a = [{"x": v, "y": v * 2} for v in [1.0, 1.1, 0.9, 1.0, 1.05] * 20]
    feats_b = [{"x": v + 5, "y": v * 2 + 10} for v in [1.0, 1.1, 0.9, 1.0, 1.05] * 20]
    result = compare_distributions(feats_a, feats_b, feature_names=["x", "y"])
    assert "x" in result
    assert "y" in result
    assert result["x"]["p_value"] < 0.001
    assert "mean_a" in result["x"]
    assert "mean_b" in result["x"]
    assert "delta" in result["x"]


def test_rank_top_separators_ordered_by_pvalue():
    comparison = {
        "feat_a": {"p_value": 0.001, "delta": 5.0, "mean_a": 1, "mean_b": 6},
        "feat_b": {"p_value": 0.5, "delta": 0.2, "mean_a": 1, "mean_b": 1.2},
        "feat_c": {"p_value": 0.01, "delta": -3.0, "mean_a": 5, "mean_b": 2},
    }
    top = rank_top_separators(comparison, top_n=2)
    assert top[0]["feature"] == "feat_a"   # menor p
    assert top[1]["feature"] == "feat_c"
    assert len(top) == 2


def test_aggregate_distribution_stats():
    feats = [{"x": 1.0}, {"x": 2.0}, {"x": 3.0}]
    stats = aggregate_distribution_stats(feats, "x")
    assert stats["mean"] == 2.0
    assert stats["min"] == 1.0
    assert stats["max"] == 3.0


def test_negative_years_constant():
    assert 2018 in NEGATIVE_YEARS
    assert 2021 in NEGATIVE_YEARS
    assert 2022 in NEGATIVE_YEARS
    assert 2025 in NEGATIVE_YEARS
    assert len(NEGATIVE_YEARS) == 4


def test_build_report_schema():
    # Mock dados pequenos
    feats_2025 = [{"ath_dd_pct": -15, "return_30d_pct": -5}] * 50
    feats_others = [{"ath_dd_pct": -60, "return_30d_pct": -25}] * 150
    report = build_report(
        features_2025=feats_2025,
        features_others_combined=feats_others,
        feature_names_used=["ath_dd_pct", "return_30d_pct"],
    )
    assert "features_distinctas_2025" in report
    assert "top5_separadoras" in report
    assert "hipotese_textual" in report
    assert "recomendacao" in report
    json.dumps(report)  # serializa sem erro
