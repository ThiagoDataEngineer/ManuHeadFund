"""
coingecko_enrichment.py -- Enriquece coin_registry.json com dados live CoinGecko.

CoinGecko API free tier:
  - Rate limit ~30 req/min
  - Endpoint /coins/{id} retorna: genesis_date, market_data.max_supply,
    market_data.circulating_supply, market_data.ath, market_data.current_price,
    community_data, developer_data (commits)

Strategy:
  - Pure functions testaveis (map / derive / merge) sem hit API
  - main() faz fetch + applied merge -> writes registry com backup

Usage:
    python coingecko_enrichment.py --markets BTC,ETH,INJ
    python coingecko_enrichment.py --all-from-registry
    python coingecko_enrichment.py --dry-run (so mostra diff sem salvar)

Preserva campos curated manualmente (burn_active, utility_score, concentration_insider_pct, notes).
"""
from __future__ import annotations
import argparse, json, os, sys, time
from datetime import datetime
from pathlib import Path
from typing import Optional
import urllib.request, urllib.parse, urllib.error

ROOT = Path(__file__).resolve().parent.parent
REGISTRY_PATH = ROOT / "journal" / "coin_registry.json"
COINGECKO_BASE = "https://api.coingecko.com/api/v3"
SUPABASE_SCHEMA = "manuheadfund"
SUPABASE_TABLE = "coin_registry_dynamic"


# Hardcoded mapping market -> CoinGecko ID (mais confiavel que /coins/list search)
MARKET_TO_CG = {
    "BTCUSDT": "bitcoin",
    "ETHUSDT": "ethereum",
    "INJUSDT": "injective-protocol",
    "ZECUSDT": "zcash",
    "RENDERUSDT": "render-token",
    "CFGUSDT": "centrifuge",
    "TONUSDT": "the-open-network",
    "NEARUSDT": "near",
    "HYPEUSDT": "hyperliquid",
    "DYDXUSDT": "dydx-chain",
    "ONDOUSDT": "ondo-finance",
    "ALGOUSDT": "algorand",
    "STORJUSDT": "storj",
    "COMPUSDT": "compound-governance-token",
    "SOLUSDT": "solana",
    "ATOMUSDT": "cosmos",
    "DOGEUSDT": "dogecoin",
    "CHZUSDT": "chiliz",
    "AAVEUSDT": "aave",
    "XMRUSDT": "monero",
    "FILUSDT": "filecoin",
    "DASHUSDT": "dash",
    "KASUSDT": "kaspa",
    "SUIUSDT": "sui",
    "XRPUSDT": "ripple",
    "BCHUSDT": "bitcoin-cash",
    "PENDLEUSDT": "pendle",
    "MORPHOUSDT": "morpho",
    "SKYUSDT": "sky",
    "MAPLEUSDT": "maple",
    "LUNCUSDT": "terra-luna",
    "VVVUSDT": "venice-token",
    # 2026-05-20 PM5: adicionados via WebFetch CoinGecko search API
    "TAOUSDT":   "bittensor",
    "PENGUUSDT": "pudgy-penguins",
    "KITEUSDT":  "kite-2",
    "RIVERUSDT": "river",
    "ARBUSDT":   "arbitrum",
    "XCHUSDT":   "chia",
    "LITUSDT":   "litentry",
    "RONUSDT":   "ronin",
    "BUSDT":     "bitrue-token",
    # 2026-05-21 morning audit: 6 markets scanned hoje sem registry entry
    "WIFUSDT":     "dogwifcoin",
    "ARRRUSDT":    "pirate-chain",
    "GRASSUSDT":   "grass",
    "ASTERUSDT":   "aster-2",
    "USELESSUSDT": "useless-3",
    "PROVEUSDT":   "succinct",
    "JTOUSDT":     "jito-governance-token",
    # 2026-05-21 sessao extra: queue acumulou +5 markets via scan/mentor discovery
    "PEAQUSDT":    "peaq-2",
    "CHEEMSUSDT":  "cheems-token",
    "WLDUSDT":     "worldcoin-wld",
    "PYTHUSDT":    "pyth-network",
    "SUSDT":       "sonic-3",  # Sonic L1 (formerly Fantom). Verificar se mapping correto.
    # 2026-08-19: expansao real (owner pediu "lista de 100 moedas" -- achado que
    # Invoke-FqsLazyEnrich/gem_executor.ps1 JA CHAMA este mapping automaticamente
    # a cada candidato novo, mas so cobria 53 tickers, travando LINK/ADA/AVAX/BNB/
    # UNI/etc em FQS=AVOID por ausencia de mapeamento, nao por qualidade real).
    # IDs resolvidos via /coins/list (match por symbol) + desambiguacao manual
    # onde havia mais de 1 projeto com o mesmo symbol -- validado amostralmente
    # contra /coins/{id} real (chainlink/cardano/avalanche-2/binancecoin/uniswap/
    # hyperliquid/crypto-com-chain/pump-fun/lido-dao/curve-dao-token/bonk/
    # litecoin/pepe confirmados batendo nome+symbol esperado).
    "ADAUSDT": "cardano",
    "AEROUSDT": "aerodrome-finance",
    "AEVOUSDT": "aevo-exchange",
    "ANKRUSDT": "ankr",
    "AVAXUSDT": "avalanche-2",
    "AVNTUSDT": "avantis",
    "BABYDOGEUSDT": "baby-doge-coin",
    "BIOUSDT": "bio-protocol",
    "BNBUSDT": "binancecoin",
    "BONKUSDT": "bonk",
    "BRETTUSDT": "brett",
    "BTTUSDT": "bittorrent",
    "CAKEUSDT": "pancakeswap-token",
    "CHIPUSDT": "chip-2",
    "CROUSDT": "crypto-com-chain",
    "CRVUSDT": "curve-dao-token",
    "DOTUSDT": "polkadot",
    "EIGENUSDT": "eigenlayer",
    "ENAUSDT": "ethena",
    "ENSUSDT": "ethereum-name-service",
    "ETCUSDT": "ethereum-classic",
    "ETHFIUSDT": "ether-fi",
    "FARTCOINUSDT": "fartcoin",
    "FLOKIUSDT": "floki",
    "GALAUSDT": "gala",
    "GRAMUSDT": "the-open-network",  # rebrand TON->GRAM 2026-06-15, mesmo ativo (CoinGecko ID ainda "the-open-network")
    "HBARUSDT": "hedera-hashgraph",
    "ICPUSDT": "internet-computer",
    "KAIAUSDT": "kaia",
    "KAITOUSDT": "kaito",
    "LDOUSDT": "lido-dao",
    "LINEAUSDT": "linea",
    "LINKUSDT": "chainlink",
    "LTCUSDT": "litecoin",
    "MASKUSDT": "mask-network",
    "MNTUSDT": "mantle",
    "OKBUSDT": "okb",
    "ONEUSDT": "harmony",
    "ORDIUSDT": "ordinals",
    "PARTIUSDT": "particle-network",
    "PEPEUSDT": "pepe",
    "PIPPINUSDT": "pippin",
    "POLUSDT": "polygon-ecosystem-token",
    "PUMPUSDT": "pump-fun",
    "RATSUSDT": "rats",
    "RAYUSDT": "raydium",
    "RVNUSDT": "ravencoin",
    "SHIBUSDT": "shiba-inu",
    "SOONUSDT": "soon-2",
    "SPXUSDT": "spx6900",
    "STRKUSDT": "starknet",
    "SUPERUSDT": "superfarm",
    "UNIUSDT": "uniswap",
    "VIRTUALUSDT": "virtual-protocol",
    "XAUTUSDT": "tether-gold",
    "XLMUSDT": "stellar",
    "ZROUSDT": "layerzero",
}


def map_market_to_coingecko_id(market: str) -> Optional[str]:
    """Maps CoinEx market symbol to CoinGecko ID. Returns None if unknown."""
    if not market:
        return None
    return MARKET_TO_CG.get(market.upper())


def derive_registry_fields(response: dict, as_of_year: int = 2026) -> dict:
    """Extract FQS-relevant fields from CoinGecko /coins/{id} response.
    Returns dict with: age_years, supply_capped, recovered_2021_ath.
    NUNCA retorna burn_active / utility_score (esses sao curated manualmente).
    """
    out = {}

    # Age
    gen = response.get("genesis_date")
    if gen:
        try:
            gen_year = int(str(gen).split("-")[0])
            out["age_years"] = max(0, as_of_year - gen_year)
        except (ValueError, IndexError):
            pass

    md = response.get("market_data") or {}

    # Supply capped: max_supply existe e finito
    max_supply = md.get("max_supply")
    out["supply_capped"] = bool(max_supply and max_supply > 0)
    # 2026-05-20 PM5 bug fix: persistir raw numbers pra FQS V1.6 partial path
    if max_supply:
        out["max_supply"] = float(max_supply)
    circ = md.get("circulating_supply")
    if circ:
        out["circulating_supply"] = float(circ)

    # Recovered 2021 ATH: current >= ATH * 0.5 (50% recover threshold ja boa)
    # Strict: current >= ATH (full recover)
    cp = md.get("current_price", {})
    ath = md.get("ath", {})
    if cp and ath:
        current_usd = cp.get("usd")
        ath_usd = ath.get("usd")
        if current_usd and ath_usd and ath_usd > 0:
            # Strict version: current >= ATH
            out["recovered_2021_ath"] = current_usd >= ath_usd
            # Persistir pra V1.6 partial path detectar 50% recovery
            out["current_price_usd"] = float(current_usd)
            out["ath_all_time_usd"] = float(ath_usd)
    else:
        out["recovered_2021_ath"] = False

    # Listing years aproximado (CoinEx listing not in CoinGecko; usar age como proxy)
    if "age_years" in out:
        out["listing_years"] = min(out["age_years"], 8)  # cap em 8 (CoinEx historia)

    return out


def merge_into_registry(registry: dict, market: str, derived: dict) -> dict:
    """Aplica derived fields ao registry, preservando campos manualmente curated.
    Campos que CoinGecko sobrescreve: age_years, supply_capped, recovered_2021_ath, listing_years.
    Campos preservados: burn_active, utility_score, concentration_top10,
    concentration_insider_pct, burn_net_deflation, notes."""
    if market not in registry:
        registry[market] = {}
    # Merge: derived sobrescreve apenas o que retornou
    for k, v in derived.items():
        registry[market][k] = v
    return registry


def find_markets_needing_full_enrichment(registry: dict) -> list:
    """Detecta markets em registry que faltam age_years (campo critico FQS dimensao 1).
    So inclui markets com mapping CoinGecko (pode enriquecer). Skip _meta + unmapped.

    Useful pra --new-only: enrich SO markets que precisam (per-coin lento/rate-limited).
    """
    out = []
    for market, entry in registry.items():
        if market.startswith("_"):
            continue
        if market not in MARKET_TO_CG:
            continue
        if not isinstance(entry, dict):
            continue
        age = entry.get("age_years")
        if age is None or age == 0:
            out.append(market)
    return sorted(out)


def fetch_coingecko(coin_id: str, timeout: int = 15) -> Optional[dict]:
    """Fetch /coins/{id}. Returns parsed dict ou None se falhar."""
    url = f"{COINGECKO_BASE}/coins/{urllib.parse.quote(coin_id)}?localization=false&tickers=false&community_data=false&developer_data=false&sparkline=false"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "coinex-ai-fqs-enrichment/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 429:
            print(f"[coingecko] rate limit hit pra {coin_id}, aguardando 60s...")
            time.sleep(60)
            try:
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    return json.loads(resp.read().decode("utf-8"))
            except Exception:
                return None
        print(f"[coingecko] HTTP {e.code} pra {coin_id}")
        return None
    except Exception as e:
        print(f"[coingecko] erro {coin_id}: {e}")
        return None


def build_supabase_row(market: str, coingecko_id: str, derived: dict) -> dict:
    """Monta 1 linha pra upsert em manuheadfund.coin_registry_dynamic.
    So campos derivaveis via CoinGecko (age_years, supply_capped, etc) --
    burn_active/utility_score/concentration_top10 continuam SO no registry
    estatico curado (docs/SETUP_SUPABASE_COIN_REGISTRY_DYNAMIC_2026_08_19.sql
    explica o motivo: CoinGecko nao tem esse dado, e julgamento manual)."""
    row = {"market": market, "coingecko_id": coingecko_id, "source": "coingecko_enrichment_auto"}
    for k in ("age_years", "supply_capped", "recovered_2021_ath", "current_price_usd",
              "ath_all_time_usd", "max_supply", "circulating_supply"):
        if k in derived:
            row[k] = derived[k]
    return row


def push_to_supabase(rows: list, url: str, service_key: str, timeout: int = 15) -> bool:
    """Upsert em lote via PostgREST (Content-Profile + Prefer merge-duplicates,
    mesmo padrao de agents/lib_state_store.ps1). Retorna True se sucesso."""
    if not rows:
        return True
    endpoint = f"{url.rstrip('/')}/rest/v1/{SUPABASE_TABLE}"
    body = json.dumps(rows).encode("utf-8")
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
        "Content-Profile": SUPABASE_SCHEMA,
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }
    req = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            resp.read()
        return True
    except urllib.error.HTTPError as e:
        print(f"[supabase] HTTP {e.code} no upsert: {e.read().decode('utf-8', errors='replace')}")
        return False
    except Exception as e:
        print(f"[supabase] erro no upsert: {e}")
        return False


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument("--markets", help="comma-separated (default: todos do MARKET_TO_CG)")
    p.add_argument("--all-from-registry", action="store_true")
    p.add_argument("--new-only", action="store_true",
                   help="So markets sem age_years (per-coin full enrichment pra novos)")
    p.add_argument("--dry-run", action="store_true", help="nao salva")
    p.add_argument("--registry", default=str(REGISTRY_PATH))
    p.add_argument("--sleep", type=float, default=2.5, help="segundos entre calls (rate limit)")
    p.add_argument("--supabase", action="store_true",
                   help="tambem faz upsert em manuheadfund.coin_registry_dynamic (requer SUPABASE_URL/SUPABASE_SERVICE_KEY no ambiente)")
    args = p.parse_args(argv)

    reg_path = Path(args.registry)
    if reg_path.exists():
        registry = json.loads(reg_path.read_text(encoding="utf-8"))
    else:
        registry = {}

    # Determine markets list
    if args.markets:
        markets = [m.strip().upper() for m in args.markets.split(",") if m.strip()]
    elif args.new_only:
        markets = find_markets_needing_full_enrichment(registry)
        if not markets:
            print("[coingecko] no markets need full enrichment (all have age_years). Exit.")
            return 0
        print(f"[coingecko] --new-only: {len(markets)} markets sem age -> {markets}")
    elif args.all_from_registry:
        markets = [k for k in registry.keys() if not k.startswith("_")]
    else:
        markets = list(MARKET_TO_CG.keys())

    print(f"[coingecko] processing {len(markets)} markets, dry_run={args.dry_run}")
    n_updated = 0
    n_failed = 0
    n_skipped = 0
    supabase_rows = []
    for mkt in markets:
        cg_id = map_market_to_coingecko_id(mkt)
        if not cg_id:
            print(f"  [skip] {mkt} sem mapping CoinGecko")
            n_skipped += 1
            continue
        resp = fetch_coingecko(cg_id)
        if not resp:
            print(f"  [fail] {mkt} ({cg_id})")
            n_failed += 1
            continue
        derived = derive_registry_fields(resp)
        registry = merge_into_registry(registry, mkt, derived)
        supabase_rows.append(build_supabase_row(mkt, cg_id, derived))
        print(f"  [ok] {mkt} ({cg_id}) -> {derived}")
        n_updated += 1
        time.sleep(args.sleep)

    print(f"\n[coingecko] {n_updated} updated, {n_failed} failed, {n_skipped} skipped")

    if args.supabase and not args.dry_run:
        supa_url = os.environ.get("SUPABASE_URL")
        supa_key = os.environ.get("SUPABASE_SERVICE_KEY")
        if not supa_url or not supa_key:
            print("[supabase] SUPABASE_URL/SUPABASE_SERVICE_KEY ausentes no ambiente -- skip upsert")
        else:
            ok = push_to_supabase(supabase_rows, supa_url, supa_key)
            print(f"[supabase] upsert de {len(supabase_rows)} linhas -> {'ok' if ok else 'FALHOU'}")

    if args.dry_run:
        print("[coingecko] DRY_RUN -- registry NOT saved")
        return 0

    # Backup + save
    if reg_path.exists():
        backup = reg_path.with_suffix(f".bak_{datetime.now().strftime('%Y%m%d_%H%M')}.json")
        backup.write_text(reg_path.read_text(encoding="utf-8"), encoding="utf-8")
        print(f"[coingecko] backup -> {backup.name}")
        # B10 fix 2026-05-20 PM6+: rotate — keep only 5 most recent backups
        backups = sorted(reg_path.parent.glob("coin_registry.bak_*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
        for stale in backups[5:]:
            try:
                stale.unlink()
                print(f"[coingecko] prune stale backup -> {stale.name}")
            except OSError:
                pass

    reg_path.parent.mkdir(parents=True, exist_ok=True)
    reg_path.write_text(json.dumps(registry, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"[coingecko] saved -> {reg_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
