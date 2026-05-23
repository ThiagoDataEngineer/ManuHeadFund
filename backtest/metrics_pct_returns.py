"""
metrics_pct_returns.py — Sharpe / DSR / PSR em DAILY RETURNS (não R-multiples).
Padrão Bailey & López de Prado 2014. Comparável cross-asset.

Diferença vs metrics_simons.py (legacy R-multiples):
- Entrada: daily_returns = [pct_return_dia1, pct_return_dia2, ...]
- Saída: Sharpe em escala daily-returns padrão (* sqrt(365) anualizado cripto)

Use em conjunto com equity_curve_from_trades:
    eq = build_equity_curve(trades, risk_pct=0.01)
    rets = daily_returns_from_equity(eq)
    s = sharpe_from_daily_returns(rets)
"""
import math
from typing import List
from scipy import stats
from constants import EULER_MASCHERONI


def annualizer_crypto() -> float:
    """Cripto trade 24/7 = 365 dias/ano."""
    return math.sqrt(365)


def _mean(xs: List[float]) -> float:
    return sum(xs) / len(xs) if xs else 0.0


def _std(xs: List[float], ddof: int = 1) -> float:
    if len(xs) < 2:
        return 0.0
    m = _mean(xs)
    var = sum((x - m) ** 2 for x in xs) / (len(xs) - ddof)
    return math.sqrt(var)


def _skewness(xs: List[float]) -> float:
    if len(xs) < 3:
        return 0.0
    n = len(xs)
    m = _mean(xs)
    s = _std(xs, ddof=0)
    if s == 0:
        return 0.0
    return (sum((x - m) ** 3 for x in xs) / n) / (s ** 3)


def _kurtosis(xs: List[float]) -> float:
    """Excess kurtosis (kurtosis - 3)."""
    if len(xs) < 4:
        return 0.0
    n = len(xs)
    m = _mean(xs)
    s = _std(xs, ddof=0)
    if s == 0:
        return 0.0
    return (sum((x - m) ** 4 for x in xs) / n) / (s ** 4) - 3.0


def sharpe_from_daily_returns(returns: List[float], annualizer: float = None) -> float:
    """
    Sharpe annualized de daily returns.
    Default annualizer = sqrt(365) para cripto.
    Retorna 0 se < 2 returns. Retorna inf se std=0 (constantes).
    """
    if len(returns) < 2:
        return 0.0
    if annualizer is None:
        annualizer = annualizer_crypto()
    m = _mean(returns)
    s = _std(returns, ddof=1)
    if s == 0:
        return float('inf') if m > 0 else (float('-inf') if m < 0 else 0.0)
    return annualizer * m / s


def psr_from_daily_returns(returns: List[float], sharpe_benchmark: float = 0.0,
                            annualizer: float = None,
                            _benchmark_is_per_period: bool = False) -> float:
    """
    Probabilistic Sharpe Ratio (Bailey & López de Prado 2012).
    Probabilidade do Sharpe verdadeiro > benchmark dado o sample.

    Convenção: sharpe_benchmark é ANUALIZADO por padrão (consistente com Sharpe
    reportado por sharpe_from_daily_returns). Internamente convertemos para
    per-period dividindo por annualizer, pois a fórmula PSR opera em SR per-period.

    Formula: PSR = CDF_normal( (SR_hat - SR_benchmark) * sqrt(n-1) /
                                sqrt(1 - skew*SR + (kurt-1)/4 * SR^2) )
    """
    n = len(returns)
    if n < 2:
        return 0.5
    if annualizer is None:
        annualizer = annualizer_crypto()
    sr_hat = sharpe_from_daily_returns(returns, annualizer=1.0)  # non-annualized para fórmula
    benchmark_per_period = sharpe_benchmark if _benchmark_is_per_period else sharpe_benchmark / annualizer
    skew = _skewness(returns)
    kurt_excess = _kurtosis(returns)
    kurt = kurt_excess + 3
    sr_diff = sr_hat - benchmark_per_period
    denom = math.sqrt(max(1e-10, 1 - skew * sr_hat + (kurt - 1) / 4 * sr_hat ** 2))
    z = sr_diff * math.sqrt(n - 1) / denom
    return float(stats.norm.cdf(z))


def dsr_from_daily_returns(returns: List[float], n_trials: int = 50,
                            sharpe_benchmark: float = 0.0,
                            sample_variance_sharpes: float = 0.5,
                            annualizer: float = None) -> float:
    """
    Deflated Sharpe Ratio (Bailey & López de Prado 2014).
    Penaliza por múltiplos testes (n_trials).

    Convenção: sample_variance_sharpes é ANUALIZADO (0.5 = var de SR anuais
    típicos numa busca de estratégias). Internamente convertemos para per-period
    via division por annualizer², porque PSR opera em SR não-anualizado.

    SR_0 = sqrt(var_sharpes_per_period) * ((1-γ)·Z⁻¹(1-1/N) + γ·Z⁻¹(1-1/(N·e)))
    DSR = PSR usando SR_0 como benchmark
    """
    if n_trials <= 1:
        return psr_from_daily_returns(returns, sharpe_benchmark)

    if annualizer is None:
        annualizer = annualizer_crypto()

    # Converte variance anualizada → per-period (PSR usa SR não-anualizado)
    var_per_period = sample_variance_sharpes / (annualizer ** 2)

    gamma = EULER_MASCHERONI
    z1 = stats.norm.ppf(1 - 1.0 / n_trials)
    z2 = stats.norm.ppf(1 - 1.0 / (n_trials * math.e))
    sr_0 = math.sqrt(var_per_period) * ((1 - gamma) * z1 + gamma * z2)

    # sharpe_benchmark vem em ANUALIZADO por convenção — converte
    benchmark_per_period = sharpe_benchmark / annualizer
    sr_0_final = max(benchmark_per_period, sr_0)
    return psr_from_daily_returns(returns, sharpe_benchmark=sr_0_final,
                                   annualizer=annualizer,
                                   _benchmark_is_per_period=True)
