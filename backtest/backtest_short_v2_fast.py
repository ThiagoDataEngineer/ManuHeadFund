#!/usr/bin/env python3
"""
Backtest OTIMIZADO: SHORT v2.5 apenas em DUMPS REAIS
Strategy: detectar dump iminente E shortar na reversão confirmada

Dataset: daily (mais rápido)
Foco: últimas 3 meses de dados (regime bear_weak atual)
"""

import pandas as pd
import numpy as np
from pathlib import Path

DATA = Path(__file__).parent / "data"
df = pd.read_csv(DATA / "universe_daily_full.csv")

df["dt"] = pd.to_datetime(df["ts"], unit="ms")
for c in ("open", "high", "low", "close", "vol_usd"):
    df[c] = pd.to_numeric(df[c], errors="coerce")
df.rename(columns={"vol_usd": "volume"}, inplace=True)
df = df.dropna(subset=["open", "close"])
df = df.sort_values(["market", "dt"])

# Últimas 90 dias (3 meses)
min_dt = df["dt"].max() - pd.Timedelta(days=90)
recent = df[df["dt"] >= min_dt].copy()

print("=" * 80)
print("BACKTEST SHORT v2.5: Otimizado para dumps reais")
print(f"Período: {recent['dt'].min().date()} até {recent['dt'].max().date()}")
print(f"Total velas: {len(recent)}, pares: {recent['market'].nunique()}")
print()

trades = []

for market in recent["market"].unique():
    mkt = recent[recent["market"] == market].sort_values("dt").reset_index(drop=True)

    if len(mkt) < 3:
        continue

    mkt["ret"] = (mkt["close"] - mkt["open"]) / mkt["open"] * 100
    mkt["ret_next"] = mkt["ret"].shift(-1)

    for i in range(len(mkt) - 2):
        curr = mkt.iloc[i]
        next_day = mkt.iloc[i+1]
        day_after = mkt.iloc[i+2]

        # === PADRÃO: pump hoje → dump amanhã ===
        # Pump >= +15% (forte)
        if curr["ret"] < 15.0:
            continue

        # Dump amanhã >= -15%
        if next_day["ret"] > -15.0:
            continue

        # === ENTRADA SHORT no dump (próximo dia open) ===
        # Entra no open do dump (mais realista)
        entry_price = next_day["open"]
        stop_price = entry_price * 1.01  # Stop 1%

        # PnL: até close do dia do dump OU próximo dia
        pnl_close_same_day = (entry_price - next_day["close"]) / entry_price * 100

        # Checagem: stop foi hit?
        stop_hit = next_day["high"] >= stop_price

        if stop_hit:
            win = False
            pnl_ret = -1.0
            exit_reason = "STOP"
        elif pnl_close_same_day >= 3.0:
            win = True
            pnl_ret = pnl_close_same_day
            exit_reason = f"PROFIT_{pnl_ret:.1f}%"
        else:
            win = False
            pnl_ret = pnl_close_same_day
            exit_reason = "TIMEOUT"

        trades.append({
            "market": market,
            "dt": next_day["dt"],
            "pump_prev": curr["ret"],
            "dump_ret": next_day["ret"],
            "entry": entry_price,
            "stop": stop_price,
            "exit": next_day["close"],
            "pnl_ret": pnl_ret,
            "win": win,
            "exit_reason": exit_reason,
        })

print(f"Total trades SHORT-pump-fade: {len(trades)}")
print()

if len(trades) > 0:
    df_trades = pd.DataFrame(trades)

    win_count = df_trades["win"].sum()
    total_count = len(df_trades)
    win_pct = win_count / total_count * 100

    print("=" * 80)
    print("RESULTADO")
    print("=" * 80)
    print(f"Wins: {win_count}/{total_count} ({win_pct:.1f}%)")
    print()
    print(f"PnL mediano: {df_trades['pnl_ret'].median():+.1f}%")
    print(f"PnL média: {df_trades['pnl_ret'].mean():+.1f}%")
    print(f"PnL Q25: {df_trades['pnl_ret'].quantile(0.25):+.1f}%")
    print(f"PnL Q75: {df_trades['pnl_ret'].quantile(0.75):+.1f}%")
    print()

    print("Exit distribution:")
    print(df_trades["exit_reason"].value_counts())
    print()

    ev = df_trades["pnl_ret"].sum() / total_count
    print(f"Expected Value: {ev:+.2f}% por trade")

    # Estimativa mensal (assumindo 10 SHORTs/mês disponíveis)
    print(f"  x 10 trades/mês (estimated) = {ev * 10:+.1f}% PnL mensal")
    print()

    if win_pct >= 55:
        print(f"✅ PADRÃO FORTE: {win_pct:.0f}% win")
    elif win_pct >= 50:
        print(f"⚠️  PADRÃO OK: {win_pct:.0f}% win")
    else:
        print(f"❌ PADRÃO FRACO: {win_pct:.0f}% win")

else:
    print("❌ Nenhum trade")
