"""
tier_a_drawdown_monitor.py -- Vigia drawdown dos markets Tier A LIVE.

Roda diariamente via cron. Para cada Tier A LIVE:
1. Fetch ticker + kline 7d
2. Compute vs 7d peak
3. Se < -15% (DRAWDOWN_FLAG) ou < -25% (DRAWDOWN_CRITICAL):
   - Dispara revalidation para esse market (smart: nao full whitelist)
   - Telegram alerta

Output: journal/tier_a_drawdown_<DATE>.json + integra com revalidation
"""
from __future__ import annotations

import json, sys, time
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backtest"))

JOURNAL = ROOT / "journal"
CANDLES_DIR = JOURNAL / "candles_coinex"

DRAWDOWN_FLAG = -0.15      # -15% from 7d peak -> flag pra investigar (default Tier A LIVE)
DRAWDOWN_CRITICAL = -0.25  # -25% -> trigger revalidation imediato (default)
MIN_VOL_REPLACEMENT = 100_000   # vol min pra replacement candidate
TOP_REPLACEMENTS = 5            # top N substitutos a mostrar

# 2026-05-19 PM: thresholds source-aware. GEM e mais volatil, tolera mais DD.
# Tier A LIVE eh capital real, mais conservador.
SOURCE_THRESHOLDS = {
    "tier_a":      {"flag": -0.15, "critical": -0.25, "label": "TIER_A_LIVE"},
    "orchestrator":{"flag": -0.15, "critical": -0.25, "label": "TIER_A_LIVE"},
    "gem":         {"flag": -0.30, "critical": -0.45, "label": "GEM"},  # GEM tolera ate -45% antes critical
}


def get_thresholds(source_or_mode):
    """Resolve flag/critical thresholds baseado em source/mode da posicao."""
    key = (source_or_mode or "").lower()
    return SOURCE_THRESHOLDS.get(key, {"flag": DRAWDOWN_FLAG, "critical": DRAWDOWN_CRITICAL, "label": "DEFAULT"})

def fetch(url, timeout=15):
    try:
        with urlopen(Request(url, headers={"User-Agent":"dd/1"}), timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception as e:
        return {"_error": str(e)}


def load_tier_a_markets():
    """Carrega Tier A LIVE da whitelist mais recente."""
    files = sorted(JOURNAL.glob("per_asset_whitelist_*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not files: return []
    with open(files[0], "r", encoding="utf-8") as f:
        wl = json.load(f)
    markets = []
    for e in wl.get("TIER_A_LIVE", []):
        m = e.get("market")
        if m and "BITSTAMP" not in m:
            markets.append(m)
    return markets


def check_drawdown(market, source="tier_a"):
    """Fetch ticker + 7d kline, compute drawdown vs peak.

    2026-05-20: source-aware thresholds wired. Antes hardcoded -15%/-25% pra todos
    -> agora GEM tolera -30%/-45% (mais volatil), tier_a fica strict.
    """
    t = fetch(f"https://api.coinex.com/v2/spot/ticker?market={market}")
    if "_error" in t or not (t.get("data") or []):
        return {"market": market, "error": "fetch_ticker_failed"}
    tick = t["data"][0]
    last = float(tick.get("last", 0))
    op = float(tick.get("open", 0))
    pct24 = ((last - op) / op * 100) if op > 0 else 0

    k = fetch(f"https://api.coinex.com/v2/spot/kline?market={market}&period=1day&limit=7")
    if "_error" in k or not (k.get("data") or []):
        return {"market": market, "error": "fetch_kline_failed"}
    highs = [float(c["high"]) for c in k["data"]]
    peak7d = max(highs) if highs else last
    vs_peak = (last - peak7d) / peak7d if peak7d > 0 else 0

    th = get_thresholds(source)
    status = "OK"
    if vs_peak <= th["critical"]:    status = "CRITICAL"
    elif vs_peak <= th["flag"]:      status = "FLAGGED"

    return {
        "market": market, "price": last, "pct24h": round(pct24, 2),
        "peak_7d": peak7d, "vs_peak_pct": round(vs_peak * 100, 2),
        "status": status,
        "source": source,
        "thresholds_used": th,
    }


def trigger_revalidation_for_market(market):
    """Roda revalidation focada apenas neste market (smart re-test)."""
    from run_cross_asset_matrix import process_pair
    entries_dir = JOURNAL / "entries_coinex"
    for f in [entries_dir/f"entries_{market}.json", entries_dir/f"alldicts_{market}.json"]:
        if f.exists():
            try: f.unlink()
            except: pass
    candles_path = CANDLES_DIR / f"{market}_1day.json"
    if not candles_path.exists():
        return {"market": market, "skipped": "no_candles"}
    try:
        r = process_pair(market, candles_path)
        return r
    except Exception as e:
        return {"market": market, "error": str(e)}


def load_pipeline_markets():
    """Carrega markets ja em promotion_pipeline.jsonl (qualquer state)."""
    p = JOURNAL / "promotion_pipeline.jsonl"
    if not p.exists(): return set()
    markets = set()
    with open(p, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                obj = json.loads(line)
                m = obj.get("market")
                if m: markets.add(m)
            except: pass
    return markets


def load_already_tested_markets():
    """Carrega ALL markets ja em whitelist (qualquer tier) -- evita re-test desnecessario."""
    files = sorted(JOURNAL.glob("per_asset_whitelist_*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not files: return {}
    with open(files[0], "r", encoding="utf-8") as f:
        wl = json.load(f)
    tested = {}
    for tier in ("TIER_A_LIVE","TIER_B_PAPER","TIER_C_SKIP"):
        for e in wl.get(tier, []):
            m = e.get("market")
            if m:
                tested[m] = {"tier": e.get("tier","?"), "sharpe": e.get("sharpe", 0)}
    return tested


def scan_replacement_candidates(excluded_markets):
    """
    Quando algum Tier A flagged/critical, busca substitutos subindo.
    Top markets por gain 7d que NAO estao em whitelist ainda.
    Inclui info de backtest historico se ja testado (warning se TIER_C).
    """
    print("\nScanning replacement candidates...")
    tested = load_already_tested_markets()
    in_pipeline = load_pipeline_markets()
    excluded_all = set(excluded_markets) | in_pipeline
    tickers_data = fetch("https://api.coinex.com/v2/spot/ticker")
    tickers = tickers_data.get("data") or []
    # Filtrar USDT, vol >= MIN, nao excluded (tier A current + pipeline OBSERVATION)
    cands = []
    for t in tickers:
        m = t.get("market")
        if not m or not m.endswith("USDT"): continue
        if m in excluded_all: continue
        vol = float(t.get("value", 0))
        if vol < MIN_VOL_REPLACEMENT: continue
        last = float(t.get("last", 0))
        op = float(t.get("open", 0))
        if op <= 0: continue
        pct24 = (last - op) / op * 100
        cands.append({"market": m, "price": last, "pct24": pct24, "vol": vol})
    # Sort por pct24 desc (top gainers)
    cands.sort(key=lambda x: -x["pct24"])
    # Get 7d kline pra cada top 15 e categorizar goldilocks-style
    top15 = cands[:15]
    enriched = []
    for c in top15:
        k = fetch(f"https://api.coinex.com/v2/spot/kline?market={c['market']}&period=1day&limit=210")
        kdata = k.get("data") or []
        if len(kdata) < 200:
            c["category"] = "NO_HIST"; enriched.append(c); continue
        closes = [float(x["close"]) for x in kdata]
        sma200 = sum(closes[-200:]) / 200
        cur = closes[-1]
        dist200 = (cur - sma200) / sma200
        mom20 = (cur - closes[-20]) / closes[-20] if closes[-20] > 0 else 0
        c["dist200"] = round(dist200, 3)
        c["mom20"] = round(mom20, 3)
        # Goldilocks category
        if dist200 > 0 and dist200 < 0.15 and mom20 > 0.02 and mom20 < 0.30:
            c["category"] = "EARLY_BULL"   # PRIME
        elif dist200 > 0 and mom20 > 0.10:
            c["category"] = "BULL_EXTENDED"
        elif dist200 > -0.05 and mom20 > 0.05:
            c["category"] = "BREAKOUT_TEST"
        else:
            c["category"] = "OTHER"
        # Anota se ja foi testado
        if c["market"] in tested:
            c["already_tested"] = True
            c["historical_tier"] = tested[c["market"]]["tier"]
            c["historical_sharpe"] = tested[c["market"]]["sharpe"]
        else:
            c["already_tested"] = False
        enriched.append(c)
    # FILTRA todos ja testados (TIER_A/B/C ja conhecidos -- nao sao substitutos novos)
    enriched = [c for c in enriched if not c.get("already_tested")]
    # Prioriza EARLY_BULL + BREAKOUT_TEST (cleaner setups)
    prime = [c for c in enriched if c["category"] in ("EARLY_BULL","BREAKOUT_TEST")]
    other = [c for c in enriched if c["category"] not in ("EARLY_BULL","BREAKOUT_TEST")]
    return (prime + other)[:TOP_REPLACEMENTS]


def main():
    print("=" * 70)
    print("Tier A Drawdown Monitor")
    print("=" * 70)
    markets = load_tier_a_markets()
    print(f"  {len(markets)} Tier A LIVE markets: {markets}\n")

    results = []
    flagged = []
    critical = []
    for m in markets:
        r = check_drawdown(m)
        if "error" in r:
            print(f"  {m}: ERR {r['error']}"); continue
        results.append(r)
        emoji = {"OK":"OK", "FLAGGED":"FLAG", "CRITICAL":"CRIT"}.get(r["status"], "?")
        print(f"  {m:<14} ${r['price']:>10.4f} 24h={r['pct24h']:>+6.2f}% peak7d=${r['peak_7d']:>10.4f} vs_peak={r['vs_peak_pct']:>+7.2f}% [{emoji}]")
        if r["status"] == "FLAGGED": flagged.append(m)
        if r["status"] == "CRITICAL": critical.append(m)

    print(f"\nFlagged ({DRAWDOWN_FLAG*100:+.0f}%): {flagged}")
    print(f"Critical ({DRAWDOWN_CRITICAL*100:+.0f}%): {critical}")

    # Critical: re-roda matrix imediato
    reval_results = []
    if critical:
        print(f"\nTriggering revalidation pra {len(critical)} CRITICAL markets...")
        for m in critical:
            print(f"\n--- revalidating {m} ---")
            r = trigger_revalidation_for_market(m)
            reval_results.append(r)
            if r.get("best"):
                b = r["best"]
                print(f"  current sharpe={b['sharpe']:+.2f} dsr={b['dsr']:.2f}")
                still_passes = b["sharpe"] >= 1.5 and b["dsr"] >= 0.65
                print(f"  still passes gate: {still_passes}")

    # Replacement scan se houver flagged ou critical
    replacements = []
    if flagged or critical:
        replacements = scan_replacement_candidates(set(markets))
        print(f"\n{'='*70}\nREPLACEMENT CANDIDATES (top {TOP_REPLACEMENTS})\n{'='*70}")
        for r in replacements:
            print(f"  {r['market']:<14} ${r['price']:>10.4f} 24h={r['pct24']:>+6.2f}% vol=${r['vol']/1e3:>7.0f}K cat={r['category']:<14} dist200={r.get('dist200','?')} mom20={r.get('mom20','?')}")

    # Auto-demote tracking (NEW 2026-05-19)
    demote_candidates = []
    try:
        from tier_a_flag_tracker import record_flags, get_demote_candidates
        record_flags(flagged, critical)
        demote_candidates = get_demote_candidates(threshold=3)
        if demote_candidates:
            print(f"\n[DEMOTE] {len(demote_candidates)} markets com 3+ FLAG consecutivos: {demote_candidates}")
    except Exception as e:
        print(f"[WARN] flag_tracker fail: {e}")

    out = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "markets_checked": len(markets),
        "flagged": flagged,
        "critical": critical,
        "demote_candidates": demote_candidates,
        "drawdowns": results,
        "revalidation_critical": reval_results,
        "replacement_candidates": replacements,
    }
    out_path = JOURNAL / f"tier_a_drawdown_{datetime.now().strftime('%Y_%m_%d')}.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_path.name}")


if __name__ == "__main__":
    main()
