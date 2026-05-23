"""
entries_cache.py — Detecção de entries DESACOPLADA de simulação.

Otimização para grid search: classify_regime + filter + ATR (caro)
roda UMA vez; simulação (rápida) roda N vezes com params diferentes.

Output entries:
    [{idx, entry_ts, regime, day_of_week_brt, atr_at_entry, entry_price}, ...]
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
from constants import TB_ATR_PERIOD, WMA200_BARS_DAILY  # noqa: E402


def _candle_to_dict(c: Dict) -> Dict:
    return {
        "ts": c.get("ts"),
        "open": float(c.get("open", 0.0)),
        "high": float(c.get("high", 0.0)),
        "low": float(c.get("low", 0.0)),
        "close": float(c.get("close", 0.0)),
        "volume": float(c.get("volume", 0.0)),
    }


def _parse_ts(ts_str: str) -> datetime:
    dt = datetime.fromisoformat(str(ts_str).replace("Z", "+00:00"))
    return dt.astimezone(timezone.utc).replace(tzinfo=None)


def detect_entries(
    candles: List[Dict],
    bars_per_day: int = 24,
    atr_period: int = TB_ATR_PERIOD,
    whitelist_mode: str = "strict_v2",
    progress_every_pct: float = 10.0,
    label: str = "asset",
    test_signals: tuple = ("COMPRA",),  # adicione "VENDA" para SHORT
) -> tuple[List[Dict], List[Dict]]:
    """
    Detecta entries aplicando whitelist v2 strict_v2.

    Args:
        test_signals: sinais a tentar por candle. Default ("COMPRA",) só LONG;
                       ("COMPRA", "VENDA") testa LONG+SHORT (use com strict_v3).

    Returns:
        (entries, all_dicts) — entries para grid search; all_dicts reusado em simulações
    """
    min_history = max(210, atr_period + 1)
    MAX_WINDOW = WMA200_BARS_DAILY * bars_per_day + 100

    print(f"[entries:{label}] Pre-convertendo {len(candles)} candles...")
    all_dicts = [_candle_to_dict(c) for c in candles]

    total = len(candles) - 1 - min_history
    pct_step = max(1, int(total * progress_every_pct / 100))
    print(f"[entries:{label}] Detectando entries em {total} iter "
          f"(whitelist={whitelist_mode}, window={MAX_WINDOW})...")

    entries = []
    for i in range(min_history, len(candles) - 1):
        if (i - min_history) % pct_step == 0 and i > min_history:
            pct = ((i - min_history) / total) * 100
            print(f"[entries:{label}]   {pct:5.1f}% entries={len(entries)}")

        start = max(0, i + 1 - MAX_WINDOW)
        window = all_dicts[start:i + 1]

        try:
            regime = classify_regime(window, bars_per_day=bars_per_day)
        except Exception:
            continue

        ts_str = candles[i].get("ts", "")
        try:
            dt_entry = _parse_ts(ts_str)
        except Exception:
            continue

        dt_brt = dt_entry - timedelta(hours=3)
        python_dow = dt_brt.weekday()
        our_dow = (python_dow + 1) % 7

        # Tenta cada sinal habilitado
        matched_dir = None
        matched_reason = None
        for sig in test_signals:
            signal_final, reason = apply_regime_filter(
                signal=sig,
                regime=regime,
                mode=whitelist_mode,
                day_of_week_brt=our_dow,
            )
            if signal_final == sig:
                matched_dir = "LONG" if sig == "COMPRA" else "SHORT"
                matched_reason = reason
                break  # primeiro sinal aprovado vence (LONG tem prioridade na ordem)
        if matched_dir is None:
            continue

        atr_window = all_dicts[max(0, i - atr_period):i + 1]
        try:
            atr_val = atr_indicator(atr_window, period=atr_period)
        except Exception:
            continue
        if atr_val <= 0:
            continue

        entries.append({
            "idx": i,
            "entry_ts": dt_entry.strftime("%Y-%m-%dT%H:%M:%S+00:00"),
            "regime": regime,
            "direction": matched_dir,
            "day_of_week_brt": our_dow,
            "atr_at_entry": atr_val,
            "entry_price": all_dicts[i]["close"],
            "reason": matched_reason,
        })

    print(f"[entries:{label}] {len(entries)} entries detectados")
    return entries, all_dicts
