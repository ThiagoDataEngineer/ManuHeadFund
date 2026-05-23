"""
quant_scanner.py — Scanner universal quant-priorizado.

Substitui scanner heurístico (volume*log(spread)/etc) por:
1. Per-asset whitelist (cross_asset validated) como source of truth
2. Ranking por Sharpe esperado * |distância para target| (urgência)
3. Score quant = expected_sharpe × momentum_factor

Output: lista priorizada de candidatos para cascade V6 com priors estatísticos.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Dict, List

ROOT_DIR = Path(__file__).resolve().parent.parent
JOURNAL_DIR = ROOT_DIR / "journal"


def load_whitelist(path: Path = None) -> Dict:
    p = path or (JOURNAL_DIR / "per_asset_whitelist_2026_05_17.json")
    if not p.exists():
        return {"TIER_A_LIVE": [], "TIER_B_PAPER": [], "TIER_C_SKIP": []}
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)


def quant_priority(
    market: str,
    current_price: float,
    atr: float,
    pct_change_24h: float,
    whitelist: Dict,
    mode: str = "LIVE",
) -> Dict:
    """
    Calcula prioridade quant para um par.

    Args:
        mode: "LIVE" só usa TIER A; "PAPER" usa A+B; "ALL" qualquer tier
    Returns:
        {qualified, tier, expected_sharpe, priority_score, setup, ...}
    """
    pools = ["TIER_A_LIVE"]
    if mode in ("PAPER", "ALL"): pools.append("TIER_B_PAPER")
    if mode == "ALL":            pools.append("TIER_C_SKIP")

    found = None
    found_tier = None
    for pool_name in pools:
        for e in whitelist.get(pool_name, []):
            if e["market"] == market:
                found = e
                found_tier = pool_name.replace("TIER_", "").split("_")[0]
                break
        if found: break

    if not found:
        return {"qualified": False, "reason": "not_in_whitelist", "market": market}

    # Setup calculation usando best params
    stop_atr_mult = found["stop_atr"]
    target_atr_mult = found["target_atr"]
    if atr <= 0 or current_price <= 0:
        return {"qualified": False, "reason": "invalid_price_atr",
                 "market": market, "tier": found_tier}

    stop_price = current_price - stop_atr_mult * atr
    target_price = current_price + target_atr_mult * atr
    stop_pct = (stop_atr_mult * atr) / current_price
    target_pct = (target_atr_mult * atr) / current_price

    # Quant priority score: Sharpe expected × momentum × (1 - tier_penalty)
    tier_weight = {"A": 1.0, "B": 0.5, "C": 0.1}.get(found_tier, 0.1)
    momentum_factor = 1.0 + min(max(pct_change_24h, -10), 10) / 100.0  # ±10% cap
    priority_score = found["sharpe"] * momentum_factor * tier_weight

    return {
        "qualified": True,
        "market": market,
        "tier": found_tier,
        "expected_sharpe": found["sharpe"],
        "expected_win_rate": found["win_rate_pct"],
        "expected_mean_r": found["mean_r"],
        "priority_score": round(priority_score, 4),
        "setup": {
            "entry": current_price,
            "stop": round(stop_price, 8),
            "target": round(target_price, 8),
            "stop_pct": round(stop_pct * 100, 2),
            "target_pct": round(target_pct * 100, 2),
            "rr": round(target_atr_mult / stop_atr_mult, 2),
        },
        "params": {"stop_atr_mult": stop_atr_mult, "target_atr_mult": target_atr_mult},
        "metadata": {
            "pbo": found.get("pbo"),
            "wf_positive": found.get("wf_positive_folds"),
            "wf_total": found.get("wf_total_folds"),
            "final_equity_backtest": found.get("final_equity"),
        },
    }


def rank_candidates(
    candidates: List[Dict],
    whitelist: Dict,
    mode: str = "LIVE",
) -> List[Dict]:
    """
    candidates: lista de {market, current_price, atr, pct_change_24h}
    Returns: lista ordenada por priority_score desc, apenas qualified.
    """
    enriched = []
    for c in candidates:
        r = quant_priority(
            market=c["market"], current_price=c.get("current_price", 0),
            atr=c.get("atr", 0), pct_change_24h=c.get("pct_change_24h", 0),
            whitelist=whitelist, mode=mode,
        )
        if r.get("qualified"):
            enriched.append(r)

    enriched.sort(key=lambda x: x["priority_score"], reverse=True)
    return enriched
