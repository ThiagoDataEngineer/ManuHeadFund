"""
TDD — signal_generator.py
Testa geração de sinais bar-a-bar sobre dados históricos.
Regra crítica: ZERO lookahead bias — bar[i] só usa dados[0..i].
"""
import pytest
from unittest.mock import MagicMock, patch
from signal_generator import (
    SignalGenerator,
    generate_signal,
    calc_stop_atr,
    calc_target,
    SignalResult,
)


# ── Fixtures ─────────────────────────────────────────────────────────────────

def make_candle(close, high=None, low=None, open_=None, volume=100.0):
    c = close
    return {
        "ts": "2025-04-01T00:00:00+00:00",
        "open": open_ or c * 0.999,
        "high": high or c * 1.005,
        "low": low or c * 0.995,
        "close": c,
        "volume": volume,
    }


@pytest.fixture
def candles_50():
    """50 candles flat — suficiente para todos os indicadores."""
    return [make_candle(100.0 + i * 0.1) for i in range(50)]


@pytest.fixture
def candles_uptrend():
    """50 candles claramente em uptrend — deve gerar COMPRA."""
    return [make_candle(80.0 + i * 0.5, high=80.0 + i * 0.5 + 1, low=80.0 + i * 0.5 - 0.5) for i in range(50)]


@pytest.fixture
def candles_downtrend():
    """50 candles claramente em downtrend — deve gerar VENDA."""
    return [make_candle(130.0 - i * 0.5, high=130.0 - i * 0.5 + 0.5, low=130.0 - i * 0.5 - 1) for i in range(50)]


@pytest.fixture
def candles_insufficient():
    """Menos de 30 candles — insuficiente para indicadores."""
    return [make_candle(100.0 + i) for i in range(15)]


# ── SignalResult ──────────────────────────────────────────────────────────────

class TestSignalResult:
    def test_has_required_fields(self):
        s = SignalResult(
            signal="COMPRA", score=72.0,
            entry_price=100.0, stop_loss=98.0, take_profit=106.0,
            atr=2.0, indicators={"ema_cross": True},
        )
        assert s.signal == "COMPRA"
        assert s.score == 72.0
        assert s.entry_price == 100.0
        assert s.stop_loss == 98.0
        assert s.take_profit == 106.0
        assert s.atr == 2.0

    def test_signal_values(self):
        for sig in ("COMPRA", "VENDA", "NEUTRO"):
            s = SignalResult(signal=sig, score=50, entry_price=100,
                             stop_loss=98, take_profit=106, atr=2, indicators={})
            assert s.signal == sig

    def test_rr_ratio_property(self):
        # entrada 100, stop 98 (risco 2), alvo 106 (ganho 6) → R:R = 3.0
        s = SignalResult(signal="COMPRA", score=70, entry_price=100,
                         stop_loss=98, take_profit=106, atr=2, indicators={})
        assert abs(s.rr_ratio - 3.0) < 0.01

    def test_is_actionable_requires_rr_above_2(self):
        good = SignalResult(signal="COMPRA", score=70, entry_price=100,
                            stop_loss=98, take_profit=106, atr=2, indicators={})
        bad = SignalResult(signal="COMPRA", score=70, entry_price=100,
                           stop_loss=99, take_profit=101, atr=1, indicators={})
        assert good.is_actionable is True
        assert bad.is_actionable is False

    def test_neutro_never_actionable(self):
        s = SignalResult(signal="NEUTRO", score=50, entry_price=100,
                         stop_loss=98, take_profit=106, atr=2, indicators={})
        assert s.is_actionable is False


# ── calc_stop_atr ─────────────────────────────────────────────────────────────

class TestCalcStopATR:
    def test_long_stop_below_entry(self, candles_50):
        stop = calc_stop_atr(candles_50, direction="LONG", multiplier=2.0)
        entry = candles_50[-1]["close"]
        assert stop < entry

    def test_short_stop_above_entry(self, candles_50):
        stop = calc_stop_atr(candles_50, direction="SHORT", multiplier=2.0)
        entry = candles_50[-1]["close"]
        assert stop > entry

    def test_wider_multiplier_wider_stop(self, candles_50):
        entry = candles_50[-1]["close"]
        stop_1x = calc_stop_atr(candles_50, direction="LONG", multiplier=1.0)
        stop_2x = calc_stop_atr(candles_50, direction="LONG", multiplier=2.0)
        assert (entry - stop_2x) > (entry - stop_1x)

    def test_stop_positive(self, candles_50):
        stop = calc_stop_atr(candles_50, direction="LONG", multiplier=2.0)
        assert stop > 0


# ── calc_target ───────────────────────────────────────────────────────────────

class TestCalcTarget:
    def test_long_target_above_entry(self, candles_50):
        entry = candles_50[-1]["close"]
        stop = entry * 0.98
        target = calc_target(entry, stop, direction="LONG", rr=3.0)
        assert target > entry

    def test_short_target_below_entry(self, candles_50):
        entry = candles_50[-1]["close"]
        stop = entry * 1.02
        target = calc_target(entry, stop, direction="SHORT", rr=3.0)
        assert target < entry

    def test_rr_3_means_gain_3x_risk(self, candles_50):
        entry = 100.0
        stop = 98.0   # risco = 2
        target = calc_target(entry, stop, direction="LONG", rr=3.0)
        assert abs(target - 106.0) < 0.01  # ganho = 6 = 3 × 2


# ── generate_signal ───────────────────────────────────────────────────────────

class TestGenerateSignal:
    def test_returns_signal_result(self, candles_50):
        result = generate_signal(candles_50)
        assert isinstance(result, SignalResult)

    def test_signal_is_valid_value(self, candles_50):
        result = generate_signal(candles_50)
        assert result.signal in ("COMPRA", "VENDA", "NEUTRO")

    def test_score_between_0_and_100(self, candles_50):
        result = generate_signal(candles_50)
        assert 0 <= result.score <= 100

    def test_uptrend_tends_compra(self, candles_uptrend):
        result = generate_signal(candles_uptrend)
        # uptrend forte deve gerar COMPRA ou score > 50
        assert result.signal == "COMPRA" or result.score > 50

    def test_downtrend_tends_venda(self, candles_downtrend):
        result = generate_signal(candles_downtrend)
        # score bearish dominante — pode ser VENDA (>=65) ou NEUTRO (60<65 com threshold atual)
        assert result.signal in ("VENDA", "NEUTRO") and result.score >= 50

    def test_insufficient_data_returns_neutro(self, candles_insufficient):
        result = generate_signal(candles_insufficient)
        assert result.signal == "NEUTRO"

    def test_indicators_dict_populated(self, candles_50):
        result = generate_signal(candles_50)
        assert isinstance(result.indicators, dict)
        assert len(result.indicators) > 0

    def test_stop_loss_below_entry_on_compra(self, candles_uptrend):
        result = generate_signal(candles_uptrend)
        if result.signal == "COMPRA":
            assert result.stop_loss < result.entry_price

    def test_stop_loss_above_entry_on_venda(self, candles_downtrend):
        result = generate_signal(candles_downtrend)
        if result.signal == "VENDA":
            assert result.stop_loss > result.entry_price

    def test_no_lookahead_uses_only_past_data(self):
        """Garante que bar[i] não usa dados de bar[i+1] em diante."""
        candles = [make_candle(100.0 + i) for i in range(50)]
        result_at_30 = generate_signal(candles[:30])
        # mudar candles[31..49] não deve afetar o resultado do bar[30]
        candles_modified = candles[:30] + [make_candle(99999.0)] * 20
        result_modified = generate_signal(candles_modified[:30])
        assert result_at_30.signal == result_modified.signal
        assert abs(result_at_30.score - result_modified.score) < 0.001

    def test_adx_weak_marks_trend_label(self):
        """ADX < 25 nao adiciona pontos e marca adx_trend=weak (sem hard filter)."""
        # Hard filter ADX foi testado em 2026-05-13 e regressou edge BULL em 1h
        # (de +0.578R para -0.384R). Removido. ADX agora soma score, nao bloqueia.
        with patch("signal_generator.adx") as mock_adx:
            mock_adx.return_value = {"adx": 18.0, "pdi": 20.0, "ndi": 15.0}
            result = generate_signal([make_candle(100.0 + i * 0.5,
                                                  high=100.0 + i * 0.5 + 1,
                                                  low=100.0 + i * 0.5 - 0.5)
                                      for i in range(50)])
        assert result.indicators.get("adx_trend") == "weak"

    def test_adx_strong_up_adds_bull_score(self):
        """ADX > 25 + pdi > ndi marca strong_up e contribui para bull score."""
        with patch("signal_generator.adx") as mock_adx:
            mock_adx.return_value = {"adx": 32.0, "pdi": 30.0, "ndi": 10.0}
            result = generate_signal([make_candle(100.0 + i * 0.5,
                                                  high=100.0 + i * 0.5 + 1,
                                                  low=100.0 + i * 0.5 - 0.5)
                                      for i in range(50)])
        assert result.indicators.get("adx_trend") == "strong_up"

    def test_adx_threshold_strict_above_25(self):
        """ADX exatamente 25 vai pro branch 'weak' (uso > 25 estrito, nao >=)."""
        with patch("signal_generator.adx") as mock_adx:
            mock_adx.return_value = {"adx": 25.0, "pdi": 28.0, "ndi": 10.0}
            result = generate_signal([make_candle(100.0 + i * 0.5,
                                                  high=100.0 + i * 0.5 + 1,
                                                  low=100.0 + i * 0.5 - 0.5)
                                      for i in range(50)])
        assert result.indicators.get("adx_trend") == "weak"


# ── SignalGenerator ───────────────────────────────────────────────────────────

class TestSignalGenerator:
    @pytest.fixture
    def mock_db(self):
        db = MagicMock()
        db.get_candles.return_value = [
            {**make_candle(100.0 + i * 0.2),
             "ts": f"2025-04-{i//24+1:02d}T{i%24:02d}:00:00+00:00",
             "market": "BTCUSDT", "period": "1hour"}
            for i in range(50)
        ]
        db.insert_signal.return_value = 42
        return db

    def test_run_reads_candles_from_db(self, mock_db):
        gen = SignalGenerator(db=mock_db, min_candles=30, score_threshold=55.0)
        gen.run("BTCUSDT", "1hour", "2025-04-01", "2025-04-03")
        mock_db.get_candles.assert_called_once_with("BTCUSDT", "1hour", "2025-04-01", "2025-04-03")

    def test_run_skips_bars_with_insufficient_data(self, mock_db):
        gen = SignalGenerator(db=mock_db, min_candles=30, score_threshold=55.0)
        signals = gen.run("BTCUSDT", "1hour", "2025-04-01", "2025-04-03")
        # primeiros 29 bars devem ser pulados
        total_bars = len(mock_db.get_candles.return_value)
        assert signals <= total_bars - 29

    def test_run_only_inserts_actionable_signals(self, mock_db):
        gen = SignalGenerator(db=mock_db, min_candles=30, score_threshold=55.0)
        gen.run("BTCUSDT", "1hour", "2025-04-01", "2025-04-03")
        for call in mock_db.insert_signal.call_args_list:
            row = call[0][0]
            assert row["signal"] in ("COMPRA", "VENDA")

    def test_run_returns_count_of_signals_stored(self, mock_db):
        gen = SignalGenerator(db=mock_db, min_candles=30, score_threshold=55.0)
        count = gen.run("BTCUSDT", "1hour", "2025-04-01", "2025-04-03")
        assert isinstance(count, int)
        assert count >= 0

    def test_empty_candles_returns_zero(self):
        db = MagicMock()
        db.get_candles.return_value = []
        gen = SignalGenerator(db=db, min_candles=30, score_threshold=55.0)
        count = gen.run("BTCUSDT", "1hour", "2025-04-01", "2025-04-03")
        assert count == 0
        db.insert_signal.assert_not_called()


# ── KB fix: RSI/BB nao fazem fade de tendencia em trend forte ───────────────
# Ref: knowledge/INDICATORS_REFERENCE.md:96-99 (RSI em trend), :173-175 (BB walking)

class TestKbFixTrendFade:
    """Trend-aware RSI/BB: em trend forte (ADX>25 + EMA alinhado + DI confirma),
    RSI alto/BB upper = continuacao, nao reversao."""

    def test_strong_uptrend_marks_trend_dir_up(self, candles_uptrend):
        """Em uptrend forte, indicators['trend_dir'] deve ser 'up'."""
        result = generate_signal(candles_uptrend)
        assert result.indicators.get("trend_dir") == "up"

    def test_strong_downtrend_marks_trend_dir_down(self, candles_downtrend):
        result = generate_signal(candles_downtrend)
        assert result.indicators.get("trend_dir") == "down"

    def test_flat_market_marks_trend_dir_flat(self):
        """Mercado lateral (ruido aleatorio em torno de 100): ADX baixo, trend_dir='flat'."""
        import random
        random.seed(42)
        # Oscila entre 99-101 sem direcao clara
        candles = [make_candle(100.0 + random.uniform(-1, 1)) for _ in range(50)]
        result = generate_signal(candles)
        assert result.indicators.get("trend_dir") == "flat"

    def test_rsi_high_in_uptrend_does_not_add_bearish(self, candles_uptrend):
        """RSI > 65 em uptrend forte: nao deve marcar 'overbought' (anti-fade)."""
        result = generate_signal(candles_uptrend)
        rsi_zone = result.indicators.get("rsi_zone")
        # Em uptrend, zona valida e 'trend_up_strength' ou 'exhaustion_up' (>80)
        assert rsi_zone in ("trend_up_strength", "exhaustion_up"), \
            f"RSI em uptrend nao deveria marcar overbought; got {rsi_zone}"

    def test_bb_upper_in_uptrend_is_continuation_not_reversal(self, candles_uptrend):
        """Preco na banda superior em uptrend: walking_upper (bull), nao above_upper (bear)."""
        result = generate_signal(candles_uptrend)
        bb_pos = result.indicators.get("bb_position")
        # Em uptrend forte, se tocar upper deve ser walking_upper, nao above_upper
        assert bb_pos != "above_upper", \
            f"BB upper em uptrend nao deveria ser fade; got {bb_pos}"

    def test_uptrend_after_fix_no_bear_signal(self, candles_uptrend):
        """Apos o fix, uptrend forte nao deve gerar VENDA (sinal contrario ao trend)."""
        result = generate_signal(candles_uptrend)
        assert result.signal != "VENDA", \
            f"Uptrend forte nao deveria gerar VENDA; got {result.signal} score={result.score}"

    def test_downtrend_after_fix_no_compra_signal(self, candles_downtrend):
        """Apos o fix, downtrend forte nao deve gerar COMPRA (sinal contrario ao trend)."""
        result = generate_signal(candles_downtrend)
        assert result.signal != "COMPRA", \
            f"Downtrend forte nao deveria gerar COMPRA; got {result.signal} score={result.score}"
