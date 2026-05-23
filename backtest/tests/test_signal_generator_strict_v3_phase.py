"""
test_signal_generator_strict_v3_phase.py -- strict_v3 phase-aware.

Estende strict_v3 com:
  - halving_phase (phase_1_bull / phase_2_top / phase_3_bear / phase_4_recovery)
  - trendline_soft_passes (bool, do trendline_filter soft 5-15deg)

BULL_WEAK + LONG fica permitido SE phase in {phase_1_bull, phase_4_recovery}
                                  AND trendline_soft_passes == True.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from signal_generator import apply_regime_filter  # noqa: E402


class TestStrictV3PhaseBackwardCompat:
    """strict_v3 sem kwargs novos deve preservar comportamento."""

    def test_bull_strong_long_passes(self):
        s, r = apply_regime_filter("COMPRA", "BULL_STRONG", mode="strict_v3")
        assert s == "COMPRA"

    def test_bull_weak_long_blocked_without_phase(self):
        # Sem halving_phase, BULL_WEAK LONG segue bloqueado (backward-compat)
        s, r = apply_regime_filter("COMPRA", "BULL_WEAK", mode="strict_v3")
        assert s == "NEUTRO"

    def test_short_bear_strong_passes(self):
        s, r = apply_regime_filter("VENDA", "BEAR_STRONG", mode="strict_v3")
        assert s == "VENDA"


class TestStrictV3PhaseBullWeakConditional:
    """BULL_WEAK LONG conditional: phase + trendline."""

    def test_phase_1_bull_with_soft_trendline_passes(self):
        s, r = apply_regime_filter(
            "COMPRA", "BULL_WEAK", mode="strict_v3",
            halving_phase="phase_1_bull", trendline_soft_passes=True,
        )
        assert s == "COMPRA"
        assert "bull_weak" in r.lower()

    def test_phase_1_bull_without_trendline_blocked(self):
        s, r = apply_regime_filter(
            "COMPRA", "BULL_WEAK", mode="strict_v3",
            halving_phase="phase_1_bull", trendline_soft_passes=False,
        )
        assert s == "NEUTRO"
        assert "trendline" in r.lower()

    def test_phase_2_top_blocked_even_with_trendline(self):
        # Validado backtest: phase_2_top BULL_WEAK = -0.38R com fees
        s, r = apply_regime_filter(
            "COMPRA", "BULL_WEAK", mode="strict_v3",
            halving_phase="phase_2_top", trendline_soft_passes=True,
        )
        assert s == "NEUTRO"
        assert "phase" in r.lower()

    def test_phase_3_bear_blocked(self):
        # Dados insuficientes -> conservador
        s, r = apply_regime_filter(
            "COMPRA", "BULL_WEAK", mode="strict_v3",
            halving_phase="phase_3_bear", trendline_soft_passes=True,
        )
        assert s == "NEUTRO"

    def test_phase_4_recovery_with_trendline_passes(self):
        s, r = apply_regime_filter(
            "COMPRA", "BULL_WEAK", mode="strict_v3",
            halving_phase="phase_4_recovery", trendline_soft_passes=True,
        )
        assert s == "COMPRA"


class TestStrictV3PhaseOtherRegimes:
    """Regimes alem de BULL_WEAK nao sao afetados por phase params."""

    def test_bull_strong_unaffected_by_phase(self):
        s, _ = apply_regime_filter(
            "COMPRA", "BULL_STRONG", mode="strict_v3",
            halving_phase="phase_2_top", trendline_soft_passes=False,
        )
        assert s == "COMPRA"

    def test_short_unaffected_by_phase(self):
        s, _ = apply_regime_filter(
            "VENDA", "BEAR_STRONG", mode="strict_v3",
            halving_phase="phase_1_bull",
        )
        assert s == "VENDA"
