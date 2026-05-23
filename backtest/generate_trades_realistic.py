"""
generate_trades_realistic.py — Gerador de trades com triple barrier path-dependent.

Substitui generate_xrp_trades binário (+5R/-1R) por simulação realista:
  - stop = entry - 1*ATR(14)
  - target = entry + 5*ATR(14)
  - timeout = 168h (7 dias)
  - fees CoinEx taker 0.05% + slippage 0.05% (round-trip ~0.2%)

Filtro de entrada: whitelist v2 strict_v2 (mesma do generate_xrp_trades original)
para preservar comparabilidade do edge — só muda o cálculo de result_r.
"""
from __future__ import annotations

import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, List

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.path.insert(0, str(ROOT_DIR))

from regime_classifier import classify_regime  # noqa: E402
from signal_generator import apply_regime_filter  # noqa: E402
from indicators import atr as atr_indicator  # noqa: E402
from triple_barrier_simulator import simulate_trade  # noqa: E402
from constants import (  # noqa: E402
    TB_ATR_PERIOD, TB_STOP_ATR_MULT, TB_TARGET_ATR_MULT,
    TB_MAX_BARS, TB_FEE_TAKER_PCT, TB_SLIPPAGE_PCT,
    WMA200_BARS_DAILY,
)


def candle_to_dict(c: Dict) -> Dict:
    """Normaliza candle para dict com keys padrão."""
    return {
        "ts": c.get("ts"),
        "open": float(c.get("open", 0.0)),
        "high": float(c.get("high", 0.0)),
        "low": float(c.get("low", 0.0)),
        "close": float(c.get("close", 0.0)),
        "volume": float(c.get("volume", 0.0)),
    }


def parse_ts(ts_str: str) -> datetime:
    dt = datetime.fromisoformat(str(ts_str).replace("Z", "+00:00"))
    return dt.astimezone(timezone.utc).replace(tzinfo=None)


def generate_trades_realistic(
    candles: List[Dict],
    bars_per_day: int = 24,
    stop_atr: float = TB_STOP_ATR_MULT,
    target_atr: float = TB_TARGET_ATR_MULT,
    max_bars: int = TB_MAX_BARS,
    fee_pct: float = TB_FEE_TAKER_PCT,
    slippage_pct: float = TB_SLIPPAGE_PCT,
    atr_period: int = TB_ATR_PERIOD,
    progress_every_pct: float = 5.0,
    label: str = "asset",
) -> List[Dict]:
    """
    Gera trades aplicando whitelist v2 strict_v2 + triple barrier path-dependent.

    Args:
        candles: lista ordenada por tempo crescente
        bars_per_day: 24 para hourly, 1 para daily
        Demais: ver triple_barrier_simulator.simulate_trade

    Returns:
        lista de trades {entry_ts, regime, direction, result_r, exit_reason,
                          holding_bars, entry_price, atr_at_entry}
    """
    trades = []
    min_history = max(210, atr_period + 1)
    MAX_WINDOW = WMA200_BARS_DAILY * bars_per_day + 100

    print(f"[gen-real:{label}] Pré-convertendo {len(candles)} candles ...")
    all_dicts = [candle_to_dict(c) for c in candles]

    total = len(candles) - 1 - min_history
    print(f"[gen-real:{label}] Processando {total} iterações "
          f"(window={MAX_WINDOW}, stop={stop_atr}*ATR, target={target_atr}*ATR, "
          f"timeout={max_bars}h, fee+slip={fee_pct+slippage_pct:.4f}/lado) ...")

    pct_step = max(1, int(total * progress_every_pct / 100))

    for i in range(min_history, len(candles) - 1):
        if (i - min_history) % pct_step == 0 and i > min_history:
            pct = ((i - min_history) / total) * 100
            print(f"[gen-real:{label}]   {pct:5.1f}% trades={len(trades)}")

        start = max(0, i + 1 - MAX_WINDOW)
        window = all_dicts[start:i + 1]

        try:
            regime = classify_regime(window, bars_per_day=bars_per_day)
        except Exception:
            continue

        ts_str = candles[i].get("ts", "")
        try:
            dt_entry = parse_ts(ts_str)
        except Exception:
            continue

        # day_of_week BRT (UTC-3)
        dt_brt = dt_entry - timedelta(hours=3)
        python_dow = dt_brt.weekday()
        our_dow = (python_dow + 1) % 7  # Mon=1...Sun=0

        signal_final, reason = apply_regime_filter(
            signal="COMPRA",
            regime=regime,
            mode="strict_v2",
            day_of_week_brt=our_dow,
        )

        if signal_final != "COMPRA":
            continue

        # ATR at entry (last atr_period+1 candles antes do entry)
        atr_window = all_dicts[max(0, i - atr_period):i + 1]
        try:
            atr_val = atr_indicator(atr_window, period=atr_period)
        except (ValueError, Exception):
            continue

        if atr_val <= 0:
            continue

        # Simula trade com triple barrier (usa candles[i:] como forward path)
        sim = simulate_trade(
            entry_idx=i,
            candles=all_dicts,
            direction="LONG",
            atr_value=atr_val,
            stop_atr=stop_atr,
            target_atr=target_atr,
            max_bars=max_bars,
            fee_pct=fee_pct,
            slippage_pct=slippage_pct,
        )

        if sim["exit_reason"] == "invalid":
            continue

        trades.append({
            "entry_ts": dt_entry.strftime("%Y-%m-%dT%H:%M:%S+00:00"),
            "regime": regime,
            "direction": "LONG",
            "result_r": round(sim["result_r"], 4),
            "exit_reason": sim["exit_reason"],
            "holding_bars": sim["holding_bars"],
            "entry_price": round(all_dicts[i]["close"], 6),
            "atr_at_entry": round(atr_val, 6),
            "reason": reason,
            "day_of_week_brt": our_dow,
        })

    print(f"[gen-real:{label}] {len(trades)} trades gerados")
    return trades
