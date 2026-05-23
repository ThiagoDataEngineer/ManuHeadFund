"""
test_meta_label_short.py -- TDD: meta-labeling 2 etapas (Lopez de Prado AFML cap 3).

Filosofia: PRIMARY classifica direcao; SECONDARY classifica P(win).
           Trade so executa se SECONDARY P(win) >= threshold.

Aplicado a SHORT em BEAR_STRONG: resgata o SHORT BTC que falhou 0/4
no refino 2026-05-18.
"""
from __future__ import annotations

import os
import sys

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from meta_label_short import (  # noqa: E402
    compute_meta_features,
    meta_label_predict,
    apply_meta_filter,
    MetaLabelConfig,
)


def _mk_signal(regime="BEAR_STRONG", funding_z=2.0, oi_delta_pct=-0.05,
               dow="Thursday", atr_pct=0.04, session_hr_brt=14):
    return {
        "regime": regime,
        "funding_z": funding_z,
        "oi_delta_pct": oi_delta_pct,
        "dow": dow,
        "atr_pct": atr_pct,
        "session_hr_brt": session_hr_brt,
        "direction": "short",
    }


class TestComputeMetaFeatures:
    def test_returns_dict_with_required_keys(self):
        sig = _mk_signal()
        feats = compute_meta_features(sig)
        assert isinstance(feats, dict)
        assert "regime_score" in feats
        assert "funding_extreme" in feats
        assert "oi_capitulation" in feats
        assert "dow_score" in feats

    def test_funding_extreme_high_when_z_above_2(self):
        feats = compute_meta_features(_mk_signal(funding_z=3.5))
        assert feats["funding_extreme"] >= 1

    def test_funding_extreme_zero_when_z_neutral(self):
        feats = compute_meta_features(_mk_signal(funding_z=0.5))
        assert feats["funding_extreme"] == 0

    def test_oi_capitulation_when_oi_drops_more_than_3pct(self):
        feats = compute_meta_features(_mk_signal(oi_delta_pct=-0.05))
        assert feats["oi_capitulation"] == 1

    def test_dow_score_thursday_higher_for_short(self):
        feats_thu = compute_meta_features(_mk_signal(dow="Thursday"))
        feats_mon = compute_meta_features(_mk_signal(dow="Monday"))
        assert feats_thu["dow_score"] >= feats_mon["dow_score"]


class TestMetaLabelPredict:
    def test_returns_p_win_in_zero_one(self):
        feats = compute_meta_features(_mk_signal())
        p = meta_label_predict(feats)
        assert 0.0 <= p <= 1.0

    def test_high_confluence_returns_p_above_05(self):
        # BEAR_STRONG + funding extreme + OI capitulation + Thursday = setup A+
        feats = compute_meta_features(_mk_signal(
            regime="BEAR_STRONG", funding_z=3.5, oi_delta_pct=-0.05, dow="Thursday"
        ))
        p = meta_label_predict(feats)
        assert p > 0.5

    def test_low_confluence_returns_p_below_05(self):
        # BULL_STRONG + no funding extreme + OI flat + Monday = SHORT ruim
        feats = compute_meta_features(_mk_signal(
            regime="BULL_STRONG", funding_z=0.5, oi_delta_pct=0.01, dow="Monday"
        ))
        p = meta_label_predict(feats)
        assert p < 0.5


class TestApplyMetaFilter:
    def test_blocks_signal_below_threshold(self):
        sig = _mk_signal(regime="BULL_STRONG", funding_z=0.5)
        cfg = MetaLabelConfig(p_win_threshold=0.55)
        result = apply_meta_filter(sig, cfg)
        assert result["passes"] is False
        assert result["p_win"] < 0.55

    def test_passes_signal_above_threshold(self):
        sig = _mk_signal(regime="BEAR_STRONG", funding_z=3.5,
                          oi_delta_pct=-0.05, dow="Thursday")
        cfg = MetaLabelConfig(p_win_threshold=0.55)
        result = apply_meta_filter(sig, cfg)
        assert result["passes"] is True
        assert result["p_win"] >= 0.55

    def test_returns_p_win_and_passes_keys(self):
        sig = _mk_signal()
        cfg = MetaLabelConfig()
        result = apply_meta_filter(sig, cfg)
        assert "p_win" in result
        assert "passes" in result
        assert "features" in result
