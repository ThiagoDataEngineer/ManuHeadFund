"""
regime_8state_classifier.py — Reclassifica bars/trades para 8 regimes refinados.

Usa SMA200 + ADX + estado de cruzamento + drawdown para classificar:
  BULL_STRONG    : preço > SMA200 E ADX > 25 E PDI > NDI E não-transition
  BULL_WEAK      : preço > SMA200 E (ADX <= 25 OU PDI <= NDI) E não-transition
  TRANSITION_UP  : SMA200 cruzou para cima nos últimos TRANSITION_BARS
  TRANSITION_DOWN: SMA200 cruzou para baixo nos últimos TRANSITION_BARS
  SIDEWAYS       : |preço - SMA200| / SMA200 < SIDEWAYS_BAND
  BEAR_WEAK      : preço < SMA200 E ADX <= 25 (e não CAPITULATION/TRANSITION)
  BEAR_STRONG    : preço < SMA200 E ADX > 25 E NDI > PDI (e não CAPITULATION)
  CAPITULATION   : preço < SMA200 E (preço/SMA200 - 1) < -CAPITULATION_THRESHOLD

Precedência (descendente):
  CAPITULATION > TRANSITION_UP/DOWN > BULL_STRONG/WEAK / BEAR_STRONG/WEAK > SIDEWAYS

NÃO MODIFICA: db.py, signal_generator.py, metrics.py, indicators.py.
Tested in: tests/test_regime_8state_classifier.py (10 testes pytest TDD).
"""
from typing import Dict, List, Optional

from indicators import adx as _adx_calc


# DRIFT-4/5 cross-ref 2026-05-16: source of truth = backtest/constants.py
SMA200_PERIOD          = 200
ADX_PERIOD             = 14
TRANSITION_BARS        = 20      # janela para detectar cruzamento recente
SIDEWAYS_BAND          = 0.02    # +-2% em torno da SMA200
ADX_STRONG_THRESHOLD   = 25.0
CAPITULATION_THRESHOLD = 0.25    # 25% abaixo da SMA200


def _sma(closes: List[float], period: int) -> float:
    if len(closes) < period:
        return 0.0
    return sum(closes[-period:]) / period


def _safe_adx(candles: List[Dict], period: int = ADX_PERIOD) -> Dict:
    try:
        return _adx_calc(candles, period=period)
    except Exception:
        return {"adx": 0.0, "pdi": 0.0, "ndi": 0.0}


def _detect_recent_cross(
    candles: List[Dict], idx: int, lookback: int = TRANSITION_BARS
) -> Optional[str]:
    """Retorna 'UP' se preço cruzou SMA200 para cima nos últimos lookback bars,
    'DOWN' se cruzou para baixo, ou None."""
    start = max(SMA200_PERIOD, idx - lookback + 1)
    if idx < SMA200_PERIOD:
        return None
    closes = [c["close"] for c in candles]
    last_pos = None  # True se acima, False se abaixo
    crossed = None
    for i in range(start, idx + 1):
        sma = _sma(closes[:i + 1], SMA200_PERIOD)
        if sma <= 0:
            continue
        above = closes[i] > sma
        if last_pos is None:
            last_pos = above
            continue
        if above != last_pos:
            crossed = "UP" if above else "DOWN"
            last_pos = above
    return crossed


def classify_8state(candles: List[Dict], idx: int) -> str:
    """Classifica o regime no bar idx usando candles[0..idx]."""
    if idx < SMA200_PERIOD or len(candles) <= idx:
        return "UNKNOWN"

    closes = [c["close"] for c in candles[:idx + 1]]
    price  = closes[-1]
    sma200 = _sma(closes, SMA200_PERIOD)
    if sma200 <= 0:
        return "UNKNOWN"

    distance = (price - sma200) / sma200

    # CAPITULATION tem precedência (preço muito longe abaixo)
    if distance < -CAPITULATION_THRESHOLD:
        return "CAPITULATION"

    # TRANSITION (cruzamento recente)
    cross = _detect_recent_cross(candles, idx, TRANSITION_BARS)
    if cross == "UP":
        return "TRANSITION_UP"
    if cross == "DOWN":
        return "TRANSITION_DOWN"

    # SIDEWAYS (banda neutra)
    if abs(distance) < SIDEWAYS_BAND:
        return "SIDEWAYS"

    # ADX para diferenciar STRONG/WEAK
    adx_window = candles[max(0, idx - ADX_PERIOD * 3):idx + 1]
    adx_res = _safe_adx(adx_window, period=ADX_PERIOD)
    adx_val = float(adx_res.get("adx", 0.0))
    pdi     = float(adx_res.get("pdi", 0.0))
    ndi     = float(adx_res.get("ndi", 0.0))

    if distance > 0:
        # BULL
        if adx_val > ADX_STRONG_THRESHOLD and pdi > ndi:
            return "BULL_STRONG"
        return "BULL_WEAK"
    else:
        # BEAR
        if adx_val > ADX_STRONG_THRESHOLD and ndi > pdi:
            return "BEAR_STRONG"
        return "BEAR_WEAK"


# ============================================================================
# FAST PATH — precompute SMA200 / ADX / cross flags em UMA passada
# ============================================================================

def precompute_indicators(
    candles: List[Dict],
    transition_bars: int = TRANSITION_BARS,
) -> Dict:
    """
    Pre-computa em UMA passada todas as informacoes necessarias para classify
    em O(1): SMA200, distance_pct, ADX/PDI/NDI, transition flags.

    transition_bars: parametrizável para recalibração (default TRANSITION_BARS).
    """
    n = len(candles)
    closes = [c["close"] for c in candles]
    highs  = [c["high"]  for c in candles]
    lows   = [c["low"]   for c in candles]

    # SMA200 rolling — janela deslizante O(N)
    sma_series: List[float] = [None] * n  # type: ignore[list-item]
    running_sum = 0.0
    for i in range(n):
        running_sum += closes[i]
        if i >= SMA200_PERIOD:
            running_sum -= closes[i - SMA200_PERIOD]
        if i >= SMA200_PERIOD - 1:
            sma_series[i] = running_sum / SMA200_PERIOD

    # Distance: (price - sma200) / sma200
    distance: List[float] = [None] * n  # type: ignore[list-item]
    for i in range(n):
        if sma_series[i] is not None and sma_series[i] > 0:
            distance[i] = (closes[i] - sma_series[i]) / sma_series[i]

    # Cross flags — itera UMA vez detectando cruzamentos
    last_pos = None  # True se acima
    last_cross_idx = None
    last_cross_dir = None  # 'UP' / 'DOWN'
    transition: List[str] = [None] * n  # type: ignore[list-item]
    for i in range(n):
        if sma_series[i] is None:
            continue
        above = closes[i] > sma_series[i]
        if last_pos is None:
            last_pos = above
        elif above != last_pos:
            last_cross_idx = i
            last_cross_dir = "UP" if above else "DOWN"
            last_pos = above
        # Trans ativa se cruzamento recente (<=transition_bars)
        if last_cross_idx is not None and (i - last_cross_idx) <= transition_bars:
            transition[i] = last_cross_dir

    # ADX/PDI/NDI rolling com smoothing de Wilder — UMA passada
    adx_arr = [0.0] * n
    pdi_arr = [0.0] * n
    ndi_arr = [0.0] * n

    tr_list:  List[float] = [0.0] * n
    pdm_list: List[float] = [0.0] * n
    ndm_list: List[float] = [0.0] * n
    for i in range(1, n):
        h, l, pc = highs[i], lows[i], closes[i - 1]
        tr = max(h - l, abs(h - pc), abs(l - pc))
        up = h - highs[i - 1]
        dn = lows[i - 1] - l
        tr_list[i]  = tr
        pdm_list[i] = up if up > dn and up > 0 else 0.0
        ndm_list[i] = dn if dn > up and dn > 0 else 0.0

    # Wilder smoothed: cumulative
    if n > ADX_PERIOD:
        tr_s  = sum(tr_list[1:ADX_PERIOD + 1])
        pdm_s = sum(pdm_list[1:ADX_PERIOD + 1])
        ndm_s = sum(ndm_list[1:ADX_PERIOD + 1])

        dx_buffer: List[float] = []
        adx_running = 0.0

        for i in range(ADX_PERIOD + 1, n):
            tr_s  = tr_s  - tr_s  / ADX_PERIOD + tr_list[i]
            pdm_s = pdm_s - pdm_s / ADX_PERIOD + pdm_list[i]
            ndm_s = ndm_s - ndm_s / ADX_PERIOD + ndm_list[i]

            if tr_s == 0:
                pdi = ndi = 0.0
            else:
                pdi = 100.0 * pdm_s / tr_s
                ndi = 100.0 * ndm_s / tr_s
            dx = 100.0 * abs(pdi - ndi) / (pdi + ndi) if (pdi + ndi) > 0 else 0.0

            dx_buffer.append(dx)
            if len(dx_buffer) == ADX_PERIOD:
                adx_running = sum(dx_buffer) / ADX_PERIOD
            elif len(dx_buffer) > ADX_PERIOD:
                adx_running = (adx_running * (ADX_PERIOD - 1) + dx) / ADX_PERIOD

            adx_arr[i] = adx_running if len(dx_buffer) >= ADX_PERIOD else 0.0
            pdi_arr[i] = pdi
            ndi_arr[i] = ndi

    return {
        "sma200":     sma_series,
        "distance":   distance,
        "adx":        adx_arr,
        "pdi":        pdi_arr,
        "ndi":        ndi_arr,
        "transition": transition,
    }


def classify_8state_fast(
    precomputed: Dict,
    idx: int,
    adx_strong: float = ADX_STRONG_THRESHOLD,
    sideways_band: float = SIDEWAYS_BAND,
    capitulation: float = CAPITULATION_THRESHOLD,
) -> str:
    """Versão O(1) usando indicadores pré-computados. Aceita thresholds custom para recalibração."""
    sma = precomputed["sma200"][idx] if idx < len(precomputed["sma200"]) else None
    if sma is None or sma <= 0:
        return "UNKNOWN"

    dist = precomputed["distance"][idx]
    if dist is None:
        return "UNKNOWN"

    if dist < -capitulation:
        return "CAPITULATION"

    trans = precomputed["transition"][idx]
    if trans == "UP":
        return "TRANSITION_UP"
    if trans == "DOWN":
        return "TRANSITION_DOWN"

    if abs(dist) < sideways_band:
        return "SIDEWAYS"

    adx_val = precomputed["adx"][idx]
    pdi     = precomputed["pdi"][idx]
    ndi     = precomputed["ndi"][idx]

    if dist > 0:
        if adx_val > adx_strong and pdi > ndi:
            return "BULL_STRONG"
        return "BULL_WEAK"
    else:
        if adx_val > adx_strong and ndi > pdi:
            return "BEAR_STRONG"
        return "BEAR_WEAK"


# ----------------------------------------------------------------------------
# Pipeline: reclassifica trades usando candles
# ----------------------------------------------------------------------------

def _build_ts_index(candles: List[Dict]) -> Dict[str, int]:
    """Indexa candles por ts (e por ts[:10] como fallback diário)."""
    idx_map: Dict[str, int] = {}
    for i, c in enumerate(candles):
        ts = c.get("ts")
        if not ts:
            continue
        idx_map[ts] = i
        # Fallback para casamento diário
        day = str(ts)[:10]
        if day not in idx_map:
            idx_map[day] = i
    return idx_map


def reclassify_trades_8state(
    trades: List[Dict],
    candles: List[Dict],
    adx_strong: float = ADX_STRONG_THRESHOLD,
    transition_bars: int = TRANSITION_BARS,
    sideways_band: float = SIDEWAYS_BAND,
    capitulation: float = CAPITULATION_THRESHOLD,
) -> List[Dict]:
    """Para cada trade, encontra o candle correspondente (por entry_ts) e
    reclassifica o regime usando classify_8state.

    Retorna NOVA lista de trades com 'regime' atualizado para 8-state.
    Trades sem candle correspondente mantêm 'regime' original.
    """
    if not candles:
        return [dict(t) for t in trades]

    # Ordena candles por ts e cria índice
    sorted_candles = sorted(candles, key=lambda c: str(c.get("ts", "")))
    idx_map = _build_ts_index(sorted_candles)

    # FAST PATH: pre-computa indicadores em UMA passada O(N) em vez de O(N*M)
    precomputed = precompute_indicators(sorted_candles, transition_bars=transition_bars)

    out: List[Dict] = []
    for t in trades:
        nt = dict(t)
        entry_ts = t.get("entry_ts") or t.get("bar_ts")
        if entry_ts is None:
            out.append(nt)
            continue

        i = idx_map.get(entry_ts) or idx_map.get(str(entry_ts)[:10])
        if i is None:
            i = _find_le(sorted_candles, entry_ts)

        if i is None or i < SMA200_PERIOD:
            out.append(nt)
            continue

        regime = classify_8state_fast(
            precomputed, i,
            adx_strong=adx_strong,
            sideways_band=sideways_band,
            capitulation=capitulation,
        )
        if regime != "UNKNOWN":
            nt["regime"] = regime
        out.append(nt)

    return out


def _find_le(candles: List[Dict], target_ts: str) -> Optional[int]:
    """Binary search: maior idx tal que candles[idx].ts <= target_ts."""
    lo, hi = 0, len(candles) - 1
    res = None
    while lo <= hi:
        mid = (lo + hi) // 2
        if str(candles[mid].get("ts", "")) <= str(target_ts):
            res = mid
            lo = mid + 1
        else:
            hi = mid - 1
    return res
