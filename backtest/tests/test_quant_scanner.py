"""TDD quant_scanner — prioridade quant-driven."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from quant_scanner import quant_priority, rank_candidates


WL = {
    "TIER_A_LIVE": [
        {"market": "ZECUSDT", "stop_atr": 3.0, "target_atr": 3.0,
         "sharpe": 5.31, "win_rate_pct": 56.6, "mean_r": 0.58,
         "pbo": 0.0, "wf_positive_folds": 3, "wf_total_folds": 5,
         "final_equity": 3.97},
    ],
    "TIER_B_PAPER": [
        {"market": "HYPEUSDT", "stop_atr": 3.0, "target_atr": 2.0,
         "sharpe": 12.23, "win_rate_pct": 73.5, "mean_r": 0.78,
         "pbo": 0.33, "wf_positive_folds": 0, "wf_total_folds": 5,
         "final_equity": 1.30},
    ],
    "TIER_C_SKIP": [
        {"market": "ETHUSDT", "stop_atr": 1.0, "target_atr": 2.0,
         "sharpe": -0.92, "win_rate_pct": 33.8, "mean_r": -0.07,
         "pbo": 0.05, "final_equity": 0.89},
    ],
}


def test_tier_a_qualified_live():
    r = quant_priority("ZECUSDT", 100, 5.0, 2.0, WL, mode="LIVE")
    assert r["qualified"]
    assert r["tier"] == "A"
    assert r["expected_sharpe"] == 5.31


def test_tier_b_blocked_in_live_mode():
    r = quant_priority("HYPEUSDT", 100, 5.0, 2.0, WL, mode="LIVE")
    assert not r["qualified"]


def test_tier_b_allowed_in_paper_mode():
    r = quant_priority("HYPEUSDT", 100, 5.0, 2.0, WL, mode="PAPER")
    assert r["qualified"]
    assert r["tier"] == "B"


def test_setup_calculation():
    r = quant_priority("ZECUSDT", 100, 5.0, 2.0, WL, mode="LIVE")
    # stop=3*5=15 abaixo: 100-15=85
    # target=3*5=15 acima: 100+15=115
    assert abs(r["setup"]["stop"] - 85.0) < 0.01
    assert abs(r["setup"]["target"] - 115.0) < 0.01
    assert r["setup"]["rr"] == 1.0


def test_not_in_whitelist():
    r = quant_priority("RANDUSDT", 100, 5.0, 2.0, WL, mode="LIVE")
    assert not r["qualified"]
    assert r["reason"] == "not_in_whitelist"


def test_invalid_atr():
    r = quant_priority("ZECUSDT", 100, 0, 2.0, WL, mode="LIVE")
    assert not r["qualified"]


def test_priority_score_factors_momentum():
    """Maior pct_change_24h -> maior priority (momentum favor)."""
    r_pos = quant_priority("ZECUSDT", 100, 5.0, +5.0, WL, mode="LIVE")
    r_neg = quant_priority("ZECUSDT", 100, 5.0, -5.0, WL, mode="LIVE")
    assert r_pos["priority_score"] > r_neg["priority_score"]


def test_rank_candidates_sorts_by_priority():
    cands = [
        {"market": "ETHUSDT", "current_price": 3000, "atr": 50, "pct_change_24h": 0},
        {"market": "ZECUSDT", "current_price": 100, "atr": 5, "pct_change_24h": 0},
        {"market": "HYPEUSDT", "current_price": 20, "atr": 2, "pct_change_24h": 0},
    ]
    r = rank_candidates(cands, WL, mode="LIVE")
    # ETH=C (not qualified), HYPE=B (not in LIVE), só ZEC qualifica
    assert len(r) == 1
    assert r[0]["market"] == "ZECUSDT"


def test_rank_candidates_paper_mode_includes_b():
    cands = [
        {"market": "ZECUSDT", "current_price": 100, "atr": 5, "pct_change_24h": 0},
        {"market": "HYPEUSDT", "current_price": 20, "atr": 2, "pct_change_24h": 0},
    ]
    r = rank_candidates(cands, WL, mode="PAPER")
    assert len(r) == 2
    # A tier weighted 1.0, B tier weighted 0.5; ZEC sharpe 5.31, HYPE 12.23
    # ZEC: 5.31*1.0*1.0 = 5.31
    # HYPE: 12.23*0.5*1.0 = 6.115
    # HYPE wins por priority
    assert r[0]["market"] == "HYPEUSDT"
