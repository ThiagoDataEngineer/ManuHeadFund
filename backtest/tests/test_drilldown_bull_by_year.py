"""TDD drilldown BULL_STRONG / BULL_WEAK por ano (2023, 2024, 2025).

Investiga quebra do edge LONG-only nos regimes BULL no holdout.
"""
import pytest
from drilldown_bull_by_year import (
    filter_bull_regimes,
    split_by_year,
    metrics_for,
    compare_holdout_vs_train,
    diagnose_break_pattern,
    extract_loser_pattern,
    build_drilldown_report,
    validate_schema,
)


def _trade(year, regime, direction="LONG", r=1.0, entry_price=100.0, hour=0):
    return {
        "entry_ts": f"{year}-06-15T{hour:02d}:00:00+00:00",
        "regime": regime,
        "direction": direction,
        "result_r": r,
        "entry_price": entry_price,
        "exit_reason": "TARGET" if r > 0 else "STOP",
    }


# ─────────────────────────────────────────────────────────────────────────────
# Suite TDD — drilldown
# ─────────────────────────────────────────────────────────────────────────────

class TestDrilldownBullByYear:

    def test_filter_bull_regimes_only(self):
        """filter_bull_regimes mantem apenas BULL_STRONG e BULL_WEAK."""
        trades = [
            _trade(2023, "BULL_STRONG"),
            _trade(2023, "BULL_WEAK"),
            _trade(2023, "BEAR_WEAK"),
            _trade(2023, "SIDEWAYS"),
            _trade(2023, "TRANSITION_UP"),
        ]
        result = filter_bull_regimes(trades)
        assert len(result) == 2
        assert {t["regime"] for t in result} == {"BULL_STRONG", "BULL_WEAK"}

    def test_split_by_year_buckets_correctly(self):
        """split_by_year separa em buckets por ano com base em entry_ts."""
        trades = [_trade(2023, "BULL_STRONG"), _trade(2024, "BULL_STRONG"), _trade(2025, "BULL_WEAK")]
        result = split_by_year(trades)
        assert set(result.keys()) == {2023, 2024, 2025}
        assert len(result[2023]) == 1
        assert len(result[2024]) == 1
        assert len(result[2025]) == 1

    def test_metrics_for_basic(self):
        """metrics_for retorna trades/exp/pf/wr."""
        rs = [1.0, 1.0, -1.0, 1.0, -1.0]
        trades = [_trade(2023, "BULL_STRONG", r=r) for r in rs]
        m = metrics_for(trades)
        assert m["trades"] == 5
        assert abs(m["exp"] - 0.2) < 1e-6
        assert m["wr"] == 60.0
        assert m["pf"] > 0

    def test_metrics_for_empty(self):
        """metrics_for([]) retorna zeros sem crashar."""
        m = metrics_for([])
        assert m["trades"] == 0 and m["exp"] == 0.0 and m["pf"] == 0.0

    def test_compare_holdout_vs_train_delta(self):
        """compare_holdout_vs_train retorna delta exp/pf vs train baseline."""
        train_metrics = {"trades": 100, "exp": 0.40, "pf": 1.60, "wr": 35.0}
        holdout_metrics = {"trades": 30, "exp": 0.10, "pf": 1.05, "wr": 28.0}
        delta = compare_holdout_vs_train(train_metrics, holdout_metrics)
        assert abs(delta["delta_exp"] - (-0.30)) < 1e-6
        assert abs(delta["delta_pf"] - (-0.55)) < 1e-6
        assert delta["degraded"] is True

    def test_compare_holdout_not_degraded(self):
        """Holdout exp >= train → degraded=False."""
        train_metrics = {"trades": 100, "exp": 0.30, "pf": 1.4, "wr": 30.0}
        holdout_metrics = {"trades": 50, "exp": 0.45, "pf": 1.7, "wr": 35.0}
        delta = compare_holdout_vs_train(train_metrics, holdout_metrics)
        assert delta["degraded"] is False

    def test_diagnose_mild_regime_artifact_2025_only(self):
        """Diagnostico: so 2025 quebra, 2023+2024 OK = MILD_REGIME_ARTIFACT."""
        per_year = {
            2023: {"exp": 0.40, "trades": 80},
            2024: {"exp": 0.38, "trades": 90},
            2025: {"exp": -0.10, "trades": 50},
        }
        d = diagnose_break_pattern(per_year, train_exp=0.36)
        assert d == "MILD_REGIME_ARTIFACT"

    def test_diagnose_structural_all_years(self):
        """Diagnostico: 2023+2024+2025 todos quebrados = STRUCTURAL_BREAK."""
        per_year = {
            2023: {"exp": -0.05, "trades": 80},
            2024: {"exp": 0.02, "trades": 90},
            2025: {"exp": -0.10, "trades": 50},
        }
        d = diagnose_break_pattern(per_year, train_exp=0.36)
        assert d == "STRUCTURAL_BREAK"

    def test_diagnose_mixed_pattern(self):
        """Diagnostico: 1 ano ok + 2 quebrados (nao so 2025) = MIXED."""
        per_year = {
            2023: {"exp": 0.40, "trades": 80},     # ok
            2024: {"exp": -0.08, "trades": 90},    # quebra
            2025: {"exp": -0.12, "trades": 50},    # quebra
        }
        d = diagnose_break_pattern(per_year, train_exp=0.36)
        assert d == "MIXED"

    def test_extract_loser_pattern_returns_text(self):
        """extract_loser_pattern retorna string nao-vazia descrevendo padrao."""
        losers = [_trade(2025, "BULL_STRONG", r=-1.0, entry_price=90000 + i*100, hour=i % 24)
                  for i in range(20)]
        pattern = extract_loser_pattern(losers)
        assert isinstance(pattern, str) and len(pattern) > 10

    def test_extract_loser_pattern_empty(self):
        """Sem losers → retorna texto indicativo, nao crash."""
        pattern = extract_loser_pattern([])
        assert isinstance(pattern, str)

    def test_build_drilldown_report_schema(self):
        """Output completo bate com schema esperado."""
        trades_train = [_trade(2020, "BULL_STRONG", r=0.5) for _ in range(50)]
        trades_holdout = (
            [_trade(2023, "BULL_STRONG", r=0.3) for _ in range(20)] +
            [_trade(2024, "BULL_STRONG", r=0.2) for _ in range(20)] +
            [_trade(2025, "BULL_STRONG", r=-0.5) for _ in range(20)] +
            [_trade(2023, "BULL_WEAK", r=0.4) for _ in range(15)] +
            [_trade(2024, "BULL_WEAK", r=0.3) for _ in range(15)] +
            [_trade(2025, "BULL_WEAK", r=-0.3) for _ in range(15)]
        )
        report = build_drilldown_report(trades_train, trades_holdout)
        assert validate_schema(report) is True
        assert "metricas_por_ano" in report
        assert "ano_pior" in report
        assert "razao" in report
        assert "padrao_trades_perdedores" in report
        assert "diagnostico" in report
        assert report["diagnostico"] in ("MILD_REGIME_ARTIFACT", "STRUCTURAL_BREAK", "MIXED")
