"""TDD - funding_peak.py"""
import pytest
from datetime import datetime, timedelta
from funding_peak import (
    rolling_mean, is_overheated, detect_peak, detect_drop, scan_signals,
)


def make_series(start_date: str, values):
    """Cria dict[date] = value a partir de start_date sequencial."""
    out = {}
    d0 = datetime.fromisoformat(start_date).date()
    for i, v in enumerate(values):
        out[(d0 + timedelta(days=i)).isoformat()] = v
    return out


# ── rolling_mean ─────────────────────────────────────────────────────────────

class TestRollingMean:
    def test_basic_average(self):
        s = make_series("2024-01-01", [0.01, 0.02, 0.03, 0.04, 0.05])
        m = rolling_mean(s, "2024-01-05", days=5)
        assert m == pytest.approx(0.03, abs=0.001)

    def test_returns_none_if_target_missing(self):
        s = make_series("2024-01-01", [0.01, 0.02])
        assert rolling_mean(s, "2024-01-15", days=5) is None

    def test_returns_none_if_insufficient_history(self):
        s = make_series("2024-01-05", [0.01])  # so 1 dia
        assert rolling_mean(s, "2024-01-05", days=5) is None


# ── is_overheated ────────────────────────────────────────────────────────────

class TestIsOverheated:
    def test_above_threshold(self):
        assert is_overheated(0.06) is True

    def test_at_threshold(self):
        assert is_overheated(0.05) is True

    def test_below_threshold(self):
        assert is_overheated(0.04) is False

    def test_none_value(self):
        assert is_overheated(None) is False


# ── detect_peak ──────────────────────────────────────────────────────────────

class TestDetectPeak:
    def test_finds_peak_when_overheated(self):
        # 20 dias: cresce, picos no dia 15, depois cai
        vals = [0.02] * 5 + [0.04] * 5 + [0.10] * 3 + [0.06] * 7
        s = make_series("2024-01-01", vals)
        peak = detect_peak(s, "2024-01-20", lookback_days=14)
        assert peak is not None
        assert peak["value"] > 0.05

    def test_returns_none_if_no_overheat(self):
        # tudo abaixo de hot threshold
        s = make_series("2024-01-01", [0.01] * 20)
        peak = detect_peak(s, "2024-01-20", lookback_days=14)
        assert peak is None


# ── detect_drop ──────────────────────────────────────────────────────────────

class TestDetectDrop:
    def test_confirmed_drop(self):
        # picou em 0.10, caiu pra 0.05 (queda 50%, > 30% threshold)
        vals = [0.10] * 5 + [0.05] * 5
        s = make_series("2024-01-01", vals)
        assert detect_drop(s, "2024-01-10", peak_value=0.10, drop_pct=0.30) is True

    def test_no_drop_when_still_high(self):
        vals = [0.10] * 5 + [0.09] * 5  # so caiu 10%
        s = make_series("2024-01-01", vals)
        assert detect_drop(s, "2024-01-10", peak_value=0.10, drop_pct=0.30) is False

    def test_fake_reversal_blocked(self):
        # caiu pra 0.05 mas so em 1 dia (resto ainda alto)
        vals = [0.10] * 5 + [0.05] + [0.10] * 4
        s = make_series("2024-01-01", vals)
        # target_date e ultimo dia, rolling_5d sera ~0.09 (alto)
        assert detect_drop(s, "2024-01-10", peak_value=0.10, drop_pct=0.30) is False


# ── scan_signals ─────────────────────────────────────────────────────────────

class TestScanSignals:
    def test_detects_single_peak_drop_cycle(self):
        # Aquece 7 dias → cai 7 dias
        vals = [0.02] * 5 + [0.10] * 7 + [0.03] * 7
        s = make_series("2024-01-01", vals)
        triggers = scan_signals(s)
        assert len(triggers) >= 1

    def test_no_triggers_when_calm(self):
        s = make_series("2024-01-01", [0.01] * 30)
        assert scan_signals(s) == []

    def test_respects_min_gap_days(self):
        # 2 ciclos de overheat dentro de 10 dias - so deve gerar 1 trigger
        vals = ([0.02] * 5 + [0.10] * 3 + [0.02] * 3) * 2
        s = make_series("2024-01-01", vals)
        triggers = scan_signals(s, min_gap_days=14)
        # com 14d gap entre triggers, max 2 triggers
        if len(triggers) >= 2:
            from datetime import datetime
            d0 = datetime.fromisoformat(triggers[0]["date"]).date()
            d1 = datetime.fromisoformat(triggers[1]["date"]).date()
            assert (d1 - d0).days >= 14
