"""TDD: simulate_from_entries deve produzir trades equivalentes ao path-dependent."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from simulate_from_entries import simulate_from_entries


def _ohlc(rows):
    return [{"open": o, "high": h, "low": l, "close": c} for o, h, l, c in rows]


def test_simulate_empty_entries():
    assert simulate_from_entries([], []) == []


def test_simulate_target_hit():
    """Entry com target hit produz trade com result_r positivo."""
    candles = _ohlc([
        (100, 100, 100, 100),
        (100, 150, 100, 140),
    ])
    entries = [{
        "idx": 0, "entry_ts": "2024-01-01T00:00:00+00:00",
        "regime": "BULL_STRONG", "direction": "LONG",
        "atr_at_entry": 10.0, "entry_price": 100.0,
        "day_of_week_brt": 1, "reason": "test",
    }]
    trades = simulate_from_entries(entries, candles,
                                    stop_atr=1.0, target_atr=5.0,
                                    fee_pct=0.0, slippage_pct=0.0)
    assert len(trades) == 1
    assert trades[0]["exit_reason"] == "target_hit"
    assert abs(trades[0]["result_r"] - 5.0) < 0.01
    assert trades[0]["regime"] == "BULL_STRONG"


def test_simulate_filters_invalid():
    """Entry invalido (atr=0) e dropado, nao quebra grid search."""
    candles = _ohlc([(100, 100, 100, 100), (100, 105, 95, 100)])
    entries = [{
        "idx": 0, "entry_ts": "2024-01-01T00:00:00+00:00",
        "regime": "BULL_STRONG", "direction": "LONG",
        "atr_at_entry": 0.0, "entry_price": 100.0,  # atr zero
        "day_of_week_brt": 1, "reason": "test",
    }]
    trades = simulate_from_entries(entries, candles)
    assert trades == []


def test_grid_changes_outcome():
    """Mesmo entry com stop/target diferentes produz result_r diferente."""
    candles = _ohlc([
        (100, 100, 100, 100),
        (100, 115, 100, 102),  # high=115: bate target=110 (1*ATR) mas nao 150 (5*ATR); close=102
    ])
    entries = [{
        "idx": 0, "entry_ts": "2024-01-01T00:00:00+00:00",
        "regime": "BULL_STRONG", "direction": "LONG",
        "atr_at_entry": 10.0, "entry_price": 100.0,
        "day_of_week_brt": 1, "reason": "test",
    }]
    t_tight = simulate_from_entries(entries, candles,
                                     stop_atr=1.0, target_atr=1.0,
                                     fee_pct=0.0, slippage_pct=0.0)
    t_wide = simulate_from_entries(entries, candles,
                                    stop_atr=1.0, target_atr=5.0, max_bars=2,
                                    fee_pct=0.0, slippage_pct=0.0)
    assert t_tight[0]["exit_reason"] == "target_hit"
    assert t_wide[0]["exit_reason"] == "timeout"  # nao bate target nem stop
    assert t_tight[0]["result_r"] > t_wide[0]["result_r"]
