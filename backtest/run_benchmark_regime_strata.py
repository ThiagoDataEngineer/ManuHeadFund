"""Gera journal/benchmark_regime_strata_results.json com dados reais.

Pipeline:
  1. Para cada mercado/periodo disponivel, percorre candles
  2. Em cada bar: classify_regime + generate_signal + simulate_trade
  3. Conta dias por regime (com base no regime do candle)
  4. Agrega trades por (regime, direction)
  5. Salva JSON com schema validado
"""
import os
import sys
import json
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from db import Database
from signal_generator import generate_signal, SMA200_PERIOD, MIN_CANDLES
from trade_simulator import simulate_trade
from regime_classifier import classify_regime
from benchmark_regime_strata import (
    metrics_per_regime, aggregate_results, validate_json_schema,
)
from backtest_runner import MAX_BARS_FORWARD


def collect_trades_and_regime_days(market: str, period: str, start: str, end: str, db: Database):
    candles = db.get_candles(market, period, start, end)
    if not candles or len(candles) < MIN_CANDLES + 10:
        return [], {}

    trades = []
    regime_days = {}

    bars_per_day = {"1hour": 24, "4hour": 6, "1day": 1}.get(period, 1)
    for i in range(MIN_CANDLES, len(candles)):
        window = candles[max(0, i - 1500):i + 1]   # janela mais larga para regimes
        regime = classify_regime(window, bars_per_day=bars_per_day)
        regime_days[regime] = regime_days.get(regime, 0) + 1

        sig_window = candles[max(0, i - SMA200_PERIOD + 1):i + 1]
        result = generate_signal(sig_window)
        if not result.is_actionable: continue
        if result.signal not in ("COMPRA", "VENDA"): continue

        forward = candles[i + 1:i + 1 + MAX_BARS_FORWARD]
        if not forward: continue
        direction = "LONG" if result.signal == "COMPRA" else "SHORT"
        sim = simulate_trade(
            direction=direction, entry=result.entry_price,
            stop=result.stop_loss, target=result.take_profit,
            candles=forward, fee_pct=0.10,
        )
        trades.append({
            "market": market, "period": period,
            "regime": regime, "direction": direction,
            "result_r": sim.result_r,
        })

    return trades, regime_days


def main():
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)

    datasets = [
        ("BTCUSDT", "1hour", "2024-11-01", "2025-05-01"),
        ("BTCUSDT", "1hour", "2025-05-01", "2025-11-01"),
        ("ETHUSDT", "1hour", "2024-11-01", "2025-05-01"),
    ]

    all_trades = []
    all_regime_days = {}
    sources = []
    for market, period, start, end in datasets:
        print(f"Coletando {market} {period} {start}->{end}...", flush=True)
        trades, days = collect_trades_and_regime_days(market, period, start, end, db)
        all_trades.extend(trades)
        for k, v in days.items():
            all_regime_days[k] = all_regime_days.get(k, 0) + v
        sources.append({
            "market": market, "period": period, "start": start, "end": end,
            "trades": len(trades), "bars": sum(days.values()),
        })
        print(f"  -> {len(trades)} trades, {sum(days.values())} bars")

    print(f"\nTotal: {len(all_trades)} trades em {sum(all_regime_days.values())} bars")
    print(f"Regime distribution: {all_regime_days}")

    rm = metrics_per_regime(all_trades)
    result = aggregate_results(regime_days=all_regime_days, regime_metrics=rm)

    # Metadata
    result["meta"] = {
        "generated_at": "2026-05-14",
        "data_sources": sources,
        "total_trades": len(all_trades),
        "total_bars": sum(all_regime_days.values()),
        "note": "Periodo disponivel: BTC Nov/24-Nov/25 + ETH Nov/24-Mai/25 (~18 meses corridos). Plano original previa 11y; aguardando ingest Bitstamp.",
    }

    assert validate_json_schema(result), "Schema invalido!"

    journal_dir = Path(__file__).parent.parent / "journal"
    journal_dir.mkdir(exist_ok=True)
    out = journal_dir / "benchmark_regime_strata_results.json"
    out.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"\nSalvo em {out}")

    # Tabela final
    print("\n" + "=" * 100)
    print(f"{'Regime':<18} | {'Days%':>6} | {'LONG n/exp/pf':<22} | {'SHORT n/exp/pf':<22} | {'Best':<7} | {'Edge':<8}")
    print("-" * 100)
    for r in sorted(result["by_regime"], key=lambda x: -x["days_pct"]):
        lm, sm = r["long_metrics"], r["short_metrics"]
        lstr = f"{lm['trades']:>3}/{lm['exp']:>+6.3f}R/{lm['pf']:>4.2f}"
        sstr = f"{sm['trades']:>3}/{sm['exp']:>+6.3f}R/{sm['pf']:>4.2f}"
        print(f"{r['regime']:<18} | {r['days_pct']:>5.1f}% | {lstr:<22} | {sstr:<22} | {r['best_direction']:<7} | {r['edge_strength']:<8}")
    print("=" * 100)
    g = result["go_criterion"]
    print(f"\nGO criterion: {g['rule']}")
    print(f"  {g['regimes_with_edge']}/{g['regimes_total']} regimes com edge => {'PASSED' if g['passed'] else 'NOT PASSED'}")


if __name__ == "__main__":
    main()
