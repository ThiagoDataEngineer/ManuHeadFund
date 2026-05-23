"""
test_triple_barrier_simulator.py — TDD para simulação path-dependent realista.

Substitui simulação binária +5R/-1R (que gerava equity 10^28 absurdo em XRP)
por triple barrier de López de Prado AFML cap 3:
  - upper barrier (target_atr * ATR)
  - lower barrier (stop_atr * ATR)
  - vertical barrier (max_bars timeout)
  - + fees + slippage realistas
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from triple_barrier_simulator import simulate_trade


def _candles_uniform(prices, atr_val=10.0):
    """Helper: lista de candles com high=low=close=open=preço, ATR fixo."""
    return [{"open": p, "high": p, "low": p, "close": p} for p in prices]


def _candles_ohlc(rows):
    """Helper: lista de candles a partir de tuples (open, high, low, close)."""
    return [{"open": o, "high": h, "low": l, "close": c} for o, h, l, c in rows]


def test_target_hit_long():
    """LONG: candle futuro toca target → result_r ≈ +target_mult (descontado fees)."""
    # entry=100, ATR=10, target_mult=5 → target=150
    # candle[1] high=150 → target hit
    candles = _candles_ohlc([
        (100, 100, 100, 100),  # entry
        (100, 150, 100, 140),  # target hit at high=150
    ])
    r = simulate_trade(
        entry_idx=0, candles=candles, direction="LONG",
        atr_value=10.0, stop_atr=1.0, target_atr=5.0,
        max_bars=10, fee_pct=0.0, slippage_pct=0.0,
    )
    assert r["exit_reason"] == "target_hit"
    assert r["exit_idx"] == 1
    assert abs(r["result_r"] - 5.0) < 0.01  # +5R sem fees


def test_stop_hit_long():
    """LONG: candle futuro toca stop → result_r ≈ -1R."""
    candles = _candles_ohlc([
        (100, 100, 100, 100),  # entry
        (100, 100, 89, 92),    # stop hit at low=89 (stop=90)
    ])
    r = simulate_trade(
        entry_idx=0, candles=candles, direction="LONG",
        atr_value=10.0, stop_atr=1.0, target_atr=5.0,
        max_bars=10, fee_pct=0.0, slippage_pct=0.0,
    )
    assert r["exit_reason"] == "stop_hit"
    assert r["exit_idx"] == 1
    assert abs(r["result_r"] - (-1.0)) < 0.01  # -1R


def test_timeout_long():
    """LONG: sem toque em barreira → exit no max_bars com PnL real."""
    # entry=100, ATR=10, max_bars=3, todos candles em range 95-105
    candles = _candles_ohlc([
        (100, 100, 100, 100),
        (100, 105, 95, 102),
        (102, 104, 98, 103),
        (103, 105, 100, 104),
    ])
    r = simulate_trade(
        entry_idx=0, candles=candles, direction="LONG",
        atr_value=10.0, stop_atr=1.0, target_atr=5.0,
        max_bars=3, fee_pct=0.0, slippage_pct=0.0,
    )
    assert r["exit_reason"] == "timeout"
    # exit_price = close do candle max_bars = 104
    # PnL pct = (104-100)/100 = 0.04 = 4% = 0.4R em unidades de stop (stop=1%-equiv = 10/100=10%)
    # Como stop = 1*ATR = 10, e 10 vale 1R: PnL em R = 4/10 = 0.4R
    assert abs(r["result_r"] - 0.4) < 0.01


def test_target_hit_short():
    """SHORT: candle futuro toca target embaixo → result_r ≈ +5R."""
    # entry=100, ATR=10, SHORT: stop=110, target=50
    candles = _candles_ohlc([
        (100, 100, 100, 100),  # entry
        (100, 100, 49, 60),    # target hit at low=49 (target=50)
    ])
    r = simulate_trade(
        entry_idx=0, candles=candles, direction="SHORT",
        atr_value=10.0, stop_atr=1.0, target_atr=5.0,
        max_bars=10, fee_pct=0.0, slippage_pct=0.0,
    )
    assert r["exit_reason"] == "target_hit"
    assert abs(r["result_r"] - 5.0) < 0.01


def test_stop_hit_short():
    """SHORT: candle futuro sobe e bate stop → -1R."""
    candles = _candles_ohlc([
        (100, 100, 100, 100),  # entry
        (100, 111, 100, 108),  # stop hit at high=111 (stop=110)
    ])
    r = simulate_trade(
        entry_idx=0, candles=candles, direction="SHORT",
        atr_value=10.0, stop_atr=1.0, target_atr=5.0,
        max_bars=10, fee_pct=0.0, slippage_pct=0.0,
    )
    assert r["exit_reason"] == "stop_hit"
    assert abs(r["result_r"] - (-1.0)) < 0.01


def test_fees_reduce_winning_trade():
    """Fees reduzem ganho real: target=5R com fee 0.1% por lado → result_r < 5."""
    candles = _candles_ohlc([
        (100, 100, 100, 100),
        (100, 150, 100, 140),
    ])
    r_no_fee = simulate_trade(
        entry_idx=0, candles=candles, direction="LONG",
        atr_value=10.0, stop_atr=1.0, target_atr=5.0,
        max_bars=10, fee_pct=0.0, slippage_pct=0.0,
    )
    r_with_fee = simulate_trade(
        entry_idx=0, candles=candles, direction="LONG",
        atr_value=10.0, stop_atr=1.0, target_atr=5.0,
        max_bars=10, fee_pct=0.001, slippage_pct=0.001,
    )
    # 0.4% round-trip (fee+slip * 2 sides) ≈ -0.4% pct return
    # Em R: stop_pct = 10%, então 0.4%/10% = 0.04R de erosão
    assert r_with_fee["result_r"] < r_no_fee["result_r"]
    assert abs((r_no_fee["result_r"] - r_with_fee["result_r"]) - 0.04) < 0.02


def test_priority_stop_first_if_same_candle():
    """Se candle bate stop e target no mesmo bar, conservador = stop primeiro."""
    candles = _candles_ohlc([
        (100, 100, 100, 100),
        (100, 150, 89, 100),  # high=150 (target) E low=89 (stop)
    ])
    r = simulate_trade(
        entry_idx=0, candles=candles, direction="LONG",
        atr_value=10.0, stop_atr=1.0, target_atr=5.0,
        max_bars=10, fee_pct=0.0, slippage_pct=0.0,
    )
    # Conservador: assume stop tocou primeiro (não temos OHLC intrabar)
    assert r["exit_reason"] == "stop_hit"
    assert abs(r["result_r"] - (-1.0)) < 0.01


def test_invalid_entry_idx():
    """entry_idx fora do array retorna result_r=0, exit_reason='invalid'."""
    candles = _candles_ohlc([(100, 100, 100, 100)])
    r = simulate_trade(
        entry_idx=5, candles=candles, direction="LONG",
        atr_value=10.0, stop_atr=1.0, target_atr=5.0,
        max_bars=10, fee_pct=0.0, slippage_pct=0.0,
    )
    assert r["exit_reason"] == "invalid"
    assert r["result_r"] == 0.0


def test_atr_zero_invalid():
    """ATR=0 invalida trade (impossível calcular stops)."""
    candles = _candles_ohlc([(100, 100, 100, 100), (100, 105, 95, 100)])
    r = simulate_trade(
        entry_idx=0, candles=candles, direction="LONG",
        atr_value=0.0, stop_atr=1.0, target_atr=5.0,
        max_bars=10, fee_pct=0.0, slippage_pct=0.0,
    )
    assert r["exit_reason"] == "invalid"
    assert r["result_r"] == 0.0


def test_holding_bars_field():
    """Retorna holding_bars = exit_idx - entry_idx."""
    candles = _candles_ohlc([
        (100, 100, 100, 100),
        (100, 105, 95, 100),
        (100, 150, 100, 140),
    ])
    r = simulate_trade(
        entry_idx=0, candles=candles, direction="LONG",
        atr_value=10.0, stop_atr=1.0, target_atr=5.0,
        max_bars=10, fee_pct=0.0, slippage_pct=0.0,
    )
    assert r["holding_bars"] == 2
