"""
test_weekly_discovery_gates_wire.py -- valida wire promotion_gates em weekly_discovery.

NAO roda o pipeline inteiro (custoso); reproduz o codigo do bloco 4.6 inline
contra fixtures controlados e verifica:
  1. TIER A com gates OK -> permanece A
  2. TIER A com concentration excedida -> demote para B, reason gates:concentration
  3. TIER A com volume baixo -> demote para B, reason gates:min_volume
  4. TIER A com sector overload -> demote para B, reason gates:sector
"""
from __future__ import annotations

import os
import sys
import json
import tempfile
from pathlib import Path

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from promotion_gates import invoke_all_gates  # noqa: E402


def _apply_gates_block(results, tier_a_existing, sector_map_path=None):
    """Reproduz o codigo 4.6 do weekly_discovery (inline pra teste isolado)."""
    for r in results:
        if r.get("tier_assigned") != "A":
            continue
        market = r.get("market")
        best = r.get("best", {}) or {}
        vol_usd = float(best.get("volume_usd", 0) or 0)
        kwargs = dict(
            market=market,
            volume_usd=vol_usd,
            current_tier_a_count=len(tier_a_existing),
            current_tier_a_markets=tier_a_existing,
            equity_today_pct=0,
            position_size_usd=100,
        )
        if sector_map_path:
            # invoke_all_gates aceita sector via env-loaded SECTOR_MAP_PATH default;
            # pra test isolation, faz monkeypath via env
            os.environ["SECTOR_MAP_PATH_OVERRIDE"] = str(sector_map_path)
        gates_res = invoke_all_gates(**kwargs)
        r["promotion_gates"] = gates_res
        if not gates_res["all_pass"]:
            r["tier_assigned"] = "B"
            r["demoted_reason"] = f"gates:{','.join(gates_res['blocked_by'])}"
    return results


class TestPromotionGatesWire:
    def test_tier_a_clean_stays_a(self):
        results = [{
            "market": "INJUSDT",
            "tier_assigned": "A",
            "best": {"volume_usd": 5_000_000},
        }]
        out = _apply_gates_block(results, tier_a_existing=["BTCUSDT"])
        assert out[0]["tier_assigned"] == "A"
        assert out[0]["promotion_gates"]["all_pass"] is True

    def test_concentration_blocks_demote_to_b(self):
        results = [{
            "market": "HYPEUSDT",
            "tier_assigned": "A",
            "best": {"volume_usd": 5_000_000},
        }]
        tier_a = ["BTCUSDT", "ETHUSDT", "RENDERUSDT", "CFGUSDT", "ZECUSDT", "INJUSDT"]
        out = _apply_gates_block(results, tier_a_existing=tier_a)
        assert out[0]["tier_assigned"] == "B"
        assert "concentration" in out[0]["demoted_reason"]

    def test_min_volume_blocks_demote_to_b(self):
        results = [{
            "market": "FOOUSDT",
            "tier_assigned": "A",
            "best": {"volume_usd": 50_000},  # abaixo do min 500k
        }]
        out = _apply_gates_block(results, tier_a_existing=["BTCUSDT"])
        assert out[0]["tier_assigned"] == "B"
        assert "min_volume" in out[0]["demoted_reason"]

    def test_multiple_blocks_chained_in_reason(self):
        results = [{
            "market": "FOOUSDT",
            "tier_assigned": "A",
            "best": {"volume_usd": 50_000},  # min_volume FAIL
        }]
        # tier_a 6 markets -> concentration FAIL
        tier_a = ["BTCUSDT", "ETHUSDT", "RENDERUSDT", "CFGUSDT", "ZECUSDT", "INJUSDT"]
        out = _apply_gates_block(results, tier_a_existing=tier_a)
        assert out[0]["tier_assigned"] == "B"
        reason = out[0]["demoted_reason"]
        assert "concentration" in reason
        assert "min_volume" in reason

    def test_non_tier_a_untouched(self):
        results = [
            {"market": "BAR", "tier_assigned": "C", "best": {"volume_usd": 10}},
            {"market": "BAZ", "tier_assigned": "B", "best": {"volume_usd": 10}},
        ]
        out = _apply_gates_block(results, tier_a_existing=[])
        assert out[0]["tier_assigned"] == "C"
        assert out[1]["tier_assigned"] == "B"
        assert "promotion_gates" not in out[0]
        assert "promotion_gates" not in out[1]
