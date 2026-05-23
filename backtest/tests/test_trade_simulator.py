"""
TDD — trade_simulator.py
Testa a lógica de simulação de trades: sizing, R:R, fees, resultado.
"""
import pytest
from trade_simulator import (
    calc_position_size,
    simulate_trade,
    TradeResult,
)


# ── Position Sizing (Regra do 1%) ────────────────────────────────────────────

class TestPositionSizing:
    def test_risk_1pct_of_capital(self):
        # capital=1000, entrada=100, stop=99 → distância=1% → posição=1000 USDT
        size = calc_position_size(capital=1000.0, entry=100.0, stop=99.0)
        assert abs(size - 1000.0) < 0.01

    def test_wider_stop_smaller_position(self):
        size_tight = calc_position_size(capital=1000.0, entry=100.0, stop=99.0)   # 1% stop
        size_wide = calc_position_size(capital=1000.0, entry=100.0, stop=95.0)    # 5% stop
        assert size_tight > size_wide

    def test_max_loss_always_1pct(self):
        capital = 5000.0
        entry = 50000.0
        stop = 49000.0
        size = calc_position_size(capital=capital, entry=entry, stop=stop)
        loss = size * abs(entry - stop) / entry
        assert abs(loss - capital * 0.01) < 0.10

    def test_stop_equals_entry_raises(self):
        with pytest.raises((ValueError, ZeroDivisionError)):
            calc_position_size(capital=1000.0, entry=100.0, stop=100.0)

    def test_stop_above_entry_long_raises(self):
        with pytest.raises(ValueError):
            calc_position_size(capital=1000.0, entry=100.0, stop=101.0, direction="LONG")

    def test_capital_zero_raises(self):
        with pytest.raises(ValueError):
            calc_position_size(capital=0.0, entry=100.0, stop=99.0)


# ── Simulação de Trade Individual ────────────────────────────────────────────

class TestSimulateTrade:
    def test_target_hit_returns_positive_r(self):
        result = simulate_trade(
            direction="LONG",
            entry=100.0,
            stop=99.0,    # risco: 1%
            target=103.0, # alvo: 3% → R:R 1:3
            candles=[
                {"high": 101.0, "low": 99.5, "close": 100.5},
                {"high": 103.5, "low": 101.0, "close": 103.0},  # alvo atingido
            ]
        )
        assert result.exit_reason == "TARGET"
        assert result.result_r > 0

    def test_stop_hit_returns_minus_one_r(self):
        result = simulate_trade(
            direction="LONG",
            entry=100.0,
            stop=99.0,
            target=103.0,
            candles=[
                {"high": 100.5, "low": 98.5, "close": 99.0},  # low < stop → stop hit
            ]
        )
        assert result.exit_reason == "STOP"
        assert abs(result.result_r - (-1.0)) < 0.01

    def test_short_target_hit(self):
        result = simulate_trade(
            direction="SHORT",
            entry=100.0,
            stop=101.0,   # risco: 1%
            target=97.0,  # alvo: 3% abaixo
            candles=[
                {"high": 100.5, "low": 99.5, "close": 100.0},
                {"high": 99.0, "low": 96.5, "close": 97.0},  # alvo atingido
            ]
        )
        assert result.exit_reason == "TARGET"
        assert result.result_r > 0

    def test_short_stop_hit(self):
        result = simulate_trade(
            direction="SHORT",
            entry=100.0,
            stop=101.0,
            target=97.0,
            candles=[
                {"high": 101.5, "low": 99.5, "close": 101.0},  # high > stop → stop hit
            ]
        )
        assert result.exit_reason == "STOP"
        assert result.result_r < 0

    def test_timeout_when_no_exit_hit(self):
        result = simulate_trade(
            direction="LONG",
            entry=100.0,
            stop=99.0,
            target=103.0,
            candles=[
                {"high": 101.0, "low": 99.5, "close": 100.5},
                {"high": 102.0, "low": 99.6, "close": 101.0},
            ]
        )
        assert result.exit_reason == "TIMEOUT"

    def test_fees_deducted_from_pnl(self):
        result = simulate_trade(
            direction="LONG",
            entry=100.0,
            stop=99.0,
            target=103.0,
            candles=[{"high": 103.5, "low": 100.5, "close": 103.0}],
            fee_pct=0.10,  # 0.05% + 0.05% = 0.10% round trip
        )
        assert result.pnl_pct < 3.0  # ganho bruto de 3% menos fees

    def test_result_r_consistent_with_risk(self):
        # Risco = $1 (stop 1% abaixo), alvo = $3 (target 3% acima) → R:R = 3
        result = simulate_trade(
            direction="LONG",
            entry=100.0,
            stop=99.0,
            target=103.0,
            candles=[{"high": 103.5, "low": 100.5, "close": 103.0}],
        )
        assert abs(result.result_r - 3.0) < 0.1

    def test_empty_candles_returns_timeout(self):
        result = simulate_trade(
            direction="LONG",
            entry=100.0,
            stop=99.0,
            target=103.0,
            candles=[]
        )
        assert result.exit_reason == "TIMEOUT"


# ── TradeResult ───────────────────────────────────────────────────────────────

class TestTradeResult:
    def test_trade_result_has_required_fields(self):
        result = TradeResult(
            exit_reason="TARGET",
            exit_price=103.0,
            result_r=3.0,
            pnl_pct=2.9,
            bars_held=2,
        )
        assert result.exit_reason == "TARGET"
        assert result.exit_price == 103.0
        assert result.result_r == 3.0
        assert result.pnl_pct == 2.9
        assert result.bars_held == 2

    def test_trade_result_is_winner(self):
        win = TradeResult(exit_reason="TARGET", exit_price=103.0, result_r=2.5, pnl_pct=2.4, bars_held=3)
        loss = TradeResult(exit_reason="STOP", exit_price=99.0, result_r=-1.0, pnl_pct=-1.1, bars_held=1)
        assert win.is_winner is True
        assert loss.is_winner is False
