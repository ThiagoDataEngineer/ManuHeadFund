"""TDD — stablecoin_regime.py"""
import pytest
from stablecoin_regime import (
    classify_regime, compute_supply_change, regime_at,
    is_short_allowed, long_sizing_multiplier,
)


# ── classify_regime ──────────────────────────────────────────────────────────

class TestClassifyRegime:
    def test_expansion_threshold(self):
        assert classify_regime(3.0) == "EXPANSION"
        assert classify_regime(5.0) == "EXPANSION"

    def test_neutral_range(self):
        assert classify_regime(0.0) == "NEUTRAL"
        assert classify_regime(2.99) == "NEUTRAL"
        assert classify_regime(-0.5) == "NEUTRAL"

    def test_warning(self):
        assert classify_regime(-0.6) == "WARNING"
        assert classify_regime(-2.0) == "WARNING"

    def test_contraction(self):
        assert classify_regime(-2.1) == "CONTRACTION"
        assert classify_regime(-5.0) == "CONTRACTION"

    def test_crisis(self):
        assert classify_regime(-5.1) == "CRISIS"
        assert classify_regime(-10.0) == "CRISIS"

    def test_none_returns_unknown(self):
        assert classify_regime(None) == "UNKNOWN"


# ── compute_supply_change ────────────────────────────────────────────────────

class TestComputeSupplyChange:
    @pytest.fixture
    def series(self):
        # 30 dias atras: 100, hoje: 110 → +10%
        return {
            "2024-01-01": 100.0,
            "2024-01-31": 110.0,
        }

    def test_basic_change(self, series):
        c = compute_supply_change(series, "2024-01-31", days=30)
        assert c == pytest.approx(10.0, abs=0.01)

    def test_returns_none_if_target_missing(self, series):
        assert compute_supply_change(series, "2024-02-15", days=30) is None

    def test_negative_change(self):
        series = {"2024-01-01": 100.0, "2024-01-31": 95.0}
        c = compute_supply_change(series, "2024-01-31", days=30)
        assert c == pytest.approx(-5.0, abs=0.01)

    def test_tolerates_missing_prev_within_3d(self):
        # Prev exact 30d ago missing, 31d ago present
        series = {"2024-01-01": 100.0, "2024-02-01": 110.0}  # 31 days diff
        c = compute_supply_change(series, "2024-02-01", days=30)
        assert c == pytest.approx(10.0, abs=0.01)

    def test_returns_none_when_no_prev_in_window(self):
        series = {"2024-02-01": 110.0}  # nothing in past
        assert compute_supply_change(series, "2024-02-01", days=30) is None


# ── regime_at ────────────────────────────────────────────────────────────────

class TestRegimeAt:
    def test_expansion_regime(self):
        s = {"2024-01-01": 100.0, "2024-01-31": 105.0}
        r = regime_at(s, "2024-01-31")
        assert r["regime"] == "EXPANSION"
        assert r["supply_change_30d_pct"] == pytest.approx(5.0, abs=0.01)

    def test_crisis_regime(self):
        s = {"2024-01-01": 100.0, "2024-01-31": 92.0}  # -8%
        r = regime_at(s, "2024-01-31")
        assert r["regime"] == "CRISIS"


# ── gate / sizing helpers ────────────────────────────────────────────────────

class TestGates:
    def test_short_not_allowed_in_expansion(self):
        assert not is_short_allowed("EXPANSION")

    def test_short_not_allowed_in_neutral(self):
        assert not is_short_allowed("NEUTRAL")

    def test_short_allowed_in_warning_and_worse(self):
        assert is_short_allowed("WARNING")
        assert is_short_allowed("CONTRACTION")
        assert is_short_allowed("CRISIS")

    def test_sizing_multipliers_order(self):
        assert long_sizing_multiplier("EXPANSION") > long_sizing_multiplier("NEUTRAL")
        assert long_sizing_multiplier("NEUTRAL") > long_sizing_multiplier("WARNING")
        assert long_sizing_multiplier("WARNING") > long_sizing_multiplier("CONTRACTION")
        assert long_sizing_multiplier("CONTRACTION") > long_sizing_multiplier("CRISIS")

    def test_crisis_blocks_long(self):
        assert long_sizing_multiplier("CRISIS") == 0.0

    def test_unknown_fallback_neutral(self):
        assert long_sizing_multiplier("UNKNOWN") == 1.0
