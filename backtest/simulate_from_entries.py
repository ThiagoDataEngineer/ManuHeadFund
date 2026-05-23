"""
simulate_from_entries.py — Simulação triple barrier a partir de entries cacheados.

Permite grid search rápido: muda stop_atr/target_atr/max_bars sem re-rodar
classify_regime + filter + ATR.
"""
from __future__ import annotations

import sys
from pathlib import Path
from typing import Dict, List

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from triple_barrier_simulator import simulate_trade  # noqa: E402
from constants import (  # noqa: E402
    TB_STOP_ATR_MULT, TB_TARGET_ATR_MULT, TB_MAX_BARS,
    TB_FEE_TAKER_PCT, TB_SLIPPAGE_PCT,
)


def simulate_from_entries(
    entries: List[Dict],
    all_dicts: List[Dict],
    stop_atr: float = TB_STOP_ATR_MULT,
    target_atr: float = TB_TARGET_ATR_MULT,
    max_bars: int = TB_MAX_BARS,
    fee_pct: float = TB_FEE_TAKER_PCT,
    slippage_pct: float = TB_SLIPPAGE_PCT,
) -> List[Dict]:
    """
    Para cada entry, simula exit com triple barrier nos all_dicts.
    Retorna trades no formato compativel com build_equity_curve.
    """
    trades = []
    for e in entries:
        sim = simulate_trade(
            entry_idx=e["idx"],
            candles=all_dicts,
            direction=e["direction"],
            atr_value=e["atr_at_entry"],
            stop_atr=stop_atr,
            target_atr=target_atr,
            max_bars=max_bars,
            fee_pct=fee_pct,
            slippage_pct=slippage_pct,
        )
        if sim["exit_reason"] == "invalid":
            continue
        trades.append({
            "entry_ts": e["entry_ts"],
            "regime": e["regime"],
            "direction": e["direction"],
            "result_r": round(sim["result_r"], 4),
            "exit_reason": sim["exit_reason"],
            "holding_bars": sim["holding_bars"],
            "entry_price": round(e["entry_price"], 6),
            "atr_at_entry": round(e["atr_at_entry"], 6),
            "day_of_week_brt": e["day_of_week_brt"],
        })
    return trades
