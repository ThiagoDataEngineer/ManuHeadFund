"""
TDD — metrics.py
Testa cálculo das métricas de performance institucionais.
"""
import pytest
from metrics import calc_metrics, BacktestMetrics, classify_regime, calc_metrics_by_regime, RegimeBreakdown


@pytest.fixture
def trades_mixed():
    """10 trades: 6 wins (+3R cada), 4 losses (-1R cada) → win rate 60%."""
    return (
        [3.0] * 6 +   # winners
        [-1.0] * 4    # losers
    )


@pytest.fixture
def trades_all_wins():
    return [2.0, 3.0, 1.5, 4.0, 2.5]


@pytest.fixture
def trades_all_losses():
    return [-1.0, -1.0, -1.0, -1.0, -1.0]


@pytest.fixture
def trades_breakeven():
    """50% win rate com R:R 1:1 → expectancy zero."""
    return [1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0]


# ── Win Rate ─────────────────────────────────────────────────────────────────

class TestWinRate:
    def test_win_rate_60pct(self, trades_mixed):
        m = calc_metrics(trades_mixed)
        assert abs(m.win_rate - 60.0) < 0.01

    def test_win_rate_100pct(self, trades_all_wins):
        m = calc_metrics(trades_all_wins)
        assert m.win_rate == 100.0

    def test_win_rate_0pct(self, trades_all_losses):
        m = calc_metrics(trades_all_losses)
        assert m.win_rate == 0.0

    def test_win_rate_50pct(self, trades_breakeven):
        m = calc_metrics(trades_breakeven)
        assert m.win_rate == 50.0


# ── Expectancy ───────────────────────────────────────────────────────────────

class TestExpectancy:
    def test_expectancy_positive(self, trades_mixed):
        # (0.6 × 3.0) + (0.4 × -1.0) = 1.8 - 0.4 = 1.4R
        m = calc_metrics(trades_mixed)
        assert abs(m.expectancy_r - 1.4) < 0.01

    def test_expectancy_zero_breakeven(self, trades_breakeven):
        m = calc_metrics(trades_breakeven)
        assert abs(m.expectancy_r) < 0.01

    def test_expectancy_negative_all_losses(self, trades_all_losses):
        m = calc_metrics(trades_all_losses)
        assert m.expectancy_r < 0


# ── Profit Factor ─────────────────────────────────────────────────────────────

class TestProfitFactor:
    def test_profit_factor_above_1_is_profitable(self, trades_mixed):
        # ganhos: 6×3=18, perdas: 4×1=4 → PF = 18/4 = 4.5
        m = calc_metrics(trades_mixed)
        assert abs(m.profit_factor - 4.5) < 0.01

    def test_profit_factor_below_1_is_losing(self, trades_all_losses):
        m = calc_metrics(trades_all_losses)
        assert m.profit_factor == 0.0

    def test_profit_factor_infinite_all_wins(self, trades_all_wins):
        m = calc_metrics(trades_all_wins)
        assert m.profit_factor == float("inf")


# ── Max Drawdown ──────────────────────────────────────────────────────────────

class TestMaxDrawdown:
    def test_drawdown_always_positive(self, trades_mixed):
        m = calc_metrics(trades_mixed)
        assert m.max_drawdown_r >= 0.0

    def test_no_drawdown_all_wins(self, trades_all_wins):
        m = calc_metrics(trades_all_wins)
        assert m.max_drawdown_r == 0.0

    def test_drawdown_sequence_of_losses(self):
        # 3 perdas seguidas: drawdown = 3R
        trades = [2.0, -1.0, -1.0, -1.0, 2.0]
        m = calc_metrics(trades)
        assert abs(m.max_drawdown_r - 3.0) < 0.01

    def test_drawdown_worst_case(self):
        # começa bem, depois cai: pico em 5R, cai para 2R → drawdown = 3R
        trades = [1.0, 1.0, 1.0, 1.0, 1.0, -1.0, -1.0, -1.0]
        m = calc_metrics(trades)
        assert abs(m.max_drawdown_r - 3.0) < 0.01


# ── Sharpe Ratio ─────────────────────────────────────────────────────────────

class TestSharpeRatio:
    def test_sharpe_positive_for_profitable_strategy(self, trades_mixed):
        m = calc_metrics(trades_mixed)
        assert m.sharpe_ratio > 0

    def test_sharpe_zero_for_breakeven(self, trades_breakeven):
        m = calc_metrics(trades_breakeven)
        assert abs(m.sharpe_ratio) < 0.01

    def test_sharpe_negative_for_losing_strategy(self, trades_all_losses):
        m = calc_metrics(trades_all_losses)
        assert m.sharpe_ratio < 0

    def test_sharpe_higher_for_consistent_wins(self):
        consistent = [1.0] * 10
        volatile = [5.0, -3.0, 5.0, -3.0, 5.0]
        m_consistent = calc_metrics(consistent)
        m_volatile = calc_metrics(volatile)
        assert m_consistent.sharpe_ratio > m_volatile.sharpe_ratio


# ── BacktestMetrics ───────────────────────────────────────────────────────────

class TestBacktestMetrics:
    def test_metrics_has_all_fields(self, trades_mixed):
        m = calc_metrics(trades_mixed)
        assert hasattr(m, "total_trades")
        assert hasattr(m, "winning_trades")
        assert hasattr(m, "win_rate")
        assert hasattr(m, "expectancy_r")
        assert hasattr(m, "profit_factor")
        assert hasattr(m, "max_drawdown_r")
        assert hasattr(m, "sharpe_ratio")
        assert hasattr(m, "sortino_ratio")

    def test_sortino_only_penalizes_downside(self, trades_mixed):
        m = calc_metrics(trades_mixed)
        # serie mista com ganhos — sortino >= sharpe (downside vol < total vol)
        assert m.sortino_ratio >= m.sharpe_ratio

    def test_sortino_inf_when_no_losses(self):
        m = calc_metrics([1.0, 2.0, 3.0])
        assert m.sortino_ratio == float("inf")

    def test_sortino_negative_when_all_losses(self):
        m = calc_metrics([-1.0, -2.0, -3.0])
        assert m.sortino_ratio < 0

    def test_sortino_positive_when_expectancy_positive(self):
        m = calc_metrics([5.0, -1.0, 5.0, -1.0])
        assert m.sortino_ratio > 0

    def test_total_trades_count(self, trades_mixed):
        m = calc_metrics(trades_mixed)
        assert m.total_trades == 10

    def test_winning_trades_count(self, trades_mixed):
        m = calc_metrics(trades_mixed)
        assert m.winning_trades == 6

    def test_empty_trades_raises(self):
        with pytest.raises(ValueError):
            calc_metrics([])


# ── classify_regime ───────────────────────────────────────────────────────────

class TestClassifyRegime:
    def test_bull_when_price_above_sma200_plus_threshold(self):
        # close = 105, sma200 = 100, threshold 2% → 105 > 102 → bull
        assert classify_regime(close=105.0, sma200=100.0) == "bull"

    def test_bear_when_price_below_sma200_minus_threshold(self):
        # close = 94, sma200 = 100, threshold 2% → 94 < 98 → bear
        assert classify_regime(close=94.0, sma200=100.0) == "bear"

    def test_sideways_when_price_within_threshold_band(self):
        # close = 101, sma200 = 100, threshold 2% → dentro da banda → sideways
        assert classify_regime(close=101.0, sma200=100.0) == "sideways"

    def test_sideways_at_exact_upper_boundary(self):
        # close = 102.0 = sma200 * 1.02 → não passa do limiar → sideways
        assert classify_regime(close=102.0, sma200=100.0) == "sideways"

    def test_sideways_at_exact_lower_boundary(self):
        # close = 98.0 = sma200 * 0.98 → não está abaixo → sideways
        assert classify_regime(close=98.0, sma200=100.0) == "sideways"

    def test_custom_threshold(self):
        # threshold = 5%: close = 106 > 105 → bull
        assert classify_regime(close=106.0, sma200=100.0, threshold=0.05) == "bull"

    def test_zero_sma200_raises(self):
        with pytest.raises(ValueError):
            classify_regime(close=100.0, sma200=0.0)


# ── calc_metrics_by_regime ────────────────────────────────────────────────────

class TestCalcMetricsByRegime:
    @pytest.fixture
    def bull_trades(self):
        return [3.0, 2.0, 2.5, 3.0, -1.0]  # 80% win rate

    @pytest.fixture
    def bear_trades(self):
        return [-1.0, -1.0, 1.0, -1.0, -1.0]  # 20% win rate

    def test_segments_bull_and_bear_correctly(self, bull_trades, bear_trades):
        r_series = bull_trades + bear_trades
        regimes  = ["bull"] * 5 + ["bear"] * 5
        result = calc_metrics_by_regime(r_series, regimes)
        assert result.bull.win_rate > result.bear.win_rate
        assert result.bull.expectancy_r > result.bear.expectancy_r

    def test_combined_equals_full_series_metrics(self, bull_trades, bear_trades):
        r_series = bull_trades + bear_trades
        regimes  = ["bull"] * 5 + ["bear"] * 5
        result   = calc_metrics_by_regime(r_series, regimes)
        expected = calc_metrics(r_series)
        assert abs(result.combined.win_rate - expected.win_rate) < 0.01
        assert abs(result.combined.expectancy_r - expected.expectancy_r) < 0.01

    def test_missing_regime_returns_none(self):
        r_series = [1.0, 2.0, -1.0]
        regimes  = ["bull", "bull", "bull"]  # sem bear nem sideways
        result = calc_metrics_by_regime(r_series, regimes)
        assert result.bear is None
        assert result.sideways is None
        assert result.bull is not None

    def test_regime_counts_correct(self):
        r_series = [1.0, -1.0, 0.5, -0.5, 1.0]
        regimes  = ["bull", "bear", "sideways", "bull", "bear"]
        result = calc_metrics_by_regime(r_series, regimes)
        assert result.regime_counts["bull"]     == 2
        assert result.regime_counts["bear"]     == 2
        assert result.regime_counts["sideways"] == 1

    def test_mismatched_lengths_raises(self):
        with pytest.raises(ValueError, match="mesmo comprimento"):
            calc_metrics_by_regime([1.0, 2.0], ["bull"])

    def test_invalid_regime_label_raises(self):
        with pytest.raises(ValueError, match="inválidos"):
            calc_metrics_by_regime([1.0], ["crash"])

    def test_empty_series_raises(self):
        with pytest.raises(ValueError):
            calc_metrics_by_regime([], [])

    def test_result_is_regime_breakdown(self, bull_trades, bear_trades):
        r_series = bull_trades + bear_trades
        regimes  = ["bull"] * 5 + ["bear"] * 5
        result = calc_metrics_by_regime(r_series, regimes)
        assert isinstance(result, RegimeBreakdown)
        assert isinstance(result.combined, BacktestMetrics)

    def test_ergodicity_score_present(self, bull_trades, bear_trades):
        r_series = bull_trades + bear_trades
        regimes  = ["bull"] * 5 + ["bear"] * 5
        result = calc_metrics_by_regime(r_series, regimes)
        assert hasattr(result, "ergodicity_score")
        assert 0.0 <= result.ergodicity_score <= 1.0

    def test_ergodicity_high_when_consistent_between_regimes(self):
        # win rate similar em ambos os regimes: ~60% bull, ~60% bear
        r_series = [2.0, -1.0, 2.0, -1.0, 2.0,   # bull: 3/5 = 60%
                    2.0, -1.0, 2.0, -1.0, 2.0]    # bear: 3/5 = 60%
        regimes  = ["bull"] * 5 + ["bear"] * 5
        result = calc_metrics_by_regime(r_series, regimes)
        assert result.ergodicity_score > 0.90  # quase perfeito

    def test_ergodicity_low_when_regime_dependent(self, bull_trades, bear_trades):
        # bull: 80% win rate vs bear: 20% win rate — sistema regime-dependente
        r_series = bull_trades + bear_trades
        regimes  = ["bull"] * 5 + ["bear"] * 5
        result = calc_metrics_by_regime(r_series, regimes)
        assert result.ergodicity_score < 0.60

    def test_ergodicity_zero_when_only_one_regime(self):
        r_series = [1.0, 2.0, -1.0]
        regimes  = ["bull", "bull", "bull"]
        result = calc_metrics_by_regime(r_series, regimes)
        assert result.ergodicity_score == 0.0  # dados insuficientes
