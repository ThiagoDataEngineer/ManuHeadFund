"""
triple_barrier_simulator.py — Path-dependent simulation realista (LdP AFML cap 3).

Substitui simulação binária +5R/-1R que inflava equity 10^28 em XRP. Walk candles
futuros bar-a-bar, marca primeira barreira tocada (target/stop/timeout) e calcula
result_r real incluindo fees + slippage.

Convenções:
- LONG: stop = entry - stop_atr*ATR; target = entry + target_atr*ATR
- SHORT: stop = entry + stop_atr*ATR; target = entry - target_atr*ATR
- Conservador: se candle bate stop E target no mesmo bar, stop ganha (não há OHLC intrabar)
- Fees + slippage aplicados nos 2 lados (entry + exit) como dedução em pct return
- result_r em unidades de stop_atr (1R = stop_atr*ATR pct do entry price)

Saída:
    {
      "exit_idx": int,             # índice do candle de saída no array
      "exit_price": float,         # preço efetivo de saída (sem fees)
      "result_r": float,           # PnL em R-multiples (descontado fees+slippage)
      "exit_reason": str,          # "target_hit" | "stop_hit" | "timeout" | "invalid"
      "holding_bars": int,         # exit_idx - entry_idx
    }
"""
from typing import Dict, List


def _invalid_result() -> Dict:
    return {
        "exit_idx": -1,
        "exit_price": 0.0,
        "result_r": 0.0,
        "exit_reason": "invalid",
        "holding_bars": 0,
    }


def simulate_trade(
    entry_idx: int,
    candles: List[Dict],
    direction: str,
    atr_value: float,
    stop_atr: float = 1.0,
    target_atr: float = 5.0,
    max_bars: int = 168,
    fee_pct: float = 0.0005,
    slippage_pct: float = 0.0005,
) -> Dict:
    """
    Simula um trade com triple barrier path-dependent.

    Args:
        entry_idx: índice do candle de entrada
        candles: lista de candles {open, high, low, close}
        direction: "LONG" ou "SHORT"
        atr_value: ATR no momento da entrada (em pontos de preço)
        stop_atr: multiplicador ATR para stop (1.0 = 1*ATR)
        target_atr: multiplicador ATR para target (5.0 = 5*ATR, R:R 1:5)
        max_bars: timeout vertical em bars
        fee_pct: fee por lado (0.0005 = 0.05%)
        slippage_pct: slippage por lado

    Returns:
        dict conforme docstring do módulo
    """
    if entry_idx < 0 or entry_idx >= len(candles):
        return _invalid_result()
    if atr_value <= 0:
        return _invalid_result()
    if direction not in ("LONG", "SHORT"):
        return _invalid_result()

    entry_candle = candles[entry_idx]
    entry_price = float(entry_candle.get("close", 0.0))
    if entry_price <= 0:
        return _invalid_result()

    # Define barreiras em preço absoluto
    if direction == "LONG":
        stop_price = entry_price - stop_atr * atr_value
        target_price = entry_price + target_atr * atr_value
    else:  # SHORT
        stop_price = entry_price + stop_atr * atr_value
        target_price = entry_price - target_atr * atr_value

    # Walk candles futuros
    end_idx = min(entry_idx + max_bars, len(candles) - 1)

    cost_per_side = fee_pct + slippage_pct  # custo total por lado
    # Pct de stop em relação ao entry — define "1R" em pct return
    stop_pct = (stop_atr * atr_value) / entry_price  # ex: 10/100 = 0.10 = 10%

    for j in range(entry_idx + 1, end_idx + 1):
        c = candles[j]
        hi = float(c.get("high", 0.0))
        lo = float(c.get("low", 0.0))

        if direction == "LONG":
            stop_hit = lo <= stop_price
            target_hit = hi >= target_price
        else:
            stop_hit = hi >= stop_price
            target_hit = lo <= target_price

        # Conservador: stop ganha em caso de ambos no mesmo bar
        if stop_hit:
            # result_r = -1 (em unidades de stop)
            # Aplica custos: -2*cost_per_side em pct, dividido por stop_pct para virar R
            cost_r = (2 * cost_per_side) / stop_pct
            return {
                "exit_idx": j,
                "exit_price": stop_price,
                "result_r": -stop_atr - cost_r,
                "exit_reason": "stop_hit",
                "holding_bars": j - entry_idx,
            }
        if target_hit:
            cost_r = (2 * cost_per_side) / stop_pct
            return {
                "exit_idx": j,
                "exit_price": target_price,
                "result_r": target_atr - cost_r,
                "exit_reason": "target_hit",
                "holding_bars": j - entry_idx,
            }

    # Timeout — exit no close do último candle (end_idx)
    exit_candle = candles[end_idx]
    exit_price = float(exit_candle.get("close", entry_price))
    if direction == "LONG":
        pnl_pct = (exit_price - entry_price) / entry_price
    else:
        pnl_pct = (entry_price - exit_price) / entry_price
    pnl_pct -= 2 * cost_per_side  # custos round-trip
    # Converte pct para R-multiple (dividindo por stop_pct)
    result_r = pnl_pct / stop_pct if stop_pct > 0 else 0.0

    return {
        "exit_idx": end_idx,
        "exit_price": exit_price,
        "result_r": result_r,
        "exit_reason": "timeout",
        "holding_bars": end_idx - entry_idx,
    }
