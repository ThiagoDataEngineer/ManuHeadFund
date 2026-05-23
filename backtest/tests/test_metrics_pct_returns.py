"""
test_metrics_pct_returns.py — TDD: Sharpe/DSR/PSR em DAILY RETURNS (não R-multiples).
Padrão Bailey & López de Prado 2014. Comparável cross-asset (BTC, XRP, ETH).
"""
import sys, os, math
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from metrics_pct_returns import (
    sharpe_from_daily_returns,
    dsr_from_daily_returns,
    psr_from_daily_returns,
    annualizer_crypto,
)


def test_annualizer_crypto():
    """Cripto trade 365 dias/ano (24/7), não 252."""
    assert abs(annualizer_crypto() - math.sqrt(365)) < 1e-9


def test_sharpe_basic():
    """Sharpe de 30 returns ~0.5% mean, ~1% std = (0.005 / 0.01) * sqrt(365)."""
    returns = [0.005] * 30
    s = sharpe_from_daily_returns(returns)
    # std=0 (constante) → Sharpe inf. Função deve handle.
    assert s == float('inf') or s > 100


def test_sharpe_zero_mean():
    """Mean zero = Sharpe 0."""
    returns = [0.01, -0.01, 0.005, -0.005] * 10
    s = sharpe_from_daily_returns(returns)
    assert abs(s) < 0.1  # próximo de 0


def test_sharpe_positive_returns():
    """Positive Sharpe quando retorno medio > 0."""
    returns = [0.01, 0.005, 0.015, -0.002, 0.008] * 10
    s = sharpe_from_daily_returns(returns)
    assert s > 0


def test_sharpe_empty():
    """Empty returns retorna 0."""
    assert sharpe_from_daily_returns([]) == 0.0
    assert sharpe_from_daily_returns([0.01]) == 0.0  # apenas 1 return


def test_psr_formula():
    """PSR aumenta com Sharpe e N, decresce com skew negativo/kurt alto."""
    returns = [0.01] * 100 + [-0.005] * 50  # Sharpe positivo
    p = psr_from_daily_returns(returns, sharpe_benchmark=0.0)
    assert 0.0 <= p <= 1.0
    # Sharpe positivo vs benchmark 0 = PSR > 0.5
    assert p > 0.5


def test_psr_negative_sharpe():
    """Sharpe negativo vs benchmark 0 = PSR < 0.5."""
    returns = [-0.01] * 100 + [0.005] * 50
    p = psr_from_daily_returns(returns, sharpe_benchmark=0.0)
    assert p < 0.5


def test_dsr_penalizes_multiple_trials():
    """DSR <= PSR quando n_trials > 1 (deflation por multiple testing).
    benchmark anualizado 0 vs SR_0 inflado por multiple trials → DSR menor."""
    returns = [0.005, 0.01, -0.003, 0.008, 0.002] * 50
    psr = psr_from_daily_returns(returns, sharpe_benchmark=0.0)
    dsr = dsr_from_daily_returns(returns, n_trials=20, sharpe_benchmark=0.0,
                                  sample_variance_sharpes=0.5)
    assert dsr <= psr  # DSR penaliza


def test_dsr_more_trials_lower():
    """Mais trials = DSR menor (SR_0 monotonicamente cresce com N)."""
    returns = [0.005, 0.01, -0.003, 0.008, 0.002] * 50
    dsr_20  = dsr_from_daily_returns(returns, n_trials=20, sharpe_benchmark=0.0,
                                      sample_variance_sharpes=0.5)
    dsr_200 = dsr_from_daily_returns(returns, n_trials=200, sharpe_benchmark=0.0,
                                      sample_variance_sharpes=0.5)
    assert dsr_200 <= dsr_20
