"""
benchmark_consolidator.py -- Consolida os 4 benchmarks dos chats em summary.md

Le os JSONs em journal/, monta tabela markdown, calcula veredito agregado e
gera relatorio em journal/benchmark_long_history_summary.md.

CLI:
    python backtest/benchmark_consolidator.py
    python backtest/benchmark_consolidator.py --wait-minutes 30
    python backtest/benchmark_consolidator.py --journal-dir <dir> --output <path>
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from typing import Dict, Iterable, List, Optional, Tuple


# ─────────────────────────────────────────────────────────────────────────────
# Configuracao default dos 4 chats
# ─────────────────────────────────────────────────────────────────────────────
DEFAULT_EXPECTED: List[Tuple[str, str]] = [
    ("chat1", "benchmark_short_bear_results.json"),
    ("chat2", "benchmark_long_14y_results.json"),
    ("chat3", "benchmark_monte_carlo_results.json"),
    ("chat4", "benchmark_walkforward_14y_results.json"),
]

# Labels humanos (titulos das linhas da tabela)
CHAT_LABELS: Dict[str, str] = {
    "chat1": "Chat 1 — Short / Bear stress",
    "chat2": "Chat 2 — Long 14y OOS",
    "chat3": "Chat 3 — Monte Carlo DD",
    "chat4": "Chat 4 — Walk-forward 14y",
}


# ─────────────────────────────────────────────────────────────────────────────
# Load
# ─────────────────────────────────────────────────────────────────────────────

def load_all_benchmarks(journal_dir: str,
                        expected_files: Iterable[Tuple[str, str]] = DEFAULT_EXPECTED,
                        tolerant: bool = True) -> Dict[str, Optional[Dict]]:
    """
    Le os JSONs esperados. Em modo tolerant, faltantes viram {pendente: True} em vez de None
    para serem renderizados na tabela como placeholders.
    """
    out: Dict[str, Optional[Dict]] = {}
    for key, fname in expected_files:
        path = os.path.join(journal_dir, fname)
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    out[key] = json.load(f)
            except Exception as e:
                if tolerant:
                    out[key] = {"pendente": True, "erro": str(e), "file": fname}
                else:
                    raise
        else:
            if tolerant:
                out[key] = {"pendente": True, "file": fname}
            else:
                out[key] = None
    return out


def _passed(payload: Optional[Dict]) -> Optional[bool]:
    """Extrai 'passed' de qualquer um dos containers comuns; None se pendente."""
    if not payload or payload.get("pendente"):
        return None
    # Tentar varios caminhos: go_live_criterion.passed, go_criterion.passed, top-level.passed
    for path in (
        ("go_live_criterion", "passed"),
        ("go_criterion",      "passed"),
        ("criterion",         "passed"),
    ):
        node: object = payload
        ok = True
        for k in path:
            if isinstance(node, dict) and k in node:
                node = node[k]
            else:
                ok = False; break
        if ok and isinstance(node, bool):
            return node
    if isinstance(payload.get("passed"), bool):
        return payload["passed"]
    return None


def _insight(payload: Optional[Dict]) -> str:
    if not payload:
        return "—"
    if payload.get("pendente"):
        return "pendente (arquivo ausente)"
    # Tentar campos com texto pronto
    for path in (
        ("go_live_criterion", "explanation"),
        ("go_criterion",      "explanation"),
        ("implication",),
    ):
        node: object = payload
        ok = True
        for k in path:
            if isinstance(node, dict) and k in node:
                node = node[k]
            else:
                ok = False; break
        if ok and isinstance(node, str) and node.strip():
            return node[:200]
    # Fallback: monta insight a partir do criterio + numeros
    crit = payload.get("go_live_criterion") or payload.get("go_criterion") or {}
    if isinstance(crit, dict) and crit:
        rule    = crit.get("rule", "")
        details = ", ".join(
            f"{k}={v}" for k, v in crit.items()
            if k not in ("rule", "passed", "explanation") and not isinstance(v, (dict, list))
        )
        if rule or details:
            return (f"{rule} | {details}" if rule and details else rule or details)[:200]
    rob = payload.get("summary", {})
    if isinstance(rob, dict) and "robustness_score" in rob:
        return f"robustness_score={rob['robustness_score']}"
    return "(sem insight extraido)"


# ─────────────────────────────────────────────────────────────────────────────
# Tabela markdown
# ─────────────────────────────────────────────────────────────────────────────

def generate_summary_table(benchmarks: Dict[str, Optional[Dict]]) -> str:
    lines = [
        "| Chat | Benchmark | Status | Insight |",
        "|---|---|---|---|",
    ]
    for key in benchmarks.keys():
        label  = CHAT_LABELS.get(key, key)
        ok     = _passed(benchmarks[key])
        status = (
            "✅ passed" if ok is True else
            "❌ failed" if ok is False else
            "⏳ pendente"
        )
        insight = _insight(benchmarks[key]).replace("\n", " ")
        lines.append(f"| {key} | {label} | {status} | {insight} |")
    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# Veredito agregado
# ─────────────────────────────────────────────────────────────────────────────

def aggregate_verdict(benchmarks: Dict[str, Optional[Dict]]) -> str:
    """
    STRONG_GO        : 4/4 passed
    GO_WITH_CAUTION  : exatamente 3/4 passed
    REVISIT          : <= 2/4 passed (inclui pendentes)
    """
    total  = len(benchmarks) or 1
    passed = sum(1 for v in benchmarks.values() if _passed(v) is True)
    if passed == total:
        return "STRONG_GO"
    if passed == total - 1:
        return "GO_WITH_CAUTION"
    return "REVISIT"


# ─────────────────────────────────────────────────────────────────────────────
# Achados / Riscos / Proximos passos
# ─────────────────────────────────────────────────────────────────────────────

def _findings_for(key: str, payload: Optional[Dict]) -> str:
    if not payload or payload.get("pendente"):
        return "*(arquivo ainda nao gerado)*"

    if key == "chat3":  # Monte Carlo
        try:
            s = payload.get("summary", {})
            g = payload.get("go_live_criterion", {})
            return (
                f"`max_p95={g.get('max_p95_across_runs')}R` em {payload.get('n_simulations'):,} sims; "
                f"`max_p99={s.get('max_p99_dd_R')}R`; robustness={s.get('robustness_score')}."
            )
        except Exception:
            return "Monte Carlo: erro ao extrair sumario."

    if key == "chat4":  # Walk-forward
        try:
            c = payload.get("consistency", {})
            w = payload.get("worst_window", {})
            return (
                f"{payload.get('n_windows')} janelas; positive%={c.get('positive_windows_pct')}; "
                f"streak max negativo={c.get('max_losing_streak_windows')}; "
                f"ergodicity={c.get('ergodicity_score')}; pior janela: `{w.get('period')}` exp={w.get('exp')}."
            )
        except Exception:
            return "Walkforward: erro ao extrair sumario."

    # Generico chat1/chat2
    explan = _insight(payload)
    return explan


def _risks(benchmarks: Dict[str, Optional[Dict]]) -> List[str]:
    risks: List[str] = []
    for key, v in benchmarks.items():
        if not v or v.get("pendente"):
            risks.append(f"Benchmark **{CHAT_LABELS.get(key, key)}** ainda nao concluido.")
            continue
        if _passed(v) is False:
            risks.append(f"**{CHAT_LABELS.get(key, key)}** falhou o criterio go-live.")
    # Risco generico que vale sempre lembrar:
    risks.append("Resultados sinteticos demo no Chat 3/4 quando os inputs reais (baseline_v2) nao estao presentes.")
    return risks


def _next_steps(verdict: str, benchmarks: Dict[str, Optional[Dict]]) -> List[str]:
    steps: List[str] = []
    if verdict == "STRONG_GO":
        steps += [
            "Liberar paper trade em escala reduzida (1-2% capital) por 2 semanas antes de live.",
            "Configurar Margem Isolada na UI CoinEx (pre-requisito manual).",
            "Habilitar `scan_master.ps1` em LIVE com aprovacao Telegram obrigatoria.",
        ]
    elif verdict == "GO_WITH_CAUTION":
        steps += [
            "Identificar qual benchmark falhou e ajustar somente o ponto fraco.",
            "Re-rodar APENAS o benchmark afetado antes de tentar live.",
            "Manter paper trade por 4 semanas em vez de 2.",
        ]
    else:
        steps += [
            "Nao liberar live. Revisar pesos do orquestrador e thresholds.",
            "Re-rodar os 4 benchmarks apos cada ajuste material.",
            "Considerar reduzir universe (so BTC/ETH) ate consistencia voltar.",
        ]
    # Append faltantes
    for key, v in benchmarks.items():
        if not v or v.get("pendente"):
            steps.append(f"Aguardar/gerar `{CHAT_LABELS.get(key, key)}` JSON.")
    return steps


# ─────────────────────────────────────────────────────────────────────────────
# Comparacao vs baseline original (5 benchmarks 2026-05-14)
# ─────────────────────────────────────────────────────────────────────────────

BASELINE_NOTE = (
    "Baseline original (2026-05-14): 5 benchmarks puramente IN-SAMPLE com expectativa "
    "+1.2R medio, win rate 55%. Esta validacao long-history adiciona OOS + stress + MC + "
    "walk-forward e endurece o criterio de go-live."
)


# ─────────────────────────────────────────────────────────────────────────────
# write_summary
# ─────────────────────────────────────────────────────────────────────────────

def write_summary(benchmarks: Dict[str, Optional[Dict]], output_path: str) -> str:
    verdict = aggregate_verdict(benchmarks)
    table   = generate_summary_table(benchmarks)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    body: List[str] = []
    body.append("# Summary Long-History Validation")
    body.append("")
    body.append(f"> Gerado: `{ts}` — consolidacao dos 4 chats de benchmarking V2.")
    body.append("")

    body.append("## Tabela consolidada")
    body.append("")
    body.append(table)
    body.append("")

    body.append("## Veredito agregado")
    body.append("")
    body.append(f"**{verdict}**")
    body.append("")
    if verdict == "STRONG_GO":
        body.append("Todos os 4 benchmarks passaram. Sistema validado para proximo estagio (paper -> live).")
    elif verdict == "GO_WITH_CAUTION":
        body.append("3 de 4 benchmarks passaram. Avancar com cautela e correcao do ponto fraco.")
    else:
        body.append("Mais de 1 benchmark falhou. Revisitar sistema antes de qualquer escalada.")
    body.append("")

    body.append("## Achados-chave por benchmark")
    body.append("")
    for key, payload in benchmarks.items():
        body.append(f"- **{CHAT_LABELS.get(key, key)}:** {_findings_for(key, payload)}")
    body.append("")

    body.append("## Riscos identificados")
    body.append("")
    for r in _risks(benchmarks):
        body.append(f"- {r}")
    body.append("")

    body.append("## Próximos passos sugeridos")
    body.append("")
    for s in _next_steps(verdict, benchmarks):
        body.append(f"- {s}")
    body.append("")

    body.append("## Comparação vs baseline original (5 benchmarks 2026-05-14)")
    body.append("")
    body.append(BASELINE_NOTE)
    body.append("")

    text = "\n".join(body)
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(text)
    return output_path


# ─────────────────────────────────────────────────────────────────────────────
# CLI com retry loop ate timeout
# ─────────────────────────────────────────────────────────────────────────────

def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Consolidate 4 chats benchmark JSONs into summary.md")
    parser.add_argument("--journal-dir",  default="journal")
    parser.add_argument("--output",       default=os.path.join("journal", "benchmark_long_history_summary.md"))
    parser.add_argument("--wait-minutes", type=int, default=0,
                        help="Espera ate todos os 4 JSONs aparecerem (poll 30s). 0 = sem espera.")
    args = parser.parse_args(argv)

    deadline = time.time() + args.wait_minutes * 60 if args.wait_minutes > 0 else None

    while True:
        benchmarks = load_all_benchmarks(args.journal_dir, DEFAULT_EXPECTED, tolerant=True)
        missing = [k for k, v in benchmarks.items() if not v or v.get("pendente")]
        if not missing or deadline is None or time.time() > deadline:
            break
        sys.stderr.write(f"[Consolidator] Aguardando {missing} ... {int(deadline - time.time())}s restantes\n")
        time.sleep(30)

    path = write_summary(benchmarks, args.output)
    verdict = aggregate_verdict(benchmarks)
    sys.stdout.write(f"[Consolidator] verdict={verdict}. -> {path}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
