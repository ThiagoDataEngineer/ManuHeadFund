"""
TDD — backtest_runner.py
Pipeline: backtest_signals → simulate_trade (forward candles) → backtest_trades → backtest_runs
Regime: classify_regime(SMA200) aplicado por trade.
"""
from datetime import datetime, timezone
from unittest.mock import MagicMock
import pytest
from backtest_runner import BacktestRunner

BASE_TS = 1704067200000  # 2024-01-01 00:00:00 UTC


def _candles(n=250, base_close=40000.0, trend=1.0):
    """n candles de 1h com tendência linear controlada."""
    result = []
    for i in range(n):
        close = base_close + i * trend
        result.append({
            "ts": datetime.fromtimestamp(
                (BASE_TS + i * 3600000) / 1000, tz=timezone.utc
            ).isoformat(),
            "open":  close - 50.0,
            "high":  close + 100.0,
            "low":   close - 100.0,
            "close": close,
            "volume": 10.0,
        })
    return result


def _signal(bar_ts, signal_type="COMPRA", entry=40200.0, sid=1):
    stop   = entry * (0.98 if signal_type == "COMPRA" else 1.02)
    target = entry * (1.06 if signal_type == "COMPRA" else 0.94)
    return {
        "id": sid,
        "market": "BTCUSDT",
        "period": "1hour",
        "bar_ts": bar_ts,
        "signal": signal_type,
        "entry_price": entry,
        "stop_loss": stop,
        "take_profit": target,
    }


# ── Init ──────────────────────────────────────────────────────────────────────

class TestBacktestRunnerInit:
    def test_default_capital(self):
        r = BacktestRunner(db=MagicMock())
        assert r.capital == 1000.0

    def test_default_fee_pct(self):
        r = BacktestRunner(db=MagicMock())
        assert r.fee_pct == 0.10

    def test_custom_capital_and_fee(self):
        r = BacktestRunner(db=MagicMock(), capital=5000.0, fee_pct=0.05)
        assert r.capital == 5000.0
        assert r.fee_pct == 0.05


# ── _classify_by_sma200 ───────────────────────────────────────────────────────

class TestClassifyBySma200:
    def test_insufficient_candles_returns_sideways(self):
        r = BacktestRunner(db=MagicMock())
        assert r._classify_by_sma200(_candles(n=199)) == "sideways"

    def test_bull_when_price_far_above_sma200(self):
        r = BacktestRunner(db=MagicMock())
        candles = [{"close": 100.0}] * 199 + [{"close": 120.0}]  # +20% acima SMA
        assert r._classify_by_sma200(candles) == "bull"

    def test_bear_when_price_far_below_sma200(self):
        r = BacktestRunner(db=MagicMock())
        candles = [{"close": 100.0}] * 199 + [{"close": 80.0}]   # -20% abaixo SMA
        assert r._classify_by_sma200(candles) == "bear"

    def test_exactly_200_candles_is_accepted(self):
        r = BacktestRunner(db=MagicMock())
        candles = [{"close": 100.0}] * 200
        regime = r._classify_by_sma200(candles)
        assert regime in ("bull", "bear", "sideways")


# ── run() ─────────────────────────────────────────────────────────────────────

class TestBacktestRunnerRun:
    @pytest.fixture
    def mock_db(self):
        db = MagicMock()
        db.insert_trade.return_value = 1
        db.insert_run.return_value = 1
        return db

    @pytest.fixture
    def candles_250(self):
        return _candles(n=250)

    def test_returns_0_when_no_signals(self, mock_db, candles_250):
        mock_db.get_signals.return_value = []
        mock_db.get_candles.return_value = candles_250
        assert BacktestRunner(db=mock_db).run("BTCUSDT", "1hour", "2024-01-01", "2024-11-01") == 0

    def test_returns_0_when_no_candles(self, mock_db):
        mock_db.get_signals.return_value = [_signal("ts")]
        mock_db.get_candles.return_value = []
        assert BacktestRunner(db=mock_db).run("BTCUSDT", "1hour", "2024-01-01", "2024-11-01") == 0

    def test_inserts_trades_bulk_with_all_signals(self, mock_db, candles_250):
        """Runner usa insert_trades_bulk (perf): 1 call com todos os trades."""
        sigs = [
            _signal(candles_250[200]["ts"], "COMPRA", 40200.0, sid=1),
            _signal(candles_250[210]["ts"], "VENDA",  40210.0, sid=2),
        ]
        mock_db.get_signals.return_value = sigs
        mock_db.get_candles.return_value = candles_250
        BacktestRunner(db=mock_db).run("BTCUSDT", "1hour", "2024-01-01", "2024-11-01")
        assert mock_db.insert_trades_bulk.call_count == 1
        bulk_arg = mock_db.insert_trades_bulk.call_args[0][0]
        assert len(bulk_arg) == 2

    def test_inserts_run_once(self, mock_db, candles_250):
        mock_db.get_signals.return_value = [_signal(candles_250[200]["ts"])]
        mock_db.get_candles.return_value = candles_250
        BacktestRunner(db=mock_db).run("BTCUSDT", "1hour", "2024-01-01", "2024-11-01")
        mock_db.insert_run.assert_called_once()

    def test_returns_total_trade_count(self, mock_db, candles_250):
        sigs = [
            _signal(candles_250[200]["ts"], sid=1),
            _signal(candles_250[210]["ts"], sid=2),
        ]
        mock_db.get_signals.return_value = sigs
        mock_db.get_candles.return_value = candles_250
        count = BacktestRunner(db=mock_db).run("BTCUSDT", "1hour", "2024-01-01", "2024-11-01")
        assert count == 2

    def test_compra_uses_long_direction(self, mock_db, candles_250):
        mock_db.get_signals.return_value = [_signal(candles_250[200]["ts"], "COMPRA")]
        mock_db.get_candles.return_value = candles_250
        BacktestRunner(db=mock_db).run("BTCUSDT", "1hour", "2024-01-01", "2024-11-01")
        assert mock_db.insert_trades_bulk.call_args[0][0][0]["direction"] == "LONG"

    def test_venda_uses_short_direction(self, mock_db, candles_250):
        mock_db.get_signals.return_value = [_signal(candles_250[200]["ts"], "VENDA", 40200.0)]
        mock_db.get_candles.return_value = candles_250
        BacktestRunner(db=mock_db).run("BTCUSDT", "1hour", "2024-01-01", "2024-11-01")
        assert mock_db.insert_trades_bulk.call_args[0][0][0]["direction"] == "SHORT"

    def test_trade_row_has_regime(self, mock_db, candles_250):
        mock_db.get_signals.return_value = [_signal(candles_250[200]["ts"])]
        mock_db.get_candles.return_value = candles_250
        BacktestRunner(db=mock_db).run("BTCUSDT", "1hour", "2024-01-01", "2024-11-01")
        trade_row = mock_db.insert_trades_bulk.call_args[0][0][0]
        assert "regime" in trade_row
        assert trade_row["regime"] in ("bull", "bear", "sideways")

    def test_run_row_has_regime_breakdown(self, mock_db, candles_250):
        mock_db.get_signals.return_value = [_signal(candles_250[200]["ts"])]
        mock_db.get_candles.return_value = candles_250
        BacktestRunner(db=mock_db).run("BTCUSDT", "1hour", "2024-01-01", "2024-11-01")
        run_row = mock_db.insert_run.call_args[0][0]
        assert "regime_breakdown" in run_row
        rb = run_row["regime_breakdown"]
        assert "counts" in rb
        assert "bull" in rb and "bear" in rb and "sideways" in rb

    def test_skips_signal_with_unknown_bar_ts(self, mock_db, candles_250):
        mock_db.get_signals.return_value = [_signal("1999-01-01T00:00:00+00:00")]
        mock_db.get_candles.return_value = candles_250
        result = BacktestRunner(db=mock_db).run("BTCUSDT", "1hour", "2024-01-01", "2024-11-01")
        assert result == 0
        mock_db.insert_trade.assert_not_called()

    def test_skips_signal_with_no_forward_candles(self, mock_db, candles_250):
        # último candle → sem candles à frente
        mock_db.get_signals.return_value = [_signal(candles_250[-1]["ts"])]
        mock_db.get_candles.return_value = candles_250
        result = BacktestRunner(db=mock_db).run("BTCUSDT", "1hour", "2024-01-01", "2024-11-01")
        assert result == 0
        mock_db.insert_trade.assert_not_called()

    def test_run_row_has_combined_metrics(self, mock_db, candles_250):
        mock_db.get_signals.return_value = [_signal(candles_250[200]["ts"])]
        mock_db.get_candles.return_value = candles_250
        BacktestRunner(db=mock_db).run("BTCUSDT", "1hour", "2024-01-01", "2024-11-01")
        run_row = mock_db.insert_run.call_args[0][0]
        for field in ("total_trades", "winning_trades", "win_rate",
                      "expectancy_r", "profit_factor", "max_drawdown", "sharpe_ratio"):
            assert field in run_row, f"campo ausente: {field}"
