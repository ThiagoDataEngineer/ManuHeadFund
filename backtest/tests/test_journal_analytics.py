"""test_journal_analytics.py — TDD para journal_analytics.py"""

import os
import sys
import tempfile
import textwrap

import pandas as pd
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from journal_analytics import (
    load_gem_signals,
    load_gem_trades,
    gate_pass_rate,
    top_blocked_gate,
    discovery_vs_momentum_ratio,
    spike_ratio_passed_vs_blocked,
    signals_per_day,
    pnl_summary,
)

# ─────────────────────────────────────────────────────────────────────────────
# Fixtures
# ─────────────────────────────────────────────────────────────────────────────

SIGNALS_CSV = textwrap.dedent("""\
    timestamp,market,score,mode,gates_passed,gate_failed,spike_ratio,spike_type,pct_change_today,mcap_usd,price_at_scan,vol_today,sizing_usd,stop_pct,target_pct,alerta,scan_id
    2026-05-12 10:00:00,FIROUSDT,78,DISCOVERY,G1|G2|G3|G4|G5|G6,,2.5,BULLISH,15.0,1500000,1.00,50000,2.0,0.50,2.00,DISCOVERY score=78,scan1
    2026-05-12 10:00:01,XYZUSDT,0,NONE,G1|G2,G4,2.1,BULLISH,8.0,0,0.50,30000,0,,,bloqueado G4,scan1
    2026-05-12 10:00:02,ABCUSDT,0,NONE,G1,G2,1.5,NEUTRAL,2.0,0,0.10,10000,0,,,bloqueado G2,scan1
    2026-05-13 10:00:00,MOMUNSDT,65,MOMENTUM,G1|G2|G3|G4|G5,,3.0,BULLISH,20.0,5000000,2.00,80000,4.0,0.30,0.90,MOMENTUM score=65,scan2
    2026-05-13 10:00:01,ZZUSDT,0,NONE,G1|G2|G3,G5,2.2,BEARISH,5.0,0,0.20,20000,0,,,bloqueado G5,scan2
""")

TRADES_CSV_EMPTY = "timestamp,market,mode,market_type,score,price_entry,qty,stop_price,target_price,sizing_usd,order_id,dry_run,status,price_exit,pnl_pct,notes\n"

TRADES_CSV_CLOSED = textwrap.dedent("""\
    timestamp,market,mode,market_type,score,price_entry,qty,stop_price,target_price,sizing_usd,order_id,dry_run,status,price_exit,pnl_pct,notes
    2026-05-12 11:00:00,FIROUSDT,DISCOVERY,FUTURES,78,1.00,2.0,0.50,3.00,2.0,T1,false,CLOSED,2.50,150.0,
    2026-05-12 12:00:00,XYZUSDT,DISCOVERY,FUTURES,72,0.50,4.0,0.25,1.50,2.0,T2,false,CLOSED,0.30,-40.0,
    2026-05-13 10:00:00,MOMUNSDT,MOMENTUM,FUTURES,65,2.00,2.0,1.40,3.80,4.0,T3,false,OPEN,,,
""")


@pytest.fixture
def signals_file(tmp_path):
    f = tmp_path / "gem_signals.csv"
    f.write_text(SIGNALS_CSV, encoding="utf-8")
    return str(f)


@pytest.fixture
def trades_empty_file(tmp_path):
    f = tmp_path / "gem_trades.csv"
    f.write_text(TRADES_CSV_EMPTY, encoding="utf-8")
    return str(f)


@pytest.fixture
def trades_closed_file(tmp_path):
    f = tmp_path / "gem_trades.csv"
    f.write_text(TRADES_CSV_CLOSED, encoding="utf-8")
    return str(f)


# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

def test_load_gem_signals_csv(signals_file):
    df = load_gem_signals(signals_file)
    assert len(df) == 5
    assert "market" in df.columns
    assert "score" in df.columns


def test_gate_pass_rate(signals_file):
    df = load_gem_signals(signals_file)
    rates = gate_pass_rate(df)
    assert "G1" in rates
    assert rates["G1"] == 100.0       # todos passam G1
    assert rates["G4"] < rates["G1"]  # G4 filtra mais


def test_top_blocked_gate(signals_file):
    df = load_gem_signals(signals_file)
    blocked = top_blocked_gate(df)
    assert "G4" in blocked
    assert blocked["G4"] >= 1


def test_discovery_vs_momentum_ratio(signals_file):
    df = load_gem_signals(signals_file)
    ratio = discovery_vs_momentum_ratio(df)
    assert "DISCOVERY" in ratio
    assert "MOMENTUM" in ratio
    assert ratio["DISCOVERY"] + ratio["MOMENTUM"] == pytest.approx(100.0, abs=0.1)


def test_spike_ratio_passed_vs_blocked(signals_file):
    df = load_gem_signals(signals_file)
    result = spike_ratio_passed_vs_blocked(df)
    assert "passed_avg" in result
    assert "blocked_avg" in result
    assert result["passed_avg"] > 0


def test_signals_per_day(signals_file):
    df = load_gem_signals(signals_file)
    spd = signals_per_day(df)
    assert len(spd) == 2          # 2 dias distintos
    assert spd.sum() == 5


def test_empty_csv_returns_empty_report(tmp_path):
    empty = tmp_path / "empty.csv"
    empty.write_text("timestamp,market,score\n", encoding="utf-8")
    df = load_gem_signals(str(empty))
    assert gate_pass_rate(df) == {}
    assert top_blocked_gate(df) == {}


def test_load_trades_csv_empty_header_only(trades_empty_file):
    df = load_gem_trades(trades_empty_file)
    assert df.empty or len(df) == 0


def test_pnl_summary_skips_when_no_closed_trades(trades_empty_file):
    df = load_gem_trades(trades_empty_file)
    result = pnl_summary(df)
    assert result == {} or result.get("closed_trades", 0) == 0
