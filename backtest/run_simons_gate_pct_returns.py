"""
run_simons_gate_pct_returns.py — Fase C: BTC Simons Gate em DAILY RETURNS (%) padrão
Bailey & López de Prado 2014, substituindo metodologia legacy R-multiples.

Mudança vs run_simons_gate_real.py:
- Legacy: strategy_returns[i] = 1.0 + 0.01 * result_r (R-multiples hourly)
- Novo:   build_equity_curve(trades, risk_pct=0.01) → daily_returns_from_equity()
          então Sharpe/PSR/DSR em returns % diários (annualizer sqrt(365))

Saídas:
  journal/simons_gate_pct_returns_btc_2026_05_16.json — métricas % returns
  journal/simons_gate_pct_returns_compare_2026_05_16.md — diff vs R-multiples
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

from equity_curve_from_trades import build_equity_curve, daily_returns_from_equity
from metrics_pct_returns import (
    sharpe_from_daily_returns,
    psr_from_daily_returns,
    dsr_from_daily_returns,
    annualizer_crypto,
)

RISK_PCT = 0.01
N_TRIALS_PRIMARY = 50
SAMPLE_VAR = 0.5
DSR_THRESH = 0.95
PSR_THRESH = 0.95
SENSITIVITY_N_TRIALS = [20, 50, 100, 200, 500]

JOURNAL_DIR = ROOT_DIR / "journal"
TRADES_FILE = JOURNAL_DIR / "transition_up_trades_dump.json"

# Baseline R-multiples (Wave 2 — run_simons_gate_real_2026_05_15)
R_MULTIPLES_BASELINE = {
    "dsr": 1.0,
    "psr": 1.0,
    "sharpe": 2.18519,
    "n_trials": 50,
    "annualizer_note": "sqrt(365*8) hourly R-mult",
    "decision": "PASS",
}


def load_trades(path: Path) -> List[Dict]:
    with open(path, "r", encoding="utf-8") as f:
        trades = json.load(f)
    print(f"[load] {len(trades)} trades carregados de {path.name}")
    return trades


def compute_metrics(returns: List[float], n_trials: int) -> Dict:
    sharpe = sharpe_from_daily_returns(returns)
    psr = psr_from_daily_returns(returns, sharpe_benchmark=0.0)
    dsr = dsr_from_daily_returns(
        returns,
        n_trials=n_trials,
        sharpe_benchmark=0.0,
        sample_variance_sharpes=SAMPLE_VAR,
    )
    return {"sharpe": sharpe, "psr": psr, "dsr": dsr}


def decide(metrics: Dict) -> tuple[str, List[str]]:
    reasons = []
    if metrics["dsr"] < DSR_THRESH:
        reasons.append(f"DSR {metrics['dsr']:.4f} < {DSR_THRESH}")
    if metrics["psr"] < PSR_THRESH:
        reasons.append(f"PSR {metrics['psr']:.4f} < {PSR_THRESH}")
    if metrics["sharpe"] <= 0:
        reasons.append(f"Sharpe {metrics['sharpe']:.4f} <= 0")
    return ("PASS" if not reasons else "FAIL", reasons)


def run_sensitivity(returns: List[float]) -> List[Dict]:
    rows = []
    for n in SENSITIVITY_N_TRIALS:
        m = compute_metrics(returns, n_trials=n)
        decision, reasons = decide(m)
        rows.append({
            "n_trials": n,
            "sharpe": round(m["sharpe"], 6),
            "psr": round(m["psr"], 6),
            "dsr": round(m["dsr"], 6),
            "decision": decision,
        })
        print(f"  n_trials={n:4d}: Sharpe={m['sharpe']:.4f} PSR={m['psr']:.4f} "
              f"DSR={m['dsr']:.4f} → {decision}")
    return rows


def build_report(out: Dict) -> str:
    m = out["metrics"]
    ds = out["dataset"]
    decision = out["decision"]
    rb = R_MULTIPLES_BASELINE
    delta_sharpe = m["sharpe"] - rb["sharpe"]

    sens_rows = ""
    for r in out["sensitivity"]:
        mark = " ← FRAGIL" if r["dsr"] < DSR_THRESH else ""
        sens_rows += (f"| {r['n_trials']} | {r['sharpe']:.4f} | {r['psr']:.4f} | "
                      f"{r['dsr']:.4f} | {r['decision']}{mark} |\n")

    if decision == "PASS":
        resumo = (f"Simons Gate em % returns DAILY: **PASS**.\n"
                  f"Sharpe={m['sharpe']:.4f} (annualizer sqrt(365)), "
                  f"PSR={m['psr']:.4f}, DSR={m['dsr']:.4f}.\n"
                  f"N={ds['n_returns']} daily returns de {ds['n_trades']} trades "
                  f"({ds['n_days']} dias com atividade).")
        veredito = ("GO — edge validado em metodologia padrão Bailey-López de Prado "
                    "(% returns daily). Comparável cross-asset com qualquer benchmark.")
    else:
        resumo = (f"Simons Gate em % returns DAILY: **FAIL** — {'; '.join(out['reasons'])}.\n"
                  f"Sharpe={m['sharpe']:.4f}, PSR={m['psr']:.4f}, DSR={m['dsr']:.4f}.")
        veredito = ("HOLD — degradação ao mudar de R-multiples para % returns. "
                    "Investigar concentração de PnL ou outliers diários.")

    report = f"""# Simons Gate — % Returns Daily (Fase C — Backtest Redo)
**Data:** 2026-05-16 | **Regime:** TRANSITION_UP+LONG | **Metodologia:** Bailey-López de Prado 2014

---

## Resumo Executivo

{resumo}

---

## Métricas (% returns DAILY, padrão cripto)

| Métrica | Valor | Threshold | Status |
|---------|-------|-----------|--------|
| Sharpe (annualized) | {m['sharpe']:.4f} | > 0 | {'✅' if m['sharpe'] > 0 else '❌'} |
| PSR | {m['psr']:.4f} | ≥ {PSR_THRESH} | {'✅' if m['psr'] >= PSR_THRESH else '❌'} |
| DSR (n_trials={N_TRIALS_PRIMARY}) | {m['dsr']:.4f} | ≥ {DSR_THRESH} | {'✅' if m['dsr'] >= DSR_THRESH else '❌'} |

**Annualizer:** sqrt(365) = 19.105 (cripto 24/7, daily returns)
**Risk per trade:** {RISK_PCT*100:.1f}% do capital

---

## Comparação: % Returns vs R-multiples (Legacy)

| Métrica | R-multiples (Wave 2) | % Returns Daily (Fase C) | Δ |
|---------|----------------------|-------------------------|----|
| Sharpe | {rb['sharpe']:.4f} | {m['sharpe']:.4f} | {'+' if delta_sharpe >= 0 else ''}{delta_sharpe:.4f} |
| PSR | {rb['psr']:.4f} | {m['psr']:.4f} | {'+' if m['psr'] - rb['psr'] >= 0 else ''}{m['psr'] - rb['psr']:.4f} |
| DSR | {rb['dsr']:.4f} | {m['dsr']:.4f} | {'+' if m['dsr'] - rb['dsr'] >= 0 else ''}{m['dsr'] - rb['dsr']:.4f} |
| Decision | {rb['decision']} | {decision} | {'≡' if decision == rb['decision'] else '⚠️ DIVERGÊNCIA'} |

**Nota:** Sharpe não é diretamente comparável (annualizers diferentes), mas decision binária deve ser consistente.

---

## Sensitivity n_trials

| n_trials | Sharpe | PSR | DSR | Decision |
|----------|--------|-----|-----|----------|
{sens_rows}

---

## Veredito

**{veredito}**

{"**Reasons:** " + "; ".join(out['reasons']) if out['reasons'] else ""}

---

## Dataset

- Trades raw: {ds['n_trades']}
- Daily returns: {ds['n_returns']}
- Dias com atividade: {ds['n_days']}
- Período: {ds['period']}
- Risk per trade: {RISK_PCT*100:.1f}%

---

*Gerado por backtest/run_simons_gate_pct_returns.py em 2026-05-16*
"""
    return report


def main():
    print("=" * 60)
    print("Simons Gate — % Returns DAILY (Fase C)")
    print("=" * 60)

    trades = load_trades(TRADES_FILE)
    n_trades = len(trades)

    # Build equity curve + daily returns
    print(f"\n[build] equity curve com risk_pct={RISK_PCT}")
    equity = build_equity_curve(trades, risk_pct=RISK_PCT)
    n_days = len(equity)
    print(f"[build] {n_days} dias com atividade")

    returns = daily_returns_from_equity(equity)
    n_returns = len(returns)
    print(f"[build] {n_returns} daily returns (N-1)")

    if n_returns < 30:
        print(f"[ERRO] Apenas {n_returns} daily returns. Mínimo 30 para DSR confiável.")
        sys.exit(1)

    dates = sorted(equity.keys())
    period_str = f"{dates[0]} → {dates[-1]}"
    final_equity = equity[dates[-1]]
    print(f"[build] Período: {period_str} | Equity final: {final_equity:.4f}x")

    # Primary metrics
    print(f"\n[primary] n_trials={N_TRIALS_PRIMARY}")
    primary = compute_metrics(returns, n_trials=N_TRIALS_PRIMARY)
    decision, reasons = decide(primary)
    print(f"  Sharpe={primary['sharpe']:.4f} | PSR={primary['psr']:.4f} | "
          f"DSR={primary['dsr']:.4f} → {decision}")

    # Sensitivity
    print(f"\n[sensitivity] n_trials sweep")
    sensitivity = run_sensitivity(returns)

    # Assemble output
    out = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "methodology": "pct_returns_daily_bailey_lopez_de_prado_2014",
        "dataset": {
            "n_trades": n_trades,
            "n_days": n_days,
            "n_returns": n_returns,
            "period": period_str,
            "final_equity": round(final_equity, 6),
            "risk_pct": RISK_PCT,
            "annualizer": f"sqrt(365)={round(annualizer_crypto(), 4)}",
        },
        "params": {
            "n_trials": N_TRIALS_PRIMARY,
            "sample_variance_sharpes": SAMPLE_VAR,
            "dsr_threshold": DSR_THRESH,
            "psr_threshold": PSR_THRESH,
        },
        "metrics": {
            "sharpe": round(primary["sharpe"], 6),
            "psr": round(primary["psr"], 6),
            "dsr": round(primary["dsr"], 6),
        },
        "decision": decision,
        "reasons": reasons,
        "sensitivity": sensitivity,
        "r_multiples_baseline": R_MULTIPLES_BASELINE,
    }

    out_json = JOURNAL_DIR / "simons_gate_pct_returns_btc_2026_05_16.json"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_json.name}")

    report = build_report(out)
    out_md = JOURNAL_DIR / "simons_gate_pct_returns_compare_2026_05_16.md"
    with open(out_md, "w", encoding="utf-8") as f:
        f.write(report)
    print(f"[save] {out_md.name}")

    print("\n" + "=" * 60)
    print(f"DECISION: {decision}")
    print(f"  Sharpe  : {primary['sharpe']:.4f}")
    print(f"  PSR     : {primary['psr']:.4f}")
    print(f"  DSR     : {primary['dsr']:.4f}")
    print(f"  N_days  : {n_days}")
    print(f"  Final eq: {final_equity:.4f}x")
    print("=" * 60)


if __name__ == "__main__":
    main()
