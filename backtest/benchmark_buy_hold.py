"""
benchmark_buy_hold.py -- Sistema Baseline V2 vs Buy & Hold passivo.

Compara, para cada run validado:
  - Retorno do sistema (em R) anualizado vs HODL %
  - Max drawdown do sistema (R) vs HODL %
  - Veredito por run + decisao go-live consolidada.

Funcoes PURAS (sem I/O) testaveis isoladamente:
  hodl_return_pct(entry_price, exit_price)
  hodl_max_dd_pct(prices)
  alpha_pct(system_pct, hodl_pct)
  classify_verdict(system_return, hodl_return, system_dd, hodl_dd)
  annualized_return_pct(total_return_pct, days)
  build_comparison(run_def, prices) -> dict

I/O isolado em fetch_daily_closes() (CoinEx publico, fallback Supabase opcional).

CLI:
  python backtest/benchmark_buy_hold.py --runs all
  python backtest/benchmark_buy_hold.py --run btc_in_sample
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Dict, List, Optional, Sequence, Tuple

import requests


# Sistema baseline V2 -- fonte: project_baseline_v2_equity_stop.md (validated_3_runs)
# Equity final em R por run vem do bloco "Numero a observar com ceticismo" (136 / 56 / 163).
BASELINE_V2_RUNS: List[Dict] = [
    {
        "run_id": "btc_in_sample",
        "market": "BTCUSDT",
        "period": ("2024-11-01", "2025-05-01"),
        "system": {
            "trades": 86,
            "final_equity_R": 136.0,
            "max_dd_R": 10.8,
            "win_rate": 0.640,
            "expectancy_R": 1.905,
            "profit_factor": 8.21,
        },
    },
    {
        "run_id": "btc_oos_temporal",
        "market": "BTCUSDT",
        "period": ("2025-05-01", "2025-11-01"),
        "system": {
            "trades": 54,
            "final_equity_R": 56.0,
            "max_dd_R": 10.8,
            "win_rate": 0.630,
            "expectancy_R": 1.043,
            "profit_factor": 3.71,
        },
    },
    {
        "run_id": "eth_oos_pair",
        "market": "ETHUSDT",
        "period": ("2024-11-01", "2025-05-01"),
        "system": {
            "trades": 73,
            "final_equity_R": 163.0,
            "max_dd_R": 10.4,
            "win_rate": 0.726,
            "expectancy_R": 2.236,
            "profit_factor": 9.16,
        },
    },
]


# ──────────────────────────────────────────────────────────────────────────────
# Funcoes puras
# ──────────────────────────────────────────────────────────────────────────────

def hodl_return_pct(entry_price: float, exit_price: float) -> float:
    """Retorno percentual de comprar @entry e vender @exit."""
    if entry_price <= 0:
        raise ValueError("entry_price deve ser positivo")
    return (exit_price / entry_price - 1.0) * 100.0


def hodl_max_dd_pct(prices: Sequence[float]) -> float:
    """Max drawdown percentual (sempre <= 0) ao longo da serie de precos."""
    if not prices:
        return 0.0
    peak = prices[0]
    max_dd = 0.0
    for p in prices:
        if p > peak:
            peak = p
        if peak > 0:
            dd = (p / peak - 1.0) * 100.0
            if dd < max_dd:
                max_dd = dd
    return max_dd


def alpha_pct(system_return_pct: float, hodl_return_pct_value: float) -> float:
    """Diferenca em pontos percentuais entre sistema e HODL."""
    return system_return_pct - hodl_return_pct_value


def annualized_return_pct(total_return_pct: float, days: int) -> float:
    """Anualiza retorno total via composicao continua simplificada (CAGR)."""
    if days <= 0:
        return 0.0
    years = days / 365.25
    if years <= 0:
        return 0.0
    base = 1.0 + total_return_pct / 100.0
    if base <= 0:
        return -100.0
    return (base ** (1.0 / years) - 1.0) * 100.0


def classify_verdict(
    system_return_pct: float,
    hodl_return_pct_value: float,
    system_dd_pct: float,
    hodl_dd_pct: float,
) -> str:
    """Veredito segundo matriz 2x2 (retorno x risco).

    DDs sao numeros negativos; 'menor DD' = mais proximo de zero (abs menor).
    """
    outperform = system_return_pct > hodl_return_pct_value
    lower_risk = abs(system_dd_pct) < abs(hodl_dd_pct)
    if outperform and lower_risk:
        return "OUTPERFORM_LOWER_RISK"
    if outperform and not lower_risk:
        return "OUTPERFORM_HIGHER_RISK"
    if not outperform and lower_risk:
        return "UNDERPERFORM_LOWER_RISK"
    return "UNDERPERFORM_HIGHER_RISK"


def system_return_to_pct(final_equity_R: float, risk_per_trade_pct: float = 1.0) -> float:
    """Converte equity em R para retorno %, assumindo risco fixo por trade.

    Default 1% por trade (regra de ouro do projeto).
    """
    return final_equity_R * risk_per_trade_pct


def system_dd_to_pct(max_dd_R: float, risk_per_trade_pct: float = 1.0) -> float:
    """DD em R para % (negativo)."""
    return -abs(max_dd_R) * risk_per_trade_pct


def days_between(start: str, end: str) -> int:
    a = datetime.fromisoformat(start)
    b = datetime.fromisoformat(end)
    return (b - a).days


# ──────────────────────────────────────────────────────────────────────────────
# Comparison builder
# ──────────────────────────────────────────────────────────────────────────────

def build_comparison(run_def: Dict, daily_closes: Sequence[float]) -> Dict:
    """Constroi entrada de comparacao para um run.

    daily_closes deve cobrir o periodo (pode estar vazio -> retorno HODL = NaN gracioso).
    """
    market = run_def["market"]
    start, end = run_def["period"]
    sys_stats = run_def["system"]

    duration_days = days_between(start, end)

    if not daily_closes:
        hodl_entry = 0.0
        hodl_exit = 0.0
        hodl_ret_pct = 0.0
        hodl_dd_pct = 0.0
        data_ok = False
    else:
        hodl_entry = float(daily_closes[0])
        hodl_exit = float(daily_closes[-1])
        hodl_ret_pct = hodl_return_pct(hodl_entry, hodl_exit) if hodl_entry > 0 else 0.0
        hodl_dd_pct = hodl_max_dd_pct(daily_closes)
        data_ok = True

    sys_ret_pct = system_return_to_pct(sys_stats["final_equity_R"])
    sys_dd_pct = system_dd_to_pct(sys_stats["max_dd_R"])
    sys_annualized = annualized_return_pct(sys_ret_pct, duration_days)

    verdict = classify_verdict(sys_ret_pct, hodl_ret_pct, sys_dd_pct, hodl_dd_pct)
    alpha = alpha_pct(sys_ret_pct, hodl_ret_pct)
    dd_ratio = (abs(sys_dd_pct) / abs(hodl_dd_pct)) if abs(hodl_dd_pct) > 0 else None

    # Exposicao de capital: % de barras com edge ativo (proxy: trades/dias)
    capital_exposed_pct = (
        100.0 * sys_stats["trades"] / max(1, duration_days)
        if duration_days > 0 else 0.0
    )

    return {
        "run_id": run_def["run_id"],
        "market": market,
        "period": f"{start} to {end}",
        "system": {
            "trades": sys_stats["trades"],
            "final_equity_R": sys_stats["final_equity_R"],
            "max_dd_R": sys_stats["max_dd_R"],
            "win_rate": sys_stats["win_rate"],
            "annualized_return_pct": round(sys_annualized, 2),
        },
        "hodl": {
            "entry_price": round(hodl_entry, 2),
            "exit_price": round(hodl_exit, 2),
            "return_pct": round(hodl_ret_pct, 2),
            "max_dd_pct": round(hodl_dd_pct, 2),
            "duration_days": duration_days,
            "data_available": data_ok,
        },
        "comparison_metrics": {
            "alpha_pct": round(alpha, 2),
            "dd_ratio": round(dd_ratio, 3) if dd_ratio is not None else None,
            "system_capital_exposed_pct": round(capital_exposed_pct, 2),
            "verdict": verdict,
        },
    }


def build_summary(comparisons: List[Dict]) -> Tuple[Dict, Dict]:
    """Sumario consolidado + criterio de go-live."""
    all_outperform = all(
        c["comparison_metrics"]["verdict"].startswith("OUTPERFORM")
        for c in comparisons
    )
    all_lower_dd = all(
        c["comparison_metrics"]["verdict"].endswith("LOWER_RISK")
        for c in comparisons
    )
    alphas = sorted(c["comparison_metrics"]["alpha_pct"] for c in comparisons)
    if alphas:
        n = len(alphas)
        median_alpha = alphas[n // 2] if n % 2 == 1 else (alphas[n // 2 - 1] + alphas[n // 2]) / 2.0
    else:
        median_alpha = 0.0

    if all_outperform and all_lower_dd:
        recommendation = "SISTEMA_DOMINA_HODL"
    elif all_outperform:
        recommendation = "SISTEMA_SUPERA_RETORNO_MAS_RISCO_MAIOR"
    elif all_lower_dd:
        recommendation = "SISTEMA_REDUZ_RISCO_SEM_GANHO"
    else:
        recommendation = "HODL_DOMINA"

    go_live_passed = all_outperform and all_lower_dd

    summary = {
        "all_runs_outperform_hodl": all_outperform,
        "all_runs_lower_dd_than_hodl": all_lower_dd,
        "median_alpha_pct": round(median_alpha, 2),
        "recommendation": recommendation,
        "go_live_criterion_passed": go_live_passed,
    }
    criterion = {
        "rule": "Sistema retorna mais E tem DD menor em todos os 3 runs",
        "passed": go_live_passed,
        "explanation": (
            "Sistema domina HODL em retorno e em risco nos 3 runs validados."
            if go_live_passed
            else "Pelo menos 1 run nao satisfaz outperform+lower_risk simultaneamente."
        ),
    }
    return summary, criterion


# ──────────────────────────────────────────────────────────────────────────────
# Data fetch (CoinEx publico) -- isolado, fora das funcoes puras
# ──────────────────────────────────────────────────────────────────────────────

COINEX_KLINE_URL = "https://api.coinex.com/v2/futures/kline"


def fetch_daily_closes_coinex(market: str, start: str, end: str) -> List[float]:
    """Baixa closes diarios via CoinEx publico para o periodo [start, end]."""
    start_dt = datetime.fromisoformat(start).replace(tzinfo=timezone.utc)
    end_dt = datetime.fromisoformat(end).replace(tzinfo=timezone.utc)
    closes: List[float] = []
    # CoinEx v2/futures/kline -- limite 1000 candles por chamada, paginacao via end_time
    end_ts = int(end_dt.timestamp() * 1000)
    start_ts = int(start_dt.timestamp() * 1000)
    while end_ts > start_ts:
        params = {
            "market": market,
            "period": "1day",
            "limit": 1000,
            "end_time": end_ts,
        }
        try:
            r = requests.get(COINEX_KLINE_URL, params=params, timeout=15)
            r.raise_for_status()
            data = r.json().get("data") or []
        except Exception:
            break
        if not data:
            break
        # Cada item: { created_at, open, close, high, low, volume, ... }
        batch_closes: List[Tuple[int, float]] = []
        oldest_ts = end_ts
        for row in data:
            ts = int(row.get("created_at", 0))
            close = float(row.get("close", 0))
            if ts < start_ts:
                continue
            batch_closes.append((ts, close))
            if ts < oldest_ts:
                oldest_ts = ts
        if not batch_closes:
            break
        closes = [c for _, c in sorted(batch_closes)] + closes
        if oldest_ts <= start_ts or len(data) < 1000:
            break
        end_ts = oldest_ts - 1
    # Dedupe por ts ja ocorreu via list rebuild; ordenado asc.
    return closes


def fetch_daily_closes(market: str, start: str, end: str) -> List[float]:
    """Wrapper: tenta CoinEx; falha silenciosa retorna []."""
    try:
        return fetch_daily_closes_coinex(market, start, end)
    except Exception:
        return []


# ──────────────────────────────────────────────────────────────────────────────
# Orquestrador + CLI
# ──────────────────────────────────────────────────────────────────────────────

def run_benchmark(run_ids: Optional[List[str]] = None) -> Dict:
    if run_ids:
        runs = [r for r in BASELINE_V2_RUNS if r["run_id"] in run_ids]
    else:
        runs = BASELINE_V2_RUNS

    comparisons: List[Dict] = []
    for r in runs:
        closes = fetch_daily_closes(r["market"], r["period"][0], r["period"][1])
        comparisons.append(build_comparison(r, closes))

    summary, criterion = build_summary(comparisons)

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "run_date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "status": "completed",
        "comparison": comparisons,
        "summary": summary,
        "go_live_criterion": criterion,
    }


def main():
    parser = argparse.ArgumentParser(description="Benchmark Sistema Baseline V2 vs HODL")
    parser.add_argument("--runs", choices=["all"], default=None,
                        help="Executa todos os runs validados")
    parser.add_argument("--run", choices=[r["run_id"] for r in BASELINE_V2_RUNS], default=None,
                        help="Executa apenas o run especificado")
    parser.add_argument("--output", default=None,
                        help="Caminho de saida do JSON (default: journal/benchmark_buy_hold_results.json)")
    args = parser.parse_args()

    if args.run:
        run_ids = [args.run]
    else:
        run_ids = None  # all

    result = run_benchmark(run_ids)

    out_path = args.output or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "journal", "benchmark_buy_hold_results.json"
    )
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(json.dumps(result["summary"], indent=2, ensure_ascii=False))
    print(f"\n[OK] Output: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
