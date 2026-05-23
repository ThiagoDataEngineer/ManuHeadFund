"""test_correlation_matrix_date_align.py -- Fix paralelo a FASE 3 (build_beta_cache).

correlation_matrix.py tinha o MESMO bug: align por INDEX, nao por DATA.
Window 30d eh ainda mais sensivel a shift que beta 180d (signal-to-noise pior).

Cobre:
- daily_returns_with_dates -> dict por data
- date_aligned_pearson em datas comuns
- Anti-regression em integration via build_matrix com market real
"""
from __future__ import annotations
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "backtest"))

from correlation_matrix import (
    daily_returns_with_dates,
    date_aligned_pearson,
    load_closes_with_dates,
    build_matrix,
)


def test_daily_returns_with_dates_basic(tmp_path):
    """Salva candles mock e verifica dict de returns."""
    import json
    candles = [
        {"ts": "2026-05-17T00:00:00+00:00", "close": 100.0},
        {"ts": "2026-05-18T00:00:00+00:00", "close": 110.0},
        {"ts": "2026-05-19T00:00:00+00:00", "close": 121.0},
    ]
    f = tmp_path / "BTCUSDT_1day.json"
    f.write_text(json.dumps(candles), encoding="utf-8")
    rets = daily_returns_with_dates("BTCUSDT", window=10, candles_dir=tmp_path)
    assert len(rets) == 2
    assert abs(rets["2026-05-18"] - 0.10) < 1e-9
    assert abs(rets["2026-05-19"] - 0.10) < 1e-9


def test_daily_returns_skips_gaps(tmp_path):
    """Gap > 1 dia -> retorno descartado (anti acumulado em janela larga)."""
    import json
    candles = [
        {"ts": "2026-05-15T00:00:00+00:00", "close": 100.0},
        {"ts": "2026-05-17T00:00:00+00:00", "close": 110.0},  # gap 5/16
    ]
    f = tmp_path / "XUSDT_1day.json"
    f.write_text(json.dumps(candles), encoding="utf-8")
    rets = daily_returns_with_dates("XUSDT", window=10, candles_dir=tmp_path)
    assert rets == {}


def test_date_aligned_pearson_perfect_corr():
    rets_a = {f"2026-05-{d:02d}": 0.01 * (d - 10) for d in range(11, 21)}
    rets_b = dict(rets_a)
    c = date_aligned_pearson(rets_a, rets_b)
    assert abs(c - 1.0) < 1e-9


def test_date_aligned_pearson_misaligned_keys_dropped():
    """Datas sem par sao descartadas, calcula so na intersecao."""
    rets_a = {"2026-05-15": 0.01, "2026-05-16": 0.02, "2026-05-17": 0.03,
              "2026-05-18": 0.04, "2026-05-19": 0.05}
    rets_b = {"2026-05-15": 0.01, "2026-05-16": 0.02, "2026-05-17": 0.03,
              "2026-05-18": 0.04, "2026-05-19": 0.05, "2026-05-20": 0.06}
    # Common = 5 dates (rets_a's range), pearson = 1.0
    c = date_aligned_pearson(rets_a, rets_b)
    assert abs(c - 1.0) < 1e-9


def test_date_aligned_pearson_min_5_pairs():
    """N < 5 retorna None."""
    a = {"2026-05-15": 0.01, "2026-05-16": 0.02}
    b = {"2026-05-15": 0.01, "2026-05-16": 0.02}
    assert date_aligned_pearson(a, b) is None


def test_build_matrix_with_real_data():
    """Lockdown: BTC vs BTC = 1.0 sempre; matriz real nao deve quebrar.

    Skip se candles ausentes.
    """
    candles_dir = ROOT / "journal" / "candles_coinex"
    if not (candles_dir / "BTCUSDT_1day.json").exists():
        import pytest
        pytest.skip("BTCUSDT candles nao disponivel")
    result = build_matrix(["BTCUSDT"], window=30, candles_dir=candles_dir)
    assert result["matrix"]["BTCUSDT"]["BTCUSDT"] == 1.0


def test_build_matrix_btc_eth_positive_correlation_post_fix():
    """Anti-regression: BTC vs ETH em 30d deve ter corr > 0.3 (positiva).

    Pre-fix (align por index com endpoints diferentes): poderia ficar perto de 0
    ou negativo. Pos-fix: align por data deve recuperar corr positiva real.
    """
    candles_dir = ROOT / "journal" / "candles_coinex"
    if not (candles_dir / "BTCUSDT_1day.json").exists() or not (candles_dir / "ETHUSDT_1day.json").exists():
        import pytest
        pytest.skip("BTC ou ETH candles ausentes")
    result = build_matrix(["BTCUSDT", "ETHUSDT"], window=30, candles_dir=candles_dir)
    corr = result["matrix"]["BTCUSDT"]["ETHUSDT"]
    if corr is None:
        import pytest
        pytest.skip("corr None -- insuficientes datas comuns")
    assert corr > 0.3, f"BTC-ETH 30d corr={corr} suspeitamente baixa (esperado >0.3 em qualquer regime)"
