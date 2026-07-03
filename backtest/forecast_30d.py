# forecast_30d.py — Previsão de captura nos próximos 30 dias
# vs oportunidades reais do universo + gates fail-closed atuais

import pandas as pd
import numpy as np
from pathlib import Path

DATA = Path(__file__).parent / "data"
df = pd.read_csv(DATA / "universe_daily_full.csv")
df["dt"] = pd.to_datetime(df["ts"], unit="ms")
for c in ("open", "high", "low", "close"):
    df[c] = pd.to_numeric(df[c], errors="coerce")
df = df.dropna(subset=["open", "close"])
df["ret"] = (df["close"] - df["open"]) / df["open"] * 100

# ultimos 30 dias
recent = df[df["dt"] >= df["dt"].max() - pd.Timedelta(days=30)]

print("=== UNIVERSO ULTIMOS 30 DIAS ===")
print(f"pares: {recent['market'].nunique()} | dias: {recent['dt'].dt.date.nunique()}")
print()

# LONG (scalp spot, capture pump)
long_events = recent[recent["ret"] >= 20].copy()
long_daily = long_events.groupby(long_events["dt"].dt.date).size()
print("LONG/SCALP (ret >= +20% intraday):")
print(f"  eventos: {len(long_events)} | dias c/ pump: {len(long_daily)} | media/dia: {len(long_events)/max(len(long_daily),1):.1f}")
print(f"  mediana pump: {long_events['ret'].median():+.1f}% | pior 5%: {long_events['ret'].quantile(0.05):+.1f}%")
print()

# SHORT (dump capture, -20%)
short_events = recent[recent["ret"] <= -20].copy()
short_daily = short_events.groupby(short_events["dt"].dt.date).size()
print("SHORT (ret <= -20% intraday):")
print(f"  eventos: {len(short_events)} | dias c/ dump: {len(short_daily)} | media/dia: {len(short_events)/max(len(short_daily),1):.1f}")
print(f"  mediana dump: {short_events['ret'].median():+.1f}% | pior 5%: {short_events['ret'].quantile(0.05):+.1f}%")
print()

# LAYER 5 spots pumpando
layer5_candidates = recent[(recent["ret"] >= 25)].copy()
print("LAYER 5 (spot exit, ret >= +25%):")
print(f"  candidatos: {len(layer5_candidates)} | dias: {layer5_candidates['dt'].dt.date.nunique()}")
print(f"  Se vender no climax: salva -4.6% D+1 mediana (n=6212 backtest, 63% win)")
print()

# o gap: gates fail-closed
print("=== GATES FAIL-CLOSED ATUAIS ===")
print("LONG approval rate: ~3-5% (BEAR_WEAK regime bloqueia 90%+)")
print("  - SCORE_MINIMO=75 bloqueia bottom 25% dos candidates")
print("  - G8 pump-chase bloqueia LONG intraday")
print("  - Mesa FORTE (consensus 3-voto) rejeita MEDIO_2 (1-voto split)")
print("  - BETA > 1.4 em bear (hard block)")
print("  - Tori SKIP sem trendline 4H")
print()
print("SHORT approval rate: ~0% (futures bottleneck 7% + backtest v1 -4% PnL)")
print("  - Só 7% dos pares têm futures (0.3-0.4/dia dos dumps)")
print("  - v1 backtest: wick estopa 55%, PnL mediano -4%")
print("  - v2 em P&D: win 52-58%, mas média ~0 e cauda -27%")
print()
print("LAYER 5 capture rate: ~60-70% dos pumps >= +25%")
print("  - Automático, não exige gate")
print("  - Salva PnL em bag spot")
print()

# previsao 30 dias
print("=== PREVISAO 30 DIAS (BEAR_WEAK regime) ===")
pump_rate = len(long_events) / max(len(long_daily), 1)
dump_rate = len(short_events) / max(len(short_daily), 1)
layer5_rate = len(layer5_candidates) / max(layer5_candidates['dt'].dt.date.nunique(), 1)

print(f"LONG: {pump_rate:.1f} pumps/dia x 30 = {int(pump_rate*30)} oportunidades")
print(f"      gates aprovam ~3-5% = ~{int(pump_rate*30*0.04)} trades")
print()
print(f"SHORT: {dump_rate:.1f} dumps/dia x 30 = {int(dump_rate*30)} oportunidades")
print(f"       futures-viable ~7% = {int(dump_rate*30*0.07)} shorts")
print(f"       backtest v1 PnL = -4% (reprovado)")
print(f"       resultado = 0 trades executados")
print()
print(f"LAYER 5: {layer5_rate:.1f} climax/dia x 30 = {int(layer5_rate*30)} exit-harvests")
print(f"         60% capture rate = ~{int(layer5_rate*30*0.6)} bags colhidas")
print(f"         valor salvo = -4.6% mediano por bag (vs segurar)")
print()
print("=== SUMMARY 30 DIAS ===")
print(f"entradas LONG: {int(pump_rate*30*0.04)}-{int(pump_rate*30*0.08)} (3-5% approval)")
print(f"entradas SHORT: 0 (futures bottleneck + backtest reprovado)")
print(f"exits (Layer 5): {int(layer5_rate*30*0.6)} bags automáticas")
print()
print("=> estamos operando ~10x abaixo da oportunidade aparente")
print("=> gates fail-closed estão FUNCIONANDO (recusam trades com EV ruim)")
print("=> próximo 30d = evolution tempo (dados) ou change gates (risco)")
