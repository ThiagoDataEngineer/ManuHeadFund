"""
curated_candidates.py — Lista curada de 40 candidatos por PERFIL de edge survival.

Baseado em CRYPTO_MARKET_MICROSTRUCTURE §5 (Edge Survival Map) +
PER_ASSET_OPTIMIZATION_PLAYBOOK §4 (taxonomy).

NÃO usa volume cego — pré-filtra por perfil teórico ANTES de coletar.
"""

CURATED_LIST = {
    # Privacy mid-cap: ZEC já é Tier A. Testar primos.
    "privacy_mid_cap": [
        "ZECUSDT",   # já cached, Tier A
        "XMRUSDT",
        "DASHUSDT",
        "DCRUSDT",   # Decred
    ],

    # Niche L1 mid-cap: MM attention media. Candidatos a Tier B/A.
    "niche_l1": [
        "ALGOUSDT",
        "ATOMUSDT",
        "NEARUSDT",
        "KASUSDT",
        "FTMUSDT",
        "ICXUSDT",
    ],

    # Old-school halving cycle: BTC já é Tier A.
    "halving_cycle": [
        "LTCUSDT",   # já cached
        "BCHUSDT",
        "ETCUSDT",   # Ethereum Classic
    ],

    # Storage/Compute: niche, retail-friendly
    "storage_compute": [
        "STORJUSDT",
        "FILUSDT",
        "ARUSDT",    # Arweave
        "RNDRUSDT",  # Render
        "AKTUSDT",   # Akash
    ],

    # Mid-cap DeFi value
    "defi_value": [
        "AAVEUSDT",  # já cached
        "MKRUSDT",
        "COMPUSDT",
        "UNIUSDT",
    ],

    # Majors (validação cruzada CoinEx vs Bitstamp)
    "majors_coinex": [
        "BTCUSDT",   # já cached
        "ETHUSDT",   # já cached
        "SOLUSDT",   # já cached
        "BNBUSDT",   # já cached
        "ADAUSDT",   # já cached
        "XRPUSDT",   # já cached
    ],

    # Mantém alguns Tier C/B já testados (validação repetida)
    "validation_pool": [
        "SUIUSDT", "DOGEUSDT", "TAOUSDT", "PEPEUSDT",
    ],
}

# Explicitly SKIPPED (MM heaven / sentiment-driven / overfit risk)
SKIP_LIST = [
    "SHIBUSDT", "FLOKIUSDT", "WIFUSDT", "BONKUSDT",  # memecoins
    "HYPEUSDT", "TONUSDT",                            # recent launch / overfit
    "TRUMPUSDT", "MELANIAUSDT",                       # political sentiment
    "MOGUSDT", "TURBOUSDT",                           # micro-cap memes
]

# Liquidity haircut (Makarov/Schoar): vol reportado * 0.7 = vol real conservador
LIQUIDITY_HAIRCUT = 0.7
MIN_VOL_USD_REAL = 300_000   # $300k vol real mínimo


def flatten_curated() -> list:
    """Retorna lista plana de todos candidatos curados, deduplicado."""
    seen = set()
    out = []
    for category, markets in CURATED_LIST.items():
        for m in markets:
            if m not in seen and m not in SKIP_LIST:
                seen.add(m)
                out.append(m)
    return out


def get_category(market: str) -> str:
    for cat, markets in CURATED_LIST.items():
        if market in markets:
            return cat
    return "unknown"


if __name__ == "__main__":
    flat = flatten_curated()
    print(f"Total curated: {len(flat)}")
    for cat, markets in CURATED_LIST.items():
        print(f"\n{cat}: {len(markets)}")
        for m in markets:
            print(f"  - {m}")
    print(f"\nSKIP: {len(SKIP_LIST)} markets descartados (memecoins/recent/political)")
