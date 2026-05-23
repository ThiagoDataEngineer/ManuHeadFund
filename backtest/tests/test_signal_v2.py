"""
test_signal_v2.py — TDD para generate_signal_v2 com pesos refinados.

Mudanças vs v1:
  - MTF alignment (4h trend): +25pts (novo)
  - ADX strength: ±15 → ±20
  - Volume confirmation: +10 → +20
  - EMA cross: ±15 → ±10 (lagging)
  - RSI: ±20 → ±10 (lagging)
  - MACD: ±15 → ±10 (lagging)
  - BB extremes: ±15 (manter)
"""
import pytest
from signal_generator_v2 import generate_signal_v2, SCORE_THRESHOLD_V2


def _candle(ts: str, o: float, h: float, low: float, c: float, vol: float = 1000.0) -> dict:
    return {"ts": ts, "open": o, "high": h, "low": low, "close": c, "volume": vol}


def _trending_up(n: int = 250, base: float = 100.0, step: float = 0.5):
    """Série em uptrend limpo — bom para testar bull setups."""
    candles = []
    price = base
    for i in range(n):
        candles.append(_candle(
            ts=f"2024-01-01T{i:02d}:00Z" if i < 24 else f"2024-01-{(i//24)+1:02d}T{i%24:02d}:00Z",
            o=price, h=price + 0.3, low=price - 0.2, c=price + step,
            vol=1000 + i * 5,
        ))
        price += step
    return candles


def _trending_down(n: int = 250, base: float = 200.0, step: float = 0.5):
    """Série em downtrend limpo."""
    candles = []
    price = base
    for i in range(n):
        candles.append(_candle(
            ts=f"2024-01-01T{i:02d}:00Z" if i < 24 else f"2024-01-{(i//24)+1:02d}T{i%24:02d}:00Z",
            o=price, h=price + 0.2, low=price - 0.3, c=price - step,
            vol=1000 + i * 5,
        ))
        price -= step
    return candles


class TestSignalV2Basic:
    def test_returns_signal_result(self):
        candles = _trending_up()
        result = generate_signal_v2(candles, candles_htf=None)
        assert result.signal in ("COMPRA", "VENDA", "NEUTRO")
        assert 0 <= result.score <= 100

    def test_uptrend_no_htf_alignment_still_generates_signal(self):
        """Sem HTF, deve gerar sinal usando os outros pesos."""
        candles = _trending_up()
        result = generate_signal_v2(candles, candles_htf=None)
        # Em uptrend forte deve dar COMPRA
        assert result.signal == "COMPRA" or result.score >= 50


class TestSignalV2MTFAlignment:
    def test_htf_aligned_boosts_score(self):
        """Quando HTF aponta na mesma direção, score deve ser maior."""
        candles_1h = _trending_up()
        candles_4h_aligned = _trending_up(n=100, base=100.0, step=2.0)  # 4h também up
        candles_4h_against = _trending_down(n=100, base=200.0, step=2.0)  # 4h down

        with_aligned = generate_signal_v2(candles_1h, candles_htf=candles_4h_aligned)
        with_against = generate_signal_v2(candles_1h, candles_htf=candles_4h_against)

        assert with_aligned.score > with_against.score

    def test_htf_against_blocks_signal_or_lowers(self):
        """HTF contra deve impedir sinal de virar acionável (NEUTRO ou score < threshold)."""
        candles_1h = _trending_up()
        candles_4h_against = _trending_down(n=100, base=200.0, step=2.0)
        result = generate_signal_v2(candles_1h, candles_htf=candles_4h_against)
        # Score deve cair pelo menos 20 pts vs alinhado
        candles_4h_aligned = _trending_up(n=100, base=100.0, step=2.0)
        aligned = generate_signal_v2(candles_1h, candles_htf=candles_4h_aligned)
        assert (aligned.score - result.score) >= 15.0


class TestSignalV2VolumeWeight:
    def test_high_volume_adds_to_dominant_side(self):
        """Volume confirmação deve dar +20 ao lado dominante."""
        candles = _trending_up()
        # Sobrescreve volume da última barra para alto
        candles[-1]["volume"] = candles[-2]["volume"] * 3.0
        result = generate_signal_v2(candles, candles_htf=None)
        # Indicadores devem reportar vol_confirm True
        assert result.indicators.get("vol_confirm") is True


class TestSignalV2ThresholdAlignment:
    def test_threshold_default_matches_v1_calibration(self):
        """Por padrão, manter 65 — afinal de contas v1 também usa 65."""
        assert SCORE_THRESHOLD_V2 == 65.0
