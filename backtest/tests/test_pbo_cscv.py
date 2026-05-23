"""TDD PBO/CSCV gate (López de Prado AFML cap 11)."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from pbo_cscv import pbo_score


def test_robust_strategy_low_pbo():
    """Config com edge real claro vs outras = best em todos os splits."""
    matrix = [
        [3.0, 3.1, 2.9, 3.0, 3.05, 3.0],   # config 0 sempre best
        [1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
        [0.8, 0.9, 0.85, 0.95, 0.9, 0.9],
        [0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
    ]
    r = pbo_score(matrix)
    assert r["valid"]
    assert r["pbo"] < 0.5


def test_overfit_strategy_high_pbo():
    """Config 0 ganha apenas em períodos pares (clear overfit pattern)."""
    matrix = [
        [3.0, -1.0, 3.0, -1.0, 3.0, -1.0],  # winner em IS pares apenas
        [0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
        [0.4, 0.4, 0.4, 0.4, 0.4, 0.4],
        [0.3, 0.3, 0.3, 0.3, 0.3, 0.3],
    ]
    r = pbo_score(matrix)
    assert r["valid"]
    # PBO alto porque best IS varia conforme split
    assert r["pbo"] > 0.3


def test_invalid_few_periods():
    matrix = [[1.0, 1.0, 1.0]]
    r = pbo_score(matrix)
    assert not r["valid"]


def test_invalid_one_config():
    matrix = [[1.0, 1.0, 1.0, 1.0, 1.0]]
    r = pbo_score(matrix)
    assert not r["valid"]


def test_verdict_label():
    """Strategy claramente robusta retorna ROBUST."""
    matrix = [
        [2.0, 2.1, 1.9, 2.0, 2.05, 2.0],
        [1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
        [0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
        [0.3, 0.3, 0.3, 0.3, 0.3, 0.3],
    ]
    r = pbo_score(matrix)
    assert r["valid"]
    # Best (config 0) é sempre best → PBO=0, ROBUST
    assert "ROBUST" in r["verdict"] or "OK" in r["verdict"]
