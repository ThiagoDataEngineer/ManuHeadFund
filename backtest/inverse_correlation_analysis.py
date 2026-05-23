"""
inverse_correlation_analysis.py -- Valida correlacao negativa cross-window.

Pergunta: corr(X, BTC) = -0.30 em 30d eh edge real ou ruido?
Resposta honesta: depende de:
  1. Estabilidade cross-window (30d/60d/90d/180d/365d devem todos ser <0 ou perto)
  2. Inverse strength: quando BTC +X%, qual o beta medio de Y? (regressao)
  3. Stability: rolling 30d windows mostra negative consistent OU oscila?

Output: tabela cross-window + beta + estabilidade pra cada candidate.
"""
from __future__ import annotations

import json
import sys
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CANDLES_DIR = ROOT / "journal" / "candles_coinex"

# Reuso functions do correlation_matrix.py
sys.path.insert(0, str(ROOT / "backtest"))
from correlation_matrix import load_closes, pearson  # noqa: E402


def daily_returns_full(closes):
    return [(closes[i] - closes[i-1]) / closes[i-1] for i in range(1, len(closes)) if closes[i-1] > 0]


def windowed_corr(returns_a, returns_b, window):
    """Corr nos ultimos N returns."""
    if len(returns_a) < window or len(returns_b) < window:
        return None
    n = min(len(returns_a), len(returns_b))
    return pearson(returns_a[-window:], returns_b[-window:])


def rolling_corr_stability(returns_a, returns_b, window=30, step=15):
    """Janelas deslizantes de N dias. Retorna lista de correlacoes."""
    n = min(len(returns_a), len(returns_b))
    if n < window + step:
        return []
    out = []
    for end in range(window, n + 1, step):
        a = returns_a[end-window:end]
        b = returns_b[end-window:end]
        c = pearson(a, b)
        if c is not None:
            out.append(c)
    return out


def regression_beta(returns_y, returns_x):
    """beta = cov(x,y) / var(x). Y = alpha + beta*X."""
    if len(returns_y) != len(returns_x) or len(returns_x) < 10:
        return None
    n = len(returns_x)
    mean_x = sum(returns_x) / n
    mean_y = sum(returns_y) / n
    cov = sum((returns_x[i] - mean_x) * (returns_y[i] - mean_y) for i in range(n)) / n
    var_x = sum((x - mean_x) ** 2 for x in returns_x) / n
    if var_x == 0:
        return None
    return cov / var_x


def analyze(candidates, base="BTCUSDT"):
    btc_closes = load_closes(base)
    if not btc_closes:
        print(f"[error] sem candles para {base}")
        return
    btc_ret = daily_returns_full(btc_closes)
    print(f"BTC returns disponiveis: {len(btc_ret)} dias\n")

    rows = []
    for c in candidates:
        closes = load_closes(c)
        if not closes:
            rows.append((c, "no_candles", None, None, None, None, None, None))
            continue
        ret = daily_returns_full(closes)
        # Aligna pelo fim (assume datas alinhadas; aproximacao)
        n = min(len(ret), len(btc_ret))
        a = ret[-n:]
        b = btc_ret[-n:]
        c30 = windowed_corr(a, b, 30)
        c90 = windowed_corr(a, b, 90)
        c180 = windowed_corr(a, b, 180)
        c365 = windowed_corr(a, b, 365)
        beta = regression_beta(a[-min(180, len(a)):], b[-min(180, len(b)):])
        # Rolling 30d stability
        roll = rolling_corr_stability(a, b, window=30, step=15)
        roll_neg_pct = sum(1 for r in roll if r < 0) / len(roll) if roll else None
        rows.append((c, n, c30, c90, c180, c365, beta, roll_neg_pct))

    print(f"{'Market':<14} {'n':>5}  {'30d':>7} {'90d':>7} {'180d':>7} {'365d':>7} {'beta180':>9} {'%neg_30d_roll':>14}")
    print("-" * 88)
    for row in rows:
        m, n, c30, c90, c180, c365, beta, pneg = row
        if n == "no_candles":
            print(f"{m:<14} (sem candles)")
            continue
        s30  = f"{c30:+.3f}" if c30 is not None else "  -  "
        s90  = f"{c90:+.3f}" if c90 is not None else "  -  "
        s180 = f"{c180:+.3f}" if c180 is not None else "  -  "
        s365 = f"{c365:+.3f}" if c365 is not None else "  -  "
        sb   = f"{beta:+.3f}" if beta is not None else "  -  "
        sp   = f"{pneg*100:.0f}%" if pneg is not None else "  -  "
        print(f"{m:<14} {n:>5}  {s30:>7} {s90:>7} {s180:>7} {s365:>7} {sb:>9} {sp:>14}")

    print()
    print("Leitura:")
    print("  - corr estavel <0 em 30/90/180/365 = inverso REAL (calibrar contra-BTC)")
    print("  - corr 30d <0 mas 365d >0 = ruido recente ou cycle-dependent (NAO confiavel sozinho)")
    print("  - beta < 0 confirma sensibilidade negativa (Y cai quando X sobe)")
    print("  - %neg_roll alta = inverse PERSISTENTE nas janelas; baixa = oscila sinal")


if __name__ == "__main__":
    targets = sys.argv[1:] if len(sys.argv) > 1 else [
        "HYPEUSDT", "NEARUSDT", "DYDXUSDT", "SOLUSDT", "TONUSDT",
        "STORJUSDT", "VVVUSDT", "ONDOUSDT", "ZECUSDT", "INJUSDT",
        "XMRUSDT", "CFGUSDT"
    ]
    analyze(targets)
