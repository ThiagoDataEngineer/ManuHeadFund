"""
weekly_revalidation.py -- Re-valida markets ja em whitelist semanalmente.

Roda apos weekly_discovery no cron domingo. Pra cada market em Tier A/B:
1. Atualiza candles (append latest 30d)
2. Re-roda cross_asset_matrix com mesmos params do whitelist
3. Compara: current_sharpe vs stored_sharpe -> degradation_pct
4. Flag se:
   - Nao passa mais gate strict (Sharpe<1.5 ou DSR<0.65)
   - OU degradacao >30% (edge esta sumindo)
5. Output: journal/weekly_revalidation_<DATE>.json com flags
6. Cron lera output e enviara Telegram alerta

Conservador: NAO demote automatico. Apenas sinaliza pra user revisar.
"""
import json, sys, time
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

SCRIPT = Path(__file__).resolve().parent
ROOT = SCRIPT.parent
sys.path.insert(0, str(SCRIPT))

CANDLES_DIR = ROOT / "journal" / "candles_coinex"
JOURNAL_DIR = ROOT / "journal"

DEGRADATION_PCT_FLAG = 0.30   # >30% degradacao = flag
SHARPE_MIN_TIER_A = 1.5
SHARPE_MIN_TIER_B = 1.5
DSR_MIN_TIER_A = 0.65        # mais lenient que promote (0.95) -- so flag obvio loss


def fetch(url, timeout=15):
    try:
        with urlopen(Request(url, headers={"User-Agent":"rv/1"}), timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception as e:
        return {"_error": str(e)}


def load_latest_whitelist():
    files = sorted(JOURNAL_DIR.glob("per_asset_whitelist_*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not files: return None, None
    with open(files[0], "r", encoding="utf-8") as f:
        return json.load(f), files[0]


def refresh_candles(market):
    """Append latest 30d candles ao existente (ou full collect se nao tem)."""
    path = CANDLES_DIR / f"{market}_1day.json"
    if path.exists():
        with open(path, "r", encoding="utf-8") as f:
            existing = json.load(f)
    else:
        existing = []
    # Fetch 60 latest (overlap pra dedupe)
    d = fetch(f"https://api.coinex.com/v2/spot/kline?market={market}&period=1day&limit=60")
    data = d.get("data") or []
    if not data: return existing
    new_candles = [{"ts": k.get("created_at"), "open":float(k["open"]),"high":float(k["high"]),"low":float(k["low"]),"close":float(k["close"]),"volume":float(k.get("volume",0))} for k in data]
    for c in new_candles:
        if isinstance(c["ts"], (int,float)):
            c["ts"] = datetime.fromtimestamp(int(c["ts"])/1000, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")
    # Dedupe by ts
    existing_ts = {c["ts"] for c in existing}
    for c in new_candles:
        if c["ts"] not in existing_ts:
            existing.append(c)
    existing.sort(key=lambda x: x["ts"])
    with open(path, "w", encoding="utf-8") as f:
        json.dump(existing, f, ensure_ascii=False)
    return existing


def revalidate_market(entry):
    """entry = whitelist row {market, sharpe, dsr, stop_atr, target_atr, ...}"""
    market = entry["market"]
    if "BITSTAMP" in market: return None  # skip bitstamp (precisa fonte diferente)
    print(f"\n--- {market} ---")
    candles = refresh_candles(market)
    if len(candles) < 250:
        return {"market": market, "status": "insufficient_history", "candles": len(candles)}
    try:
        from run_cross_asset_matrix import process_pair
        # Invalidate entries cache pra forcar re-detect com candles atualizados
        entries_dir = JOURNAL_DIR / "entries_coinex"
        for f in [entries_dir/f"entries_{market}.json", entries_dir/f"alldicts_{market}.json"]:
            if f.exists(): f.unlink()

        candles_path = CANDLES_DIR / f"{market}_1day.json"
        r = process_pair(market, candles_path)
        if not r.get("best"):
            return {"market": market, "status": "no_best", "raw": r}

        b = r["best"]
        prior_sharpe = float(entry.get("sharpe", 0))
        current_sharpe = float(b["sharpe"])
        degradation = (prior_sharpe - current_sharpe) / abs(prior_sharpe) if prior_sharpe > 0 else 0
        still_passes = (current_sharpe >= SHARPE_MIN_TIER_A and float(b.get("dsr",0)) >= DSR_MIN_TIER_A)

        status = "STABLE"
        if not still_passes:
            status = "FAILING_GATE"
        elif degradation > DEGRADATION_PCT_FLAG:
            status = "DEGRADED"

        result = {
            "market": market,
            "tier": entry.get("tier", "?"),
            "status": status,
            "prior_sharpe": round(prior_sharpe, 2),
            "current_sharpe": round(current_sharpe, 2),
            "degradation_pct": round(degradation*100, 1),
            "current_dsr": round(float(b.get("dsr", 0)), 2),
            "current_pbo": round(r.get("pbo",{}).get("pbo", 1.0) if r.get("pbo") else 1.0, 2),
            "best_params": f"s{b['stop_atr']}/t{b['target_atr']}",
            "n_trades": b.get("n_trades", 0),
        }
        print(f"  {status} | prior_sharpe={prior_sharpe:.2f} -> current={current_sharpe:.2f} ({degradation*100:+.1f}%)")
        return result
    except Exception as e:
        print(f"  err: {e}")
        return {"market": market, "status": "error", "error": str(e)}


def main():
    print("=" * 70)
    print("Weekly Revalidation -- whitelist markets")
    print("=" * 70)
    t0 = time.time()

    wl, wl_path = load_latest_whitelist()
    if not wl:
        print("[ERR] Whitelist nao encontrada"); return
    print(f"[load] {wl_path.name} version={wl.get('version','?')}")

    targets = wl.get("TIER_A_LIVE", []) + wl.get("TIER_B_PAPER", [])
    # Filtra duplicatas (BTCUSDT pode aparecer em A e B)
    seen = set(); unique_targets = []
    for e in targets:
        m = e.get("market")
        if m and m not in seen:
            seen.add(m); unique_targets.append(e)

    print(f"[targets] {len(unique_targets)} markets pra re-validar (Tier A + B)")

    results = []
    for entry in unique_targets:
        r = revalidate_market(entry)
        if r: results.append(r)

    elapsed = time.time() - t0
    print(f"\n[done] {elapsed:.1f}s | {len(results)} re-validados")

    # Categorize
    stable = [r for r in results if r.get("status") == "STABLE"]
    degraded = [r for r in results if r.get("status") == "DEGRADED"]
    failing = [r for r in results if r.get("status") == "FAILING_GATE"]
    errors = [r for r in results if r.get("status") in ("error","no_best","insufficient_history")]

    print(f"\n{'='*70}\nRESUMO REVALIDATION\n{'='*70}")
    print(f"  STABLE       : {len(stable)} -> {[r['market'] for r in stable]}")
    print(f"  DEGRADED     : {len(degraded)} -> {[r['market'] for r in degraded]}")
    print(f"  FAILING_GATE : {len(failing)} -> {[r['market'] for r in failing]}")
    if errors:
        print(f"  ERRORS       : {len(errors)} -> {[(r['market'], r.get('status')) for r in errors]}")

    out = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "whitelist_source": wl_path.name,
        "n_revalidated": len(results),
        "stable": [r["market"] for r in stable],
        "degraded": [r["market"] for r in degraded],
        "failing_gate": [r["market"] for r in failing],
        "errors": [r["market"] for r in errors],
        "results": results,
        "elapsed_sec": round(elapsed,1),
    }
    out_path = JOURNAL_DIR / f"weekly_revalidation_{datetime.now().strftime('%Y_%m_%d')}.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_path.name}")

    if degraded or failing:
        print(f"\n⚠️  ATENCAO: {len(degraded)+len(failing)} markets precisam revisao manual")


if __name__ == "__main__":
    main()
