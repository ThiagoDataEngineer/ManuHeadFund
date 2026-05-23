"""
walkforward_halving.py -- Halving-aware Walk-Forward splits para BTC.

Permite split de janelas que CRUZAM datas de halving (proxy de regime change).
Cada window inclui dado pré + pós halving, e adiciona métrica `cross_halving_pf`.

Halving dates (ground truth):
- 2012-11-28
- 2016-07-09
- 2020-05-11
- 2024-04-19
- (2028 projeção, ignorada por enquanto)

Uso:
    from walkforward_halving import HalvingSplitter, build_halving_windows
    splitter = HalvingSplitter(halving_dates=["2012-11-28", "2016-07-09",
                                              "2020-05-11", "2024-04-19"])
    windows = splitter.generate(start="2014-01-01", end="2025-12-31",
                                pre_months=6, post_months=12)

Integração com benchmark_walkforward_14y.run_walkforward via flag
--halving-dates (ver halving_walkforward_runner.py).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass, field, asdict
from datetime import date
from typing import Dict, List, Optional, Sequence

import numpy as np


DEFAULT_HALVING_DATES = [
    "2012-11-28",
    "2016-07-09",
    "2020-05-11",
    "2024-04-19",
]


def _parse_date(s: str) -> date:
    return date.fromisoformat(s[:10])


def _add_months(d: date, months: int) -> date:
    total = d.year * 12 + (d.month - 1) + months
    year, month = divmod(total, 12)
    month += 1
    last_day = [31, 29 if (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) else 28,
                31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
    day = min(d.day, last_day)
    return date(year, month, day)


@dataclass
class HalvingWindow:
    """Janela centrada em um halving, com pré/post split."""
    halving_id: int
    halving_date: str
    window_start: str
    window_end: str
    pre_start: str
    pre_end: str
    post_start: str
    post_end: str

    def to_dict(self) -> Dict:
        return asdict(self)


@dataclass
class HalvingSplitter:
    """Gera janelas WF que cruzam halvings de BTC."""
    halving_dates: List[str] = field(default_factory=lambda: list(DEFAULT_HALVING_DATES))

    def __post_init__(self):
        # Valida e ordena
        parsed = []
        for h in self.halving_dates:
            try:
                parsed.append(_parse_date(h))
            except Exception as e:
                raise ValueError(f"Halving date invalido: {h}: {e}")
        parsed.sort()
        self.halving_dates = [d.isoformat() for d in parsed]

    def generate(self, start: str, end: str,
                 pre_months: int = 6, post_months: int = 12) -> List[HalvingWindow]:
        """
        Para cada halving dentro [start, end], gera janela centrada
        [halving - pre_months, halving + post_months].

        Janelas overlap são preservadas (intencional: cada halving = window separada).
        """
        if pre_months < 0 or post_months < 0:
            raise ValueError(f"pre/post_months devem ser >= 0, got {pre_months}/{post_months}")
        if pre_months == 0 and post_months == 0:
            raise ValueError("pre_months + post_months deve ser > 0")

        sd = _parse_date(start)
        ed = _parse_date(end)
        out: List[HalvingWindow] = []

        for i, h_str in enumerate(self.halving_dates):
            h = _parse_date(h_str)
            if h < sd or h > ed:
                continue

            ws = _add_months(h, -pre_months)
            we = _add_months(h, post_months)

            # Clampa nas bordas do range global
            ws = max(ws, sd)
            we = min(we, ed)

            out.append(HalvingWindow(
                halving_id=i,
                halving_date=h.isoformat(),
                window_start=ws.isoformat(),
                window_end=we.isoformat(),
                pre_start=ws.isoformat(),
                pre_end=h.isoformat(),
                post_start=h.isoformat(),
                post_end=we.isoformat(),
            ))
        return out


def split_trades_by_halving(trades: Sequence[Dict], window: HalvingWindow) -> Dict[str, List[Dict]]:
    """
    Divide trades de uma janela em pre/post halving.
    Espera trades com campo `ts` (datetime ou ISO string).
    """
    h = _parse_date(window.halving_date)
    pre, post = [], []
    for t in trades:
        ts = t.get("ts")
        if isinstance(ts, str):
            try:
                ts = _parse_date(ts)
            except Exception:
                continue
        if not isinstance(ts, date):
            continue
        if ts < h:
            pre.append(t)
        else:
            post.append(t)
    return {"pre": pre, "post": post}


def _compute_pf(trades_r: Sequence[float]) -> float:
    arr = np.asarray(trades_r, dtype=float)
    if arr.size == 0:
        return 0.0
    gp = float(arr[arr > 0].sum())
    gl = float(-arr[arr < 0].sum())
    if gl == 0:
        return float(gp) if gp > 0 else 0.0
    return float(gp / gl)


def compute_cross_halving_pf(pre_trades_r: Sequence[float],
                             post_trades_r: Sequence[float]) -> Dict:
    """
    Computa PF pre, PF post, e ratio (post/pre).
    Ratio > 1.0 => edge se manteve ou MELHOROU pos-halving.
    Ratio < 1.0 => edge degradou (regime change quebrou estrategia).
    """
    pf_pre = _compute_pf(pre_trades_r)
    pf_post = _compute_pf(post_trades_r)
    if pf_pre == 0:
        ratio = float("inf") if pf_post > 0 else 0.0
    else:
        ratio = pf_post / pf_pre

    return {
        "pf_pre":  round(pf_pre, 4),
        "pf_post": round(pf_post, 4),
        "ratio":   round(ratio, 4) if ratio != float("inf") else None,
        "n_pre":   len(pre_trades_r),
        "n_post":  len(post_trades_r),
        "verdict": _verdict(pf_pre, pf_post),
    }


def _verdict(pf_pre: float, pf_post: float) -> str:
    if pf_pre == 0 and pf_post == 0:
        return "NO_DATA"
    if pf_pre == 0:
        return "EMERGED_POST" if pf_post > 1 else "EMERGED_WEAK"
    if pf_post == 0:
        return "DIED_POST"
    if pf_post >= pf_pre * 0.9:
        return "EDGE_PERSISTED"
    if pf_post >= pf_pre * 0.5:
        return "EDGE_DEGRADED"
    return "EDGE_BROKEN"


def build_halving_windows(start: str, end: str,
                          halving_dates: Optional[Sequence[str]] = None,
                          pre_months: int = 6,
                          post_months: int = 12) -> List[Dict]:
    """Helper top-level para gerar lista de dicts compatíveis com benchmark_walkforward."""
    if halving_dates is None:
        halving_dates = DEFAULT_HALVING_DATES
    splitter = HalvingSplitter(halving_dates=list(halving_dates))
    windows = splitter.generate(start, end, pre_months=pre_months, post_months=post_months)
    return [w.to_dict() for w in windows]


def parse_halving_arg(arg: str) -> List[str]:
    """Parse `--halving-dates 2012-11-28,2016-07-09,2020-05-11,2024-04-19`."""
    if not arg:
        return list(DEFAULT_HALVING_DATES)
    parts = [p.strip() for p in arg.split(",") if p.strip()]
    # Validate
    for p in parts:
        _parse_date(p)
    return parts


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Halving-aware WF window generator")
    parser.add_argument("--start", default="2014-01-01")
    parser.add_argument("--end", default="2025-12-31")
    parser.add_argument("--halving-dates", default=",".join(DEFAULT_HALVING_DATES),
                        help="Comma-separated ISO dates")
    parser.add_argument("--pre-months", type=int, default=6)
    parser.add_argument("--post-months", type=int, default=12)
    parser.add_argument("--output", default=os.path.join("journal", "halving_windows.json"))
    args = parser.parse_args(argv)

    dates = parse_halving_arg(args.halving_dates)
    windows = build_halving_windows(args.start, args.end, dates,
                                    pre_months=args.pre_months,
                                    post_months=args.post_months)

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump({
            "halving_dates": dates,
            "start": args.start,
            "end": args.end,
            "pre_months": args.pre_months,
            "post_months": args.post_months,
            "n_windows": len(windows),
            "windows": windows,
        }, f, indent=2)

    sys.stdout.write(f"[HalvingWF] {len(windows)} windows -> {args.output}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
