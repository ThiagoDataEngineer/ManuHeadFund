"""
test_transition_up_drilldown.py — TDD strict para transition_up_drilldown.py

PHASE 1 — RED: 13 testes ANTES da implementação.

Cobertura:
  - Buckets ADX, RSI, hora BRT (UTC-3), DoW, volume relativo
  - Segmentação por dimensão única
  - Métricas por bucket (trades/exp/pf/wr)
  - Find best sub-setup
  - Apply rule a holdout (sem otimizar)
  - Decisão VIABLE / NEEDS_MORE_DATA / NO_EDGE
  - Schema JSON

NÃO MODIFICA: db.py, signal_generator.py, metrics.py.
"""
import json
import pytest

from transition_up_drilldown import (
    bucket_adx,
    bucket_rsi,
    bucket_hour_brt,
    bucket_dow,
    bucket_volume,
    enrich_trades_with_entry_context,
    segment_by_bucket,
    metrics_per_bucket,
    find_best_subsetup,
    apply_subsetup_filter,
    decide_subsetup,
    build_subsetup_report,
)


def _trade(year=2020, month=6, day=15, hour=12, r=0.5, adx=22, rsi=55, vol_ratio=1.1):
    """Trade enriquecido sintético."""
    return {
        "entry_ts": f"{year}-{month:02d}-{day:02d}T{hour:02d}:00:00+00:00",
        "exit_ts":  f"{year}-{month:02d}-{day+1:02d}T{hour:02d}:00:00+00:00",
        "result_r": r,
        "direction": "LONG",
        "regime": "TRANSITION_UP",
        "_adx_entry": adx,
        "_rsi_entry": rsi,
        "_vol_ratio_entry": vol_ratio,
    }


# ============================================================================
# TEST 1 — Bucket ADX
# ============================================================================
def test_bucket_adx_thresholds():
    assert bucket_adx(10) == "<15"
    assert bucket_adx(14.99) == "<15"
    assert bucket_adx(15) == "15-20"
    assert bucket_adx(19.99) == "15-20"
    assert bucket_adx(20) == "20-25"
    assert bucket_adx(24.99) == "20-25"
    assert bucket_adx(25) == ">25"
    assert bucket_adx(50) == ">25"


# ============================================================================
# TEST 2 — Bucket RSI
# ============================================================================
def test_bucket_rsi_thresholds():
    assert bucket_rsi(30) == "<40"
    assert bucket_rsi(39.99) == "<40"
    assert bucket_rsi(40) == "40-60"
    assert bucket_rsi(59.99) == "40-60"
    assert bucket_rsi(60) == ">60"
    assert bucket_rsi(80) == ">60"


# ============================================================================
# TEST 3 — Hora BRT (UTC -3)
# ============================================================================
def test_bucket_hour_brt_conversion():
    """ts UTC 12:00 → 09:00 BRT; ts 02:00 UTC → 23:00 BRT (dia anterior)."""
    # 12:00 UTC = 09:00 BRT
    assert bucket_hour_brt("2020-06-15T12:00:00+00:00") == 9
    # 00:00 UTC = 21:00 BRT (dia anterior)
    assert bucket_hour_brt("2020-06-15T00:00:00+00:00") == 21
    # 03:00 UTC = 00:00 BRT
    assert bucket_hour_brt("2020-06-15T03:00:00+00:00") == 0


# ============================================================================
# TEST 4 — Dia da semana
# ============================================================================
def test_bucket_dow_name():
    # 2020-06-15 foi segunda
    assert bucket_dow("2020-06-15T12:00:00+00:00") == "Mon"
    # 2020-06-16 terça
    assert bucket_dow("2020-06-16T12:00:00+00:00") == "Tue"
    # 2020-06-20 sábado
    assert bucket_dow("2020-06-20T12:00:00+00:00") == "Sat"
    # 2020-06-21 domingo
    assert bucket_dow("2020-06-21T12:00:00+00:00") == "Sun"


# ============================================================================
# TEST 5 — Bucket volume relativo
# ============================================================================
def test_bucket_volume_relative():
    assert bucket_volume(0.5) == "<0.8"
    assert bucket_volume(0.79) == "<0.8"
    assert bucket_volume(0.8) == "0.8-1.2"
    assert bucket_volume(1.0) == "0.8-1.2"
    assert bucket_volume(1.19) == "0.8-1.2"
    assert bucket_volume(1.2) == ">1.2"
    assert bucket_volume(3.0) == ">1.2"


# ============================================================================
# TEST 6 — Segmentação por dimensão única
# ============================================================================
def test_segment_by_single_dimension():
    trades = [
        _trade(adx=10), _trade(adx=12),  # <15
        _trade(adx=18), _trade(adx=22),  # 15-20 / 20-25
        _trade(adx=30),                  # >25
    ]
    seg = segment_by_bucket(trades, dim="adx")
    assert "<15"   in seg and len(seg["<15"])   == 2
    assert "15-20" in seg and len(seg["15-20"]) == 1
    assert "20-25" in seg and len(seg["20-25"]) == 1
    assert ">25"   in seg and len(seg[">25"])   == 1


# ============================================================================
# TEST 7 — Métricas por bucket
# ============================================================================
def test_metrics_per_bucket():
    trades_by_bucket = {
        ">25": [_trade(r=0.5), _trade(r=0.7), _trade(r=-0.3)],
        "<15": [_trade(r=-0.5), _trade(r=-0.4)],
    }
    metrics = metrics_per_bucket(trades_by_bucket)
    assert ">25" in metrics and "<15" in metrics
    for bucket in (">25", "<15"):
        for k in ("trades", "exp", "pf", "wr"):
            assert k in metrics[bucket]
    # bucket ">25" mean = (0.5+0.7-0.3)/3 = 0.3
    assert metrics[">25"]["exp"] == pytest.approx(0.3, abs=1e-6)
    assert metrics[">25"]["trades"] == 3


# ============================================================================
# TEST 8 — Find best sub-setup (max exp)
# ============================================================================
def test_find_best_subsetup_max_exp():
    per_bucket = {
        "<15":   {"exp": 0.10, "trades": 200, "pf": 1.1, "wr": 30},
        "15-20": {"exp": 0.50, "trades": 150, "pf": 1.8, "wr": 40},
        "20-25": {"exp": 0.25, "trades": 180, "pf": 1.3, "wr": 32},
        ">25":   {"exp": 0.35, "trades": 100, "pf": 1.5, "wr": 38},
    }
    best = find_best_subsetup(per_bucket, min_trades=50)
    assert best["bucket"] == "15-20"
    assert best["exp"] == 0.50


def test_find_best_subsetup_respects_min_trades():
    """Bucket com mais edge mas poucos trades não é escolhido."""
    per_bucket = {
        "low_n": {"exp": 0.90, "trades": 20, "pf": 5.0, "wr": 70},
        "high_n": {"exp": 0.40, "trades": 300, "pf": 1.5, "wr": 40},
    }
    best = find_best_subsetup(per_bucket, min_trades=50)
    assert best["bucket"] == "high_n"


# ============================================================================
# TEST 9 — Apply rule a holdout (sem otimizar)
# ============================================================================
def test_apply_subsetup_filter():
    """Filtra trades pelo bucket escolhido."""
    trades = [
        _trade(adx=12), _trade(adx=18), _trade(adx=22), _trade(adx=30),
    ]
    filtered = apply_subsetup_filter(trades, dim="adx", bucket="20-25")
    assert len(filtered) == 1
    assert filtered[0]["_adx_entry"] == 22


# ============================================================================
# TEST 10 — Decisão VIABLE
# ============================================================================
def test_decide_VIABLE_when_train_and_holdout_pass():
    """exp_train >= 0.40 E exp_holdout >= 0.30 E n_holdout >= 30 → VIABLE."""
    d = decide_subsetup(train_exp=0.45, holdout_exp=0.35, holdout_n=50)
    assert d == "VIABLE"


# ============================================================================
# TEST 11 — Decisão NEEDS_MORE_DATA
# ============================================================================
def test_decide_NEEDS_MORE_DATA_when_holdout_small():
    """Train passa, holdout exp ok mas n_holdout < 30."""
    d = decide_subsetup(train_exp=0.50, holdout_exp=0.40, holdout_n=20)
    assert d == "NEEDS_MORE_DATA"


# ============================================================================
# TEST 12 — Decisão NO_EDGE
# ============================================================================
def test_decide_NO_EDGE_when_train_fails():
    """Train abaixo do threshold → NO_EDGE."""
    d = decide_subsetup(train_exp=0.20, holdout_exp=0.30, holdout_n=50)
    assert d == "NO_EDGE"

    # OU holdout abaixo do threshold com n suficiente
    d2 = decide_subsetup(train_exp=0.50, holdout_exp=0.10, holdout_n=50)
    assert d2 == "NO_EDGE"


# ============================================================================
# TEST 13 — Schema JSON output
# ============================================================================
def test_json_schema_subsetup_output():
    trades = [_trade(adx=22, r=0.5) for _ in range(40)]
    holdout = [_trade(year=2024, adx=22, r=0.3) for _ in range(35)]

    report = build_subsetup_report(
        train_trades=trades,
        holdout_trades=holdout,
        dim="adx",
    )
    for k in ("dimension", "train_buckets", "holdout_buckets",
              "best_subsetup", "holdout_validation", "decision", "honest_note"):
        assert k in report
    assert report["decision"] in ("VIABLE", "NEEDS_MORE_DATA", "NO_EDGE")
    json.dumps(report)
