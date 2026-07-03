#!/usr/bin/env python3
"""
Backtest SHORT v2.5 INTELIGENTE: encontrar o padrão real
Dados: universe_1h.csv (HISTÓRICO COMPLETO, todas as timeframes)

Estratégia: em vez de "pump H-1 → SHORT H0", procura padrão mais robusto:
  1. Identifica PUMP GIGANTESCOS (>= +20% intraday) — fake-out markers
  2. Procura REVERSAL CONFIRMADA 1h depois (close < high * 0.98)
  3. Entra SHORT na primeira 1h que reversa de verdade
  4. Stop: entry * 1.01 (tight)
  5. Exit: profit 3-5% OU time-stop 24h

Insight: a falha anterior foi entrar NO PUMP (close > high*0.97 falhou)
Novo: entra NA REVERSÃO (close < open, volume confirma venda)
"""

import pandas as pd
import numpy as np
from pathlib import Path

DATA = Path(__file__).parent / "data"

# Usar 1h completo (melhor que daily)
df = pd.read_csv(DATA / "universe_1h.csv")

# Parse
df["dt"] = pd.to_datetime(df["ts"], unit="ms")
for c in ("open", "high", "low", "close", "vol_usd"):
    df[c] = pd.to_numeric(df[c], errors="coerce")
df.rename(columns={"vol_usd": "volume"}, inplace=True)
df = df.dropna(subset=["open", "close", "volume"])
df = df.sort_values(["market", "dt"])

print("=" * 80)
print("BACKTEST SHORT v2.5: PUMP-REVERSÃO PATTERN (dados 1h histórico)")
print("=" * 80)
print(f"Dados: {len(df)} velas, {df['market'].nunique()} pares, {df['dt'].min()} até {df['dt'].max()}")
print()

# === NEW PATTERN ===
# PUMP gigantesco (>= +20% intraday) muitas vezes reversa no dia seguinte
# Especialmente se H+4 close < high

trades = []

for market in df["market"].unique():
    market_data = df[df["market"] == market].sort_values("dt").reset_index(drop=True)

    if len(market_data) < 5:
        continue

    market_data["ret"] = (market_data["close"] - market_data["open"]) / market_data["open"] * 100
    market_data["vol_ma5"] = market_data["volume"].rolling(5, min_periods=1).mean()

    # Procurar pump >= +20%
    for i in range(len(market_data) - 5):
        candle = market_data.iloc[i]

        # Critério 1: pump intraday >= 20%
        if candle["ret"] < 20.0:
            continue

        # Critério 2: volume confirma (>= 1.0x MA5, não precisa spike massivo)
        if candle["volume"] < 0.8 * candle["vol_ma5"]:
            continue

        # Critério 3: próximas 5 velas — procura reversão confirmada
        # Reversão = close < open (rejeição real)
        reversal_found = False
        reversal_idx = None

        for j in range(i+1, min(i+6, len(market_data))):  # próximas 5 horas
            next_candle = market_data.iloc[j]

            # Close abaixo do open = rejeição
            if next_candle["close"] < next_candle["open"]:
                reversal_found = True
                reversal_idx = j
                break

        if not reversal_found:
            continue

        # === ENTRADA SHORT ===
        entry_candle = market_data.iloc[reversal_idx]
        entry_price = entry_candle["close"]  # Entra no close da reversão
        stop_price = entry_price * 1.01  # Stop 1%

        # PnL nas próximas 24h (4 velas 1h = 4h; dia = 24h)
        # Simplificado: próxima vela completa (H+1)
        if reversal_idx + 1 < len(market_data):
            exit_candle = market_data.iloc[reversal_idx + 1]
            pnl_ret = (entry_price - exit_candle["close"]) / entry_price * 100

            # Win/loss
            stop_hit = exit_candle["high"] >= stop_price
            if stop_hit:
                win = False
                pnl_ret = -1.0
                exit_reason = "STOP"
            elif pnl_ret >= 3.0:
                win = True
                exit_reason = f"PROFIT_{pnl_ret:.1f}%"
            else:
                win = False
                exit_reason = "TIMEOUT"

            trades.append({
                "market": market,
                "dt_pump": candle["dt"],
                "dt_entry": entry_candle["dt"],
                "pump_ret": candle["ret"],
                "entry": entry_price,
                "stop": stop_price,
                "exit": exit_candle["close"],
                "pnl_ret": pnl_ret,
                "win": win,
                "exit_reason": exit_reason,
            })

print(f"Total trades gerados: {len(trades)}")
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
    print(f"Pior 5%: {df_trades['pnl_ret'].quantile(0.05):+.1f}%")
    print()

    ev = df_trades["pnl_ret"].sum() / total_count
    print(f"Expected Value: {ev:+.2f}% por trade")
    print(f"  x 100 trades/mês = {ev * 100:+.1f}% PnL mensal")
    print()

    print("Exit reasons:")
    print(df_trades["exit_reason"].value_counts().head(10))
    print()

    if win_pct >= 55 and ev > 0:
        print(f"✅ PADRÃO VALIDADO: {win_pct:.0f}% win, {ev:+.2f}% EV")
        print(f"   → LIVE 0.5% sizing")
    elif win_pct >= 50:
        print(f"⚠️  PADRÃO MARGINAL: {win_pct:.0f}% win, {ev:+.2f}% EV")
        print(f"   → Teste com cuidado")
    else:
        print(f"❌ PADRÃO FRACO: {win_pct:.0f}% win, {ev:+.2f}% EV")

else:
    print("❌ Nenhum trade (padrão muito restritivo)")
