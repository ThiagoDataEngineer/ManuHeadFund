"""
equity_curve_from_trades.py — Converte trades discretos (R-multiples) em
curva equity diaria MULTIPLICATIVA, base para metricas % returns padrão.

Bug raiz da metodologia anterior (2026-05-16 plan):
- Simons Gate atual usa R-multiples: +5R win / -1R loss
- DSR calculado em R-multiples != DSR daily returns (jargão diferente)
- Compare cross-asset (BTC vs XRP) tem vies (R depende de risk_pct assumido)

Solução: trades -> daily PnL % -> equity curve -> daily returns -> Sharpe/DSR
padrão Bailey-Lopez de Prado em returns %.

Use:
    eq = build_equity_curve(trades, risk_pct=0.01)
    rets = daily_returns_from_equity(eq)
    # Sharpe = sqrt(365) * mean(rets) / std(rets)
"""
from datetime import datetime
from typing import Dict, List


def aggregate_trades_by_date(trades: List[Dict]) -> Dict[str, List[float]]:
    """Agrupa trades por data (UTC) extraindo result_r."""
    out: Dict[str, List[float]] = {}
    for t in trades:
        ts = t.get("entry_ts")
        r = t.get("result_r")
        if ts is None or r is None:
            continue
        try:
            # Parse ISO8601 com fallback gracioso
            dt = datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
            date_key = dt.strftime("%Y-%m-%d")
        except (ValueError, TypeError):
            continue
        out.setdefault(date_key, []).append(float(r))
    return out


def build_equity_curve(trades: List[Dict], risk_pct: float = 0.01) -> Dict[str, float]:
    """
    Constroi curva equity diaria a partir de trades.

    Args:
        trades: lista de dicts com entry_ts ISO8601 e result_r
        risk_pct: % do capital arriscado por trade (default 1%)

    Returns:
        dict {date_iso: equity_multiplier} — equity acumulada ao FIM de cada dia
        com trades. Primeiro dia parte de 1.0 base.

    Convenção: cada trade ganha result_r * risk_pct em PnL%.
        Trade +5R com risk 1% = ganho 5%.
        Trade -1R com risk 1% = perda 1%.
    Multiplos trades no mesmo dia: produto sequencial dos returns.
    """
    by_date = aggregate_trades_by_date(trades)
    if not by_date:
        return {}

    equity = 1.0
    out: Dict[str, float] = {}
    for date_key in sorted(by_date.keys()):
        rs = by_date[date_key]
        day_mult = 1.0
        for r in rs:
            day_mult *= (1.0 + r * risk_pct)
        equity *= day_mult
        out[date_key] = equity
    return out


def daily_returns_from_equity(equity_curve: Dict[str, float]) -> List[float]:
    """
    Calcula daily returns multiplicativos a partir de equity curve.

    return[i] = equity[i] / equity[i-1] - 1

    Retorna lista de N-1 returns (precisa ≥ 2 pontos).
    """
    if not equity_curve or len(equity_curve) < 2:
        return []
    dates = sorted(equity_curve.keys())
    returns = []
    for i in range(1, len(dates)):
        prev = equity_curve[dates[i-1]]
        curr = equity_curve[dates[i]]
        if prev <= 0:
            continue
        returns.append(curr / prev - 1)
    return returns
