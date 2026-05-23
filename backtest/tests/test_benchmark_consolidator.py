"""
test_benchmark_consolidator.py -- TDD para consolidacao dos 4 chats em summary.md

Contrato testado (modulo: benchmark_consolidator):
    load_all_benchmarks(journal_dir, expected_files) -> dict (com chaves dos 4 chats)
    generate_summary_table(benchmarks) -> str (markdown)
    aggregate_verdict(benchmarks) -> "STRONG_GO"|"GO_WITH_CAUTION"|"REVISIT"
    write_summary(benchmarks, output_path) -> path
"""
from __future__ import annotations

import json
import os
import sys

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from benchmark_consolidator import (  # noqa: E402
    aggregate_verdict,
    generate_summary_table,
    load_all_benchmarks,
    write_summary,
)


EXPECTED = [
    ("chat1", "benchmark_bear_only_results.json"),
    ("chat2", "benchmark_oos_validation_results.json"),
    ("chat3", "benchmark_monte_carlo_results.json"),
    ("chat4", "benchmark_walkforward_14y_results.json"),
]


def _fake_payload(passed: bool, label: str) -> dict:
    """Payload generico com chave de criterio que o consolidator entende."""
    return {
        "label": label,
        "go_live_criterion": {
            "rule":   f"{label} rule",
            "passed": passed,
            "explanation": f"{label} explanation",
        },
        "summary": {"robustness_score": 1.0 if passed else 0.3},
    }


# ─────────────────────────────────────────────────────────────────────────────
# 1. Carrega os 4 JSONs quando todos presentes
# ─────────────────────────────────────────────────────────────────────────────
def test_loads_all_4_jsons_when_present(tmp_path):
    for key, fname in EXPECTED:
        (tmp_path / fname).write_text(json.dumps(_fake_payload(True, key)), encoding="utf-8")
    out = load_all_benchmarks(str(tmp_path), EXPECTED)
    assert set(out.keys()) == {k for k, _ in EXPECTED}
    for v in out.values():
        assert v is not None
        assert v.get("go_live_criterion", {}).get("passed") is True


# ─────────────────────────────────────────────────────────────────────────────
# 2. Trata JSON faltante com placeholder
# ─────────────────────────────────────────────────────────────────────────────
def test_handles_missing_json_with_placeholder(tmp_path):
    for key, fname in EXPECTED[:3]:  # so 3
        (tmp_path / fname).write_text(json.dumps(_fake_payload(True, key)), encoding="utf-8")
    out = load_all_benchmarks(str(tmp_path), EXPECTED, tolerant=True)
    assert out["chat4"] is None or out["chat4"].get("pendente") is True


# ─────────────────────────────────────────────────────────────────────────────
# 3. Geracao de tabela markdown com colunas Status/Insight
# ─────────────────────────────────────────────────────────────────────────────
def test_summary_table_generation():
    benchmarks = {
        "chat1": _fake_payload(True,  "Bear Only"),
        "chat2": _fake_payload(False, "OOS"),
        "chat3": _fake_payload(True,  "Monte Carlo"),
        "chat4": _fake_payload(True,  "Walk-forward"),
    }
    md = generate_summary_table(benchmarks)
    assert md.startswith("|")
    # 4 linhas + header + separator = 6 linhas iniciando com '|'
    lines = [l for l in md.splitlines() if l.startswith("|")]
    assert len(lines) >= 6
    assert "passed" in md.lower() or "✅" in md or "ok" in md.lower()
    assert "failed" in md.lower() or "❌" in md or "fail" in md.lower()


# ─────────────────────────────────────────────────────────────────────────────
# 4-6. Veredito agregado
# ─────────────────────────────────────────────────────────────────────────────
def test_aggregate_verdict_strong_go():
    benchmarks = {k: _fake_payload(True,  k) for k in ("chat1", "chat2", "chat3", "chat4")}
    assert aggregate_verdict(benchmarks) == "STRONG_GO"


def test_aggregate_verdict_go_with_caution():
    benchmarks = {
        "chat1": _fake_payload(True,  "c1"),
        "chat2": _fake_payload(True,  "c2"),
        "chat3": _fake_payload(True,  "c3"),
        "chat4": _fake_payload(False, "c4"),
    }
    assert aggregate_verdict(benchmarks) == "GO_WITH_CAUTION"


def test_aggregate_verdict_revisit():
    benchmarks = {
        "chat1": _fake_payload(True,  "c1"),
        "chat2": _fake_payload(True,  "c2"),
        "chat3": _fake_payload(False, "c3"),
        "chat4": _fake_payload(False, "c4"),
    }
    assert aggregate_verdict(benchmarks) == "REVISIT"


# ─────────────────────────────────────────────────────────────────────────────
# 7. Geracao do arquivo MD
# ─────────────────────────────────────────────────────────────────────────────
def test_markdown_file_generation(tmp_path):
    benchmarks = {k: _fake_payload(True, k) for k in ("chat1", "chat2", "chat3", "chat4")}
    out_path = tmp_path / "summary.md"
    write_summary(benchmarks, str(out_path))
    assert out_path.exists()
    content = out_path.read_text(encoding="utf-8")
    assert "# Summary Long-History Validation" in content


# ─────────────────────────────────────────────────────────────────────────────
# 8. Summary inclui todas as secoes esperadas
# ─────────────────────────────────────────────────────────────────────────────
def test_summary_includes_all_sections(tmp_path):
    benchmarks = {k: _fake_payload(True, k) for k in ("chat1", "chat2", "chat3", "chat4")}
    out_path = tmp_path / "summary.md"
    write_summary(benchmarks, str(out_path))
    content = out_path.read_text(encoding="utf-8")
    for section in (
        "Summary Long-History Validation",
        "Tabela consolidada",
        "Veredito agregado",
        "Achados-chave",
        "Riscos",
        "Próximos passos",
        "Comparação vs baseline",
    ):
        assert section in content, f"falta secao '{section}'"
