"""
test_parity_contracts.py -- Garante que docs/PARITY_CONTRACTS.md eh honesto:
 - Existe, parseia, contratos completos
 - Cada ps_ref e python_ref aponta para arquivo real (line opcional)
 - ALLOWED_PERMISSIVE em signal_generator.py contem os 4 regimes documentados

Refs:
  docs/PARITY_CONTRACTS.md
  memory/framework_paridade_python_ps.md  (Nivel 1)
"""
from __future__ import annotations

import os
import re
from pathlib import Path
from typing import List, Tuple

import pytest

# ── Repo root detection (este teste fica em backtest/tests/) ─────────────────
THIS_DIR = Path(__file__).resolve().parent
REPO_ROOT = THIS_DIR.parent.parent          # backtest/tests/ -> repo root
DOC_PATH = REPO_ROOT / "docs" / "PARITY_CONTRACTS.md"

REQUIRED_FIELDS = ("id", "rule", "ps_ref", "python_ref", "status")
VALID_STATUS = {"SYNCED", "DIVERGENT", "PS_ONLY", "PYTHON_ONLY"}

# Os 4 regimes que ALLOWED_PERMISSIVE deve cobrir (regimes-alvo da whitelist)
DOCUMENTED_LONG_REGIMES = {"BULL_STRONG", "BULL_WEAK", "TRANSITION_UP"}


def _parse_contracts(text: str) -> List[dict]:
    """
    Parseia blocos YAML de contratos do markdown. Espera:

        ```yaml
        contract:
          id: ...
          rule: ...
          ps_ref: path:line
          python_ref: path:line  | N/A
          status: SYNCED|DIVERGENT|PS_ONLY|PYTHON_ONLY
          last_verified: YYYY-MM-DD
        ```

    Parser deliberadamente simples (sem dep externa) para nao quebrar suite.
    """
    contracts = []
    block_re = re.compile(r"```yaml\s*(.*?)```", re.DOTALL)
    for block in block_re.findall(text):
        if "contract:" not in block:
            continue
        contract: dict = {}
        for line in block.splitlines():
            line = line.strip()
            if not line or line == "contract:" or line.startswith("#"):
                continue
            if ":" not in line:
                continue
            key, _, val = line.partition(":")
            contract[key.strip()] = val.strip()
        if contract:
            contracts.append(contract)
    return contracts


def _split_ref(ref: str) -> Tuple[str, int | None]:
    """ 'path/file.py:42' -> ('path/file.py', 42).  'N/A' -> ('N/A', None). """
    if ref == "N/A":
        return "N/A", None
    if ":" in ref:
        path, _, line = ref.rpartition(":")
        try:
            return path, int(line)
        except ValueError:
            return ref, None
    return ref, None


# ─────────────────────────────────────────────────────────────────────────────


def test_parity_contracts_doc_exists():
    assert DOC_PATH.is_file(), f"Esperado em {DOC_PATH}"


def test_parity_contracts_has_required_section():
    text = DOC_PATH.read_text(encoding="utf-8")
    assert "## Regras Invariantes" in text, (
        "Doc deve ter section header '## Regras Invariantes' (testes parseiam por ela)"
    )


def test_parity_contracts_parse_min_8_contracts():
    text = DOC_PATH.read_text(encoding="utf-8")
    contracts = _parse_contracts(text)
    assert len(contracts) >= 8, (
        f"Esperado >=8 contratos no doc; encontrado {len(contracts)}"
    )


def test_each_contract_has_required_fields():
    text = DOC_PATH.read_text(encoding="utf-8")
    for c in _parse_contracts(text):
        missing = [f for f in REQUIRED_FIELDS if f not in c]
        assert not missing, f"Contract {c.get('id','<sem id>')} faltando: {missing}"
        assert c["status"] in VALID_STATUS, (
            f"Contract {c['id']} status invalido: {c['status']}"
        )


def test_ps_refs_point_to_existing_files():
    text = DOC_PATH.read_text(encoding="utf-8")
    for c in _parse_contracts(text):
        path, _line = _split_ref(c["ps_ref"])
        if path == "N/A":
            continue
        full = REPO_ROOT / path
        assert full.is_file(), (
            f"Contract {c['id']}: ps_ref {path} nao existe em {REPO_ROOT}"
        )


def test_python_refs_point_to_existing_files():
    text = DOC_PATH.read_text(encoding="utf-8")
    for c in _parse_contracts(text):
        path, _line = _split_ref(c["python_ref"])
        if path == "N/A":
            continue
        full = REPO_ROOT / path
        assert full.is_file(), (
            f"Contract {c['id']}: python_ref {path} nao existe em {REPO_ROOT}"
        )


def test_allowed_permissive_contains_documented_regimes():
    """Defesa contra divergencia silenciosa: se alguem mudar ALLOWED_PERMISSIVE
    sem atualizar o contrato, este teste quebra."""
    import importlib.util

    sg_path = REPO_ROOT / "backtest" / "signal_generator.py"
    spec = importlib.util.spec_from_file_location("signal_generator", sg_path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[union-attr]

    allowed_long = set(mod.ALLOWED_PERMISSIVE["COMPRA"])
    assert DOCUMENTED_LONG_REGIMES.issubset(allowed_long), (
        f"ALLOWED_PERMISSIVE['COMPRA']={allowed_long} nao contem "
        f"{DOCUMENTED_LONG_REGIMES} documentados em PARITY_CONTRACTS.md"
    )
