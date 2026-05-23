"""
compare_v1_v2.py — Roda v1 e v2 in-memory no mesmo dataset e compara métricas.
Usa 4h como HTF para o MTF alignment do v2.
"""
import argparse
import os
from typing import Dict, List, Optional

from db import Database
from signal_generator import (
    generate_signal, _regime_for_window, SMA200_PERIOD, MIN_CANDLES,
)
from signal_generator_v2 import generate_signal_v2
from trade_simulator import simulate_trade
from metrics import calc_metrics, calc_metrics_by_regime
from backtest_runner import MAX_BARS_FORWARD, REGIME_LOOKBACK, BacktestRunner


def _find_htf_window(htf_candles: List[Dict], ts: str) -> List[Dict]:
    """Retorna candles HTF cujo ts <= ts informado (zero lookahead)."""
    return [c for c in htf_candles if c["ts"] <= ts]


def _run_pipeline(
    candles: List[Dict],
    htf_candles: Optional[List[Dict]],
    use_v2: bool,
    filter_sideways: bool,
) -> dict:
    signals = []
    total = len(candles)
    for i in range(MIN_CANDLES, total):
        window = candles[max(0, i - SMA200_PERIOD + 1):i + 1]
        if filter_sideways and _regime_for_window(window) == "sideways":
            continue
        if use_v2:
            htf_win = _find_htf_window(htf_candles, candles[i]["ts"]) if htf_candles else None
            result = generate_signal_v2(window, candles_htf=htf_win)
        else:
            result = generate_signal(window)
        if not result.is_actionable:
            continue
        signals.append({
            "bar_i": i,
            "signal": result.signal,
            "entry_price": result.entry_price,
            "stop_loss": result.stop_loss,
            "take_profit": result.take_profit,
        })

    r_series, regimes = [], []
    runner_dummy = BacktestRunner(db=None)
    for sig in signals:
        i = sig["bar_i"]
        forward = candles[i + 1:i + 1 + MAX_BARS_FORWARD]
        if not forward:
            continue
        direction = "LONG" if sig["signal"] == "COMPRA" else "SHORT"
        result = simulate_trade(
            direction=direction, entry=sig["entry_price"],
            stop=sig["stop_loss"], target=sig["take_profit"],
            candles=forward, fee_pct=0.10,
        )
        context = candles[max(0, i - REGIME_LOOKBACK + 1):i + 1]
        regime = runner_dummy._classify_by_sma200(context)
        r_series.append(result.result_r)
        regimes.append(regime)

    if not r_series:
        return {"trades": 0}

    m = calc_metrics(r_series)
    by_r = calc_metrics_by_regime(r_series, regimes)
    bull_exp = by_r.bull.expectancy_r if by_r.bull else 0.0
    bear_exp = by_r.bear.expectancy_r if by_r.bear else 0.0
    pf = m.profit_factor if m.profit_factor != float("inf") else 999.0

    return {
        "trades": m.total_trades,
        "win_rate": m.win_rate,
        "expectancy": m.expectancy_r,
        "pf": pf,
        "drawdown": m.max_drawdown_r,
        "bull_exp": bull_exp,
        "bear_exp": bear_exp,
    }


def main():
    parser = argparse.ArgumentParser(description="Comparar v1 vs v2 no mesmo dataset")
    parser.add_argument("--market", default="BTCUSDT")
    parser.add_argument("--start", required=True)
    parser.add_argument("--end", required=True)
    parser.add_argument("--ltf", default="1hour", help="Timeframe operacional")
    parser.add_argument("--htf", default="4hour", help="Timeframe maior para MTF (v2)")
    args = parser.parse_args()

    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)

    print(f"\nCarregando {args.market} {args.ltf} (operacional)...")
    candles_ltf = db.get_candles(args.market, args.ltf, args.start, args.end)
    print(f"  -> {len(candles_ltf)} candles {args.ltf}")

    print(f"Carregando {args.market} {args.htf} (HTF para v2)...")
    candles_htf = db.get_candles(args.market, args.htf, args.start, args.end)
    print(f"  -> {len(candles_htf)} candles {args.htf}")
    if not candles_htf:
        print("  AVISO: sem dados HTF. v2 rodará sem MTF alignment.")

    print("\n=== Rodando v1 ===", flush=True)
    r_v1 = _run_pipeline(candles_ltf, htf_candles=None, use_v2=False, filter_sideways=True)
    print("\n=== Rodando v2 (com MTF) ===", flush=True)
    r_v2 = _run_pipeline(candles_ltf, htf_candles=candles_htf, use_v2=True, filter_sideways=True)

    print("\n" + "=" * 80)
    print(f"COMPARATIVO v1 vs v2 — {args.market} {args.ltf} {args.start}->{args.end}")
    print("=" * 80)
    fmt = "{:<12} | {:>8} | {:>7} | {:>10} | {:>5} | {:>8} | {:>9} | {:>9}"
    print(fmt.format("Version", "Trades", "Win%", "Expectancy", "PF", "DD(R)", "BULL exp", "BEAR exp"))
    print("-" * 80)
    for name, r in [("v1", r_v1), ("v2 (MTF)", r_v2)]:
        if r["trades"] == 0:
            print(f"{name:<12} | (sem trades)")
            continue
        print(fmt.format(
            name,
            r["trades"],
            f"{r['win_rate']:.1f}%",
            f"{r['expectancy']:+.3f}R",
            f"{r['pf']:.2f}",
            f"{r['drawdown']:.0f}",
            f"{r['bull_exp']:+.3f}R",
            f"{r['bear_exp']:+.3f}R",
        ))
    print("=" * 80)


if __name__ == "__main__":
    main()
