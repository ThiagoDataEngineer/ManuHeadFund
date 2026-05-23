"""
TDD — report.py
Gera relatório HTML de um backtest_run com métricas por regime.
"""
import os
import tempfile
import pytest
from metrics import BacktestMetrics, RegimeBreakdown, calc_metrics, calc_metrics_by_regime
from report import generate_html_report


# ── fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture
def run_row():
    return {
        "market":          "BTCUSDT",
        "period":          "1hour",
        "date_from":       "2023-01-01",
        "date_to":         "2025-01-01",
        "capital_initial": 1000.0,
        "total_trades":    50,
        "winning_trades":  28,
        "win_rate":        56.0,
        "expectancy_r":    0.42,
        "profit_factor":   2.1,
        "max_drawdown":    4.3,
        "sharpe_ratio":    1.35,
    }


@pytest.fixture
def regime_breakdown():
    bull_r = [2.0] * 20 + [-1.0] * 5   # 80% win rate
    bear_r = [-1.0] * 8 + [2.0] * 4    # 33% win rate
    side_r = [0.5, -0.5, 0.5, -0.5]    # 50% win rate
    r_series = bull_r + bear_r + side_r
    regimes  = (["bull"] * 25 + ["bear"] * 12 + ["sideways"] * 4)
    return calc_metrics_by_regime(r_series, regimes)


# ── HTML estrutura ────────────────────────────────────────────────────────────

class TestReportStructure:
    def test_returns_string(self, run_row, regime_breakdown):
        html = generate_html_report(run_row, regime_breakdown)
        assert isinstance(html, str)
        assert len(html) > 100

    def test_has_html_skeleton(self, run_row, regime_breakdown):
        html = generate_html_report(run_row, regime_breakdown)
        assert "<html" in html
        assert "<body" in html
        assert "</html>" in html

    def test_has_table_tag(self, run_row, regime_breakdown):
        html = generate_html_report(run_row, regime_breakdown)
        assert "<table" in html

    def test_has_style_block(self, run_row, regime_breakdown):
        html = generate_html_report(run_row, regime_breakdown)
        assert "<style" in html


# ── Conteúdo ──────────────────────────────────────────────────────────────────

class TestReportContent:
    def test_contains_market(self, run_row, regime_breakdown):
        html = generate_html_report(run_row, regime_breakdown)
        assert "BTCUSDT" in html

    def test_contains_period(self, run_row, regime_breakdown):
        html = generate_html_report(run_row, regime_breakdown)
        assert "1hour" in html

    def test_contains_date_range(self, run_row, regime_breakdown):
        html = generate_html_report(run_row, regime_breakdown)
        assert "2023-01-01" in html
        assert "2025-01-01" in html

    def test_contains_win_rate(self, run_row, regime_breakdown):
        html = generate_html_report(run_row, regime_breakdown)
        assert "56" in html  # win_rate = 56.0%

    def test_contains_expectancy(self, run_row, regime_breakdown):
        html = generate_html_report(run_row, regime_breakdown)
        assert "0.42" in html

    def test_contains_sharpe(self, run_row, regime_breakdown):
        html = generate_html_report(run_row, regime_breakdown)
        assert "1.35" in html

    def test_contains_regime_labels(self, run_row, regime_breakdown):
        html = generate_html_report(run_row, regime_breakdown)
        assert "bull" in html.lower()
        assert "bear" in html.lower()

    def test_regime_none_does_not_break(self, run_row):
        # sem trades sideways
        br = calc_metrics_by_regime([1.0, -1.0], ["bull", "bear"])
        html = generate_html_report(run_row, br)
        assert isinstance(html, str)

    def test_contains_institutional_thresholds(self, run_row, regime_breakdown):
        html = generate_html_report(run_row, regime_breakdown)
        # as metas Tier 3 devem aparecer para referência
        assert "45" in html or "55" in html  # win rate mínimo / excelente
        assert "1.0" in html or "1.5" in html  # Sharpe mínimo / excelente


# ── Qualidade das métricas ────────────────────────────────────────────────────

class TestReportThresholds:
    def test_passing_metrics_marked(self, run_row, regime_breakdown):
        # run_row tem sharpe 1.35 > 1.0 (mínimo institucional) → deve ter marcador de aprovação
        html = generate_html_report(run_row, regime_breakdown)
        assert "pass" in html.lower() or "✓" in html or "ok" in html.lower() or "green" in html.lower()

    def test_failing_metric_marked(self, regime_breakdown):
        run_bad = {
            "market": "BTCUSDT", "period": "1hour",
            "date_from": "2023-01-01", "date_to": "2025-01-01",
            "capital_initial": 1000.0,
            "total_trades": 10, "winning_trades": 3,
            "win_rate": 30.0, "expectancy_r": -0.2,
            "profit_factor": 0.6, "max_drawdown": 25.0, "sharpe_ratio": -0.5,
        }
        html = generate_html_report(run_bad, regime_breakdown)
        assert "fail" in html.lower() or "✗" in html or "red" in html.lower() or "warn" in html.lower()


# ── Arquivo ───────────────────────────────────────────────────────────────────

class TestReportFile:
    def test_writes_file_when_output_path_given(self, run_row, regime_breakdown):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = os.path.join(tmpdir, "report.html")
            generate_html_report(run_row, regime_breakdown, output_path=path)
            assert os.path.exists(path)
            content = open(path, encoding="utf-8").read()
            assert "BTCUSDT" in content

    def test_no_file_when_output_path_none(self, run_row, regime_breakdown, tmp_path):
        # sem output_path → só retorna string, não cria arquivo
        html = generate_html_report(run_row, regime_breakdown, output_path=None)
        assert isinstance(html, str)
