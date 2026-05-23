"""
test_equity_curve_from_trades.py
TDD strict para equity_curve_from_trades — converte lista de trades em curva
equity diaria multiplicativa, base para Sharpe/DSR em daily returns (não R-multiples).

Constraint: trades com entry_ts ISO8601 + result_r + risk_pct (default 0.01).
Output: dict {date_iso: equity_multiplier} onde equity[0] = 1.0.
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from equity_curve_from_trades import (
    build_equity_curve,
    daily_returns_from_equity,
    aggregate_trades_by_date,
)


def test_aggregate_single_trade_day():
    """Um trade num dia retorna 1 entry no agg."""
    trades = [
        {"entry_ts": "2020-01-15T10:00:00+00:00", "result_r": 1.0},
    ]
    agg = aggregate_trades_by_date(trades)
    assert "2020-01-15" in agg
    assert agg["2020-01-15"] == [1.0]


def test_aggregate_multiple_trades_same_day():
    """Multiplos trades no mesmo dia agrupados."""
    trades = [
        {"entry_ts": "2020-01-15T10:00:00+00:00", "result_r": 1.0},
        {"entry_ts": "2020-01-15T14:00:00+00:00", "result_r": -1.0},
        {"entry_ts": "2020-01-15T18:00:00+00:00", "result_r": 3.0},
    ]
    agg = aggregate_trades_by_date(trades)
    assert len(agg["2020-01-15"]) == 3
    assert agg["2020-01-15"] == [1.0, -1.0, 3.0]


def test_aggregate_skips_invalid_ts():
    """Trades com entry_ts inválido são descartados."""
    trades = [
        {"entry_ts": "2020-01-15T10:00:00+00:00", "result_r": 1.0},
        {"entry_ts": "invalid", "result_r": 2.0},
        {"result_r": 3.0},  # sem entry_ts
    ]
    agg = aggregate_trades_by_date(trades)
    assert len(agg) == 1


def test_build_equity_starts_at_1():
    """Equity curve sempre inicia em 1.0 (capital normalizado)."""
    trades = [
        {"entry_ts": "2020-01-15T10:00:00+00:00", "result_r": 1.0},
    ]
    eq = build_equity_curve(trades, risk_pct=0.01)
    dates = sorted(eq.keys())
    # equity[date_0 - 1] = 1.0 OU primeiro dia já tem o efeito do trade
    assert dates[0] == "2020-01-15"
    # Trade +1R com risk 1% = ganho 1% no dia
    assert eq["2020-01-15"] == 1.01


def test_build_equity_compounds_loss():
    """Trade -1R com risk 1% = perda 1%."""
    trades = [
        {"entry_ts": "2020-01-15T10:00:00+00:00", "result_r": -1.0},
    ]
    eq = build_equity_curve(trades, risk_pct=0.01)
    assert eq["2020-01-15"] == 0.99


def test_build_equity_multiplicative_compound():
    """Multiplos trades em dias diferentes compounding."""
    trades = [
        {"entry_ts": "2020-01-15T10:00:00+00:00", "result_r": 2.0},   # +2%
        {"entry_ts": "2020-01-16T10:00:00+00:00", "result_r": -1.0},  # -1%
        {"entry_ts": "2020-01-17T10:00:00+00:00", "result_r": 5.0},   # +5%
    ]
    eq = build_equity_curve(trades, risk_pct=0.01)
    # Dia 15: 1.0 * 1.02 = 1.02
    # Dia 16: 1.02 * 0.99 = 1.0098
    # Dia 17: 1.0098 * 1.05 = 1.06029
    assert abs(eq["2020-01-15"] - 1.02) < 1e-6
    assert abs(eq["2020-01-16"] - 1.0098) < 1e-6
    assert abs(eq["2020-01-17"] - 1.06029) < 1e-6


def test_build_equity_multi_trades_same_day():
    """Multiplos trades no mesmo dia: produto dos returns."""
    trades = [
        {"entry_ts": "2020-01-15T10:00:00+00:00", "result_r": 1.0},   # +1%
        {"entry_ts": "2020-01-15T14:00:00+00:00", "result_r": 1.0},   # +1%
    ]
    eq = build_equity_curve(trades, risk_pct=0.01)
    # 1.0 * 1.01 * 1.01 = 1.0201
    assert abs(eq["2020-01-15"] - 1.0201) < 1e-6


def test_build_equity_respects_risk_pct():
    """risk_pct=0.005 (0.5%) ao invés de 1%."""
    trades = [
        {"entry_ts": "2020-01-15T10:00:00+00:00", "result_r": 1.0},
    ]
    eq = build_equity_curve(trades, risk_pct=0.005)
    assert eq["2020-01-15"] == 1.005


def test_daily_returns_basic():
    """daily_returns de equity 1.0 -> 1.02 = 0.02"""
    eq = {"2020-01-14": 1.0, "2020-01-15": 1.02, "2020-01-16": 1.0098}
    rets = daily_returns_from_equity(eq)
    assert len(rets) == 2
    assert abs(rets[0] - 0.02) < 1e-6
    assert abs(rets[1] - (1.0098/1.02 - 1)) < 1e-6


def test_daily_returns_empty():
    """Empty equity returns empty list."""
    assert daily_returns_from_equity({}) == []
    assert daily_returns_from_equity({"2020-01-15": 1.0}) == []  # só 1 ponto
