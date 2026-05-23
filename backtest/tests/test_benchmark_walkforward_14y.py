"""
test_benchmark_walkforward_14y.py -- TDD para Walk-forward Rolling Validation.

Contrato testado (modulo: benchmark_walkforward_14y):
    generate_windows(start, end, window_months, step_months) -> list[dict]
    compute_window_metrics(trades_r) -> dict {trades,exp,pf,max_dd_r}
    ergodicity_score(expectancies) -> float 0..1
    positive_windows_pct(metrics_list) -> float 0..100
    max_losing_streak_windows(expectancies) -> int
    identify_worst_window(windows) -> dict
    aggregate_metrics(windows) -> dict
    run_walkforward(windows_input, start, end) -> dict (JSON schema)
"""
from __future__ import annotations

import json
import os
import sys
from datetime import date

import numpy as np
import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from benchmark_walkforward_14y import (  # noqa: E402
    aggregate_metrics,
    compute_window_metrics,
    ergodicity_score,
    generate_windows,
    identify_worst_window,
    max_losing_streak_windows,
    positive_windows_pct,
    run_walkforward,
)


# ─────────────────────────────────────────────────────────────────────────────
# 1. Rolling window generation: 2014-2025 / 12mo / 6mo step -> ~22 windows
# ─────────────────────────────────────────────────────────────────────────────
def test_rolling_window_generation():
    windows = generate_windows(
        start=date(2014, 1, 1), end=date(2025, 12, 31),
        window_months=12, step_months=6,
    )
    # 144 meses totais; (144-12)/6 + 1 = 23, mas o ultimo pode nao caber.
    assert 21 <= len(windows) <= 23, f"esperado ~22, veio {len(windows)}"
    # Overlap 50%: cada janela comeca 6 meses depois da anterior
    for prev, curr in zip(windows, windows[1:]):
        delta = (curr["start"].year - prev["start"].year) * 12 + (curr["start"].month - prev["start"].month)
        assert delta == 6
    # Cada janela tem 12 meses
    for w in windows:
        diff = (w["end"].year - w["start"].year) * 12 + (w["end"].month - w["start"].month)
        assert 11 <= diff <= 12


# ─────────────────────────────────────────────────────────────────────────────
# 2. Janelas parciais (periodo < window_months) nao quebram
# ─────────────────────────────────────────────────────────────────────────────
def test_handles_partial_windows():
    windows = generate_windows(
        start=date(2024, 1, 1), end=date(2024, 8, 31),  # 8 meses
        window_months=12, step_months=6,
    )
    assert windows == [] or all(w.get("partial", False) for w in windows)


# ─────────────────────────────────────────────────────────────────────────────
# 3. Ergodicity score: alto quando consistente, baixo quando misto
# ─────────────────────────────────────────────────────────────────────────────
def test_ergodicity_score_consistency_high():
    exps = [1.0] * 10                       # constante +1R
    assert ergodicity_score(exps) >= 0.9


def test_ergodicity_score_consistency_low():
    exps = [2.0, 2.0, 2.0, 2.0, 2.0, -2.0, -2.0, -2.0, -2.0, -2.0]
    assert ergodicity_score(exps) <= 0.3


# ─────────────────────────────────────────────────────────────────────────────
# 4. Pct janelas positivas
# ─────────────────────────────────────────────────────────────────────────────
def test_positive_windows_pct():
    metrics = [{"exp": x} for x in (
        [1.0] * 16 + [-1.0] * 6              # 16/22 positivas
    )]
    pct = positive_windows_pct(metrics)
    assert pct == pytest.approx(16 / 22 * 100, abs=0.1)


# ─────────────────────────────────────────────────────────────────────────────
# 5. Maior streak de janelas negativas
# ─────────────────────────────────────────────────────────────────────────────
def test_max_losing_streak_windows():
    exps = [1, 1, -1, -1, -1, 1, -1, -1, -1, -1, 1]
    assert max_losing_streak_windows(exps) == 4


def test_max_losing_streak_all_positive_is_zero():
    assert max_losing_streak_windows([1, 1, 2, 0.5]) == 0


# ─────────────────────────────────────────────────────────────────────────────
# 6. Pior janela: argmin(exp) + macro context
# ─────────────────────────────────────────────────────────────────────────────
def test_worst_window_identified():
    windows = [
        {"id": "w1", "period_start": date(2022, 1, 1), "period_end": date(2022, 12, 31),
         "exp": -1.5, "regime_dominant": "bear"},
        {"id": "w2", "period_start": date(2023, 1, 1), "period_end": date(2023, 12, 31),
         "exp":  0.8, "regime_dominant": "bull"},
        {"id": "w3", "period_start": date(2024, 1, 1), "period_end": date(2024, 12, 31),
         "exp":  0.2, "regime_dominant": "sideways"},
    ]
    worst = identify_worst_window(windows)
    assert worst["id"] == "w1"
    assert "context" in worst
    assert worst["exp"] == -1.5


# ─────────────────────────────────────────────────────────────────────────────
# 7. Nao ha lookahead: window N usa apenas trades cujo timestamp <= window_end
# ─────────────────────────────────────────────────────────────────────────────
def test_no_lookahead_between_windows():
    all_trades = [
        {"ts": date(2022, 6, 1),  "r": 1.0},
        {"ts": date(2022, 12, 1), "r": -0.5},
        {"ts": date(2023, 3, 1),  "r": 2.0},  # FORA da janela 2022
        {"ts": date(2023, 8, 1),  "r": -1.0},
    ]
    win = {"id": "w1", "start": date(2022, 1, 1), "end": date(2022, 12, 31)}
    # Filtra os trades pertencentes a esta janela (helper interno do walkforward)
    from benchmark_walkforward_14y import filter_trades_for_window
    inside = filter_trades_for_window(all_trades, win)
    rs = [t["r"] for t in inside]
    assert rs == [1.0, -0.5]


# ─────────────────────────────────────────────────────────────────────────────
# 8. Aggregate metrics: mean, std, ergodicity
# ─────────────────────────────────────────────────────────────────────────────
def test_aggregate_metrics():
    windows = [{"exp": v} for v in [1.0, 0.5, -0.2, 0.8, 1.2, -0.5, 0.6]]
    agg = aggregate_metrics(windows)
    arr = np.array([w["exp"] for w in windows])
    assert agg["expectancy_mean"] == pytest.approx(float(arr.mean()), rel=1e-3)
    assert agg["expectancy_std"]  == pytest.approx(float(arr.std()),  rel=1e-3)
    assert 0.0 <= agg["ergodicity_score"] <= 1.0
    assert "positive_windows_pct"     in agg
    assert "max_losing_streak_windows" in agg


# ─────────────────────────────────────────────────────────────────────────────
# 9. JSON schema valido (end-to-end)
# ─────────────────────────────────────────────────────────────────────────────
def test_json_schema_valid():
    # Input ja com windows + trades por janela
    windows_input = [
        {"id": f"w{i:02d}",
         "period_start": date(2014 + i // 2, 1 + (i % 2) * 6, 1).isoformat(),
         "period_end":   date(2014 + i // 2 + 1, (i % 2) * 6 or 12, 28).isoformat(),
         "trades_r":     [1.0, -0.5, 1.5, -0.3, 0.8, -0.8, 1.2, -0.4],
         "regime_dominant": "bull" if i % 2 == 0 else "bear"}
        for i in range(8)
    ]
    out = run_walkforward(windows_input, start="2014-01-01", end="2025-12-31")

    assert "windows" in out and len(out["windows"]) == 8
    for w in out["windows"]:
        for k in ("id", "period", "trades", "exp", "pf", "max_dd_r", "regime_dominant"):
            assert k in w, f"falta {k} em window {w.get('id')}"

    cons = out["consistency"]
    for k in ("positive_windows_pct", "expectancy_mean", "expectancy_std",
              "ergodicity_score", "max_losing_streak_windows"):
        assert k in cons

    worst = out["worst_window"]
    for k in ("period", "exp", "context"):
        assert k in worst

    glc = out["go_criterion"]
    for k in ("rule", "passed"):
        assert k in glc

    # Deve serializar para JSON puro
    parsed = json.loads(json.dumps(out, default=str))
    assert parsed["windows"][0]["id"] == "w00"


# ─────────────────────────────────────────────────────────────────────────────
# Bonus: compute_window_metrics individual
# ─────────────────────────────────────────────────────────────────────────────
def test_compute_window_metrics_basics():
    m = compute_window_metrics([1.0, -0.5, 2.0, -1.0, 1.5])
    assert m["trades"] == 5
    assert m["exp"] == pytest.approx((1.0 - 0.5 + 2.0 - 1.0 + 1.5) / 5)
    assert m["pf"]  >  0
    assert m["max_dd_r"] >= 0


def test_compute_window_metrics_empty():
    m = compute_window_metrics([])
    assert m["trades"] == 0
    assert m["exp"]  == 0.0
    assert m["pf"]   == 0.0
    assert m["max_dd_r"] == 0.0
