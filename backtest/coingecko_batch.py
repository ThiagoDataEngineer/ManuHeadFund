"""
coingecko_batch.py -- Batch endpoint /coins/markets pra refresh rapido.

Diferenca vs coingecko_enrichment.py (per-coin /coins/{id}):
  - 1 call retorna ate 250 markets (vs 1/call)
  - SEM genesis_date (precisa /coins/{id} pra age)
  - Tem: max_supply, circulating_supply, current_price, ath, ath_date, market_cap_rank

Usage:
    python coingecko_batch.py --apply              # refresh all em batch
    python coingecko_batch.py --dry-run            # mostra diff
    python coingecko_batch.py --markets BTC,ETH    # so esses

Speedup vs per-coin: 30 calls 3s = 90s -> 1 call = ~3s (30x mais rapido).
"""
from __future__ import annotations
import argparse, json, sys, time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional
import urllib.request, urllib.parse, urllib.error

ROOT = Path(__file__).resolve().parent.parent
REGISTRY_PATH = ROOT / "journal" / "coin_registry.json"
COINGECKO_BASE = "https://api.coingecko.com/api/v3"

# Import shared mapping
sys.path.insert(0, str(ROOT / "backtest"))
from coingecko_enrichment import MARKET_TO_CG  # type: ignore


def chunk_ids(ids: List[str], size: int = 250) -> List[List[str]]:
    """Split lista de IDs em chunks de tamanho max (CoinGecko limit)."""
    return [ids[i:i + size] for i in range(0, len(ids), size)]


def derive_from_batch_row(row: dict) -> dict:
    """Extract FQS-relevant fields from /coins/markets row.
    Retorna apenas o que batch endpoint provem (NAO inclui age_years - precisa /coins/{id}).
    V1.6: persiste current_price_usd + ath_all_time_usd pra FQS partial recovery path."""
    out = {}
    max_supply = row.get("max_supply")
    out["supply_capped"] = bool(max_supply and max_supply > 0)

    current_price = row.get("current_price")
    ath = row.get("ath")
    if current_price is not None and ath and ath > 0:
        out["recovered_2021_ath"] = current_price >= ath
        out["current_price_usd"] = current_price
        out["ath_all_time_usd"] = ath
    else:
        out["recovered_2021_ath"] = False

    return out


def map_batch_response_to_markets(batch_response: List[dict],
                                  id_to_market: Dict[str, str]) -> Dict[str, dict]:
    """Cruza batch response com mapping CoinGecko ID -> market symbol.
    Returns dict {market: derived_fields}."""
    out = {}
    for row in batch_response:
        cg_id = row.get("id")
        if not cg_id or cg_id not in id_to_market:
            continue
        market = id_to_market[cg_id]
        out[market] = derive_from_batch_row(row)
    return out


def merge_batch_into_registry(registry: dict, derived_by_market: Dict[str, dict]) -> dict:
    """Aplica derived fields a multiple markets, preservando campos manuais.
    V1.6: respeita recovered_2021_ath_source='manual_override_*' (nao sobrescreve)."""
    for market, derived in derived_by_market.items():
        if market not in registry:
            registry[market] = {}
        # Preserva manual override de recovered_2021_ath
        existing_source = registry[market].get('recovered_2021_ath_source', '')
        is_manual = existing_source.startswith('manual_override')
        for k, v in derived.items():
            if k == 'recovered_2021_ath' and is_manual:
                continue  # respeita manual override
            registry[market][k] = v
    return registry


def fetch_batch(ids: List[str], vs_currency: str = "usd", timeout: int = 30) -> Optional[List[dict]]:
    """Hit /coins/markets com lista de IDs. Retorna lista de rows ou None."""
    params = {
        "vs_currency": vs_currency,
        "ids": ",".join(ids),
        "order": "market_cap_desc",
        "per_page": 250,
        "page": 1,
        "sparkline": "false",
    }
    url = COINGECKO_BASE + "/coins/markets?" + urllib.parse.urlencode(params)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "coinex-ai-fqs-batch/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 429:
            print("[batch] rate limit, sleep 60s + retry")
            time.sleep(60)
            try:
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    return json.loads(resp.read().decode("utf-8"))
            except Exception:
                return None
        print(f"[batch] HTTP {e.code}")
        return None
    except Exception as e:
        print(f"[batch] erro: {e}")
        return None


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument("--markets", help="comma-separated (default: todos do registry)")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--registry", default=str(REGISTRY_PATH))
    args = p.parse_args(argv)

    reg_path = Path(args.registry)
    registry = json.loads(reg_path.read_text(encoding="utf-8")) if reg_path.exists() else {}

    # Determine markets pra refresh
    if args.markets:
        markets = [m.strip().upper() for m in args.markets.split(",") if m.strip()]
    else:
        markets = [k for k in registry.keys() if not k.startswith("_") and k in MARKET_TO_CG]

    # Build ID list + reverse map
    ids = []
    id_to_market = {}
    for m in markets:
        cg_id = MARKET_TO_CG.get(m)
        if cg_id:
            ids.append(cg_id)
            id_to_market[cg_id] = m

    print(f"[batch] fetching {len(ids)} IDs em batch...")
    t0 = time.time()
    derived_by_market = {}
    for chunk in chunk_ids(ids, size=250):
        resp = fetch_batch(chunk)
        if not resp:
            print(f"  [fail] chunk size {len(chunk)}")
            continue
        derived = map_batch_response_to_markets(resp, id_to_market)
        derived_by_market.update(derived)

    elapsed = round(time.time() - t0, 1)
    print(f"[batch] {len(derived_by_market)} markets derived em {elapsed}s")

    if args.dry_run:
        print("\n[batch] DRY_RUN -- changes:")
        for m, d in sorted(derived_by_market.items())[:15]:
            cur = registry.get(m, {})
            sc_old = cur.get("supply_capped", "?")
            sc_new = d.get("supply_capped", "?")
            rec_old = cur.get("recovered_2021_ath", "?")
            rec_new = d.get("recovered_2021_ath", "?")
            print(f"  {m:<14} supply_capped {sc_old}->{sc_new}  recovered_ath {rec_old}->{rec_new}")
        if len(derived_by_market) > 15:
            print(f"  ... +{len(derived_by_market)-15} more")
        return 0

    # Backup + save
    if reg_path.exists():
        backup = reg_path.parent / f"coin_registry.bak_batch_{datetime.now().strftime('%Y%m%d_%H%M')}.json"
        backup.write_text(reg_path.read_text(encoding="utf-8"), encoding="utf-8")
        print(f"[batch] backup -> {backup.name}")
        # B10 fix 2026-05-20 PM6+: rotate — keep only 5 most recent backups
        backups = sorted(reg_path.parent.glob("coin_registry.bak_*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
        for stale in backups[5:]:
            try:
                stale.unlink()
                print(f"[batch] prune stale backup -> {stale.name}")
            except OSError:
                pass

    registry = merge_batch_into_registry(registry, derived_by_market)
    reg_path.parent.mkdir(parents=True, exist_ok=True)
    reg_path.write_text(json.dumps(registry, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"[batch] saved -> {reg_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
