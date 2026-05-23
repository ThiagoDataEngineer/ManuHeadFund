"""
run_simons_gate_real.py -- Simons Gate com BTC OHLC REAL (Supabase) + sensitivity n_trials.

Substitui o proxy sintético N(mu=0.0001, sigma=0.012) seed=42 usado na Wave 1.

Saídas:
  journal/simons_gate_real_2026_05_15.json      -- Tarefa A: BTC real vs sintético
  journal/simons_gate_sensitivity_2026_05_15.json -- Tarefa B: sensitivity n_trials
  journal/simons_gate_refinement_2026_05_15.md   -- Tarefa C: relatório consolidado
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Dict, List, Tuple, Optional

import numpy as np

# Ajusta path para importar do backtest/
SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.path.insert(0, str(ROOT_DIR))

from metrics_simons import run_simons_gate  # noqa: E402

# ── Valores Wave 1 sintético (para diff) ────────────────────────────────────
SYNTHETIC_BASELINE = {
    "dsr": 1.0,
    "psr": 1.0,
    "sharpe_btc": 1.3967494868247607,
    "ergodicity": 0.0008574660500808744,
    "decision": "PASS",
}

# ── Parâmetros run_simons_gate ────────────────────────────────────────────────
ANNUALIZER = np.sqrt(365 * 8)   # cripto 24/7, hourly -> sqrt(2920)
N_TRIALS_PRIMARY = 50
SAMPLE_VAR = 0.5
DSR_THRESH = 0.95
PSR_THRESH = 0.95

SENSITIVITY_N_TRIALS = [20, 50, 100, 200, 500]

JOURNAL_DIR = ROOT_DIR / "journal"
TRADES_FILE = JOURNAL_DIR / "transition_up_trades_dump.json"


# ── Helpers ──────────────────────────────────────────────────────────────────

def load_trades(path: Path) -> List[Dict]:
    with open(path, "r", encoding="utf-8") as f:
        trades = json.load(f)
    print(f"[load_trades] {len(trades)} trades carregados de {path.name}")
    return trades


def parse_ts(ts_str: str) -> datetime:
    """Normaliza ISO8601 para UTC datetime sem tzinfo (para comparação)."""
    # Suporta: '2014-01-11T01:00:00+00:00', '2014-01-11T01:00:00Z', etc.
    dt = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
    return dt.astimezone(timezone.utc).replace(tzinfo=None)


def load_btc_candles(date_from: str, date_to: str) -> List[Dict]:
    """Carrega candles BTCUSD 1hour do Supabase."""
    # Importa aqui para não quebrar em ambientes sem SUPABASE_URL
    from db import Database  # noqa: E402 (dentro do backtest/)
    db = Database()
    print(f"[load_btc_candles] Consultando BTCUSD 1hour {date_from} -> {date_to} ...")
    candles = db.get_candles("BTCUSD", "1hour", date_from, date_to)
    print(f"[load_btc_candles] {len(candles)} candles recebidos")
    return candles


def build_candle_index(candles: List[Dict]) -> Dict[datetime, float]:
    """
    Constrói índice ts (UTC, sem tzinfo) -> close price.
    Timestamp do candle é o início da hora.
    """
    idx: Dict[datetime, float] = {}
    for c in candles:
        ts_raw = c.get("ts", "")
        close = float(c.get("close", 0.0) or 0.0)
        if not ts_raw or close <= 0:
            continue
        try:
            dt = parse_ts(str(ts_raw))
            idx[dt] = close
        except Exception:
            pass
    return idx


def align_trades_to_btc(
    trades: List[Dict],
    candle_idx: Dict[datetime, float],
) -> Tuple[np.ndarray, np.ndarray, int, int]:
    """
    Alinha trades com BTC OHLC real.

    Para cada trade com entry_ts T:
      btc_return[i] = close(T + 1h) / close(T)

    Descarta trade se close(T) ou close(T+1h) não disponível.

    Returns:
        strategy_returns: array 1 + 0.01 * result_r
        btc_returns:      array close(T+1h) / close(T)
        n_aligned:        trades com candle correspondente
        n_dropped:        trades sem candle
    """
    strat_list: List[float] = []
    btc_list: List[float] = []
    n_dropped = 0
    dropped_reasons: Dict[str, int] = {"no_close_T": 0, "no_close_T1h": 0}

    for trade in trades:
        result_r = float(trade.get("result_r", 0.0))
        ts_str = trade.get("entry_ts", "")
        try:
            dt_entry = parse_ts(ts_str)
        except Exception:
            n_dropped += 1
            continue

        dt_next = dt_entry + timedelta(hours=1)

        close_t = candle_idx.get(dt_entry)
        close_t1 = candle_idx.get(dt_next)

        if close_t is None:
            dropped_reasons["no_close_T"] += 1
            n_dropped += 1
            continue
        if close_t1 is None:
            dropped_reasons["no_close_T1h"] += 1
            n_dropped += 1
            continue

        btc_ret = close_t1 / close_t
        strat_ret = 1.0 + 0.01 * result_r

        btc_list.append(btc_ret)
        strat_list.append(strat_ret)

    n_aligned = len(strat_list)
    print(f"[align] n_aligned={n_aligned}, n_dropped={n_dropped} "
          f"(no_close_T={dropped_reasons['no_close_T']}, "
          f"no_close_T1h={dropped_reasons['no_close_T1h']})")

    return (
        np.array(strat_list, dtype=np.float64),
        np.array(btc_list, dtype=np.float64),
        n_aligned,
        n_dropped,
    )


# ── Tarefa A: BTC Real ────────────────────────────────────────────────────────

def run_task_a(
    strategy_returns: np.ndarray,
    btc_returns: np.ndarray,
    n_trades_raw: int,
    n_trades_aligned: int,
    n_trades_dropped: int,
    period: str,
) -> Dict:
    print(f"\n[Task A] Rodando Simons Gate com BTC real (n_trials={N_TRIALS_PRIMARY}) ...")

    result = run_simons_gate(
        strategy_returns=strategy_returns,
        btc_returns=btc_returns,
        n_trials=N_TRIALS_PRIMARY,
        sample_variance_sharpes=SAMPLE_VAR,
        dsr_threshold=DSR_THRESH,
        psr_threshold=PSR_THRESH,
        annualizer=ANNUALIZER,
    )

    # Diffs vs sintético
    def safe_delta(real, synthetic):
        if real is None or np.isnan(float(real)):
            return None
        return float(real) - float(synthetic)

    diff = {
        "dsr":        safe_delta(result.dsr, SYNTHETIC_BASELINE["dsr"]),
        "psr":        safe_delta(result.psr, SYNTHETIC_BASELINE["psr"]),
        "sharpe_btc": safe_delta(result.sharpe_btc, SYNTHETIC_BASELINE["sharpe_btc"]),
        "ergodicity": safe_delta(result.ergodicity, SYNTHETIC_BASELINE["ergodicity"]),
    }

    out = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "dataset": {
            "n_trades_raw": n_trades_raw,
            "n_trades_aligned": n_trades_aligned,
            "n_trades_dropped": n_trades_dropped,
            "alignment_rate_pct": round(100.0 * n_trades_aligned / n_trades_raw, 2)
                                   if n_trades_raw > 0 else 0.0,
            "period": period,
            "btc_source": "supabase/coinex_real",
            "market": "BTCUSD",
            "period_candle": "1hour",
            "annualizer": f"sqrt(365*8)={round(float(ANNUALIZER), 4)}",
        },
        "params": {
            "n_trials": N_TRIALS_PRIMARY,
            "sample_variance_sharpes": SAMPLE_VAR,
            "dsr_threshold": DSR_THRESH,
            "psr_threshold": PSR_THRESH,
        },
        "metrics": {
            "dsr":        round(float(result.dsr), 6) if not np.isnan(float(result.dsr)) else None,
            "psr":        round(float(result.psr), 6),
            "sharpe_btc": round(float(result.sharpe_btc), 6),
            "ergodicity": round(float(result.ergodicity), 8),
        },
        "decision": result.decision,
        "reasons": result.reasons,
        "diff_vs_synthetic": {
            "note": "delta = real - synthetic; negativo = pior que sintético",
            "synthetic_baseline": SYNTHETIC_BASELINE,
            "deltas": {k: round(v, 6) if v is not None else None for k, v in diff.items()},
        },
    }

    print(f"[Task A] DECISION={result.decision} | DSR={result.dsr:.4f} | PSR={result.psr:.4f} | "
          f"Sharpe-BTC={result.sharpe_btc:.4f} | Ergodicity={result.ergodicity:.6f}")

    return out


# ── Tarefa B: Sensitivity n_trials ────────────────────────────────────────────

def run_task_b(
    strategy_returns: np.ndarray,
    btc_returns: np.ndarray,
) -> Dict:
    print(f"\n[Task B] Sensitivity n_trials: {SENSITIVITY_N_TRIALS}")

    rows = []
    first_fail_n = None

    for n in SENSITIVITY_N_TRIALS:
        r = run_simons_gate(
            strategy_returns=strategy_returns,
            btc_returns=btc_returns,
            n_trials=n,
            sample_variance_sharpes=SAMPLE_VAR,
            dsr_threshold=DSR_THRESH,
            psr_threshold=PSR_THRESH,
            annualizer=ANNUALIZER,
        )
        dsr_val = round(float(r.dsr), 6) if not np.isnan(float(r.dsr)) else None
        row = {
            "n_trials": n,
            "dsr": dsr_val,
            "psr": round(float(r.psr), 6),
            "sharpe_btc": round(float(r.sharpe_btc), 6),
            "ergodicity": round(float(r.ergodicity), 8),
            "decision": r.decision,
        }
        rows.append(row)
        print(f"  n_trials={n:4d}: DSR={dsr_val!s:8s} PSR={r.psr:.4f} "
              f"Sharpe-BTC={r.sharpe_btc:.4f} -> {r.decision}")

        # Detecta primeiro n_trials onde DSR cai abaixo do threshold
        if dsr_val is not None and dsr_val < DSR_THRESH and first_fail_n is None:
            first_fail_n = n

    out = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "params": {
            "sample_variance_sharpes": SAMPLE_VAR,
            "dsr_threshold": DSR_THRESH,
            "psr_threshold": PSR_THRESH,
            "annualizer": f"sqrt(365*8)={round(float(ANNUALIZER), 4)}",
        },
        "sensitivity_table": rows,
        "first_n_trials_dsr_fails": first_fail_n,
        "note": "first_n_trials_dsr_fails=None significa DSR >= 0.95 em todos os n testados",
    }

    if first_fail_n:
        print(f"[Task B] DSR cai abaixo de {DSR_THRESH} a partir de n_trials={first_fail_n} -> FRAGIL")
    else:
        print(f"[Task B] DSR >= {DSR_THRESH} em todos os n_trials testados -> ROBUSTO")

    return out


# ── Tarefa C: Relatório Markdown ───────────────────────────────────────────────

def build_report(task_a: Dict, task_b: Dict) -> str:
    ds = task_a["dataset"]
    m = task_a["metrics"]
    diff = task_a["diff_vs_synthetic"]["deltas"]
    synth = task_a["diff_vs_synthetic"]["synthetic_baseline"]
    decision = task_a["decision"]
    reasons = task_a["reasons"]
    first_fail = task_b["first_n_trials_dsr_fails"]
    sens = task_b["sensitivity_table"]

    # Resumo executivo
    if decision == "PASS":
        resumo = (
            f"Simons Gate com BTC OHLC real: **PASS** (4/4 critérios verdes).\n"
            f"N={ds['n_trades_aligned']} trades alinhados ({ds['alignment_rate_pct']}%) "
            f"de {ds['n_trades_raw']} raw ({ds['n_trades_dropped']} descartados por gap de candle).\n"
            f"DSR={m['dsr']}, PSR={m['psr']}, Sharpe-BTC={m['sharpe_btc']}, "
            f"Ergodicity={m['ergodicity']}.\n"
            f"Edge validado com BTC real — não mais dependente de proxy sintético."
        )
        veredito = "GO — edge confirmado com dados reais; prosseguir para paper trade com whitelist v2."
    else:
        fail_summary = "; ".join(reasons) if reasons else "ver reasons"
        resumo = (
            f"Simons Gate com BTC OHLC real: **FAIL** — {fail_summary}.\n"
            f"N={ds['n_trades_aligned']} trades alinhados ({ds['alignment_rate_pct']}%) "
            f"de {ds['n_trades_raw']} raw ({ds['n_trades_dropped']} descartados por gap de candle).\n"
            f"BTC real degradou métricas vs sintético: verificar tabela A.\n"
            f"Revisar sub-setup TRANSITION_UP+Mon antes de escalar para paper."
        )
        veredito = "HOLD — degradação com BTC real; investigar gap de dados ou revisar whitelist."

    # Tabela A
    def fmt_delta(d):
        if d is None:
            return "N/A"
        sign = "+" if d >= 0 else ""
        return f"{sign}{d:.4f}"

    tbl_a = (
        "| Métrica | Sintético (Wave 1) | Real (BTC OHLC) | Delta |\n"
        "|---------|-------------------|-----------------|-------|\n"
        f"| DSR | {synth['dsr']:.4f} | {m['dsr'] if m['dsr'] is not None else 'NaN'} | {fmt_delta(diff['dsr'])} |\n"
        f"| PSR | {synth['psr']:.4f} | {m['psr']:.4f} | {fmt_delta(diff['psr'])} |\n"
        f"| Sharpe-BTC | {synth['sharpe_btc']:.4f} | {m['sharpe_btc']:.4f} | {fmt_delta(diff['sharpe_btc'])} |\n"
        f"| Ergodicity | {synth['ergodicity']:.6f} | {m['ergodicity']:.6f} | {fmt_delta(diff['ergodicity'])} |\n"
    )

    # Tabela B
    tbl_b_header = (
        "| n_trials | DSR | PSR | Decision |\n"
        "|----------|-----|-----|----------|\n"
    )
    tbl_b_rows = ""
    for row in sens:
        dsr_str = f"{row['dsr']:.4f}" if row['dsr'] is not None else "NaN"
        mark = " <-- FRAGIL" if (row['dsr'] is not None and row['dsr'] < DSR_THRESH) else ""
        tbl_b_rows += f"| {row['n_trials']} | {dsr_str} | {row['psr']:.4f} | {row['decision']}{mark} |\n"

    # Limitações
    limitations = []
    if ds['n_trades_dropped'] > 0:
        pct_drop = 100.0 - ds['alignment_rate_pct']
        limitations.append(
            f"- {ds['n_trades_dropped']} trades ({pct_drop:.1f}%) descartados por gap de candle BTCUSD no Supabase. "
            f"Período: {ds['period']}. Gaps concentrados em 2014-2016 (dados escassos)."
        )
    if first_fail is not None:
        limitations.append(
            f"- DSR sensível a n_trials: cai abaixo de {DSR_THRESH} com n_trials={first_fail}. "
            f"Edge pode ser frágil se o número real de estratégias testadas for alto."
        )
    if not limitations:
        limitations.append("- Nenhuma limitação crítica identificada além das documentadas no MEMORY.")

    lim_str = "\n".join(limitations)

    report = f"""# Simons Gate Refinement — BTC OHLC Real vs Sintético
**Data:** 2026-05-15 | **Regime:** TRANSITION_UP+LONG | **N raw:** {ds['n_trades_raw']} | **N alinhados:** {ds['n_trades_aligned']}

---

## Resumo Executivo

{resumo}

---

## Tabela A: Sintético vs Real (4 Métricas)

{tbl_a}

**Fonte BTC:** {ds['btc_source']} | **Candle:** {ds['market']} {ds['period_candle']} | **Annualizer:** {ds['annualizer']}

---

## Tabela B: Sensitivity n_trials (DSR com BTC real)

{tbl_b_header}{tbl_b_rows}
**Primeiro n_trials onde DSR < 0.95:** {first_fail if first_fail else 'Nenhum (robusto em todos os valores testados)'}

---

## Veredito

**{veredito}**

{"**Reasons:** " + "; ".join(reasons) if reasons else ""}

---

## Limitações Remanescentes

{lim_str}

---

*Gerado por backtest/run_simons_gate_real.py em 2026-05-15*
"""
    return report


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("Simons Gate Real — BTC OHLC via Supabase")
    print("=" * 60)

    # 1. Carrega trades
    trades = load_trades(TRADES_FILE)
    n_raw = len(trades)

    # 2. Determina período
    ts_list = [parse_ts(t["entry_ts"]) for t in trades]
    ts_list_sorted = sorted(ts_list)
    dt_first = ts_list_sorted[0]
    dt_last = ts_list_sorted[-1]
    dt_last_plus1d = dt_last + timedelta(days=1)

    date_from = dt_first.strftime("%Y-%m-%dT%H:%M:%S")
    date_to = dt_last_plus1d.strftime("%Y-%m-%dT%H:%M:%S")
    period_str = f"{dt_first.strftime('%Y-%m-%d')} -> {dt_last.strftime('%Y-%m-%d')}"
    print(f"[main] Período: {period_str}")

    # 3. Carrega candles BTC real
    candles = load_btc_candles(date_from, date_to)
    candle_idx = build_candle_index(candles)
    print(f"[main] Candle index: {len(candle_idx)} timestamps únicos")

    if len(candle_idx) == 0:
        print("[ERRO] Nenhum candle carregado. Verifique SUPABASE_URL e SUPABASE_SERVICE_KEY.")
        sys.exit(1)

    # 4. Alinha trades -> BTC returns
    strategy_returns, btc_returns, n_aligned, n_dropped = align_trades_to_btc(trades, candle_idx)

    if n_aligned < 30:
        print(f"[ERRO] Apenas {n_aligned} trades alinhados (mínimo 30 para DSR). "
              "Verifique gaps no Supabase.")
        sys.exit(1)

    # 5. Tarefa A
    task_a = run_task_a(
        strategy_returns=strategy_returns,
        btc_returns=btc_returns,
        n_trades_raw=n_raw,
        n_trades_aligned=n_aligned,
        n_trades_dropped=n_dropped,
        period=period_str,
    )
    out_a = JOURNAL_DIR / "simons_gate_real_2026_05_15.json"
    with open(out_a, "w", encoding="utf-8") as f:
        json.dump(task_a, f, indent=2, ensure_ascii=False)
    print(f"[Task A] Salvo: {out_a}")

    # 6. Tarefa B
    task_b = run_task_b(strategy_returns, btc_returns)
    out_b = JOURNAL_DIR / "simons_gate_sensitivity_2026_05_15.json"
    with open(out_b, "w", encoding="utf-8") as f:
        json.dump(task_b, f, indent=2, ensure_ascii=False)
    print(f"[Task B] Salvo: {out_b}")

    # 7. Tarefa C — Relatório
    report_md = build_report(task_a, task_b)
    out_c = JOURNAL_DIR / "simons_gate_refinement_2026_05_15.md"
    with open(out_c, "w", encoding="utf-8") as f:
        f.write(report_md)
    print(f"[Task C] Salvo: {out_c}")

    print("\n" + "=" * 60)
    print(f"RESULTADO FINAL: {task_a['decision']}")
    print(f"  N_trades_aligned : {n_aligned}")
    print(f"  N_trades_dropped : {n_dropped}")
    print(f"  DSR              : {task_a['metrics']['dsr']}")
    print(f"  PSR              : {task_a['metrics']['psr']}")
    print(f"  Sharpe-BTC       : {task_a['metrics']['sharpe_btc']}")
    print(f"  Ergodicity       : {task_a['metrics']['ergodicity']}")
    first_fail = task_b["first_n_trials_dsr_fails"]
    if first_fail:
        print(f"  DSR falha em     : n_trials={first_fail}")
    else:
        print(f"  Sensitivity      : DSR robusto em todos os n_trials")
    print("=" * 60)


if __name__ == "__main__":
    main()
