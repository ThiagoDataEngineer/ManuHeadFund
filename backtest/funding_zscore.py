"""
funding_zscore.py -- Le funding_history/<SYMBOL>.jsonl e devolve z-score atual.

Z-score = (current - mean_baseline) / std_baseline.
Baseline default = ultimos 90 dias.

CLI:
    python funding_zscore.py BTCUSDT
    python funding_zscore.py BTCUSDT --baseline-days 180

Output: {"symbol":"BTCUSDT","current":0.0001,"mean":...,"std":...,"z":...,"n":N}

Usado pelo gate Test-FundingRateGate (PS) via:
    $z = python funding_zscore.py SYM --json | ConvertFrom-Json
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path
from typing import List, Optional

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DIR = ROOT / "journal" / "funding_history"
DEFAULT_BASELINE_DAYS = 90
MS_PER_DAY = 86_400_000


def load_funding(symbol: str, base_dir: Path = DEFAULT_DIR) -> List[dict]:
    path = base_dir / f"{symbol}.jsonl"
    if not path.exists():
        return []
    rows = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except Exception:
                continue
    rows.sort(key=lambda r: r.get("funding_time", 0))
    return rows


def compute_zscore(rows: List[dict], baseline_days: int = DEFAULT_BASELINE_DAYS) -> dict:
    if not rows:
        return {"current": None, "mean": None, "std": None, "z": None, "n": 0, "reason": "no_data"}
    last_ts = rows[-1].get("funding_time", 0)
    cutoff = last_ts - baseline_days * MS_PER_DAY
    baseline = [float(r["funding_rate"]) for r in rows if r.get("funding_time", 0) >= cutoff]
    if len(baseline) < 10:
        return {"current": None, "mean": None, "std": None, "z": None, "n": len(baseline), "reason": "insufficient_baseline"}
    current = float(rows[-1]["funding_rate"])
    mean = statistics.fmean(baseline)
    std = statistics.pstdev(baseline)
    z = 0.0 if std == 0 else (current - mean) / std
    return {
        "current": current,
        "mean": mean,
        "std": std,
        "z": z,
        "n": len(baseline),
        "baseline_days": baseline_days,
    }


def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(description="Funding z-score from Binance history.")
    p.add_argument("symbol", help="ex: BTCUSDT")
    p.add_argument("--baseline-days", type=int, default=DEFAULT_BASELINE_DAYS)
    p.add_argument("--dir", default=str(DEFAULT_DIR))
    p.add_argument("--json", action="store_true", help="emite JSON puro stdout")
    args = p.parse_args(argv)

    rows = load_funding(args.symbol, Path(args.dir))
    result = compute_zscore(rows, args.baseline_days)
    result["symbol"] = args.symbol

    if args.json:
        print(json.dumps(result))
    else:
        if result.get("z") is None:
            print(f"{args.symbol}: SEM Z-SCORE (reason={result.get('reason')})")
        else:
            print(f"{args.symbol}: z={result['z']:.2f} (current={result['current']:.5f} mean={result['mean']:.5f} std={result['std']:.5f} n={result['n']})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
