"""
dump_transition_up_trades.py — Dumpa trades TRANSITION_UP LONG (já reclassificados 8-state)
para journal/transition_up_trades_dump.json. Usado pelo contador PowerShell.
"""
import argparse
import json
import os
from typing import Dict, List

from regime_8state_classifier import reclassify_trades_8state


def _load_trades(market: str, start: str, end: str) -> List[Dict]:
    from db import Database
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    out, offset, page = [], 0, 1000
    while True:
        params = (f"select=*&market=eq.{market}"
                  f"&entry_ts=gte.{start}&entry_ts=lte.{end}"
                  f"&order=entry_ts.asc&limit={page}&offset={offset}")
        rows = db._get("backtest_trades", params)
        out.extend(rows)
        if len(rows) < page:
            break
        offset += page
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--market", default="BTCUSD")
    parser.add_argument("--period", default="1hour")
    parser.add_argument("--start",  default="2014-01-01")
    parser.add_argument("--end",    default="2025-05-01")
    parser.add_argument("--output", default=None)
    args = parser.parse_args()

    print(f"Carregando trades {args.market}...")
    trades = _load_trades(args.market, args.start, args.end)
    print(f"  -> {len(trades)} trades")

    from db import Database
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)
    print(f"Carregando candles {args.period}...")
    candles = db.get_candles(args.market, args.period, args.start, args.end)
    print(f"  -> {len(candles)} candles")

    print("Reclassificando 8-state...")
    enriched = reclassify_trades_8state(trades, candles)
    transition_up = [t for t in enriched
                     if t.get("regime") == "TRANSITION_UP" and t.get("direction") == "LONG"]
    print(f"  -> {len(transition_up)} trades TRANSITION_UP LONG")

    # Slim: só os campos necessários para o contador PowerShell
    slim = [{
        "entry_ts": t.get("entry_ts"),
        "regime":   t.get("regime"),
        "direction": t.get("direction"),
        "result_r": float(t.get("result_r", 0.0)),
    } for t in transition_up]

    out_path = args.output
    if out_path is None:
        here = os.path.dirname(os.path.abspath(__file__))
        journal = os.path.abspath(os.path.join(here, "..", "journal"))
        os.makedirs(journal, exist_ok=True)
        out_path = os.path.join(journal, "transition_up_trades_dump.json")

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(slim, f, indent=2)
    print(f"Saved: {out_path}")


if __name__ == "__main__":
    main()
