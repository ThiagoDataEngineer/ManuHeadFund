#!/usr/bin/env python3
"""
Backtest SHORT v2.5: PUMP-FADE pattern
Pergunta: qual é o win rate de entrar SHORT após pump massive H-1?

Pattern:
  H-1: ret >= +5% E volume >= 0.8x MA5 → WATCH
  H0:  close < high*0.97 → ENTRADA SHORT
  STOP: entry * 1.01 (1% tight)
  EXIT: profit 3-5% OU time-stop 24h OU stop

Dados: últimos 30 dias, todos os pares
"""

import pandas as pd
import numpy as np
from pathlib import Path

DATA = Path(__file__).parent / "data"
df = pd.read_csv(DATA / "universe_daily_full.csv")

# Parse
df["dt"] = pd.to_datetime(df["ts"], unit="ms")
for c in ("open", "high", "low", "close", "vol_usd"):
    df[c] = pd.to_numeric(df[c], errors="coerce")
df.rename(columns={"vol_usd": "volume"}, inplace=True)
df = df.dropna(subset=["open", "close"])
df = df.sort_values(["market", "dt"])

# Ultimos 30 dias
recent = df[df["dt"] >= df["dt"].max() - pd.Timedelta(days=30)].copy()

print("=" * 80)
print("BACKTEST SHORT v2.5: PUMP-FADE Pattern")
print("=" * 80)
print()

# === PHASE 1: Identify WATCH signals (H-1 pump) ===
print("PHASE 1: Identificar WATCH signals (pump H-1)")
print()

trades = []

for market in recent["market"].unique():
    market_data = recent[recent["market"] == market].sort_values("dt").reset_index(drop=True)

    if len(market_data) < 2:
        continue

    # Calcular volume MA5
    market_data["vol_ma5"] = market_data["volume"].rolling(5, min_periods=1).mean()
    market_data["ret"] = (market_data["close"] - market_data["open"]) / market_data["open"] * 100
    market_data["ret_d1"] = market_data["ret"].shift(-1)  # return próximo dia

    # Procurar pump H-1 (índice i-1)
    for i in range(1, len(market_data)):
        h_minus_1 = market_data.iloc[i-1]
        h_0 = market_data.iloc[i]

        # Regra WATCH: pump >= 5% + volume >= 0.8x MA5
        if h_minus_1["ret"] >= 5.0 and h_minus_1["volume"] >= 0.8 * h_minus_1["vol_ma5"]:
            # === PHASE 2: Check confirmação H0 ===
            # Entrada SHORT só se H0 close < high*0.97 (rejeição claro)
            if h_0["close"] < h_0["high"] * 0.97:
                entry_price = h_0["close"]  # Entrada no close H0
                stop_price = entry_price * 1.01  # 1% stop

                # Calcular PnL 24h depois (próximo dia full)
                if i + 1 < len(market_data):
                    h_plus_1 = market_data.iloc[i+1]

                    # PnL: (entry - close) / entry * 100
                    pnl_ret = (entry_price - h_plus_1["close"]) / entry_price * 100

                    # Checar se stop foi atingido (high > stop)
                    stop_hit = h_plus_1["high"] >= stop_price

                    # Profit target: -3% a -5%
                    profit_hit = pnl_ret >= 3.0 and pnl_ret <= 5.0

                    # Win/loss
                    if stop_hit:
                        win = False
                        pnl_ret = -1.0  # stop loss
                        exit_reason = "STOP"
                    elif profit_hit:
                        win = True
                        exit_reason = f"PROFIT_{pnl_ret:.1f}%"
                    elif pnl_ret >= 3.0:  # any profit >= 3%
                        win = True
                        exit_reason = f"PROFIT_{pnl_ret:.1f}%"
                    else:
                        win = False
                        exit_reason = "TIMEOUT"

                    trades.append({
                        "market": market,
                        "dt": h_0["dt"],
                        "pump_h_minus_1": h_minus_1["ret"],
                        "vol_ratio": h_minus_1["volume"] / h_minus_1["vol_ma5"],
                        "entry": entry_price,
                        "stop": stop_price,
                        "h0_close": h_0["close"],
                        "h0_high": h_0["high"],
                        "exit_price": h_plus_1["close"],
                        "pnl_ret": pnl_ret,
                        "win": win,
                        "exit_reason": exit_reason,
                    })

print(f"Total WATCH signals (pump >= 5% + vol spike): {len(trades)}")
print()

if len(trades) > 0:
    df_trades = pd.DataFrame(trades)

    # === ANÁLISE ===
    print("=" * 80)
    print("RESULTADO BACKTEST")
    print("=" * 80)
    print()

    win_count = df_trades["win"].sum()
    total_count = len(df_trades)
    win_pct = win_count / total_count * 100

    print(f"Total trades: {total_count}")
    print(f"Wins: {win_count} ({win_pct:.1f}%)")
    print(f"Losses: {total_count - win_count} ({100-win_pct:.1f}%)")
    print()

    print(f"PnL mediano: {df_trades['pnl_ret'].median():+.1f}%")
    print(f"PnL média: {df_trades['pnl_ret'].mean():+.1f}%")
    print(f"PnL Q25: {df_trades['pnl_ret'].quantile(0.25):+.1f}%")
    print(f"PnL Q75: {df_trades['pnl_ret'].quantile(0.75):+.1f}%")
    print(f"Pior 5%: {df_trades['pnl_ret'].quantile(0.05):+.1f}%")
    print()

    print("Exit reasons:")
    print(df_trades["exit_reason"].value_counts())
    print()

    # Filtrar profits e losses
    profits = df_trades[df_trades["pnl_ret"] > 0]
    losses = df_trades[df_trades["pnl_ret"] < 0]

    if len(profits) > 0:
        print(f"Trades com lucro (PnL > 0): {len(profits)}")
        print(f"  Mediana PnL: {profits['pnl_ret'].median():+.1f}%")
        print(f"  Média PnL: {profits['pnl_ret'].mean():+.1f}%")
    print()

    if len(losses) > 0:
        print(f"Trades com perda (PnL < 0): {len(losses)}")
        print(f"  Mediana PnL: {losses['pnl_ret'].median():+.1f}%")
        print(f"  Média PnL: {losses['pnl_ret'].mean():+.1f}%")
    print()

    # Esperança matemática (sem custos ainda)
    ev = df_trades["pnl_ret"].sum() / total_count
    print(f"Expected Value (sem fees): {ev:+.2f}% por trade")
    print(f"  x 150 trades/mês = {ev * 150:+.1f}% PnL mensal")
    print()

    # === BREAKDOWN por PUMP size ===
    print("Breakdown por tamanho do pump H-1:")
    df_trades["pump_bucket"] = pd.cut(df_trades["pump_h_minus_1"],
                                       bins=[0, 10, 20, 50, 500],
                                       labels=["5-10%", "10-20%", "20-50%", "50%+"])

    for bucket in ["5-10%", "10-20%", "20-50%", "50%+"]:
        bucket_trades = df_trades[df_trades["pump_bucket"] == bucket]
        if len(bucket_trades) > 0:
            win_pct_b = bucket_trades["win"].sum() / len(bucket_trades) * 100
            pnl_b = bucket_trades["pnl_ret"].mean()
            print(f"  {bucket}: n={len(bucket_trades)}, win={win_pct_b:.0f}%, pnl={pnl_b:+.1f}%")

    print()
    print("=" * 80)
    print("CONCLUSÃO")
    print("=" * 80)
    print()

    if win_pct >= 55 and ev > 0:
        print(f"✅ PADRÃO VALIDADO: {win_pct:.0f}% win, {ev:+.2f}% EV")
        print(f"   → Pronto pra LIVE com 0.5% sizing")
        print(f"   → Esperado: {ev * 150:+.1f}% PnL/mês (se 150 trades)")
    elif win_pct >= 50:
        print(f"⚠️  PADRÃO MARGINAL: {win_pct:.0f}% win, {ev:+.2f}% EV")
        print(f"   → Pode testar LIVE com cuidado (0.25% sizing)")
        print(f"   → Refinar rules (pump trigger, stop width)")
    else:
        print(f"❌ PADRÃO FALHOU: {win_pct:.0f}% win, {ev:+.2f}% EV")
        print(f"   → Não recomendado LIVE")
        print(f"   → Precisa de ajuste (entrada timing, profit target)")

else:
    print("❌ Nenhum trade gerado (padrão muito restritivo)")
    print("   → Ajustar trigger (pump >= 3%? volume ratio?)")
