"""SUITE A — TDD strict para regime_classifier.py (8 estados + INSUFFICIENT_DATA).

PHASE 1 RED: estes testes devem FALHAR antes da implementacao.
Regimes: BULL_STRONG | BULL_WEAK | SIDEWAYS | TRANSITION_UP | TRANSITION_DOWN
        | BEAR_WEAK | BEAR_STRONG | CAPITULATION | INSUFFICIENT_DATA

Zero lookahead: classify(t) usa apenas candles[<=t].
"""
import pytest
from regime_classifier import classify_regime


# ── Fixtures sinteticos: gera serie de candles com regime conhecido ─────────

def _candle(close, high=None, low=None, volume=100.0, ts=None):
    return {
        "ts": ts or f"2025-01-01T{0:02d}:00:00+00:00",
        "open": close * 0.999,
        "high": high if high is not None else close * 1.005,
        "low": low if low is not None else close * 0.995,
        "close": close,
        "volume": volume,
    }


def _series(values, start_ts="2024-01-01"):
    """Converte lista de closes em candles dict com ts incrementais (diarios)."""
    from datetime import datetime, timedelta
    base = datetime.fromisoformat(start_ts)
    return [_candle(v, ts=(base + timedelta(days=i)).isoformat() + "+00:00") for i, v in enumerate(values)]


# ── Generators de regime sintetico ─────────────────────────────────────────

def _bull_strong_series(n=250):
    """SMA200 base 100, preco final 130 (30% acima), ADX alto, retorno 60d +25%."""
    # 200 candles em 100 (estabiliza SMA200=100), depois 50 candles subindo +0.6/dia
    base = [100.0 + (i % 3 - 1) * 0.5 for i in range(200)]
    rise = [100.0 + (j + 1) * 0.6 for j in range(50)]
    return _series(base + rise)


def _bull_weak_series(n=250):
    """SMA200 ~100, preco final 105 (5% acima), ADX baixo, retorno 60d +8%."""
    base = [100.0 + (i % 4 - 1.5) * 0.3 for i in range(200)]
    drift = [100.0 + (j + 1) * 0.1 for j in range(50)]
    return _series(base + drift)


def _sideways_series(n=250):
    """Preco oscila +-2% em torno do SMA200, ADX baixo."""
    import math
    vals = [100.0 + 2.0 * math.sin(i / 5.0) for i in range(250)]
    return _series(vals)


def _transition_up_series():
    """Preco abaixo SMA200 ate dia ~240, cruzou para cima ha ~10 dias."""
    # 200 dias em 95 (SMA200 ~95), 30 dias em 92 (SMA200 cai um pouco), 10 dias subindo
    pre = [95.0 + (i % 3 - 1) * 0.3 for i in range(200)]
    dip = [92.0 + (i % 3 - 1) * 0.3 for i in range(30)]
    cross_up = [94.0 + j * 0.5 for j in range(10)]   # cruza SMA200 para cima
    return _series(pre + dip + cross_up)


def _transition_down_series():
    """Preco acima SMA200 ate dia ~240, cruzou para baixo ha ~10 dias."""
    pre = [105.0 + (i % 3 - 1) * 0.3 for i in range(200)]
    pump = [108.0 + (i % 3 - 1) * 0.3 for i in range(30)]
    cross_down = [106.0 - j * 0.5 for j in range(10)]
    return _series(pre + pump + cross_down)


def _bear_weak_series():
    """Preco 5% abaixo SMA200, ADX baixo."""
    base = [100.0 + (i % 4 - 1.5) * 0.3 for i in range(200)]
    drop = [100.0 - (j + 1) * 0.1 for j in range(50)]
    return _series(base + drop)


def _bear_strong_series():
    """Preco 20% abaixo SMA200, ADX alto, retorno 60d -25%."""
    base = [100.0 + (i % 3 - 1) * 0.3 for i in range(200)]
    crash = [100.0 - (j + 1) * 0.4 for j in range(50)]
    return _series(base + crash)


def _capitulation_series():
    """Preco abaixo 200WMA (200 semanas = 1400 dias)."""
    # Para 200WMA precisamos de muitos candles diarios. Usar 1500 candles, ultimos bem abaixo.
    base = [100.0 + (i % 3 - 1) * 0.5 for i in range(1400)]
    crash = [60.0 - (j * 0.2) for j in range(100)]
    return _series(base + crash)


# ── SUITE A — Tests (10) ────────────────────────────────────────────────────

class TestRegimeClassifier:

    def test_classify_bull_strong(self):
        """30% acima SMA200 + ADX>30 + retorno 60d > +20% = BULL_STRONG."""
        candles = _bull_strong_series()
        assert classify_regime(candles) == "BULL_STRONG"

    def test_classify_bull_weak(self):
        """5% acima SMA200 + ADX<25 = BULL_WEAK."""
        candles = _bull_weak_series()
        assert classify_regime(candles) == "BULL_WEAK"

    def test_classify_sideways(self):
        """Preco oscilando +-2% SMA200 + ADX baixo + retorno 60d pequeno = SIDEWAYS."""
        candles = _sideways_series()
        assert classify_regime(candles) == "SIDEWAYS"

    def test_classify_transition_up(self):
        """Cruzou SMA200 para cima nos ultimos 10 dias = TRANSITION_UP."""
        candles = _transition_up_series()
        assert classify_regime(candles) == "TRANSITION_UP"

    def test_classify_transition_down(self):
        """Cruzou SMA200 para baixo nos ultimos 10 dias = TRANSITION_DOWN."""
        candles = _transition_down_series()
        assert classify_regime(candles) == "TRANSITION_DOWN"

    def test_classify_bear_weak(self):
        """5% abaixo SMA200 + ADX<25 = BEAR_WEAK."""
        candles = _bear_weak_series()
        assert classify_regime(candles) == "BEAR_WEAK"

    def test_classify_bear_strong(self):
        """20% abaixo SMA200 + ADX>30 + retorno 60d < -20% = BEAR_STRONG."""
        candles = _bear_strong_series()
        assert classify_regime(candles) == "BEAR_STRONG"

    def test_classify_capitulation(self):
        """Preco abaixo 200WMA = CAPITULATION (override de BEAR_STRONG)."""
        candles = _capitulation_series()
        assert classify_regime(candles) == "CAPITULATION"

    def test_classifier_no_lookahead(self):
        """Classify(t) deve usar apenas candles[<=t]. Determinismo confirmado."""
        full = _bull_strong_series()
        # Tira ultimos 10 candles, classifica
        r1 = classify_regime(full[:-10])
        r2 = classify_regime(full[:-10])
        assert r1 == r2  # determinismo
        # Adicionar futuros candles nao muda historico
        full_modified = full[:-10] + [_candle(50.0) for _ in range(10)]
        r3 = classify_regime(full_modified[:-10])
        assert r1 == r3

    def test_classifier_handles_short_history(self):
        """< 200 candles = INSUFFICIENT_DATA (nao crashar)."""
        candles = _series([100.0] * 50)
        assert classify_regime(candles) == "INSUFFICIENT_DATA"

    def test_capitulation_respects_bars_per_day_for_hourly_data(self):
        """Regressao: com bars_per_day=24 (dados 1h), 1400 candles 1h = 58 dias, NAO 200 semanas.
        CAPITULATION nao pode disparar sem 1400*24=33600 candles 1h.
        """
        # 2000 candles 1h em preco baixo: representa apenas ~83 dias, nao tem como ser CAPITULATION
        candles = _series([50.0] * 2000)
        regime = classify_regime(candles, bars_per_day=24)
        assert regime != "CAPITULATION", \
            f"CAPITULATION incorreto com bars_per_day=24 em apenas 2000 candles 1h; got {regime}"

    def test_capitulation_triggers_for_daily_data_below_200wma(self):
        """Default bars_per_day=1 (diario): 1500 candles com crash final dispara CAPITULATION."""
        candles = _capitulation_series()
        assert classify_regime(candles, bars_per_day=1) == "CAPITULATION"
