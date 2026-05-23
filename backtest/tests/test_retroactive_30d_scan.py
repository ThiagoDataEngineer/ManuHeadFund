"""
test_retroactive_30d_scan.py - TDD para retroactive_30d_scan.py
"""
import pytest

from retroactive_30d_scan import (
    find_bar_at_days_ago,
    simulate_signal_at_bar,
    classify_outcome_so_far,
    build_retroactive_report,
)


def _candle(ts, close):
    return {"ts": ts, "open": close, "high": close * 1.005, "low": close * 0.995,
            "close": close, "volume": 1000.0}


def _series_uptrend(n=300, start=100.0, step=0.5):
    """Serie ascendente, candle horario 2024."""
    out = []
    for i in range(n):
        ts = f"2024-01-{(i // 24) + 1:02d}T{i % 24:02d}:00:00+00:00"
        out.append(_candle(ts, start + i * step))
    return out


# ============================================================================
# 1) find_bar_at_days_ago
# ============================================================================
def test_find_bar_at_days_ago_returns_correct_index():
    """720 candles 1h = 30 dias atras."""
    candles = _series_uptrend(n=1000)
    idx = find_bar_at_days_ago(candles, days=30, period_hours=1)
    # idx target = last - (30*24) = 1000-1-720 = 279
    assert idx == 279


def test_find_bar_returns_none_if_not_enough_history():
    candles = _series_uptrend(n=100)  # apenas 100 bars
    idx = find_bar_at_days_ago(candles, days=30, period_hours=1)
    assert idx is None


# ============================================================================
# 2) simulate_signal_at_bar
# ============================================================================
def test_simulate_signal_at_bar_uptrend_strong_signal():
    """Em uptrend forte, bar 30d atras deve gerar sinal acionavel ou NEUTRO."""
    candles = _series_uptrend(n=1000, start=100, step=2.0)
    idx = find_bar_at_days_ago(candles, days=30, period_hours=1)
    sig = simulate_signal_at_bar(candles, idx)
    assert "signal" in sig
    assert "score" in sig
    assert "is_actionable" in sig
    assert "regime_8state" in sig
    assert "entry_price" in sig
    assert "stop_loss" in sig
    assert "take_profit" in sig


# ============================================================================
# 3) classify_outcome_so_far
# ============================================================================
def test_classify_outcome_target_hit_long():
    """LONG: entry=100, stop=90, target=150. Se preco subiu para 160 entre os bars seguintes -> TARGET_HIT."""
    fwd = [_candle(f"2024-02-{i+1:02d}T00:00:00", p) for i, p in
           enumerate([105, 110, 130, 155, 160])]
    out = classify_outcome_so_far(direction="LONG", entry=100, stop=90, target=150, forward_candles=fwd)
    assert out["status"] == "TARGET_HIT"


def test_classify_outcome_stop_hit_long():
    fwd = [_candle(f"2024-02-{i+1:02d}T00:00:00", p) for i, p in
           enumerate([95, 92, 88, 85, 80])]
    out = classify_outcome_so_far(direction="LONG", entry=100, stop=90, target=150, forward_candles=fwd)
    assert out["status"] == "STOP_HIT"


def test_classify_outcome_open_long():
    """Stop nao atingido, target nao atingido -> OPEN."""
    fwd = [_candle(f"2024-02-{i+1:02d}T00:00:00", p) for i, p in
           enumerate([105, 110, 115, 120, 125])]
    out = classify_outcome_so_far(direction="LONG", entry=100, stop=90, target=150, forward_candles=fwd)
    assert out["status"] == "OPEN"


def test_classify_outcome_target_hit_short():
    fwd = [_candle(f"2024-02-{i+1:02d}T00:00:00", p) for i, p in
           enumerate([95, 92, 85, 75, 70])]
    out = classify_outcome_so_far(direction="SHORT", entry=100, stop=110, target=80, forward_candles=fwd)
    assert out["status"] == "TARGET_HIT"


# ============================================================================
# 4) Report schema
# ============================================================================
def test_build_retroactive_report_schema():
    candles_map = {"AAA": _series_uptrend(n=1000)}
    report = build_retroactive_report(candles_map, days_ago=30, period_hours=1)
    for k in ("timestamp_utc", "days_ago", "results", "summary"):
        assert k in report
    assert isinstance(report["results"], list)
    if report["results"]:
        for k in ("symbol", "bar_ts", "regime_8state", "signal", "score",
                  "is_actionable", "verdict", "outcome"):
            assert k in report["results"][0]
