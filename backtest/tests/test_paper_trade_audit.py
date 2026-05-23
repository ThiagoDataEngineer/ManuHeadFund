"""
test_paper_trade_audit.py -- TDD para auditor de logs paper trade DryRun.

Sintaxe real do log (bbnclvt9g):
  [HH:MM:SS] [TRADE] Orchestrator MARKET: DECISION score= sinal=
  [HH:MM:SS] [INFO] Ciclo concluido em Ns | gems=N candidates=N top=N
  MASTER CYCLE  HH:MM dd/mm  WINDOW  momento=NN/100
  === ORCHESTRATOR V6 (Esquadrao) === MARKET HH:MM
    [V6] Decisao: ABORTAR | Tempo: Ns
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from paper_trade_audit import (  # noqa: E402
    aggregate_by_regime_direction,
    count_transition_up_mon_long,
    find_data_gaps,
    filter_signals_by_regime_direction,
    identify_abort_reasons,
    parse_paper_trade_log,
    parse_trade_line,
)


# ── Fixtures sinteticas ─────────────────────────────────────────────────────

SYNTHETIC_LOG = """\
﻿=====================================================
  SCAN MASTER -- Loop Mestre
=====================================================

-------------------------------------------------
  MASTER CYCLE  03:29 14/05  SLOW  momento=22/100
-------------------------------------------------

[GEM] Iniciando GemScan (TopN=5)...
[03:29:20] [GEM] GemScan: nenhum gem encontrado

=== ORCHESTRATOR V6 (Esquadrao) === KITEUSDT 03:30
  [V6] Decisao: ABORTAR | Tempo: 7.7s
[03:30:20] [TRADE] Orchestrator KITEUSDT: ABORTAR score= sinal=

=== ORCHESTRATOR V6 (Esquadrao) === BTCUSDT 03:31
  [V6] Decisao: EXECUTAR | Tempo: 4.2s | regime=UP_MON direction=LONG
[03:31:05] [TRADE] Orchestrator BTCUSDT: EXECUTAR score=82 sinal=COMPRA regime=UP_MON direction=LONG

[03:31:05] [INFO] Ciclo concluido em 75s | gems=0 candidates=18 top=3

-------------------------------------------------
  MASTER CYCLE  05:30 14/05  NEUTRAL  momento=42/100
-------------------------------------------------

=== ORCHESTRATOR V6 (Esquadrao) === ETHUSDT 05:31
  [V6] Decisao: ABORTAR | Tempo: 3s | razao=score_baixo
[05:31:32] [TRADE] Orchestrator ETHUSDT: ABORTAR score=58 sinal= regime=NEUTRAL direction=
"""


@pytest.fixture
def synthetic_log_path():
    with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False, encoding="utf-8") as f:
        f.write(SYNTHETIC_LOG)
        path = f.name
    yield path
    os.unlink(path)


# ── 1. parse_trade_line ────────────────────────────────────────────────────

def test_parse_trade_line_basic_abortar():
    s = parse_trade_line("[03:30:20] [TRADE] Orchestrator KITEUSDT: ABORTAR score= sinal=")
    assert s is not None
    assert s["timestamp"] == "03:30:20"
    assert s["market"] == "KITEUSDT"
    assert s["decision"] == "ABORTAR"
    assert s["score"] is None
    assert s["sinal"] is None


def test_parse_trade_line_with_score_sinal():
    s = parse_trade_line("[03:31:05] [TRADE] Orchestrator BTCUSDT: EXECUTAR score=82 sinal=COMPRA")
    assert s["decision"] == "EXECUTAR"
    assert s["score"] == 82
    assert s["sinal"] == "COMPRA"


def test_parse_trade_line_with_regime_direction():
    s = parse_trade_line(
        "[03:31:05] [TRADE] Orchestrator BTCUSDT: EXECUTAR score=82 sinal=COMPRA regime=UP_MON direction=LONG"
    )
    assert s["regime"] == "UP_MON"
    assert s["direction"] == "LONG"


def test_parse_trade_line_non_trade_returns_none():
    s = parse_trade_line("[03:29:20] [GEM] GemScan: nenhum gem encontrado")
    assert s is None


def test_parse_trade_line_empty():
    assert parse_trade_line("") is None
    assert parse_trade_line("   ") is None


# ── 2. parse_paper_trade_log ───────────────────────────────────────────────

def test_parse_paper_trade_log_returns_list(synthetic_log_path):
    signals = parse_paper_trade_log(synthetic_log_path)
    assert isinstance(signals, list)
    # 3 TRADE entries no fixture (KITEUSDT ABORTAR, BTCUSDT EXECUTAR, ETHUSDT ABORTAR)
    assert len(signals) == 3


def test_parse_paper_trade_log_associates_master_cycle_context(synthetic_log_path):
    signals = parse_paper_trade_log(synthetic_log_path)
    # Os primeiros 2 sinais sao do ciclo SLOW, ultimo do NEUTRAL
    assert signals[0]["cycle_window"] == "SLOW"
    assert signals[2]["cycle_window"] == "NEUTRAL"


def test_parse_paper_trade_log_handles_missing_file():
    signals = parse_paper_trade_log("/path/que/nao/existe.log")
    assert signals == []


def test_parse_paper_trade_log_empty_file(tmp_path):
    p = tmp_path / "empty.log"
    p.write_text("", encoding="utf-8")
    assert parse_paper_trade_log(str(p)) == []


def test_parse_paper_trade_log_corrupted_lines_skipped(tmp_path):
    p = tmp_path / "corrupted.log"
    p.write_text(
        "GARBAGE LINE\n"
        "[03:30:20] [TRADE] Orchestrator KITEUSDT: ABORTAR score= sinal=\n"
        "MORE GARBAGE\n",
        encoding="utf-8",
    )
    signals = parse_paper_trade_log(str(p))
    assert len(signals) == 1


# ── 3. filter_signals_by_regime_direction ─────────────────────────────────

def test_filter_signals_matches_regime_and_direction():
    sigs = [
        {"market": "BTC", "regime": "UP_MON", "direction": "LONG"},
        {"market": "ETH", "regime": "NEUTRAL", "direction": "LONG"},
        {"market": "SOL", "regime": "UP_MON", "direction": "SHORT"},
    ]
    out = filter_signals_by_regime_direction(sigs, regime="UP_MON", direction="LONG")
    assert len(out) == 1
    assert out[0]["market"] == "BTC"


def test_filter_signals_with_missing_regime_excludes():
    sigs = [{"market": "X", "decision": "ABORTAR"}]  # sem regime
    assert filter_signals_by_regime_direction(sigs, "UP_MON", "LONG") == []


# ── 4. count_transition_up_mon_long ───────────────────────────────────────

def test_count_transition_up_mon_long_basic():
    sigs = [
        {"date": "2023-05-01", "regime": "UP_MON", "direction": "LONG", "decision": "EXECUTAR"},
        {"date": "2024-01-01", "regime": "UP_MON", "direction": "LONG", "decision": "ABORTAR"},
        {"date": "2024-02-01", "regime": "UP_WK", "direction": "LONG", "decision": "EXECUTAR"},
    ]
    result = count_transition_up_mon_long(sigs, since_date="2023-01-01")
    assert result["count_total"] == 2
    assert result["count_executed"] == 1
    assert "gap_to_30" in result
    assert result["gap_to_30"] == 28  # 30 - 2


def test_count_transition_up_mon_long_excludes_before_date():
    sigs = [
        {"date": "2022-12-31", "regime": "UP_MON", "direction": "LONG", "decision": "EXECUTAR"},
        {"date": "2023-01-01", "regime": "UP_MON", "direction": "LONG", "decision": "EXECUTAR"},
    ]
    r = count_transition_up_mon_long(sigs, since_date="2023-01-01")
    assert r["count_total"] == 1


# ── 5. aggregate_by_regime_direction ──────────────────────────────────────

def test_aggregate_by_regime_direction():
    sigs = [
        {"regime": "UP_MON", "direction": "LONG", "decision": "EXECUTAR"},
        {"regime": "UP_MON", "direction": "LONG", "decision": "ABORTAR"},
        {"regime": "NEUTRAL", "direction": "LONG", "decision": "ABORTAR"},
    ]
    agg = aggregate_by_regime_direction(sigs)
    assert agg["UP_MON|LONG"]["total"] == 2
    assert agg["UP_MON|LONG"]["executed"] == 1
    assert agg["NEUTRAL|LONG"]["total"] == 1


def test_aggregate_handles_unknown_regime():
    sigs = [{"market": "X"}]  # sem regime/direction
    agg = aggregate_by_regime_direction(sigs)
    assert "UNKNOWN|UNKNOWN" in agg


# ── 6. identify_abort_reasons ────────────────────────────────────────────

def test_identify_abort_reasons_counts_top_n():
    sigs = [
        {"decision": "ABORTAR", "razao": "score_baixo"},
        {"decision": "ABORTAR", "razao": "score_baixo"},
        {"decision": "ABORTAR", "razao": "macro_contra"},
        {"decision": "EXECUTAR", "razao": "ok"},
    ]
    reasons = identify_abort_reasons(sigs, top_n=5)
    assert reasons[0]["reason"] == "score_baixo"
    assert reasons[0]["count"] == 2
    assert any(r["reason"] == "macro_contra" for r in reasons)


def test_identify_abort_reasons_handles_missing_razao():
    sigs = [{"decision": "ABORTAR"}, {"decision": "ABORTAR"}]
    reasons = identify_abort_reasons(sigs, top_n=5)
    assert reasons[0]["reason"] == "unspecified"
    assert reasons[0]["count"] == 2


# ── 7. find_data_gaps ────────────────────────────────────────────────────

def test_find_data_gaps_reports_absent_regimes():
    sigs = [
        {"regime": "UP_MON", "direction": "LONG"},
        {"regime": "NEUTRAL", "direction": "LONG"},
    ]
    expected = ["UP_MON", "UP_WK", "NEUTRAL", "DOWN_WK", "DOWN_MON"]
    gaps = find_data_gaps(sigs, expected)
    missing_regimes = [g["regime"] for g in gaps]
    assert "UP_WK" in missing_regimes
    assert "DOWN_MON" in missing_regimes
    assert "UP_MON" not in missing_regimes


# ── Edge: timezone awareness (UTC vs BRT) ────────────────────────────────

def test_parse_trade_line_records_timestamp_as_string():
    # No interpretation — apenas string que pode ser convertida depois
    s = parse_trade_line("[03:30:20] [TRADE] Orchestrator KITEUSDT: ABORTAR score= sinal=")
    assert s["timestamp"] == "03:30:20"
    # Sem tzinfo embutido -- consumidor decide
    assert "timezone" not in s or s["timezone"] is None


# ── 8. Novo formato lib_trade_logger.ps1 ─────────────────────────────────
# Formato: [HH:MM:SS] [TRADE] MARKET: DECISION regime=X direction=Y
#          score=Z tier=T consensus=C razao=...

def test_parse_trade_line_new_format_full_fields():
    """Novo formato sem 'Orchestrator', com tier+consensus."""
    line = (
        "[03:31:05] [TRADE] BTCUSDT: EXECUTAR "
        "regime=UP_MON direction=LONG score=82 tier=A consensus=FORTE_3 razao=score_alto"
    )
    s = parse_trade_line(line)
    assert s is not None
    assert s["market"] == "BTCUSDT"
    assert s["decision"] == "EXECUTAR"
    assert s["regime"] == "UP_MON"
    assert s["direction"] == "LONG"
    assert s["score"] == 82
    assert s["tier"] == "A"
    assert s["consensus"] == "FORTE_3"
    assert s["razao"] == "score_alto"


def test_parse_trade_line_new_format_dash_means_none():
    """Campos com '-' (do formatador) viram None."""
    line = (
        "[03:30:20] [TRADE] KITEUSDT: ABORTAR "
        "regime=- direction=- score=- tier=D consensus=CAOS razao=-"
    )
    s = parse_trade_line(line)
    assert s["regime"] is None
    assert s["direction"] is None
    assert s["score"] is None
    assert s["razao"] is None
    assert s["tier"] == "D"
    assert s["consensus"] == "CAOS"


def test_parse_trade_line_new_format_razao_with_spaces():
    """razao=... eh tail-livre: pode conter espacos."""
    line = (
        "[10:00:00] [TRADE] ETHUSDT: ABORTAR "
        "regime=NEUTRAL direction=LONG score=42 tier=C consensus=MEDIO_1 "
        "razao=score baixo macro contra"
    )
    s = parse_trade_line(line)
    assert s["razao"] == "score baixo macro contra"
    assert s["score"] == 42
    assert s["consensus"] == "MEDIO_1"


def test_parse_trade_line_legacy_format_still_works():
    """Back-compat: formato antigo (com 'Orchestrator', score=/sinal=) preservado."""
    line = "[05:31:32] [TRADE] Orchestrator ETHUSDT: ABORTAR score=58 sinal= regime=NEUTRAL direction="
    s = parse_trade_line(line)
    assert s["market"] == "ETHUSDT"
    assert s["decision"] == "ABORTAR"
    assert s["score"] == 58
    assert s["sinal"] is None
    assert s["regime"] == "NEUTRAL"
    assert s["direction"] is None
    # Campos novos ausentes => None
    assert s.get("tier") is None
    assert s.get("consensus") is None


def test_parse_paper_trade_log_mixed_old_and_new_format(tmp_path):
    """Log com linhas legacy + novas no mesmo arquivo (durante transicao)."""
    log = (
        "MASTER CYCLE  10:00 14/05  PRIME  momento=85/100\n"
        "[10:00:01] [TRADE] Orchestrator BTCUSDT: EXECUTAR score=80 sinal=COMPRA\n"
        "[10:00:02] [TRADE] ETHUSDT: ABORTAR regime=NEUTRAL direction=LONG score=42 "
        "tier=C consensus=MEDIO_1 razao=score baixo\n"
    )
    p = tmp_path / "mixed.log"
    p.write_text(log, encoding="utf-8")
    signals = parse_paper_trade_log(str(p))
    assert len(signals) == 2
    # Primeiro = legacy, segundo = novo
    assert signals[0]["market"] == "BTCUSDT"
    assert signals[0]["sinal"] == "COMPRA"
    assert signals[1]["market"] == "ETHUSDT"
    assert signals[1]["tier"] == "C"
    assert signals[1]["consensus"] == "MEDIO_1"
    assert signals[1]["razao"] == "score baixo"


# ── 9. Formato v1.5 (lib_trade_logger.ps1 2026-05-15 EUREKA A) ───────────
# Emite scanner_score + score_predicted separados em vez de score=X ambiguo.

def test_parse_trade_line_v15_dual_score():
    """v1.5: scanner_score + score_predicted como campos separados."""
    line = (
        "[10:00:00] [TRADE] BTCUSDT: ABORTAR "
        "regime=NEUTRAL direction=LONG scanner_score=42 score_predicted=60 "
        "tier=D consensus=CAOS razao=tier_baixo"
    )
    s = parse_trade_line(line)
    assert s is not None
    assert s["market"] == "BTCUSDT"
    assert s["scanner_score"] == 42
    assert s["score_predicted"] == 60
    # 'score' legacy preservado como alias de score_predicted (compat consumers)
    assert s["score"] == 60
    assert s["tier"] == "D"


def test_parse_trade_line_v15_with_dash_scanner_score():
    """v1.5: scanner_score=- (null) + score_predicted populado."""
    line = (
        "[10:00:00] [TRADE] BTCUSDT: ABORTAR "
        "regime=NEUTRAL direction=LONG scanner_score=- score_predicted=75 "
        "tier=B consensus=MEDIO_2 razao=ok"
    )
    s = parse_trade_line(line)
    assert s["scanner_score"] is None
    assert s["score_predicted"] == 75
    assert s["score"] == 75


def test_parse_trade_line_v15_both_dash():
    """v1.5: ambos scanner_score e score_predicted como '-'."""
    line = (
        "[10:00:00] [TRADE] BTCUSDT: ABORTAR "
        "regime=NEUTRAL direction=LONG scanner_score=- score_predicted=- "
        "tier=D consensus=CAOS razao=-"
    )
    s = parse_trade_line(line)
    assert s["scanner_score"] is None
    assert s["score_predicted"] is None
    assert s["score"] is None


def test_parse_trade_line_legacy_v10_score_still_works():
    """v1.0 (sem _predicted/_scanner) ainda parseia."""
    line = (
        "[10:00:00] [TRADE] ETHUSDT: ABORTAR "
        "regime=NEUTRAL direction=LONG score=42 tier=C consensus=MEDIO_1 razao=x"
    )
    s = parse_trade_line(line)
    assert s["score"] == 42
    assert s["scanner_score"] is None
    assert s["score_predicted"] is None
    assert s["tier"] == "C"


def test_parse_paper_trade_log_v15_format(tmp_path):
    """End-to-end: log inteiro em v1.5 com dual score."""
    log = (
        "MASTER CYCLE  10:00 15/05  PRIME  momento=85/100\n"
        "[10:00:01] [TRADE] BTCUSDT: ABORTAR "
        "regime=NEUTRAL direction=LONG scanner_score=42 score_predicted=60 "
        "tier=D consensus=CAOS razao=tier_baixo\n"
        "[10:00:02] [TRADE] ETHUSDT: ABORTAR "
        "regime=NEUTRAL direction=LONG scanner_score=- score_predicted=42 "
        "tier=D consensus=CAOS razao=score_baixo\n"
    )
    p = tmp_path / "v15.log"
    p.write_text(log, encoding="utf-8")
    signals = parse_paper_trade_log(str(p))
    assert len(signals) == 2
    assert signals[0]["scanner_score"] == 42
    assert signals[0]["score_predicted"] == 60
    assert signals[1]["scanner_score"] is None
    assert signals[1]["score_predicted"] == 42


def test_v15_mixed_with_v10_and_legacy(tmp_path):
    """Log heterogeneo: 3 formatos coexistindo."""
    log = (
        "MASTER CYCLE  10:00 15/05  PRIME  momento=85/100\n"
        # Legacy v0 (com Orchestrator + sinal=)
        "[10:00:01] [TRADE] Orchestrator BTCUSDT: EXECUTAR score=80 sinal=COMPRA\n"
        # v1.0 (sem dual score)
        "[10:00:02] [TRADE] ETHUSDT: ABORTAR regime=NEUTRAL direction=LONG "
        "score=42 tier=C consensus=MEDIO_1 razao=ok\n"
        # v1.5 (dual score)
        "[10:00:03] [TRADE] SOLUSDT: ABORTAR regime=NEUTRAL direction=LONG "
        "scanner_score=42 score_predicted=60 tier=D consensus=CAOS razao=tier_baixo\n"
    )
    p = tmp_path / "mixed.log"
    p.write_text(log, encoding="utf-8")
    signals = parse_paper_trade_log(str(p))
    assert len(signals) == 3
    # Legacy
    assert signals[0]["market"] == "BTCUSDT"
    assert signals[0]["score"] == 80
    # v1.0
    assert signals[1]["market"] == "ETHUSDT"
    assert signals[1]["score"] == 42
    assert signals[1]["scanner_score"] is None
    # v1.5
    assert signals[2]["market"] == "SOLUSDT"
    assert signals[2]["scanner_score"] == 42
    assert signals[2]["score_predicted"] == 60
