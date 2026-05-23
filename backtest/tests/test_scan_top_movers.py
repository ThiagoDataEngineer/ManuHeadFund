"""
test_scan_top_movers.py - TDD para scan_top_movers.py

PHASE 1 - RED: testes ANTES da implementacao.

Cobertura:
  - Filtra stablecoins e wrapped tokens
  - Filtra por marketcap minimo
  - Filtra por volume diario minimo
  - Rank top gainers / top losers
  - Anota regime simples (above/below SMA50 diario via 24h proxy)
  - Schema JSON output
"""
import pytest

from scan_top_movers import (
    is_stablecoin,
    is_wrapped_or_synthetic,
    filter_liquid_coins,
    rank_top_gainers,
    rank_top_losers,
    classify_simple_regime,
    build_movers_report,
    annotate_coinex_availability,
    filter_tradeable_on_coinex,
)


def _coin(symbol="BTC", mcap=1_000_000_000, vol=500_000_000, change_30d=10.0,
          change_24h=1.0, price=50000.0, sma50_proxy=None):
    return {
        "id":                   symbol.lower(),
        "symbol":               symbol.lower(),
        "name":                 symbol,
        "current_price":        price,
        "market_cap":           mcap,
        "total_volume":         vol,
        "price_change_percentage_30d_in_currency": change_30d,
        "price_change_percentage_24h": change_24h,
        "sma50_proxy":          sma50_proxy if sma50_proxy is not None else price * 0.95,
    }


# ============================================================================
# Filtros
# ============================================================================
def test_filter_stablecoins():
    assert is_stablecoin("USDT") is True
    assert is_stablecoin("usdc") is True
    assert is_stablecoin("DAI") is True
    assert is_stablecoin("BUSD") is True
    assert is_stablecoin("BTC") is False
    assert is_stablecoin("ETH") is False


def test_filter_wrapped_tokens():
    assert is_wrapped_or_synthetic("WBTC") is True
    assert is_wrapped_or_synthetic("WETH") is True
    assert is_wrapped_or_synthetic("stETH") is True
    assert is_wrapped_or_synthetic("BTC") is False


def test_filter_liquid_excludes_low_mcap():
    coins = [
        _coin("AAA", mcap=10_000_000),       # 10M - too small
        _coin("BBB", mcap=100_000_000),      # 100M - ok
        _coin("BTC", mcap=1_000_000_000),    # 1B - ok
    ]
    out = filter_liquid_coins(coins, min_mcap=50_000_000, min_volume=1_000_000)
    assert len(out) == 2
    syms = {c["symbol"] for c in out}
    assert "aaa" not in syms


def test_filter_liquid_excludes_low_volume():
    coins = [
        _coin("AAA", mcap=100_000_000, vol=100_000),     # baixo volume
        _coin("BTC", mcap=100_000_000, vol=500_000_000), # alto volume
    ]
    out = filter_liquid_coins(coins, min_mcap=50_000_000, min_volume=10_000_000)
    syms = {c["symbol"] for c in out}
    assert "aaa" not in syms
    assert "btc" in syms


def test_filter_liquid_excludes_stablecoins():
    coins = [
        _coin("USDT", mcap=100_000_000_000, vol=50_000_000_000),
        _coin("BTC",  mcap=1_000_000_000,  vol=500_000_000),
    ]
    out = filter_liquid_coins(coins, min_mcap=50_000_000, min_volume=10_000_000)
    syms = {c["symbol"] for c in out}
    assert "usdt" not in syms


# ============================================================================
# Ranking
# ============================================================================
def test_rank_top_gainers_descending():
    coins = [
        _coin("A", change_30d=10),
        _coin("B", change_30d=50),
        _coin("C", change_30d=30),
    ]
    top = rank_top_gainers(coins, n=2)
    assert len(top) == 2
    assert top[0]["symbol"] == "b"  # 50%
    assert top[1]["symbol"] == "c"  # 30%


def test_rank_top_losers_ascending():
    coins = [
        _coin("A", change_30d=-10),
        _coin("B", change_30d=-50),
        _coin("C", change_30d=-30),
    ]
    top = rank_top_losers(coins, n=2)
    assert top[0]["symbol"] == "b"  # -50%
    assert top[1]["symbol"] == "c"  # -30%


def test_rank_excludes_positive_from_losers():
    """Top losers só inclui mudancas <0."""
    coins = [
        _coin("A", change_30d=10),
        _coin("B", change_30d=-20),
    ]
    top = rank_top_losers(coins, n=5)
    syms = {c["symbol"] for c in top}
    assert syms == {"b"}


# ============================================================================
# Classificação regime simples
# ============================================================================
def test_classify_simple_regime_bull_when_above_sma50():
    """price > sma50_proxy => 'BULL'."""
    coin = _coin("BTC", price=50000, sma50_proxy=45000)
    assert classify_simple_regime(coin) == "BULL"


def test_classify_simple_regime_bear_when_below_sma50():
    coin = _coin("BTC", price=40000, sma50_proxy=45000)
    assert classify_simple_regime(coin) == "BEAR"


def test_classify_simple_regime_sideways_when_near_sma50():
    coin = _coin("BTC", price=45100, sma50_proxy=45000)  # ~0.2% above
    assert classify_simple_regime(coin) == "SIDEWAYS"


# ============================================================================
# Schema do report
# ============================================================================
# ============================================================================
# CoinEx availability
# ============================================================================
def test_annotate_coinex_marks_spot_only():
    coins = [_coin("BTC")]
    pairs = {"spot": {"BTCUSDT"}, "futures": set()}
    out = annotate_coinex_availability(coins, pairs)
    assert out[0]["coinex_spot"] is True
    assert out[0]["coinex_futures"] is False
    assert out[0]["coinex_availability"] == "SPOT_ONLY"


def test_annotate_coinex_marks_both():
    coins = [_coin("BTC")]
    pairs = {"spot": {"BTCUSDT"}, "futures": {"BTCUSDT"}}
    out = annotate_coinex_availability(coins, pairs)
    assert out[0]["coinex_availability"] == "BOTH"


def test_annotate_coinex_marks_not_available():
    coins = [_coin("XYZ")]
    pairs = {"spot": {"BTCUSDT"}, "futures": {"BTCUSDT"}}
    out = annotate_coinex_availability(coins, pairs)
    assert out[0]["coinex_availability"] == "NOT_AVAILABLE"


def test_filter_tradeable_keeps_only_coinex_listed():
    coins = [
        _coin("BTC"),
        _coin("XYZ"),  # nao listado
        _coin("ETH"),
    ]
    pairs = {"spot": {"BTCUSDT", "ETHUSDT"}, "futures": {"BTCUSDT"}}
    annotated = annotate_coinex_availability(coins, pairs)
    tradeable = filter_tradeable_on_coinex(annotated)
    syms = {c["symbol"] for c in tradeable}
    assert syms == {"btc", "eth"}


def test_report_schema():
    coins = [
        _coin("BTC", mcap=1_000_000_000_000, vol=50_000_000_000, change_30d=15, price=50000, sma50_proxy=45000),
        _coin("ETH", mcap=300_000_000_000,   vol=20_000_000_000, change_30d=8,  price=3000,  sma50_proxy=2900),
        _coin("XYZ", mcap=500_000_000,       vol=100_000_000,    change_30d=-25, price=10,    sma50_proxy=15),
    ]
    report = build_movers_report(coins, top_n=2)
    for k in ("timestamp_utc", "criteria", "top_gainers", "top_losers", "summary"):
        assert k in report
    assert isinstance(report["top_gainers"], list)
    assert isinstance(report["top_losers"], list)
    for entry in report["top_gainers"] + report["top_losers"]:
        for k in ("symbol", "name", "price", "change_30d_pct", "market_cap",
                  "volume_24h", "regime_simple", "long_long_or_short_long"):
            # 'long_long_or_short_long' eh proposito explicito (LONG_CANDIDATE / SHORT_CANDIDATE / AVOID)
            assert k in entry
