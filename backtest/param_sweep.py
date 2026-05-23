"""
param_sweep.py — Varredura de parâmetros do signal_generator + backtest_runner.
Para cada valor do parâmetro testado, gera sinais → simula trades → coleta métricas.

Uso:
    from param_sweep import sweep_score_threshold
    results = sweep_score_threshold(
        market="BTCUSDT", period="1hour",
        date_from="2024-01-01", date_to="2026-04-30",
        values=[65, 70, 75, 80, 85],
        filter_sideways=True,
    )
    for r in sorted(results, key=lambda x: -x.expectancy_r):
        print(r)
"""
from dataclasses import dataclass
from typing import List, Optional


@dataclass
class SweepResult:
    param_name: str
    param_value: float
    total_trades: int
    win_rate: float            # %
    expectancy_r: float
    profit_factor: float
    max_drawdown_r: float
    bull_expectancy: float
    bear_expectancy: float

    def __str__(self) -> str:
        return (f"{self.param_name}={self.param_value:>5.1f} | "
                f"n={self.total_trades:>5d} | win={self.win_rate:>4.1f}% | "
                f"exp={self.expectancy_r:+.3f}R | PF={self.profit_factor:.2f} | "
                f"DD={self.max_drawdown_r:.0f}R | "
                f"BULL={self.bull_expectancy:+.3f}R BEAR={self.bear_expectancy:+.3f}R")


def _run_one(
    market: str,
    period: str,
    date_from: str,
    date_to: str,
    score_threshold: float,
    filter_sideways: bool,
    rr_override: Optional[float] = None,
    param_name: str = "score_threshold",
) -> Optional[SweepResult]:
    """Executa signal_generator + backtest in-memory para um threshold."""
    import os
    from db import Database
    from signal_generator import SignalGenerator, generate_signal, _regime_for_window, SMA200_PERIOD, MIN_CANDLES
    from trade_simulator import simulate_trade
    from metrics import calc_metrics, calc_metrics_by_regime
    from backtest_runner import MAX_BARS_FORWARD, REGIME_LOOKBACK, BacktestRunner
    import signal_generator as sg

    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)

    candles = db.get_candles(market, period, date_from, date_to)
    if not candles:
        return None

    # 1) Geração de sinais in-memory (sem persistir)
    signals = []
    total = len(candles)
    for i in range(MIN_CANDLES, total):
        window = candles[max(0, i - SMA200_PERIOD + 1):i + 1]
        if filter_sideways:
            if _regime_for_window(window) == "sideways":
                continue
        # Temporariamente força os parâmetros para este run
        orig_score = sg.SCORE_THRESHOLD
        orig_rr = sg.RR_DEFAULT
        sg.SCORE_THRESHOLD = score_threshold
        if rr_override is not None:
            sg.RR_DEFAULT = rr_override
        try:
            result = generate_signal(window)
        finally:
            sg.SCORE_THRESHOLD = orig_score
            sg.RR_DEFAULT = orig_rr
        if not result.is_actionable:
            continue
        signals.append({
            "bar_ts": candles[i]["ts"],
            "bar_i": i,
            "signal": result.signal,
            "entry_price": result.entry_price,
            "stop_loss": result.stop_loss,
            "take_profit": result.take_profit,
        })

    if not signals:
        return SweepResult("score_threshold", score_threshold, 0, 0, 0, 0, 0, 0, 0)

    # 2) Simulação de trades in-memory
    r_series: List[float] = []
    regimes: List[str] = []
    runner_dummy = BacktestRunner(db=db)
    for sig in signals:
        i = sig["bar_i"]
        forward = candles[i + 1:i + 1 + MAX_BARS_FORWARD]
        if not forward:
            continue
        direction = "LONG" if sig["signal"] == "COMPRA" else "SHORT"
        result = simulate_trade(
            direction=direction,
            entry=sig["entry_price"],
            stop=sig["stop_loss"],
            target=sig["take_profit"],
            candles=forward,
            fee_pct=0.10,
        )
        context = candles[max(0, i - REGIME_LOOKBACK + 1):i + 1]
        regime = runner_dummy._classify_by_sma200(context)
        r_series.append(result.result_r)
        regimes.append(regime)

    if not r_series:
        return SweepResult("score_threshold", score_threshold, 0, 0, 0, 0, 0, 0, 0)

    combined = calc_metrics(r_series)
    by_regime = calc_metrics_by_regime(r_series, regimes)

    bull_exp = by_regime.bull.expectancy_r if by_regime.bull else 0.0
    bear_exp = by_regime.bear.expectancy_r if by_regime.bear else 0.0

    pf = combined.profit_factor if combined.profit_factor != float("inf") else 999.0
    value = rr_override if rr_override is not None else score_threshold
    return SweepResult(
        param_name=param_name,
        param_value=value,
        total_trades=combined.total_trades,
        win_rate=combined.win_rate,
        expectancy_r=combined.expectancy_r,
        profit_factor=pf,
        max_drawdown_r=combined.max_drawdown_r,
        bull_expectancy=bull_exp,
        bear_expectancy=bear_exp,
    )


def sweep_score_threshold(
    market: str,
    period: str,
    date_from: str,
    date_to: str,
    values: List[float],
    filter_sideways: bool = True,
    dry_run: bool = False,
) -> List[SweepResult]:
    """Varre uma lista de SCORE_THRESHOLD valores e retorna métricas para cada."""
    if dry_run:
        # Para testes unitários: retorna resultados sintéticos que respeitam ordem (threshold maior = menos trades)
        return [
            SweepResult(
                param_name="score_threshold",
                param_value=v,
                total_trades=max(10, int(2000 * (1 - (v - 65) / 50))),
                win_rate=30.0 + (v - 65) * 0.3,
                expectancy_r=0.05 + (v - 65) * 0.01,
                profit_factor=1.1 + (v - 65) * 0.02,
                max_drawdown_r=200.0 - (v - 65) * 2,
                bull_expectancy=0.1 + (v - 65) * 0.01,
                bear_expectancy=0.05 + (v - 65) * 0.005,
            )
            for v in values
        ]

    results = []
    for v in values:
        print(f"\n=== Sweep score_threshold={v} ===", flush=True)
        r = _run_one(market, period, date_from, date_to, v, filter_sideways)
        if r:
            print(r, flush=True)
            results.append(r)
    return results


def sweep_rr_default(
    market: str,
    period: str,
    date_from: str,
    date_to: str,
    values: List[float],
    score_threshold: float = 65.0,
    filter_sideways: bool = True,
) -> List[SweepResult]:
    """Varre RR_DEFAULT mantendo SCORE_THRESHOLD fixo."""
    results = []
    for rr in values:
        print(f"\n=== Sweep rr_default={rr} (score_threshold={score_threshold}) ===", flush=True)
        r = _run_one(
            market, period, date_from, date_to,
            score_threshold=score_threshold,
            filter_sideways=filter_sideways,
            rr_override=rr,
            param_name="rr_default",
        )
        if r:
            print(r, flush=True)
            results.append(r)
    return results


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Sweep de parâmetros do signal_generator")
    parser.add_argument("--market", default="BTCUSDT")
    parser.add_argument("--period", default="1hour")
    parser.add_argument("--start", required=True)
    parser.add_argument("--end", required=True)
    parser.add_argument("--param", choices=["score", "rr"], default="score",
                        help="Parametro a varrer: score (SCORE_THRESHOLD) ou rr (RR_DEFAULT)")
    parser.add_argument("--values", type=float, nargs="+", required=True,
                        help="Lista de valores (ex: --values 65 70 75 80 85)")
    parser.add_argument("--score-threshold", type=float, default=65.0,
                        help="SCORE_THRESHOLD fixo quando --param=rr")
    parser.add_argument("--no-filter-sideways", action="store_true")
    args = parser.parse_args()

    pname = "SCORE_THRESHOLD" if args.param == "score" else "RR_DEFAULT"
    print(f"\n=== Sweep {pname} em {args.market} {args.period} {args.start}->{args.end} ===")
    print(f"Values: {args.values}")
    print(f"Filter sideways: {not args.no_filter_sideways}")

    if args.param == "score":
        results = sweep_score_threshold(
            market=args.market, period=args.period,
            date_from=args.start, date_to=args.end,
            values=args.values,
            filter_sideways=not args.no_filter_sideways,
        )
    else:
        results = sweep_rr_default(
            market=args.market, period=args.period,
            date_from=args.start, date_to=args.end,
            values=args.values,
            score_threshold=args.score_threshold,
            filter_sideways=not args.no_filter_sideways,
        )

    print("\n" + "=" * 80)
    print("RANKING (por expectancy):")
    print("=" * 80)
    valid = [r for r in results if r.total_trades >= 100]
    for r in sorted(valid, key=lambda x: -x.expectancy_r):
        print(r)
    if len(valid) < len(results):
        print(f"\n(excluídos {len(results) - len(valid)} resultados com n < 100)")


if __name__ == "__main__":
    main()
