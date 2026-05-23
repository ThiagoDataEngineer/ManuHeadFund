"""
study_2w_14y.py — Estudo profundo do backtest 2w/14y:
  1. Event trades — top winners de cada bull cycle com indicadores
  2. Hold-out Optuna — train pre-2018, test pos-2018, valida edge sem cherry-pick

Uso:
    python study_2w_14y.py [--n_trials 60] [--top_n 3]
"""
import argparse
import os
from typing import Dict, List, Tuple

from dotenv import load_dotenv
load_dotenv()

import optuna
optuna.logging.set_verbosity(optuna.logging.WARNING)

from db import Database
import signal_generator as sg
from trade_simulator import simulate_trade
from metrics import calc_metrics, calc_metrics_by_regime, classify_regime
from backtest_2w_14y import (
    MARKET, PERIOD_1D, START, END, RESAMPLE_DAYS,
    MAX_BARS_FORWARD, REGIME_LOOKBACK, FEE_PCT, CYCLES,
    resample_to_2w, classify_by_sma, in_cycle,
)

TRAIN_END = "2018-12-31"   # train ate fim do bear 2018 (cobre bull 2013 + bear 2014 + bull 2016-17 + bear 2018)
TEST_START = "2019-01-01"  # test 2019+ (bull 2019-21, bear 2022, bull 2023-24, 2025+)


def run_strategy(
    twoweek: List[Dict],
    score_threshold: float,
    atr_mult: float,
    rr: float,
    capture_indicators: bool = False,
) -> List[Dict]:
    """Gera sinais + simula trades com params dados. Monkey-patcha sg constants."""
    old_score, old_atr, old_rr = sg.SCORE_THRESHOLD, sg.ATR_STOP_MULT, sg.RR_DEFAULT
    sg.SCORE_THRESHOLD = score_threshold
    sg.ATR_STOP_MULT = atr_mult
    sg.RR_DEFAULT = rr

    trades: List[Dict] = []
    try:
        for i in range(35, len(twoweek)):
            window = twoweek[: i + 1]
            result = sg.generate_signal(window)
            if not result.is_actionable:
                continue
            forward = twoweek[i + 1 : i + 1 + MAX_BARS_FORWARD]
            if not forward:
                continue
            direction = "LONG" if result.signal == "COMPRA" else "SHORT"
            sim = simulate_trade(
                direction=direction,
                entry=result.entry_price,
                stop=result.stop_loss,
                target=result.take_profit,
                candles=forward,
                fee_pct=FEE_PCT,
            )
            regime = classify_by_sma(window)
            row = {
                "ts": twoweek[i]["ts"],
                "direction": direction,
                "entry": result.entry_price,
                "stop": result.stop_loss,
                "target": result.take_profit,
                "result_r": sim.result_r,
                "bars_held": sim.bars_held,
                "exit_reason": sim.exit_reason,
                "regime": regime,
                "score": result.score,
            }
            if capture_indicators:
                row["indicators"] = result.indicators
            trades.append(row)
    finally:
        sg.SCORE_THRESHOLD, sg.ATR_STOP_MULT, sg.RR_DEFAULT = old_score, old_atr, old_rr

    return trades


def study_event_trades(twoweek: List[Dict], top_n: int = 3) -> None:
    """Identifica top winners de cada bull cycle e mostra indicadores."""
    trades = run_strategy(
        twoweek,
        score_threshold=sg.SCORE_THRESHOLD,
        atr_mult=sg.ATR_STOP_MULT,
        rr=sg.RR_DEFAULT,
        capture_indicators=True,
    )

    bull_cycles = [(n, s, e) for (n, s, e) in CYCLES if "Bull" in n]
    sep = "=" * 72

    print(f"\n{sep}")
    print(f"  EVENT TRADES — top {top_n} winners por ciclo bull")
    print(sep)

    for name, cs, ce in bull_cycles:
        sub = [t for t in trades if in_cycle(t["ts"], cs, ce)]
        if not sub:
            continue
        winners = sorted([t for t in sub if t["result_r"] > 0],
                         key=lambda t: -t["result_r"])[:top_n]
        if not winners:
            print(f"\n[{name}]  sem winners")
            continue

        print(f"\n[{name}]  ({cs} -> {ce})")
        print(f"  {len(sub)} trades total | {len(winners)} top winners exibidos")
        for w in winners:
            ind = w["indicators"]
            print(f"  -> {w['ts'][:10]}  {w['direction']}  "
                  f"entry=${w['entry']:.2f}  result={w['result_r']:+.2f}R  "
                  f"({w['exit_reason']}, {w['bars_held']} bars)")
            print(f"     score={w['score']}  "
                  f"ema_cross={ind.get('ema_cross','-')}  "
                  f"above_ema50={ind.get('above_ema50','-')}  "
                  f"rsi={ind.get('rsi','-')} ({ind.get('rsi_zone','-')})  "
                  f"macd={ind.get('macd_signal','-')}  "
                  f"bb={ind.get('bb_position','-')}  "
                  f"adx={ind.get('adx','-')} ({ind.get('adx_trend','-')})  "
                  f"vol_x={ind.get('vol_ratio','-')}")

    print(f"\n{sep}")
    print("  AGGREGADO — feature frequency across all bull winners")
    print(sep)
    all_winners = [t for t in trades if t["result_r"] > 0 and t["regime"] == "bull"]
    if all_winners:
        feats: Dict[str, int] = {}
        for w in all_winners:
            ind = w["indicators"]
            for k in ("ema_cross", "rsi_zone", "macd_signal",
                      "bb_position", "adx_trend"):
                v = ind.get(k)
                if v:
                    feats[f"{k}={v}"] = feats.get(f"{k}={v}", 0) + 1
        for k, v in sorted(feats.items(), key=lambda x: -x[1]):
            pct = v / len(all_winners) * 100
            print(f"  {k:35s}  {v:3d}/{len(all_winners)}  ({pct:.0f}%)")


def study_holdout_optuna(twoweek: List[Dict], n_trials: int = 60) -> None:
    """Hold-out: optimize on train (<=2018), evaluate on test (2019+)."""
    train = [c for c in twoweek if c["ts"][:10] <= TRAIN_END]
    test_full = [c for c in twoweek if c["ts"][:10] >= TEST_START]
    # test precisa de warm-up: incluir ultimos 35 bars do train para indicadores
    test_with_warmup = train[-35:] + test_full

    print(f"\n{'=' * 72}")
    print(f"  HOLD-OUT OPTUNA — train ate {TRAIN_END}, test {TEST_START}+")
    print(f"  Train candles: {len(train)} | Test candles: {len(test_full)} (+{35} warmup)")
    print(f"  Trials: {n_trials}")
    print("=" * 72)

    def objective(trial: optuna.Trial) -> float:
        st = trial.suggest_float("score_threshold", 55.0, 80.0, step=2.5)
        am = trial.suggest_float("atr_mult", 1.0, 3.5, step=0.25)
        rr_v = trial.suggest_float("rr", 2.0, 8.0, step=0.5)

        trades = run_strategy(train, st, am, rr_v)
        if len(trades) < 10:
            return -1.0
        rs = [t["result_r"] for t in trades]
        regs = [t["regime"] for t in trades]
        try:
            br = calc_metrics_by_regime(rs, regs)
            erg = br.ergodicity_score
        except Exception:
            erg = 0.0
        m = calc_metrics(rs)
        # penaliza expectancy negativa
        if m.expectancy_r < 0:
            return -0.5 + erg * 0.3
        return erg * 0.4 + m.expectancy_r * 0.3 + (m.profit_factor / 10) * 0.3

    study = optuna.create_study(direction="maximize")
    study.optimize(objective, n_trials=n_trials, show_progress_bar=False)

    best = study.best_params
    print(f"\n  Best params (TRAIN): {best}")
    print(f"  Best objective: {study.best_value:.4f}")

    # Avaliar train e test com best params
    train_trades = run_strategy(train, best["score_threshold"], best["atr_mult"], best["rr"])
    test_trades_raw = run_strategy(test_with_warmup, best["score_threshold"], best["atr_mult"], best["rr"])
    test_trades = [t for t in test_trades_raw if t["ts"][:10] >= TEST_START]

    sep = "-" * 72
    print(f"\n{sep}")
    print(f"  {'Conjunto':<10} {'Trades':>8} {'Win%':>8} {'Exp(R)':>10} {'PF':>8} {'MaxDD':>10}")
    print(sep)
    for label, ts in [("TRAIN", train_trades), ("TEST", test_trades)]:
        if not ts:
            print(f"  {label:<10}  sem trades")
            continue
        rs = [t["result_r"] for t in ts]
        m = calc_metrics(rs)
        print(f"  {label:<10} {m.total_trades:>8} {m.win_rate:>7.1f}% "
              f"{m.expectancy_r:>+9.3f}R {m.profit_factor:>8.2f} "
              f"{m.max_drawdown_r:>8.2f}R")
    print(sep)

    # Comparacao com baseline (defaults)
    print(f"\n  BASELINE (defaults: score={sg.SCORE_THRESHOLD}, atr_mult={sg.ATR_STOP_MULT}, rr={sg.RR_DEFAULT}):")
    base_train = run_strategy(train, sg.SCORE_THRESHOLD, sg.ATR_STOP_MULT, sg.RR_DEFAULT)
    base_test_raw = run_strategy(test_with_warmup, sg.SCORE_THRESHOLD, sg.ATR_STOP_MULT, sg.RR_DEFAULT)
    base_test = [t for t in base_test_raw if t["ts"][:10] >= TEST_START]
    for label, ts in [("TRAIN", base_train), ("TEST", base_test)]:
        if not ts:
            continue
        rs = [t["result_r"] for t in ts]
        m = calc_metrics(rs)
        print(f"  {label:<10} {m.total_trades:>8} {m.win_rate:>7.1f}% "
              f"{m.expectancy_r:>+9.3f}R {m.profit_factor:>8.2f}")

    # Verdict
    test_rs = [t["result_r"] for t in test_trades]
    if test_rs:
        m_test = calc_metrics(test_rs)
        verdict = "EDGE SOBREVIVE OOS" if m_test.expectancy_r > 0.3 else \
                  "EDGE FRACA OOS" if m_test.expectancy_r > 0 else "OVERFITTING"
        print(f"\n  VERDICT: {verdict}  (test expectancy = {m_test.expectancy_r:+.3f}R)")


def main():
    parser = argparse.ArgumentParser(description="Estudo profundo do backtest 2w/14y")
    parser.add_argument("--n_trials", type=int, default=60)
    parser.add_argument("--top_n", type=int, default=3)
    parser.add_argument("--skip_event", action="store_true")
    parser.add_argument("--skip_holdout", action="store_true")
    args = parser.parse_args()

    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)

    print(f"Carregando {MARKET} {PERIOD_1D} do Supabase ({START} -> {END})...")
    daily = db.get_candles(MARKET, PERIOD_1D, START, END)
    twoweek = resample_to_2w(daily, RESAMPLE_DAYS)
    print(f"  {len(daily)} candles 1d -> {len(twoweek)} candles 2w")

    if not args.skip_event:
        study_event_trades(twoweek, top_n=args.top_n)

    if not args.skip_holdout:
        study_holdout_optuna(twoweek, n_trials=args.n_trials)


if __name__ == "__main__":
    main()