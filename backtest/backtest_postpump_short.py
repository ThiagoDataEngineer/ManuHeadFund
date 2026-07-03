# backtest_postpump_short.py — Backtest REALISTA da lei de dissipacao
# Estrategia A (futures): SHORT no open D+1 apos pump >= threshold no par COM futures CoinEx
#   - stop: high do dia do pump + buffer (tese invalida se rompe o topo)
#   - saida: close D+1 (hold 1d) ou D+2/D+3
#   - custos: slippage 0.3% cada lado + taker 0.05% x2 (~0.7% round trip); funding ignorado
#     (em squeeze, funding costuma PAGAR o short — nao contamos a favor: conservador)
# Estrategia B (spot exit rule): bag que pumpou >= threshold — vender no close do pump
#   vs segurar 1/3/7 dias (quanto a regra de saida salva, sem futures)

import json
import urllib.request
from pathlib import Path

import numpy as np
import pandas as pd

DATA = Path(__file__).parent / "data"
SLIP = 0.3   # % por lado
FEE = 0.05   # % taker por lado (futures CoinEx)
RT_COST = 2 * (SLIP + FEE)  # 0.7% round trip


def load():
    df = pd.read_csv(DATA / "universe_daily_full.csv")
    df["dt"] = pd.to_datetime(df["ts"], unit="ms")
    for c in ("open", "high", "low", "close", "vol_usd"):
        df[c] = pd.to_numeric(df[c], errors="coerce")
    df = df.dropna(subset=["open", "high", "low", "close"])
    df = df[df["open"] > 0].sort_values(["market", "ts"]).reset_index(drop=True)
    df["ret"] = (df["close"] - df["open"]) / df["open"] * 100
    g = df.groupby("market")
    for k in (1, 2, 3, 7):
        df[f"open_d{k}"] = g["open"].shift(-k)
        df[f"close_d{k}"] = g["close"].shift(-k)
        df[f"high_d{k}"] = g["high"].shift(-k)
    return df


def futures_markets():
    with urllib.request.urlopen("https://api.coinex.com/v2/futures/market", timeout=15) as r:
        fut = json.loads(r.read().decode())
    return {m["market"] for m in fut.get("data", [])}


def bt_short(df, fut, thr=30, stop_buf=2.0, hold=1, upwick_min=None):
    """Short: entra open D+1, stop = high(D0)*(1+buf%), sai close D+hold."""
    ev = df[(df["ret"] >= thr) & df["market"].isin(fut)].copy()
    ev = ev.dropna(subset=[f"close_d{hold}", "open_d1"])
    ev = ev[ev["vol_usd"] >= 10000]
    if upwick_min is not None:
        upw = (ev["high"] - ev[["open", "close"]].max(axis=1)) / ev["open"] * 100
        ev = ev[upw >= upwick_min]
    if len(ev) == 0:
        return None

    entry = ev["open_d1"]
    stop = ev["high"] * (1 + stop_buf / 100)
    # foi estopado se high de algum dia do hold cruzou o stop (conservador: stop antes do alvo)
    stopped = ev["high_d1"] >= stop
    for k in range(2, hold + 1):
        stopped = stopped | (ev[f"high_d{k}"] >= stop)
    exit_px = np.where(stopped, stop, ev[f"close_d{hold}"])
    pnl = (entry - exit_px) / entry * 100 - RT_COST  # short
    ev = ev.assign(pnl=pnl, stopped=stopped)

    r = {
        "n": len(ev),
        "win": (ev["pnl"] > 0).mean() * 100,
        "med": ev["pnl"].median(),
        "avg": ev["pnl"].mean(),
        "stop_rate": ev["stopped"].mean() * 100,
        "p95_loss": ev["pnl"].quantile(0.05),
        "total_R": ev["pnl"].sum(),
        "by_year": ev.groupby(ev["dt"].dt.year)["pnl"].agg(["median", "mean", "count"]),
        "per_month": len(ev) / max((ev["dt"].max() - ev["dt"].min()).days / 30, 1),
    }
    return r


def main():
    df = load()
    fut = futures_markets()
    print(f"universo: {df['market'].nunique()} pares | futures: {len(fut)} | custos {RT_COST:.1f}% RT + stop\n")

    print("=== A. SHORT pos-pump (futures reais, custos, stop high+buf) ===")
    print(f"{'config':>42} | {'n':>4} | {'win%':>5} | {'med':>6} | {'avg':>6} | {'stop%':>5} | {'pior5%':>7} | {'tr/mes':>6}")
    for thr, buf, hold, upw, label in [
        (30, 2, 1, None, "thr30 buf2 hold1"),
        (30, 5, 1, None, "thr30 buf5 hold1"),
        (30, 2, 2, None, "thr30 buf2 hold2"),
        (30, 2, 3, None, "thr30 buf2 hold3"),
        (20, 2, 1, None, "thr20 buf2 hold1"),
        (50, 2, 1, None, "thr50 buf2 hold1"),
        (20, 2, 1, 5.0, "thr20+upwick5 buf2 hold1"),
        (30, 2, 1, 5.0, "thr30+upwick5 buf2 hold1"),
    ]:
        r = bt_short(df, fut, thr, buf, hold, upw)
        if not r:
            continue
        print(f"{label:>42} | {r['n']:>4} | {r['win']:>4.0f}% | {r['med']:>+5.1f} | {r['avg']:>+5.1f} | {r['stop_rate']:>4.0f}% | {r['p95_loss']:>+6.1f} | {r['per_month']:>6.1f}")

    best = bt_short(df, fut, 30, 2, 1)
    print("\n  Walk-forward por ano (thr30 buf2 hold1):")
    for y, row in best["by_year"].iterrows():
        print(f"    {y}: mediana {row['median']:+.1f}% | media {row['mean']:+.1f}% | n={int(row['count'])}")

    print("\n=== B. REGRA DE SAIDA SPOT: vender no close do pump vs segurar ===")
    ev = df[(df["ret"] >= 25) & (df["vol_usd"] >= 5000)].dropna(subset=["close_d1", "close_d3", "close_d7"])
    sell_now = 0.0  # referencia: vendeu no close do pump
    for k, label in [(1, "segurar +1d"), (3, "segurar +3d"), (7, "segurar +7d")]:
        drift = (ev[f"close_d{k}"] - ev["close"]) / ev["close"] * 100
        print(f"    {label}: mediana {drift.median():+.1f}% vs vender ja | pior 5%: {drift.quantile(0.05):+.1f}% | melhora em {(drift>0).mean()*100:.0f}% dos casos (n={len(ev)})")
    print("    -> custo de NAO vender no climax = o valor da regra de saida")


if __name__ == "__main__":
    main()
