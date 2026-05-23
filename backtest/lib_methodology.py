"""lib_methodology.py -- Foundation TDD'd methodology lib for OOS validation.

5 core functions:
  - dedup_alphabetical(events) -> pick first market alphabetically per day
  - dedup_max_wss(events) -> pick highest-WSS market per day
  - cluster_portfolio_avg(events) -> per-day mean outcome (cluster as portfolio)
  - bootstrap_ci_by_day(events, n_iter=1000) -> 95% CI lift, resampling DAYS
  - effective_n(events) -> distinct days count

Used by all OOS validations. Single source of truth for "how do we measure".

Invariants enforced:
  - effective_n(events) <= len(events) sempre
  - dedup_*(events) subset of events
  - bootstrap CI: lower <= point_estimate <= upper
  - dedup deterministico: mesma entrada -> mesma saida
"""
from __future__ import annotations
import random
from collections import defaultdict
from typing import Any


def dedup_alphabetical(events: list[dict]) -> list[dict]:
    """Per day, return event with alphabetically-smallest market.

    Matches current vol_climax_scanner.ps1 cluster filter behavior
    (first-come first-serve happens to be alphabetical in iteration).
    """
    by_day = defaultdict(list)
    for e in events:
        day = e["ts"][:10]
        by_day[day].append(e)
    return [sorted(by_day[d], key=lambda e: e["market"])[0] for d in sorted(by_day)]


def dedup_max_wss(events: list[dict]) -> list[dict]:
    """Per day, return event with highest WSS score.

    Requires events to have 'wss' field. Fallback to alphabetical if tie.
    Use this to test: if scanner picked best-WSS instead of alphabetical,
    would OOS lift improve?
    """
    by_day = defaultdict(list)
    for e in events:
        day = e["ts"][:10]
        by_day[day].append(e)
    out = []
    for d in sorted(by_day):
        candidates = by_day[d]
        # Sort by (-wss, market) for deterministic tie-breaking
        candidates_sorted = sorted(candidates, key=lambda e: (-e.get("wss", 0), e["market"]))
        out.append(candidates_sorted[0])
    return out


def cluster_portfolio_avg(events: list[dict], outcome_field: str = "outcome") -> list[dict]:
    """Per day, return synthetic event with mean outcome of all firing markets.

    Represents "if I split capital across all firing markets equally on cluster days".
    Synthetic event preserves date and contains: outcome=mean, market='_PORTFOLIO_',
    cluster_size=N, contributing_markets=[...].
    """
    by_day = defaultdict(list)
    for e in events:
        day = e["ts"][:10]
        by_day[day].append(e)
    out = []
    for d in sorted(by_day):
        cluster = by_day[d]
        outcomes = [e[outcome_field] for e in cluster]
        mean_out = sum(outcomes) / len(outcomes)
        out.append({
            "ts": cluster[0]["ts"],
            "market": "_PORTFOLIO_",
            outcome_field: mean_out,
            "cluster_size": len(cluster),
            "contributing_markets": sorted(e["market"] for e in cluster),
            "phase": cluster[0].get("phase", ""),
        })
    return out


def effective_n(events: list[dict]) -> int:
    """Distinct days count (true independent N for clustered data)."""
    return len(set(e["ts"][:10] for e in events))


def bootstrap_ci_by_day(events: list[dict], baseline: list[dict],
                        outcome_field: str = "outcome",
                        thr_net: float = 1.6,
                        n_iter: int = 1000,
                        seed: int = 42) -> dict:
    """Bootstrap 95% CI of lift (signal hit% - baseline hit%), resampling BY DAY.

    Resample-by-day preserves cluster structure (correct CI for clustered data).
    Returns dict with:
        point_lift, ci_low, ci_high, point_n_days, point_baseline_n_days

    If insufficient data, returns None.
    """
    sig_days = sorted(set(e["ts"][:10] for e in events))
    if len(sig_days) < 3 or len(baseline) == 0:
        return None

    rng = random.Random(seed)

    def hit_rate(evs):
        n = len(evs)
        if n == 0: return None
        return sum(1 for e in evs if e[outcome_field] >= thr_net) / n * 100

    # Group events by day for sig
    sig_by_day = defaultdict(list)
    for e in events:
        sig_by_day[e["ts"][:10]].append(e)
    # Baseline already in "per-event" form
    base_by_day = defaultdict(list)
    for e in baseline:
        base_by_day[e["ts"][:10]].append(e)
    base_days = sorted(base_by_day.keys())

    # Point estimate: dedup_alphabetical (matches scanner)
    sig_dedup = dedup_alphabetical(events)
    base_dedup = dedup_alphabetical(baseline)
    point_sig = hit_rate(sig_dedup)
    point_base = hit_rate(base_dedup)
    if point_sig is None or point_base is None:
        return None
    point_lift = point_sig - point_base

    # Bootstrap: resample sig_days WITH REPLACEMENT, same for base_days
    lifts = []
    for _ in range(n_iter):
        # Resample signal days
        sampled_sig_days = [rng.choice(sig_days) for _ in range(len(sig_days))]
        sampled_sig_events = []
        for d in sampled_sig_days:
            picks = sig_by_day[d]
            sampled_sig_events.append(sorted(picks, key=lambda e: e["market"])[0])

        # Resample base days same size
        sampled_base_days = [rng.choice(base_days) for _ in range(len(base_days))]
        sampled_base_events = []
        for d in sampled_base_days:
            picks = base_by_day[d]
            sampled_base_events.append(sorted(picks, key=lambda e: e["market"])[0])

        sr = hit_rate(sampled_sig_events)
        br = hit_rate(sampled_base_events)
        if sr is not None and br is not None:
            lifts.append(sr - br)

    if not lifts:
        return None
    lifts.sort()
    ci_low = lifts[int(0.025 * len(lifts))]
    ci_high = lifts[int(0.975 * len(lifts))]

    return {
        "point_lift": round(point_lift, 2),
        "ci_low": round(ci_low, 2),
        "ci_high": round(ci_high, 2),
        "n_days_sig": len(sig_days),
        "n_days_base": len(base_days),
        "n_iter": n_iter,
    }
