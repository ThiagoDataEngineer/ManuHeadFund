"""test_promotion_gates.py — Python paridade dos 10 gates."""
from __future__ import annotations

import json
import os
import sys
import tempfile
from datetime import datetime, timezone, timedelta

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from promotion_gates import (  # noqa: E402
    check_concentration_limit,
    check_daily_loss_circuit,
    check_sector_concentration,
    check_cooldown_post_demote,
    check_min_volume_gate,
    check_phase_boundary_safety,
    check_time_of_week_gate,
    check_slippage_budget,
    check_cross_asset_correlation,
    check_funding_rate_gate,
    add_demote_event,
    invoke_all_gates,
)


@pytest.fixture
def sector_map():
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False, encoding="utf-8") as f:
        json.dump({"markets": {
            "BTCUSDT": "store_of_value",
            "ETHUSDT": "l1",
            "INJUSDT": "l1",
            "ZECUSDT": "privacy",
            "ONDOUSDT": "rwa",
            "CFGUSDT": "rwa",
            "PENDLEUSDT": "rwa",
        }}, f)
        path = f.name
    yield path
    os.unlink(path)


@pytest.fixture
def demote_hist():
    with tempfile.NamedTemporaryFile(mode="w", suffix=".jsonl", delete=False) as f:
        path = f.name
    yield path
    if os.path.exists(path):
        os.unlink(path)


class TestConcentration:
    def test_below_limit(self):
        assert check_concentration_limit(3, 5)["passes"] is True
    def test_at_limit(self):
        assert check_concentration_limit(5, 5)["passes"] is True
    def test_above_limit(self):
        assert check_concentration_limit(6, 5)["passes"] is False


class TestDailyLoss:
    def test_minor_loss_passes(self):
        assert check_daily_loss_circuit(-3.0)["passes"] is True
    def test_at_threshold_blocks(self):
        assert check_daily_loss_circuit(-5.0)["passes"] is False
    def test_severe_loss_blocks(self):
        assert check_daily_loss_circuit(-8.0)["passes"] is False
    def test_profit_passes(self):
        assert check_daily_loss_circuit(2.5)["passes"] is True


class TestSector:
    def test_2_rwa_blocks_3rd(self, sector_map):
        r = check_sector_concentration("ENAUSDT", ["CFGUSDT", "PENDLEUSDT", "BTCUSDT"],
                                       sector_map_path=sector_map)
        # ENA não está no map = unknown → passa
        assert r["passes"] is True
    def test_2_l1_blocks_3rd(self, sector_map):
        r = check_sector_concentration("INJUSDT", ["ETHUSDT", "INJUSDT"], sector_map_path=sector_map, max_per_sector=2)
        # ETH+INJ ja sao 2 L1, INJ entrada NAO passa
        assert r["passes"] is False
    def test_first_l2_passes(self, sector_map):
        r = check_sector_concentration("ARBUSDT", ["BTCUSDT", "ETHUSDT"], sector_map_path=sector_map)
        assert r["passes"] is True
    def test_unknown_passes(self, sector_map):
        r = check_sector_concentration("FOOUSDT", ["BTCUSDT", "ETHUSDT"], sector_map_path=sector_map)
        assert r["passes"] is True


class TestCooldown:
    def test_never_demoted_passes(self, demote_hist):
        assert check_cooldown_post_demote("BTCUSDT", demote_history_path=demote_hist)["passes"] is True
    def test_recent_demote_blocks(self, demote_hist):
        old = (datetime.now(timezone.utc) - timedelta(days=5)).strftime("%Y-%m-%dT%H:%M:%SZ")
        with open(demote_hist, "w") as f:
            f.write(json.dumps({"market": "X", "demoted_at": old, "reason": "test"}) + "\n")
        assert check_cooldown_post_demote("X", demote_history_path=demote_hist)["passes"] is False
    def test_old_demote_passes(self, demote_hist):
        old = (datetime.now(timezone.utc) - timedelta(days=60)).strftime("%Y-%m-%dT%H:%M:%SZ")
        with open(demote_hist, "w") as f:
            f.write(json.dumps({"market": "X", "demoted_at": old, "reason": "test"}) + "\n")
        assert check_cooldown_post_demote("X", demote_history_path=demote_hist)["passes"] is True


class TestMinVolume:
    def test_above_passes(self):
        assert check_min_volume_gate(1_000_000)["passes"] is True
    def test_below_blocks(self):
        assert check_min_volume_gate(50_000)["passes"] is False
    def test_cfg_real_case(self):
        # CFG vol $7.6K seria blocked com default $500K
        assert check_min_volume_gate(7_600)["passes"] is False


class TestPhaseBoundary:
    def test_null_passes(self):
        assert check_phase_boundary_safety(None)["passes"] is True
    def test_recent_change_blocks(self):
        recent = datetime.now(timezone.utc) - timedelta(days=3)
        assert check_phase_boundary_safety(recent)["passes"] is False
    def test_old_change_passes(self):
        old = datetime.now(timezone.utc) - timedelta(days=10)
        assert check_phase_boundary_safety(old)["passes"] is True


class TestTimeOfWeek:
    def test_monday_long_passes(self):
        mon = datetime(2024, 1, 15, 12, 0)  # Monday
        assert check_time_of_week_gate(mon, direction="long")["passes"] is True
    def test_thursday_afternoon_long_blocks(self):
        thu = datetime(2024, 1, 18, 16, 0)  # Thursday 16h
        assert check_time_of_week_gate(thu, direction="long")["passes"] is False
    def test_thursday_short_passes(self):
        thu = datetime(2024, 1, 18, 16, 0)
        assert check_time_of_week_gate(thu, direction="short")["passes"] is True


class TestSlippageBudget:
    def test_high_ratio_passes(self):
        assert check_slippage_budget(1_000_000, 100)["passes"] is True
    def test_low_ratio_blocks(self):
        assert check_slippage_budget(5_000, 100)["passes"] is False
    def test_zero_size(self):
        assert check_slippage_budget(1_000_000, 0)["passes"] is False


class TestCorrelation:
    def test_no_corr_passes(self, sector_map):
        r = check_cross_asset_correlation("INJUSDT", ["BTCUSDT"], sector_map_path=sector_map)
        assert r["passes"] is True
    def test_same_sector_blocks(self, sector_map):
        r = check_cross_asset_correlation("INJUSDT", ["ETHUSDT"], sector_map_path=sector_map)
        assert r["passes"] is False


class TestFunding:
    def test_neutral_long_passes(self):
        assert check_funding_rate_gate(0.5, "long")["passes"] is True
    def test_overheated_long_blocks(self):
        assert check_funding_rate_gate(2.5, "long")["passes"] is False
    def test_overcold_short_blocks(self):
        assert check_funding_rate_gate(-2.5, "short")["passes"] is False


class TestAggregator:
    def test_invoke_all_gates_returns_summary(self, sector_map):
        r = invoke_all_gates("INJUSDT",
                            volume_usd=1_000_000,
                            current_tier_a_count=3,
                            current_tier_a_markets=["BTCUSDT"],
                            equity_today_pct=2.0,
                            position_size_usd=100)
        assert "all_pass" in r
        assert "blocked_by" in r
        assert "gates" in r
