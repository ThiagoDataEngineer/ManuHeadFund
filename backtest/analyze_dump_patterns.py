#!/usr/bin/env python3
"""
Análise de DUMPS gigantescos nos últimos 30 dias.
Pergunta: qual é o padrão 1h ANTES de um dump >= -30%?
"""

import pandas as pd
import numpy as np
from pathlib import Path
from datetime import timedelta

DATA = Path(__file__).parent / "data"
df = pd.read_csv(DATA / "universe_daily_full.csv")

# parse
df["dt"] = pd.to_datetime(df["ts"], unit="ms")
for c in ("open", "high", "low", "close", "vol_usd"):
    df[c] = pd.to_numeric(df[c], errors="coerce")
df.rename(columns={"vol_usd": "volume"}, inplace=True)
df = df.dropna(subset=["open", "close"])
df["ret"] = (df["close"] - df["open"]) / df["open"] * 100
df = df.sort_values(["market", "dt"])

# ultimos 30 dias
recent = df[df["dt"] >= df["dt"].max() - pd.Timedelta(days=30)].copy()

print("=" * 80)
print("PADRÃO DE DUMPS GIGANTESCOS (>= -30%)")
print("=" * 80)
print()

# Filtrar DUMPS gigantescos
dumps_huge = recent[recent["ret"] <= -30].copy()
dumps_huge = dumps_huge.sort_values("ret")

print(f"Total dumps >= -30%: {len(dumps_huge)}")
print(f"Pares afetados: {dumps_huge['market'].nunique()}")
print()

if len(dumps_huge) > 0:
    print("TOP 10 PIORES (ordenado por queda):")
    for idx, row in dumps_huge.head(10).iterrows():
        market = row["market"]
        dt = row["dt"]
        ret = row["ret"]
        close = row["close"]
        open_ = row["open"]
        high = row["high"]
        low = row["low"]
        vol = row["volume"]

        # achar candle anterior (1h antes em dados diários = mesmo dia anterior)
        prev = recent[(recent["market"] == market) & (recent["dt"] < dt)].sort_values("dt").tail(1)

        if len(prev) > 0:
            prev_row = prev.iloc[0]
            prev_ret = prev_row["ret"]
            prev_vol = prev_row["volume"]
            prev_close = prev_row["close"]
            vol_ratio = vol / prev_vol if prev_vol > 0 else 0
        else:
            prev_ret = np.nan
            prev_vol = np.nan
            vol_ratio = np.nan
            prev_close = np.nan

        print(f"\n  {market}")
        print(f"    DATA: {dt.strftime('%Y-%m-%d %H:%M')}")
        print(f"    QUEDA: {ret:+.1f}% (open {open_:.6f} > close {close:.6f})")
        print(f"    AMPLITUDE: high {high:.6f}, low {low:.6f} (range {(high-low)/open_*100:.1f}%)")
        print(f"    VOLUME HOJE: {vol:.2e}")
        if not np.isnan(vol_ratio):
            print(f"    VOLUME ANTERIOR: {prev_vol:.2e} (ratio {vol_ratio:.2f}x)")
        if not np.isnan(prev_ret):
            print(f"    SINAL 1h ANTES: {prev_ret:+.1f}% (volume +{(vol_ratio-1)*100:+.0f}% vs H-1)")

print()
print("=" * 80)
print("PADRÃO GERAL (todos os dumps >= -20%)")
print("=" * 80)
print()

dumps_bad = recent[recent["ret"] <= -20].copy()
print(f"Total de dumps >= -20%: {len(dumps_bad)}")
print(f"Mediana queda: {dumps_bad['ret'].median():+.1f}%")
print(f"Pior 10%: {dumps_bad['ret'].quantile(0.1):+.1f}%")
print()

# Volume antes/depois
print("VOLUME PROFILE (comparação H-1):")
dumps_with_prev = []
for market in dumps_bad["market"].unique():
    market_dumps = dumps_bad[dumps_bad["market"] == market].sort_values("dt")
    market_all = recent[recent["market"] == market].sort_values("dt")

    for idx, row in market_dumps.iterrows():
        prev = market_all[market_all["dt"] < row["dt"]].tail(1)
        if len(prev) > 0:
            prev_row = prev.iloc[0]
            vol_ratio = row["volume"] / prev_row["volume"] if prev_row["volume"] > 0 else 0
            dumps_with_prev.append({
                "market": market,
                "dump_ret": row["ret"],
                "vol_ratio": vol_ratio,
                "prev_ret": prev_row["ret"],
                "vol_today": row["volume"],
                "vol_prev": prev_row["volume"],
            })

if dumps_with_prev:
    df_prev = pd.DataFrame(dumps_with_prev)
    print(f"  Volume ratio H-1: mediana {df_prev['vol_ratio'].median():.2f}x (q25={df_prev['vol_ratio'].quantile(0.25):.2f}, q75={df_prev['vol_ratio'].quantile(0.75):.2f})")
    print(f"  Retorno anterior (H-1): mediana {df_prev['prev_ret'].median():+.1f}%")
    print(f"    - De quantos dumps H-1 também era negativo? {(df_prev['prev_ret'] < 0).sum() / len(df_prev) * 100:.0f}%")
    print(f"    - De quantos H-1 era positivo (pump antes do dump)? {(df_prev['prev_ret'] > 0).sum() / len(df_prev) * 100:.0f}%")

print()
print("=" * 80)
print("CONCLUSÃO PRÁTICA")
print("=" * 80)
print()
print("Como detectar em tempo real:")
print("  1. UNIVERSO: todos os dias ~5 dumps >= -20% (0.5% dos pares)")
print("  2. GIGANTESCOS (>= -30%): ~1-2 por 30 dias (raro, mas quando vem = 30-60% queda)")
print("  3. TRIGGER H-1: volume spike (~1.2-2x) melhor que queda anterior")
print("  4. ENTRADA: H-1 confirmou reversal OU pump prévio? Entra SHORT 1h em confirmação")
print("  5. EXIT: time-stop 24h OU profit 3-5% OU stop 1%")
print()
print("PRÓX PASSO: backtestá-lo com dados 1h reais (nuvem coleta 1h contínua)")
