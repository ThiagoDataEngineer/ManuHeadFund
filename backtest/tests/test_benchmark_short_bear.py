"""
test_benchmark_short_bear.py -- TDD strict: testes ANTES de implementacao.

Hipotese: SHORT em bears classicos (2018 -84%, 2022 -78%) tem edge.
Baseline V2 LONG-only nao testou SHORT em regime adequado.
"""
from __future__ import annotations

import os
import sys
import json

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from benchmark_short_bear import (  # noqa: E402
    EquityStopTracker,
    aggregate_metrics,
    calc_short_stop,
    calc_short_target,
    classify_trend,
    classify_verdict,
    is_long_fade_blocked_by_kbfix,
    is_short_signal_kbfix,
    load_bear_candles,
    simulate_short_pnl_r,
)


# ── 1. Short PnL inverso ─────────────────────────────────────────────────────

def test_short_inverse_pnl_calculation():
    # entry=100, stop=110, target=50; candles tocando target
    candles = [
        {"open": 100, "high": 102, "low": 95, "close": 95},
        {"open": 95, "high": 96, "low": 60, "close": 60},
        {"open": 60, "high": 60, "low": 45, "close": 50},
    ]
    r = simulate_short_pnl_r(entry=100.0, stop=110.0, target=50.0, candles=candles)
    # risk=10, gain=50 -> R=+5
    assert r == pytest.approx(5.0, abs=0.01)


# ── 2. Short stop acima da entry ────────────────────────────────────────────

def test_short_stop_loss_above_entry():
    # entry=80000, ATR=2000, mult=2 -> stop=84000
    stop = calc_short_stop(entry=80000.0, atr_value=2000.0, multiplier=2.0)
    assert stop == pytest.approx(84000.0)
    assert stop > 80000.0


# ── 3. Short target abaixo da entry ─────────────────────────────────────────

def test_short_target_below_entry():
    # entry=80000, stop=84000 (4k risk), RR=5 -> target = 80000 - 5*4000 = 60000
    target = calc_short_target(entry=80000.0, stop=84000.0, rr=5.0)
    assert target == pytest.approx(60000.0)
    assert target < 80000.0


# ── 4. KB-fix: RSI alto em downtrend NAO gera LONG (continuation, nao fade) ──

def test_kbfix_rsi_high_downtrend_no_long_signal():
    # ADX>25, EMA9<EMA21 (NDI>PDI) -> trend down
    trend = classify_trend(adx_value=30.0, ema9=99.0, ema21=100.0, pdi=15.0, ndi=25.0)
    assert trend == "down"
    # Em downtrend, RSI=80 deve bloquear LONG (continuation bear)
    blocked = is_long_fade_blocked_by_kbfix(trend_dir="down", rsi=80.0)
    assert blocked is True


# ── 5. KB-fix: BB upper touch em downtrend = SHORT (nao LONG fade) ──────────

def test_kbfix_bb_upper_downtrend_short_signal():
    is_short = is_short_signal_kbfix(trend_dir="down", price_touches_bb_upper=True)
    assert is_short is True
    # Em uptrend, mesmo touch nao da SHORT
    is_short_up = is_short_signal_kbfix(trend_dir="up", price_touches_bb_upper=True)
    assert is_short_up is False


# ── 6. Equity stop pausa apos -10R ──────────────────────────────────────────

def test_equity_stop_pauses_short_after_10R():
    tracker = EquityStopTracker(threshold_R=10.0)
    for _ in range(5):
        tracker.on_trade_close(-2.0)  # -2R x5 = -10R
    assert tracker.is_paused() is True
    # 6 signal deveria ser pulado
    assert tracker.should_skip_signal() is True


# ── 7. Equity stop retoma apos recovery ─────────────────────────────────────

def test_equity_stop_resumes_after_recovery():
    tracker = EquityStopTracker(threshold_R=10.0)
    for _ in range(5):
        tracker.on_trade_close(-2.0)
    assert tracker.is_paused() is True
    # +3R recovery -> DD = 7R < 10R -> retoma
    tracker.on_trade_close(3.0)
    assert tracker.is_paused() is False
    assert tracker.should_skip_signal() is False


# ── 8. Bear 2018 data loads (skip se Bitstamp/CoinEx indisponivel) ──────────

def test_bear_2018_data_loads():
    candles = load_bear_candles(market="BTCUSDT", start="2018-01-01", end="2018-12-31")
    if not candles:
        pytest.skip("Dados 2018 indisponiveis (sem acesso CoinEx/Bitstamp ou sem env DB)")
    assert len(candles) >= 300


# ── 9. Bear 2022 data loads ─────────────────────────────────────────────────

def test_bear_2022_data_loads():
    candles = load_bear_candles(market="BTCUSDT", start="2022-01-01", end="2022-12-31")
    if not candles:
        pytest.skip("Dados 2022 indisponiveis")
    assert len(candles) >= 300


# ── 10. Agregacao de metricas por periodo ───────────────────────────────────

def test_period_metrics_aggregation():
    # 50 trades: 30 winners de +1R, 20 losers de -1R
    rs = [1.0] * 30 + [-1.0] * 20
    m = aggregate_metrics(rs)
    assert m["trades"] == 50
    assert m["win_rate"] == pytest.approx(0.60, abs=1e-6)
    assert m["expectancy_r"] == pytest.approx(0.20, abs=1e-6)
    assert m["profit_factor"] == pytest.approx(30.0 / 20.0, abs=1e-6)
    assert m["max_dd_r"] >= 0.0


# ── 11. Veredito ────────────────────────────────────────────────────────────

def test_verdict_classification():
    # Caso positivo: exp +0.7R, dd_ratio 0.3 -> SHORT_FUNCIONA_BEAR
    v1 = classify_verdict(expectancy_r=0.7, dd_ratio=0.3)
    assert v1 == "SHORT_FUNCIONA_BEAR"
    # Caso ruim: exp +0.2R, dd_ratio 0.8 -> SHORT_INSUFICIENTE
    v2 = classify_verdict(expectancy_r=0.2, dd_ratio=0.8)
    assert v2 == "SHORT_INSUFICIENTE"


# ── 12. JSON output schema ──────────────────────────────────────────────────

REQUIRED_TOP = {"timestamp", "config", "periods", "go_criterion", "implication"}
REQUIRED_PERIOD = {"period_id", "market", "start", "end", "trades", "metrics", "verdict"}
REQUIRED_CRITERION = {"rule", "passed", "explanation"}


def test_json_output_schema_valid():
    # Constroi resultado sintetico e valida schema
    from benchmark_short_bear import build_result_skeleton, build_period_result

    p1 = build_period_result(
        period_id="bear_2018", market="BTCUSDT",
        start="2018-01-01", end="2018-12-31",
        r_series=[1.0, -1.0, 1.0, 1.0, -1.0, 1.0],
        n_skipped=10,
    )
    p2 = build_period_result(
        period_id="bear_2022", market="BTCUSDT",
        start="2022-01-01", end="2022-12-31",
        r_series=[1.0, 1.0, -1.0, 1.0, 1.0],
        n_skipped=8,
    )
    result = build_result_skeleton([p1, p2])
    assert REQUIRED_TOP.issubset(result.keys())
    for p in result["periods"]:
        assert REQUIRED_PERIOD.issubset(p.keys())
    assert REQUIRED_CRITERION.issubset(result["go_criterion"].keys())
    # Serializa
    json.dumps(result)
