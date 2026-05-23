"""
metrics.py — Métricas de performance institucionais
Referências: Sharpe (1966), Calmar (Young 1991), Van Tharp (expectancy)
"""
import math
from dataclasses import dataclass, field
from typing import Dict, List, Optional


@dataclass
class BacktestMetrics:
    total_trades: int
    winning_trades: int
    win_rate: float        # %
    expectancy_r: float    # R médio por trade
    profit_factor: float   # ganhos brutos / perdas brutas
    max_drawdown_r: float  # maior sequência de perda em R
    sharpe_ratio: float    # retorno médio / desvio padrão dos retornos
    sortino_ratio: float   # retorno médio / downside deviation (Melão: melhor que Sharpe para crypto)


def calc_metrics(r_series: List[float]) -> BacktestMetrics:
    if not r_series:
        raise ValueError("r_series não pode ser vazia")

    total = len(r_series)
    winners = [r for r in r_series if r > 0]
    losers = [r for r in r_series if r <= 0]

    win_count = len(winners)
    win_rate = (win_count / total) * 100.0

    expectancy = sum(r_series) / total

    gross_profit = sum(winners)
    gross_loss = abs(sum(losers))
    profit_factor = gross_profit / gross_loss if gross_loss > 0 else float("inf")

    # max drawdown em R (sequência de perdas cumulativas)
    peak = 0.0
    cumulative = 0.0
    max_dd = 0.0
    for r in r_series:
        cumulative += r
        if cumulative > peak:
            peak = cumulative
        dd = peak - cumulative
        if dd > max_dd:
            max_dd = dd

    mean_r = expectancy

    # Sharpe (sem risk-free rate — adequado para crypto onde volatilidade domina)
    if total < 2:
        sharpe = 0.0
    else:
        variance = sum((r - mean_r) ** 2 for r in r_series) / (total - 1)
        std_r = math.sqrt(variance)
        if std_r > 0:
            sharpe = mean_r / std_r
        elif mean_r > 0:
            sharpe = float("inf")
        elif mean_r < 0:
            sharpe = float("-inf")
        else:
            sharpe = 0.0

    # Sortino — penaliza só downside vol (Melão: mais honesto para crypto com fat positive tails)
    downside = [r for r in r_series if r < 0]
    if len(downside) >= 2:
        downside_variance = sum(r ** 2 for r in downside) / len(downside)
        downside_std = math.sqrt(downside_variance)
        if downside_std > 0:
            sortino = mean_r / downside_std
        elif mean_r > 0:
            sortino = float("inf")
        else:
            sortino = 0.0
    elif mean_r > 0:
        sortino = float("inf")
    else:
        sortino = 0.0

    return BacktestMetrics(
        total_trades=total,
        winning_trades=win_count,
        win_rate=win_rate,
        expectancy_r=expectancy,
        profit_factor=profit_factor,
        max_drawdown_r=max_dd,
        sharpe_ratio=sharpe,
        sortino_ratio=sortino,
    )


# ── Regime benchmarking ───────────────────────────────────────────────────────

VALID_REGIMES = frozenset({"bull", "bear", "sideways"})


def classify_regime(close: float, sma200: float, threshold: float = 0.02) -> str:
    """Classifica regime de mercado via SMA200.

    bull     → close > sma200 * (1 + threshold)
    bear     → close < sma200 * (1 - threshold)
    sideways → dentro da banda
    """
    if sma200 <= 0:
        raise ValueError("sma200 deve ser positivo")
    if close > sma200 * (1.0 + threshold):
        return "bull"
    if close < sma200 * (1.0 - threshold):
        return "bear"
    return "sideways"


@dataclass
class RegimeBreakdown:
    bull:              Optional[BacktestMetrics]
    bear:              Optional[BacktestMetrics]
    sideways:          Optional[BacktestMetrics]
    combined:          BacktestMetrics
    regime_counts:     Dict[str, int]
    ergodicity_score:  float  # 0-1: consistência entre regimes (Melão: critério de aceite > 0.70)


def calc_metrics_by_regime(
    r_series: List[float],
    regimes: List[str],
) -> RegimeBreakdown:
    """Calcula métricas segmentadas por regime de mercado (bull/bear/sideways).

    r_series: resultados em R por trade
    regimes:  regime de cada trade — deve ter o mesmo comprimento que r_series
    """
    if not r_series:
        raise ValueError("r_series não pode ser vazia")
    if len(r_series) != len(regimes):
        raise ValueError("r_series e regimes devem ter o mesmo comprimento")
    invalid = set(regimes) - VALID_REGIMES
    if invalid:
        raise ValueError(f"Regimes inválidos: {invalid}")

    buckets: Dict[str, List[float]] = {"bull": [], "bear": [], "sideways": []}
    for r, regime in zip(r_series, regimes):
        buckets[regime].append(r)

    def _safe(trades: List[float]) -> Optional[BacktestMetrics]:
        return calc_metrics(trades) if trades else None

    bull_m     = _safe(buckets["bull"])
    bear_m     = _safe(buckets["bear"])
    sideways_m = _safe(buckets["sideways"])

    # Ergodicity score (Melão): 1 - CV(win_rates entre regimes)
    # Alto (>0.70) = sistema robusto em todos os regimes; baixo = regime-dependente
    available_wr = [m.win_rate for m in [bull_m, bear_m, sideways_m] if m is not None]
    if len(available_wr) >= 2:
        mean_wr = sum(available_wr) / len(available_wr)
        std_wr  = math.sqrt(sum((x - mean_wr) ** 2 for x in available_wr) / len(available_wr))
        ergodicity = max(0.0, 1.0 - (std_wr / mean_wr)) if mean_wr > 0 else 0.0
    else:
        ergodicity = 0.0  # dados insuficientes para avaliar

    return RegimeBreakdown(
        bull=bull_m,
        bear=bear_m,
        sideways=sideways_m,
        combined=calc_metrics(r_series),
        regime_counts={k: len(v) for k, v in buckets.items()},
        ergodicity_score=round(ergodicity, 3),
    )
