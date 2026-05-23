"""TDD short_rules — 16 testes (4 por regra)."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from short_rules import (
    rule_a_sma200_break,
    rule_b_rally_failure,
    rule_c_late_cycle_mining_stress,
    rule_d_consecutive_weakness,
    evaluate_all_rules,
)


# ── Rule A: SMA200 break ──────────────────────────────────────────────

def test_rule_a_triggers_clean_break():
    """Preço -5% SMA200, ADX 30, -DI > +DI por 10 → TRUE"""
    f = {"dist_sma200": -0.05, "adx": 30, "di_diff": 10}
    assert rule_a_sma200_break(f) is True


def test_rule_a_no_trigger_weak_adx():
    """ADX 20 (fraco) → FALSE mesmo com SMA200 break"""
    f = {"dist_sma200": -0.05, "adx": 20, "di_diff": 10}
    assert rule_a_sma200_break(f) is False


def test_rule_a_no_trigger_above_sma():
    """Preço ACIMA SMA200 → FALSE"""
    f = {"dist_sma200": 0.03, "adx": 30, "di_diff": 10}
    assert rule_a_sma200_break(f) is False


def test_rule_a_no_trigger_capitulation():
    """Já em capitulação (-25%) → FALSE (rule_a é break recente, não capitulação)"""
    f = {"dist_sma200": -0.25, "adx": 30, "di_diff": 10}
    assert rule_a_sma200_break(f) is False


# ── Rule B: Rally failure ─────────────────────────────────────────────

def test_rule_b_triggers_rally_low_vol():
    """Rally 7% mas vol 0.6× → TRUE (rally sem força)"""
    f = {"rally_strength_3d": 0.07, "vol_ratio_20d": 0.6, "dist_sma200": 0.05}
    assert rule_b_rally_failure(f) is True


def test_rule_b_no_trigger_high_vol():
    """Rally 7% com vol 1.5× → FALSE (rally com força = bull legítimo)"""
    f = {"rally_strength_3d": 0.07, "vol_ratio_20d": 1.5, "dist_sma200": 0.05}
    assert rule_b_rally_failure(f) is False


def test_rule_b_no_trigger_small_rally():
    """Rally 2% → FALSE (não é blow-off)"""
    f = {"rally_strength_3d": 0.02, "vol_ratio_20d": 0.6, "dist_sma200": 0.05}
    assert rule_b_rally_failure(f) is False


def test_rule_b_no_trigger_hyper_bull():
    """Rally 7% mas preço 20% acima SMA200 → FALSE (bull-strong, não shortear)"""
    f = {"rally_strength_3d": 0.07, "vol_ratio_20d": 0.6, "dist_sma200": 0.20}
    assert rule_b_rally_failure(f) is False


# ── Rule C: Late cycle + mining stress ───────────────────────────────

def test_rule_c_triggers_post_pico_mining_stress():
    """Mês 20 + mining 1.1× + preço abaixo SMA200 → TRUE"""
    f = {"months_post_halving": 20, "mining_ratio": 1.1, "dist_sma200": -0.05}
    assert rule_c_late_cycle_mining_stress(f) is True


def test_rule_c_no_trigger_early_cycle():
    """Mês 10 (mid-bull) → FALSE"""
    f = {"months_post_halving": 10, "mining_ratio": 1.1, "dist_sma200": -0.05}
    assert rule_c_late_cycle_mining_stress(f) is False


def test_rule_c_no_trigger_high_mining_ratio():
    """Mês 20 mas mining 2× (lucrativo) → FALSE"""
    f = {"months_post_halving": 20, "mining_ratio": 2.0, "dist_sma200": -0.05}
    assert rule_c_late_cycle_mining_stress(f) is False


def test_rule_c_no_trigger_above_sma200():
    """Mês 20 + mining 1.1 mas preço acima SMA200 → FALSE"""
    f = {"months_post_halving": 20, "mining_ratio": 1.1, "dist_sma200": 0.10}
    assert rule_c_late_cycle_mining_stress(f) is False


# ── Rule D: Consecutive weakness ──────────────────────────────────────

def test_rule_d_triggers_5_red():
    """5 dias vermelhos consecutivos + preço abaixo SMA200 → TRUE"""
    f = {"consecutive_red_days": 5, "dist_sma200": -0.03}
    assert rule_d_consecutive_weakness(f) is True


def test_rule_d_no_trigger_3_red():
    """3 dias vermelhos → FALSE (precisa 4+)"""
    f = {"consecutive_red_days": 3, "dist_sma200": -0.03}
    assert rule_d_consecutive_weakness(f) is False


def test_rule_d_no_trigger_above_sma():
    """5 red mas preço acima SMA200 → FALSE (consolidação em bull)"""
    f = {"consecutive_red_days": 5, "dist_sma200": 0.05}
    assert rule_d_consecutive_weakness(f) is False


def test_evaluate_all_returns_4_keys():
    """evaluate_all_rules retorna dict com 4 regras"""
    f = {"dist_sma200": -0.05, "adx": 30, "di_diff": 10,
         "rally_strength_3d": 0.07, "vol_ratio_20d": 0.6,
         "months_post_halving": 20, "mining_ratio": 1.1,
         "consecutive_red_days": 5}
    result = evaluate_all_rules(f)
    assert len(result) == 4
    assert all(isinstance(v, bool) for v in result.values())
