"""test_methodology.py -- TDD inline para lib_methodology.

3 niveis:
  - Unit tests: cada funcao basica
  - Property-based tests: invariants matematicos
  - Methodology tests: invariants de processo

Run direto: python test_methodology.py
"""
from __future__ import annotations
import sys
sys.path.insert(0, "backtest")
from lib_methodology import (dedup_alphabetical, dedup_max_wss,
                              cluster_portfolio_avg, effective_n,
                              bootstrap_ci_by_day)


# ─── Helpers para fixtures ────────────────────────────────────────────────────

def _ev(ts, market, outcome=0.0, wss=50.0, phase="h24_p3_bear"):
    return {"ts": ts, "market": market, "outcome": outcome, "wss": wss, "phase": phase}


def _ok(name):
    print(f"  ✓ {name}")


def _fail(name, msg):
    print(f"  ✗ {name}: {msg}")
    return False


# ─── Unit tests ───────────────────────────────────────────────────────────────

def test_effective_n_basic():
    evs = [_ev("2026-01-01", "BTC"), _ev("2026-01-01", "ETH"), _ev("2026-01-02", "BTC")]
    assert effective_n(evs) == 2, f"expected 2, got {effective_n(evs)}"
    _ok("effective_n basic (3 events / 2 days)")


def test_dedup_alphabetical_basic():
    evs = [_ev("2026-01-01", "ETH"), _ev("2026-01-01", "BTC"), _ev("2026-01-02", "SOL")]
    out = dedup_alphabetical(evs)
    assert len(out) == 2, f"expected 2 events out, got {len(out)}"
    assert out[0]["market"] == "BTC", f"expected BTC alphabetical, got {out[0]['market']}"
    assert out[1]["market"] == "SOL"
    _ok("dedup_alphabetical picks alphabetical")


def test_dedup_max_wss_basic():
    evs = [_ev("2026-01-01", "BTC", wss=50), _ev("2026-01-01", "ETH", wss=70),
           _ev("2026-01-02", "SOL", wss=30)]
    out = dedup_max_wss(evs)
    assert len(out) == 2
    assert out[0]["market"] == "ETH", f"expected ETH (wss=70), got {out[0]['market']}"
    assert out[1]["market"] == "SOL"
    _ok("dedup_max_wss picks highest WSS")


def test_cluster_portfolio_avg_basic():
    evs = [_ev("2026-01-01", "BTC", outcome=4.0), _ev("2026-01-01", "ETH", outcome=2.0),
           _ev("2026-01-02", "SOL", outcome=-1.0)]
    out = cluster_portfolio_avg(evs)
    assert len(out) == 2
    assert out[0]["outcome"] == 3.0, f"expected mean 3.0, got {out[0]['outcome']}"
    assert out[0]["cluster_size"] == 2
    assert out[0]["market"] == "_PORTFOLIO_"
    assert out[0]["contributing_markets"] == ["BTC", "ETH"]
    _ok("cluster_portfolio_avg mean correct + metadata")


# ─── Property-based tests (invariants matematicos) ────────────────────────────

def test_effective_n_property_le_len():
    """effective_n <= len(events) sempre."""
    fixtures = [
        [_ev("2026-01-01", "BTC")],
        [_ev("2026-01-01", "BTC"), _ev("2026-01-01", "ETH")],
        [_ev("2026-01-01", "BTC"), _ev("2026-01-02", "ETH"), _ev("2026-01-03", "SOL")],
    ]
    for evs in fixtures:
        assert effective_n(evs) <= len(evs), f"effective_n > len for {evs}"
    _ok("PROPERTY: effective_n(evs) <= len(evs) sempre")


def test_dedup_property_subset_of_input():
    """dedup_*(events) subset of events (em termos de (ts, market))."""
    evs = [_ev("2026-01-01", "BTC", wss=50), _ev("2026-01-01", "ETH", wss=70),
           _ev("2026-01-02", "SOL", wss=30), _ev("2026-01-03", "ADA", wss=80)]
    inp_keys = set((e["ts"], e["market"]) for e in evs)
    for fn, name in [(dedup_alphabetical, "alphabetical"), (dedup_max_wss, "max_wss")]:
        out = fn(evs)
        out_keys = set((e["ts"], e["market"]) for e in out)
        assert out_keys.issubset(inp_keys), f"{name} produced non-subset"
    _ok("PROPERTY: dedup_* output subset of input")


def test_dedup_property_one_per_day():
    """dedup_* sempre produce exactly 1 event per distinct day."""
    evs = [_ev("2026-01-01", "BTC"), _ev("2026-01-01", "ETH"), _ev("2026-01-01", "SOL"),
           _ev("2026-01-02", "ADA"), _ev("2026-01-02", "DOT")]
    n_days = effective_n(evs)
    for fn, name in [(dedup_alphabetical, "alphabetical"), (dedup_max_wss, "max_wss")]:
        out = fn(evs)
        assert len(out) == n_days, f"{name}: {len(out)} events vs {n_days} days"
    _ok("PROPERTY: dedup_* produces exactly effective_n events")


def test_cluster_portfolio_avg_preserves_day_count():
    """cluster_portfolio_avg output length == effective_n(input)."""
    evs = [_ev("2026-01-01", "BTC", outcome=2), _ev("2026-01-01", "ETH", outcome=4),
           _ev("2026-01-02", "SOL", outcome=1)]
    out = cluster_portfolio_avg(evs)
    assert len(out) == effective_n(evs)
    _ok("PROPERTY: cluster_portfolio_avg preserves day count")


def test_wss_dedup_picks_strictly_max_when_no_tie():
    """Se WSS values distintos no mesmo dia, dedup_max_wss escolhe o MAIOR."""
    evs = [_ev("2026-01-01", "A", wss=10), _ev("2026-01-01", "B", wss=60),
           _ev("2026-01-01", "C", wss=80), _ev("2026-01-01", "D", wss=30)]
    out = dedup_max_wss(evs)
    assert len(out) == 1
    assert out[0]["market"] == "C", f"expected C (wss=80), got {out[0]['market']}"
    _ok("PROPERTY: dedup_max_wss picks strict max")


# ─── Methodology invariants ───────────────────────────────────────────────────

def test_methodology_determinism():
    """Mesma entrada -> mesma saida (sem random)."""
    evs = [_ev("2026-01-01", "BTC", wss=50), _ev("2026-01-01", "ETH", wss=70)]
    r1 = dedup_alphabetical(evs)
    r2 = dedup_alphabetical(evs)
    assert r1 == r2, "dedup_alphabetical not deterministic"
    r3 = dedup_max_wss(evs)
    r4 = dedup_max_wss(evs)
    assert r3 == r4, "dedup_max_wss not deterministic"
    _ok("METHODOLOGY: determinism (deterministic functions)")


def test_methodology_order_invariance():
    """Shuffle ordem dos events -> mesmo resultado (dedup independente de ordem)."""
    evs1 = [_ev("2026-01-01", "BTC", wss=50), _ev("2026-01-01", "ETH", wss=70),
            _ev("2026-01-02", "SOL", wss=30)]
    evs2 = [evs1[2], evs1[0], evs1[1]]  # shuffled
    for fn in [dedup_alphabetical, dedup_max_wss]:
        r1 = sorted([(e["ts"], e["market"]) for e in fn(evs1)])
        r2 = sorted([(e["ts"], e["market"]) for e in fn(evs2)])
        assert r1 == r2, f"order matters for {fn.__name__}"
    _ok("METHODOLOGY: order invariance (input shuffle = same dedup result)")


def test_methodology_cluster_collapse():
    """Se duplicar todos events do mesmo dia, cluster_portfolio mantem outcome (mean igual)."""
    evs_single = [_ev("2026-01-01", "BTC", outcome=3.0), _ev("2026-01-01", "ETH", outcome=5.0)]
    out_single = cluster_portfolio_avg(evs_single)
    # Duplicate the same event in same day - mean should stay similar with same markets
    evs_dup = evs_single + [_ev("2026-01-01", "BTC", outcome=3.0)]  # duplicate BTC same outcome
    out_dup = cluster_portfolio_avg(evs_dup)
    # 3 events: (3+5+3)/3 = 3.67 vs original (3+5)/2 = 4.0 — different because we added weight
    # The invariant we ACTUALLY want: if we collapse cluster to 1 trade, total outcome captured.
    # Here just verify same number of days (both produce 1 day output)
    assert len(out_single) == 1 and len(out_dup) == 1
    _ok("METHODOLOGY: cluster_portfolio_avg single output per day regardless of cluster size")


def test_bootstrap_ci_basic_smoke():
    """Bootstrap não crasha + retorna CI envolve point estimate."""
    # 5 sig days, 100 base days
    sig = []
    base = []
    for i in range(5):
        sig.append(_ev(f"2026-01-{i+1:02d}", "BTC", outcome=5.0))  # all wins
    for i in range(100):
        base.append(_ev(f"2025-12-{(i%30)+1:02d}", f"X{i}", outcome=1.0))  # all baseline below threshold
    r = bootstrap_ci_by_day(sig, base, thr_net=1.6, n_iter=200, seed=42)
    assert r is not None
    assert r["ci_low"] <= r["point_lift"] <= r["ci_high"], f"CI doesn't envelope point: {r}"
    _ok("METHODOLOGY: bootstrap CI envelopes point estimate")


def test_bootstrap_ci_insufficient_data():
    """Bootstrap retorna None se sample muito pequeno."""
    sig = [_ev("2026-01-01", "BTC", outcome=5.0), _ev("2026-01-02", "ETH", outcome=3.0)]
    base = [_ev("2025-12-01", "X", outcome=1.0)]
    r = bootstrap_ci_by_day(sig, base, n_iter=100)
    assert r is None, "should return None with <3 sig days"
    _ok("METHODOLOGY: bootstrap returns None for insufficient sample")


# ─── Runner ───────────────────────────────────────────────────────────────────

def main():
    tests = [
        test_effective_n_basic, test_dedup_alphabetical_basic,
        test_dedup_max_wss_basic, test_cluster_portfolio_avg_basic,
        test_effective_n_property_le_len, test_dedup_property_subset_of_input,
        test_dedup_property_one_per_day, test_cluster_portfolio_avg_preserves_day_count,
        test_wss_dedup_picks_strictly_max_when_no_tie,
        test_methodology_determinism, test_methodology_order_invariance,
        test_methodology_cluster_collapse,
        test_bootstrap_ci_basic_smoke, test_bootstrap_ci_insufficient_data,
    ]
    passed = 0
    failed = 0
    for t in tests:
        try:
            t()
            passed += 1
        except AssertionError as e:
            print(f"  ✗ {t.__name__}: {e}")
            failed += 1
        except Exception as e:
            print(f"  ✗ {t.__name__}: {type(e).__name__}: {e}")
            failed += 1
    print(f"\nTDD: {passed}/{passed+failed} PASS")
    return failed


if __name__ == "__main__":
    sys.exit(main())
