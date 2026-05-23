"""
test_recalibrate_distribution_filter.py -- TDD para recalibracao do detector.

Train 2014-2022, holdout 2023-2025. F1 score dia-a-dia.
"""
from __future__ import annotations

import os
import sys

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from recalibrate_distribution_filter import (  # noqa: E402
    DETECTOR_PARAM_GRID,
    DecisionResult,
    GROUND_TRUTH_LABELS,
    decide_outcome,
    detect_with_config,
    evaluate_f1,
    grid_search_train,
    is_holdout_year,
    is_train_year,
)


def test_year_partition():
    assert is_train_year(2014) is True
    assert is_train_year(2022) is True
    assert is_train_year(2023) is False
    assert is_holdout_year(2023) is True
    assert is_holdout_year(2025) is True
    assert is_holdout_year(2022) is False


def test_ground_truth_labels_correct():
    # User spec
    assert GROUND_TRUTH_LABELS[2014] == "SAFE"
    assert GROUND_TRUTH_LABELS[2018] == "DANGER"
    assert GROUND_TRUTH_LABELS[2021] == "DANGER"
    assert GROUND_TRUTH_LABELS[2022] == "DANGER"
    assert GROUND_TRUTH_LABELS[2025] == "DANGER"
    # Anos positivos no baseline 14y
    assert GROUND_TRUTH_LABELS[2020] == "SAFE"
    assert GROUND_TRUTH_LABELS[2024] == "SAFE"


def test_detect_with_config_returns_state():
    closes = [100.0 + i * 0.1 for i in range(250)]
    cfg = {
        "ath_dd_severe_weight": 25,
        "ath_dd_severe_threshold": -25.0,
        "danger_threshold": 70,
        "warning_threshold": 40,
        "semantic_ratio": 0.85,
    }
    state = detect_with_config(closes, cfg)
    assert state in {"SAFE", "WARNING", "DANGER", "BEAR_CONFIRMED"}


def test_evaluate_f1_perfect_classification():
    # 100 predictions match 100 labels -> F1 = 1.0
    preds = ["DANGER"] * 50 + ["SAFE"] * 50
    labels = ["DANGER"] * 50 + ["SAFE"] * 50
    f1 = evaluate_f1(preds, labels)
    assert f1 == pytest.approx(1.0, abs=1e-6)


def test_evaluate_f1_zero_classification():
    # All predictions wrong
    preds = ["SAFE"] * 50 + ["DANGER"] * 50
    labels = ["DANGER"] * 50 + ["SAFE"] * 50
    f1 = evaluate_f1(preds, labels)
    assert f1 == pytest.approx(0.0, abs=1e-6)


def test_evaluate_f1_mixed():
    # 30 TP, 10 FP, 20 FN: precision=30/40=0.75, recall=30/50=0.60, f1=0.667
    preds = ["DANGER"] * 40 + ["SAFE"] * 60
    labels = ["DANGER"] * 30 + ["SAFE"] * 10 + ["DANGER"] * 20 + ["SAFE"] * 40
    f1 = evaluate_f1(preds, labels)
    assert f1 == pytest.approx(2 * 0.75 * 0.60 / (0.75 + 0.60), abs=1e-3)


def test_grid_search_returns_best_config():
    # Grid pequeno mock
    fake_grid = [
        {"ath_dd_severe_weight": 20, "ath_dd_severe_threshold": -25, "danger_threshold": 60,
         "warning_threshold": 40, "semantic_ratio": 0.85},
        {"ath_dd_severe_weight": 25, "ath_dd_severe_threshold": -25, "danger_threshold": 70,
         "warning_threshold": 40, "semantic_ratio": 0.85},
    ]
    # Synthetic train data: 2 years with 100 days each
    train_data = {
        2018: ([100.0 - i * 0.5 for i in range(220 + 100)], "DANGER"),
        2014: ([100.0 + i * 0.5 for i in range(220 + 100)], "SAFE"),
    }
    best_cfg, best_f1, all_results = grid_search_train(train_data, fake_grid)
    assert "ath_dd_severe_weight" in best_cfg
    assert 0.0 <= best_f1 <= 1.0
    assert len(all_results) == len(fake_grid)


def test_decide_outcome_pass():
    r = decide_outcome(f1_train=0.85, f1_holdout=0.75, positive_years_pct=82.0)
    assert r.decision == "PASS"


def test_decide_outcome_fail_overfit():
    # Train alto, holdout baixo
    r = decide_outcome(f1_train=0.90, f1_holdout=0.55, positive_years_pct=78.0)
    assert r.decision == "FAIL_OVERFIT"


def test_decide_outcome_fail_insufficient():
    # Holdout OK mas positive_years baixo
    r = decide_outcome(f1_train=0.75, f1_holdout=0.72, positive_years_pct=70.0)
    assert r.decision == "FAIL_INSUFFICIENT"


def test_param_grid_not_empty():
    assert len(DETECTOR_PARAM_GRID) > 5
    # Cada item tem todas as chaves necessarias
    for cfg in DETECTOR_PARAM_GRID:
        assert "ath_dd_severe_weight" in cfg
        assert "danger_threshold" in cfg
        assert "warning_threshold" in cfg
        assert "semantic_ratio" in cfg
