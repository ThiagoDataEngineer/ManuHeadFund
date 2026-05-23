"""test_drawdown_source_aware.py -- valida thresholds source-aware no monitor."""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from tier_a_drawdown_monitor import get_thresholds, SOURCE_THRESHOLDS, DRAWDOWN_FLAG, DRAWDOWN_CRITICAL


class TestGetThresholds:
    def test_tier_a_strict(self):
        t = get_thresholds("tier_a")
        assert t["flag"] == -0.15
        assert t["critical"] == -0.25
        assert t["label"] == "TIER_A_LIVE"

    def test_gem_loose(self):
        t = get_thresholds("gem")
        assert t["flag"] == -0.30
        assert t["critical"] == -0.45
        assert t["label"] == "GEM"

    def test_orchestrator_alias_tier_a(self):
        t = get_thresholds("orchestrator")
        assert t["flag"] == -0.15
        assert t["critical"] == -0.25

    def test_unknown_falls_to_default(self):
        t = get_thresholds("foobar")
        assert t["flag"] == DRAWDOWN_FLAG
        assert t["critical"] == DRAWDOWN_CRITICAL
        assert t["label"] == "DEFAULT"

    def test_none_defensive(self):
        t = get_thresholds(None)
        assert t["flag"] == DRAWDOWN_FLAG

    def test_gem_tolerates_30pct_dd(self):
        # GEM com -30% DD seria FLAG mas nao CRITICAL
        t = get_thresholds("gem")
        dd_pct = -0.32
        assert dd_pct <= t["flag"]      # flagged
        assert dd_pct > t["critical"]   # NOT critical

    def test_tier_a_30pct_already_critical(self):
        # Mesma -32% DD pra Tier A LIVE = CRITICAL
        t = get_thresholds("tier_a")
        dd_pct = -0.32
        assert dd_pct <= t["critical"]


# =============================================================================
# Wire integration (2026-05-20): check_drawdown deve USAR get_thresholds.
# Antes era helper orfa. Agora wired.
# =============================================================================
from unittest.mock import patch
from tier_a_drawdown_monitor import check_drawdown


def _mock_ticker(last_price):
    """Mocka fetch retornando ticker + kline com peak controlado."""
    return {"data": [{"last": str(last_price), "open": str(last_price)}]}


def _mock_kline(peak_price, current_price):
    return {"data": [
        {"high": str(peak_price)} for _ in range(6)
    ] + [{"high": str(current_price)}]}


class TestCheckDrawdownSourceAware:
    """check_drawdown deve aplicar thresholds source-aware."""

    def test_tier_a_position_minus20pct_eh_FLAGGED(self):
        # Tier A: -20% vs peak -> FLAGGED (entre -15% e -25%)
        with patch("tier_a_drawdown_monitor.fetch") as mf:
            mf.side_effect = [_mock_ticker(80), _mock_kline(100, 80)]
            r = check_drawdown("BTCUSDT", source="tier_a")
            assert r["status"] == "FLAGGED"
            assert r["source"] == "tier_a"

    def test_tier_a_position_minus30pct_eh_CRITICAL(self):
        with patch("tier_a_drawdown_monitor.fetch") as mf:
            mf.side_effect = [_mock_ticker(70), _mock_kline(100, 70)]
            r = check_drawdown("BTCUSDT", source="tier_a")
            assert r["status"] == "CRITICAL"

    def test_gem_position_minus30pct_eh_FLAGGED_apenas(self):
        # GEM: -30% ainda flag (critical=-45%), nao critical
        with patch("tier_a_drawdown_monitor.fetch") as mf:
            mf.side_effect = [_mock_ticker(70), _mock_kline(100, 70)]
            r = check_drawdown("PEPEUSDT", source="gem")
            assert r["status"] == "FLAGGED"
            assert r["source"] == "gem"

    def test_gem_position_minus50pct_eh_CRITICAL(self):
        with patch("tier_a_drawdown_monitor.fetch") as mf:
            mf.side_effect = [_mock_ticker(50), _mock_kline(100, 50)]
            r = check_drawdown("PEPEUSDT", source="gem")
            assert r["status"] == "CRITICAL"

    def test_default_source_eh_tier_a(self):
        # backward compat: sem source -> tier_a thresholds
        with patch("tier_a_drawdown_monitor.fetch") as mf:
            mf.side_effect = [_mock_ticker(80), _mock_kline(100, 80)]
            r = check_drawdown("BTCUSDT")
            assert r["status"] == "FLAGGED"  # -20% tier_a = flagged

    def test_response_includes_thresholds_applied(self):
        # Diagnose: response deve incluir thresholds usados pra debug
        with patch("tier_a_drawdown_monitor.fetch") as mf:
            mf.side_effect = [_mock_ticker(90), _mock_kline(100, 90)]
            r = check_drawdown("BTCUSDT", source="gem")
            assert "thresholds_used" in r
            assert r["thresholds_used"]["flag"] == -0.30
            assert r["thresholds_used"]["critical"] == -0.45
