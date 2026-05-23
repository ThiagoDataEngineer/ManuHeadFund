"""dow_refinement.py — Refinamento do efeito dia-da-semana.

Tests:
  - Robustez subperiodos (2011-2014, 2015-2018, 2019-2022, 2023-2026)
  - Estrategia comparativa: Mon-Wed only vs Buy&Hold vs Thu-Sun only
  - Day-of-week × regime macro (bull vs bear)
  - Sharpe-like return/risk por estrategia
"""
import math
import os
import sys
from datetime import datetime
from typing import Dict, List

try: sys.stdout.reconfigure(encoding="utf-8")
except Exception: pass

from dotenv import load_dotenv
load_dotenv()

from db import Database
from backtest_2w_14y import MARKET, PERIOD_1D
from calendar_effects_btc import daily_returns, stats, t_test_two_groups


WEEKDAY_LABELS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


def cumulative_strategy(returns: Dict[str, float], allowed_dows: set) -> Dict:
    """Retorna stats acumulado segurando posicao so nos dias permitidos."""
    daily_pl = []
    for date_iso in sorted(returns.keys()):
        dow = datetime.fromisoformat(date_iso).weekday()
        r = returns[date_iso] if dow in allowed_dows else 0.0
        daily_pl.append(r)
    if not daily_pl:
        return {"total_log": 0, "final_mult": 1, "sharpe": 0, "n_active": 0}
    total_log = sum(daily_pl)
    n_active = sum(1 for d in returns if datetime.fromisoformat(d).weekday() in allowed_dows)
    # sharpe-like: mean / std × sqrt(365)
    active_returns = [r for d, r in returns.items()
                      if datetime.fromisoformat(d).weekday() in allowed_dows]
    if active_returns and len(active_returns) > 1:
        m = sum(active_returns) / len(active_returns)
        s = math.sqrt(sum((x - m) ** 2 for x in active_returns) / (len(active_returns) - 1))
        sharpe = (m / s) * math.sqrt(365) if s > 0 else 0
    else:
        sharpe = 0
    return {
        "total_log": total_log,
        "final_mult": math.exp(total_log),
        "sharpe": sharpe,
        "n_active": n_active,
        "n_total": len(daily_pl),
        "mean_active": sum(active_returns) / len(active_returns) if active_returns else 0,
    }


def filter_by_period(returns: Dict[str, float], start: str, end: str) -> Dict[str, float]:
    return {d: r for d, r in returns.items() if start <= d < end}


def analyze_subperiods(returns: Dict[str, float]) -> None:
    """Verifica se o efeito segunda > quinta sobrevive em todos os subperiodos."""
    periods = [
        ("2011-2014", "2011-01-01", "2015-01-01"),
        ("2015-2018", "2015-01-01", "2019-01-01"),
        ("2019-2022", "2019-01-01", "2023-01-01"),
        ("2023-2026", "2023-01-01", "2027-01-01"),
    ]
    sep = "-" * 72
    print(f"  {'Period':<12} {'Mon':>9} {'Tue':>9} {'Wed':>9} {'Thu':>9} {'Fri':>9} {'p(M-T)'}")
    print(sep)
    for label, s, e in periods:
        sub = filter_by_period(returns, s, e)
        if len(sub) < 100:
            continue
        by_dow: Dict[int, List[float]] = {i: [] for i in range(7)}
        for d, r in sub.items():
            by_dow[datetime.fromisoformat(d).weekday()].append(r)
        means = {i: (sum(by_dow[i]) / len(by_dow[i]) if by_dow[i] else 0)
                 for i in range(7)}
        t, p = t_test_two_groups(by_dow[0], by_dow[3])  # Mon vs Thu
        marker = "SIG" if p < 0.05 else ""
        print(f"  {label:<12} "
              f"{means[0]*100:>+7.3f}%  {means[1]*100:>+7.3f}%  "
              f"{means[2]*100:>+7.3f}%  {means[3]*100:>+7.3f}%  "
              f"{means[4]*100:>+7.3f}%   p={p:.3f} {marker}")


def analyze_strategies(returns: Dict[str, float]) -> None:
    """Compara estrategias de timing."""
    strategies = {
        "Buy & Hold":       {0, 1, 2, 3, 4, 5, 6},
        "Mon-Wed only":     {0, 1, 2},
        "Mon only":         {0},
        "Mon+Wed":          {0, 2},
        "Skip Thursday":    {0, 1, 2, 4, 5, 6},
        "Skip weekend":     {0, 1, 2, 3, 4},
        "Mon-Fri":          {0, 1, 2, 3, 4},
        "Weekend only":     {5, 6},
        "Thu-Sun only":     {3, 4, 5, 6},
    }
    sep = "-" * 76
    print(f"  {'Strategy':<18} {'Time%':>7} {'CumRet':>10} {'Mean/day':>10} {'Sharpe':>8}")
    print(sep)
    n_total = len(returns)
    for label, dows in strategies.items():
        s = cumulative_strategy(returns, dows)
        time_pct = s["n_active"] / max(n_total, 1) * 100
        cum_ret_pct = (s["final_mult"] - 1) * 100
        print(f"  {label:<18} {time_pct:>6.1f}% {cum_ret_pct:>+9.1f}%  "
              f"{s['mean_active']*100:>+8.4f}%  {s['sharpe']:>7.2f}")


def analyze_dow_by_macro(returns: Dict[str, float], daily_btc: Dict[str, float]) -> None:
    """Dia da semana × regime macro (bull/bear via SMA200 do preco)."""
    # SMA200 do preco
    sorted_dates = sorted(daily_btc.keys())
    btc_list = [(d, daily_btc[d]) for d in sorted_dates]
    regimes: Dict[str, str] = {}
    for i in range(len(btc_list)):
        if i < 200:
            regimes[btc_list[i][0]] = "warmup"
            continue
        sma = sum(b[1] for b in btc_list[i - 200:i]) / 200
        close = btc_list[i][1]
        if close > sma * 1.02:
            regimes[btc_list[i][0]] = "bull"
        elif close < sma * 0.98:
            regimes[btc_list[i][0]] = "bear"
        else:
            regimes[btc_list[i][0]] = "sideways"

    sep = "-" * 72
    print(f"  {'Regime':<10} {'Mon':>9} {'Tue':>9} {'Wed':>9} {'Thu':>9} {'Fri':>9}")
    print(sep)
    for regime in ("bull", "bear", "sideways"):
        by_dow: Dict[int, List[float]] = {i: [] for i in range(7)}
        for d, r in returns.items():
            if regimes.get(d) == regime:
                by_dow[datetime.fromisoformat(d).weekday()].append(r)
        means = {i: (sum(by_dow[i]) / len(by_dow[i]) if by_dow[i] else 0)
                 for i in range(7)}
        n = sum(len(by_dow[i]) for i in range(7))
        print(f"  {regime:<10} "
              f"{means[0]*100:>+7.3f}%  {means[1]*100:>+7.3f}%  "
              f"{means[2]*100:>+7.3f}%  {means[3]*100:>+7.3f}%  "
              f"{means[4]*100:>+7.3f}%  n={n}")


def main():
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    daily = db.get_candles(MARKET, PERIOD_1D, "2011-01-01", "2026-12-31")
    daily_btc = {c["ts"][:10]: float(c["close"]) for c in daily}
    returns = daily_returns(daily_btc)

    sep = "=" * 76
    print(f"\n{sep}\n  1. ROBUSTEZ EM SUBPERIODOS (Mon vs Thu)\n{sep}")
    analyze_subperiods(returns)

    print(f"\n{sep}\n  2. ESTRATEGIAS COMPARADAS (cumulative return)\n{sep}")
    analyze_strategies(returns)

    print(f"\n{sep}\n  3. DIA DA SEMANA × REGIME MACRO (SMA200)\n{sep}")
    analyze_dow_by_macro(returns, daily_btc)

    print(f"\n{sep}\n  CONCLUSAO ESPERADA\n{sep}")
    print("  - Efeito sobrevive em todos os subperiodos? (robustness)")
    print("  - 'Mon-Wed only' supera Buy&Hold em risk-adjusted return?")
    print("  - Efeito eh consistente cross-regime ou so em bull?")


if __name__ == "__main__":
    main()
