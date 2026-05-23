"""phase1_diagnostic.py -- Walk-forward + Adversarial validation CURRENT predicate.

Phase 1 do Chained A/B v6.

Tests:
  T1 Walk-forward: WSS weights stability across 4 rolling 1y windows
  T2 Adversarial: train vs OOS classifier accuracy (>0.7 = drift catastrophico)

GATE A: se T2 acc > 0.8 -> predicate DEAD, skip Phase 2+
"""
from __future__ import annotations
import sys, time, json
import numpy as np
sys.path.insert(0, "backtest")
from datetime import datetime, timezone
from collections import defaultdict
from lib_methodology_fast import (load_universe, build_btc_regime_index_fast,
                                   walk_signals_fast, rsi_vectorized)
from wyckoff_spring_score import compute_wss, load_market_quality, months_post_halving


def main():
    t0 = time.time()
    print("=== PHASE 1 — Diagnostic (walk-forward + adversarial) ===\n")

    print("Loading universe...")
    md = load_universe(min_bars=300, include_external=True)
    print(f"  Markets: {len(md)}")

    print("Building BTC regime...")
    btc = build_btc_regime_index_fast()
    print(f"  Days indexed: {len(btc)}")

    print("Walking signals (vectorized)...")
    t1 = time.time()
    all_e = walk_signals_fast(md, btc, window=3)
    sig = [e for e in all_e if e["signal"] == "v" and e["phase"] in ("h20_p3_bear","h24_p3_bear")]
    base = [e for e in all_e if e["signal"] == "_" and e["phase"] in ("h20_p3_bear","h24_p3_bear")]
    print(f"  sig: {len(sig)} | base: {len(base)} | took {time.time()-t1:.1f}s")

    # ─── T1 Walk-forward: hit_rate em 4 rolling 6mo windows ────────────────────
    print("\n=== T1 Walk-forward (hit_rate em 6mo rolling windows) ===")
    # Sort sig by ts
    sig_sorted = sorted(sig, key=lambda e: e["ts"])
    if len(sig_sorted) < 8:
        print(f"  INSUFFICIENT sample ({len(sig_sorted)} < 8)")
    else:
        # Use 6-month windows by ts
        # Group by year-month buckets, then aggregate per 6mo
        from datetime import timedelta
        def parse(ts): return datetime.fromisoformat(ts.replace("Z","+00:00")).replace(tzinfo=timezone.utc)
        # Window bins: split sig into 4 chronological quartiles
        chunks = [sig_sorted[i*len(sig_sorted)//4:(i+1)*len(sig_sorted)//4] for i in range(4)]
        chunk_hits = []
        for i, ch in enumerate(chunks):
            if not ch: continue
            wins = sum(1 for e in ch if (e["outcome"] - 0.6) >= 1.0)
            hit = wins / len(ch) * 100
            chunk_hits.append(hit)
            ts_start = ch[0]["ts"][:10]
            ts_end = ch[-1]["ts"][:10]
            print(f"  Chunk {i+1} ({ts_start} -> {ts_end}): n={len(ch)} hit={hit:.1f}%")
        if len(chunk_hits) >= 2:
            stability = np.std(chunk_hits)
            print(f"  Stability (stddev hit_rates): {stability:.1f}pp  ", end="")
            if stability > 15:
                print("(DRIFT DETECTED — weights instaveis)")
            else:
                print("(stable across windows)")

    # ─── T2 Adversarial: train vs OOS classifier accuracy ──────────────────────
    print("\n=== T2 Adversarial validation (train vs OOS distinguishable?) ===")
    split = int(len(sig_sorted) * 0.80)
    train = sig_sorted[:split]
    holdout = sig_sorted[split:]
    if len(train) < 10 or len(holdout) < 3:
        print(f"  INSUFFICIENT (train={len(train)} holdout={len(holdout)})")
        print("\nGate A: NO_VERDICT (insufficient sample)")
    else:
        # Simple adversarial: usar features (btc_drawdown, btc_vol_20d, mph, outcome)
        # Treina classifier binario distinguir train (0) vs holdout (1).
        # Accuracy > 0.7 = drift confirmado.
        def features(e):
            from wyckoff_spring_score import months_post_halving
            return [
                e["btc_drawdown"] if e["btc_drawdown"] is not None else 0,
                e["btc_vol_20d"] if e["btc_vol_20d"] is not None else 0,
                months_post_halving(e["ts"]),
                e["outcome"],
            ]
        X = np.array([features(e) for e in train + holdout])
        y = np.array([0]*len(train) + [1]*len(holdout))

        # Simple "classifier": logistic regression via numpy (sem sklearn)
        # Threshold-based on each feature, pick best.
        best_acc = 0.5
        best_feat = -1
        for f_idx in range(X.shape[1]):
            vals = X[:, f_idx]
            # Try threshold = median
            thresh = np.median(vals)
            pred = (vals > thresh).astype(int)
            # Try both polarities
            acc_pos = (pred == y).mean()
            acc_neg = ((1 - pred) == y).mean()
            acc = max(acc_pos, acc_neg)
            if acc > best_acc:
                best_acc = acc
                best_feat = f_idx
        feat_names = ["btc_dd", "btc_vol", "mph", "outcome"]
        print(f"  Adversarial accuracy: {best_acc:.2f} (feature {feat_names[best_feat] if best_feat>=0 else 'n/a'})")
        print(f"  Train n={len(train)} | Holdout n={len(holdout)}")
        if best_acc > 0.8:
            print(f"  ⚠️ DRIFT CATASTROFICO (acc > 0.8). GATE A FIRES — predicate DEAD em current regime.")
        elif best_acc > 0.6:
            print(f"  ⚠️ Drift confirmado (acc > 0.6) mas nao catastrofico. Continuar Phase 2.")
        else:
            print(f"  ✓ Train e OOS indistinguiveis (acc < 0.6). Predicate fundamentalmente fraco OU regime estavel.")

    print(f"\n=== Total time: {time.time()-t0:.1f}s ===")


if __name__ == "__main__":
    main()
