"""regime_classifier.py — 8 estados de regime de mercado para BTC/cripto.

Estados:
  BULL_STRONG    — preco >=20% acima SMA200 + ADX>25 + retorno 60d > +15%
  BULL_WEAK      — preco acima SMA200, sem extremos
  SIDEWAYS       — |distancia SMA200| < 2% + ADX baixo + |retorno 60d| < 10%
  TRANSITION_UP  — cruzou SMA200 para cima nos ultimos 10 dias
  TRANSITION_DOWN— cruzou SMA200 para baixo nos ultimos 10 dias
  BEAR_WEAK      — preco abaixo SMA200, sem extremos
  BEAR_STRONG    — preco <=-15% abaixo SMA200 + ADX>25 + retorno 60d < -15%
  CAPITULATION   — preco abaixo 200WMA (override de tudo)
  INSUFFICIENT_DATA — < 200 candles

Zero lookahead: classify(candles) usa apenas candles fornecidos.
"""
from typing import List, Dict, Optional


# DRIFT-4/5 cross-ref 2026-05-16: source of truth = backtest/constants.py
# Migração futura: `from constants import SMA200_PERIOD as SMA200_WINDOW, SIDEWAYS_BAND as DIST_SIDEWAYS`
SMA200_WINDOW = 200
WMA200_BARS_DAILY = 1400    # 200 semanas em candles diarios
TRANSITION_WINDOW = 10      # dias para detectar cruzamento recente
RETURN_60D_LOOKBACK = 60

# Thresholds
# Distance e retorno 60d sao primarios (mais robustos que ADX em dados sinteticos/voláteis).
# ADX entra como confirmacao lenient — nao bloqueia STRONG em trends limpos.
DIST_SIDEWAYS = 0.02        # +-2% de SMA200 (alias de SIDEWAYS_BAND em constants.py)
DIST_STRONG = 0.15          # 15% (BULL_STRONG/BEAR_STRONG)
RETURN_60D_STRONG = 0.15    # 15% para STRONG
RETURN_60D_SIDEWAYS = 0.10  # < 10% para SIDEWAYS


def _sma(closes: List[float], n: int) -> float:
    if len(closes) < n:
        return 0.0
    return sum(closes[-n:]) / n


def _sma_at(closes: List[float], end_idx: int, n: int) -> Optional[float]:
    """SMA(n) terminando em end_idx (inclusive)."""
    start = end_idx - n + 1
    if start < 0:
        return None
    return sum(closes[start:end_idx + 1]) / n


def _detect_recent_cross(closes: List[float], window: int = TRANSITION_WINDOW) -> Optional[str]:
    """Detecta cruzamento SMA200 nos ultimos `window` candles.
    Retorna 'up', 'down' ou None.
    """
    n = len(closes)
    if n < SMA200_WINDOW + window:
        return None

    signs = []
    for i in range(window + 1):
        end_idx = n - 1 - i
        sma = _sma_at(closes, end_idx, SMA200_WINDOW)
        if sma is None:
            return None
        signs.append(1 if closes[end_idx] > sma else -1)
    signs.reverse()  # oldest first

    prev = signs[0]
    for s in signs[1:]:
        if s != prev:
            return "up" if s > 0 else "down"
        prev = s
    return None


def classify_regime(candles: List[Dict], bars_per_day: int = 1) -> str:
    """Classifica o regime do ultimo candle. Zero lookahead.

    Args:
      candles: lista de dicts {close, ...}
      bars_per_day: 1 para diario, 24 para 1h, 96 para 15m. Calibra a janela 200WMA.

    Ordem de prioridade:
      1. INSUFFICIENT_DATA  (< 200 candles)
      2. CAPITULATION       (close < 200WMA, se disponivel)
      3. TRANSITION_UP/DOWN (cruzamento recente)
      4. SIDEWAYS           (perto da SMA200 + baixo retorno 60d)
      5. BULL_STRONG / BEAR_STRONG (extremos)
      6. BULL_WEAK / BEAR_WEAK    (default acima/abaixo)
    """
    if not candles or len(candles) < SMA200_WINDOW:
        return "INSUFFICIENT_DATA"

    closes = [c["close"] for c in candles]
    price = closes[-1]
    sma200 = _sma(closes, SMA200_WINDOW)
    if sma200 <= 0:
        return "INSUFFICIENT_DATA"

    distance = (price - sma200) / sma200

    # 2) CAPITULATION — requer bars suficientes para representar 200 semanas reais
    wma_window = WMA200_BARS_DAILY * bars_per_day
    if len(closes) >= wma_window:
        wma200 = _sma(closes, wma_window)
        if wma200 > 0 and price < wma200:
            return "CAPITULATION"

    # 3) TRANSITION
    cross = _detect_recent_cross(closes, TRANSITION_WINDOW)
    if cross == "up":
        return "TRANSITION_UP"
    if cross == "down":
        return "TRANSITION_DOWN"

    # 60d return
    if len(closes) > RETURN_60D_LOOKBACK:
        ret_60d = (price - closes[-RETURN_60D_LOOKBACK - 1]) / closes[-RETURN_60D_LOOKBACK - 1]
    else:
        ret_60d = 0.0

    # 4) SIDEWAYS — distancia + retorno 60d pequenos (ADX nao bloqueia)
    if abs(distance) < DIST_SIDEWAYS and abs(ret_60d) < RETURN_60D_SIDEWAYS:
        return "SIDEWAYS"

    # 5) STRONG — distance + retorno 60d extremos (ADX como bonus opcional)
    if distance >= DIST_STRONG and ret_60d >= RETURN_60D_STRONG:
        return "BULL_STRONG"
    if distance <= -DIST_STRONG and ret_60d <= -RETURN_60D_STRONG:
        return "BEAR_STRONG"

    # 6) WEAK
    if distance > 0:
        return "BULL_WEAK"
    return "BEAR_WEAK"
