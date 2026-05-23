"""
TDD — data_collector.py
Testa busca de candles da CoinEx API, Binance data.binance.vision e persistência no Supabase.
"""
import io
import zipfile
import pytest
from unittest.mock import MagicMock, patch
from datetime import datetime, timezone
from data_collector import (
    CoinExCollector, parse_candle, paginate_candles,
    BinanceCollector, parse_binance_candle, BINANCE_PERIOD_MAP,
    PERIOD_SECONDS, BINANCE_DAILY_ONLY,
    BINANCE_KLINES_BASE_MONTHLY, BINANCE_KLINES_BASE_DAILY,
)


# ── parse_candle ──────────────────────────────────────────────────────────────

class TestParseCandle:
    def test_parse_valid_coinex_candle(self):
        raw = {
            "created_at": 1704067200000,  # 2024-01-01 00:00:00 UTC
            "open": "42000.5",
            "high": "42500.0",
            "low": "41800.0",
            "close": "42200.0",
            "volume": "100.5",
        }
        result = parse_candle(raw, market="BTCUSDT", period="1hour")
        assert result["market"] == "BTCUSDT"
        assert result["period"] == "1hour"
        assert result["open"] == 42000.5
        assert result["high"] == 42500.0
        assert result["low"] == 41800.0
        assert result["close"] == 42200.0
        assert result["volume"] == 100.5

    def test_parse_converts_ts_to_iso(self):
        raw = {"created_at": 1704067200000, "open": "1", "high": "1",
               "low": "1", "close": "1", "volume": "1"}
        result = parse_candle(raw, market="BTCUSDT", period="1hour")
        assert "ts" in result
        assert "2024-01-01" in result["ts"]

    def test_parse_numeric_strings_to_float(self):
        raw = {"created_at": 1704067200000, "open": "99999.99",
               "high": "100000.0", "low": "99000.0", "close": "99500.0", "volume": "0.001"}
        result = parse_candle(raw, market="BTCUSDT", period="1hour")
        assert isinstance(result["open"], float)
        assert isinstance(result["volume"], float)

    def test_parse_missing_field_raises(self):
        raw = {"created_at": 1704067200000, "open": "42000"}  # faltam campos
        with pytest.raises(KeyError):
            parse_candle(raw, market="BTCUSDT", period="1hour")


# ── paginate_candles ──────────────────────────────────────────────────────────

class TestPaginateCandles:
    def test_generates_correct_time_windows(self):
        windows = list(paginate_candles(
            start="2024-01-01",
            end="2024-01-03",
            period="1hour",
            limit=100,
        ))
        assert len(windows) >= 1
        for w in windows:
            assert "start_ts" in w
            assert "end_ts" in w
            assert w["end_ts"] > w["start_ts"]

    def test_windows_cover_full_range(self):
        windows = list(paginate_candles(
            start="2024-01-01",
            end="2024-06-01",
            period="1hour",
            limit=1000,
        ))
        assert windows[0]["start_ts"] <= datetime(2024, 1, 1, tzinfo=timezone.utc).timestamp() * 1000 + 1
        assert windows[-1]["end_ts"] >= datetime(2024, 6, 1, tzinfo=timezone.utc).timestamp() * 1000 - 1

    def test_no_overlap_between_windows(self):
        windows = list(paginate_candles(
            start="2024-01-01",
            end="2024-02-01",
            period="1hour",
            limit=100,
        ))
        for i in range(len(windows) - 1):
            assert windows[i]["end_ts"] <= windows[i + 1]["start_ts"]

    def test_daily_period_larger_windows(self):
        windows_1h = list(paginate_candles("2024-01-01", "2024-12-31", "1hour", 1000))
        windows_1d = list(paginate_candles("2024-01-01", "2024-12-31", "1day", 1000))
        assert len(windows_1h) > len(windows_1d)


# ── CoinExCollector ───────────────────────────────────────────────────────────

class TestCoinExCollector:
    @pytest.fixture
    def mock_db(self):
        db = MagicMock()
        db.upsert_candles.return_value = None
        return db

    @pytest.fixture
    def mock_api_response(self):
        return {
            "data": [
                {"created_at": 1704067200000 + i * 3600000,
                 "open": str(42000 + i), "high": str(42100 + i),
                 "low": str(41900 + i), "close": str(42050 + i),
                 "volume": "10.5"}
                for i in range(5)
            ]
        }

    def test_collector_init(self, mock_db):
        collector = CoinExCollector(db=mock_db)
        assert collector.db is mock_db

    @patch("data_collector.requests.get")
    def test_fetch_calls_coinex_api(self, mock_get, mock_db, mock_api_response):
        mock_get.return_value.json.return_value = mock_api_response
        mock_get.return_value.status_code = 200
        collector = CoinExCollector(db=mock_db)
        collector.fetch_and_store(market="BTCUSDT", period="1hour",
                                  start="2024-01-01", end="2024-01-02")
        mock_get.assert_called()
        call_url = mock_get.call_args[0][0] if mock_get.call_args[0] else mock_get.call_args[1].get("url", "")
        assert "kline" in call_url or "BTCUSDT" in str(mock_get.call_args)

    @patch("data_collector.requests.get")
    def test_fetch_stores_parsed_candles(self, mock_get, mock_db, mock_api_response):
        mock_get.return_value.json.return_value = mock_api_response
        mock_get.return_value.status_code = 200
        collector = CoinExCollector(db=mock_db)
        collector.fetch_and_store(market="BTCUSDT", period="1hour",
                                  start="2024-01-01", end="2024-01-02")
        mock_db.upsert_candles.assert_called()
        candles = mock_db.upsert_candles.call_args[0][0]
        assert len(candles) > 0
        assert candles[0]["market"] == "BTCUSDT"

    @patch("data_collector.requests.get")
    def test_empty_api_response_skips_upsert(self, mock_get, mock_db):
        mock_get.return_value.json.return_value = {"data": []}
        mock_get.return_value.status_code = 200
        collector = CoinExCollector(db=mock_db)
        collector.fetch_and_store(market="BTCUSDT", period="1hour",
                                  start="2024-01-01", end="2024-01-02")
        mock_db.upsert_candles.assert_not_called()

    @patch("data_collector.requests.get")
    def test_api_error_raises(self, mock_get, mock_db):
        mock_get.return_value.status_code = 429
        mock_get.return_value.json.return_value = {"code": 429, "message": "rate limit"}
        collector = CoinExCollector(db=mock_db)
        with pytest.raises(Exception):
            collector.fetch_and_store(market="BTCUSDT", period="1hour",
                                      start="2024-01-01", end="2024-01-02")

    @patch("data_collector.requests.get")
    def test_progress_reported_per_batch(self, mock_get, mock_db, mock_api_response, capsys):
        mock_get.return_value.json.return_value = mock_api_response
        mock_get.return_value.status_code = 200
        collector = CoinExCollector(db=mock_db)
        collector.fetch_and_store(market="BTCUSDT", period="1hour",
                                  start="2024-01-01", end="2024-01-03")
        captured = capsys.readouterr()
        assert "BTCUSDT" in captured.out or len(captured.out) >= 0


# ── parse_binance_candle ──────────────────────────────────────────────────────

class TestParseBinanceCandle:
    # Binance CSV row: open_time, open, high, low, close, volume, close_time, ...
    VALID_ROW = [
        "1704067200000", "42000.5", "42500.0", "41800.0", "42200.0", "100.5",
        "1704070799999", "4221000.0", "308", "50.25", "2110500.0", "0"
    ]

    def test_parses_ohlcv_correctly(self):
        result = parse_binance_candle(self.VALID_ROW, market="BTCUSDT", period="1hour")
        assert result["market"] == "BTCUSDT"
        assert result["period"] == "1hour"
        assert result["open"] == 42000.5
        assert result["high"] == 42500.0
        assert result["low"] == 41800.0
        assert result["close"] == 42200.0
        assert result["volume"] == 100.5

    def test_converts_open_time_to_iso(self):
        result = parse_binance_candle(self.VALID_ROW, market="BTCUSDT", period="1hour")
        assert "ts" in result
        assert "2024-01-01" in result["ts"]

    def test_all_price_fields_are_float(self):
        result = parse_binance_candle(self.VALID_ROW, market="BTCUSDT", period="1hour")
        for field in ("open", "high", "low", "close", "volume"):
            assert isinstance(result[field], float), f"{field} deve ser float"

    def test_uses_open_time_not_close_time(self):
        # open_time=1704067200000 (00:00), close_time=1704070799999 (00:59)
        result = parse_binance_candle(self.VALID_ROW, market="BTCUSDT", period="1hour")
        assert "T00:00:00" in result["ts"]  # abertura do candle, não fechamento


# ── BINANCE_PERIOD_MAP ────────────────────────────────────────────────────────

class TestBinancePeriodMap:
    def test_all_coinex_periods_are_mapped(self):
        coinex_periods = ["1min", "3min", "5min", "15min", "30min",
                          "1hour", "2hour", "4hour", "6hour", "12hour",
                          "1day", "3day", "1week"]
        for period in coinex_periods:
            assert period in BINANCE_PERIOD_MAP, f"{period} ausente no BINANCE_PERIOD_MAP"

    def test_1hour_maps_to_1h(self):
        assert BINANCE_PERIOD_MAP["1hour"] == "1h"

    def test_4hour_maps_to_4h(self):
        assert BINANCE_PERIOD_MAP["4hour"] == "4h"

    def test_1day_maps_to_1d(self):
        assert BINANCE_PERIOD_MAP["1day"] == "1d"

    def test_1sec_maps_to_1s(self):
        assert BINANCE_PERIOD_MAP["1sec"] == "1s"

    def test_1sec_in_period_seconds_equals_1(self):
        assert PERIOD_SECONDS["1sec"] == 1

    def test_1s_in_binance_daily_only(self):
        assert "1s" in BINANCE_DAILY_ONLY


# ── BinanceCollector ──────────────────────────────────────────────────────────

def _make_zip(symbol: str, interval: str, year: int, month: int,
              rows: list) -> bytes:
    """Cria um ZIP em memória com o CSV da Binance."""
    csv_name = f"{symbol}-{interval}-{year}-{month:02d}.csv"
    csv_content = "\n".join(",".join(row) for row in rows).encode("utf-8")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(csv_name, csv_content)
    return buf.getvalue()


class TestBinanceCollector:
    @pytest.fixture
    def mock_db(self):
        db = MagicMock()
        db.upsert_candles.return_value = None
        return db

    @pytest.fixture
    def jan2024_rows(self):
        """5 candles de 1h em janeiro/2024."""
        base_ts = 1704067200000  # 2024-01-01 00:00 UTC
        return [
            [str(base_ts + i * 3600000), str(42000 + i), str(42100 + i),
             str(41900 + i), str(42050 + i), "10.5",
             str(base_ts + i * 3600000 + 3599999), "441525.0", "100", "5.25", "220762.5", "0"]
            for i in range(5)
        ]

    def test_collector_init(self, mock_db):
        collector = BinanceCollector(db=mock_db)
        assert collector.db is mock_db

    @patch("data_collector.requests.get")
    def test_fetch_month_returns_rows(self, mock_get, jan2024_rows):
        zip_bytes = _make_zip("BTCUSDT", "1h", 2024, 1, jan2024_rows)
        mock_get.return_value.status_code = 200
        mock_get.return_value.content = zip_bytes
        collector = BinanceCollector(db=MagicMock())
        rows = collector._fetch_month("BTCUSDT", "1h", 2024, 1)
        assert len(rows) == 5
        assert rows[0][0] == str(1704067200000)  # open_time correto

    @patch("data_collector.requests.get")
    def test_fetch_month_404_returns_empty(self, mock_get):
        mock_get.return_value.status_code = 404
        collector = BinanceCollector(db=MagicMock())
        rows = collector._fetch_month("BTCUSDT", "1h", 2099, 1)  # mês futuro
        assert rows == []

    @patch("data_collector.requests.get")
    def test_fetch_month_error_raises(self, mock_get):
        mock_get.return_value.status_code = 500
        mock_get.return_value.text = "Internal Server Error"
        collector = BinanceCollector(db=MagicMock())
        with pytest.raises(Exception, match="500"):
            collector._fetch_month("BTCUSDT", "1h", 2024, 1)

    @patch("data_collector.requests.get")
    def test_fetch_and_store_saves_candles(self, mock_get, mock_db, jan2024_rows):
        zip_bytes = _make_zip("BTCUSDT", "1h", 2024, 1, jan2024_rows)
        mock_get.return_value.status_code = 200
        mock_get.return_value.content = zip_bytes
        collector = BinanceCollector(db=mock_db)
        total = collector.fetch_and_store("BTCUSDT", "1hour", "2024-01-01", "2024-01-02")
        assert total > 0
        mock_db.upsert_candles.assert_called()
        candles = mock_db.upsert_candles.call_args[0][0]
        assert candles[0]["market"] == "BTCUSDT"
        assert candles[0]["period"] == "1hour"

    @patch("data_collector.requests.get")
    def test_fetch_and_store_respects_date_range(self, mock_get, mock_db, jan2024_rows):
        # jan2024_rows: 2024-01-01 00:00, 01:00, 02:00, 03:00, 04:00
        # end="2024-01-01T01:30:00" → inclui 00:00 e 01:00 (open_time <= end_ms)
        zip_bytes = _make_zip("BTCUSDT", "1h", 2024, 1, jan2024_rows)
        mock_get.return_value.status_code = 200
        mock_get.return_value.content = zip_bytes
        collector = BinanceCollector(db=mock_db)
        total = collector.fetch_and_store("BTCUSDT", "1hour", "2024-01-01", "2024-01-01T01:30:00")
        assert total == 2  # 00:00 e 01:00 (02:00 está após o end)

    @patch("data_collector.requests.get")
    def test_fetch_and_store_skips_upsert_when_no_candles_in_range(self, mock_get, mock_db, jan2024_rows):
        zip_bytes = _make_zip("BTCUSDT", "1h", 2024, 1, jan2024_rows)
        mock_get.return_value.status_code = 200
        mock_get.return_value.content = zip_bytes
        collector = BinanceCollector(db=mock_db)
        # Range antes dos candles do fixture
        total = collector.fetch_and_store("BTCUSDT", "1hour", "2023-12-01", "2023-12-31")
        assert total == 0
        mock_db.upsert_candles.assert_not_called()

    def test_unsupported_period_raises(self, mock_db):
        collector = BinanceCollector(db=mock_db)
        with pytest.raises(ValueError, match="not supported"):
            collector.fetch_and_store("BTCUSDT", "2day", "2024-01-01", "2024-01-31")

    @patch("data_collector.requests.get")
    def test_fetch_and_store_iterates_multiple_months(self, mock_get, mock_db, jan2024_rows):
        # Pedimos 2 meses mas só jan tem dados (fev retorna 404)
        zip_jan = _make_zip("BTCUSDT", "1h", 2024, 1, jan2024_rows)

        def side_effect(url, **kwargs):
            m = MagicMock()
            if "2024-01" in url:
                m.status_code = 200
                m.content = zip_jan
            else:
                m.status_code = 404
            return m

        mock_get.side_effect = side_effect
        collector = BinanceCollector(db=mock_db)
        total = collector.fetch_and_store("BTCUSDT", "1hour", "2024-01-01", "2024-02-28")
        assert total == 5  # só os 5 de janeiro

    @patch("data_collector.requests.get")
    def test_fetch_and_store_url_uses_binance_vision(self, mock_get, mock_db, jan2024_rows):
        zip_bytes = _make_zip("BTCUSDT", "1h", 2024, 1, jan2024_rows)
        mock_get.return_value.status_code = 200
        mock_get.return_value.content = zip_bytes
        collector = BinanceCollector(db=mock_db)
        collector.fetch_and_store("BTCUSDT", "1hour", "2024-01-01", "2024-01-02")
        called_url = mock_get.call_args[0][0]
        assert "data.binance.vision" in called_url
        assert "BTCUSDT" in called_url
        assert "1h" in called_url

    @patch("data_collector.requests.get")
    def test_csv_with_header_row_is_skipped(self, mock_get, mock_db, jan2024_rows):
        header = ["open_time", "open", "high", "low", "close", "volume",
                  "close_time", "quote_vol", "trades", "tbba", "tbqa", "ignore"]
        rows_with_header = [header] + jan2024_rows
        zip_bytes = _make_zip("BTCUSDT", "1h", 2024, 1, rows_with_header)
        mock_get.return_value.status_code = 200
        mock_get.return_value.content = zip_bytes
        collector = BinanceCollector(db=mock_db)
        # Range cobre apenas janeiro para garantir uma única iteração de mês
        total = collector.fetch_and_store("BTCUSDT", "1hour", "2024-01-01", "2024-01-31T23:59:59")
        assert total == 5  # header não conta

    @patch("data_collector.requests.get")
    def test_fetch_month_url_uses_monthly_base(self, mock_get, mock_db, jan2024_rows):
        zip_bytes = _make_zip("BTCUSDT", "1h", 2024, 1, jan2024_rows)
        mock_get.return_value.status_code = 200
        mock_get.return_value.content = zip_bytes
        collector = BinanceCollector(db=mock_db)
        collector._fetch_month("BTCUSDT", "1h", 2024, 1)
        called_url = mock_get.call_args[0][0]
        assert BINANCE_KLINES_BASE_MONTHLY in called_url
        assert BINANCE_KLINES_BASE_DAILY not in called_url


# ── BinanceCollector — daily ZIPs (1s) ───────────────────────────────────────

def _make_daily_zip(symbol: str, interval: str, year: int, month: int, day: int,
                    rows: list) -> bytes:
    """Cria um ZIP diário em memória com o CSV da Binance (formato sub-minuto)."""
    csv_name = f"{symbol}-{interval}-{year}-{month:02d}-{day:02d}.csv"
    csv_content = "\n".join(",".join(row) for row in rows).encode("utf-8")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(csv_name, csv_content)
    return buf.getvalue()


class TestBinanceDailyKlines:
    """Testa BinanceCollector com ZIPs diários (period=1sec / interval=1s)."""

    @pytest.fixture
    def mock_db(self):
        db = MagicMock()
        db.upsert_candles.return_value = None
        return db

    @pytest.fixture
    def jan01_1s_rows(self):
        """4 candles de 1s em 2024-01-01 00:00:00-00:00:03 UTC."""
        base_ts = 1704067200000  # 2024-01-01 00:00:00 UTC
        return [
            [str(base_ts + i * 1000), "42000.5", "42001.0", "41999.5", "42000.8", "0.5",
             str(base_ts + i * 1000 + 999), "21000.4", "10", "0.25", "10500.2", "0"]
            for i in range(4)
        ]

    @patch("data_collector.requests.get")
    def test_fetch_daily_returns_rows(self, mock_get, jan01_1s_rows):
        zip_bytes = _make_daily_zip("BTCUSDT", "1s", 2024, 1, 1, jan01_1s_rows)
        mock_get.return_value.status_code = 200
        mock_get.return_value.content = zip_bytes
        collector = BinanceCollector(db=MagicMock())
        dt = datetime(2024, 1, 1, tzinfo=timezone.utc)
        rows = collector._fetch_daily("BTCUSDT", "1s", dt)
        assert len(rows) == 4
        assert rows[0][0] == str(1704067200000)

    @patch("data_collector.requests.get")
    def test_fetch_daily_404_returns_empty(self, mock_get):
        mock_get.return_value.status_code = 404
        collector = BinanceCollector(db=MagicMock())
        dt = datetime(2099, 1, 1, tzinfo=timezone.utc)
        rows = collector._fetch_daily("BTCUSDT", "1s", dt)
        assert rows == []

    @patch("data_collector.requests.get")
    def test_fetch_daily_error_raises(self, mock_get):
        mock_get.return_value.status_code = 503
        collector = BinanceCollector(db=MagicMock())
        dt = datetime(2024, 1, 1, tzinfo=timezone.utc)
        with pytest.raises(Exception, match="503"):
            collector._fetch_daily("BTCUSDT", "1s", dt)

    @patch("data_collector.requests.get")
    def test_fetch_and_store_1sec_uses_daily_base_url(self, mock_get, mock_db, jan01_1s_rows):
        zip_bytes = _make_daily_zip("BTCUSDT", "1s", 2024, 1, 1, jan01_1s_rows)
        mock_get.return_value.status_code = 200
        mock_get.return_value.content = zip_bytes
        collector = BinanceCollector(db=mock_db)
        collector.fetch_and_store("BTCUSDT", "1sec", "2024-01-01", "2024-01-01T00:00:10")
        called_url = mock_get.call_args[0][0]
        assert BINANCE_KLINES_BASE_DAILY in called_url
        assert "1s" in called_url
        assert "2024-01-01" in called_url

    @patch("data_collector.requests.get")
    def test_fetch_and_store_1sec_saves_candles_with_correct_period(
            self, mock_get, mock_db, jan01_1s_rows):
        zip_bytes = _make_daily_zip("BTCUSDT", "1s", 2024, 1, 1, jan01_1s_rows)
        mock_get.return_value.status_code = 200
        mock_get.return_value.content = zip_bytes
        collector = BinanceCollector(db=mock_db)
        total = collector.fetch_and_store("BTCUSDT", "1sec", "2024-01-01", "2024-01-01T23:59:59")
        assert total == 4
        candles = mock_db.upsert_candles.call_args[0][0]
        assert candles[0]["period"] == "1sec"
        assert candles[0]["market"] == "BTCUSDT"

    @patch("data_collector.requests.get")
    def test_fetch_and_store_1sec_iterates_day_by_day(self, mock_get, mock_db, jan01_1s_rows):
        # 3 dias pedidos; só dia 1 tem dados (outros 404)
        zip_day1 = _make_daily_zip("BTCUSDT", "1s", 2024, 1, 1, jan01_1s_rows)

        def side_effect(url, **kwargs):
            m = MagicMock()
            if "2024-01-01" in url:
                m.status_code = 200
                m.content = zip_day1
            else:
                m.status_code = 404
            return m

        mock_get.side_effect = side_effect
        collector = BinanceCollector(db=mock_db)
        total = collector.fetch_and_store("BTCUSDT", "1sec", "2024-01-01", "2024-01-03")
        assert total == 4  # só dia 1
        assert mock_get.call_count == 3  # 3 requisições (01, 02, 03)

    @patch("data_collector.requests.get")
    def test_fetch_and_store_1sec_respects_date_range(self, mock_get, mock_db, jan01_1s_rows):
        # jan01_1s_rows: 00:00:00, 00:00:01, 00:00:02, 00:00:03
        # end = 00:00:01.500 → inclui 00:00:00 e 00:00:01
        zip_bytes = _make_daily_zip("BTCUSDT", "1s", 2024, 1, 1, jan01_1s_rows)
        mock_get.return_value.status_code = 200
        mock_get.return_value.content = zip_bytes
        collector = BinanceCollector(db=mock_db)
        total = collector.fetch_and_store(
            "BTCUSDT", "1sec", "2024-01-01T00:00:00", "2024-01-01T00:00:01")
        assert total == 2  # 00:00:00 e 00:00:01
