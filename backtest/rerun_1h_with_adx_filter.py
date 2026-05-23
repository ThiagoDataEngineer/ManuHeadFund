"""rerun_1h_with_adx_filter.py — Re-roda backtest BTCUSDT 1h com ADX hard filter ativo.

Baseline (sem filter, documentado):
  134 trades | win 33.6% | exp +0.090R | PF 1.14 | BULL +0.578R / BEAR -0.035R / SIDEWAYS -0.084R

Hipotese: filter bloqueia signals em sideways onde edge nao existe.
"""
import os
import sys

try: sys.stdout.reconfigure(encoding="utf-8")
except Exception: pass

from dotenv import load_dotenv
load_dotenv()

from db import Database
from signal_generator import generate_signal, MIN_CANDLES, _regime_for_window
from trade_simulator import simulate_trade
from metrics import calc_metrics, calc_metrics_by_regime, classify_regime

MARKET = "BTCUSDT"
PERIOD = "1hour"
START  = "2024-11-01"
END    = "2025-06-01"
MAX_BARS_FORWARD = 50
REGIME_LOOKBACK = 200
FEE_PCT = 0.10


def main():
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    candles = db.get_candles(MARKET, PERIOD, START, END)
    print(f"  {len(candles)} candles 1h carregados ({START} -> {END})")

    if len(candles) < 200:
        print("  Candles insuficientes."); return

    trades = []
    blocked_by_adx = 0
    no_signal = 0

    skipped_sideways = 0
    filter_sideways = "--no-side-filter" not in sys.argv  # default ON pra comparar com baseline
    for i in range(MIN_CANDLES, len(candles)):
        window = candles[max(0, i - REGIME_LOOKBACK + 1): i + 1]

        if filter_sideways:
            regime_pre = _regime_for_window(window)
            if regime_pre == "sideways":
                skipped_sideways += 1
                continue

        result = generate_signal(window)
        ind = result.indicators or {}

        if ind.get("adx_blocked") is True and result.signal == "NEUTRO":
            blocked_by_adx += 1

        if not result.is_actionable:
            no_signal += 1
            continue

        forward = candles[i + 1: i + 1 + MAX_BARS_FORWARD]
        if not forward:
            continue

        direction = "LONG" if result.signal == "COMPRA" else "SHORT"
        sim = simulate_trade(direction=direction, entry=result.entry_price,
                             stop=result.stop_loss, target=result.take_profit,
                             candles=forward, fee_pct=FEE_PCT)

        # Regime via SMA200
        closes = [c["close"] for c in window[-200:]] if len(window) >= 200 else None
        regime = "sideways"
        if closes:
            sma200 = sum(closes) / 200
            regime = classify_regime(window[-1]["close"], sma200)

        trades.append({"result_r": sim.result_r, "regime": regime, "score": result.score,
                       "direction": direction})

    if not trades:
        print("  Sem trades gerados.")
        return

    rs = [t["result_r"] for t in trades]
    regs = [t["regime"] for t in trades]
    m = calc_metrics(rs)
    br = calc_metrics_by_regime(rs, regs)

    sep = "=" * 70
    print(f"\n{sep}")
    print(f"  BACKTEST 1h COM ADX HARD FILTER — {MARKET} {START}..{END}")
    print(sep)
    print(f"  Bars analisados:      {len(candles) - MIN_CANDLES}")
    print(f"  filter_sideways:      {filter_sideways}")
    print(f"  Skipped (sideways):   {skipped_sideways}")
    print(f"  Bloqueados por ADX:   {blocked_by_adx}")
    print(f"  Sem sinal acionavel:  {no_signal}")
    print(f"  Trades gerados:       {m.total_trades}")
    print(f"  Win rate:             {m.win_rate:.1f}%")
    print(f"  Expectancy:           {m.expectancy_r:+.3f}R")
    print(f"  Profit Factor:        {m.profit_factor:.2f}")
    print(f"  Max Drawdown:         {m.max_drawdown_r:.2f}R")
    print(f"  Sharpe:               {m.sharpe_ratio:.3f}")
    print(sep)
    print("  POR REGIME (SMA200)")
    for label, rm in [("BULL", br.bull), ("BEAR", br.bear), ("SIDEWAYS", br.sideways)]:
        if rm is None:
            print(f"  {label:<10}  sem trades")
            continue
        flag = "[OK]" if rm.expectancy_r > 0.3 else "[--]"
        print(f"  {label:<10} n={rm.total_trades:3d}  win={rm.win_rate:5.1f}%  "
              f"exp={rm.expectancy_r:+.3f}R  {flag}")
    print(sep)

    print("\n  COMPARATIVO vs BASELINE (sem filter, documentado):")
    print(f"  {'Metric':<14} {'baseline':>10} {'with_adx':>10} {'delta':>10}")
    base = {"trades": 134, "win": 33.6, "exp": 0.090, "pf": 1.14,
            "bull_exp": 0.578, "bear_exp": -0.035, "side_exp": -0.084}
    print(f"  {'trades':<14} {base['trades']:>10} {m.total_trades:>10} {m.total_trades-base['trades']:>+10}")
    print(f"  {'win%':<14} {base['win']:>9.1f}% {m.win_rate:>9.1f}% {m.win_rate-base['win']:>+9.1f}")
    print(f"  {'exp(R)':<14} {base['exp']:>+9.3f} {m.expectancy_r:>+9.3f} {m.expectancy_r-base['exp']:>+9.3f}")
    print(f"  {'PF':<14} {base['pf']:>10.2f} {m.profit_factor:>10.2f} {m.profit_factor-base['pf']:>+10.2f}")
    if br.bull:    print(f"  {'BULL exp':<14} {base['bull_exp']:>+9.3f} {br.bull.expectancy_r:>+9.3f} {br.bull.expectancy_r-base['bull_exp']:>+9.3f}")
    if br.bear:    print(f"  {'BEAR exp':<14} {base['bear_exp']:>+9.3f} {br.bear.expectancy_r:>+9.3f} {br.bear.expectancy_r-base['bear_exp']:>+9.3f}")
    if br.sideways:print(f"  {'SIDE exp':<14} {base['side_exp']:>+9.3f} {br.sideways.expectancy_r:>+9.3f} {br.sideways.expectancy_r-base['side_exp']:>+9.3f}")
    print(sep)


if __name__ == "__main__":
    main()
