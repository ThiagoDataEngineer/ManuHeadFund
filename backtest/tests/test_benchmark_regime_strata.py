"""SUITE B — TDD strict para benchmark_regime_strata.py.

Analisa performance LONG/SHORT por regime e decide melhor direcao.
"""
import pytest
from benchmark_regime_strata import (
    metrics_per_regime,
    best_direction,
    edge_strength,
    aggregate_results,
    validate_json_schema,
)


# ── Fixtures ────────────────────────────────────────────────────────────────

def _trades(regime, direction, results_r):
    """Lista de trade-dicts com regime+direction+result_r prontos para group-by."""
    return [{"regime": regime, "direction": direction, "result_r": r} for r in results_r]


# ── SUITE B — 8 testes ──────────────────────────────────────────────────────

class TestBenchmarkRegimeStrata:

    def test_metrics_per_regime_isolation(self):
        """Trades agrupados por regime tem n, exp, pf isolados."""
        trades = (
            _trades("BULL_STRONG", "LONG", [1, 1, -1, 1, -1]) +
            _trades("BEAR_WEAK", "SHORT", [-1, -1, 1, -1])
        )
        result = metrics_per_regime(trades)
        assert "BULL_STRONG" in result
        assert "BEAR_WEAK" in result
        assert result["BULL_STRONG"]["LONG"]["trades"] == 5
        assert result["BEAR_WEAK"]["SHORT"]["trades"] == 4
        # Isolamento: BULL_STRONG nao deve ter SHORT
        assert "SHORT" not in result["BULL_STRONG"] or result["BULL_STRONG"]["SHORT"]["trades"] == 0

    def test_best_direction_logic_long(self):
        """long_exp +1R vs short_exp -0.5R: melhor direcao = LONG."""
        assert best_direction(long_exp=1.0, short_exp=-0.5) == "LONG"

    def test_best_direction_logic_short(self):
        """long_exp -0.3R vs short_exp +0.8R: melhor direcao = SHORT."""
        assert best_direction(long_exp=-0.3, short_exp=0.8) == "SHORT"

    def test_best_direction_avoid(self):
        """Ambos abaixo de +0.3R = AVOID (sem edge significativo)."""
        assert best_direction(long_exp=0.1, short_exp=0.2) == "AVOID"
        assert best_direction(long_exp=-0.1, short_exp=0.0) == "AVOID"

    def test_best_direction_both(self):
        """Ambos acima de +0.3R = BOTH (edge nos dois lados)."""
        assert best_direction(long_exp=0.5, short_exp=0.4) == "BOTH"

    def test_edge_strength_categories(self):
        """exp>=+0.5 = STRONG; +0.3 a +0.5 = MEDIUM; +0.1 a +0.3 = WEAK; <+0.1 = NONE."""
        assert edge_strength(0.8) == "STRONG"
        assert edge_strength(0.5) == "STRONG"
        assert edge_strength(0.35) == "MEDIUM"
        assert edge_strength(0.30) == "MEDIUM"
        assert edge_strength(0.20) == "WEAK"
        assert edge_strength(0.05) == "NONE"
        assert edge_strength(-0.5) == "NONE"

    def test_aggregate_days_pct_sums_to_100(self):
        """Soma de days_pct entre regimes deve dar ~100% (tolerancia 1%)."""
        regime_days = {
            "BULL_STRONG": 800, "BULL_WEAK": 600, "SIDEWAYS": 700,
            "TRANSITION_UP": 100, "TRANSITION_DOWN": 100,
            "BEAR_WEAK": 400, "BEAR_STRONG": 200, "CAPITULATION": 100,
        }
        agg = aggregate_results(regime_days=regime_days, regime_metrics={})
        total_pct = sum(r["days_pct"] for r in agg["by_regime"])
        assert abs(total_pct - 100.0) < 1.0

    def test_json_schema_valid(self):
        """Output completo bate com schema esperado."""
        regime_days = {"BULL_STRONG": 1000, "SIDEWAYS": 1000}
        regime_metrics = {
            "BULL_STRONG": {
                "LONG":  {"trades": 50, "exp": 0.6, "pf": 2.0},
                "SHORT": {"trades": 10, "exp": -0.2, "pf": 0.6},
            },
            "SIDEWAYS": {
                "LONG":  {"trades": 30, "exp": 0.35, "pf": 1.4},
                "SHORT": {"trades": 30, "exp": 0.40, "pf": 1.5},
            },
        }
        result = aggregate_results(regime_days=regime_days, regime_metrics=regime_metrics)
        assert validate_json_schema(result) is True
        # Estrutura
        assert "by_regime" in result
        assert "go_criterion" in result
        # Cada by_regime tem todos os campos
        for r in result["by_regime"]:
            assert "regime" in r
            assert "days_total" in r
            assert "days_pct" in r
            assert "long_metrics" in r
            assert "short_metrics" in r
            assert "best_direction" in r
            assert "edge_strength" in r
        # go_criterion
        assert "rule" in result["go_criterion"]
        assert "regimes_with_edge" in result["go_criterion"]
        assert "regimes_total" in result["go_criterion"]
        assert "passed" in result["go_criterion"]
