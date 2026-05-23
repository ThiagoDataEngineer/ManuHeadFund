"""
retroactive_30d_scan.py - Simula "se rodassemos NOSSO sistema 30 dias atras nestes candidatos,
o que teria acontecido?".

Pipeline:
  1. Para cada candidato (gainer ou loser), busca candles CoinEx 1h
  2. Encontra a barra que era "ha 30 dias"
  3. Roda signal_generator (v1) + regime_8state nesse bar
  4. Classifica outcome: TARGET_HIT, STOP_HIT ou OPEN baseado nos bars seguintes
  5. Reporta: teria entrado? que direcao? bateu target ou stop?

CLI:
    python backtest/retroactive_30d_scan.py
"""
import argparse
import json
import os
import time
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Optional

from signal_generator import generate_signal, SMA200_PERIOD, MIN_CANDLES, _regime_for_window
from regime_8state_classifier import precompute_indicators, classify_8state_fast


COINEX_KLINE_URL = "https://api.coinex.com/v2/futures/kline"
COINEX_SPOT_KLINE_URL = "https://api.coinex.com/v2/spot/kline"
RATE_LIMIT_SLEEP = 0.4


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

def find_bar_at_days_ago(candles: List[Dict], days: int, period_hours: int = 1) -> Optional[int]:
    """Retorna idx do candle que era ha `days` dias atras. None se nao tem hist suficiente."""
    bars_back = days * (24 // period_hours)
    n = len(candles)
    needed = bars_back + SMA200_PERIOD
    if n < needed:
        return None
    return n - 1 - bars_back


def simulate_signal_at_bar(candles: List[Dict], idx: int) -> Dict:
    """Roda generate_signal + classify_8state_fast no bar idx (usa apenas candles[0..idx])."""
    window = candles[max(0, idx - SMA200_PERIOD + 1):idx + 1]
    if len(window) < MIN_CANDLES:
        return {
            "signal":         "NEUTRO",
            "score":          0.0,
            "is_actionable":  False,
            "regime_8state":  "UNKNOWN",
            "entry_price":    0.0,
            "stop_loss":      0.0,
            "take_profit":    0.0,
        }

    # Precompute regime so com a janela ate idx (zero lookahead)
    pre = precompute_indicators(candles[:idx + 1])
    regime8 = classify_8state_fast(pre, idx)

    # signal_generator v1
    result = generate_signal(window)

    return {
        "signal":         result.signal,
        "score":          float(result.score),
        "is_actionable":  bool(result.is_actionable),
        "regime_8state":  regime8,
        "entry_price":    float(result.entry_price),
        "stop_loss":      float(result.stop_loss),
        "take_profit":    float(result.take_profit),
        "rr_ratio":       float(result.rr_ratio),
    }


def classify_outcome_so_far(
    direction: str, entry: float, stop: float, target: float, forward_candles: List[Dict],
) -> Dict:
    """Verifica nos forward_candles se stop ou target foi atingido (intra-bar via high/low).
    Retorna status (TARGET_HIT/STOP_HIT/OPEN) + bars_held + result_r aproximado."""
    risk = abs(entry - stop)
    for i, c in enumerate(forward_candles):
        high = float(c["high"])
        low  = float(c["low"])
        if direction == "LONG":
            if low <= stop:
                return {"status": "STOP_HIT", "bars_held": i + 1, "exit_price": stop, "result_r": -1.0}
            if high >= target:
                reward = abs(target - entry)
                return {"status": "TARGET_HIT", "bars_held": i + 1, "exit_price": target,
                        "result_r": reward / risk if risk > 0 else 0.0}
        else:  # SHORT
            if high >= stop:
                return {"status": "STOP_HIT", "bars_held": i + 1, "exit_price": stop, "result_r": -1.0}
            if low <= target:
                reward = abs(entry - target)
                return {"status": "TARGET_HIT", "bars_held": i + 1, "exit_price": target,
                        "result_r": reward / risk if risk > 0 else 0.0}
    # Aberta
    if forward_candles:
        last = forward_candles[-1]
        last_close = float(last["close"])
        if direction == "LONG":
            mtm_r = (last_close - entry) / risk if risk > 0 else 0.0
        else:
            mtm_r = (entry - last_close) / risk if risk > 0 else 0.0
        return {"status": "OPEN", "bars_held": len(forward_candles),
                "exit_price": last_close, "result_r": round(mtm_r, 4)}
    return {"status": "OPEN", "bars_held": 0, "exit_price": entry, "result_r": 0.0}


# ----------------------------------------------------------------------------
# Build report
# ----------------------------------------------------------------------------

def _direction_from_signal(signal: str) -> str:
    return "LONG" if signal == "COMPRA" else ("SHORT" if signal == "VENDA" else "NEUTRO")


def build_retroactive_report(
    candles_map: Dict[str, List[Dict]],
    days_ago: int = 30,
    period_hours: int = 1,
) -> Dict:
    results = []
    for symbol, candles in candles_map.items():
        idx = find_bar_at_days_ago(candles, days=days_ago, period_hours=period_hours)
        if idx is None:
            results.append({
                "symbol":         symbol,
                "bar_ts":         None,
                "regime_8state":  "INSUFFICIENT_HISTORY",
                "signal":         "NEUTRO",
                "score":          0.0,
                "is_actionable":  False,
                "verdict":        "NO_DATA",
                "outcome":        {"status": "N/A", "bars_held": 0, "exit_price": 0.0, "result_r": 0.0},
            })
            continue

        sig = simulate_signal_at_bar(candles, idx)
        direction = _direction_from_signal(sig["signal"])

        if sig["is_actionable"]:
            verdict = "WOULD_HAVE_ENTERED"
            forward = candles[idx + 1:]  # bars apos a entrada
            outcome = classify_outcome_so_far(
                direction=direction,
                entry=sig["entry_price"], stop=sig["stop_loss"],
                target=sig["take_profit"], forward_candles=forward,
            )
        else:
            verdict = "NO_ENTRY"
            outcome = {"status": "N/A", "bars_held": 0, "exit_price": 0.0, "result_r": 0.0}

        results.append({
            "symbol":         symbol,
            "bar_ts":         candles[idx].get("ts"),
            "regime_8state":  sig["regime_8state"],
            "signal":         sig["signal"],
            "direction":      direction,
            "score":          sig["score"],
            "is_actionable":  sig["is_actionable"],
            "entry_price":    round(sig["entry_price"], 6),
            "stop_loss":      round(sig["stop_loss"], 6),
            "take_profit":    round(sig["take_profit"], 6),
            "rr_ratio":       round(sig.get("rr_ratio", 0.0), 2),
            "verdict":        verdict,
            "outcome":        outcome,
        })

    actionable = [r for r in results if r["is_actionable"]]
    target_hits = [r for r in actionable if r["outcome"]["status"] == "TARGET_HIT"]
    stop_hits   = [r for r in actionable if r["outcome"]["status"] == "STOP_HIT"]
    open_trades = [r for r in actionable if r["outcome"]["status"] == "OPEN"]

    return {
        "timestamp_utc": datetime.now(tz=timezone.utc).isoformat(),
        "days_ago":      days_ago,
        "results":       results,
        "summary": {
            "total_scanned":     len(results),
            "would_have_entered": len(actionable),
            "target_hits":        len(target_hits),
            "stop_hits":          len(stop_hits),
            "still_open":         len(open_trades),
        },
    }


# ----------------------------------------------------------------------------
# Fetcher (CoinEx kline)
# ----------------------------------------------------------------------------

def _fetch_coinex_klines(market: str, period: str = "1hour", limit: int = 1000,
                        use_futures: bool = True) -> List[Dict]:
    """Pega ate `limit` candles mais recentes do CoinEx."""
    import requests
    url = COINEX_KLINE_URL if use_futures else COINEX_SPOT_KLINE_URL
    params = {"market": market, "period": period, "limit": min(limit, 1000)}
    try:
        r = requests.get(url, params=params, timeout=15)
        if r.status_code != 200:
            return []
        data = r.json().get("data", []) or []
        # Converte para schema interno
        out = []
        for d in data:
            ts_ms = int(d.get("created_at") or 0)
            ts_iso = datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc).isoformat()
            out.append({
                "ts":     ts_iso,
                "open":   float(d.get("open", 0)),
                "high":   float(d.get("high", 0)),
                "low":    float(d.get("low", 0)),
                "close":  float(d.get("close", 0)),
                "volume": float(d.get("volume", 0)),
            })
        return sorted(out, key=lambda c: c["ts"])
    except Exception as e:
        print(f"  erro fetch {market}: {e}")
        return []


def fetch_history_for_symbol(symbol: str, period: str = "1hour", bars: int = 1000) -> List[Dict]:
    """Tenta futures primeiro, depois spot. Retorna candles ordenados."""
    market = f"{symbol}USDT"
    out = _fetch_coinex_klines(market, period=period, limit=bars, use_futures=True)
    if not out:
        out = _fetch_coinex_klines(market, period=period, limit=bars, use_futures=False)
    return out


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------

def _load_scan_results() -> List[Dict]:
    """Carrega journal/scan_top_movers.json (gainers + losers)."""
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.abspath(os.path.join(here, "..", "journal", "scan_top_movers.json"))
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    out = []
    for g in data.get("top_gainers", []):
        out.append({"symbol": g["symbol"], "side": "gainer",
                    "coinex": g.get("coinex_availability")})
    for l in data.get("top_losers", []):
        out.append({"symbol": l["symbol"], "side": "loser",
                    "coinex": l.get("coinex_availability")})
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--days-ago", type=int, default=30)
    parser.add_argument("--period",   default="1hour")
    parser.add_argument("--bars",     type=int, default=1000,
                        help="Quantos candles buscar (default 1000 = ~41 dias 1h)")
    parser.add_argument("--output",   default=None)
    args = parser.parse_args()

    print(f"Carregando candidatos do scan_top_movers.json...")
    candidates = _load_scan_results()
    print(f"  -> {len(candidates)} candidatos (gainers + losers)")

    candles_map: Dict[str, List[Dict]] = {}
    for cand in candidates:
        sym = cand["symbol"]
        print(f"  fetch {sym}USDT ({cand['side']}, {cand['coinex']})...", end=" ", flush=True)
        candles = fetch_history_for_symbol(sym, period=args.period, bars=args.bars)
        print(f"{len(candles)} candles")
        if candles:
            candles_map[sym] = candles
        time.sleep(RATE_LIMIT_SLEEP)

    report = build_retroactive_report(
        candles_map, days_ago=args.days_ago, period_hours=1 if args.period == "1hour" else 4,
    )

    # Anota side
    side_map = {c["symbol"]: c["side"] for c in candidates}
    for r in report["results"]:
        r["side"] = side_map.get(r["symbol"], "?")

    out_path = args.output
    if out_path is None:
        here = os.path.dirname(os.path.abspath(__file__))
        journal = os.path.abspath(os.path.join(here, "..", "journal"))
        os.makedirs(journal, exist_ok=True)
        out_path = os.path.join(journal, "retroactive_30d_scan.json")

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print()
    print("=" * 110)
    print(f"RETROACTIVE SCAN - se rodassemos nosso sistema {args.days_ago} dias atras:")
    print("=" * 110)
    print(f"{'SIDE':<8}{'SYM':<10}{'SIGNAL':<10}{'SCORE':>7}{'REGIME':>16}{'ACTION':>10}"
          f"{'ENTRY':>11}{'STOP':>11}{'TARGET':>11}{'OUTCOME':>14}{'R':>9}")
    print("-" * 110)
    for r in report["results"]:
        side = r.get("side", "?")
        out = r["outcome"]
        action = "YES" if r["is_actionable"] else "no"
        rr = out.get("result_r", 0.0) if r["is_actionable"] else None
        rr_str = f"{rr:+.2f}" if rr is not None else "-"
        print(f"{side:<8}{r['symbol']:<10}{r['signal']:<10}{r['score']:>7.1f}"
              f"{r['regime_8state']:>16}{action:>10}"
              f"{r['entry_price']:>11.4f}{r['stop_loss']:>11.4f}{r['take_profit']:>11.4f}"
              f"{out['status']:>14}{rr_str:>9}")

    s = report["summary"]
    print()
    print(f"Resumo: {s['total_scanned']} candidatos | {s['would_have_entered']} teriam entrado | "
          f"{s['target_hits']} TARGET_HIT | {s['stop_hits']} STOP_HIT | {s['still_open']} ainda abertos")
    print(f"\nSaved: {out_path}")


if __name__ == "__main__":
    main()
