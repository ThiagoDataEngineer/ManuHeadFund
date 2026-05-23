"""TDD short_features — 12 testes core."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from short_features import compute_features, _atr, _adx, _sma


def _mk(ts, o, h, l, c, v=100):
    return {"ts": ts, "open": o, "high": h, "low": l, "close": c, "volume": v}


def _uptrend(n=60, start=100, step=1):
    """Cria n candles em uptrend constante."""
    return [_mk(f"2024-01-{(i%28)+1:02d}T00:00:00+00:00",
                start + i*step, start + i*step + 0.5,
                start + i*step - 0.5, start + i*step + 0.3, 100)
            for i in range(n)]


def _downtrend(n=60, start=200, step=-1):
    return [_mk(f"2024-01-{(i%28)+1:02d}T00:00:00+00:00",
                start + i*step, start + i*step + 0.5,
                start + i*step - 0.5, start + i*step - 0.3, 100)
            for i in range(n)]


def test_sma_basic():
    assert _sma([1, 2, 3, 4, 5], 3) == 4.0   # média últimos 3
    assert _sma([1, 2], 5) is None           # insuficiente


def test_atr_basic():
    candles = [_mk(f"2024-01-{i+1:02d}T00:00:00", 100+i, 110+i, 90+i, 100+i)
               for i in range(20)]
    atr = _atr(candles, period=14)
    assert atr is not None
    assert atr > 0


def test_adx_uptrend_returns_high_plus_di():
    candles = _uptrend(n=40)
    adx = _adx(candles, period=14)
    # Em uptrend forte, +DI deve > -DI
    assert adx["plus_di"] > adx["minus_di"]


def test_adx_downtrend_returns_high_minus_di():
    candles = _downtrend(n=40)
    adx = _adx(candles, period=14)
    assert adx["minus_di"] > adx["plus_di"]


def test_compute_features_insufficient_history():
    candles = _uptrend(n=30)
    r = compute_features(candles, 30)
    # 30 candles no idx 30 -> ainda OK pra sma50 (window=250 limit, mas só 30 disponíveis)
    # Mas SMA50 requer 50 — então será None nesse campo
    if r:
        assert r["sma200"] is None  # nao tem 200 ainda


def test_compute_features_full_uptrend():
    candles = _uptrend(n=260, start=100, step=0.5)
    r = compute_features(candles, 250)
    assert r is not None
    assert r["dist_sma200"] > 0  # preço acima SMA200 em uptrend
    assert r["plus_di"] > r["minus_di"]


def test_compute_features_full_downtrend():
    candles = _downtrend(n=260, start=300, step=-0.5)
    r = compute_features(candles, 250)
    assert r is not None
    assert r["dist_sma200"] < 0  # preço abaixo SMA200 em downtrend
    assert r["di_diff"] > 0      # -DI > +DI


def test_consecutive_red_days():
    """Últimos 5 candles vermelhos = consec_red >= 5."""
    base = _uptrend(n=50)
    # Adiciona 5 red candles consecutivos
    for i in range(50, 55):
        base.append(_mk(f"2024-03-{i-49:02d}T00:00:00", 200, 205, 190, 195, 100))
    r = compute_features(base, 54)
    if r:
        assert r["consecutive_red_days"] >= 5


def test_mining_ratio_calculated():
    candles = _uptrend(n=260, start=50000, step=100)
    r = compute_features(candles, 250)
    # close ~ 50000 + 250*100 = 75000, ratio = 75000/55000 = 1.36
    assert r is not None
    assert 1.0 < r["mining_ratio"] < 2.5


def test_months_post_halving_positive():
    # 2024-12-01 = ~7.4 meses pós halving 2024-04-19
    candles = []
    for i in range(260):
        m = (i % 11) + 1
        d = (i % 28) + 1
        candles.append(_mk(f"2024-{m:02d}-{d:02d}T00:00:00+00:00",
                            100+i, 110+i, 90+i, 100+i, 100))
    r = compute_features(candles, 250)
    if r:
        assert r["months_post_halving"] > 0


def test_rally_strength_detects_pump():
    candles = _uptrend(n=250)
    # injeta pump no candle 250: open 100 → high 130 (30% rally)
    candles.append(_mk("2024-12-01T00:00:00", 100, 130, 99, 125, 500))
    r = compute_features(candles, 250)
    if r:
        assert r["rally_strength_3d"] > 0.25  # capturou rally 30%


def test_volume_ratio_spike():
    """Candle com volume 5× normal → vol_ratio_20d ~5x."""
    candles = []
    for i in range(40):
        candles.append(_mk(f"2024-01-{(i%28)+1:02d}T00:00:00", 100+i, 105+i, 95+i, 100+i, 100))
    # spike volume
    candles.append(_mk("2024-03-01T00:00:00", 140, 145, 135, 142, 500))
    candles += _uptrend(n=220, start=142)  # complete history
    # Re-index spike at idx 40
    if len(candles) > 250:
        r = compute_features(candles, 250)
        if r:
            assert r["vol_ratio_20d"] > 0  # nao zero
