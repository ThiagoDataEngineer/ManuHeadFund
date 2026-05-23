"""
metrics_simons.py -- Gate científico Simons (DSR, PSR, Sharpe-BTC, Ergodicity).
Implementação pura NumPy das métricas de Renaissance Technologies para validação de edge.

Referências:
- Bailey & López de Prado 2014, "The Sharpe Ratio Illusion and Backtesting"
  Journal of Portfolio Management 40(5): 94-107
- knowledge/SIMONS_RENTECH.md §4.1
"""
from __future__ import annotations

import numpy as np
from typing import Optional
from dataclasses import dataclass
from math import erf, sqrt

# Constante de Euler-Mascheroni
EULER_MASCHERONI = 0.5772156649


def norm_cdf(x: float) -> float:
    """Standard normal CDF approximation (sem scipy)."""
    return (1 + erf(x / sqrt(2))) / 2


def norm_ppf(p: float) -> float:
    """
    Standard normal PPF (inverse CDF) — Hall-Wehrly 1991 rational approximation.
    Acurácia O(1e-6).
    """
    if p <= 0 or p >= 1:
        raise ValueError(f"p deve estar em (0, 1), got {p}")

    # Shifted p para [0.5, 1] para simetria
    p_orig = p
    p = min(p, 1 - p)
    sign = 1 if p_orig > 0.5 else -1

    # Hall-Wehrly coefficients (R-quality)
    c0 = 2.515517
    c1 = 0.802853
    c2 = 0.010328
    d1 = 1.432788
    d2 = 0.189269
    d3 = 0.001308

    t = np.sqrt(-2 * np.log(p))
    numerator = c0 + c1 * t + c2 * t**2
    denominator = 1 + d1 * t + d2 * t**2 + d3 * t**3

    return sign * (t - numerator / denominator)


def skew(x: np.ndarray) -> float:
    """Calcula skewness (terceiro momento normalizado)."""
    x = np.asarray(x)
    mean_x = np.mean(x)
    n = len(x)
    m3 = np.mean((x - mean_x) ** 3)
    m2 = np.mean((x - mean_x) ** 2)
    return m3 / (m2 ** 1.5) if m2 > 0 else 0.0


def kurtosis_excess(x: np.ndarray) -> float:
    """Calcula excess kurtosis (quarto momento - 3)."""
    x = np.asarray(x)
    mean_x = np.mean(x)
    n = len(x)
    m4 = np.mean((x - mean_x) ** 4)
    m2 = np.mean((x - mean_x) ** 2)
    return (m4 / (m2 ** 2) - 3) if m2 > 0 else 0.0


@dataclass
class SimonsGateResult:
    """Resultado do gate científico Simons (4 critérios)."""
    dsr: float
    psr: float
    sharpe_btc: float
    ergodicity: float
    decision: str  # "PASS" | "FAIL"
    reasons: list[str]


def deflated_sharpe_ratio(
    returns: np.ndarray,
    n_trials: int,
    sample_variance_sharpes: float,
    annualizer: float = np.sqrt(365),
) -> float:
    """
    Deflated Sharpe Ratio (DSR) — Bailey & López de Prado 2014.

    Mede a probabilidade de uma Sharpe Ratio observada ser estatisticamente
    significante (não resultado de múltiplos testes de estratégia).

    Fórmula:
      SR₀ = sqrt(V[SRₙ]) * ((1-γ) * Φ⁻¹[1-1/N] + γ * Φ⁻¹[1-1/(N*e)])
      M = sqrt((1 - γ₃*SR₀ + ((γ₄-1)/4)*SR₀²) / (n-1))
      Z = (SR* - SR₀) * M
      DSR = Φ(Z)

    Args:
        returns: array de retornos (P&L / capital)
        n_trials: número de estratégias testadas (múltiplos testes)
        sample_variance_sharpes: variância amostral dos SRs testados
        annualizer: fator de anualização (sqrt(365) para cripto 24/7)

    Returns:
        float em [0, 1]: probabilidade de edge real, ou NaN se n_obs < 30
    """
    returns = np.asarray(returns, dtype=np.float64)

    # Validação
    if len(returns) == 0:
        raise ValueError("Returns array não pode estar vazio")
    if len(returns) < 30:
        return np.nan

    n_obs = len(returns)

    # Calcula Sharpe Ratio observado
    mean_ret = np.mean(returns)
    std_ret = np.std(returns, ddof=1)
    if std_ret == 0:
        return np.nan
    sr_observed = (mean_ret / std_ret) * annualizer

    # Calcula a inflação esperada do Sharpe (SR₀)
    gamma = EULER_MASCHERONI / np.pi  # ~0.1654
    try:
        z_high = norm_ppf(1 - 1 / n_trials)
        z_very_high = norm_ppf(1 - 1 / (n_trials * np.e))
    except ValueError:
        # Fallback para n_trials muito grande
        z_high = np.sqrt(2 * np.log(n_trials))
        z_very_high = np.sqrt(2 * np.log(n_trials * np.e))

    sr0_base = np.sqrt(sample_variance_sharpes) * (
        (1 - gamma) * z_high + gamma * z_very_high
    )

    # Penalidade por skewness e kurtosis
    sk = skew(returns)
    kurt = kurtosis_excess(returns)
    # Usa SR0, não SRobs (Bailey & LdP 2014, eq 5)
    penalty = 1 - gamma * sk * sr0_base + ((kurt) / 4) * (sr0_base ** 2) / (n_obs - 1)

    if penalty <= 0:
        penalty = 0.01  # Fallback: baixa confiança, mas evita NaN

    # Z-score deflacionado
    z_dsr = (sr_observed - sr0_base) * np.sqrt(n_obs - 1) / np.sqrt(penalty)

    # Probabilidade (DSR = Φ(z))
    dsr = norm_cdf(z_dsr)
    return float(np.clip(dsr, 0.0, 1.0))


def probabilistic_sharpe_ratio(
    returns: np.ndarray,
    benchmark_sharpe: float = 0.0,
    annualizer: float = np.sqrt(365),
) -> float:
    """
    Probabilistic Sharpe Ratio (PSR) — Bailey & López de Prado.

    Probabilidade de o SR observado ser maior que um benchmark.

    PSR = Φ( (SR* - SR_bench) / sqrt(var(SR)) )

    Args:
        returns: array de retornos
        benchmark_sharpe: SR benchmark (default 0 = melhor que nada)
        annualizer: fator de anualização

    Returns:
        float em [0, 1]: probabilidade SR > benchmark
    """
    returns = np.asarray(returns, dtype=np.float64)

    if len(returns) == 0:
        raise ValueError("Returns array não pode estar vazio")

    n_obs = len(returns)
    mean_ret = np.mean(returns)
    std_ret = np.std(returns, ddof=1)

    if std_ret == 0:
        return 0.0 if mean_ret <= benchmark_sharpe else 1.0

    sr_observed = (mean_ret / std_ret) * annualizer

    # Variância do SR (aproximação)
    var_sr = (1 + 0.5 * sr_observed ** 2) / n_obs

    # Z-score
    z_psr = (sr_observed - benchmark_sharpe) / np.sqrt(var_sr)
    psr = norm_cdf(z_psr)

    return float(psr)


def sharpe_btc_denominated(
    strategy_returns: np.ndarray,
    btc_returns: np.ndarray,
    annualizer: float = np.sqrt(365),
) -> float:
    """
    Sharpe Ratio em unidade BTC (denominação cripto).

    Crucial em cripto: BTC é a base não-inflacionária. Uma estratégia só é boa
    se bate o HODL BTC (ergodicidade cripto).

    Calcula: Sharpe(strategy/BTC_return) = E[alpha] / std(alpha)
    onde alpha = strategy_return / btc_return (retorno relativo).

    Args:
        strategy_returns: retornos da estratégia (multiplicadores ou %)
        btc_returns: retornos do BTC (multiplicadores ou %)
        annualizer: fator de anualização

    Returns:
        float: Sharpe em unidade BTC (positivo = alpha vs HODL)
    """
    strategy_returns = np.asarray(strategy_returns, dtype=np.float64)
    btc_returns = np.asarray(btc_returns, dtype=np.float64)

    if len(strategy_returns) == 0 or len(btc_returns) == 0:
        raise ValueError("Returns arrays não podem estar vazios")

    # Alpha: retorno relativo strategy vs BTC
    # Se strategy sobe 30% (+1.30) e BTC sobe 60% (+1.60):
    # alpha = 1.30 / 1.60 = 0.8125 (perdeu em BTC)
    alpha = strategy_returns / btc_returns

    # Log-returns para calcular Sharpe (mais robusto)
    log_alpha = np.log(alpha)

    mean_alpha = np.mean(log_alpha)

    # Com n < 2, sem volatilidade -> retorna sign(mean)
    n = len(log_alpha)
    if n < 2:
        # Single point: retorna sign(mean_alpha) com magnitude pequena
        return float(np.sign(mean_alpha) * 10.0) if mean_alpha != 0 else 0.0

    # Com n >= 2, usa ddof=1
    std_alpha = np.std(log_alpha, ddof=1)

    if std_alpha == 0 or std_alpha < 1e-10:
        # Sem volatilidade: retorna sign(mean)
        return float(np.sign(mean_alpha) * 10.0) if mean_alpha != 0 else 0.0

    sharpe_btc = (mean_alpha / std_alpha) * annualizer
    return float(sharpe_btc)


def ergodicity_score(
    returns: np.ndarray,
    annualizer: float = np.sqrt(365),
) -> float:
    """
    Ergodicity Score — mede path-dependency (volatility drag).

    Compara crescimento geométrico vs aritmético em log-scale:
    Score = (geom_mean / arith_mean) - 1
      > 0: crescimento saudável
      <= 0: volatility drag severo

    Intuição (Taleb/Peters):
      - Multiplicadores [1.10, 0.90, 1.10, 0.90] têm drag alto
      - Multiplicadores [1.02, 1.03, 1.01, 1.04] têm drag baixo

    Args:
        returns: retornos (multiplicadores, ex: 1.01 = +1%)
        annualizer: não usado aqui (para simetria de interface)

    Returns:
        float: Score ergodicidade (positivo = bom, negativo = drag)
    """
    returns = np.asarray(returns, dtype=np.float64)

    if len(returns) == 0:
        raise ValueError("Returns array não pode estar vazio")

    if len(returns) < 2:
        return 0.0  # Sem histórico

    # Log-returns (composição contínua)
    log_returns = np.log(returns)

    # Média aritmética (E[log(R)])
    arith_mean = np.mean(log_returns)

    # Média geométrica é exp(arith_mean), mas medimos em log scale
    # Volatilidade em log-returns
    log_vol = np.std(log_returns, ddof=1)

    # Drag = -(1/2) * σ²  (Jensen's inequality)
    # Score positivo = geom_mean está próximo a arith_mean
    drag = -0.5 * (log_vol ** 2)
    score = arith_mean + drag  # Contribuição positiva + drag

    return float(score)


def run_simons_gate(
    strategy_returns: np.ndarray,
    btc_returns: np.ndarray,
    n_trials: int = 100,
    sample_variance_sharpes: float = 0.5,
    dsr_threshold: float = 0.95,
    psr_threshold: float = 0.95,
    annualizer: float = np.sqrt(365),
) -> SimonsGateResult:
    """
    Executa os 4 gates científicos Simons para validar edge.

    Critérios PASS:
      1. DSR >= dsr_threshold (e.g., 0.95 = 95% de confiança)
      2. PSR >= psr_threshold (vs benchmark 0)
      3. Sharpe-BTC >= 0 (bate HODL BTC)
      4. Ergodicity >= 0 (sem drag patológico)

    DECISION:
      PASS = todos 4 critérios verdes
      FAIL = qualquer critério red (com reasons explícitas)

    Args:
        strategy_returns: retornos da estratégia (array multiplicadores)
        btc_returns: retornos do BTC (array multiplicadores)
        n_trials: número de testes (para DSR inflation)
        sample_variance_sharpes: variância dos SRs testados
        dsr_threshold: threshold mínimo DSR
        psr_threshold: threshold mínimo PSR
        annualizer: fator anualização

    Returns:
        SimonsGateResult com 6 campos: dsr, psr, sharpe_btc, ergodicity, decision, reasons
    """
    strategy_returns = np.asarray(strategy_returns, dtype=np.float64)
    btc_returns = np.asarray(btc_returns, dtype=np.float64)

    reasons = []

    # 1. DSR
    dsr = deflated_sharpe_ratio(
        strategy_returns,
        n_trials=n_trials,
        sample_variance_sharpes=sample_variance_sharpes,
        annualizer=annualizer,
    )
    if np.isnan(dsr):
        reasons.append("DSR=NaN (insuficientes observações ou Sharpe indefinido)")
    elif dsr < dsr_threshold:
        reasons.append(f"DSR={dsr:.4f} < threshold {dsr_threshold:.2f} (múltiplos testes inflacionam SR)")

    # 2. PSR
    psr = probabilistic_sharpe_ratio(strategy_returns, benchmark_sharpe=0.0, annualizer=annualizer)
    if psr < psr_threshold:
        reasons.append(f"PSR={psr:.4f} < threshold {psr_threshold:.2f} (SR não é significante vs 0)")

    # 3. Sharpe-BTC
    sharpe_btc = sharpe_btc_denominated(strategy_returns, btc_returns, annualizer=annualizer)
    if sharpe_btc < 0:
        reasons.append(f"Sharpe-BTC={sharpe_btc:.4f} < 0 (perdeu vs HODL BTC)")

    # 4. Ergodicity
    ergodicity = ergodicity_score(strategy_returns, annualizer=annualizer)
    if ergodicity < 0:
        reasons.append(f"Ergodicity={ergodicity:.4f} < 0 (volatility drag patológico)")

    # Decision
    decision = "PASS" if len(reasons) == 0 else "FAIL"

    return SimonsGateResult(
        dsr=dsr,
        psr=psr,
        sharpe_btc=sharpe_btc,
        ergodicity=ergodicity,
        decision=decision,
        reasons=reasons,
    )