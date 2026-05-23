"""
test_risk_adjusted_metrics.py — TDD para risk_adjusted_metrics.py

Cobertura:
  - Sharpe, Sortino, Calmar (anualizados)
  - Classification (EXCEPTIONAL/ELITE/PROFESSIONAL/RETAIL)
  - Overfit warning (Sharpe > 3)
  - Discount factor (conservador anti-overfit)
  - JSON schema do output final
"""
import math
import json
import pytest

from risk_adjusted_metrics import (
    sharpe_annualized,
    sortino_annualized,
    calmar_annualized,
    periods_per_year,
    classify_sharpe,
    discounted_sharpe,
    overfit_warning,
    build_run_report,
    build_aggregate_report,
)


# ----------------------------------------------------------------------------
# 1. Sharpe — cálculo com retornos conhecidos
# ----------------------------------------------------------------------------
def test_sharpe_with_known_returns():
    """Retornos simétricos de magnitude conhecida produzem Sharpe previsível."""
    # 10 trades alternados ±0.05R, ppy=365 (mensal-ish)
    r_series = [0.05, -0.05] * 50  # mean=0, std>0
    # Mean=0 => sharpe=0
    s = sharpe_annualized(r_series, n_trades=100, period_days=100, rf_rate=0.0)
    assert s == 0.0


def test_sharpe_positive_when_mean_positive():
    """Retornos com mean > 0 e variance > 0 dão Sharpe > 0."""
    r_series = [0.2, 0.1, 0.3, 0.15, 0.05, 0.2, 0.1, 0.25, 0.05, 0.15]
    s = sharpe_annualized(r_series, n_trades=10, period_days=30, rf_rate=0.0)
    assert s > 0


# ----------------------------------------------------------------------------
# 2. Sortino — diferenciado pelo downside
# ----------------------------------------------------------------------------
def test_sortino_diferentia_downside():
    """Sortino deve ser maior que Sharpe quando os ganhos têm mais variância que perdas."""
    # Ganhos voláteis, perdas pequenas e estáveis
    r_series = [1.0, 2.0, 3.0, -0.1, -0.1, -0.1, 4.0, 5.0]
    sh = sharpe_annualized(r_series, n_trades=8, period_days=30, rf_rate=0.0)
    so = sortino_annualized(r_series, n_trades=8, period_days=30, rf_rate=0.0)
    assert so > sh  # downside std é menor que std total => Sortino > Sharpe


# ----------------------------------------------------------------------------
# 3. Calmar — return anualizado / max drawdown
# ----------------------------------------------------------------------------
def test_calmar_basic_calculation():
    """Calmar = annualized_return / max_drawdown."""
    # ann_return 30%, max_dd 10% => calmar = 3.0
    c = calmar_annualized(annualized_return_pct=30.0, max_drawdown_pct=10.0)
    assert c == pytest.approx(3.0, rel=1e-6)


def test_calmar_zero_drawdown_returns_inf():
    """Calmar com drawdown zero retorna infinito (não erro)."""
    c = calmar_annualized(annualized_return_pct=20.0, max_drawdown_pct=0.0)
    assert math.isinf(c) or c > 1e6


# ----------------------------------------------------------------------------
# 4. Periods per year — anualização correta
# ----------------------------------------------------------------------------
def test_annualization_correta():
    """86 trades em 181 dias => ppy = (86/181)*365 ≈ 173.4."""
    ppy = periods_per_year(n_trades=86, period_days=181)
    assert ppy == pytest.approx(173.4, rel=1e-2)


def test_periods_per_year_handles_zero_days():
    """Período zero dias retorna 1 (não divide por zero)."""
    ppy = periods_per_year(n_trades=10, period_days=0)
    assert ppy == 1


# ----------------------------------------------------------------------------
# 5. Volatilidade zero / retornos constantes
# ----------------------------------------------------------------------------
def test_zero_volatility_returns_inf():
    """Série constante com mean > 0 e std = 0 retorna inf (não NaN)."""
    r_series = [0.1] * 20
    s = sharpe_annualized(r_series, n_trades=20, period_days=30, rf_rate=0.0)
    assert math.isinf(s) or s > 1e6


def test_zero_volatility_zero_mean_returns_zero():
    """Série zerada retorna 0, não NaN."""
    r_series = [0.0] * 20
    s = sharpe_annualized(r_series, n_trades=20, period_days=30, rf_rate=0.0)
    assert s == 0.0


# ----------------------------------------------------------------------------
# 6. Risk-free rate configurável
# ----------------------------------------------------------------------------
def test_risk_free_configurable():
    """rf=0 e rf>0 produzem valores diferentes."""
    r_series = [0.1, 0.15, 0.05, 0.2, 0.1, 0.12, 0.08, 0.15, 0.09, 0.11]
    s0 = sharpe_annualized(r_series, n_trades=10, period_days=30, rf_rate=0.0)
    s_rf = sharpe_annualized(r_series, n_trades=10, period_days=30, rf_rate=0.05)
    # Com rf > 0, Sharpe deve diminuir (mean - rf é menor)
    assert s_rf < s0


# ----------------------------------------------------------------------------
# 7. Classification — todas as faixas
# ----------------------------------------------------------------------------
def test_classification_all_buckets():
    """Classificação de cada faixa Sharpe."""
    assert classify_sharpe(3.5) == "EXCEPTIONAL"
    assert classify_sharpe(2.5) == "ELITE"
    assert classify_sharpe(1.5) == "PROFESSIONAL"
    assert classify_sharpe(0.5) == "RETAIL"
    # Bordas
    assert classify_sharpe(3.0) == "ELITE"  # > 3 é EXCEPTIONAL, exato 3 é ELITE
    assert classify_sharpe(2.0) == "PROFESSIONAL"
    assert classify_sharpe(1.0) == "PROFESSIONAL"
    assert classify_sharpe(0.0) == "RETAIL"
    assert classify_sharpe(-1.0) == "RETAIL"


# ----------------------------------------------------------------------------
# 8. Overfit warning — Sharpe > 3 acende alerta
# ----------------------------------------------------------------------------
def test_overfit_warning_above_threshold():
    """Sharpe > 3 sinaliza overfit_warning.sharpe_above_3 = True."""
    w = overfit_warning(3.5)
    assert w["sharpe_above_3"] is True
    assert "suspeito" in w["interpretation"].lower() or "overfit" in w["interpretation"].lower()

    w_ok = overfit_warning(2.5)
    assert w_ok["sharpe_above_3"] is False


# ----------------------------------------------------------------------------
# 9. Discount factor — Sharpe descontado conservador
# ----------------------------------------------------------------------------
def test_discounted_sharpe_calculation():
    """Sharpe descontado = raw * 0.5 (default)."""
    assert discounted_sharpe(2.85, factor=0.5) == pytest.approx(1.425, rel=1e-6)
    assert discounted_sharpe(4.0, factor=0.5) == 2.0
    # Factor parametrizável
    assert discounted_sharpe(3.0, factor=0.7) == pytest.approx(2.1, rel=1e-6)


# ----------------------------------------------------------------------------
# 10. JSON schema válido
# ----------------------------------------------------------------------------
def test_json_schema_valid():
    """build_run_report retorna dict com todos os campos do contrato."""
    r_series = [0.5, -0.3, 1.2, -0.4, 0.8, 0.2, -0.5, 1.0, 0.3, -0.2]
    run = build_run_report(
        run_id="test_run",
        r_series=r_series,
        period_days=60,
        max_drawdown_r=1.5,
        annualized_return_pct=25.0,
        max_drawdown_pct=8.0,
    )
    assert "run_id" in run
    assert "n_trades" in run
    assert "period_days" in run
    assert "ratios" in run
    assert "sharpe_annualized" in run["ratios"]
    assert "sortino_annualized" in run["ratios"]
    assert "calmar_annualized" in run["ratios"]
    assert "comparison_table" in run
    assert "classification" in run
    assert "overfit_warning" in run
    assert run["overfit_warning"]["sharpe_above_3"] in (True, False)


def test_aggregate_report_go_live_criterion():
    """Aggregate report calcula mediana dos 3 runs e aplica critério go-live."""
    runs = [
        {"ratios": {"sharpe_annualized": 2.0, "sortino_annualized": 3.0, "calmar_annualized": 1.5}},
        {"ratios": {"sharpe_annualized": 2.5, "sortino_annualized": 3.5, "calmar_annualized": 2.0}},
        {"ratios": {"sharpe_annualized": 3.0, "sortino_annualized": 4.0, "calmar_annualized": 2.5}},
    ]
    agg = build_aggregate_report(runs)
    assert "median" in agg
    assert agg["median"]["sharpe"] == 2.5  # mediana exata
    assert "go_live_criterion" in agg
    assert "median_sharpe_raw" in agg["go_live_criterion"]
    assert "median_sharpe_discounted" in agg["go_live_criterion"]
    assert "passed" in agg["go_live_criterion"]
    # 2.5 * 0.5 = 1.25 < 1.5 => não passa
    assert agg["go_live_criterion"]["median_sharpe_discounted"] == pytest.approx(1.25, rel=1e-6)
    assert agg["go_live_criterion"]["passed"] is False


def test_aggregate_passes_when_discounted_above_threshold():
    """Sharpe mediano alto o suficiente passa o critério."""
    runs = [
        {"ratios": {"sharpe_annualized": 3.0, "sortino_annualized": 4.0, "calmar_annualized": 2.0}},
        {"ratios": {"sharpe_annualized": 3.5, "sortino_annualized": 4.5, "calmar_annualized": 2.5}},
        {"ratios": {"sharpe_annualized": 3.2, "sortino_annualized": 4.2, "calmar_annualized": 2.2}},
    ]
    agg = build_aggregate_report(runs)
    # mediana = 3.2; descontado = 1.6 >= 1.5 => passa
    assert agg["go_live_criterion"]["passed"] is True
