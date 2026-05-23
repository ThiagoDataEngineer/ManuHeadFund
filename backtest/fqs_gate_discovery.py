"""
fqs_gate_discovery.py -- FQS gate aplicado em weekly_discovery.

Pure functions:
  - load_fqs_score(market): le coin_registry.json e retorna {fqs, category}
  - is_fqs_eligible(market, target_tier): valida contra cutoffs
  - apply_fqs_gate(results, target_tier): bloqueia/demote results que falham

Wire em weekly_discovery: chama apply_fqs_gate apos promotion_gates pra
filtrar markets com FQS abaixo do esperado pro tier alvo.

Cutoffs por tier (alinhado com lib_fundamental_quality.ps1):
  TIER_A_LIVE  : QUALITY ou BLUE_CHIP (FQS >= 4)
  TIER_B_PAPER : QUALITY ou BLUE_CHIP (FQS >= 4)
  GEM          : SPECULATIVE ou acima (FQS >= 2)
  default      : AVOID (FQS 0-1)
"""
from __future__ import annotations
import json
from pathlib import Path
from typing import List, Optional

ROOT = Path(__file__).resolve().parent.parent
REGISTRY = ROOT / "journal" / "coin_registry.json"


def load_registry(path: Optional[Path] = None) -> dict:
    p = path or REGISTRY
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {}


def compute_fqs(entry: dict) -> dict:
    """Espelho da logica lib_fundamental_quality.ps1 V1.5.
    Retorna {fqs, category, reasons}."""
    fqs = 0
    reasons = []
    age = entry.get("age_years", 0) or 0

    if age >= 3:
        fqs += 1; reasons.append("age_3y+")

    supply_capped = bool(entry.get("supply_capped"))
    burn_net = bool(entry.get("burn_net_deflation"))
    if supply_capped or burn_net:
        fqs += 1; reasons.append("supply_capped" if supply_capped else "burn_net_deflation")

    if bool(entry.get("burn_active")):
        fqs += 1; reasons.append("burn_active")

    utility = entry.get("utility_score", 0) or 0
    if utility >= 0.5:
        fqs += 1; reasons.append("utility_high")

    conc_field = entry.get("concentration_insider_pct")
    if conc_field is None:
        conc_field = entry.get("concentration_top10", 1.0)
    if conc_field <= 0.5:
        fqs += 1; reasons.append("concentration_ok")

    if entry.get("recovered_2021_ath") is True:
        fqs += 1; reasons.append("recovered_ath")
    elif age < 2:
        fqs += 1; reasons.append("young_NA_cycle")

    if (entry.get("listing_years", 0) or 0) >= 2:
        fqs += 1; reasons.append("listing_stable")

    if fqs >= 6:
        category = "BLUE_CHIP"
    elif fqs >= 4:
        category = "QUALITY"
    elif fqs >= 2:
        category = "SPECULATIVE"
    else:
        category = "AVOID"

    return {"fqs": fqs, "category": category, "reasons": reasons}


def load_fqs_score(market: str, registry_path: Optional[Path] = None) -> dict:
    reg = load_registry(registry_path)
    if market not in reg:
        return {"fqs": 0, "category": "AVOID", "reasons": ["market_not_in_registry"]}
    return compute_fqs(reg[market])


def is_fqs_eligible(market: str, target_tier: str, registry_path: Optional[Path] = None) -> bool:
    cat = load_fqs_score(market, registry_path)["category"]
    if target_tier in ("TIER_A_LIVE", "TIER_B_PAPER"):
        return cat in ("BLUE_CHIP", "QUALITY")
    if target_tier == "GEM":
        return cat in ("BLUE_CHIP", "QUALITY", "SPECULATIVE")
    return False


def apply_fqs_gate(results: list, target_tier: str = "TIER_A_LIVE",
                   registry_path: Optional[Path] = None) -> list:
    """Modifica em-place os results: tier=A com FQS insuficiente -> tier=B + reason.
    Retorna lista de results modificada."""
    for r in results:
        if not isinstance(r, dict):
            continue
        if r.get("tier_assigned") != "A":
            continue
        market = r.get("market")
        if not market:
            continue
        score = load_fqs_score(market, registry_path)
        r["fqs_score"] = score
        if score["category"] not in ("BLUE_CHIP", "QUALITY"):
            r["tier_assigned"] = "B"
            prev = r.get("demoted_reason", "")
            new_reason = f"fqs_{score['fqs']}_{score['category']}"
            r["demoted_reason"] = (prev + "|" if prev else "") + new_reason
    return results
