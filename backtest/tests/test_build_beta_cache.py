"""test_build_beta_cache.py -- FASE 3 anti-regression 2026-05-21.

Lockdown do bug: build_beta_cache alinhava por INDEX, nao por DATA. Quando
candles de markets terminavam em datas diferentes (BTC 2026-05-19 + HYPE 2026-05-18),
slice [-n:] introduzia shift de 1 dia -> beta virava ruido -> signs flip aleatorios.

22 markets ficaram com beta NEGATIVO contra BTC (ETH=-0.117, SOL=-0.026, DOGE=-0.077)
em janela 180d. Apos fix: ETH=+1.242, SOL=+1.216, todos positivos exceto USDC stable.
"""
from __future__ import annotations
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "backtest"))

from build_beta_cache import (
    date_aligned_returns,
    compute_beta,
    load_closes_with_dates,
)


def test_date_aligned_returns_perfectly_aligned():
    """Series com mesmas datas: retorna returns consecutivos."""
    btc = [("2026-05-15", 100.0), ("2026-05-16", 110.0), ("2026-05-17", 121.0)]
    m   = [("2026-05-15", 50.0),  ("2026-05-16", 55.0),  ("2026-05-17", 60.5)]
    ret_m, ret_b = date_aligned_returns(m, btc)
    assert len(ret_m) == 2
    assert len(ret_b) == 2
    # Both 10% then ~10%
    assert abs(ret_m[0] - 0.10) < 1e-9
    assert abs(ret_b[0] - 0.10) < 1e-9


def test_date_aligned_returns_misaligned_endpoints():
    """FASE 3 root cause: BTC termina depois de HYPE.

    Antes (bug): slice [-2:] de ambos retornava 2 entries cada, mas dates diferentes
    pareadas -> beta corrompido.
    Agora (fix): so dates em COMUM viram pares. BTC 5/19 sem par em HYPE eh descartado.
    """
    btc = [("2026-05-17", 100.0), ("2026-05-18", 110.0), ("2026-05-19", 121.0)]
    hype = [("2026-05-17", 50.0),  ("2026-05-18", 55.0)]  # nao tem 5/19
    ret_m, ret_b = date_aligned_returns(hype, btc)
    # Common dates: 5/17, 5/18 -> 1 retorno consecutivo
    assert len(ret_m) == 1
    assert len(ret_b) == 1
    assert abs(ret_m[0] - 0.10) < 1e-9
    assert abs(ret_b[0] - 0.10) < 1e-9


def test_date_aligned_returns_skips_gaps():
    """Gap de 1+ dia entre datas -> retorno descartado (anti-snapshot-acumulado)."""
    btc = [("2026-05-15", 100.0), ("2026-05-17", 110.0)]  # gap 5/16
    m   = [("2026-05-15", 50.0),  ("2026-05-17", 55.0)]
    ret_m, ret_b = date_aligned_returns(m, btc)
    assert ret_m == []
    assert ret_b == []


def test_compute_beta_perfect_correlation():
    """Y identico a X -> beta=1.0. Min 10 obs (gate compute_beta)."""
    x = [0.01, -0.02, 0.03, -0.01, 0.02, 0.015, -0.005, 0.01, -0.02, 0.03]
    y = list(x)
    beta = compute_beta(y, x)
    assert abs(beta - 1.0) < 1e-9


def test_compute_beta_amplifier():
    """Y = 1.5 * X (amplifier) -> beta=1.5."""
    x = [0.01, -0.02, 0.03, -0.01, 0.02, 0.015, -0.005, 0.01, -0.02, 0.03]
    y = [1.5 * v for v in x]
    beta = compute_beta(y, x)
    assert abs(beta - 1.5) < 1e-9


def test_compute_beta_insufficient_data():
    """N < 10 retorna None."""
    assert compute_beta([0.01]*5, [0.01]*5) is None


def test_load_closes_with_dates_real_btc():
    """Carrega BTCUSDT real do disco -> retorna (date, close) ordenado.

    Skip se candles ausentes.
    """
    candles_dir = ROOT / "journal" / "candles_coinex"
    if not (candles_dir / "BTCUSDT_1day.json").exists():
        import pytest
        pytest.skip("BTCUSDT candles nao disponivel no ambiente")
    series = load_closes_with_dates("BTCUSDT", candles_dir)
    assert len(series) > 100
    for d, c in series[:3]:
        assert isinstance(d, str) and len(d) == 10
        assert c > 0


def test_anti_regression_eth_beta_positive_post_fix():
    """Regressao critica: ETH deve ter beta POSITIVO vs BTC em janela 180d.

    Pre-fix: ETH=-0.117 (sign-flip por index misalignment).
    Pos-fix: ETH ~ +1.2 (BTC amplifier real).

    Skip se beta_vs_btc.json nao existe (ambiente sem dados).
    """
    import json
    beta_file = ROOT / "journal" / "beta_vs_btc.json"
    if not beta_file.exists():
        import pytest
        pytest.skip("beta_vs_btc.json nao disponivel")
    data = json.loads(beta_file.read_text(encoding="utf-8-sig"))
    eth = data["beta"].get("ETHUSDT")
    if eth is None:
        import pytest
        pytest.skip("ETHUSDT nao no cache")
    assert eth > 0.5, f"ETH beta={eth} suspeito (esperado >0.5 em window 180d vs BTC)"
