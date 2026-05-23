"""
test_benchmark_short_v6_btc.py -- TDD test suite para benchmark_short_v6_btc.py

Tests:
  1. Imports OK
  2. V6 filter rejects BULL_STRONG candles
  3. V6 filter accepts BEAR_STRONG candles
  4. Tori proxy: breakdown detection
  5. Tori proxy: rejection detection
  6. Tori proxy: no signal wenn neither breakdown nor rejection
  7. Funding unavailable fallback
  8. Comparison structure vs baseline
  9. GO criterion logic
  10. Integration: synthetic bear scenario

Roda com `pytest backtest/tests/test_benchmark_short_v6_btc.py -v`
"""
import json
import sys
import os
from datetime import datetime, timedelta, timezone
from typing import Dict, List

import pytest

# Add backtest to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from benchmark_short_v6_btc import (
    SHORT_ALLOWED_REGIMES,
    get_regime_at_idx,
    tori_trendline_proxy,
    passes_v6_filters,
    EquityStopTrackerV6,
    classify_verdict_v6,
    build_result_skeleton_v6,
    scan_period_v6,
)


# ──────────────────────────────────────────────────────────────────────────────
# Test 1: Imports OK
# ──────────────────────────────────────────────────────────────────────────────

def test_imports_v6_modules():
    """Verifica se todos os modulos importam sem erro."""
    try:
        import benchmark_short_v6_btc  # noqa: F401
        from benchmark_short_v6_btc import (  # noqa: F401
            SHORT_ALLOWED_REGIMES,
            tori_trendline_proxy,
            EquityStopTrackerV6,
            scan_period_v6,
            build_result_skeleton_v6,
        )
        assert True
    except ImportError as e:
        pytest.fail(f"Import failed: {e}")


# ──────────────────────────────────────────────────────────────────────────────
# Test 2: V6 filter rejects BULL_STRONG
# ──────────────────────────────────────────────────────────────────────────────

def test_regime_filter_rejects_bull_strong():
    """BULL_STRONG nao esta em SHORT_ALLOWED_REGIMES."""
    assert "BULL_STRONG" not in SHORT_ALLOWED_REGIMES
    assert "BEAR_STRONG" in SHORT_ALLOWED_REGIMES


# ──────────────────────────────────────────────────────────────────────────────
# Test 3: V6 filter accepts BEAR_STRONG
# ──────────────────────────────────────────────────────────────────────────────

def test_regime_filter_accepts_bear_strong():
    """BEAR_STRONG esta em SHORT_ALLOWED_REGIMES."""
    assert "BEAR_STRONG" in SHORT_ALLOWED_REGIMES
    assert "CAPITULATION" in SHORT_ALLOWED_REGIMES
    assert "TRANSITION_DOWN" in SHORT_ALLOWED_REGIMES
    assert "SIDEWAYS" in SHORT_ALLOWED_REGIMES
    assert "BEAR_WEAK" in SHORT_ALLOWED_REGIMES


# ──────────────────────────────────────────────────────────────────────────────
# Test 4: Tori proxy detects breakdown
# ──────────────────────────────────────────────────────────────────────────────

def test_tori_proxy_breakdown():
    """Tori detects quando close[-1] < min(closes[:-1])."""
    candles = [
        {"high": 10.0, "low": 9.0, "close": 9.5},
        {"high": 10.5, "low": 9.2, "close": 10.0},
        {"high": 11.0, "low": 9.5, "close": 10.5},
        {"high": 10.8, "low": 9.3, "close": 10.2},
        {"high": 10.6, "low": 9.1, "close": 8.5},  # < min(9.5, 10.0, 10.5, 10.2)
    ]
    # idx=4: close=8.5 < min(9.5, 10.0, 10.5, 10.2) = 9.5 -> breakdown
    result = tori_trendline_proxy(candles, idx=4, lookback=5)
    assert result is True


# ──────────────────────────────────────────────────────────────────────────────
# Test 5: Tori proxy detects rejection
# ──────────────────────────────────────────────────────────────────────────────

def test_tori_proxy_rejection():
    """Tori detects quando close[-1] < max(highs[:-1]) * 0.99."""
    candles = [
        {"high": 10.0, "low": 9.0, "close": 9.5},
        {"high": 10.5, "low": 9.2, "close": 10.0},
        {"high": 11.0, "low": 9.5, "close": 10.5},
        {"high": 10.8, "low": 9.3, "close": 10.2},
        {"high": 10.9, "low": 9.0, "close": 10.78},  # < 10.9 * 0.99 = 10.791
    ]
    result = tori_trendline_proxy(candles, idx=4, lookback=5)
    assert result is True


# ──────────────────────────────────────────────────────────────────────────────
# Test 6: Tori proxy rejects quando nao ha breakdown nem rejection
# ──────────────────────────────────────────────────────────────────────────────

def test_tori_proxy_no_signal():
    """Tori retorna False quando nao ha breakdown nem rejection."""
    # max_high anteriores = 11.0, threshold rejection = 11.0 * 0.99 = 10.89
    # close 11.0 == max_high, NAO < 10.89 -> no rejection
    # close > min anteriores (9.5) -> no breakdown
    candles = [
        {"high": 10.0, "low": 9.0, "close": 9.5},
        {"high": 10.5, "low": 9.2, "close": 10.0},
        {"high": 11.0, "low": 9.5, "close": 10.5},
        {"high": 10.8, "low": 9.3, "close": 10.2},
        {"high": 11.2, "low": 9.3, "close": 11.0},  # > all min/max threshold
    ]
    result = tori_trendline_proxy(candles, idx=4, lookback=5)
    assert result is False


# ──────────────────────────────────────────────────────────────────────────────
# Test 7: Tori proxy rejects when idx < lookback
# ──────────────────────────────────────────────────────────────────────────────

def test_tori_proxy_insufficient_data():
    """Tori retorna False when idx < lookback."""
    candles = [
        {"high": 10.0, "low": 9.0, "close": 9.5},
        {"high": 10.5, "low": 9.2, "close": 10.0},
    ]
    result = tori_trendline_proxy(candles, idx=1, lookback=5)
    assert result is False


# ──────────────────────────────────────────────────────────────────────────────
# Test 8: Equity stop tracker V6 counts pause bars
# ──────────────────────────────────────────────────────────────────────────────

def test_equity_stop_tracker_v6_pause():
    """EquityStopTrackerV6 pausa por pause_bars apos -10R hit."""
    tracker = EquityStopTrackerV6(threshold_R=10.0, pause_bars=5)
    # Acumula +5R (peak=5)
    tracker.on_trade_close(5.0)
    assert tracker.is_paused() is False

    # Perde -15R -> cai para -10R (dd=15 > threshold=10)
    tracker.on_trade_close(-15.0)
    assert tracker.is_paused() is True
    assert tracker.pause_countdown == 5

    # on_bar_advance() 5x
    for _ in range(5):
        tracker.on_bar_advance()
        if tracker.pause_countdown > 0:
            assert tracker.is_paused() is True
        else:
            assert tracker.is_paused() is False

    # Apos 5 bars, pause lifted
    assert tracker.is_paused() is False


# ──────────────────────────────────────────────────────────────────────────────
# Test 9: Classify verdict V6
# ──────────────────────────────────────────────────────────────────────────────

def test_classify_verdict_v6_edge():
    """V6 classifica SHORT_EDGE_V6 quando exp >= 0.40R e dd_ratio < 0.6."""
    verdict = classify_verdict_v6(expectancy_r=0.50, dd_ratio=0.5)
    assert verdict == "SHORT_EDGE_V6"


def test_classify_verdict_v6_marginal():
    """V6 classifica SHORT_MARGINAL quando exp >= 0.20R ou dd_ratio < 0.8."""
    verdict = classify_verdict_v6(expectancy_r=0.30, dd_ratio=0.7)
    assert verdict == "SHORT_MARGINAL"


def test_classify_verdict_v6_insuficiente():
    """V6 classifica SHORT_INSUFICIENTE caso contrario."""
    verdict = classify_verdict_v6(expectancy_r=0.10, dd_ratio=0.9)
    assert verdict == "SHORT_INSUFICIENTE"


# ──────────────────────────────────────────────────────────────────────────────
# Test 10: build_result_skeleton_v6 GO criterion
# ──────────────────────────────────────────────────────────────────────────────

def test_go_criterion_v6_pass():
    """GO criterion passa quando ambos periods >= 0.40R, PF >= 1.5, DD <= 12R."""
    periods = [
        {
            "period_id": "bear_2018",
            "metrics": {
                "expectancy_r": 0.50,
                "profit_factor": 1.8,
                "max_dd_r": 10.0,
            },
        },
        {
            "period_id": "bear_2022",
            "metrics": {
                "expectancy_r": 0.45,
                "profit_factor": 1.6,
                "max_dd_r": 11.0,
            },
        },
    ]
    result = build_result_skeleton_v6(periods)
    assert result["go_criterion"]["passed"] is True
    assert "destranca SHORT em regime bear" in result["go_criterion"]["explanation"]


def test_go_criterion_v6_fail_expectancy():
    """GO criterion falha quando um period tem exp < 0.40R."""
    periods = [
        {
            "period_id": "bear_2018",
            "metrics": {
                "expectancy_r": 0.30,  # < 0.40
                "profit_factor": 1.8,
                "max_dd_r": 10.0,
            },
        },
        {
            "period_id": "bear_2022",
            "metrics": {
                "expectancy_r": 0.45,
                "profit_factor": 1.6,
                "max_dd_r": 11.0,
            },
        },
    ]
    result = build_result_skeleton_v6(periods)
    assert result["go_criterion"]["passed"] is False
    assert "falha em: bear_2018" in result["go_criterion"]["explanation"]


def test_go_criterion_v6_fail_dd():
    """GO criterion falha quando um period tem max_dd_r > 12R."""
    periods = [
        {
            "period_id": "bear_2018",
            "metrics": {
                "expectancy_r": 0.50,
                "profit_factor": 1.8,
                "max_dd_r": 13.0,  # > 12
            },
        },
        {
            "period_id": "bear_2022",
            "metrics": {
                "expectancy_r": 0.45,
                "profit_factor": 1.6,
                "max_dd_r": 11.0,
            },
        },
    ]
    result = build_result_skeleton_v6(periods)
    assert result["go_criterion"]["passed"] is False


# ──────────────────────────────────────────────────────────────────────────────
# Test 11: Result structure matches baseline
# ──────────────────────────────────────────────────────────────────────────────

def test_result_structure():
    """Result skeleton tem structure esperada."""
    periods = [
        {
            "period_id": "bear_2018",
            "metrics": {
                "expectancy_r": 0.50,
                "profit_factor": 1.8,
                "max_dd_r": 10.0,
            },
        },
        {
            "period_id": "bear_2022",
            "metrics": {
                "expectancy_r": 0.45,
                "profit_factor": 1.6,
                "max_dd_r": 11.0,
            },
        },
    ]
    result = build_result_skeleton_v6(periods)

    assert "timestamp" in result
    assert "config" in result
    assert result["config"] == "v6_short_btc"
    assert "periods" in result
    assert "go_criterion" in result
    assert "v6_changelog" in result
    assert len(result["periods"]) == 2


# ──────────────────────────────────────────────────────────────────────────────
# Test 12: Synthetic bear scenario (integration)
# ──────────────────────────────────────────────────────────────────────────────

def test_synthetic_bear_scenario():
    """Simula 50 candles BEAR + Tori breakdown -> detecta setup."""
    # Cria candles sintéticas descendo (bear market)
    candles = []
    price = 50000.0
    for i in range(50):
        high = price * 1.02
        low = price * 0.98
        close = price * (0.99 - 0.001 * i)  # Declina gradualmente
        candles.append({
            "ts": int((datetime.now(timezone.utc) - timedelta(days=50 - i)).timestamp() * 1000),
            "open": price,
            "high": high,
            "low": low,
            "close": close,
            "volume": 1000.0,
        })
        price = close

    # No último bar, força breakdown
    candles[-1]["close"] = candles[-2]["close"] * 0.95  # Force breakdown

    # Tori proxy deveria detectar
    result = tori_trendline_proxy(candles, idx=len(candles) - 1, lookback=5)
    assert result is True, "Synthetic bear breakdown nao foi detectado"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
