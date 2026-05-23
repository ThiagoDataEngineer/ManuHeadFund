"""
journal_analytics.py — Analytics sobre gem_signals.csv e gem_trades.csv
Uso:
    python backtest/journal_analytics.py
    python backtest/journal_analytics.py --signals journal/gem_signals.csv
"""

import argparse
import os
import sys
from dataclasses import dataclass, field
from typing import Dict, List, Optional

try:
    import pandas as pd
except ImportError:
    print("pandas nao instalado. Execute: pip install pandas")
    sys.exit(1)


# ─────────────────────────────────────────────────────────────────────────────
# Load
# ─────────────────────────────────────────────────────────────────────────────

def load_gem_signals(path: str) -> pd.DataFrame:
    if not os.path.exists(path):
        return pd.DataFrame()
    df = pd.read_csv(path, encoding="utf-8")
    if df.empty:
        return df
    # normaliza tipos
    for col in ["score", "spike_ratio", "pct_change_today", "sizing_usd"]:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    if "timestamp" in df.columns:
        df["timestamp"] = pd.to_datetime(df["timestamp"], errors="coerce")
    return df


def load_gem_trades(path: str) -> pd.DataFrame:
    if not os.path.exists(path):
        return pd.DataFrame()
    df = pd.read_csv(path, encoding="utf-8")
    if df.empty:
        return df
    for col in ["price_entry", "price_exit", "pnl_pct", "qty"]:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


# ─────────────────────────────────────────────────────────────────────────────
# Analytics — signals
# ─────────────────────────────────────────────────────────────────────────────

def gate_pass_rate(df: pd.DataFrame) -> Dict[str, float]:
    """% dos scans que chegaram a cada gate (G1..G6)."""
    if df.empty:
        return {}
    total = len(df)
    rates = {}
    for gate in ["G1", "G2", "G3", "G4", "G5", "G6"]:
        passed = df["gates_passed"].fillna("").str.contains(gate).sum()
        rates[gate] = round(passed / total * 100, 1)
    return rates


def top_blocked_gate(df: pd.DataFrame) -> Dict[str, int]:
    """Histograma de qual gate bloqueia mais."""
    if df.empty or "gate_failed" not in df.columns:
        return {}
    counts = df["gate_failed"].fillna("PASSED").value_counts().to_dict()
    return counts


def discovery_vs_momentum_ratio(df: pd.DataFrame) -> Dict[str, float]:
    """Ratio DISCOVERY vs MOMENTUM nos sinais aprovados (score > 0)."""
    if df.empty:
        return {"DISCOVERY": 0.0, "MOMENTUM": 0.0}
    approved = df[df["score"].fillna(0) > 0]
    if approved.empty:
        return {"DISCOVERY": 0.0, "MOMENTUM": 0.0}
    counts = approved["mode"].value_counts()
    total = len(approved)
    return {
        "DISCOVERY": round(counts.get("DISCOVERY", 0) / total * 100, 1),
        "MOMENTUM":  round(counts.get("MOMENTUM", 0)  / total * 100, 1),
    }


def spike_ratio_passed_vs_blocked(df: pd.DataFrame) -> Dict[str, float]:
    """Spike ratio medio: sinais que passaram todos os gates vs bloqueados."""
    if df.empty or "spike_ratio" not in df.columns:
        return {}
    passed  = df[df["gate_failed"].fillna("") == ""]["spike_ratio"].dropna()
    blocked = df[df["gate_failed"].fillna("") != ""]["spike_ratio"].dropna()
    return {
        "passed_avg":  round(passed.mean(),  2) if not passed.empty  else 0.0,
        "blocked_avg": round(blocked.mean(), 2) if not blocked.empty else 0.0,
    }


def signals_per_day(df: pd.DataFrame) -> pd.Series:
    """Contagem de sinais por dia."""
    if df.empty or "timestamp" not in df.columns:
        return pd.Series(dtype=int)
    return df.groupby(df["timestamp"].dt.date).size()


# ─────────────────────────────────────────────────────────────────────────────
# Analytics — trades
# ─────────────────────────────────────────────────────────────────────────────

def pnl_summary(df: pd.DataFrame) -> Dict:
    """Resumo de PnL para trades fechados (status != OPEN)."""
    if df.empty:
        return {}
    closed = df[df["status"].fillna("OPEN") != "OPEN"] if "status" in df.columns else pd.DataFrame()
    if closed.empty:
        return {"closed_trades": 0, "note": "sem trades fechados ainda"}
    pnl = closed["pnl_pct"].dropna()
    return {
        "closed_trades": len(closed),
        "win_rate":      round((pnl > 0).mean() * 100, 1),
        "avg_pnl_pct":   round(pnl.mean(), 2),
        "best":          round(pnl.max(), 2),
        "worst":         round(pnl.min(), 2),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Report
# ─────────────────────────────────────────────────────────────────────────────

def print_report(signals_path: str, trades_path: str) -> None:
    signals = load_gem_signals(signals_path)
    trades  = load_gem_trades(trades_path)

    print("\n" + "=" * 60)
    print("  JOURNAL ANALYTICS")
    print("=" * 60)

    print(f"\n  Sinais carregados : {len(signals)}")
    print(f"  Trades carregados : {len(trades)}")

    if not signals.empty:
        print("\n  Gate pass rate:")
        for gate, pct in gate_pass_rate(signals).items():
            print(f"    {gate}: {pct}%")

        print("\n  Top gates bloqueadores:")
        for gate, cnt in sorted(top_blocked_gate(signals).items(), key=lambda x: -x[1])[:5]:
            print(f"    {gate:<12} {cnt}")

        print("\n  Discovery vs Momentum (aprovados):")
        for mode, pct in discovery_vs_momentum_ratio(signals).items():
            print(f"    {mode}: {pct}%")

        print("\n  Spike ratio medio:")
        for k, v in spike_ratio_passed_vs_blocked(signals).items():
            print(f"    {k}: {v}x")

        spd = signals_per_day(signals)
        if not spd.empty:
            print(f"\n  Sinais/dia: avg={round(spd.mean(),1)}  max={spd.max()}  dias={len(spd)}")

    if not trades.empty:
        print("\n  PnL summary:")
        for k, v in pnl_summary(trades).items():
            print(f"    {k}: {v}")

    print("=" * 60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--signals", default="journal/gem_signals.csv")
    parser.add_argument("--trades",  default="journal/gem_trades.csv")
    args = parser.parse_args()
    print_report(args.signals, args.trades)
