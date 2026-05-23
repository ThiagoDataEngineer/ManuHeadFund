"""TDD compact curated coletor + liquidity haircut."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from curated_candidates import flatten_curated, SKIP_LIST, LIQUIDITY_HAIRCUT, MIN_VOL_USD_REAL, get_category


def test_flatten_dedup():
    flat = flatten_curated()
    assert len(flat) == len(set(flat))


def test_no_skip_in_curated():
    flat = flatten_curated()
    for skip in SKIP_LIST:
        assert skip not in flat


def test_zec_in_curated():
    assert "ZECUSDT" in flatten_curated()


def test_memes_excluded():
    flat = flatten_curated()
    assert "DOGEUSDT" in flat   # validation_pool
    assert "SHIBUSDT" not in flat  # skip list


def test_liquidity_haircut_value():
    assert LIQUIDITY_HAIRCUT == 0.7
    assert MIN_VOL_USD_REAL == 300_000


def test_get_category():
    assert get_category("ZECUSDT") == "privacy_mid_cap"
    assert get_category("BTCUSDT") == "majors_coinex"
    assert get_category("XYZUSDT") == "unknown"
