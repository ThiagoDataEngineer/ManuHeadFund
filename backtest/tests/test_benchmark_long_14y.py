"""
test_benchmark_long_14y.py — TDD strict para benchmark_long_14y.py

PHASE 1 — RED: 13 testes escritos antes de qualquer implementação.

Cobertura:
  - load de dados BTCUSD Bitstamp 14 anos (skip gracioso se indisponível)
  - split de trades por ano
  - métricas agregadas full-period
  - métricas por ano (n, exp, pf, max_dd_r, regime_dominant)
  - ranking worst/best 3 anos
  - % de anos positivos
  - Sharpe annualizado por ano
  - regime dominante por ano (BULL/BEAR/SIDEWAYS)
  - handling de anos faltantes
  - GO criterion (70% anos positivos + total PF >= 1.5)
  - validação de schema JSON

NÃO MODIFICA: db.py, signal_generator.py, metrics.py.
"""
import os
import math
import json
import pytest
from typing import Dict, List

# Importações do módulo a ser implementado (PHASE 2)
from benchmark_long_14y import (
    split_trades_by_year,
    calc_aggregate_metrics,
    calc_per_year_metrics,
    rank_worst_years,
    rank_best_years,
    positive_years_pct,
    sharpe_annualized_year,
    classify_regime_dominant,
    evaluate_go_criterion,
    build_long_14y_report,
)


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

def _trade(year: int, result_r: float, regime: str = "bull") -> Dict:
    """Cria um trade sintético com timestamp dentro do ano."""
    return {
        "entry_ts": f"{year}-06-15T12:00:00+00:00",
        "exit_ts":  f"{year}-06-16T12:00:00+00:00",
        "result_r": result_r,
        "regime":   regime,
        "direction": "LONG",
    }


def _candle(ts: str, close: float) -> Dict:
    return {"ts": ts, "open": close, "high": close, "low": close, "close": close, "volume": 1000.0}


# ============================================================================
# TEST 1 — Data load gracioso (skip se indisponível)
# ============================================================================
def test_14y_data_loads_or_skip_gracefully():
    """Tenta carregar BTCUSD Bitstamp 2014-2025; skip se < 2000 candles."""
    if not (os.environ.get("SUPABASE_URL") and
            (os.environ.get("SUPABASE_SERVICE_KEY") or os.environ.get("SUPABASE_ANON_KEY"))):
        pytest.skip("SUPABASE_* env vars not set")

    try:
        from db import Database
        key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
        db = Database(url=os.environ["SUPABASE_URL"], key=key)
        candles = db.get_candles("BTCUSD", "1hour", "2014-01-01", "2025-05-01")
        if len(candles) < 2000:
            pytest.skip(f"data unavailable: only {len(candles)} candles")
        assert len(candles) >= 2000
    except Exception as e:
        pytest.skip(f"data unavailable: {e}")


# ============================================================================
# TEST 2 — Split de trades por ano
# ============================================================================
def test_year_bucket_split_correct():
    """1000 trades distribuídos em 2014-2025 → dict {year: [trades]} com soma=1000."""
    trades = []
    distribution = {2014: 50, 2015: 80, 2016: 70, 2017: 120, 2018: 100, 2019: 90,
                    2020: 110, 2021: 130, 2022: 95, 2023: 85, 2024: 70}  # soma = 1000
    for year, count in distribution.items():
        for _ in range(count):
            trades.append(_trade(year, 0.5))

    by_year = split_trades_by_year(trades)
    total = sum(len(v) for v in by_year.values())
    assert total == 1000
    for year, count in distribution.items():
        assert len(by_year[year]) == count


# ============================================================================
# TEST 3 — Métricas agregadas full-period
# ============================================================================
def test_aggregate_metrics_full_period():
    """N trades simulados → dict com expectancy_r, profit_factor, max_dd_r, sharpe."""
    trades = []
    for _ in range(100):
        trades.append(_trade(2020, 0.5))
    for _ in range(100):
        trades.append(_trade(2021, -0.3))

    agg = calc_aggregate_metrics(trades)
    assert "expectancy_r" in agg
    assert "profit_factor" in agg
    assert "max_drawdown_r" in agg
    assert "sharpe_annualized" in agg
    # 100 wins de +0.5R + 100 losses de -0.3R = mean 0.1R
    assert agg["expectancy_r"] == pytest.approx(0.1, abs=1e-6)


# ============================================================================
# TEST 4 — Métricas por ano
# ============================================================================
def test_per_year_metrics():
    """Trades em 3 anos → 3 entradas com n, exp, pf, max_dd_r."""
    trades = []
    for _ in range(50):
        trades.append(_trade(2020, 0.4))
    for _ in range(40):
        trades.append(_trade(2021, -0.2))
    for _ in range(30):
        trades.append(_trade(2022, 0.6))

    by_year = split_trades_by_year(trades)
    per_year = calc_per_year_metrics(by_year, candles_by_year={})
    assert len(per_year) == 3
    for entry in per_year:
        assert "year" in entry
        assert "trades" in entry
        assert "expectancy_r" in entry
        assert "profit_factor" in entry
        assert "max_drawdown_r" in entry
        assert "regime_dominant" in entry


# ============================================================================
# TEST 5 — Ranking worst 3 anos
# ============================================================================
def test_worst_3_years_ranking():
    """5 anos com exp variada → 3 piores em ordem ascendente."""
    per_year = [
        {"year": 2020, "expectancy_r": 0.5, "trades": 50},
        {"year": 2021, "expectancy_r": -0.3, "trades": 40},
        {"year": 2022, "expectancy_r": 0.2, "trades": 60},
        {"year": 2023, "expectancy_r": -0.1, "trades": 70},
        {"year": 2024, "expectancy_r": -0.5, "trades": 30},
    ]
    worst = rank_worst_years(per_year, n=3)
    assert len(worst) == 3
    # Ordem ascendente: pior primeiro
    assert worst[0]["year"] == 2024  # -0.5
    assert worst[1]["year"] == 2021  # -0.3
    assert worst[2]["year"] == 2023  # -0.1


# ============================================================================
# TEST 6 — Ranking best 3 anos
# ============================================================================
def test_best_3_years_ranking():
    """5 anos → 3 melhores em ordem descendente."""
    per_year = [
        {"year": 2020, "expectancy_r": 0.5, "trades": 50},
        {"year": 2021, "expectancy_r": -0.3, "trades": 40},
        {"year": 2022, "expectancy_r": 0.2, "trades": 60},
        {"year": 2023, "expectancy_r": 0.8, "trades": 70},
        {"year": 2024, "expectancy_r": -0.5, "trades": 30},
    ]
    best = rank_best_years(per_year, n=3)
    assert len(best) == 3
    assert best[0]["year"] == 2023  # 0.8
    assert best[1]["year"] == 2020  # 0.5
    assert best[2]["year"] == 2022  # 0.2


# ============================================================================
# TEST 7 — % anos positivos
# ============================================================================
def test_positive_years_pct():
    """11 anos, 8 com exp > 0 → 72.7%."""
    per_year = []
    for i in range(8):
        per_year.append({"year": 2014 + i, "expectancy_r": 0.5})
    for i in range(3):
        per_year.append({"year": 2022 + i, "expectancy_r": -0.2})
    pct = positive_years_pct(per_year)
    assert pct == pytest.approx(72.7, abs=0.1)


# ============================================================================
# TEST 8 — Sharpe annualized per ano
# ============================================================================
def test_sharpe_annualized_per_year():
    """Sharpe annualizado = mean/std * sqrt(N_trades_per_year)."""
    # Série conhecida
    r_series = [0.5, -0.3, 0.4, -0.2, 0.6, -0.1, 0.3, -0.4, 0.5, 0.2]
    sh = sharpe_annualized_year(r_series)
    # mean = 0.15, std ≈ 0.385, n=10 → 0.15/0.385 * sqrt(10) ≈ 1.232
    assert sh > 0
    assert sh == pytest.approx(0.15 / _std(r_series) * math.sqrt(10), rel=1e-3)


def _std(xs):
    m = sum(xs) / len(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1))


# ============================================================================
# TEST 9 — Regime dominante per ano
# ============================================================================
def test_regime_dominant_per_year():
    """Candles do ano → regime dominante (BULL/BEAR/SIDEWAYS) baseado em % do ano."""
    # Cria 1000 candles, primeira metade em uptrend (close > SMA200), segunda igual
    candles = []
    for i in range(1000):
        # Uptrend linear: BULL dominante
        candles.append(_candle(f"2020-01-01T00:00:00", 10000 + i * 50))
    regime = classify_regime_dominant(candles)
    assert regime in ("BULL", "BEAR", "SIDEWAYS")
    # Em uptrend linear forte: deve ser BULL
    assert regime == "BULL"


# ============================================================================
# TEST 10 — Handles missing years
# ============================================================================
def test_handles_missing_years():
    """Trades em 2014-2025 com 2020 faltando → marca 2020 como data_unavailable."""
    trades = []
    for year in [2014, 2015, 2016, 2017, 2018, 2019, 2021, 2022, 2023, 2024]:
        for _ in range(10):
            trades.append(_trade(year, 0.3))
    # 2020 ausente

    by_year = split_trades_by_year(trades)
    per_year = calc_per_year_metrics(by_year, candles_by_year={},
                                     expected_years=range(2014, 2025))
    years_in_report = {p["year"] for p in per_year}
    assert 2020 in years_in_report
    missing_2020 = next(p for p in per_year if p["year"] == 2020)
    assert missing_2020.get("data_unavailable") is True


# ============================================================================
# TEST 11 — GO criterion passes (70%+ positivos)
# ============================================================================
def test_go_criterion_passes_when_70pct_positive():
    """11 anos, 8 positivos (72.7%), total_pf=2.1 → passed=true."""
    result = evaluate_go_criterion(positive_pct=72.7, total_pf=2.1)
    assert result["passed"] is True


# ============================================================================
# TEST 12 — GO criterion fails (< 70% positivos)
# ============================================================================
def test_go_criterion_fails_below_70pct():
    """11 anos, 5 positivos (45.5%), total_pf=2.1 → passed=false."""
    result = evaluate_go_criterion(positive_pct=45.5, total_pf=2.1)
    assert result["passed"] is False


# ============================================================================
# TEST 13 — JSON schema válido
# ============================================================================
def test_json_schema_valid():
    """build_long_14y_report retorna dict com schema completo."""
    trades = []
    for year in [2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024]:
        for i in range(20):
            r = 0.5 if i % 3 != 0 else -0.3
            trades.append(_trade(year, r))

    report = build_long_14y_report(trades, candles_by_year={})

    # Schema
    assert "total" in report
    for k in ("trades", "win_rate", "expectancy_r", "profit_factor",
              "max_drawdown_r", "annualized_return_pct", "sharpe_annualized"):
        assert k in report["total"]

    assert "by_year" in report
    assert isinstance(report["by_year"], list)
    assert len(report["by_year"]) >= 11
    for entry in report["by_year"]:
        for k in ("year", "trades", "expectancy_r", "profit_factor",
                  "max_drawdown_r", "regime_dominant"):
            assert k in entry

    assert "worst_3_years" in report
    assert len(report["worst_3_years"]) == 3
    for entry in report["worst_3_years"]:
        for k in ("year", "expectancy_r", "context"):
            assert k in entry

    assert "best_3_years" in report
    assert len(report["best_3_years"]) == 3

    assert "positive_years_pct" in report
    assert 0 <= report["positive_years_pct"] <= 100

    assert "go_criterion" in report
    for k in ("rule", "passed", "total_pf", "positive_years_pct"):
        assert k in report["go_criterion"]

    # Serializa sem erro
    json.dumps(report)
