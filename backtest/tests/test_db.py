"""
TDD — db.py
Testa a camada de abstração REST do banco de dados usando mocks de requests.
Não faz chamadas reais ao Supabase.
"""
import pytest
from unittest.mock import MagicMock, patch
from db import Database


@pytest.fixture
def mock_requests_get():
    with patch("db.requests.get") as mock:
        mock.return_value.status_code = 200
        mock.return_value.json.return_value = []
        mock.return_value.raise_for_status.return_value = None
        yield mock


@pytest.fixture
def mock_requests_post():
    with patch("db.requests.post") as mock:
        mock.return_value.status_code = 201
        mock.return_value.json.return_value = [{"id": 42}]
        mock.return_value.text = '[{"id": 42}]'
        mock.return_value.raise_for_status.return_value = None
        yield mock


@pytest.fixture
def db():
    return Database(url="https://fake.supabase.co", key="fake-service-key")


# ── Inicialização ─────────────────────────────────────────────────────────────

class TestDatabaseInit:
    def test_init_requires_url_and_key(self):
        with pytest.raises((TypeError, KeyError)):
            Database()

    def test_init_stores_url_and_key(self, db):
        assert "fake.supabase.co" in db.url
        assert db.key == "fake-service-key"

    def test_init_sets_auth_headers(self, db):
        assert "Authorization" in db.headers
        assert "Bearer fake-service-key" in db.headers["Authorization"]


# ── Candles ───────────────────────────────────────────────────────────────────

class TestCandles:
    def test_upsert_candles_calls_post(self, db, mock_requests_post):
        candles = [
            {"market": "BTCUSDT", "period": "1hour", "ts": "2025-04-01T00:00:00+00:00",
             "open": 82000, "high": 82500, "low": 81800, "close": 82200, "volume": 100.5}
        ]
        db.upsert_candles(candles)
        mock_requests_post.assert_called_once()
        call_url = mock_requests_post.call_args[0][0]
        assert "candles" in call_url

    def test_upsert_candles_empty_list_does_nothing(self, db, mock_requests_post):
        db.upsert_candles([])
        mock_requests_post.assert_not_called()

    def test_upsert_uses_on_conflict(self, db, mock_requests_post):
        candles = [{"market": "BTCUSDT", "period": "1hour", "ts": "2025-04-01T00:00:00+00:00",
                    "open": 1, "high": 1, "low": 1, "close": 1, "volume": 1}]
        db.upsert_candles(candles)
        call_url = mock_requests_post.call_args[0][0]
        assert "on_conflict" in call_url

    def test_get_candles_calls_get(self, db, mock_requests_get):
        mock_requests_get.return_value.json.return_value = [{"market": "BTCUSDT", "close": 82000}]
        result = db.get_candles("BTCUSDT", "1hour", "2025-04-01", "2025-04-30")
        mock_requests_get.assert_called_once()
        assert isinstance(result, list)

    def test_get_candles_filters_market_period(self, db, mock_requests_get):
        mock_requests_get.return_value.json.return_value = []
        db.get_candles("ETHUSDT", "4hour", "2025-04-01", "2025-04-30")
        call_url = mock_requests_get.call_args[0][0]
        assert "candles" in call_url
        params = mock_requests_get.call_args[1].get("params", "") or mock_requests_get.call_args[0][0]
        assert "ETHUSDT" in str(mock_requests_get.call_args)


# ── Signals ───────────────────────────────────────────────────────────────────

class TestSignals:
    def test_insert_signal_calls_post(self, db, mock_requests_post):
        signal = {
            "market": "BTCUSDT", "period": "1hour", "bar_ts": "2025-04-01T01:00:00+00:00",
            "signal": "COMPRA", "score": 75, "entry_price": 82000,
            "stop_loss": 81500, "take_profit": 83500, "atr": 300, "indicators": {}
        }
        db.insert_signal(signal)
        mock_requests_post.assert_called_once()
        call_url = mock_requests_post.call_args[0][0]
        assert "backtest_signals" in call_url

    def test_insert_signal_returns_id(self, db, mock_requests_post):
        signal = {
            "market": "BTCUSDT", "period": "1hour", "bar_ts": "2025-04-01T01:00:00+00:00",
            "signal": "COMPRA", "score": 75, "entry_price": 82000,
            "stop_loss": 81500, "take_profit": 83500, "atr": 300, "indicators": {}
        }
        result = db.insert_signal(signal)
        assert result == 42


# ── Trades ────────────────────────────────────────────────────────────────────

class TestTrades:
    def test_insert_trade_calls_post(self, db, mock_requests_post):
        trade = {
            "signal_id": 1, "market": "BTCUSDT", "direction": "LONG",
            "entry_ts": "2025-04-01T01:00:00+00:00", "entry_price": 82000,
            "stop_loss": 81500, "take_profit": 83500,
            "exit_reason": "TARGET", "result_r": 3.0, "pnl_pct": 2.9, "capital_used": 1000
        }
        db.insert_trade(trade)
        call_url = mock_requests_post.call_args[0][0]
        assert "backtest_trades" in call_url


# ── Backtest Runs ─────────────────────────────────────────────────────────────

class TestBacktestRuns:
    def test_insert_run_calls_post(self, db, mock_requests_post):
        run = {
            "market": "BTCUSDT", "period": "1hour",
            "date_from": "2025-04-01", "date_to": "2025-05-01",
            "capital_initial": 1000, "total_trades": 50,
            "winning_trades": 30, "win_rate": 60.0,
            "expectancy_r": 1.2, "profit_factor": 2.5,
            "max_drawdown": 8.0, "sharpe_ratio": 1.4,
            "calmar_ratio": 0.9, "final_capital": 1800, "return_pct": 80.0
        }
        db.insert_run(run)
        call_url = mock_requests_post.call_args[0][0]
        assert "backtest_runs" in call_url

    def test_get_runs_returns_list(self, db, mock_requests_get):
        mock_requests_get.return_value.json.return_value = []
        result = db.get_runs()
        assert isinstance(result, list)
        call_url = mock_requests_get.call_args[0][0]
        assert "backtest_runs" in call_url
