# backtest_postpump_short_v2.py — SHORT pos-pump com ENTRADA POR CONFIRMACAO (1h)
# v1 (diario) REPROVADO: short no open D+1 era estopado por wick em 55% dos casos
# (momentum <4h da Lei 1). v2: deixa o momentum esticar e entra na REVERSAO:
#   - evento: dia D com ret >= 30% (par pumped, dataset 1h ~41 dias)
#   - no D+1: rastreia o high intradiario hora a hora
#   - ENTRADA: primeira hora cujo close < high_so_far * (1 - conf%)  [reversao confirmada]
#   - STOP: high_so_far * (1 + buf%)   TP: nenhum; sai no close do D+1 (ou stop)
#   - custos 0.7% RT

from pathlib import Path
import numpy as np
import pandas as pd

DATA = Path(__file__).parent / "data"
RT_COST = 0.7


def main():
    h = pd.read_csv(DATA / "universe_1h.csv")
    h["dt"] = pd.to_datetime(h["ts"], unit="ms")
    for c in ("open", "high", "low", "close", "vol_usd"):
        h[c] = pd.to_numeric(h[c], errors="coerce")
    h = h.dropna(subset=["open", "high", "low", "close"])
    h = h[h["open"] > 0].sort_values(["market", "ts"]).reset_index(drop=True)
    h["date"] = h["dt"].dt.date

    # dias e retornos diarios reconstruidos do 1h
    day = h.groupby(["market", "date"]).agg(
        o=("open", "first"), c=("close", "last"), hi=("high", "max"), vol=("vol_usd", "sum")).reset_index()
    day["ret"] = (day["c"] - day["o"]) / day["o"] * 100
    day = day.sort_values(["market", "date"])
    day["next_date"] = day.groupby("market")["date"].shift(-1)

    events = day[(day["ret"] >= 30) & (day["vol"] >= 10000)].dropna(subset=["next_date"])
    print(f"eventos pump>=30% no dataset 1h: {len(events)} ({events['market'].nunique()} pares, {day['date'].nunique()} dias)\n")

    hourly = {k: v.reset_index(drop=True) for k, v in h.groupby(["market", "date"])}

    def run(conf, buf, min_hours_left=3):
        trades = []
        for _, ev in events.iterrows():
            key = (ev["market"], ev["next_date"])
            hd = hourly.get(key)
            if hd is None or len(hd) < 6:
                continue
            high_so_far = -np.inf
            entered = False
            for i, row in hd.iterrows():
                high_so_far = max(high_so_far, row["high"])
                trigger = high_so_far * (1 - conf / 100)
                if not entered and row["close"] <= trigger and i >= 1 and i <= len(hd) - min_hours_left:
                    entry = row["close"]
                    stop = high_so_far * (1 + buf / 100)
                    entered = True
                    # simula resto do dia
                    rest = hd.iloc[i + 1:]
                    stopped = (rest["high"] >= stop).any()
                    if stopped:
                        exit_px = stop
                    else:
                        exit_px = hd.iloc[-1]["close"]
                    pnl = (entry - exit_px) / entry * 100 - RT_COST
                    trades.append({"pnl": pnl, "stopped": stopped, "market": ev["market"], "date": ev["next_date"]})
                    break
        if not trades:
            return None
        t = pd.DataFrame(trades)
        return {
            "n": len(t), "fill": len(t) / len(events) * 100,
            "win": (t["pnl"] > 0).mean() * 100, "med": t["pnl"].median(),
            "avg": t["pnl"].mean(), "stop": t["stopped"].mean() * 100,
            "p5": t["pnl"].quantile(0.05), "total": t["pnl"].sum(),
        }

    print(f"{'config (conf/buf)':>22} | {'n':>4} | {'fill%':>5} | {'win%':>5} | {'med':>6} | {'avg':>6} | {'stop%':>5} | {'pior5%':>7}")
    for conf, buf in [(3, 3), (5, 3), (5, 5), (7, 5), (10, 5), (10, 8), (15, 8)]:
        r = run(conf, buf)
        if not r:
            continue
        print(f"{f'queda {conf}% do high / stop +{buf}%':>22} | {r['n']:>4} | {r['fill']:>4.0f}% | {r['win']:>4.0f}% | {r['med']:>+5.1f} | {r['avg']:>+5.1f} | {r['stop']:>4.0f}% | {r['p5']:>+6.1f}")

    print("\nnota: dataset 1h cobre ~41 dias / 1 regime — validacao preliminar.")
    print("se aprovar, recoletar 1h continuamente para walk-forward multi-regime.")


if __name__ == "__main__":
    main()
