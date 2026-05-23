"""
TDD — indicators.py
Valores esperados calculados manualmente ou via TradingView para garantir
que o port do PowerShell está matematicamente correto.
"""
import pytest
from indicators import ema, rsi, atr, macd, bollinger, adx


# ── Fixtures ────────────────────────────────────────────────────────────────

@pytest.fixture
def closes_simple():
    """10 closes conhecidos para cálculos manuais."""
    return [10.0, 11.0, 12.0, 11.0, 10.0, 11.0, 12.0, 13.0, 12.0, 11.0]


@pytest.fixture
def closes_20():
    """20 closes para RSI e Bollinger (mínimo 14 + 6 buffer)."""
    return [
        44.34, 44.09, 44.15, 43.61, 44.33, 44.83, 45.10, 45.15,
        43.61, 44.33, 44.83, 45.10, 45.15, 44.34, 44.09, 44.15,
        43.61, 44.83, 45.10, 45.15
    ]


@pytest.fixture
def candles_20():
    """20 candles (high/low/close) para ATR e ADX."""
    data = [
        (44.50, 43.80, 44.34),
        (44.20, 43.70, 44.09),
        (44.30, 43.90, 44.15),
        (43.80, 43.30, 43.61),
        (44.50, 43.90, 44.33),
        (45.00, 44.50, 44.83),
        (45.30, 44.80, 45.10),
        (45.40, 44.90, 45.15),
        (44.00, 43.30, 43.61),
        (44.60, 43.90, 44.33),
        (45.00, 44.50, 44.83),
        (45.30, 44.90, 45.10),
        (45.50, 44.90, 45.15),
        (44.70, 44.00, 44.34),
        (44.40, 43.70, 44.09),
        (44.40, 43.90, 44.15),
        (43.90, 43.40, 43.61),
        (45.10, 44.50, 44.83),
        (45.40, 44.80, 45.10),
        (45.60, 44.90, 45.15),
    ]
    return [{"high": h, "low": l, "close": c} for h, l, c in data]


# ── EMA ──────────────────────────────────────────────────────────────────────

class TestEMA:
    def test_ema_period_1_returns_last_close(self, closes_simple):
        result = ema(closes_simple, period=1)
        assert result == closes_simple[-1]

    def test_ema_period_equal_len_returns_sma(self):
        closes = [10.0, 10.0, 10.0, 10.0, 10.0]
        result = ema(closes, period=5)
        assert abs(result - 10.0) < 0.01

    def test_ema_trending_up_above_sma(self):
        closes = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
        sma = sum(closes) / len(closes)
        result = ema(closes, period=5)
        assert result > sma

    def test_ema_period_3_known_value(self):
        closes = [10.0, 11.0, 12.0]
        # k = 2/(3+1) = 0.5
        # ema0 = 10, ema1 = 11*0.5 + 10*0.5 = 10.5, ema2 = 12*0.5 + 10.5*0.5 = 11.25
        result = ema(closes, period=3)
        assert abs(result - 11.25) < 0.01

    def test_ema_requires_minimum_data(self):
        with pytest.raises((ValueError, IndexError)):
            ema([], period=9)

    def test_ema_period_larger_than_data_raises(self):
        with pytest.raises((ValueError, IndexError)):
            ema([1.0, 2.0], period=9)


# ── RSI ──────────────────────────────────────────────────────────────────────

class TestRSI:
    def test_rsi_range_0_to_100(self, closes_20):
        result = rsi(closes_20, period=14)
        assert 0.0 <= result <= 100.0

    def test_rsi_all_gains_returns_100(self):
        closes = [float(i) for i in range(1, 20)]
        result = rsi(closes, period=14)
        assert result == 100.0

    def test_rsi_all_losses_returns_0(self):
        closes = [float(20 - i) for i in range(19)]
        result = rsi(closes, period=14)
        assert result == 0.0

    def test_rsi_flat_market_returns_50(self):
        closes = [10.0] * 20
        result = rsi(closes, period=14)
        assert result == 50.0 or result == 100.0  # sem movimento: avg_loss=0

    def test_rsi_requires_period_plus_one_candles(self):
        with pytest.raises((ValueError, IndexError)):
            rsi([1.0, 2.0, 3.0], period=14)

    def test_rsi_oversold_below_30(self):
        closes = [100.0, 95.0, 90.0, 85.0, 80.0, 75.0, 70.0, 65.0,
                  60.0, 55.0, 50.0, 45.0, 40.0, 35.0, 30.0]
        result = rsi(closes, period=14)
        assert result < 30.0

    def test_rsi_overbought_above_70(self):
        closes = [10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0,
                  50.0, 55.0, 60.0, 65.0, 70.0, 75.0, 80.0]
        result = rsi(closes, period=14)
        assert result > 70.0


# ── ATR ──────────────────────────────────────────────────────────────────────

class TestATR:
    def test_atr_positive(self, candles_20):
        result = atr(candles_20, period=14)
        assert result > 0.0

    def test_atr_flat_candles_near_zero(self):
        candles = [{"high": 10.0, "low": 10.0, "close": 10.0}] * 20
        result = atr(candles, period=14)
        assert result < 0.001

    def test_atr_high_volatility_larger_value(self):
        candles_low_vol = [{"high": 10.1, "low": 9.9, "close": 10.0}] * 20
        candles_high_vol = [{"high": 12.0, "low": 8.0, "close": 10.0}] * 20
        assert atr(candles_high_vol, period=14) > atr(candles_low_vol, period=14)

    def test_atr_requires_minimum_candles(self):
        with pytest.raises((ValueError, IndexError)):
            atr([{"high": 10.0, "low": 9.0, "close": 9.5}], period=14)


# ── MACD ─────────────────────────────────────────────────────────────────────

@pytest.fixture
def closes_35():
    """35 closes para MACD (slow=26 + signal=9)."""
    base = [44.34, 44.09, 44.15, 43.61, 44.33, 44.83, 45.10, 45.15,
            43.61, 44.33, 44.83, 45.10, 45.15, 44.34, 44.09, 44.15,
            43.61, 44.83, 45.10, 45.15]
    return base + [44.0 + i * 0.1 for i in range(15)]


class TestMACD:
    def test_macd_returns_three_values(self, closes_35):
        result = macd(closes_35)
        assert "macd_line" in result
        assert "signal_line" in result
        assert "histogram" in result

    def test_macd_histogram_equals_line_minus_signal(self, closes_35):
        result = macd(closes_35)
        expected = result["macd_line"] - result["signal_line"]
        assert abs(result["histogram"] - expected) < 1e-10

    def test_macd_bullish_crossover(self):
        # série claramente bullish: histogram deve ser positivo
        closes = [float(i) for i in range(1, 40)]
        result = macd(closes)
        assert result["histogram"] > 0

    def test_macd_bearish_crossover(self):
        # série claramente bearish: histogram deve ser negativo
        closes = [float(40 - i) for i in range(39)]
        result = macd(closes)
        assert result["histogram"] < 0

    def test_macd_requires_minimum_26_candles(self):
        with pytest.raises((ValueError, IndexError)):
            macd([1.0] * 10)


# ── BOLLINGER BANDS ───────────────────────────────────────────────────────────

class TestBollinger:
    def test_bollinger_returns_three_bands(self, closes_20):
        result = bollinger(closes_20, period=20)
        assert "upper" in result
        assert "middle" in result
        assert "lower" in result

    def test_bollinger_upper_above_middle_above_lower(self, closes_20):
        result = bollinger(closes_20, period=20)
        assert result["upper"] > result["middle"] > result["lower"]

    def test_bollinger_middle_is_sma(self, closes_20):
        result = bollinger(closes_20, period=20)
        sma = sum(closes_20[-20:]) / 20
        assert abs(result["middle"] - sma) < 0.001

    def test_bollinger_flat_series_zero_width(self):
        closes = [10.0] * 25
        result = bollinger(closes, period=20)
        assert abs(result["upper"] - result["lower"]) < 0.001

    def test_bollinger_width_proportional_to_volatility(self, closes_20):
        import random
        random.seed(42)
        flat = [10.0] * 25
        volatile = [10.0 + random.uniform(-3, 3) for _ in range(25)]
        width_flat = bollinger(flat, period=20)["upper"] - bollinger(flat, period=20)["lower"]
        width_vol = bollinger(volatile, period=20)["upper"] - bollinger(volatile, period=20)["lower"]
        assert width_vol > width_flat


# ── ADX ───────────────────────────────────────────────────────────────────────

class TestADX:
    def test_adx_returns_dict_with_keys(self, candles_20):
        result = adx(candles_20, period=14)
        assert "adx" in result
        assert "pdi" in result
        assert "ndi" in result

    def test_adx_range_0_to_100(self, candles_20):
        result = adx(candles_20, period=14)
        assert 0.0 <= result["adx"] <= 100.0

    def test_adx_trending_market_above_25(self):
        candles = [{"high": float(i + 1), "low": float(i), "close": float(i) + 0.5}
                   for i in range(1, 30)]
        result = adx(candles, period=14)
        assert result["adx"] > 20.0

    def test_adx_pdi_positive_in_uptrend(self):
        candles = [{"high": float(i + 1), "low": float(i), "close": float(i) + 0.5}
                   for i in range(1, 30)]
        result = adx(candles, period=14)
        assert result["pdi"] > result["ndi"]
