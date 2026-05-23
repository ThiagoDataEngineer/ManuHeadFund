"""
distribution_phase_detector.py -- Detector pos-distribuicao (rule-first).

Combina 4 indicadores macro-onchain (todos pure-py):
  - Pi Cycle (SMA111 vs SMA350*2)
  - ATH drawdown
  - NUPL proxy + trajetoria 30d
  - 200WMA contexto (status + tendencia)

Score 0-100 + estado:
  SAFE          : score < 40
  WARNING       : 40 <= score < 70
  DANGER        : score >= 70
  BEAR_CONFIRMED: ATH DD <= -50% (override)

Insuficient data (< 220 closes): retorna SAFE com flag.
"""
from __future__ import annotations

import os
import sys
from datetime import datetime, timezone
from typing import Dict, List, Optional, Sequence

import requests


# ──────────────────────────────────────────────────────────────────────────────
# Indicadores primarios (puros)
# ──────────────────────────────────────────────────────────────────────────────

def _sma(values: Sequence[float], n: int) -> Optional[float]:
    if n <= 0 or len(values) < n:
        return None
    return sum(values[-n:]) / n


def pi_cycle_state(daily_closes: Sequence[float], lookback_cross: int = 90) -> str:
    """Pi Cycle Top (semantico): detecta topo de ciclo via 2 caminhos.

    Caminho estrito: SMA111 cruza acima de SMA350*2 (Pi Cycle classico).
    Caminho semantico: ATH dentro dos ultimos 120 dias E current >= 10% abaixo.

    Estados:
      PRE_PEAK   : ainda em bull, sem topo recente
      TRIGGERED  : Pi Cycle classico cruzou ha < 30 dias
      POST_PEAK  : pos-topo (Pi Cycle ou semantico)
      NEUTRAL    : insuficiente para calcular
    """
    if len(daily_closes) < 120:
        return "NEUTRAL"
    closes = list(daily_closes)

    # Caminho semantico: ATH com idade >= 30d E retracao >=10% (filtra dips de bull)
    # Em bull forte (2017 dips), ATH sempre recente -> ATH_age baixo -> nao POST_PEAK.
    # Em pos-distribuicao real (2018 Jan, 2025 Mar), ATH ficou >=30 dias para tras.
    full_window = closes[-365:] if len(closes) >= 365 else closes
    ath_recent = max(full_window)
    ath_idx_from_end = len(full_window) - 1 - max(
        i for i, v in enumerate(full_window) if v == ath_recent
    )
    current = closes[-1]
    # Threshold ATH_age>=21d AND price < ATH*0.85:
    # - 2018 Jan: ATH 14-44d old, dropdown 0.56 -> capta
    # - 2025 Mar: ATH 50d+, dropdown 0.73 -> capta
    # - 2017 Sep dips: ATH 21-27d old, dropdown 0.85+ recuperando -> nao capta
    semantic_post_peak = (
        ath_idx_from_end >= 21
        and current < ath_recent * 0.85
    )

    # Caminho estrito (Pi Cycle classico)
    strict_state = "PRE_PEAK"
    if len(closes) >= 350:
        sma111_now = _sma(closes, 111)
        sma350_now = _sma(closes, 350)
        if sma111_now is not None and sma350_now is not None:
            above_now = sma111_now >= 2 * sma350_now
            recent_cross_idx = None
            # Scan barato: amostra 1 a cada 5 dias
            for i in range(len(closes) - 1, max(0, len(closes) - lookback_cross - 1), -5):
                s111 = _sma(closes[:i + 1], 111)
                s350 = _sma(closes[:i + 1], 350)
                s111_prev = _sma(closes[:i - 4], 111) if i > 5 else None
                s350_prev = _sma(closes[:i - 4], 350) if i > 5 else None
                if (s111 and s350 and s111_prev and s350_prev
                        and s111_prev < 2 * s350_prev and s111 >= 2 * s350):
                    recent_cross_idx = i
                    break
            if recent_cross_idx is not None:
                days_since = len(closes) - 1 - recent_cross_idx
                strict_state = "TRIGGERED" if days_since < 30 else "POST_PEAK"
            elif above_now:
                strict_state = "POST_PEAK"

    if strict_state in ("TRIGGERED", "POST_PEAK"):
        return strict_state
    if semantic_post_peak:
        return "POST_PEAK"
    return "PRE_PEAK"


def ath_drawdown_pct(daily_closes: Sequence[float]) -> float:
    """Drawdown % desde ATH (negativo)."""
    if not daily_closes:
        return 0.0
    ath = max(daily_closes)
    current = daily_closes[-1]
    if ath <= 0:
        return 0.0
    return (current / ath - 1.0) * 100.0


def nupl_proxy_score(fear_greed: int, sma200_distance_pct: float,
                     funding_rate_8h: float = 0.0) -> float:
    """NUPL proxy: 0-1. Mesma formula da lib_cycle_indicators.ps1."""
    fg = max(0.0, min(1.0, fear_greed / 100.0))
    sma = max(0.0, min(1.0, (sma200_distance_pct + 30.0) / 60.0))
    fund = max(0.0, min(1.0, (funding_rate_8h / 0.001) + 0.5))
    return 0.5 * fg + 0.3 * sma + 0.2 * fund


def nupl_trajectory(nupl_series: Sequence[float], window: int = 30) -> Dict:
    """Detecta declinio nos ultimos `window` valores."""
    if len(nupl_series) < 2:
        return {"declining": False, "previous_max_30d": 0.0, "current": 0.0}
    recent = list(nupl_series[-window:]) if len(nupl_series) >= window else list(nupl_series)
    current = recent[-1]
    prev_max = max(recent[:-1]) if len(recent) > 1 else current
    declining = current < prev_max - 0.05  # queda significativa
    return {
        "declining": declining,
        "previous_max_30d": prev_max,
        "current": current,
    }


def wma_200_context(daily_closes: Sequence[float]) -> Dict:
    """Status + trend do 200WMA (aprox via SMA200 daily * sqrt(7)/sqrt(7) -- simplifica para SMA200)."""
    if len(daily_closes) < 220:
        return {"status": "UNKNOWN", "trend": "flat", "distance_pct": 0.0}
    sma200_now = _sma(daily_closes, 200)
    sma200_prev = _sma(daily_closes[:-20], 200)
    if sma200_now is None or sma200_prev is None:
        return {"status": "UNKNOWN", "trend": "flat", "distance_pct": 0.0}
    current = daily_closes[-1]
    distance = (current / sma200_now - 1.0) * 100.0
    if distance > 40.0:
        status = "ABOVE_FAR"
    elif distance > 5.0:
        status = "ABOVE"
    elif distance > -5.0:
        status = "AT"
    elif distance > -20.0:
        status = "BELOW"
    else:
        status = "BELOW_FAR"
    if sma200_now > sma200_prev * 1.005:
        trend = "up"
    elif sma200_now < sma200_prev * 0.995:
        trend = "down"
    else:
        trend = "flat"
    return {"status": status, "trend": trend, "distance_pct": distance}


# ──────────────────────────────────────────────────────────────────────────────
# Score + state classification
# ──────────────────────────────────────────────────────────────────────────────

def classify_state_from_score(score: float, ath_dd_pct: float) -> str:
    if ath_dd_pct <= -50.0:
        return "BEAR_CONFIRMED"
    if score >= 70:
        return "DANGER"
    if score >= 40:
        return "WARNING"
    return "SAFE"


def detect_distribution_phase(
    daily_closes: Sequence[float],
    fear_greed: int = 50,
    funding_rate_8h: float = 0.0,
    nupl_history: Optional[Sequence[float]] = None,
) -> Dict:
    """Detector principal. Retorna dict completo com state + score + components."""
    if not daily_closes or len(daily_closes) < 220:
        return {
            "state": "SAFE",
            "score": 0.0,
            "components": {"pi_cycle": 0, "ath_dd": 0, "nupl": 0, "wma": 0, "return_30d": 0},
            "ath_dd_pct": 0.0,
            "insufficient_data": True,
        }

    closes = list(daily_closes)
    score = 0.0
    comp = {"pi_cycle": 0, "ath_dd": 0, "nupl": 0, "wma": 0,
            "return_30d": 0, "sustained_below": 0}

    # Return-30d component
    if len(closes) >= 31:
        return_30d = (closes[-1] / closes[-31] - 1.0) * 100.0
        if return_30d <= -25.0:
            comp["return_30d"] = 25
        elif return_30d <= -15.0:
            comp["return_30d"] = 18
        elif return_30d <= -7.0:
            comp["return_30d"] = 8
        score += comp["return_30d"]

    # Sustained-below: requer CONSECUTIVOS dias abaixo (nao acumulados)
    # para evitar somar 2 dips de bull separados como sinal distribuicao.
    ath_in_window = max(closes[-365:] if len(closes) >= 365 else closes)
    if ath_in_window > 0 and len(closes) >= 60:
        threshold_price = ath_in_window * 0.85
        consecutive = 0
        for c in reversed(closes[-60:]):
            if c < threshold_price:
                consecutive += 1
            else:
                break
        if consecutive >= 25:
            comp["sustained_below"] = 22
        elif consecutive >= 15:
            comp["sustained_below"] = 15
        score += comp["sustained_below"]

    # Pi Cycle
    pi_state = pi_cycle_state(closes)
    if pi_state == "POST_PEAK":
        comp["pi_cycle"] = 25
    elif pi_state == "TRIGGERED":
        comp["pi_cycle"] = 25
    score += comp["pi_cycle"]

    # ATH DD (peso recalibrado)
    dd = ath_drawdown_pct(closes)
    if dd <= -50.0:
        comp["ath_dd"] = 35
    elif dd <= -25.0:
        comp["ath_dd"] = 25
    elif dd <= -15.0:
        comp["ath_dd"] = 20
    elif dd <= -10.0:
        comp["ath_dd"] = 12
    elif dd <= -5.0:
        comp["ath_dd"] = 5
    score += comp["ath_dd"]

    # NUPL trajectory (se historico fornecido) -- senao estima a partir do contexto atual
    sma200 = _sma(closes, 200) or closes[-1]
    sma200_dist = (closes[-1] / sma200 - 1.0) * 100.0
    current_nupl = nupl_proxy_score(fear_greed, sma200_dist, funding_rate_8h)
    if nupl_history is None:
        # Estima trajetoria 30d via series de SMA200 distance + fg constante
        synth = []
        for k in range(30, 0, -1):
            if len(closes) >= 200 + k:
                window = closes[:-k] if k > 0 else closes
                sm = _sma(window, 200) or window[-1]
                d = (window[-1] / sm - 1.0) * 100.0
                synth.append(nupl_proxy_score(fear_greed, d, funding_rate_8h))
        synth.append(current_nupl)
        traj = nupl_trajectory(synth)
    else:
        traj = nupl_trajectory(list(nupl_history) + [current_nupl])
    if traj["declining"] and traj["previous_max_30d"] > 0.6:
        comp["nupl"] = 20
        score += 20

    # 200WMA context
    wma = wma_200_context(closes)
    if wma["status"] in ("ABOVE_FAR",) and wma["trend"] == "down":
        comp["wma"] = 15
        score += 15
    elif wma["status"] == "BELOW_FAR":
        comp["wma"] = 10
        score += 10

    state = classify_state_from_score(score, dd)

    return {
        "state": state,
        "score": round(score, 1),
        "components": comp,
        "ath_dd_pct": round(dd, 2),
        "pi_cycle_state": pi_state,
        "wma_status": wma["status"],
        "wma_trend": wma["trend"],
        "nupl_current": round(current_nupl, 3),
        "insufficient_data": False,
    }


# ──────────────────────────────────────────────────────────────────────────────
# Data loading (Bitstamp publico) -- usado nos testes 2-6
# ──────────────────────────────────────────────────────────────────────────────

_BITSTAMP_CACHE: Dict[str, List[float]] = {}


def fetch_btc_daily_closes(
    start_offset_days: int = 400,
    end_date: Optional[str] = None,
    pair: str = "btcusd",
) -> List[float]:
    """Baixa closes diarios BTC do Bitstamp ate end_date (inclusive).

    Returns lista ordenada ASC de closes. [] em caso de falha.
    """
    end_dt = datetime.fromisoformat(end_date).replace(tzinfo=timezone.utc) if end_date else datetime.now(timezone.utc)
    end_ts = int(end_dt.timestamp())

    cache_key = f"{pair}:{end_ts}"
    if cache_key in _BITSTAMP_CACHE:
        return _BITSTAMP_CACHE[cache_key]

    # Bitstamp limita ~1000 candles por chamada. Para cobrir longos periodos
    # paginamos para tras via end parameter.
    url = f"https://www.bitstamp.net/api/v2/ohlc/{pair}/"
    step = 86400  # diario
    closes_by_ts: Dict[int, float] = {}
    cur_end = end_ts
    # Limite total: ~30 anos = 11000 dias; paginas de 1000
    for _ in range(15):
        try:
            r = requests.get(url, params={"step": step, "limit": 1000, "end": cur_end}, timeout=15)
            r.raise_for_status()
            data = r.json().get("data", {}).get("ohlc", []) or []
        except Exception:
            break
        if not data:
            break
        oldest = cur_end
        for row in data:
            ts = int(row.get("timestamp", 0))
            close = float(row.get("close", 0))
            closes_by_ts[ts] = close
            if ts < oldest:
                oldest = ts
        if len(data) < 1000:
            break
        cur_end = oldest - 1

    ordered = [closes_by_ts[k] for k in sorted(closes_by_ts.keys())]
    _BITSTAMP_CACHE[cache_key] = ordered
    return ordered


def main():
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--end", default=None, help="Data ISO (ex: 2022-06-30)")
    args = p.parse_args()
    closes = fetch_btc_daily_closes(end_date=args.end)
    print(f"closes loaded: {len(closes)}")
    r = detect_distribution_phase(closes, fear_greed=50)
    import json as _j
    print(_j.dumps(r, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
