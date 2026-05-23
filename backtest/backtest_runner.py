"""
backtest_runner.py — Executa trade_simulator sobre sinais históricos → backtest_trades + backtest_runs

Pipeline:
    backtest_signals (DB)
        → simulate_trade(candles forward, MAX_BARS_FORWARD bars)
        → classify_regime(SMA200 dos candles anteriores)
        → backtest_trades (INSERT por trade)
        → calc_metrics_by_regime
        → backtest_runs (INSERT resumo)

Uso:
    python backtest_runner.py --market BTCUSDT --period 1hour \
                              --start 2023-01-01 --end 2025-01-01
"""
import argparse
import os
from typing import Dict, List, Optional

from metrics import (
    BacktestMetrics, RegimeBreakdown,
    calc_metrics, calc_metrics_by_regime, classify_regime,
)
from report import generate_html_report
from trade_simulator import simulate_trade, calc_position_size

MAX_BARS_FORWARD = 50    # janela de simulação após o sinal
REGIME_LOOKBACK  = 200   # candles para calcular SMA200


class BacktestRunner:
    # DRIFT-3 fix 2026-05-16: fee_pct alinhado com CoinEx real (docs/CONSTANTS.md).
    # Antes: 0.10% (10 bps) hardcoded -> backtest 25% pessimista vs live (0.08%).
    # Live: $COINEX_FEE_ROUNDTRIP_FALLBACK = 0.0008 (config.ps1:91).
    # Maker+Taker round-trip = 0.03%+0.05% = 0.08% para VIP 0. VIPs maiores: menor.
    def __init__(self, db, capital: float = 1000.0, fee_pct: float = 0.08):
        self.db = db
        self.capital = capital
        self.fee_pct = fee_pct
        self._last_regime: Optional[RegimeBreakdown] = None   # disponível após run()

    def _classify_by_sma200(self, candles: List[Dict]) -> str:
        """Classifica regime pelo SMA200 dos candles fornecidos.
        Retorna 'sideways' se houver menos de 200 candles (conservador).
        """
        if len(candles) < 200:
            return "sideways"
        closes = [c["close"] for c in candles[-200:]]
        sma200 = sum(closes) / 200.0
        return classify_regime(candles[-1]["close"], sma200)

    def run(self, market: str, period: str, date_from: str, date_to: str) -> int:
        signals = self.db.get_signals(market, period, date_from, date_to)
        candles = self.db.get_candles(market, period, date_from, date_to)

        if not signals or not candles:
            return 0

        ts_index: Dict[str, int] = {c["ts"]: i for i, c in enumerate(candles)}

        r_series: List[float] = []
        regimes:  List[str]   = []
        trade_buffer: List[Dict] = []

        for sig in signals:
            bar_i = ts_index.get(sig["bar_ts"])
            if bar_i is None:
                continue

            forward = candles[bar_i + 1 : bar_i + 1 + MAX_BARS_FORWARD]
            if not forward:
                continue

            direction = "LONG" if sig["signal"] == "COMPRA" else "SHORT"
            entry = float(sig["entry_price"])
            stop  = float(sig["stop_loss"])
            target = float(sig["take_profit"])

            result = simulate_trade(
                direction=direction,
                entry=entry,
                stop=stop,
                target=target,
                candles=forward,
                fee_pct=self.fee_pct,
            )

            context = candles[max(0, bar_i - REGIME_LOOKBACK + 1) : bar_i + 1]
            regime = self._classify_by_sma200(context)

            try:
                capital_used = calc_position_size(
                    self.capital, entry, stop, direction=direction
                )
            except (ValueError, ZeroDivisionError):
                capital_used = 0.0

            exit_bar = forward[min(result.bars_held, len(forward)) - 1]

            trade_row = {
                "signal_id":   sig.get("id"),
                "market":      market,
                "direction":   direction,
                "entry_ts":    sig["bar_ts"],
                "exit_ts":     exit_bar["ts"],
                "entry_price": entry,
                "exit_price":  result.exit_price,
                "stop_loss":   stop,
                "take_profit": target,
                "exit_reason": result.exit_reason,
                "result_r":    round(result.result_r, 4),
                "pnl_pct":     round(result.pnl_pct, 4),
                "fee_pct":     self.fee_pct,
                "capital_used": round(capital_used, 2),
                "regime":      regime,
            }
            trade_buffer.append(trade_row)

            r_series.append(result.result_r)
            regimes.append(regime)

        if not r_series:
            return 0

        self.db.insert_trades_bulk(trade_buffer)

        combined   = calc_metrics(r_series)
        by_regime  = calc_metrics_by_regime(r_series, regimes)

        def _f(v: float) -> Optional[float]:
            """Sanitiza inf/-inf/NaN para None (JSON-safe)."""
            if v != v or v == float("inf") or v == float("-inf"):
                return None
            return v

        def _regime_dict(m: Optional[BacktestMetrics]) -> Optional[dict]:
            if m is None:
                return None
            return {
                "total_trades":  m.total_trades,
                "win_rate":      round(m.win_rate, 2),
                "expectancy_r":  round(m.expectancy_r, 4),
                "profit_factor": _f(round(m.profit_factor, 4)),
                "sharpe_ratio":  _f(round(m.sharpe_ratio, 4)),
            }

        run_row = {
            "market":          market,
            "period":          period,
            "date_from":       date_from,
            "date_to":         date_to,
            "capital_initial": self.capital,
            "total_trades":    combined.total_trades,
            "winning_trades":  combined.winning_trades,
            "win_rate":        round(combined.win_rate, 2),
            "expectancy_r":    round(combined.expectancy_r, 4),
            "profit_factor":   _f(round(combined.profit_factor, 4)),
            "max_drawdown":    round(combined.max_drawdown_r, 4),
            "sharpe_ratio":    _f(round(combined.sharpe_ratio, 4)),
            "regime_breakdown": {
                "bull":      _regime_dict(by_regime.bull),
                "bear":      _regime_dict(by_regime.bear),
                "sideways":  _regime_dict(by_regime.sideways),
                "counts":    by_regime.regime_counts,
            },
        }
        self.db.insert_run(run_row)

        self._last_regime = by_regime
        _print_report(market, period, combined, by_regime)
        return combined.total_trades

    def save_html(
        self,
        run_row: Dict,
        regime: RegimeBreakdown,
        output_path: str = "backtest_report.html",
    ) -> str:
        return generate_html_report(run_row, regime, output_path=output_path)


def _print_report(market: str, period: str, m: BacktestMetrics, br: RegimeBreakdown) -> None:
    sep = "-" * 52
    print(f"\n{sep}")
    print(f"  BACKTEST — {market} {period}")
    print(sep)
    print(f"  Trades:        {m.total_trades}  ({m.winning_trades} wins, {m.win_rate:.1f}%)")
    print(f"  Expectancy:    {m.expectancy_r:+.3f}R")
    print(f"  Profit Factor: {m.profit_factor:.2f}")
    print(f"  Max Drawdown:  {m.max_drawdown_r:.2f}R")
    print(f"  Sharpe:        {m.sharpe_ratio:.3f}")
    print(sep)
    for regime, metrics in [("BULL", br.bull), ("BEAR", br.bear), ("SIDEWAYS", br.sideways)]:
        if metrics is None:
            continue
        flag = "[OK]" if metrics.expectancy_r > 0.3 else "[--]"
        print(f"  {regime:8s}  win={metrics.win_rate:.0f}%  "
              f"exp={metrics.expectancy_r:+.3f}R  "
              f"n={metrics.total_trades}  {flag}")
    print(sep)


def main():
    parser = argparse.ArgumentParser(description="Backtest runner -> backtest_trades + backtest_runs")
    parser.add_argument("--market",   default="BTCUSDT")
    parser.add_argument("--period",   default="1hour")
    parser.add_argument("--start",    required=True)
    parser.add_argument("--end",      required=True)
    parser.add_argument("--capital",  type=float, default=1000.0)
    parser.add_argument("--fee",      type=float, default=0.10,
                        help="Fee round-trip %% (default 0.10 = 0.1%%)")
    parser.add_argument("--html",     default="backtest_report.html",
                        help="Caminho do relatório HTML ('' para desativar)")
    args = parser.parse_args()

    from db import Database
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db  = Database(url=os.environ["SUPABASE_URL"], key=key)

    runner = BacktestRunner(db=db, capital=args.capital, fee_pct=args.fee)
    print(f"\nRunning backtest {args.market} {args.period} {args.start}->{args.end}...")
    count = runner.run(args.market, args.period, args.start, args.end)
    print(f"\nConcluido. {count} trades simulados e armazenados.")

    if args.html and count > 0:
        # gera relatório HTML com os dados do último run
        last_run = db.get_runs()[0]
        regime = runner._last_regime  # exposto pelo runner após o run
        if regime is not None:
            runner.save_html(last_run, regime, output_path=args.html)
            print(f"Relatório HTML gerado: {args.html}")


if __name__ == "__main__":
    main()
