"""calendar_effects_btc.py — 4 efeitos calendario/ciclicos sobre BTC 14y.

Testes:
  1. Dia da semana (Mon-Sun returns)
  2. Ultima semana do mes (rebalanceamento)
  3. Janela pre/pos FOMC (extraido de DFEDTARU changes via FRED)
  4. Fase lunar (new moon / full moon vs outros)
"""
import math
import os
import sys
import urllib.request
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Tuple

try: sys.stdout.reconfigure(encoding="utf-8")
except Exception: pass

from dotenv import load_dotenv
load_dotenv()

from db import Database
from backtest_2w_14y import MARKET, PERIOD_1D


# ── Utilities ────────────────────────────────────────────────────────────────

def t_test_two_groups(a: List[float], b: List[float]) -> Tuple[float, float]:
    """Welch's t-test simples. Retorna (t, approx_pvalue)."""
    if len(a) < 2 or len(b) < 2:
        return 0.0, 1.0
    ma = sum(a) / len(a); mb = sum(b) / len(b)
    va = sum((x - ma) ** 2 for x in a) / (len(a) - 1)
    vb = sum((x - mb) ** 2 for x in b) / (len(b) - 1)
    se = math.sqrt(va / len(a) + vb / len(b))
    if se == 0:
        return 0.0, 1.0
    t = (ma - mb) / se
    # approximacao normal pro p-value (n grande)
    p = 2 * (1 - normal_cdf(abs(t)))
    return t, p


def normal_cdf(x: float) -> float:
    """Aproximacao Abramowitz & Stegun da CDF normal padrao."""
    return 0.5 * (1 + math.erf(x / math.sqrt(2)))


def daily_returns(daily_btc: Dict[str, float]) -> Dict[str, float]:
    """Retorna dict[date_iso] = log_return."""
    sorted_dates = sorted(daily_btc.keys())
    out = {}
    for i in range(1, len(sorted_dates)):
        prev = daily_btc[sorted_dates[i - 1]]
        curr = daily_btc[sorted_dates[i]]
        if prev > 0:
            out[sorted_dates[i]] = math.log(curr / prev)
    return out


def stats(returns: List[float]) -> Dict:
    if not returns:
        return {"n": 0, "mean": 0, "median": 0, "std": 0}
    n = len(returns)
    m = sum(returns) / n
    s = math.sqrt(sum((r - m) ** 2 for r in returns) / max(n - 1, 1))
    sorted_r = sorted(returns)
    med = sorted_r[n // 2]
    return {"n": n, "mean": m, "median": med, "std": s}


# ── 1. Day of week ───────────────────────────────────────────────────────────

def analyze_dow(returns: Dict[str, float]) -> None:
    by_dow: Dict[int, List[float]] = {i: [] for i in range(7)}
    for date_iso, r in returns.items():
        dow = datetime.fromisoformat(date_iso).weekday()  # Mon=0, Sun=6
        by_dow[dow].append(r)

    days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    print(f"\n  {'Day':<5} {'N':>6} {'mean%':>9} {'median%':>9} {'std%':>8}")
    print("  " + "-" * 42)
    means = {}
    for i in range(7):
        s = stats(by_dow[i])
        means[i] = s["mean"]
        print(f"  {days[i]:<5} {s['n']:>6} {s['mean']*100:>+8.3f}% "
              f"{s['median']*100:>+8.3f}% {s['std']*100:>7.3f}%")

    # Test: melhor dia vs pior dia
    best = max(means, key=lambda k: means[k])
    worst = min(means, key=lambda k: means[k])
    t, p = t_test_two_groups(by_dow[best], by_dow[worst])
    diff = (means[best] - means[worst]) * 100
    print(f"\n  Best: {days[best]} ({means[best]*100:+.3f}%)  vs  "
          f"Worst: {days[worst]} ({means[worst]*100:+.3f}%)")
    print(f"  Diff: {diff:+.3f}pp/day   t={t:.2f}  p={p:.4f}  "
          f"{'(SIG)' if p < 0.05 else '(ns)'}")


# ── 2. Last week of month ────────────────────────────────────────────────────

def analyze_last_week(returns: Dict[str, float]) -> None:
    last_week, other = [], []
    for date_iso, r in returns.items():
        d = datetime.fromisoformat(date_iso)
        if d.day >= 24:
            last_week.append(r)
        else:
            other.append(r)

    s_lw = stats(last_week); s_ot = stats(other)
    t, p = t_test_two_groups(last_week, other)
    print(f"\n  {'Group':<14} {'N':>6} {'mean%':>10} {'median%':>10}")
    print("  " + "-" * 44)
    print(f"  {'Day >= 24':<14} {s_lw['n']:>6} {s_lw['mean']*100:>+9.3f}% {s_lw['median']*100:>+9.3f}%")
    print(f"  {'Day < 24':<14} {s_ot['n']:>6} {s_ot['mean']*100:>+9.3f}% {s_ot['median']*100:>+9.3f}%")
    diff = (s_lw['mean'] - s_ot['mean']) * 100
    print(f"  Diff: {diff:+.3f}pp/day  t={t:.2f}  p={p:.4f}  "
          f"{'(SIG)' if p < 0.05 else '(ns)'}")


# ── 3. FOMC window ───────────────────────────────────────────────────────────

def fetch_fomc_dates() -> List[str]:
    """Datas de mudanca da Fed Funds Upper (DFEDTARU). Cache FRED CSV."""
    url = "https://fred.stlouisfed.org/graph/fredgraph.csv?id=DFEDTARU&cosd=2011-01-01&coed=2026-12-31"
    resp = urllib.request.urlopen(url, timeout=20)
    data = resp.read().decode().strip().split("\n")
    series = {}
    for i, line in enumerate(data):
        if i == 0: continue
        parts = line.split(",")
        if len(parts) < 2 or parts[1] in (".", ""):
            continue
        try:
            series[parts[0]] = float(parts[1])
        except ValueError:
            continue
    # Detecta mudancas
    sorted_dates = sorted(series.keys())
    changes = []
    prev = None
    for d in sorted_dates:
        v = series[d]
        if prev is not None and v != prev:
            changes.append(d)
        prev = v
    return changes


def analyze_fomc(returns: Dict[str, float], fomc_dates: List[str]) -> None:
    pre_2d, post_2d, normal = [], [], []
    fomc_set = set(fomc_dates)
    fomc_sorted = sorted(fomc_dates)
    for date_iso, r in returns.items():
        d = datetime.fromisoformat(date_iso).date()
        is_pre = is_post = False
        # janela: 2d antes ate 2d depois
        for fomc in fomc_sorted:
            fdt = datetime.fromisoformat(fomc).date()
            delta = (d - fdt).days
            if 1 <= delta <= 2:
                is_post = True; break
            if -2 <= delta <= 0:
                is_pre = True; break
        if is_pre: pre_2d.append(r)
        elif is_post: post_2d.append(r)
        else: normal.append(r)

    print(f"  FOMC dates detectadas: {len(fomc_dates)} mudancas Fed Funds")
    print(f"\n  {'Window':<14} {'N':>6} {'mean%':>10} {'median%':>10}")
    print("  " + "-" * 44)
    for label, group in [("Pre FOMC -2d", pre_2d), ("Post FOMC +2d", post_2d), ("Normal", normal)]:
        s = stats(group)
        print(f"  {label:<14} {s['n']:>6} {s['mean']*100:>+9.3f}% {s['median']*100:>+9.3f}%")

    t1, p1 = t_test_two_groups(pre_2d, normal)
    t2, p2 = t_test_two_groups(post_2d, normal)
    diff1 = (stats(pre_2d)["mean"] - stats(normal)["mean"]) * 100
    diff2 = (stats(post_2d)["mean"] - stats(normal)["mean"]) * 100
    print(f"\n  Pre vs Normal:  diff={diff1:+.3f}pp  t={t1:.2f}  p={p1:.4f}  "
          f"{'(SIG)' if p1 < 0.05 else '(ns)'}")
    print(f"  Post vs Normal: diff={diff2:+.3f}pp  t={t2:.2f}  p={p2:.4f}  "
          f"{'(SIG)' if p2 < 0.05 else '(ns)'}")


# ── 4. Moon phase ────────────────────────────────────────────────────────────

NEW_MOON_REF = datetime(2000, 1, 6, 18, 14, tzinfo=timezone.utc)
LUNAR_CYCLE_DAYS = 29.530588853


def moon_phase(date_iso: str) -> float:
    """Retorna fase 0.0-1.0 (0=new moon, 0.5=full moon)."""
    d = datetime.fromisoformat(date_iso).replace(tzinfo=timezone.utc)
    days_since = (d - NEW_MOON_REF).total_seconds() / 86400
    return (days_since / LUNAR_CYCLE_DAYS) % 1.0


def analyze_moon(returns: Dict[str, float]) -> None:
    new_window, full_window, other = [], [], []
    # janela: +-2 dias da fase exata (0.0 ou 0.5)
    window = 2 / LUNAR_CYCLE_DAYS  # ~0.0677
    for date_iso, r in returns.items():
        p = moon_phase(date_iso)
        if p < window or p > 1 - window:
            new_window.append(r)
        elif abs(p - 0.5) < window:
            full_window.append(r)
        else:
            other.append(r)

    print(f"\n  {'Group':<14} {'N':>6} {'mean%':>10} {'median%':>10}")
    print("  " + "-" * 44)
    for label, group in [("New moon +-2d", new_window),
                          ("Full moon +-2d", full_window),
                          ("Other", other)]:
        s = stats(group)
        print(f"  {label:<14} {s['n']:>6} {s['mean']*100:>+9.3f}% {s['median']*100:>+9.3f}%")

    t1, p1 = t_test_two_groups(new_window, full_window)
    t2, p2 = t_test_two_groups(full_window, other)
    diff1 = (stats(new_window)["mean"] - stats(full_window)["mean"]) * 100
    diff2 = (stats(full_window)["mean"] - stats(other)["mean"]) * 100
    print(f"\n  New vs Full:   diff={diff1:+.3f}pp  t={t1:.2f}  p={p1:.4f}  "
          f"{'(SIG)' if p1 < 0.05 else '(ns)'}")
    print(f"  Full vs Other: diff={diff2:+.3f}pp  t={t2:.2f}  p={p2:.4f}  "
          f"{'(SIG)' if p2 < 0.05 else '(ns)'}")


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    daily = db.get_candles(MARKET, PERIOD_1D, "2011-01-01", "2026-12-31")
    daily_btc = {c["ts"][:10]: float(c["close"]) for c in daily}
    returns = daily_returns(daily_btc)
    print(f"  BTC candles: {len(daily_btc)} | Returns: {len(returns)}")

    sep = "=" * 60
    print(f"\n{sep}\n  1. DIA DA SEMANA\n{sep}")
    analyze_dow(returns)

    print(f"\n{sep}\n  2. ULTIMA SEMANA DO MES (dia >= 24)\n{sep}")
    analyze_last_week(returns)

    print(f"\n{sep}\n  3. JANELA FOMC (+-2d em torno de mudancas Fed Funds)\n{sep}")
    fomc = fetch_fomc_dates()
    analyze_fomc(returns, fomc)

    print(f"\n{sep}\n  4. FASE LUNAR (Yuan/Zheng/Zhu 2006)\n{sep}")
    analyze_moon(returns)

    print(f"\n{sep}\n  LEGENDA:\n{sep}")
    print("  pp/day = percentage points por dia")
    print("  SIG = p < 0.05 (significancia estatistica em t-test Welch)")
    print("  ns = nao significativo")


if __name__ == "__main__":
    main()
