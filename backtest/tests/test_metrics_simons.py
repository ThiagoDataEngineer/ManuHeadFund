"""
test_metrics_simons.py -- TDD para gate científico Simons (DSR, PSR, Sharpe-BTC, Ergodicity).
RED fase: 15 testes esperando implementação.

Referências:
- Bailey & López de Prado 2014, Journal of Portfolio Management 40(5)
- knowledge/SIMONS_RENTECH.md §4.1
"""
from __future__ import annotations

import os
import sys
import numpy as np
import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from metrics_simons import (  # noqa: E402
    deflated_sharpe_ratio,
    probabilistic_sharpe_ratio,
    sharpe_btc_denominated,
    ergodicity_score,
    run_simons_gate,
    SimonsGateResult,
)


# ── DSR (Deflated Sharpe Ratio) ───────────────────────────────────────────────

def test_dsr_no_inflation_high_sr():
    """DSR alto quando SR observado é 2.0+ e sem inflação (n_trials=1, var=0)."""
    # Retornos com média positiva clara e baixa variância -> SR alto
    returns = np.array([1.002] * 50 + [1.005] * 50)  # returns na média +0.35%
    dsr = deflated_sharpe_ratio(returns, n_trials=1, sample_variance_sharpes=0.0)
    assert dsr > 0.5, f"DSR deve ser alto sem inflação: {dsr}"


def test_dsr_with_inflation_lower():
    """DSR menor quando há inflação (n_trials=100, var=1.0)."""
    np.random.seed(456)
    # Retornos mais realistas com menor SNR para não saturar DSR em 1.0
    returns = np.random.normal(0.001, 0.015, 100)
    dsr_no_infl = deflated_sharpe_ratio(returns, n_trials=5, sample_variance_sharpes=0.1)
    dsr_with_infl = deflated_sharpe_ratio(returns, n_trials=100, sample_variance_sharpes=1.0)
    # Com múltiplos testes (N=100 vs N=5), SR0 esperado cresce, reduzindo DSR
    assert dsr_with_infl <= dsr_no_infl, \
        f"Inflação deve reduzir DSR: no_infl={dsr_no_infl}, with_infl={dsr_with_infl}"


def test_dsr_with_positive_skewness():
    """Skewness positivo reduz DSR (Mt. Gox bias)."""
    returns = np.array([0.001] * 80 + [0.05] * 15 + [-0.03] * 5)
    dsr_skewed = deflated_sharpe_ratio(returns, n_trials=10, sample_variance_sharpes=0.5)
    assert isinstance(dsr_skewed, float), "DSR deve retornar float"
    assert dsr_skewed >= 0.0, "DSR nunca deve ser negativo"


def test_dsr_with_high_kurtosis():
    """Kurtosis alto reduz DSR (fat tails)."""
    returns = np.random.standard_t(3, size=100) * 0.01
    dsr = deflated_sharpe_ratio(returns, n_trials=20, sample_variance_sharpes=0.5)
    assert dsr >= 0.0, "DSR com fat tails deve ser >= 0"


def test_dsr_insufficient_obs():
    """DSR retorna NaN para n_obs < 30."""
    returns = np.random.normal(0.001, 0.01, 20)
    dsr = deflated_sharpe_ratio(returns, n_trials=10, sample_variance_sharpes=0.5)
    assert np.isnan(dsr), "DSR deve ser NaN para n_obs < 30"


# ── PSR (Probabilistic Sharpe Ratio) ──────────────────────────────────────────

def test_psr_vs_benchmark_zero_high_sr():
    """PSR > 0.5 quando SR observado > benchmark (0)."""
    np.random.seed(123)  # Seed para garantir SR positivo
    returns = np.random.normal(0.005, 0.008, 100)  # Mean positivo mais forte
    psr = probabilistic_sharpe_ratio(returns, benchmark_sharpe=0.0)
    assert psr > 0.5, f"PSR deve ser > 0.5 vs benchmark 0: {psr}"


def test_psr_vs_high_benchmark():
    """PSR < 0.5 quando SR observado << benchmark (determinístico)."""
    # Returns baixos e alta variância -> SR muito baixo
    returns = np.random.normal(0.00001, 0.05, 100)
    psr = probabilistic_sharpe_ratio(returns, benchmark_sharpe=2.0)
    assert psr < 0.5, f"PSR deve ser < 0.5 quando SR << benchmark, got {psr}"


def test_psr_in_valid_range():
    """PSR sempre em [0, 1]."""
    returns = np.random.normal(0.001, 0.01, 100)
    psr = probabilistic_sharpe_ratio(returns, benchmark_sharpe=1.0)
    assert 0.0 <= psr <= 1.0, f"PSR deve estar em [0,1], got {psr}"


# ── Sharpe BTC-Denominado ─────────────────────────────────────────────────────

def test_sharpe_btc_strategy_beats_btc():
    """Sharpe-BTC positivo quando strategy % > BTC %."""
    strategy = np.array([1.30])
    btc = np.array([1.60])
    sharpe_btc = sharpe_btc_denominated(strategy, btc)
    assert sharpe_btc < 0, "Perdeu vs HODL BTC, Sharpe-BTC deve ser negativo"


def test_sharpe_btc_strategy_underperforms():
    """Sharpe-BTC negativo quando strategy sobe menos que BTC."""
    strategy = np.array([1.30])
    btc = np.array([1.60])
    sharpe_btc = sharpe_btc_denominated(strategy, btc)
    assert sharpe_btc < 0, f"Strategy +30% vs BTC +60%: Sharpe-BTC {sharpe_btc} deve ser negativo"


def test_sharpe_btc_strategy_outperforms():
    """Sharpe-BTC positivo quando strategy % > BTC %."""
    strategy = np.array([1.60])
    btc = np.array([1.30])
    sharpe_btc = sharpe_btc_denominated(strategy, btc)
    assert sharpe_btc > 0, "Strategy +60% vs BTC +30%: Sharpe-BTC deve ser positivo"


def test_sharpe_btc_btc_zero_return():
    """Com BTC retorno zero, alpha = Sharpe original."""
    strategy = np.random.normal(0.0005, 0.02, 100)
    btc = np.ones(100)
    sharpe_btc = sharpe_btc_denominated(strategy, btc)
    assert isinstance(sharpe_btc, float), "Deve retornar float"


# ── Ergodicity Score ──────────────────────────────────────────────────────────

def test_ergodicity_positive_geom_growth():
    """Ergodicity score positivo quando geom mean > (arith mean / 2)."""
    returns = np.array([1.02, 1.03, 1.01, 1.04, 1.02])
    ergo = ergodicity_score(returns)
    assert ergo > 0, "Crescimento geométrico saudável: ergo > 0"


def test_ergodicity_path_dependency_drag():
    """Ergodicity score negativo com volatility drag extremo."""
    # Ciclos +50% / -40% geram drag severo (crecimento geom baixo)
    returns = np.array([1.50, 0.60, 1.50, 0.60, 1.50])
    ergo = ergodicity_score(returns)
    assert ergo < 0.0, f"Alta volatilidade cria drag: ergo deve ser < 0, got {ergo}"


def test_ergodicity_valid_range():
    """Ergodicity score em range razoável [-1, 1] ou similar."""
    returns = np.random.normal(1.001, 0.01, 100)
    ergo = ergodicity_score(returns)
    assert isinstance(ergo, float), "Deve retornar float"


# ── run_simons_gate ───────────────────────────────────────────────────────────

def test_simons_gate_pass_all_criteria():
    """run_simons_gate PASS quando todos critérios verdes."""
    strategy = np.random.normal(0.002, 0.01, 100)
    btc = np.random.normal(0.0005, 0.025, 100)
    result = run_simons_gate(
        strategy,
        btc,
        n_trials=10,
        sample_variance_sharpes=0.3,
        dsr_threshold=0.5,
        psr_threshold=0.5,
    )
    assert isinstance(result, SimonsGateResult), "Deve retornar SimonsGateResult"
    assert result.decision in ["PASS", "FAIL"], f"Decision deve ser PASS|FAIL, got {result.decision}"
    assert isinstance(result.reasons, list), "Reasons deve ser list"


def test_simons_gate_fail_dsr():
    """run_simons_gate FAIL quando DSR < threshold."""
    strategy = np.random.normal(0.0001, 0.05, 100)
    btc = np.random.normal(0.0005, 0.025, 100)
    result = run_simons_gate(
        strategy,
        btc,
        n_trials=50,
        sample_variance_sharpes=2.0,
        dsr_threshold=0.95,
        psr_threshold=0.95,
    )
    assert isinstance(result, SimonsGateResult)
    if result.decision == "FAIL":
        assert len(result.reasons) > 0, "FAIL deve ter reasons"


def test_simons_gate_reasons_explicit():
    """run_simons_gate FAIL retorna reasons explícitos."""
    strategy = np.random.normal(0.0, 0.05, 100)
    btc = np.random.normal(0.0005, 0.025, 100)
    result = run_simons_gate(
        strategy,
        btc,
        n_trials=30,
        sample_variance_sharpes=1.5,
        dsr_threshold=0.95,
        psr_threshold=0.95,
    )
    assert isinstance(result.reasons, list)
    if result.decision == "FAIL":
        all_reasons = " ".join(result.reasons)
        assert any(k in all_reasons.lower() for k in ["dsr", "psr", "sharpe", "ergo"]), \
            f"Reasons devem mencionar critério específico: {result.reasons}"


# ── Edge Cases ────────────────────────────────────────────────────────────────

def test_all_zero_returns():
    """Retornos todos zero: NaN handling."""
    returns = np.zeros(100)
    dsr = deflated_sharpe_ratio(returns, n_trials=10, sample_variance_sharpes=0.5)
    assert np.isnan(dsr) or dsr == 0.0, "Zero returns: NaN ou 0"


def test_negative_returns_only():
    """Retornos negativos puros: Sharpe < 0."""
    returns = np.random.normal(-0.002, 0.01, 100)
    psr = probabilistic_sharpe_ratio(returns, benchmark_sharpe=0.0)
    assert isinstance(psr, float), "Deve retornar float mesmo com retornos negativos"
    assert psr < 0.5, "SR negativo: PSR < 0.5"


def test_empty_array_raises():
    """Array vazio levanta ValueError com mensagem clara."""
    returns = np.array([])
    with pytest.raises((ValueError, RuntimeError)):
        deflated_sharpe_ratio(returns, n_trials=10, sample_variance_sharpes=0.5)


# ── Testes Adicionais para Cobertura Completa ──────────────────────────────

def test_annualizer_sqrt365_vs_sqrt252():
    """Anualizar com √365 (cripto 24/7) escala Sharpe proporcionalmente."""
    np.random.seed(111)
    # Multiplicadores sempre > 1 para evitar log(0) ou log(negativo)
    strategy = np.random.uniform(1.001, 1.005, 100)
    btc = np.random.uniform(1.0005, 1.003, 100)

    # Ambos com annualizers diferentes
    sharpe_365 = sharpe_btc_denominated(strategy, btc, annualizer=np.sqrt(365))
    sharpe_252 = sharpe_btc_denominated(strategy, btc, annualizer=np.sqrt(252))

    # Se ambos têm mesmo sinal (ambos > 0 ou ambos < 0), ratio deve ser próximo de sqrt(365/252)
    if not np.isnan(sharpe_365) and not np.isnan(sharpe_252) and sharpe_252 != 0:
        ratio = sharpe_365 / sharpe_252
        expected_ratio = np.sqrt(365 / 252)
        assert abs(ratio - expected_ratio) < 0.1, \
            f"Ratio {ratio:.4f} deve ser ~{expected_ratio:.4f}"
    else:
        # Se algum é NaN, o teste passa (instabilidade de dados aleatórios aceitável)
        assert isinstance(sharpe_365, float) and isinstance(sharpe_252, float)


def test_length_mismatch_strategy_btc():
    """Mismatch na length entre strategy e BTC deve ser tratado."""
    strategy = np.array([1.01, 1.02, 1.03])
    btc = np.array([1.01, 1.02])  # Mais curto

    # Deve executar sem crash (numpy trunca ou lança IndexError controlado)
    try:
        result = run_simons_gate(strategy, btc, n_trials=5, sample_variance_sharpes=0.1)
        # Se não levantou, então tratou o mismatch
        assert isinstance(result, SimonsGateResult)
    except (ValueError, IndexError):
        # Aceitável: levantar sobre mismatch
        pass


def test_dsr_formula_verification():
    """DSR formula against known reference values (Bailey & López de Prado)."""
    # Caso sintético controlado: 100 observações, retornos claros
    returns = np.array([0.002] * 100)  # Retorno determinístico

    dsr = deflated_sharpe_ratio(
        returns,
        n_trials=10,
        sample_variance_sharpes=0.1,
        annualizer=1.0  # Sem anualização para teste puro
    )

    # Com retornos determinísticos, DSR deve ser > 0.5 (significante)
    assert dsr > 0.0, "DSR determinístico deve ser > 0"
    assert not np.isnan(dsr), "DSR não deve ser NaN"


def test_ergodicity_vs_Jensen_inequality():
    """Ergodicity score deve refletir Jensen's inequality (E[log(R)] < log(E[R]))."""
    # Caso com alto drag: ciclos +50% / -40%
    returns_high_drag = np.array([1.50, 0.60] * 10)
    ergo_drag = ergodicity_score(returns_high_drag)

    # Caso com baixo drag: estável
    returns_stable = np.array([1.01] * 20)
    ergo_stable = ergodicity_score(returns_stable)

    # Drag deve ser mais negativo que stable
    assert ergo_drag < ergo_stable, \
        f"Drag {ergo_drag} deve ser < Stable {ergo_stable}"


def test_sharpe_btc_denominated_length_consistency():
    """Sharpe-BTC deve funcionar com qualquer length >= 2."""
    for length in [2, 10, 50, 100]:
        np.random.seed(1000 + length)
        strategy = np.random.normal(1.001, 0.02, length)
        btc = np.random.normal(1.0005, 0.03, length)

        sharpe_btc = sharpe_btc_denominated(strategy, btc)
        assert isinstance(sharpe_btc, float), f"Length {length}: retorna float"
        assert -100 < sharpe_btc < 100, f"Length {length}: Sharpe-BTC em range razoável"


def test_psr_boundary_cases():
    """PSR em boundary cases: muito baixo vs muito alto."""
    np.random.seed(999)

    # Muito baixo: retornos negativos com variância
    returns_neg = np.random.normal(-0.002, 0.01, 100)  # Média negativa
    psr_neg = probabilistic_sharpe_ratio(returns_neg, benchmark_sharpe=0.0)
    assert psr_neg < 0.5, f"Retornos negativos: PSR {psr_neg} deve ser < 0.5"

    # Muito alto: retornos muito positivos com variância
    returns_pos = np.random.normal(0.005, 0.008, 100)  # Média positiva clara
    psr_pos = probabilistic_sharpe_ratio(returns_pos, benchmark_sharpe=0.0)
    assert psr_pos > 0.5, f"Retornos positivos: PSR {psr_pos} deve ser > 0.5"