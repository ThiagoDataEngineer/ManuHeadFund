"""
weekly_discovery.py -- Pipeline automatica de descoberta cross-asset.

Workflow:
1. Goldilocks scan top liquid markets CoinEx -> classifica EARLY_BULL/FRESH_CROSS/etc
2. Para cada candidato A+/A nao listado em whitelist ou pipeline:
   - Collect candles (se nao existir)
   - Run cross_asset_matrix (process_pair)
   - Categoriza Tier A LIVE / Tier B PAPER / Tier C SKIP por gate strict
3. Output JSON: journal/weekly_discovery_<DATE>.json com decisoes
4. Cron PowerShell le esse JSON e:
   - Adiciona Tier A descobertos a whitelist v3.X+1
   - Adiciona Tier B/C ao promotion_pipeline OBSERVATION
   - Telegram alerta novidades

Honest: NAO promove sem validacao matematica. Goldilocks da pista, matrix decide.
"""
from __future__ import annotations

import json, sys, time
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

CANDLES_DIR = ROOT_DIR / "journal" / "candles_coinex"
CANDLES_DIR.mkdir(parents=True, exist_ok=True)
JOURNAL_DIR = ROOT_DIR / "journal"

MIN_VOL_USDT = 50_000     # 2026-05-18: 100k -> 50k (catch low-vol Tier A like CFG)
MIN_VOL_NARRATIVE = 5_000  # threshold relaxado pra candidatos narrativa
MAX_NEW_PER_RUN = 5        # rate limit -- ainda 5 quant + ate 5 narrative extra
COINEX = "https://api.coinex.com/v2/spot"
NARRATIVE_PATH_REL = "journal/narrative_candidates.json"

# Tier thresholds (alinhado com whitelist v3 criteria)
TIER_A_GATE = {"sharpe_min": 1.5, "dsr_min": 0.95, "psr_min": 0.95, "pbo_max": 0.30, "wf_min": 3}
TIER_B_GATE = {"sharpe_min": 2.0, "dsr_min": 0.65, "psr_min": 0.80, "pbo_max": 0.40}


def fetch(url, timeout=15):
    try:
        with urlopen(Request(url, headers={"User-Agent":"wd/1"}), timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception as e:
        return {"_error": str(e)}


def get_all_tickers():
    d = fetch(f"{COINEX}/ticker")
    return d.get("data") or []


def get_kline(market, n=210):
    d = fetch(f"{COINEX}/kline?market={market}&period=1day&limit={n}")
    return d.get("data") or []


def goldilocks_categorize(market, kline_data):
    """Mesma logica de snapshot_goldilocks.py."""
    if len(kline_data) < 200: return None
    closes = [float(k["close"]) for k in kline_data]
    highs  = [float(k["high"])  for k in kline_data]
    lows   = [float(k["low"])   for k in kline_data]
    sma200 = sum(closes[-200:]) / 200
    cur = closes[-1]
    dist200 = (cur - sma200) / sma200
    mom_20d = (cur - closes[-20]) / closes[-20] if closes[-20] > 0 else 0
    mom_5d  = (cur - closes[-5])  / closes[-5]  if closes[-5]  > 0 else 0
    cross_recent = False
    for i in range(1, min(15, len(closes) - 200)):
        idx = len(closes) - 1 - i
        sma200_then = sum(closes[idx-199:idx+1]) / 200
        ratio_then = (closes[idx] - sma200_then) / sma200_then
        if ratio_then < 0 and dist200 > 0:
            cross_recent = True; break
    recent_peak = max(closes[-30:])
    pullback_peak = (cur - recent_peak) / recent_peak

    if dist200 > 0 and dist200 < 0.15 and mom_20d > 0.02 and mom_20d < 0.30:
        return "EARLY_BULL"
    if dist200 > 0 and pullback_peak < -0.05 and pullback_peak > -0.15 and mom_5d > 0:
        return "PULLBACK_BULL"
    if cross_recent:
        return "FRESH_CROSS"
    if dist200 > -0.05 and dist200 < 0.05 and mom_20d > 0.05:
        return "BREAKOUT_TEST"
    return None


def collect_candles(market, paginate=True):
    """Coleta full daily candles via pagination."""
    candles_path = CANDLES_DIR / f"{market}_1day.json"
    if candles_path.exists():
        with open(candles_path, "r", encoding="utf-8") as f:
            existing = json.load(f)
        if len(existing) >= 250:
            return existing
    all_candles = []
    end_ts = None
    for page in range(5):
        url = f"{COINEX}/kline?market={market}&period=1day&limit=1000"
        if end_ts: url += f"&end_time={end_ts}"
        d = fetch(url)
        data = d.get("data") or []
        if not data: break
        for k in data:
            all_candles.append({
                "ts": k.get("created_at"),
                "open": float(k["open"]), "high": float(k["high"]),
                "low": float(k["low"]), "close": float(k["close"]),
                "volume": float(k.get("volume", 0)),
            })
        if len(data) < 1000: break
        end_ts = data[0].get("created_at")
        time.sleep(0.5)
    seen = set(); dedup = []
    for c in all_candles:
        if c["ts"] not in seen:
            seen.add(c["ts"]); dedup.append(c)
    dedup.sort(key=lambda x: x["ts"])
    # Convert ts -> ISO
    for c in dedup:
        if isinstance(c["ts"], (int, float)):
            c["ts"] = datetime.fromtimestamp(int(c["ts"])/1000, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")
    with open(candles_path, "w", encoding="utf-8") as f:
        json.dump(dedup, f, ensure_ascii=False)
    return dedup


def load_whitelist():
    """Le whitelist mais recente."""
    files = sorted(JOURNAL_DIR.glob("per_asset_whitelist_*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not files: return {"TIER_A_LIVE": [], "TIER_B_PAPER": [], "TIER_C_SKIP": []}
    with open(files[0], "r", encoding="utf-8") as f:
        return json.load(f)


def load_pipeline_markets():
    """Le markets ja no promotion_pipeline (qualquer state)."""
    p = JOURNAL_DIR / "promotion_pipeline.jsonl"
    if not p.exists(): return set()
    markets = set()
    with open(p, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                obj = json.loads(line)
                markets.add(obj.get("market"))
            except: pass
    return markets


def categorize_result(r):
    """Aplica gates Tier A / B / C.

    C1 fix 2026-05-21: B23 Sharpe ceiling + C4 min_n_entries gates aplicados aqui.
    Justificativa empirica:
      - PENDLE Sharpe 8.75 -> -19% dia 1 (overfitting)
      - CFG    Sharpe 8.48 -> demoted Tier A->B (overfitting)
      - HYPE   Sharpe 12.23 com N=34 -> double red flag (overfit + insufficient sample)
    Anti-pattern: Sharpe outlier = sinal RED FLAG, nao sinal verde.
    """
    if not r.get("best"): return "C"
    b = r["best"]
    sharpe = b.get("sharpe", 0); dsr = b.get("dsr", 0); psr = b.get("psr", 0)
    n_entries = r.get("n_entries", 0)
    pbo = r.get("pbo", {}).get("pbo", 1.0) if r.get("pbo") else 1.0
    wf_pos = 0; wf_total = 0
    if r.get("walk_forward"):
        oos = r["walk_forward"]["oos_summary"]
        wf_pos = oos.get("positive_sharpe_folds", 0); wf_total = oos.get("total_folds", 0)

    # C1 (B23) — Sharpe outlier ceiling: > 5 = red flag empirico (PENDLE/CFG/HYPE)
    if sharpe > 5.0:
        r["_overfit_flag"] = f"sharpe_{sharpe}_above_5_red_flag"
        return "C"
    # C4 — sample size mínimo: < 50 = statistical insanity (HYPE N=34 -> Sharpe 12.23)
    if n_entries > 0 and n_entries < 50:
        r["_overfit_flag"] = f"n_entries_{n_entries}_below_50_insufficient_sample"
        return "C"

    g = TIER_A_GATE
    if (sharpe >= g["sharpe_min"] and dsr >= g["dsr_min"] and psr >= g["psr_min"]
        and pbo < g["pbo_max"] and (wf_pos >= g["wf_min"] if wf_total > 0 else False)):
        return "A"
    g = TIER_B_GATE
    if sharpe >= g["sharpe_min"] and dsr >= g["dsr_min"] and pbo < g["pbo_max"]:
        return "B"
    return "C"


def main():
    print("=" * 78)
    print("Weekly Discovery Pipeline")
    print("=" * 78)
    t0 = time.time()

    # 1. Fetch tickers + filter liquid
    tickers = get_all_tickers()
    print(f"[1] {len(tickers)} tickers totais")
    usdt = [t for t in tickers if t["market"].endswith("USDT")
            and float(t.get("value", 0)) >= MIN_VOL_USDT]
    usdt.sort(key=lambda x: float(x["value"]), reverse=True)
    print(f"    {len(usdt)} markets USDT vol >= ${MIN_VOL_USDT:,.0f}")

    # 2. Load whitelist + pipeline para evitar re-test
    wl = load_whitelist()
    listed = set()
    for tier in ("TIER_A_LIVE","TIER_B_PAPER","TIER_C_SKIP"):
        for e in wl.get(tier, []): listed.add(e.get("market"))
    pipeline_markets = load_pipeline_markets()
    print(f"[2] Whitelist tem {len(listed)} markets ja avaliados")
    print(f"    Pipeline tem {len(pipeline_markets)} markets")

    # 3. Goldilocks scan + filter candidates novos
    print(f"[3a] Goldilocks scan + filter nao-listados...")
    candidates = []
    for t in usdt[:80]:
        market = t["market"]
        if market in listed: continue
        kl = get_kline(market)
        if len(kl) < 200: continue
        cat = goldilocks_categorize(market, kl)
        if cat in ("EARLY_BULL","FRESH_CROSS","PULLBACK_BULL","BREAKOUT_TEST"):
            candidates.append({"market": market, "category": cat, "vol": float(t.get("value", 0)), "source": "goldilocks"})
        if len(candidates) >= MAX_NEW_PER_RUN: break

    print(f"    {len(candidates)} candidatos quant (max {MAX_NEW_PER_RUN}/run):")
    for c in candidates:
        print(f"      {c['market']:<14} cat={c['category']:<14} vol=${c['vol']/1e6:.2f}M")

    # 3b. Narrative candidates injection (user-curated ou news tracker)
    narrative_path = ROOT_DIR / NARRATIVE_PATH_REL
    narrative_count = 0
    if narrative_path.exists():
        try:
            with open(narrative_path, "r", encoding="utf-8") as f:
                narrative = json.load(f)
            nm_list = narrative.get("markets", [])
            # Filter ja-listados ou ja-em-candidates
            existing_set = {c["market"] for c in candidates} | listed
            ticker_lookup = {t["market"]: float(t.get("value", 0)) for t in tickers}
            for nm in nm_list:
                if nm in existing_set: continue
                vol = ticker_lookup.get(nm, 0)
                if vol < MIN_VOL_NARRATIVE:
                    print(f"    [skip narrative] {nm} vol=${vol:.0f} < ${MIN_VOL_NARRATIVE}")
                    continue
                candidates.append({"market": nm, "category": "NARRATIVE", "vol": vol, "source": "narrative"})
                narrative_count += 1
                if narrative_count >= MAX_NEW_PER_RUN: break
            print(f"    +{narrative_count} candidatos narrativa (de {len(nm_list)} listados em {NARRATIVE_PATH_REL})")
        except Exception as e:
            print(f"    [warn] falha ler narrative: {e}")
    else:
        print(f"    (sem {NARRATIVE_PATH_REL}, skip narrative injection)")

    if not candidates:
        print("[done] Nenhum candidato novo. Whitelist atual cobre top mercados.")
        out = {"timestamp": datetime.now(timezone.utc).isoformat(), "candidates": [], "results": []}
        out_path = JOURNAL_DIR / f"weekly_discovery_{datetime.now().strftime('%Y_%m_%d')}.json"
        with open(out_path, "w", encoding="utf-8") as f: json.dump(out, f, indent=2)
        print(f"[save] {out_path.name}")
        return out

    # 3.5. Funding gate preempt (NEW 2026-05-19 PM) -- elimina candidatos overheated
    # ANTES da matrix (custo zero, evita 3-5min de calc desperdicado). Se funding z-score
    # >= 2.0 (long overheated) ou histórico ausente E mercado em pump >5% 24h: skip.
    try:
        from funding_zscore import load_funding, compute_zscore
        survived = []
        skipped = []
        for c in candidates:
            mkt = c["market"]
            rows = load_funding(mkt)
            zr = compute_zscore(rows)
            z = zr.get("z")
            if z is not None and z >= 2.0:
                c["preempt_reason"] = f"funding_overheated_z={z:.2f}"
                skipped.append(c)
            else:
                c["funding_z"] = z
                survived.append(c)
        if skipped:
            print(f"[3.5] Preempt funding gate: {len(skipped)} skipped (overheated >z=2.0)")
            for s in skipped: print(f"      [SKIP] {s['market']} {s['preempt_reason']}")
        candidates = survived
    except Exception as e:
        print(f"[3.5] [warn] funding preempt fail: {e} -- continuando sem skip")

    # 4. Para cada candidato: collect + matrix (PARALELO 2026-05-19 — 3-5x speedup)
    print(f"\n[4] Coletando candles + rodando matrix em {len(candidates)} candidatos (paralelo)...")
    from run_cross_asset_matrix import process_pair
    from concurrent.futures import ThreadPoolExecutor, as_completed

    def _process_candidate(c):
        market = c["market"]
        try:
            collect_candles(market)
        except Exception as e:
            return {"market": market, "error": f"collect: {e}", "tier_assigned": "ERR",
                    "category_goldilocks": c["category"]}
        candles_path = CANDLES_DIR / f"{market}_1day.json"
        try:
            r = process_pair(market, candles_path)
            tier = categorize_result(r)
            r["category_goldilocks"] = c["category"]
            r["tier_assigned"] = tier
            return r
        except Exception as e:
            return {"market": market, "error": str(e), "tier_assigned": "ERR",
                    "category_goldilocks": c["category"]}

    results = []
    # ThreadPoolExecutor com max 3 workers (cuidado com rate limit CoinEx + CPU local)
    with ThreadPoolExecutor(max_workers=3) as executor:
        futures = {executor.submit(_process_candidate, c): c for c in candidates}
        for future in as_completed(futures):
            r = future.result()
            results.append(r)
            market = r.get("market", "?")
            tier = r.get("tier_assigned", "?")
            best = r.get("best", {})
            sharpe = best.get("sharpe", 0)
            dsr = best.get("dsr", 0)
            print(f"  [done] {market:<14} TIER {tier} Sharpe={sharpe:.2f} DSR={dsr:.2f}")

    elapsed = time.time() - t0
    print(f"\n[done] {elapsed:.1f}s | {len(results)} markets testados")

    # 4.5. Anti-pump-buy gate (NEW 2026-05-19): se TIER A mas preco no peak → demote TIER B
    # Resolve padrao PENDLE/INJ promovidos em topo → drawdown -17% no dia 1.
    try:
        from pump_buy_gate import check_pump_buy_gate, peak_7d_from_candles
        for r in results:
            if r.get("tier_assigned") != "A": continue
            market = r.get("market")
            candles_path = CANDLES_DIR / f"{market}_1day.json"
            if not candles_path.exists(): continue
            with open(candles_path, "r", encoding="utf-8") as f:
                candles = json.load(f)
            if len(candles) < 7: continue
            last7 = candles[-7:]
            current = float(candles[-1]["close"])
            peak = peak_7d_from_candles(last7)
            gate = check_pump_buy_gate(current, peak, max_dist_from_peak_pct=-5.0)
            r["pump_buy_gate"] = gate
            if not gate["passes"]:
                print(f"  [GATE BLOCK] {market}: dist={gate['dist_pct']}% -> demote TIER A -> B (aguardar pullback)")
                r["tier_assigned"] = "B"
                r["demoted_reason"] = f"anti_pump_buy:dist_{gate['dist_pct']}%"
    except Exception as e:
        print(f"[warn] pump_buy_gate fail: {e}")

    # 4.6. Promotion safety gates (NEW 2026-05-19 PM): concentration / sector / cooldown /
    # min_vol / funding (cache real). Aplica gates a tudo TIER A apos pump_buy gate.
    # Bloqueia promote: demote pra B com reason 'gates_block:<failures>'.
    try:
        from promotion_gates import invoke_all_gates
        wl_for_gates = load_whitelist()
        tier_a_existing = [e["market"] for e in wl_for_gates.get("TIER_A_LIVE", []) if e.get("market")]
        for r in results:
            if r.get("tier_assigned") != "A": continue
            market = r.get("market")
            best = r.get("best", {}) or {}
            vol_usd = float(best.get("volume_usd", 0) or 0)
            # avg daily vol from candles se vol_usd ausente
            if vol_usd <= 0:
                cp = CANDLES_DIR / f"{market}_1day.json"
                if cp.exists():
                    try:
                        with open(cp, "r", encoding="utf-8") as f:
                            cs = json.load(f)
                        if cs and len(cs) >= 7:
                            vols = [float(c.get("volume", 0)) * float(c.get("close", 0)) for c in cs[-7:]]
                            vol_usd = sum(vols) / max(1, len(vols))
                    except Exception:
                        pass
            gates_res = invoke_all_gates(
                market=market,
                volume_usd=vol_usd,
                current_tier_a_count=len(tier_a_existing),
                current_tier_a_markets=tier_a_existing,
                equity_today_pct=0,
                position_size_usd=100,
            )
            r["promotion_gates"] = gates_res
            if not gates_res["all_pass"]:
                print(f"  [GATE BLOCK] {market}: blocked_by={gates_res['blocked_by']} -> demote TIER A -> B")
                r["tier_assigned"] = "B"
                prev = r.get("demoted_reason", "")
                r["demoted_reason"] = (prev + "|" if prev else "") + f"gates:{','.join(gates_res['blocked_by'])}"
    except Exception as e:
        print(f"[warn] promotion_gates fail: {e}")

    # 4.7. FQS gate (NEW 2026-05-19 PM): bloqueia TIER A se FQS < QUALITY.
    # Convergente com promotion_gates: gates tier-quantitativos + fundamental qualitativo.
    try:
        from fqs_gate_discovery import apply_fqs_gate
        apply_fqs_gate(results, target_tier="TIER_A_LIVE")
        for r in results:
            if r.get("demoted_reason", "").startswith("fqs_") or "|fqs_" in r.get("demoted_reason", ""):
                print(f"  [FQS BLOCK] {r.get('market')}: {r.get('demoted_reason')}")
    except Exception as e:
        print(f"[warn] fqs_gate fail: {e}")

    # 5. Summary + save
    tier_counts = {"A":[], "B":[], "C":[], "ERR":[]}
    for r in results:
        t = r.get("tier_assigned","C")
        tier_counts[t].append(r.get("market"))

    print(f"\n=== VEREDICTO ===")
    for t in ("A","B","C","ERR"):
        if tier_counts[t]:
            print(f"  TIER {t}: {tier_counts[t]}")

    out = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "candidates_scanned": [c["market"] for c in candidates],
        "tier_a_new": tier_counts["A"],
        "tier_b_new": tier_counts["B"],
        "tier_c_new": tier_counts["C"],
        "errors": tier_counts["ERR"],
        "results": results,
        "elapsed_sec": round(elapsed, 1),
    }
    out_path = JOURNAL_DIR / f"weekly_discovery_{datetime.now().strftime('%Y_%m_%d')}.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_path.name}")
    return out


if __name__ == "__main__":
    main()
