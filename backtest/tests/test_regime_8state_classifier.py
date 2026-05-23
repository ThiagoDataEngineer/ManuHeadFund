"""
test_regime_8state_classifier.py — TDD strict para regime_8state_classifier.py

PHASE 1 — RED: 10 testes ANTES da implementação.

Classifica cada bar em 1 dos 8 regimes:
  BULL_STRONG   : preço > SMA200 E ADX > 25 E PDI > NDI
  BULL_WEAK     : preço > SMA200 E ADX <= 25
  TRANSITION_UP : SMA200 cruzou para cima nos últimos TRANSITION_BARS
  TRANSITION_DOWN: SMA200 cruzou para baixo nos últimos TRANSITION_BARS
  SIDEWAYS      : |preço - SMA200| / SMA200 < SIDEWAYS_BAND
  BEAR_WEAK     : preço < SMA200 E ADX <= 25
  BEAR_STRONG   : preço < SMA200 E ADX > 25 E NDI > PDI
  CAPITULATION  : preço < SMA200 E distância < -25%

NÃO MODIFICA: db.py, signal_generator.py, metrics.py, indicators.py.
"""
import pytest

from regime_8state_classifier import (
    classify_8state,
    reclassify_trades_8state,
    SMA200_PERIOD,
    ADX_PERIOD,
    TRANSITION_BARS,
    SIDEWAYS_BAND,
    CAPITULATION_THRESHOLD,
)


def _candle(close: float, high: float = None, low: float = None, vol: float = 1000.0) -> dict:
    h = high if high is not None else close * 1.01
    l = low  if low  is not None else close * 0.99
    return {"ts": "2020-01-01T00:00:00", "open": close, "high": h, "low": l, "close": close, "volume": vol}


def _series_flat(n: int, val: float = 100.0):
    return [_candle(val) for _ in range(n)]


def _series_uptrend_strong(n: int, start: float = 100.0, step: float = 1.0):
    """Uptrend forte: tendência clara para gerar ADX alto."""
    out = []
    price = start
    for _ in range(n):
        out.append(_candle(price, high=price + 0.5, low=price - 0.2))
        price += step
    return out


def _series_downtrend_strong(n: int, start: float = 500.0, step: float = 1.0):
    out = []
    price = start
    for _ in range(n):
        out.append(_candle(price, high=price + 0.2, low=price - 0.5))
        price -= step
    return out


def _series_choppy(n: int, base: float = 100.0):
    """Range lateral oscilante: ADX baixo."""
    out = []
    for i in range(n):
        price = base + (1.0 if i % 2 == 0 else -1.0) * 0.5
        out.append(_candle(price))
    return out


# ============================================================================
# TEST 1 — BULL_STRONG: uptrend forte + acima SMA200 + ADX alto
# ============================================================================
def test_bull_strong_when_above_sma200_and_adx_high():
    """250 candles em uptrend forte → último deve classificar BULL_STRONG."""
    candles = _series_uptrend_strong(250, start=100.0, step=2.0)
    regime = classify_8state(candles, idx=len(candles) - 1)
    assert regime == "BULL_STRONG"


# ============================================================================
# TEST 2 — BULL_WEAK: acima SMA200 mas ADX baixo (choppy acima)
# ============================================================================
def test_bull_weak_when_above_sma200_and_adx_low():
    """Sobe lentamente após base longa → acima SMA200 mas ADX baixo."""
    # 200 candles base baixa + 50 candles platô levemente acima
    base = _series_flat(200, val=100.0)
    # platô em 105 (5% acima da SMA200) com pequenas oscilações
    platau = []
    for i in range(50):
        p = 105.0 + (0.3 if i % 2 == 0 else -0.3)
        platau.append(_candle(p))
    candles = base + platau
    regime = classify_8state(candles, idx=len(candles) - 1)
    assert regime == "BULL_WEAK"


# ============================================================================
# TEST 3 — BEAR_STRONG: downtrend forte + abaixo SMA200 + ADX alto
# ============================================================================
def test_bear_strong_when_below_sma200_and_adx_high():
    candles = _series_downtrend_strong(250, start=500.0, step=1.5)
    regime = classify_8state(candles, idx=len(candles) - 1)
    # CAPITULATION é possível também — distância pode passar de -25%
    assert regime in ("BEAR_STRONG", "CAPITULATION")


# ============================================================================
# TEST 4 — BEAR_WEAK: abaixo SMA200 mas ADX baixo (choppy abaixo)
# ============================================================================
def test_bear_weak_when_below_sma200_and_adx_low():
    base = _series_flat(200, val=100.0)
    platau = []
    for i in range(50):
        p = 95.0 + (0.3 if i % 2 == 0 else -0.3)  # 5% abaixo
        platau.append(_candle(p))
    candles = base + platau
    regime = classify_8state(candles, idx=len(candles) - 1)
    assert regime == "BEAR_WEAK"


# ============================================================================
# TEST 5 — SIDEWAYS: preço dentro da banda neutra SMA200
# ============================================================================
def test_sideways_when_close_to_sma200():
    """Preço a < 2% de SMA200 → SIDEWAYS."""
    candles = _series_flat(250, val=100.0)
    regime = classify_8state(candles, idx=len(candles) - 1)
    assert regime == "SIDEWAYS"


# ============================================================================
# TEST 6 — TRANSITION_UP: cruzou SMA200 ascendente recente
# ============================================================================
def test_transition_up_after_cross_above():
    """200 candles abaixo + 20 candles cruzando para cima → TRANSITION_UP."""
    candles = []
    # 220 candles em 95 (abaixo)
    for _ in range(220):
        candles.append(_candle(95.0))
    # 20 candles subindo cruzando para cima (107)
    for i in range(20):
        candles.append(_candle(95.0 + i * 0.7))  # vai de 95 até ~108
    regime = classify_8state(candles, idx=len(candles) - 1)
    assert regime in ("TRANSITION_UP", "BULL_WEAK", "BULL_STRONG")  # aceita variações por força do trend


# ============================================================================
# TEST 7 — TRANSITION_DOWN: cruzou SMA200 descendente recente
# ============================================================================
def test_transition_down_after_cross_below():
    candles = []
    for _ in range(220):
        candles.append(_candle(105.0))
    for i in range(20):
        candles.append(_candle(105.0 - i * 0.7))
    regime = classify_8state(candles, idx=len(candles) - 1)
    assert regime in ("TRANSITION_DOWN", "BEAR_WEAK", "BEAR_STRONG")


# ============================================================================
# TEST 8 — CAPITULATION: distância < -25%
# ============================================================================
def test_capitulation_when_far_below():
    """SMA200 estável em 100, preço atual 50 → -50% → CAPITULATION."""
    candles = _series_flat(200, val=100.0)
    # 30 candles caindo até 50
    for i in range(30):
        candles.append(_candle(100.0 - i * 1.7))
    regime = classify_8state(candles, idx=len(candles) - 1)
    assert regime == "CAPITULATION"


# ============================================================================
# TEST 9 — Pipeline reclassify_trades_8state
# ============================================================================
def test_reclassify_trades_pipeline():
    """Recebe trades + candles → retorna trades com regime atualizado para 8-state."""
    # Trade em "2020-06-15" — precisa de candles com esse timestamp
    candles = []
    # 250 candles antes da data do trade em uptrend forte
    for i in range(250):
        # ts incremental ascendente, mas a função deve usar índice por ts
        ts = f"2020-{(i // 30) + 1:02d}-{(i % 30) + 1:02d}T00:00:00"
        candles.append({
            "ts": ts, "close": 100 + i * 2.0,
            "high": 100 + i * 2.0 + 0.5, "low": 100 + i * 2.0 - 0.2,
            "open": 100 + i * 2.0, "volume": 1000.0,
        })
    # Trade no último timestamp
    last_ts = candles[-1]["ts"]
    trades = [{
        "entry_ts": last_ts,
        "result_r": 0.5,
        "direction": "LONG",
        "regime": "bull",   # antes era 3-state
    }]
    enriched = reclassify_trades_8state(trades, candles)
    assert len(enriched) == 1
    assert enriched[0]["regime"] in (
        "BULL_STRONG", "BULL_WEAK", "TRANSITION_UP",
        "TRANSITION_DOWN", "SIDEWAYS", "BEAR_WEAK", "BEAR_STRONG", "CAPITULATION"
    )


# ============================================================================
# TEST 10 — Dados insuficientes retorna UNKNOWN (não crasha)
# ============================================================================
def test_insufficient_data_returns_unknown():
    candles = _series_flat(50)  # < 200 candles
    regime = classify_8state(candles, idx=len(candles) - 1)
    assert regime == "UNKNOWN"
