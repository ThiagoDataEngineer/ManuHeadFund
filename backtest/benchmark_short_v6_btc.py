"""
benchmark_short_v6_btc.py -- V6 SHORT validation on classic bears (2018, 2022).

Extends baseline_v2 with non-LLM V6 components:
  1. Regime 8-state filter: SHORT только в BEAR_WEAK/BEAR_STRONG/CAPITULATION/TRANSITION_DOWN/SIDEWAYS
  2. Tori trendline gate (proxy): entry SHORT só se price breakdown ou touch resistance
  3. Funding peak overlay: import if available, fallback gracefully for 2018-2022 BTC
  4. Equity stop refinement: -10R pause + 24h reset window

Reusoamos funcs puras de benchmark_short_bear.py para máxima compatibilidade.

PUBLIC API:
  run_benchmark_short_v6(market="BTCUSD", ...) -> dict (same shape as V2)

CLI:
  python backtest/benchmark_short_v6_btc.py --output journal/benchmark_short_v6_btc_YYYY_MM_DD.json
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Dict, List, Optional, Sequence, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Import funcs puras de benchmark_short_bear
from benchmark_short_bear import (
    simulate_short_pnl_r,
    calc_short_stop,
    calc_short_target,
    classify_trend,
    is_long_fade_blocked_by_kbfix,
    is_short_signal_kbfix,
    aggregate_metrics,
    build_period_result,
    build_result_skeleton,
    load_bear_candles,
    EquityStopTracker,
)

from trade_simulator import simulate_trade  # noqa: E402
from metrics import calc_metrics  # noqa: E402

# Optional imports (graceful fallback)
try:
    from regime_8state_classifier import (
        precompute_indicators,
        classify_8state_fast,
    )
    REGIME_AVAILABLE = True
except ImportError:
    REGIME_AVAILABLE = False

try:
    from funding_peak import scan_signals as funding_scan_signals
    FUNDING_AVAILABLE = True
except ImportError:
    FUNDING_AVAILABLE = False

try:
    from meta_label_short import apply_meta_filter, MetaLabelConfig
    META_LABEL_AVAILABLE = True
except ImportError:
    META_LABEL_AVAILABLE = False


# ──────────────────────────────────────────────────────────────────────────────
# V6 Layer: Regime filter
# ──────────────────────────────────────────────────────────────────────────────

# Regimes permitidos para SHORT segundo whitelist v2 rule 5 (paper tier)
SHORT_ALLOWED_REGIMES = frozenset({
    "BEAR_WEAK",
    "BEAR_STRONG",
    "CAPITULATION",
    "TRANSITION_DOWN",
    "SIDEWAYS",
})


def get_regime_at_idx(precomputed: Optional[Dict], idx: int) -> str:
    """Retorna regime no bar idx. Se precomputed=None, retorna 'UNKNOWN'."""
    if precomputed is None:
        return "UNKNOWN"
    try:
        # Usar fast path
        from regime_8state_classifier import classify_8state_fast
        return classify_8state_fast(precomputed, idx)
    except Exception:
        return "UNKNOWN"


# ──────────────────────────────────────────────────────────────────────────────
# V6 Layer: Tori trendline gate (proxy)
# ──────────────────────────────────────────────────────────────────────────────

def tori_trendline_proxy(candles: List[Dict], idx: int, lookback: int = 5) -> bool:
    """Simula Tori gate determinístico via price action.

    Retorna True se:
      - close[idx-1] < min(close[idx-lookback:idx-1])  (breakdown)
      - OU close[idx-1] < high[idx-lookback:] * 0.99    (rejeição em resistência)
    """
    if idx < lookback - 1 or len(candles) <= idx:
        return False

    # Window inclui candle no idx (last to evaluate) + lookback-1 anteriores
    window = candles[max(0, idx - lookback + 1):idx + 1]
    if len(window) < 2:
        return False

    closes = [c["close"] for c in window]
    highs = [c["high"] for c in window]

    last_close = closes[-1]
    min_close = min(closes[:-1]) if len(closes) > 1 else closes[-1]
    max_high = max(highs[:-1]) if len(highs) > 1 else highs[-1]

    breakdown = last_close < min_close
    rejection = last_close < max_high * 0.99

    return breakdown or rejection


# ──────────────────────────────────────────────────────────────────────────────
# V6 Layer: Enhanced equity stop (pause + reset after -10R)
# ──────────────────────────────────────────────────────────────────────────────

@dataclass
class EquityStopTrackerV6(EquityStopTracker):
    """Estende baseline V2 com pause window de 24h (5 barras aprox) após -10R hit."""
    pause_bars: int = 5  # ~24h em daily
    pause_countdown: int = 0

    def on_trade_close(self, r: float) -> None:
        """Update equity e gerencia pause window."""
        self.equity += r
        if self.equity > self.peak:
            self.peak = self.equity
        dd = self.peak - self.equity

        if dd >= self.threshold_R:
            self._paused = True
            self.pause_countdown = self.pause_bars
        else:
            # Decrement pause counter
            if self.pause_countdown > 0:
                self.pause_countdown -= 1
            if self.pause_countdown <= 0:
                self._paused = False

    def on_bar_advance(self) -> None:
        """Call a cada bar novo (mesmo sem trade). Avança pause counter."""
        if self.pause_countdown > 0:
            self.pause_countdown -= 1
        if self.pause_countdown <= 0:
            self._paused = False


# ──────────────────────────────────────────────────────────────────────────────
# V6 Filter composition
# ──────────────────────────────────────────────────────────────────────────────

def _build_meta_signal(sig, candles: List[Dict], idx: int, regime: str) -> Dict:
    """Constroi signal dict pra meta_label a partir de dados disponiveis no backtest.

    Funding/OI nao disponiveis em historico BTC 2018-2022 -> placeholder 0.
    Meta-label efetivo aqui = regime + DoW + ATR.
    """
    ts = candles[idx].get("timestamp", 0)
    try:
        dt = datetime.utcfromtimestamp(ts / 1000 if ts > 1e12 else ts)
        dow = dt.strftime("%A")
        session_hr_brt = (dt.hour - 3) % 24
    except Exception:
        dow = "Wednesday"
        session_hr_brt = 12
    entry = getattr(sig, "entry_price", 0) or candles[idx].get("close", 0)
    atr_val = getattr(sig, "atr", 0) or (candles[idx]["high"] - candles[idx]["low"])
    atr_pct = (atr_val / entry) if entry > 0 else 0.02
    return {
        "regime": regime,
        "funding_z": 0.0,
        "oi_delta_pct": 0.0,
        "dow": dow,
        "atr_pct": atr_pct,
        "session_hr_brt": session_hr_brt,
        "direction": "short",
    }


def passes_v6_filters(
    sig,
    candles: List[Dict],
    idx: int,
    precomputed: Optional[Dict],
    tracker: EquityStopTrackerV6,
    apply_meta_label: bool = False,
    meta_threshold: float = 0.55,
) -> Tuple[bool, Dict]:
    """Aplica todos os filtros V6 e retorna (passed, {filter_results})."""
    filters = {
        "regime_filter": False,
        "regime_name": "UNKNOWN",
        "tori_gate": False,
        "funding_proxy": None,
        "equity_pause": False,
        "meta_label_p_win": None,
        "meta_label_passed": None,
    }

    # 1. Regime filter
    regime = get_regime_at_idx(precomputed, idx)
    filters["regime_name"] = regime
    if regime in SHORT_ALLOWED_REGIMES:
        filters["regime_filter"] = True
    else:
        return False, filters

    # 2. Tori gate
    if tori_trendline_proxy(candles, idx, lookback=5):
        filters["tori_gate"] = True
    else:
        return False, filters

    # 3. Equity pause check
    if tracker.should_skip_signal():
        filters["equity_pause"] = True
        return False, filters

    # 4. Meta-labeling (optional, additive)
    if apply_meta_label and META_LABEL_AVAILABLE:
        meta_sig = _build_meta_signal(sig, candles, idx, regime)
        meta_result = apply_meta_filter(meta_sig, MetaLabelConfig(p_win_threshold=meta_threshold))
        filters["meta_label_p_win"] = meta_result["p_win"]
        filters["meta_label_passed"] = meta_result["passes"]
        if not meta_result["passes"]:
            return False, filters

    # 5. Funding (placeholder — sem dado histórico BTC)
    filters["funding_proxy"] = "unavailable_btc_2018_2022"

    return True, filters


# ──────────────────────────────────────────────────────────────────────────────
# Signal generation wrapper (reuso de signal_generator)
# ──────────────────────────────────────────────────────────────────────────────

def _try_generate_signal(candles_window: List[Dict]):
    """Reusa signal_generator.generate_signal (LEITURA apenas)."""
    try:
        from signal_generator import generate_signal
        return generate_signal(candles_window)
    except Exception:
        return None


# ──────────────────────────────────────────────────────────────────────────────
# V6 Scan loop
# ──────────────────────────────────────────────────────────────────────────────

def scan_period_v6(market: str, start: str, end: str, max_lookahead_bars: int = 40,
                   apply_meta_label: bool = False, meta_threshold: float = 0.55) -> Dict:
    """Roda scan SHORT-only V6 com regime filtering + Tori gate + enhanced equity stop."""
    candles = load_bear_candles(market, start, end)
    if not candles:
        return {
            "r_series": [],
            "n_skipped": 0,
            "n_signals": 0,
            "n_regime_filtered": 0,
            "n_tori_filtered": 0,
            "n_equity_paused": 0,
            "data_unavailable": True,
            "v6_filters_applied": {},
        }

    # Pre-compute regime indicators
    precomputed = None
    if REGIME_AVAILABLE:
        try:
            precomputed = precompute_indicators(candles)
        except Exception:
            pass

    MIN_WINDOW = 60
    tracker = EquityStopTrackerV6(threshold_R=10.0)
    r_series: List[float] = []
    n_skipped = 0
    n_signals = 0
    n_regime_filtered = 0
    n_tori_filtered = 0
    n_equity_paused = 0
    n_meta_filtered = 0
    filters_applied = {regime: 0 for regime in SHORT_ALLOWED_REGIMES}
    filters_applied["REJECTED"] = 0

    i = MIN_WINDOW
    while i < len(candles) - 5:
        window = candles[max(0, i - 200):i + 1]
        sig = _try_generate_signal(window)

        if sig is None or sig.signal != "VENDA":
            tracker.on_bar_advance()
            i += 1
            continue

        n_signals += 1

        # Apply V6 filters
        passed, filter_result = passes_v6_filters(
            sig, candles, i, precomputed, tracker,
            apply_meta_label=apply_meta_label, meta_threshold=meta_threshold,
        )

        if not passed:
            regime_name = filter_result.get("regime_name", "UNKNOWN")
            if regime_name == "UNKNOWN":
                n_regime_filtered += 1
            elif not filter_result.get("tori_gate"):
                n_tori_filtered += 1
            elif filter_result.get("equity_pause"):
                n_equity_paused += 1
            elif filter_result.get("meta_label_passed") is False:
                n_meta_filtered += 1

            if regime_name in filters_applied:
                filters_applied[regime_name] += 1
            else:
                filters_applied["REJECTED"] += 1

            tracker.on_bar_advance()
            i += 1
            continue

        # Signal passed — execute trade
        atr_val = getattr(sig, "atr", 0.0) or (candles[i]["high"] - candles[i]["low"])
        entry = sig.entry_price
        stop = sig.stop_loss if sig.stop_loss > entry else calc_short_stop(entry, atr_val)
        target = sig.take_profit if sig.take_profit < entry else calc_short_target(entry, stop, 5.0)

        fwd = candles[i + 1:i + 1 + max_lookahead_bars]
        r = simulate_short_pnl_r(entry, stop, target, fwd)
        r_series.append(r)
        tracker.on_trade_close(r)

        # Track regime de execução
        regime = filter_result.get("regime_name", "UNKNOWN")
        if regime in filters_applied:
            filters_applied[regime] += 1

        # Avancar
        i += max(1, min(max_lookahead_bars, 5))

    return {
        "r_series": r_series,
        "n_skipped": n_skipped,
        "n_signals": n_signals,
        "n_regime_filtered": n_regime_filtered,
        "n_tori_filtered": n_tori_filtered,
        "n_equity_paused": n_equity_paused,
        "n_meta_filtered": n_meta_filtered,
        "data_unavailable": False,
        "v6_filters_applied": filters_applied,
    }


# ──────────────────────────────────────────────────────────────────────────────
# Comparison builder
# ──────────────────────────────────────────────────────────────────────────────

def build_period_result_v6(
    period_id: str,
    market: str,
    start: str,
    end: str,
    r_series: Sequence[float],
    v6_filters: Dict = None,
) -> Dict:
    """Extended period result com V6 metadata."""
    base = build_period_result(period_id, market, start, end, r_series)
    base["v6_filters"] = v6_filters or {}
    return base


def classify_verdict_v6(expectancy_r: float, dd_ratio: float) -> str:
    """Veredito SHORT V6 (mais permissivo que V2).

    SHORT_EDGE_V6 : exp >= +0.40R e dd_ratio < 0.6
    SHORT_MARGINAL : exp >= +0.20R OU dd_ratio < 0.8
    SHORT_INSUFICIENTE : caso contrario
    """
    if expectancy_r >= 0.40 and dd_ratio < 0.6:
        return "SHORT_EDGE_V6"
    if expectancy_r >= 0.20 or dd_ratio < 0.8:
        return "SHORT_MARGINAL"
    return "SHORT_INSUFICIENTE"


def build_result_skeleton_v6(periods: List[Dict]) -> Dict:
    """GO criterion para V6: expectancy >= +0.40R em AMBOS + PF >= 1.5 + DD <= 12R."""
    all_good = all(
        p["metrics"]["expectancy_r"] >= 0.40
        and p["metrics"]["profit_factor"] >= 1.5
        and p["metrics"]["max_dd_r"] <= 12.0
        for p in periods
    )

    if all_good:
        explanation = (
            "SHORT com V6 layer demonstra edge em bears classicos: "
            "expectancy >= +0.40R, PF >= 1.5, DD <= 12R em ambos periodos. "
            "V6 destranca SHORT em regime bear vs V2 baseline."
        )
        implication = (
            "HOLD: V6 destranca SHORT em regime bear. Prosseguir para paper trade antes de live."
        )
    else:
        weak = [
            p["period_id"]
            for p in periods
            if (
                p["metrics"]["expectancy_r"] < 0.40
                or p["metrics"]["profit_factor"] < 1.5
                or p["metrics"]["max_dd_r"] > 12.0
            )
        ]
        explanation = (
            f"Criterio falha em: {', '.join(weak)}. "
            "V6 nao resolve insuficiencia estrutural."
        )
        implication = (
            "HOLD: SHORT segue inviavel. Revisitar quando houver dataset altcoin com mais liquides."
        )

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "config": "v6_short_btc",
        "periods": periods,
        "go_criterion": {
            "rule": "expectancy >= +0.40R + PF >= 1.5 + DD <= 12R em ambos bears",
            "passed": all_good,
            "explanation": explanation,
        },
        "implication": implication,
        "v6_changelog": {
            "regime_8state_filter": "BEAR_WEAK/BEAR_STRONG/CAPITULATION/TRANSITION_DOWN/SIDEWAYS apenas",
            "tori_trendline_gate": "proxy: breakdown de min(5d) OU rejeicao de max(5d)",
            "equity_stop_v6": "pause window 5 bars apos -10R hit (24h reset)",
            "funding_peak": "unavailable BTC 2018-2022, placeholder inserido",
        },
    }


# ──────────────────────────────────────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────────────────────────────────────

BEAR_PERIODS = [
    {"period_id": "bear_2018", "market": "BTCUSDT", "start": "2018-01-01", "end": "2018-12-31"},
    {"period_id": "bear_2022", "market": "BTCUSDT", "start": "2022-01-01", "end": "2022-12-31"},
]


def main():
    parser = argparse.ArgumentParser(description="Benchmark SHORT V6 em bears")
    parser.add_argument("--output", default=None)
    parser.add_argument("--meta-label", action="store_true",
                        help="Aplica meta-labeling 2-etapas (Lopez de Prado) como filtro adicional")
    parser.add_argument("--meta-threshold", type=float, default=0.55,
                        help="P(win) threshold pro meta-label (default 0.55)")
    args = parser.parse_args()

    print(f"[INFO] V6 components: regime={REGIME_AVAILABLE} funding={FUNDING_AVAILABLE} meta_label={META_LABEL_AVAILABLE}")
    if args.meta_label:
        print(f"[INFO] meta-label ENABLED with threshold P(win) >= {args.meta_threshold}")

    periods_out: List[Dict] = []
    for cfg in BEAR_PERIODS:
        print(
            f"[scan_v6] {cfg['period_id']} {cfg['market']} {cfg['start']}..{cfg['end']}"
        )
        scan = scan_period_v6(cfg["market"], cfg["start"], cfg["end"],
                              apply_meta_label=args.meta_label,
                              meta_threshold=args.meta_threshold)

        if scan["data_unavailable"]:
            print(f"  [WARN] dados indisponiveis para {cfg['period_id']}")
            periods_out.append(
                build_period_result_v6(
                    period_id=cfg["period_id"],
                    market=cfg["market"],
                    start=cfg["start"],
                    end=cfg["end"],
                    r_series=[],
                    v6_filters={},
                )
            )
            continue

        print(
            f"  signals={scan['n_signals']} "
            f"executed={len(scan['r_series'])} "
            f"regime_filtered={scan['n_regime_filtered']} "
            f"tori_filtered={scan['n_tori_filtered']} "
            f"equity_paused={scan['n_equity_paused']} "
            f"meta_filtered={scan.get('n_meta_filtered', 0)}"
        )
        print(f"  v6_filter_breakdown: {scan['v6_filters_applied']}")

        periods_out.append(
            build_period_result_v6(
                period_id=cfg["period_id"],
                market=cfg["market"],
                start=cfg["start"],
                end=cfg["end"],
                r_series=scan["r_series"],
                v6_filters=scan["v6_filters_applied"],
            )
        )

    result = build_result_skeleton_v6(periods_out)

    out_path = args.output or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "journal",
        "benchmark_short_v6_btc_results.json",
    )
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"\n[OK] saved: {out_path}")
    print(json.dumps(result["go_criterion"], indent=2, ensure_ascii=False))

    return 0


if __name__ == "__main__":
    sys.exit(main())
