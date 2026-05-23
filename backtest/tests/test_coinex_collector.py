"""TDD coinex_collector — smoke tests usando endpoints publicos."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from coinex_collector import _ts_to_iso


def test_ts_to_iso_ms():
    """1700000000000 ms = 2023-11-14T22:13:20+00:00"""
    s = _ts_to_iso(1700000000000)
    assert s.startswith("2023-11-14")


def test_ts_to_iso_secs():
    """1700000000 (sec) tambem funciona"""
    s = _ts_to_iso(1700000000)
    assert s.startswith("2023-11-14")


def test_ts_to_iso_returns_iso_format():
    s = _ts_to_iso(1700000000000)
    assert "T" in s
    assert "+00:00" in s
