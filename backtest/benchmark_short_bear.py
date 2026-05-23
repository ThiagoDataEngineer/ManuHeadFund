"""
benchmark_short_bear.py -- Valida SHORT em bears classicos (2018, 2022).

Hipotese: SHORT teve expectancy negativa no V2 baseline por VIES de regime
(periodo bull), nao falha estrutural. Testa em 2 bears (BTC -84% em 2018,
-78% em 2022) replicando logica V2 (KB-fix RSI/BB + equity stop -10R).

PUBLIC API:
  Funcoes puras (testaveis):
    simulate_short_pnl_r(entry, stop, target, candles) -> float
    calc_short_stop(entry, atr_value, multiplier=2.0) -> float
    calc_short_target(entry, stop, rr=5.0) -> float
    classify_trend(adx_value, ema9, ema21, pdi, ndi) -> "up"|"down"|"flat"
    is_long_fade_blocked_by_kbfix(trend_dir, rsi) -> bool
    is_short_signal_kbfix(trend_dir, price_touches_bb_upper) -> bool
    aggregate_metrics(r_series) -> dict
    classify_verdict(expectancy_r, dd_ratio) -> str
    build_period_result(...) -> dict
    build_result_skeleton(periods) -> dict
  Classes:
    EquityStopTracker -- pausa apos -10R desde peak, retoma quando DD<10R
  I/O:
    load_bear_candles(market, start, end) -> List[Dict]

CLI:
  python backtest/benchmark_short_bear.py
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Dict, List, Optional, Sequence

# Reuso de simulate_trade para evitar reimplementacao
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trade_simulator import simulate_trade  # noqa: E402
from metrics import calc_metrics  # noqa: E402


# ──────────────────────────────────────────────────────────────────────────────
# Funcoes puras
# ──────────────────────────────────────────────────────────────────────────────

def simulate_short_pnl_r(
    entry: float,
    stop: float,
    target: float,
    candles: List[Dict],
) -> float:
    """PnL em R de um SHORT (entry > target). Reusa simulate_trade."""
    result = simulate_trade(
        direction="SHORT",
        entry=entry,
        stop=stop,
        target=target,
        candles=candles,
    )
    return result.result_r


def calc_short_stop(entry: float, atr_value: float, multiplier: float = 2.0) -> float:
    """Stop SHORT = entry + mult * ATR (acima da entrada)."""
    return entry + multiplier * atr_value


def calc_short_target(entry: float, stop: float, rr: float = 5.0) -> float:
    """Target SHORT = entry - rr * risk (abaixo da entrada)."""
    risk = abs(entry - stop)
    return entry - rr * risk


def classify_trend(
    adx_value: float,
    ema9: float,
    ema21: float,
    pdi: float,
    ndi: float,
) -> str:
    """KB-fix trend: ADX>25 + EMA9/21 alinhado + DI confirma."""
    if adx_value <= 25.0:
        return "flat"
    if ema9 > ema21 and pdi > ndi:
        return "up"
    if ema9 < ema21 and ndi > pdi:
        return "down"
    return "flat"


def is_long_fade_blocked_by_kbfix(trend_dir: str, rsi: float) -> bool:
    """Em downtrend, RSI alto = continuation bear, NAO fade para LONG.

    Bloqueia LONG quando trend=down e RSI alto (>70).
    """
    return trend_dir == "down" and rsi > 70.0


def is_short_signal_kbfix(trend_dir: str, price_touches_bb_upper: bool) -> bool:
    """Em downtrend confirmado, touch em BB upper = SHORT (continuation, nao fade).

    Em uptrend, BB upper = walking-the-band, nao reverter -> nao gera SHORT aqui.
    """
    return trend_dir == "down" and price_touches_bb_upper


# ──────────────────────────────────────────────────────────────────────────────
# Equity stop tracker
# ──────────────────────────────────────────────────────────────────────────────

@dataclass
class EquityStopTracker:
    threshold_R: float = 10.0
    equity: float = 0.0
    peak: float = 0.0
    _paused: bool = False

    def on_trade_close(self, r: float) -> None:
        self.equity += r
        if self.equity > self.peak:
            self.peak = self.equity
        dd = self.peak - self.equity
        if dd >= self.threshold_R:
            self._paused = True
        else:
            self._paused = False

    def is_paused(self) -> bool:
        return self._paused

    def should_skip_signal(self) -> bool:
        return self._paused


# ──────────────────────────────────────────────────────────────────────────────
# Agregacao + veredito
# ──────────────────────────────────────────────────────────────────────────────

def aggregate_metrics(r_series: Sequence[float]) -> Dict:
    """Wrap metrics.calc_metrics em dict."""
    if not r_series:
        return {
            "trades": 0,
            "win_rate": 0.0,
            "expectancy_r": 0.0,
            "profit_factor": 0.0,
            "max_dd_r": 0.0,
        }
    m = calc_metrics(list(r_series))
    return {
        "trades": m.total_trades,
        "win_rate": m.win_rate / 100.0,
        "expectancy_r": m.expectancy_r,
        "profit_factor": m.profit_factor if m.profit_factor != float("inf") else 999.0,
        "max_dd_r": m.max_drawdown_r,
        "sharpe": m.sharpe_ratio,
        "sortino": m.sortino_ratio if m.sortino_ratio != float("inf") else 999.0,
    }


def classify_verdict(expectancy_r: float, dd_ratio: float) -> str:
    """Veredito SHORT em bear.

    SHORT_FUNCIONA_BEAR  : exp >= 0.5R e dd_ratio < 0.5
    SHORT_PROMISSOR      : exp >= 0.3R OU dd_ratio < 0.5
    SHORT_INSUFICIENTE   : caso contrario
    """
    if expectancy_r >= 0.5 and dd_ratio < 0.5:
        return "SHORT_FUNCIONA_BEAR"
    if expectancy_r >= 0.3 or dd_ratio < 0.5:
        return "SHORT_PROMISSOR"
    return "SHORT_INSUFICIENTE"


# ──────────────────────────────────────────────────────────────────────────────
# Output builders
# ──────────────────────────────────────────────────────────────────────────────

def build_period_result(
    period_id: str,
    market: str,
    start: str,
    end: str,
    r_series: Sequence[float],
    n_skipped: int = 0,
) -> Dict:
    metrics = aggregate_metrics(r_series)
    # dd_ratio = max_dd_r / abs(equity_final); guarda contra div/0
    final_equity = sum(r_series)
    dd_ratio = metrics["max_dd_r"] / abs(final_equity) if abs(final_equity) > 0 else 1.0
    verdict = classify_verdict(metrics["expectancy_r"], dd_ratio)
    return {
        "period_id": period_id,
        "market": market,
        "start": start,
        "end": end,
        "trades": metrics["trades"],
        "skipped_equity_stop": n_skipped,
        "metrics": {
            **metrics,
            "final_equity_r": final_equity,
            "dd_ratio": round(dd_ratio, 3),
        },
        "verdict": verdict,
    }


def build_result_skeleton(periods: List[Dict]) -> Dict:
    # Go criterion: expectancy >= +0.5R em ambos + dd_ratio < 0.5
    all_good = all(
        p["metrics"]["expectancy_r"] >= 0.5 and p["metrics"]["dd_ratio"] < 0.5
        for p in periods
    )
    if all_good:
        explanation = "SHORT mostra edge real em bears classicos: expectancy >= +0.5R e DD controlado em ambos os periodos."
        implication = "Liberar SHORT em regime bear confirmado (macro_bias=BEARISH ou drawdown desde ATH > -30%)."
    else:
        weak = [p["period_id"] for p in periods
                if p["metrics"]["expectancy_r"] < 0.5 or p["metrics"]["dd_ratio"] >= 0.5]
        explanation = f"Criterio falha em: {', '.join(weak)}. SHORT nao demonstra edge robusto."
        implication = "Manter sistema LONG-only. SHORT segue inviavel mesmo em regime ideal."

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "config": "baseline_v2_short_only",
        "periods": periods,
        "go_criterion": {
            "rule": "expectancy >= +0.5R em ambos bears + dd_ratio < 0.5",
            "passed": all_good,
            "explanation": explanation,
        },
        "implication": implication,
    }


# ──────────────────────────────────────────────────────────────────────────────
# Data loading
# ──────────────────────────────────────────────────────────────────────────────

def _load_from_db(market: str, period: str, start: str, end: str) -> List[Dict]:
    try:
        from db import Database
        env_ok = bool(os.environ.get("SUPABASE_URL")) and bool(os.environ.get("SUPABASE_KEY"))
        if not env_ok:
            return []
        db = Database()
        return db.get_candles(market, period, start, end)
    except Exception:
        return []


def _load_from_coinex(market: str, start: str, end: str) -> List[Dict]:
    import requests
    url = "https://api.coinex.com/v2/futures/kline"
    start_dt = datetime.fromisoformat(start).replace(tzinfo=timezone.utc)
    end_dt = datetime.fromisoformat(end).replace(tzinfo=timezone.utc)
    start_ms = int(start_dt.timestamp() * 1000)
    end_ms = int(end_dt.timestamp() * 1000)
    out: Dict[int, Dict] = {}
    while end_ms > start_ms:
        try:
            r = requests.get(url, params={
                "market": market, "period": "1day", "limit": 1000,
                "end_time": end_ms,
            }, timeout=15)
            r.raise_for_status()
            data = r.json().get("data") or []
        except Exception:
            break
        if not data:
            break
        oldest = end_ms
        for row in data:
            ts = int(row.get("created_at", 0))
            if ts < start_ms:
                continue
            out[ts] = {
                "ts": ts,
                "open": float(row.get("open", 0)),
                "high": float(row.get("high", 0)),
                "low": float(row.get("low", 0)),
                "close": float(row.get("close", 0)),
                "volume": float(row.get("volume", 0)),
            }
            if ts < oldest:
                oldest = ts
        if oldest <= start_ms or len(data) < 1000:
            break
        end_ms = oldest - 1
    return [out[k] for k in sorted(out.keys())]


def _load_from_bitstamp(market: str, start: str, end: str) -> List[Dict]:
    """Fallback Bitstamp BTCUSD para 2018 (antes de muitos USDT futures)."""
    if not market.upper().startswith("BTC"):
        return []
    import requests
    pair = "btcusd"
    url = f"https://www.bitstamp.net/api/v2/ohlc/{pair}/"
    start_dt = datetime.fromisoformat(start).replace(tzinfo=timezone.utc)
    end_dt = datetime.fromisoformat(end).replace(tzinfo=timezone.utc)
    start_ts = int(start_dt.timestamp())
    end_ts = int(end_dt.timestamp())
    out: Dict[int, Dict] = {}
    cur = start_ts
    step = 86400
    while cur < end_ts:
        try:
            r = requests.get(url, params={
                "step": step, "limit": 1000, "start": cur,
            }, timeout=15)
            r.raise_for_status()
            data = r.json().get("data", {}).get("ohlc", []) or []
        except Exception:
            break
        if not data:
            break
        newest = cur
        for row in data:
            ts = int(row.get("timestamp", 0))
            if ts > end_ts or ts < start_ts:
                continue
            out[ts] = {
                "ts": ts * 1000,
                "open": float(row.get("open", 0)),
                "high": float(row.get("high", 0)),
                "low": float(row.get("low", 0)),
                "close": float(row.get("close", 0)),
                "volume": float(row.get("volume", 0)),
            }
            if ts > newest:
                newest = ts
        if newest <= cur or len(data) < 1000:
            break
        cur = newest + 1
    return [out[k] for k in sorted(out.keys())]


def load_bear_candles(market: str, start: str, end: str) -> List[Dict]:
    """Tenta DB -> CoinEx -> Bitstamp (BTC apenas). Retorna [] se nada funcionar."""
    candles = _load_from_db(market, "1day", start, end)
    if len(candles) >= 300:
        return candles
    candles = _load_from_coinex(market, start, end)
    if len(candles) >= 300:
        return candles
    return _load_from_bitstamp(market, start, end)


# ──────────────────────────────────────────────────────────────────────────────
# Scan loop (signal generation + simulation)
# ──────────────────────────────────────────────────────────────────────────────

def _try_generate_signal(candles_window: List[Dict]):
    """Reusa signal_generator.generate_signal (LEITURA apenas)."""
    try:
        from signal_generator import generate_signal
        return generate_signal(candles_window)
    except Exception:
        return None


def _signal_to_short_setup(sig, atr_value: float) -> Optional[Dict]:
    """Converte SignalResult em setup SHORT se aplicavel."""
    if sig is None:
        return None
    # Aceita apenas SHORT (VENDA). LONG e filtrado fora.
    if getattr(sig, "signal", "") != "VENDA":
        return None
    entry = sig.entry_price
    stop = sig.stop_loss if sig.stop_loss > entry else calc_short_stop(entry, atr_value)
    target = sig.take_profit if sig.take_profit < entry else calc_short_target(entry, stop, 5.0)
    return {"entry": entry, "stop": stop, "target": target}


def scan_period(market: str, start: str, end: str, max_lookahead_bars: int = 40) -> Dict:
    """Roda scan SHORT-only com equity stop sobre o periodo."""
    candles = load_bear_candles(market, start, end)
    if not candles:
        return {"r_series": [], "n_skipped": 0, "n_signals": 0, "data_unavailable": True}

    MIN_WINDOW = 60
    tracker = EquityStopTracker(threshold_R=10.0)
    r_series: List[float] = []
    n_skipped = 0
    n_signals = 0

    i = MIN_WINDOW
    while i < len(candles) - 5:
        window = candles[max(0, i - 200):i + 1]
        sig = _try_generate_signal(window)
        if sig is None:
            i += 1
            continue
        n_signals_candidate = (sig.signal == "VENDA")
        if not n_signals_candidate:
            i += 1
            continue
        n_signals += 1
        if tracker.should_skip_signal():
            n_skipped += 1
            i += 1
            continue
        atr_val = getattr(sig, "atr", 0.0) or (candles[i]["high"] - candles[i]["low"])
        setup = _signal_to_short_setup(sig, atr_val)
        if setup is None:
            i += 1
            continue
        fwd = candles[i + 1:i + 1 + max_lookahead_bars]
        r = simulate_short_pnl_r(setup["entry"], setup["stop"], setup["target"], fwd)
        r_series.append(r)
        tracker.on_trade_close(r)
        # Avancar para alem do trade
        i += max(1, min(max_lookahead_bars, 5))
    return {"r_series": r_series, "n_skipped": n_skipped, "n_signals": n_signals, "data_unavailable": False}


# ──────────────────────────────────────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────────────────────────────────────

BEAR_PERIODS = [
    {"period_id": "bear_2018", "market": "BTCUSDT", "start": "2018-01-01", "end": "2018-12-31"},
    {"period_id": "bear_2022", "market": "BTCUSDT", "start": "2022-01-01", "end": "2022-12-31"},
]


def main():
    parser = argparse.ArgumentParser(description="Benchmark SHORT em bears")
    parser.add_argument("--output", default=None)
    args = parser.parse_args()

    periods_out: List[Dict] = []
    for cfg in BEAR_PERIODS:
        print(f"[scan] {cfg['period_id']} {cfg['market']} {cfg['start']}..{cfg['end']}")
        scan = scan_period(cfg["market"], cfg["start"], cfg["end"])
        if scan["data_unavailable"]:
            print(f"  [WARN] dados indisponiveis para {cfg['period_id']}")
            periods_out.append(build_period_result(
                period_id=cfg["period_id"], market=cfg["market"],
                start=cfg["start"], end=cfg["end"],
                r_series=[], n_skipped=0,
            ))
            continue
        print(f"  signals={scan['n_signals']} executed={len(scan['r_series'])} skipped={scan['n_skipped']}")
        periods_out.append(build_period_result(
            period_id=cfg["period_id"], market=cfg["market"],
            start=cfg["start"], end=cfg["end"],
            r_series=scan["r_series"], n_skipped=scan["n_skipped"],
        ))

    result = build_result_skeleton(periods_out)

    out_path = args.output or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "journal", "benchmark_short_bear_results.json"
    )
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    print(f"\n[OK] saved: {out_path}")
    print(json.dumps(result["go_criterion"], indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
