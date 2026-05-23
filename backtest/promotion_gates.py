"""
promotion_gates.py -- Python mirror de agents/lib_promotion_gates.ps1.

10 gates pre-promotion + pre-trade. Paridade exata com PS lib.
"""
from __future__ import annotations

import json
import os
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Union

ROOT = Path(__file__).resolve().parent.parent
SECTOR_MAP_PATH = ROOT / "journal" / "sector_map.json"
DEMOTE_HISTORY_PATH = ROOT / "journal" / "demote_history.jsonl"


def _result(passes: bool, reason: str, **kw) -> Dict:
    return {"passes": passes, "reason": reason, **kw}


def check_concentration_limit(current_count: int, max_count: int = 5) -> Dict:
    passes = current_count <= max_count
    return _result(passes, "ok" if passes else "concentration_limit_exceeded",
                   current=current_count, max=max_count)


def check_daily_loss_circuit(equity_today_pct: float, threshold_pct: float = -5.0) -> Dict:
    passes = equity_today_pct > threshold_pct
    return _result(passes, "ok" if passes else "daily_loss_circuit_triggered",
                   equity_pct=equity_today_pct, threshold=threshold_pct)


def get_sector_of(market: str, sector_map_path: Optional[str] = None) -> str:
    p = sector_map_path or str(SECTOR_MAP_PATH)
    if not os.path.exists(p): return "unknown"
    try:
        with open(p, "r", encoding="utf-8") as f:
            data = json.load(f)
        markets = data.get("markets", {})
        return markets.get(market, "unknown")
    except Exception:
        return "unknown"


def check_sector_concentration(market: str, current_tier_a_markets: List[str],
                              sector_map_path: Optional[str] = None,
                              max_per_sector: int = 2) -> Dict:
    sector = get_sector_of(market, sector_map_path)
    if sector == "unknown":
        return _result(True, "sector_unknown_pass", sector=sector, count=0, max=max_per_sector)
    count = sum(1 for m in current_tier_a_markets
                if get_sector_of(m, sector_map_path) == sector)
    passes = count < max_per_sector
    return _result(passes, "ok" if passes else "sector_concentration_exceeded",
                   sector=sector, count=count, max=max_per_sector)


def add_demote_event(market: str, reason: str = "manual",
                     demote_history_path: Optional[str] = None) -> None:
    p = demote_history_path or str(DEMOTE_HISTORY_PATH)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    event = {
        "market": market,
        "demoted_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "reason": reason,
    }
    with open(p, "a", encoding="utf-8") as f:
        f.write(json.dumps(event) + "\n")


def check_cooldown_post_demote(market: str,
                              demote_history_path: Optional[str] = None,
                              cooldown_days: int = 30) -> Dict:
    p = demote_history_path or str(DEMOTE_HISTORY_PATH)
    if not os.path.exists(p):
        return _result(True, "no_history")
    latest_ts = None
    with open(p, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                obj = json.loads(line)
                if obj.get("market") != market: continue
                ts = datetime.strptime(obj["demoted_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
                if latest_ts is None or ts > latest_ts: latest_ts = ts
            except Exception:
                continue
    if latest_ts is None:
        return _result(True, "never_demoted")
    days_since = (datetime.now(timezone.utc) - latest_ts).total_seconds() / 86400
    passes = days_since >= cooldown_days
    return _result(passes, "cooldown_expired" if passes else "cooldown_active",
                   days_since=round(days_since, 1),
                   cooldown_days=cooldown_days,
                   latest_demote=latest_ts.strftime("%Y-%m-%d"))


def check_min_volume_gate(volume_usd: float, min_volume_usd: float = 500000) -> Dict:
    passes = volume_usd >= min_volume_usd
    return _result(passes, "ok" if passes else "volume_below_minimum",
                   volume=volume_usd, min=min_volume_usd)


def check_phase_boundary_safety(phase_changed_at: Optional[Union[datetime, str]],
                               safety_days: int = 7) -> Dict:
    if phase_changed_at is None:
        return _result(True, "no_phase_history")
    if isinstance(phase_changed_at, str):
        phase_changed_at = datetime.fromisoformat(phase_changed_at.replace("Z", "+00:00"))
    if phase_changed_at.tzinfo is None:
        phase_changed_at = phase_changed_at.replace(tzinfo=timezone.utc)
    days_since = (datetime.now(timezone.utc) - phase_changed_at).total_seconds() / 86400
    passes = days_since >= safety_days
    return _result(passes, "safety_period_passed" if passes else "phase_boundary_active",
                   days_since=round(days_since, 1), safety_days=safety_days)


def check_time_of_week_gate(dt: Optional[datetime] = None,
                           direction: str = "long",
                           blocked_days: Optional[List[int]] = None,
                           blocked_hour_start: int = 14,
                           blocked_hour_end: int = 23) -> Dict:
    dt = dt or datetime.now()
    blocked_days = blocked_days or [3]  # Thursday in Python weekday (Mon=0..Sun=6)
    dow = dt.weekday()
    hr = dt.hour
    is_blocked_day = dow in blocked_days
    is_blocked_hour = blocked_hour_start <= hr <= blocked_hour_end
    blocked = is_blocked_day and is_blocked_hour and direction == "long"
    return _result(not blocked, "ok" if not blocked else "time_of_week_blocked",
                   dow=dt.strftime("%A"), hour=hr, direction=direction)


def check_slippage_budget(volume_usd_24h: float, position_size_usd: float,
                         min_ratio: float = 100.0) -> Dict:
    if position_size_usd <= 0:
        return _result(False, "invalid_size", ratio=0)
    ratio = volume_usd_24h / position_size_usd
    passes = ratio >= min_ratio
    return _result(passes, "ok" if passes else "slippage_too_high",
                   ratio=round(ratio, 1),
                   min_ratio=min_ratio,
                   estimated_slippage_pct=round(100 / max(ratio, 1), 3))


def check_cross_asset_correlation(market: str,
                                 current_long_markets: List[str],
                                 sector_map_path: Optional[str] = None,
                                 correlation_threshold: float = 0.8) -> Dict:
    sector = get_sector_of(market, sector_map_path)
    if sector == "unknown":
        return _result(True, "sector_unknown")
    same_sector = sum(1 for m in current_long_markets
                      if get_sector_of(m, sector_map_path) == sector)
    passes = same_sector == 0
    return _result(passes, "ok" if passes else "correlated_position_active",
                   sector=sector, same_sector_long_count=same_sector,
                   threshold=correlation_threshold, note="v1_proxy_sector_based")


def check_funding_rate_gate(funding_z_score: float, direction: str = "long",
                           max_z_for_long: float = 2.0,
                           max_z_for_short: float = -2.0) -> Dict:
    if direction == "long":
        passes = funding_z_score < max_z_for_long
        reason = "ok" if passes else "funding_overheated_long"
    else:
        passes = funding_z_score > max_z_for_short
        reason = "ok" if passes else "funding_overcold_short"
    return _result(passes, reason,
                   funding_z=funding_z_score, direction=direction,
                   note="requires_binance_funding_history_baseline")


def invoke_all_gates(market: str,
                    volume_usd: float = 0,
                    current_tier_a_count: int = 0,
                    current_tier_a_markets: Optional[List[str]] = None,
                    equity_today_pct: float = 0,
                    phase_changed_at: Optional[Union[datetime, str]] = None,
                    funding_z: Optional[float] = None,
                    position_size_usd: float = 100,
                    max_tier_a: int = 5,
                    max_per_sector: int = 2,
                    cooldown_days: int = 30,
                    safety_days: int = 7,
                    min_volume_usd: float = 500000,
                    daily_loss_threshold: float = -5.0) -> Dict:
    current_tier_a_markets = current_tier_a_markets or []
    gates = {
        "concentration": check_concentration_limit(current_tier_a_count, max_tier_a),
        "daily_loss": check_daily_loss_circuit(equity_today_pct, daily_loss_threshold),
        "sector": check_sector_concentration(market, current_tier_a_markets, max_per_sector=max_per_sector),
        "cooldown": check_cooldown_post_demote(market, cooldown_days=cooldown_days),
        "min_volume": check_min_volume_gate(volume_usd, min_volume_usd),
        "phase_boundary": check_phase_boundary_safety(phase_changed_at, safety_days),
        "time_of_week": check_time_of_week_gate(direction="long"),
        "slippage": check_slippage_budget(volume_usd, position_size_usd),
        "correlation": check_cross_asset_correlation(market, current_tier_a_markets),
    }
    if funding_z is not None:
        gates["funding"] = check_funding_rate_gate(funding_z, direction="long")
    else:
        # Tenta carregar do cache offline (binance funding collector).
        # Sem cache: passa silenciosamente com reason=no_baseline.
        try:
            from funding_zscore import load_funding, compute_zscore  # type: ignore
            rows = load_funding(market)
            zr = compute_zscore(rows)
            if zr.get("z") is not None:
                gates["funding"] = check_funding_rate_gate(float(zr["z"]), direction="long")
            else:
                gates["funding"] = {"passes": True, "reason": "no_baseline", "z": None}
        except Exception:
            gates["funding"] = {"passes": True, "reason": "no_baseline", "z": None}
    all_pass = all(g["passes"] for g in gates.values())
    blocked_by = [k for k, g in gates.items() if not g["passes"]]
    return {
        "market": market,
        "all_pass": all_pass,
        "blocked_by": blocked_by,
        "gates": gates,
    }
