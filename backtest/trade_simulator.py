"""
trade_simulator.py — Simula execução de trades sobre dados históricos
Regras: 1% risk rule, fees CoinEx 0.05% taker, slippage 0.05%
"""
from dataclasses import dataclass, field
from typing import List, Dict, Literal


@dataclass
class TradeResult:
    exit_reason: Literal["TARGET", "STOP", "TIMEOUT"]
    exit_price: float
    result_r: float
    pnl_pct: float
    bars_held: int

    @property
    def is_winner(self) -> bool:
        return self.result_r > 0


def calc_position_size(
    capital: float,
    entry: float,
    stop: float,
    risk_pct: float = 0.01,
    direction: str = "LONG",
) -> float:
    if capital <= 0:
        raise ValueError("Capital deve ser positivo")
    if entry == stop:
        raise ZeroDivisionError("Stop não pode ser igual à entrada")
    if direction == "LONG" and stop >= entry:
        raise ValueError("Stop LONG deve ser abaixo da entrada")
    if direction == "SHORT" and stop <= entry:
        raise ValueError("Stop SHORT deve ser acima da entrada")
    risk_amount = capital * risk_pct
    stop_distance = abs(entry - stop) / entry
    return risk_amount / stop_distance


def simulate_trade(
    direction: str,
    entry: float,
    stop: float,
    target: float,
    candles: List[Dict],
    fee_pct: float = 0.08,  # DRIFT-3 fix 2026-05-16: alinhado CoinEx (docs/CONSTANTS.md)
) -> TradeResult:
    risk = abs(entry - stop)

    for i, bar in enumerate(candles):
        high, low = bar["high"], bar["low"]

        if direction == "LONG":
            if low <= stop:
                exit_price = stop
                pnl = (exit_price - entry) / entry * 100 - fee_pct
                return TradeResult(
                    exit_reason="STOP",
                    exit_price=exit_price,
                    result_r=-1.0,
                    pnl_pct=pnl,
                    bars_held=i + 1,
                )
            if high >= target:
                exit_price = target
                gross_pnl = (exit_price - entry) / entry * 100
                pnl = gross_pnl - fee_pct
                result_r = (target - entry) / risk
                return TradeResult(
                    exit_reason="TARGET",
                    exit_price=exit_price,
                    result_r=result_r,
                    pnl_pct=pnl,
                    bars_held=i + 1,
                )
        else:  # SHORT
            if high >= stop:
                exit_price = stop
                pnl = (entry - exit_price) / entry * 100 - fee_pct
                return TradeResult(
                    exit_reason="STOP",
                    exit_price=exit_price,
                    result_r=-1.0,
                    pnl_pct=pnl,
                    bars_held=i + 1,
                )
            if low <= target:
                exit_price = target
                gross_pnl = (entry - exit_price) / entry * 100
                pnl = gross_pnl - fee_pct
                result_r = (entry - target) / risk
                return TradeResult(
                    exit_reason="TARGET",
                    exit_price=exit_price,
                    result_r=result_r,
                    pnl_pct=pnl,
                    bars_held=len(candles),
                )

    last_close = candles[-1]["close"] if candles else entry
    if direction == "LONG":
        pnl = (last_close - entry) / entry * 100 - fee_pct
        result_r = (last_close - entry) / risk
    else:
        pnl = (entry - last_close) / entry * 100 - fee_pct
        result_r = (entry - last_close) / risk

    return TradeResult(
        exit_reason="TIMEOUT",
        exit_price=last_close,
        result_r=result_r,
        pnl_pct=pnl,
        bars_held=len(candles),
    )
