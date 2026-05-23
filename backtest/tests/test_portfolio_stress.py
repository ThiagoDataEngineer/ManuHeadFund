"""test_portfolio_stress.py -- TDD pra stress simulator.

simulate_btc_shock(positions, btc_pct) -> aplica BTC move + beta projection.
worst_case_portfolio(positions) -> max DD considerando correlation matrix.
"""
from __future__ import annotations
import os, sys, json, tempfile
from pathlib import Path

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from portfolio_stress import (
    simulate_btc_shock,
    portfolio_beta_avg,
    simulate_scenarios,
)


class TestSimulateBtcShock:
    def test_single_asset_beta_1_equal_btc(self):
        positions = [{"market": "BTCUSDT", "size_usd": 100, "beta": 1.0}]
        r = simulate_btc_shock(positions, btc_pct=-10)
        assert r["btc_shock_pct"] == -10
        assert abs(r["portfolio_pct"] - (-10)) < 0.01
        assert r["loss_usd"] == 10.0

    def test_amplifier_beta_1_5_amplifies(self):
        positions = [{"market": "ZEC", "size_usd": 100, "beta": 1.5}]
        r = simulate_btc_shock(positions, btc_pct=-10)
        # ZEC cai 15% (1.5x BTC). Loss = 15 USD
        assert abs(r["portfolio_pct"] - (-15)) < 0.01
        assert r["loss_usd"] == 15.0

    def test_negative_beta_inverse(self):
        positions = [{"market": "HYPE", "size_usd": 100, "beta": -0.26}]
        r = simulate_btc_shock(positions, btc_pct=-10)
        # HYPE com beta -0.26: BTC -10% -> HYPE +2.6% -> ganho!
        assert r["portfolio_pct"] > 0
        assert r["loss_usd"] < 0  # ganho

    def test_mixed_portfolio_weighted_avg(self):
        positions = [
            {"market": "BTC", "size_usd": 100, "beta": 1.0},
            {"market": "HYPE", "size_usd": 100, "beta": -0.26},
        ]
        r = simulate_btc_shock(positions, btc_pct=-20)
        # BTC -20 * 100 = -20; HYPE +5.2 * 100 = +5.2
        # Total: -20 + 5.2 = -14.8 USD em $200 = -7.4%
        assert abs(r["portfolio_pct"] - (-7.4)) < 0.1

    def test_zero_btc_shock_no_change(self):
        positions = [{"market": "X", "size_usd": 100, "beta": 1.0}]
        r = simulate_btc_shock(positions, btc_pct=0)
        assert r["portfolio_pct"] == 0
        assert r["loss_usd"] == 0


class TestPortfolioBetaAvg:
    def test_all_equal_weight(self):
        positions = [
            {"market": "A", "size_usd": 100, "beta": 1.5},
            {"market": "B", "size_usd": 100, "beta": 0.5},
        ]
        # Weighted avg: (1.5*100 + 0.5*100) / 200 = 1.0
        assert portfolio_beta_avg(positions) == 1.0

    def test_unequal_weight(self):
        positions = [
            {"market": "A", "size_usd": 300, "beta": 1.5},
            {"market": "B", "size_usd": 100, "beta": 0.5},
        ]
        # Weighted avg: (1.5*300 + 0.5*100) / 400 = (450+50)/400 = 1.25
        assert abs(portfolio_beta_avg(positions) - 1.25) < 0.01

    def test_empty_returns_zero(self):
        assert portfolio_beta_avg([]) == 0

    def test_missing_beta_treated_as_one(self):
        positions = [{"market": "A", "size_usd": 100}]  # no beta key
        # Default beta=1.0 (BTC-correlated assumption)
        assert portfolio_beta_avg(positions) == 1.0


class TestSimulateScenarios:
    def test_returns_table_with_scenarios(self):
        positions = [{"market": "BTC", "size_usd": 100, "beta": 1.0}]
        result = simulate_scenarios(positions, capital_total=1000)
        assert "scenarios" in result
        assert "portfolio_beta_avg" in result
        # Cenarios padrao: -10, -25, -50, +10, +25
        scenarios = result["scenarios"]
        assert any(s["btc_shock_pct"] == -50 for s in scenarios)
        assert any(s["btc_shock_pct"] == -10 for s in scenarios)

    def test_loss_pct_capital_correct(self):
        positions = [{"market": "X", "size_usd": 100, "beta": 1.0}]
        result = simulate_scenarios(positions, capital_total=1000)
        # Em -50% BTC: portfolio -50% de $100 = -$50 = -5% de $1000 capital
        scenario = next(s for s in result["scenarios"] if s["btc_shock_pct"] == -50)
        assert abs(scenario["loss_pct_of_capital"] - (-5.0)) < 0.1

    def test_amplifier_risk_flagged(self):
        # 5 amplifiers + capital comparison
        positions = [
            {"market": "ZEC", "size_usd": 27.6, "beta": 1.57},
            {"market": "INJ", "size_usd": 27.6, "beta": 1.21},
            {"market": "CFG", "size_usd": 27.6, "beta": 1.28},
            {"market": "RENDER", "size_usd": 27.6, "beta": 1.30},
            {"market": "BTC", "size_usd": 27.6, "beta": 1.00},
        ]
        result = simulate_scenarios(positions, capital_total=2762.93)
        # avg beta deve ser 1.27
        assert result["portfolio_beta_avg"] > 1.2
        # -50% BTC com avg beta 1.27 = -63.5% portfolio. Em $138 exposto / $2762 = ~-3.2% capital
        scenario_50 = next(s for s in result["scenarios"] if s["btc_shock_pct"] == -50)
        assert scenario_50["portfolio_pct"] < -50  # amplifies
