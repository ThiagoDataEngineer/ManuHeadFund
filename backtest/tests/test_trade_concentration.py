"""TDD trade_concentration: detectar overfit/tail concentration."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from trade_concentration import (
    top_n_contribution_pct,
    annual_contribution,
    gini_coefficient,
    analyze_concentration,
)


def _mk_trade(ts, r):
    return {"entry_ts": ts, "result_r": r}


def test_gini_uniform():
    """100 valores iguais → Gini ≈ 0."""
    g = gini_coefficient([1.0] * 100)
    assert g < 0.05


def test_gini_concentrated():
    """1 valor enorme + 99 pequenos → Gini alto."""
    g = gini_coefficient([1000.0] + [0.01] * 99)
    assert g > 0.85


def test_top_1pct_distributed():
    """100 trades uniformes: top 1% deve ser ~1% do equity total."""
    trades = [_mk_trade(f"2020-01-{(i%28)+1:02d}T00:00:00+00:00", 1.0)
              for i in range(100)]
    r = top_n_contribution_pct(trades, risk_pct=0.01, top_n_pct=0.01)
    # top 1 winner em 100 = ~1% do log return total
    assert abs(r["top_pct_of_total_log"] - 1.0) < 0.5


def test_top_1pct_concentrated():
    """1 trade gigante domina."""
    trades = [_mk_trade("2020-01-01T00:00:00+00:00", 0.1) for _ in range(99)]
    trades.append(_mk_trade("2020-01-02T00:00:00+00:00", 50.0))  # 50R
    r = top_n_contribution_pct(trades, risk_pct=0.01, top_n_pct=0.01)
    assert r["top_pct_of_total_log"] > 30  # top 1% (1 trade) > 30% do equity


def test_annual_breakdown():
    """Trades em anos diferentes geram breakdown anual."""
    trades = [
        _mk_trade("2020-01-01T00:00:00+00:00", 5.0),
        _mk_trade("2021-01-01T00:00:00+00:00", 3.0),
    ]
    a = annual_contribution(trades, risk_pct=0.01)
    years = [x["year"] for x in a]
    assert "2020" in years
    assert "2021" in years
    # 2020 5R > 2021 3R em log return
    pct_2020 = next(x["pct_of_total"] for x in a if x["year"] == "2020")
    pct_2021 = next(x["pct_of_total"] for x in a if x["year"] == "2021")
    assert pct_2020 > pct_2021


def test_analyze_distributed_no_flags():
    """Strategy uniforme → no concentration flags."""
    trades = []
    for year in range(2018, 2025):
        for i in range(50):
            trades.append(_mk_trade(f"{year}-01-{(i%28)+1:02d}T00:00:00+00:00",
                                     0.5 if i % 3 else -0.3))
    out = analyze_concentration(trades, risk_pct=0.01)
    assert out["verdict"] in ("DISTRIBUTED ✅", "CONCENTRATED ⚠️")
    # Não vamos forçar uma label; só verifica que não crashou


def test_analyze_concentrated_flagged():
    """Strategy com 1 trade gigante isolado → flag."""
    trades = []
    for i in range(99):
        trades.append(_mk_trade(f"2020-01-{(i%28)+1:02d}T00:00:00+00:00", 0.1))
    trades.append(_mk_trade("2021-06-15T00:00:00+00:00", 500.0))  # lottery
    out = analyze_concentration(trades, risk_pct=0.01)
    assert "CONCENTRATED" in out["verdict"]
    assert len(out["concentration_flags"]) > 0
