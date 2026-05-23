"""
test_param_sweep.py — TDD para sweep de parâmetros do signal_generator.
Garante que diferentes thresholds produzem resultados diferentes e ordenáveis.
"""
import pytest
from param_sweep import sweep_score_threshold, SweepResult


class TestSweepStructure:
    def test_sweep_result_has_required_fields(self):
        r = SweepResult(
            param_name="score_threshold",
            param_value=75.0,
            total_trades=500,
            win_rate=35.0,
            expectancy_r=0.20,
            profit_factor=1.4,
            max_drawdown_r=80.0,
            bull_expectancy=0.25,
            bear_expectancy=0.15,
        )
        assert r.param_name == "score_threshold"
        assert r.param_value == 75.0
        assert r.total_trades == 500

    def test_sweep_result_is_comparable_by_expectancy(self):
        a = SweepResult("score_threshold", 65, 1000, 30, 0.10, 1.1, 50, 0.05, 0.15)
        b = SweepResult("score_threshold", 80, 300, 40, 0.30, 1.5, 30, 0.35, 0.25)
        assert b.expectancy_r > a.expectancy_r


class TestSweepExecution:
    def test_sweep_runs_all_values(self):
        """Sweep deve produzir um SweepResult por valor testado."""
        results = sweep_score_threshold(
            market="BTCUSDT",
            period="1hour",
            date_from="2024-01-01",
            date_to="2024-02-01",  # janela curta para teste
            values=[65.0, 75.0, 85.0],
            filter_sideways=True,
            dry_run=True,  # não chama Supabase real
        )
        assert len(results) == 3
        assert all(r.param_name == "score_threshold" for r in results)
        assert sorted([r.param_value for r in results]) == [65.0, 75.0, 85.0]

    def test_sweep_higher_threshold_gives_fewer_trades(self):
        """Sanity check: threshold mais alto deve filtrar mais."""
        results = sweep_score_threshold(
            market="BTCUSDT",
            period="1hour",
            date_from="2024-01-01",
            date_to="2024-02-01",
            values=[65.0, 85.0],
            filter_sideways=True,
            dry_run=True,
        )
        by_value = {r.param_value: r for r in results}
        # Threshold 85 deve ter menos ou igual trades que 65
        assert by_value[85.0].total_trades <= by_value[65.0].total_trades


class TestSweepRanking:
    def test_best_by_expectancy(self):
        results = [
            SweepResult("score_threshold", 65, 1000, 30, 0.10, 1.1, 50, 0.05, 0.15),
            SweepResult("score_threshold", 75, 500, 35, 0.25, 1.4, 60, 0.30, 0.20),
            SweepResult("score_threshold", 85, 200, 42, 0.35, 1.6, 40, 0.40, 0.30),
        ]
        best = max(results, key=lambda r: r.expectancy_r)
        assert best.param_value == 85.0

    def test_filter_minimum_trades(self):
        """Excluir resultados com amostra estatística insuficiente."""
        results = [
            SweepResult("score_threshold", 65, 1000, 30, 0.10, 1.1, 50, 0.05, 0.15),
            SweepResult("score_threshold", 85, 50, 60, 0.80, 3.0, 20, 0.85, 0.75),  # n muito pequeno
        ]
        filtered = [r for r in results if r.total_trades >= 100]
        assert len(filtered) == 1
        assert filtered[0].param_value == 65.0
