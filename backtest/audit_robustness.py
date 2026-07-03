# audit_robustness.py — Auditoria de robustez da lei de dissipacao
# Perguntas do auditor:
#  1. A lei vale em TODOS os regimes (2023 bull, 2024, 2025, 2026 bear)?  [OOS temporal]
#  2. Effective-N: quantos DIAS distintos sustentam o sinal pos-pump? (clusters!)
#  3. Quantos dos pumps >=30% tem FUTURES na CoinEx (shortavel de fato)?

import json
import time
import urllib.request
from pathlib import Path

import numpy as np
import pandas as pd

DATA = Path(__file__).parent / "data"


def main():
    df = pd.read_csv(DATA / "universe_daily_full.csv")
    df["dt"] = pd.to_datetime(df["ts"], unit="ms")
    for c in ("open", "high", "low", "close", "vol_usd"):
        df[c] = pd.to_numeric(df[c], errors="coerce")
    df = df.dropna(subset=["open", "close"])
    df = df[df["open"] > 0].sort_values(["market", "ts"]).reset_index(drop=True)
    df["ret"] = (df["close"] - df["open"]) / df["open"] * 100
    df["ret_d1"] = df.groupby("market")["ret"].shift(-1)
    df["year"] = df["dt"].dt.year
    d = df.dropna(subset=["ret_d1"])
    d = d[d["vol_usd"] >= 3000]

    # ── 1. LEI POR ANO/REGIME (o teste OOS que decide tudo) ────────────
    print("=== 1. POS-PUMP >=30%: a lei sobrevive em cada regime? ===")
    print(f"    {'ano':>5} | {'n':>5} | {'D+1 mediana':>11} | {'cai%':>5} | {'dump-20%':>8} | regime")
    regimes = {2023: "BULL", 2024: "transicao", 2025: "BEAR", 2026: "BEAR_WEAK"}
    pp = d[d["ret"] >= 30]
    for y in sorted(pp["year"].unique()):
        s = pp[pp["year"] == y]
        if len(s) < 30:
            print(f"    {y:>5} | n={len(s)} (pouco)")
            continue
        print(f"    {y:>5} | {len(s):>5} | {s['ret_d1'].median():>+10.1f}% | {(s['ret_d1']<0).mean()*100:>4.0f}% | {(s['ret_d1']<=-20).mean()*100:>7.1f}% | {regimes.get(y,'?')}")

    print("\n    (faixa 20-30% por ano)")
    pp2 = d[d["ret"].between(20, 30)]
    for y in sorted(pp2["year"].unique()):
        s = pp2[pp2["year"] == y]
        if len(s) < 30:
            continue
        print(f"    {y:>5} | {len(s):>5} | {s['ret_d1'].median():>+10.1f}% | {(s['ret_d1']<0).mean()*100:>4.0f}%")

    # curva completa 2023 (bull) vs 2026 (bear)
    print("\n    Curva completa BULL 2023 vs BEAR 2026 (mediana D+1):")
    bins = [-100, -10, 0, 10, 20, 30, 50, 10000]
    labels = ["<-10", "-10..0", "0..10", "10..20", "20..30", "30..50", ">50"]
    for y in (2023, 2026):
        s = d[d["year"] == y].copy()
        s["rb"] = pd.cut(s["ret"], bins, labels=labels)
        t = s.groupby("rb", observed=True)["ret_d1"].median()
        row = " | ".join(f"{k}: {v:+.1f}" for k, v in t.items())
        print(f"    {y}: {row}")

    # ── 2. EFFECTIVE-N: dias distintos (cluster correction) ────────────
    print("\n=== 2. EFFECTIVE-N do sinal pos-pump >=30% ===")
    pp = d[d["ret"] >= 30]
    days = pp["dt"].dt.date.nunique()
    print(f"    eventos: {len(pp)} | dias distintos: {days} | media {len(pp)/max(days,1):.1f} eventos/dia")
    # win-rate por DIA (cada dia = 1 observacao independente)
    byday = pp.groupby(pp["dt"].dt.date)["ret_d1"].median()
    print(f"    win-rate POR DIA (mediana do dia < 0): {(byday<0).mean()*100:.0f}% de {len(byday)} dias")
    print(f"    mediana das medianas diarias: {byday.median():+.1f}%")

    # ── 3. SHORTABILITY: quantos tem futures? ──────────────────────────
    print("\n=== 3. SHORTABILITY: pumps >=30% com futures na CoinEx ===")
    try:
        with urllib.request.urlopen("https://api.coinex.com/v2/futures/market", timeout=15) as r:
            fut = json.loads(r.read().decode())
        fut_mkts = {m["market"] for m in fut.get("data", [])}
        print(f"    futures listados: {len(fut_mkts)} pares")
        recent = pp[pp["dt"] >= pp["dt"].max() - pd.Timedelta(days=120)]
        has = recent["market"].isin(fut_mkts)
        print(f"    pumps >=30% ultimos 120d: {len(recent)} | com futures: {has.sum()} ({has.mean()*100:.0f}%)")
        sh = recent[has]
        if len(sh) > 30:
            print(f"    D+1 mediana SO dos shortaveis: {sh['ret_d1'].median():+.1f}% | cai {(sh['ret_d1']<0).mean()*100:.0f}%")
            print(f"    candidatos shortaveis/dia: {len(sh)/120:.1f}")
    except Exception as e:
        print(f"    erro futures: {e}")


if __name__ == "__main__":
    main()
