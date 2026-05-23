"""test_fqs_gate_discovery.py -- TDD pra FQS gate em weekly_discovery."""
from __future__ import annotations
import os, sys, json, tempfile
from pathlib import Path

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from fqs_gate_discovery import (
    compute_fqs,
    load_fqs_score,
    is_fqs_eligible,
    apply_fqs_gate,
)


class TestComputeFqs:
    def test_full_blue_chip_score_7(self):
        entry = {
            "age_years": 10, "supply_capped": True, "burn_active": True,
            "utility_score": 1.0, "concentration_top10": 0.20,
            "recovered_2021_ath": True, "listing_years": 5,
        }
        r = compute_fqs(entry)
        assert r["fqs"] == 7
        assert r["category"] == "BLUE_CHIP"

    def test_btc_no_burn_fqs_6(self):
        # BTC: no burn but capped + age + recovered -> 6/7
        entry = {
            "age_years": 16, "supply_capped": True, "burn_active": False,
            "utility_score": 1.0, "concentration_top10": 0.10,
            "recovered_2021_ath": True, "listing_years": 8,
        }
        r = compute_fqs(entry)
        assert r["fqs"] == 6
        assert r["category"] == "BLUE_CHIP"

    def test_eth_uncapped_burn_net_deflation(self):
        # ETH: uncapped MAS burn_net_deflation = True -> dimension 2 OK
        entry = {
            "age_years": 10, "supply_capped": False, "burn_net_deflation": True,
            "burn_active": True, "utility_score": 1.0, "concentration_top10": 0.25,
            "recovered_2021_ath": False, "listing_years": 8,
        }
        r = compute_fqs(entry)
        assert r["fqs"] >= 6
        assert "burn_net_deflation" in r["reasons"]

    def test_young_token_no_cycle_penalty(self):
        # HYPE-like: age<2 -> young_NA_cycle bonus em vez de fail
        entry = {
            "age_years": 1.5, "supply_capped": True, "burn_active": True,
            "utility_score": 0.8, "concentration_top10": 0.40,
            "recovered_2021_ath": False, "listing_years": 1,
        }
        r = compute_fqs(entry)
        assert "young_NA_cycle" in r["reasons"]
        assert r["fqs"] >= 4

    def test_speculative_2_signals(self):
        entry = {"age_years": 3, "supply_capped": False, "burn_active": False,
                 "utility_score": 0.2, "concentration_top10": 0.60,
                 "recovered_2021_ath": False, "listing_years": 0.5}
        r = compute_fqs(entry)
        assert r["category"] in ("AVOID", "SPECULATIVE")

    def test_concentration_insider_overrides(self):
        # concentration_top10 alta MAS insider OK -> usa insider
        entry = {"age_years": 5, "supply_capped": True, "burn_active": True,
                 "utility_score": 0.7, "concentration_top10": 0.70,
                 "concentration_insider_pct": 0.20,
                 "recovered_2021_ath": True, "listing_years": 4}
        r = compute_fqs(entry)
        assert "concentration_ok" in r["reasons"]


class TestIsFqsEligible:
    def test_blue_chip_eligible_tier_a(self, tmp_path):
        reg = tmp_path / "reg.json"
        reg.write_text(json.dumps({"BLUE": {
            "age_years": 10, "supply_capped": True, "burn_active": True,
            "utility_score": 1.0, "concentration_top10": 0.10,
            "recovered_2021_ath": True, "listing_years": 5,
        }}))
        assert is_fqs_eligible("BLUE", "TIER_A_LIVE", reg) is True
        assert is_fqs_eligible("BLUE", "GEM", reg) is True

    def test_avoid_not_eligible_anywhere(self, tmp_path):
        reg = tmp_path / "reg.json"
        reg.write_text(json.dumps({"BAD": {
            "age_years": 0.3, "supply_capped": False, "burn_active": False,
            "utility_score": 0, "concentration_top10": 0.85,
            "recovered_2021_ath": False, "listing_years": 0.1,
        }}))
        assert is_fqs_eligible("BAD", "TIER_A_LIVE", reg) is False
        assert is_fqs_eligible("BAD", "GEM", reg) is False

    def test_speculative_only_gem(self, tmp_path):
        reg = tmp_path / "reg.json"
        reg.write_text(json.dumps({"SPEC": {
            "age_years": 4, "supply_capped": True, "burn_active": False,
            "utility_score": 0.3, "concentration_top10": 0.55,
            "recovered_2021_ath": False, "listing_years": 1,
        }}))
        assert is_fqs_eligible("SPEC", "TIER_A_LIVE", reg) is False
        assert is_fqs_eligible("SPEC", "GEM", reg) is True


class TestApplyFqsGate:
    def test_blue_chip_stays_tier_a(self, tmp_path):
        reg = tmp_path / "reg.json"
        reg.write_text(json.dumps({"GOOD": {
            "age_years": 10, "supply_capped": True, "burn_active": True,
            "utility_score": 1.0, "concentration_top10": 0.20,
            "recovered_2021_ath": True, "listing_years": 5,
        }}))
        results = [{"market": "GOOD", "tier_assigned": "A"}]
        apply_fqs_gate(results, "TIER_A_LIVE", reg)
        assert results[0]["tier_assigned"] == "A"
        assert results[0]["fqs_score"]["category"] == "BLUE_CHIP"

    def test_speculative_demoted_to_b(self, tmp_path):
        reg = tmp_path / "reg.json"
        reg.write_text(json.dumps({"SPEC": {
            "age_years": 4, "supply_capped": False, "burn_active": False,
            "utility_score": 0.4, "concentration_top10": 0.55,
            "recovered_2021_ath": False, "listing_years": 1,
        }}))
        results = [{"market": "SPEC", "tier_assigned": "A"}]
        apply_fqs_gate(results, "TIER_A_LIVE", reg)
        assert results[0]["tier_assigned"] == "B"
        assert "fqs_" in results[0]["demoted_reason"]

    def test_tier_b_untouched(self, tmp_path):
        reg = tmp_path / "reg.json"
        reg.write_text(json.dumps({"X": {"age_years": 0}}))
        results = [{"market": "X", "tier_assigned": "B"}]
        apply_fqs_gate(results, "TIER_A_LIVE", reg)
        assert results[0]["tier_assigned"] == "B"
        # fqs_score nao adicionado a tier B
        assert "fqs_score" not in results[0]

    def test_unknown_market_demoted(self, tmp_path):
        reg = tmp_path / "reg.json"
        reg.write_text(json.dumps({}))
        results = [{"market": "UNKNOWN", "tier_assigned": "A"}]
        apply_fqs_gate(results, "TIER_A_LIVE", reg)
        assert results[0]["tier_assigned"] == "B"

    def test_chained_with_other_demote_reasons(self, tmp_path):
        reg = tmp_path / "reg.json"
        reg.write_text(json.dumps({"X": {"age_years": 0}}))
        results = [{"market": "X", "tier_assigned": "A", "demoted_reason": "anti_pump_buy:-2.5%"}]
        apply_fqs_gate(results, "TIER_A_LIVE", reg)
        assert "anti_pump_buy" in results[0]["demoted_reason"]
        assert "fqs_" in results[0]["demoted_reason"]
