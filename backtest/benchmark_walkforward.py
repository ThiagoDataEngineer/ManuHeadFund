"""
benchmark_walkforward.py — Walk-forward validation do baseline V2

Para CONFIG FIXA (KB-fix + LONG only + RR>=5 + equity stop -10R),
mede consistência em múltiplas janelas temporais + pares.

Diferença de optimize_walkforward.py:
  - Este: VALIDA config fixa em múltiplas janelas
  - optimize_walkforward.py: OTIMIZA parâmetros via Optuna

Saída: journal/benchmark_walkforward_results.json
"""
import os
import sys
import json
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(__file__))

from db import Database
from signal_generator import generate_signal, SMA200_PERIOD, MIN_CANDLES
from trade_simulator import simulate_trade
from metrics import calc_metrics, calc_metrics_by_regime
from backtest_runner import MAX_BARS_FORWARD, REGIME_LOOKBACK, BacktestRunner


EQUITY_STOP_R = -10.0


def run_window(db, market, start, end, label):
    """Roda baseline V2 (LONG+RR5+equity_stop) em uma janela e retorna metrics + per-trade R."""
    candles = db.get_candles(market, "1hour", start, end)
    if not candles or len(candles) < MIN_CANDLES + 10:
        return None

    runner = BacktestRunner(db=None)
    signals = []
    equity = 0.0
    peak = 0.0
    skipped = 0

    for i in range(MIN_CANDLES, len(candles)):
        # Equity stop check
        if peak - equity >= abs(EQUITY_STOP_R):
            if equity > peak:
                peak = equity
            else:
                skipped += 1
                continue
            if peak - equity < abs(EQUITY_STOP_R):
                pass

        window = candles[max(0, i - SMA200_PERIOD + 1):i + 1]
        result = generate_signal(window)
        if not result.is_actionable:
            continue
        if result.signal != "COMPRA":
            continue
        if result.rr_ratio < 5.0:
            continue

        forward = candles[i + 1:i + 1 + MAX_BARS_FORWARD]
        if not forward:
            continue

        sim = simulate_trade(
            direction="LONG",
            entry=result.entry_price,
            stop=result.stop_loss,
            target=result.take_profit,
            candles=forward,
            fee_pct=0.10,
        )

        context = candles[max(0, i - REGIME_LOOKBACK + 1):i + 1]
        regime = runner._classify_by_sma200(context)
        signals.append({"r": sim.result_r, "regime": regime})

        equity += sim.result_r
        if equity > peak:
            peak = equity

    if not signals:
        return None

    rs = [s["r"] for s in signals]
    regs = [s["regime"] for s in signals]
    m = calc_metrics(rs)
    by_r = calc_metrics_by_regime(rs, regs)

    return {
        "label": label,
        "market": market,
        "period": f"{start} to {end}",
        "trades": m.total_trades,
        "skipped_by_stop": skipped,
        "win_rate": round(m.win_rate, 3),
        "expectancy_r": round(m.expectancy_r, 3),
        "profit_factor": round(m.profit_factor, 2) if m.profit_factor != float("inf") else 999.0,
        "equity_final_r": round(equity, 2),
        "max_dd_r": round(peak - min(0.0, equity), 2),
        "by_regime": {
            "bull":     {"n": by_r.bull.total_trades, "exp": round(by_r.bull.expectancy_r, 3)} if by_r.bull else None,
            "bear":     {"n": by_r.bear.total_trades, "exp": round(by_r.bear.expectancy_r, 3)} if by_r.bear else None,
            "sideways": {"n": by_r.sideways.total_trades, "exp": round(by_r.sideways.expectancy_r, 3)} if by_r.sideways else None,
        },
        "raw_returns": rs,  # para ergodicity
    }


def main():
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ.get("SUPABASE_ANON_KEY")
    if not key:
        print("[ERRO] SUPABASE keys nao configuradas")
        sys.exit(1)
    db = Database(url=os.environ["SUPABASE_URL"], key=key)

    # 5 janelas: 3 originais + 2 adicionais para reforçar
    windows = [
        ("BTCUSDT", "2024-11-01", "2025-05-01", "btc_window_1_full"),
        ("BTCUSDT", "2024-11-01", "2025-02-01", "btc_window_2_q1"),
        ("BTCUSDT", "2025-02-01", "2025-05-01", "btc_window_3_q2"),
        ("BTCUSDT", "2025-05-01", "2025-11-01", "btc_window_4_oos"),
        ("ETHUSDT", "2024-11-01", "2025-05-01", "eth_window_5_pair_oos"),
    ]

    results = []
    for market, start, end, label in windows:
        print(f"  Rodando {label}: {market} {start} -> {end}")
        r = run_window(db, market, start, end, label)
        if r:
            results.append(r)

    if not results:
        print("[ERRO] Nenhum resultado gerado")
        sys.exit(1)

    # Ergodicity entre janelas
    all_returns_by_regime = {"bull": [], "bear": [], "sideways": []}
    for r in results:
        for s in zip(r["raw_returns"],
                     ["bull" if br and br["n"] > 0 else "" for br in [r["by_regime"]["bull"]]]):
            pass

    # Ergodicity score baseado em consistência entre janelas
    expectancies = [r["expectancy_r"] for r in results]
    pfs = [r["profit_factor"] for r in results if r["profit_factor"] != 999.0]

    expectancy_min = min(expectancies)
    expectancy_max = max(expectancies)
    expectancy_consistency = expectancy_min / expectancy_max if expectancy_max > 0 else 0

    pf_min = min(pfs) if pfs else 0
    pf_max = max(pfs) if pfs else 0
    pf_consistency = pf_min / pf_max if pf_max > 0 else 0

    # Ergodicity sintética: produto de consistências (0-1)
    ergodicity = (expectancy_consistency + pf_consistency) / 2

    positive_windows = sum(1 for r in results if r["expectancy_r"] > 0)
    all_positive = positive_windows == len(results)

    go_criterion_passed = ergodicity >= 0.65 and all_positive

    output = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "config": "baseline_v2: KB-fix + LONG only + RR>=5 + equity stop -10R",
        "windows": [{k: v for k, v in r.items() if k != "raw_returns"} for r in results],
        "consistency": {
            "expectancy_min": round(expectancy_min, 3),
            "expectancy_max": round(expectancy_max, 3),
            "expectancy_consistency_ratio": round(expectancy_consistency, 3),
            "pf_min": round(pf_min, 2),
            "pf_max": round(pf_max, 2),
            "pf_consistency_ratio": round(pf_consistency, 3),
            "ergodicity_synthetic": round(ergodicity, 3),
            "positive_windows": f"{positive_windows}/{len(results)}",
        },
        "go_live_criterion": {
            "rule": "Ergodicity >= 0.65 + expectancy positiva em todas janelas",
            "ergodicity": round(ergodicity, 3),
            "all_positive": all_positive,
            "passed": go_criterion_passed,
            "explanation": (
                f"Ergodicity {ergodicity:.3f} {'>=' if ergodicity >= 0.65 else '<'} 0.65 threshold. "
                f"{'Todas' if all_positive else 'Nem todas'} as janelas com expectancy positiva."
            ),
        },
    }

    out_path = os.path.join(os.path.dirname(__file__), "..", "journal", "benchmark_walkforward_results.json")
    out_path = os.path.normpath(out_path)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2)
    print(f"\nResultado: {out_path}")
    print(f"GO criterion: {'PASSED' if go_criterion_passed else 'FAILED'}")
    print(f"  Ergodicity: {ergodicity:.3f}")
    print(f"  Positive windows: {positive_windows}/{len(results)}")


if __name__ == "__main__":
    main()
