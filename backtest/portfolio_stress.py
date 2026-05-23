"""
portfolio_stress.py -- Stress simulator. Dado posicoes Tier A + betas,
simula BTC shocks (-10/-25/-50% + upside) e projeta portfolio outcome.

Pure functions (testaveis sem hit external):
  - simulate_btc_shock(positions, btc_pct): aplica beta projection
  - portfolio_beta_avg(positions): weighted avg
  - simulate_scenarios(positions, capital_total): suite de cenarios padrao

Output util pra:
  1. Verificar "se BTC -50%, quanto perdemos?"
  2. Risk budget visualization
  3. Pre-trade gate (futuro): block adicao que aumenta scenario worst case
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path
from typing import List, Optional


def simulate_btc_shock(positions: list, btc_pct: float) -> dict:
    """Aplica BTC shock + projeta cada posicao via beta.
    Returns {btc_shock_pct, portfolio_pct, loss_usd, per_position}.
    """
    total_size = sum(p.get("size_usd", 0) for p in positions)
    if total_size == 0:
        return {"btc_shock_pct": btc_pct, "portfolio_pct": 0.0,
                "loss_usd": 0.0, "per_position": []}

    total_pnl_usd = 0.0
    per_pos = []
    for p in positions:
        size = p.get("size_usd", 0)
        beta = p.get("beta", 1.0)
        projected_pct = btc_pct * beta
        pnl_usd = size * projected_pct / 100.0
        total_pnl_usd += pnl_usd
        per_pos.append({
            "market": p.get("market"),
            "size_usd": size,
            "beta": beta,
            "projected_pct": round(projected_pct, 2),
            "pnl_usd": round(pnl_usd, 2),
        })

    portfolio_pct = (total_pnl_usd / total_size) * 100 if total_size > 0 else 0
    return {
        "btc_shock_pct": btc_pct,
        "portfolio_pct": round(portfolio_pct, 2),
        "loss_usd": round(-total_pnl_usd, 2),  # loss positive = bad
        "per_position": per_pos,
    }


def portfolio_beta_avg(positions: list) -> float:
    """Weighted avg beta (size_usd-weighted)."""
    total_size = sum(p.get("size_usd", 0) for p in positions)
    if total_size == 0:
        return 0.0
    weighted_sum = sum(p.get("size_usd", 0) * p.get("beta", 1.0) for p in positions)
    return round(weighted_sum / total_size, 3)


def simulate_scenarios(positions: list, capital_total: float,
                       scenarios: Optional[List[float]] = None) -> dict:
    """Roda suite de cenarios. Default: -50, -25, -10, +10, +25."""
    if scenarios is None:
        scenarios = [-50, -25, -10, 0, +10, +25]
    out = []
    for s in scenarios:
        r = simulate_btc_shock(positions, s)
        loss_pct_capital = -r["loss_usd"] / capital_total * 100 if capital_total > 0 else 0
        out.append({
            "btc_shock_pct": s,
            "portfolio_pct": r["portfolio_pct"],
            "loss_usd": r["loss_usd"],
            "loss_pct_of_capital": round(loss_pct_capital, 2),
        })
    return {
        "portfolio_beta_avg": portfolio_beta_avg(positions),
        "total_position_usd": round(sum(p.get("size_usd", 0) for p in positions), 2),
        "capital_total": capital_total,
        "scenarios": out,
    }


def load_tier_a_positions(whitelist_path: Path, beta_path: Path,
                          size_usd_per_position: float = 27.63) -> list:
    """Le whitelist + beta cache + cria positions Tier A LIVE com size uniforme."""
    if not whitelist_path.exists():
        return []
    wl = json.loads(whitelist_path.read_text(encoding="utf-8"))
    betas = {}
    if beta_path.exists():
        b = json.loads(beta_path.read_text(encoding="utf-8"))
        betas = b.get("beta", {})
    out = []
    for entry in wl.get("TIER_A_LIVE", []):
        m = entry.get("market")
        if not m or "BITSTAMP" in m: continue
        beta = betas.get(m, 1.0)
        out.append({"market": m, "size_usd": size_usd_per_position, "beta": beta})
    return out


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument("--capital", type=float, default=2762.93)
    p.add_argument("--size-per-position", type=float, default=27.63)
    args = p.parse_args(argv)

    ROOT = Path(__file__).resolve().parent.parent
    # Pega whitelist mais recente
    wls = sorted(ROOT.glob("journal/per_asset_whitelist_*.json"),
                 key=lambda f: f.stat().st_mtime, reverse=True)
    wls = [f for f in wls if "bak" not in f.name and "pre_demote" not in f.name
                                and "pre_swap" not in f.name]
    if not wls:
        print("No whitelist found"); return 1
    wl_path = wls[0]
    beta_path = ROOT / "journal" / "beta_vs_btc.json"

    positions = load_tier_a_positions(wl_path, beta_path, args.size_per_position)
    if not positions:
        print("No Tier A LIVE positions"); return 1

    result = simulate_scenarios(positions, args.capital)
    print(f"=== Portfolio Stress @ capital ${args.capital} (size/pos ${args.size_per_position}) ===")
    print(f"Whitelist: {wl_path.name}")
    print(f"Positions: {[p['market'] for p in positions]}")
    print(f"Portfolio beta_avg: {result['portfolio_beta_avg']}")
    print(f"Total exposed: ${result['total_position_usd']}")
    print()
    print(f"{'BTC shock':>12} {'Portfolio %':>14} {'Loss USD':>11} {'Loss % capital':>16}")
    print("-" * 60)
    for s in result["scenarios"]:
        print(f"{s['btc_shock_pct']:+11.0f}% {s['portfolio_pct']:+13.2f}% "
              f"${s['loss_usd']:>10.2f} {s['loss_pct_of_capital']:+15.2f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
