"""
backtest_2w_14y.py — Backtest macro: BTCUSD 1d→2w resample, 14 anos (2011-2026).

Self-contained: lê 1d do Supabase, agrega para 2w em memória,
gera sinais via TechAgent (signal_generator) e simula trades.
Não escreve no DB.

Uso:
    python backtest_2w_14y.py
"""
import os
from collections import defaultdict
from datetime import datetime, timezone
from typing import Dict, List

from dotenv import load_dotenv
load_dotenv()

from db import Database
from signal_generator import generate_signal
from trade_simulator import simulate_trade
from metrics import calc_metrics, calc_metrics_by_regime, classify_regime
from report import generate_html_report

MARKET = "BTCUSD"
PERIOD_1D = "1day"
START = "2011-01-01"
END = "2026-12-31"
RESAMPLE_DAYS = 14
MAX_BARS_FORWARD = 10   # 10 bars × 2w = ~5 meses de janela
REGIME_LOOKBACK = 50    # 50 × 2w = ~2 anos para SMA "200"-ish
FEE_PCT = 0.10

# Ciclos macro BTC para breakdown
CYCLES = [
    ("Pre-halving 1",  "2011-08-01", "2012-11-28"),
    ("Bull 2013",      "2012-11-28", "2013-12-31"),
    ("Bear 2014",      "2014-01-01", "2015-08-31"),
    ("Bull 2016-17",   "2015-09-01", "2017-12-17"),
    ("Bear 2018",      "2017-12-18", "2018-12-31"),
    ("Bull 2019-21",   "2019-01-01", "2021-11-10"),
    ("Bear 2022",      "2021-11-11", "2022-12-31"),
    ("Bull 2023-24",   "2023-01-01", "2024-12-31"),
    ("2025+",          "2025-01-01", "2030-01-01"),
]


def resample_to_2w(daily: List[Dict], days: int = RESAMPLE_DAYS) -> List[Dict]:
    """Agrega candles 1d em buckets de N dias (OHLC + sum volume).

    Bucketing: agrupa por floor(ts_unix / (days*86400)).
    """
    if not daily:
        return []
    bucket_sec = days * 86400
    buckets: Dict[int, List[Dict]] = defaultdict(list)
    for c in daily:
        ts = datetime.fromisoformat(c["ts"].replace("Z", "+00:00"))
        ts_unix = int(ts.timestamp())
        key = ts_unix // bucket_sec
        buckets[key].append((ts_unix, c))

    out: List[Dict] = []
    for key in sorted(buckets.keys()):
        group = sorted(buckets[key], key=lambda x: x[0])
        rows = [r for _, r in group]
        agg_ts = datetime.fromtimestamp(group[0][0], tz=timezone.utc).isoformat()
        out.append({
            "market": rows[0]["market"],
            "period": f"{days}d",
            "ts":     agg_ts,
            "open":   float(rows[0]["open"]),
            "high":   max(float(r["high"]) for r in rows),
            "low":    min(float(r["low"]) for r in rows),
            "close":  float(rows[-1]["close"]),
            "volume": sum(float(r["volume"]) for r in rows),
        })
    return out


def classify_by_sma(candles: List[Dict], lookback: int = REGIME_LOOKBACK) -> str:
    if len(candles) < lookback:
        return "sideways"
    closes = [c["close"] for c in candles[-lookback:]]
    sma = sum(closes) / lookback
    return classify_regime(candles[-1]["close"], sma)


def in_cycle(ts_iso: str, start: str, end: str) -> bool:
    return start <= ts_iso[:10] <= end


def main():
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)

    print(f"Lendo {MARKET} {PERIOD_1D} do Supabase ({START} -> {END})...")
    daily = db.get_candles(MARKET, PERIOD_1D, START, END)
    print(f"  {len(daily)} candles 1d carregados")

    twoweek = resample_to_2w(daily, RESAMPLE_DAYS)
    print(f"  {len(twoweek)} candles {RESAMPLE_DAYS}d apos resample")
    if twoweek:
        print(f"  range: {twoweek[0]['ts'][:10]} -> {twoweek[-1]['ts'][:10]}")

    # Gera sinais bar-a-bar (zero lookahead)
    MIN_BARS = 35
    signals = []
    for i in range(MIN_BARS, len(twoweek)):
        window = twoweek[: i + 1]
        result = generate_signal(window)
        if not result.is_actionable:
            continue
        # forward window para simulacao
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
        signals.append({
            "ts": twoweek[i]["ts"],
            "direction": direction,
            "result_r": sim.result_r,
            "exit_reason": sim.exit_reason,
            "regime": regime,
            "score": result.score,
        })

    if not signals:
        print("Nenhum sinal acionavel gerado.")
        return

    r_series = [s["result_r"] for s in signals]
    regimes  = [s["regime"]   for s in signals]
    m  = calc_metrics(r_series)
    br = calc_metrics_by_regime(r_series, regimes)

    # ── Print overall ─────────────────────────────────────────────────────────
    sep = "-" * 60
    print(f"\n{sep}")
    print(f"  BACKTEST MACRO — {MARKET} 2w (14 anos)")
    print(sep)
    print(f"  Periodo:       {twoweek[0]['ts'][:10]} -> {twoweek[-1]['ts'][:10]}")
    print(f"  Candles 2w:    {len(twoweek)}")
    print(f"  Trades:        {m.total_trades}  ({m.winning_trades} wins, {m.win_rate:.1f}%)")
    print(f"  Expectancy:    {m.expectancy_r:+.3f}R")
    print(f"  Profit Factor: {m.profit_factor:.2f}")
    print(f"  Max Drawdown:  {m.max_drawdown_r:.2f}R")
    print(f"  Sharpe:        {m.sharpe_ratio:.3f}")
    print(sep)
    print("  POR REGIME (SMA50 sobre 2w ~= 2 anos de tendencia macro)")
    for name, rm in [("BULL", br.bull), ("BEAR", br.bear), ("SIDEWAYS", br.sideways)]:
        if rm is None:
            continue
        flag = "[OK]" if rm.expectancy_r > 0.3 else "[--]"
        print(f"  {name:8s}  n={rm.total_trades:3d}  win={rm.win_rate:5.1f}%  exp={rm.expectancy_r:+.3f}R  {flag}")
    print(sep)
    print("  POR CICLO MACRO")
    cycle_rows = []
    for name, cs, ce in CYCLES:
        sub = [s for s in signals if in_cycle(s["ts"], cs, ce)]
        if not sub:
            continue
        rs = [s["result_r"] for s in sub]
        cm = calc_metrics(rs)
        flag = "[OK]" if cm.expectancy_r > 0.3 else "[--]"
        print(f"  {name:18s}  n={cm.total_trades:3d}  win={cm.win_rate:5.1f}%  "
              f"exp={cm.expectancy_r:+.3f}R  pf={cm.profit_factor:5.2f}  {flag}")
        cycle_rows.append((name, cm))
    print(sep)

    # ── HTML report ──────────────────────────────────────────────────────────
    run_row = {
        "market":          MARKET,
        "period":          f"{RESAMPLE_DAYS}d (resample 1d->2w)",
        "date_from":       twoweek[0]["ts"][:10],
        "date_to":         twoweek[-1]["ts"][:10],
        "capital_initial": 1000.0,
        "total_trades":    m.total_trades,
        "winning_trades":  m.winning_trades,
        "win_rate":        round(m.win_rate, 2),
        "expectancy_r":    round(m.expectancy_r, 4),
        "profit_factor":   round(m.profit_factor, 4),
        "max_drawdown":    round(m.max_drawdown_r, 4),
        "sharpe_ratio":    round(m.sharpe_ratio, 4),
    }
    html = generate_html_report(run_row, br, output_path=None)

    cycle_html = ['<div class="section"><h2>Por Ciclo Macro</h2>',
                  '<table><tr><th>Ciclo</th><th class="num">Trades</th>'
                  '<th class="num">Win Rate</th><th class="num">Expectancy</th>'
                  '<th class="num">Profit Factor</th><th class="num">Edge</th></tr>']
    for name, cm in cycle_rows:
        exp_cls = "pass" if cm.expectancy_r > 0.3 else ("warn" if cm.expectancy_r > 0 else "fail")
        edge = "OK" if cm.expectancy_r > 0.3 else "--"
        cycle_html.append(
            f'<tr><td>{name}</td><td class="num">{cm.total_trades}</td>'
            f'<td class="num">{cm.win_rate:.1f}%</td>'
            f'<td class="num {exp_cls}">{cm.expectancy_r:+.3f}R</td>'
            f'<td class="num">{cm.profit_factor:.2f}</td>'
            f'<td class="num {exp_cls}">{edge}</td></tr>'
        )
    cycle_html.append('</table></div>')
    cycle_section = "\n".join(cycle_html)

    html = html.replace("</body>", cycle_section + "\n</body>")
    out_path = "backtest_report_BTCUSD_2w_14y.html"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"  HTML salvo: {out_path}")


if __name__ == "__main__":
    main()