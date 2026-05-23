"""TDD para walkforward_halving.py — halving-aware splits para BTC."""
from __future__ import annotations

import os
import sys
import pytest
from datetime import date

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from walkforward_halving import (  # noqa: E402
    HalvingSplitter,
    HalvingWindow,
    build_halving_windows,
    split_trades_by_halving,
    compute_cross_halving_pf,
    parse_halving_arg,
    DEFAULT_HALVING_DATES,
)


def test_default_halving_dates_count():
    """Devem existir 4 halvings: 2012, 2016, 2020, 2024."""
    assert len(DEFAULT_HALVING_DATES) == 4
    assert "2012-11-28" in DEFAULT_HALVING_DATES
    assert "2024-04-19" in DEFAULT_HALVING_DATES


def test_splitter_generates_window_per_halving_in_range():
    """Range 2014-2025 deve gerar 3 janelas (2016, 2020, 2024 — 2012 fora)."""
    s = HalvingSplitter()
    wins = s.generate("2014-01-01", "2025-12-31", pre_months=6, post_months=12)
    assert len(wins) == 3
    halving_dates = [w.halving_date for w in wins]
    assert "2016-07-09" in halving_dates
    assert "2020-05-11" in halving_dates
    assert "2024-04-19" in halving_dates


def test_splitter_respects_pre_post_months():
    """Pre/post months devem produzir janela proporcional centrada no halving."""
    s = HalvingSplitter(halving_dates=["2020-05-11"])
    wins = s.generate("2018-01-01", "2022-12-31", pre_months=6, post_months=12)
    assert len(wins) == 1
    w = wins[0]
    # 2020-05-11 - 6m = 2019-11-11
    assert w.pre_start == "2019-11-11"
    # 2020-05-11 + 12m = 2021-05-11
    assert w.post_end == "2021-05-11"
    assert w.pre_end == "2020-05-11"
    assert w.post_start == "2020-05-11"


def test_splitter_clamps_to_global_range():
    """Se halving cai próximo da borda, janela deve clampar."""
    s = HalvingSplitter(halving_dates=["2024-04-19"])
    wins = s.generate("2024-01-01", "2024-12-31", pre_months=12, post_months=12)
    assert len(wins) == 1
    w = wins[0]
    # pre_start clampa em 2024-01-01 (ao invés de 2023-04-19)
    assert w.pre_start == "2024-01-01"
    # post_end clampa em 2024-12-31
    assert w.post_end == "2024-12-31"


def test_splitter_skips_halvings_outside_range():
    """Halving fora do range global é ignorado."""
    s = HalvingSplitter()
    wins = s.generate("2017-01-01", "2019-12-31", pre_months=6, post_months=12)
    halvings = [w.halving_date for w in wins]
    assert "2012-11-28" not in halvings
    assert "2020-05-11" not in halvings  # post-range
    # Note: 2016-07-09 também está fora range start


def test_splitter_invalid_negative_months():
    """pre/post months negativos lança ValueError."""
    s = HalvingSplitter(halving_dates=["2020-05-11"])
    with pytest.raises(ValueError):
        s.generate("2019-01-01", "2021-12-31", pre_months=-1, post_months=12)


def test_splitter_zero_both_months_raises():
    """Janela degenerada lança ValueError."""
    s = HalvingSplitter(halving_dates=["2020-05-11"])
    with pytest.raises(ValueError):
        s.generate("2019-01-01", "2021-12-31", pre_months=0, post_months=0)


def test_split_trades_by_halving_basic():
    """Trades pre/post halving são separados corretamente."""
    trades = [
        {"ts": date(2020, 3, 1), "r": 1.5},
        {"ts": date(2020, 5, 1), "r": -1.0},
        {"ts": date(2020, 5, 15), "r": 2.0},
        {"ts": date(2020, 8, 1), "r": 1.0},
    ]
    window = HalvingWindow(
        halving_id=2, halving_date="2020-05-11",
        window_start="2020-01-01", window_end="2020-12-31",
        pre_start="2020-01-01", pre_end="2020-05-11",
        post_start="2020-05-11", post_end="2020-12-31",
    )
    split = split_trades_by_halving(trades, window)
    assert len(split["pre"]) == 2
    assert len(split["post"]) == 2


def test_compute_cross_halving_pf_persisted():
    """PF pre ~ PF post => EDGE_PERSISTED."""
    pre = [2.0, -1.0, 2.0, -1.0]  # PF = 4/2 = 2.0
    post = [2.0, -1.0, 2.0, -1.0]
    r = compute_cross_halving_pf(pre, post)
    assert r["pf_pre"] == 2.0
    assert r["pf_post"] == 2.0
    assert r["verdict"] == "EDGE_PERSISTED"


def test_compute_cross_halving_pf_degraded():
    """PF post << PF pre => EDGE_DEGRADED ou EDGE_BROKEN."""
    pre = [3.0, -1.0, 3.0, -1.0]  # PF = 6/2 = 3.0
    post = [1.5, -1.0, 1.5, -1.0]  # PF = 3/2 = 1.5
    r = compute_cross_halving_pf(pre, post)
    assert r["pf_pre"] == 3.0
    assert r["pf_post"] == 1.5
    assert r["verdict"] in ["EDGE_DEGRADED", "EDGE_BROKEN"]


def test_build_halving_windows_returns_dicts():
    """Helper top-level retorna list of dicts."""
    out = build_halving_windows("2014-01-01", "2025-12-31")
    assert isinstance(out, list)
    assert all(isinstance(w, dict) for w in out)
    assert "halving_date" in out[0]
    assert "pre_start" in out[0]


def test_parse_halving_arg_default_empty():
    """Empty arg returns default."""
    out = parse_halving_arg("")
    assert out == list(DEFAULT_HALVING_DATES)


def test_parse_halving_arg_csv():
    """CSV halving dates parsed correctly."""
    out = parse_halving_arg("2020-05-11,2024-04-19")
    assert out == ["2020-05-11", "2024-04-19"]
