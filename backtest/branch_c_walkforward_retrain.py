#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Branch C — Walk-Forward Retrain WSS
====================================

Testa se retreinar WSS thresholds em janelas móveis rescue edge.

Hypothesis:
- Branch A/B falharam com thresholds fixos (Tier S/A/B/C)
- Talvez thresholds ótimos mudem por regime
- Walk-forward retrain: otimiza thresholds em train, testa em OOS

Methodology:
1. Split timeline em K folds (embargo 14d)
2. Para cada fold:
   - Train: otimiza thresholds WSS (grid search)
   - Test: aplica thresholds otimizados em OOS
3. Compara vs baseline (thresholds fixos)

Expected outcome:
- Se edge existe mas thresholds errados: WF retrain > baseline
- Se edge não existe: WF retrain ≈ baseline (ambos ruins)

Author: Claude Sonnet 4.5
Date: 2026-05-22
"""

import json
import sys
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional
import numpy as np
from collections import defaultdict

# Add backtest to path
sys.path.insert(0, str(Path(__file__).parent))


# ============================================================================
# CONFIG
# ============================================================================

JOURNAL_DIR = Path(__file__).parent.parent / "journal"
CACHE_DIR = JOURNAL_DIR / "candles_coinex"

# Walk-forward config
K_FOLDS = 5
EMBARGO_DAYS = 14
MIN_TRAIN_EVENTS = 20  # Mínimo events para otimizar
MIN_TEST_EVENTS = 5    # Mínimo events para testar

# WSS threshold grid search
TIER_S_GRID = [80, 85, 90, 95]  # Tier S threshold
TIER_A_GRID = [60, 65, 70, 75]  # Tier A threshold
TIER_B_GRID = [40, 45, 50, 55]  # Tier B threshold

# Baseline (Branch A v2 fixed thresholds)
BASELINE_THRESHOLDS = {
    "tier_s": 85,
    "tier_a": 70,
    "tier_b": 50
}

# OOS cycles (same as Branch A v2)
OOS_CYCLES = {
    "h20_p3_bear": ("2024-01-01", "2024-12-31"),
    "h24_p3_bear": ("2025-01-01", "2026-05-22")
}


# ============================================================================
# HELPERS
# ============================================================================

def load_market_candles(market: str) -> Optional[List[Dict]]:
    """Load candles from cache."""
    cache_file = CACHE_DIR / f"{market}.json"
    if not cache_file.exists():
        return None
    
    try:
        with open(cache_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data.get("candles", [])
    except Exception as e:
        print(f"⚠️  Error loading {market}: {e}")
        return None


def parse_date(date_str: str) -> datetime:
    """Parse date string to datetime."""
    return datetime.strptime(date_str, "%Y-%m-%d")


def filter_events_by_date(events: List[Dict], start_date: str, end_date: str) -> List[Dict]:
    """Filter events by date range."""
    start_dt = parse_date(start_date)
    end_dt = parse_date(end_date)
    
    filtered = []
    for event in events:
        # Events have "ts" field in ISO format
        event_date_str = event["ts"][:10]  # Extract YYYY-MM-DD
        event_date = parse_date(event_date_str)
        if start_dt <= event_date <= end_dt:
            filtered.append(event)
    
    return filtered


def compute_lift(events: List[Dict], tier_threshold: int) -> float:
    """
    Compute lift for events above tier_threshold.
    
    Lift = hit_rate_tier - hit_rate_baseline
    
    Hit = outcome >= 1.006 (1% gross + 0.6% costs)
    """
    if not events:
        return 0.0
    
    # Filter events by WSS score
    tier_events = [e for e in events if e.get("wss", 0) >= tier_threshold]
    
    if not tier_events:
        return 0.0
    
    # Compute hit rates (outcome >= 1.006 = hit)
    COSTS_PCT = 0.006
    THR_NET = 1.0 + COSTS_PCT
    
    tier_hits = sum(1 for e in tier_events if e.get("outcome", 0) >= THR_NET)
    tier_hit_rate = tier_hits / len(tier_events)
    
    baseline_hits = sum(1 for e in events if e.get("outcome", 0) >= THR_NET)
    baseline_hit_rate = baseline_hits / len(events)
    
    lift = tier_hit_rate - baseline_hit_rate
    return lift


def optimize_thresholds(events: List[Dict]) -> Dict[str, int]:
    """
    Grid search para encontrar thresholds ótimos.
    
    Objective: maximizar lift Tier S (threshold mais alto).
    """
    best_lift = -999
    best_thresholds = BASELINE_THRESHOLDS.copy()
    
    for tier_s in TIER_S_GRID:
        lift = compute_lift(events, tier_s)
        
        if lift > best_lift:
            best_lift = lift
            best_thresholds = {
                "tier_s": tier_s,
                "tier_a": tier_s - 15,  # Tier A = S - 15
                "tier_b": tier_s - 35   # Tier B = S - 35
            }
    
    return best_thresholds


def compute_bootstrap_ci(events: List[Dict], tier_threshold: int, n_bootstrap: int = 1000) -> Tuple[float, float]:
    """
    Bootstrap CI 95% para lift.
    """
    if len(events) < 5:
        return (np.nan, np.nan)
    
    lifts = []
    for _ in range(n_bootstrap):
        sample = np.random.choice(events, size=len(events), replace=True)
        lift = compute_lift(sample.tolist(), tier_threshold)
        lifts.append(lift)
    
    ci_lower = np.percentile(lifts, 2.5)
    ci_upper = np.percentile(lifts, 97.5)
    
    return (ci_lower, ci_upper)


# ============================================================================
# WALK-FORWARD LOGIC
# ============================================================================

def create_walk_forward_splits(events: List[Dict], k_folds: int, embargo_days: int) -> List[Dict]:
    """
    Create walk-forward splits with embargo.
    
    Returns:
        List of dicts with train/test events and date ranges.
    """
    # Sort events by ts
    sorted_events = sorted(events, key=lambda e: e["ts"])
    
    if len(sorted_events) < k_folds * 2:
        return []
    
    # Split into k folds
    fold_size = len(sorted_events) // k_folds
    splits = []
    
    for i in range(k_folds):
        # Test fold
        test_start_idx = i * fold_size
        test_end_idx = (i + 1) * fold_size if i < k_folds - 1 else len(sorted_events)
        test_events = sorted_events[test_start_idx:test_end_idx]
        
        if not test_events:
            continue
        
        # Train: all events BEFORE test (with embargo)
        test_first_date = datetime.fromisoformat(test_events[0]["ts"].replace("Z", "+00:00"))
        embargo_date = test_first_date - timedelta(days=embargo_days)
        
        train_events = [
            e for e in sorted_events[:test_start_idx]
            if datetime.fromisoformat(e["ts"].replace("Z", "+00:00")) < embargo_date
        ]
        
        if len(train_events) < MIN_TRAIN_EVENTS or len(test_events) < MIN_TEST_EVENTS:
            continue
        
        # Date ranges
        train_start = train_events[0]["ts"][:10]
        train_end = train_events[-1]["ts"][:10]
        test_start = test_events[0]["ts"][:10]
        test_end = test_events[-1]["ts"][:10]
        
        splits.append({
            "fold_idx": i,
            "train_events": train_events,
            "test_events": test_events,
            "train_period": (train_start, train_end),
            "test_period": (test_start, test_end),
            "n_train": len(train_events),
            "n_test": len(test_events)
        })
    
    return splits


def run_walk_forward_retrain(all_events: List[Dict]) -> Dict:
    """
    Execute walk-forward retrain.
    
    Returns:
        Results dict with fold-by-fold metrics.
    """
    print("\n" + "="*80)
    print("BRANCH C — WALK-FORWARD RETRAIN")
    print("="*80)
    
    # Create splits
    splits = create_walk_forward_splits(all_events, K_FOLDS, EMBARGO_DAYS)
    
    if not splits:
        return {
            "error": "Insufficient events for walk-forward splits",
            "n_events": len(all_events)
        }
    
    print(f"\n✅ Created {len(splits)} valid folds (embargo {EMBARGO_DAYS}d)")
    
    # Run each fold
    fold_results = []
    
    for split in splits:
        fold_idx = split["fold_idx"]
        train_events = split["train_events"]
        test_events = split["test_events"]
        
        print(f"\n{'─'*80}")
        print(f"FOLD {fold_idx + 1}/{len(splits)}")
        print(f"{'─'*80}")
        print(f"Train: {split['train_period'][0]} → {split['train_period'][1]} ({split['n_train']} events)")
        print(f"Test:  {split['test_period'][0]} → {split['test_period'][1]} ({split['n_test']} events)")
        
        # Optimize thresholds on train
        print("\n🔍 Optimizing thresholds on train set...")
        optimized_thresholds = optimize_thresholds(train_events)
        
        train_lift_opt = compute_lift(train_events, optimized_thresholds["tier_s"])
        train_lift_baseline = compute_lift(train_events, BASELINE_THRESHOLDS["tier_s"])
        
        print(f"   Optimized thresholds: Tier S={optimized_thresholds['tier_s']}")
        print(f"   Train lift (optimized): {train_lift_opt:+.1%}")
        print(f"   Train lift (baseline):  {train_lift_baseline:+.1%}")
        
        # Test on OOS
        print("\n📊 Testing on OOS...")
        test_lift_opt = compute_lift(test_events, optimized_thresholds["tier_s"])
        test_lift_baseline = compute_lift(test_events, BASELINE_THRESHOLDS["tier_s"])
        
        # Bootstrap CI
        ci_opt = compute_bootstrap_ci(test_events, optimized_thresholds["tier_s"], n_bootstrap=1000)
        ci_baseline = compute_bootstrap_ci(test_events, BASELINE_THRESHOLDS["tier_s"], n_bootstrap=1000)
        
        print(f"   Test lift (optimized): {test_lift_opt:+.1%} CI [{ci_opt[0]:+.1%}, {ci_opt[1]:+.1%}]")
        print(f"   Test lift (baseline):  {test_lift_baseline:+.1%} CI [{ci_baseline[0]:+.1%}, {ci_baseline[1]:+.1%}]")
        
        # Delta
        delta = test_lift_opt - test_lift_baseline
        print(f"   Δ (opt - baseline):    {delta:+.1%}")
        
        fold_results.append({
            "fold_idx": fold_idx,
            "train_period": split["train_period"],
            "test_period": split["test_period"],
            "n_train": split["n_train"],
            "n_test": split["n_test"],
            "optimized_thresholds": optimized_thresholds,
            "train_lift_opt": train_lift_opt,
            "train_lift_baseline": train_lift_baseline,
            "test_lift_opt": test_lift_opt,
            "test_lift_baseline": test_lift_baseline,
            "test_ci_opt": ci_opt,
            "test_ci_baseline": ci_baseline,
            "delta": delta
        })
    
    # Aggregate results
    print("\n" + "="*80)
    print("AGGREGATE RESULTS")
    print("="*80)
    
    mean_test_lift_opt = np.mean([f["test_lift_opt"] for f in fold_results])
    mean_test_lift_baseline = np.mean([f["test_lift_baseline"] for f in fold_results])
    mean_delta = np.mean([f["delta"] for f in fold_results])
    
    positive_delta_folds = sum(1 for f in fold_results if f["delta"] > 0)
    
    print(f"\nMean test lift (optimized): {mean_test_lift_opt:+.1%}")
    print(f"Mean test lift (baseline):  {mean_test_lift_baseline:+.1%}")
    print(f"Mean Δ (opt - baseline):    {mean_delta:+.1%}")
    print(f"Positive Δ folds:           {positive_delta_folds}/{len(fold_results)}")
    
    # Verdict
    print("\n" + "="*80)
    print("VERDICT")
    print("="*80)
    
    if mean_delta > 0.05:  # +5pp improvement
        verdict = "✅ RETRAIN HELPS — optimized thresholds rescue edge"
        recommendation = "Deploy adaptive thresholds per regime"
    elif mean_delta > 0:
        verdict = "⚠️  MARGINAL IMPROVEMENT — retrain helps slightly"
        recommendation = "Consider adaptive thresholds, but edge still weak"
    else:
        verdict = "❌ RETRAIN DOES NOT HELP — edge não existe"
        recommendation = "Aceitar WSS como risk-control only, não auto-trade"
    
    print(f"\n{verdict}")
    print(f"Recommendation: {recommendation}")
    
    return {
        "timestamp": datetime.now().isoformat(),
        "k_folds": K_FOLDS,
        "embargo_days": EMBARGO_DAYS,
        "n_valid_folds": len(fold_results),
        "baseline_thresholds": BASELINE_THRESHOLDS,
        "fold_results": fold_results,
        "aggregate": {
            "mean_test_lift_opt": mean_test_lift_opt,
            "mean_test_lift_baseline": mean_test_lift_baseline,
            "mean_delta": mean_delta,
            "positive_delta_folds": positive_delta_folds,
            "total_folds": len(fold_results)
        },
        "verdict": verdict,
        "recommendation": recommendation
    }


# ============================================================================
# MAIN
# ============================================================================

def main():
    """Main execution."""
    print("\n" + "="*80)
    print("BRANCH C — WALK-FORWARD RETRAIN WSS")
    print("="*80)
    print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    # Load all events from Branch A v2
    branch_a_file = JOURNAL_DIR / "branch_a_v2_expanded_results.json"
    
    if not branch_a_file.exists():
        print(f"\n❌ Branch A v2 results not found: {branch_a_file}")
        print("   Run branch_a_v2_expanded.py first")
        return
    
    print(f"\n📂 Loading events from: {branch_a_file.name}")
    
    with open(branch_a_file, "r", encoding="utf-8") as f:
        branch_a_data = json.load(f)
    
    all_events = branch_a_data.get("all_sig_events", [])
    
    if not all_events:
        print("\n❌ No events found in Branch A v2 results")
        return
    
    print(f"✅ Loaded {len(all_events)} significant events")
    
    # Filter to OOS cycles only (same as Branch A v2)
    oos_events = []
    for cycle_name, (start_date, end_date) in OOS_CYCLES.items():
        cycle_events = filter_events_by_date(all_events, start_date, end_date)
        oos_events.extend(cycle_events)
        print(f"   {cycle_name}: {len(cycle_events)} events")
    
    print(f"\n✅ Total OOS events: {len(oos_events)}")
    
    if len(oos_events) < MIN_TRAIN_EVENTS * 2:
        print(f"\n❌ Insufficient OOS events for walk-forward ({len(oos_events)} < {MIN_TRAIN_EVENTS * 2})")
        return
    
    # Run walk-forward retrain
    results = run_walk_forward_retrain(oos_events)
    
    # Save results
    output_file = JOURNAL_DIR / "branch_c_walkforward_retrain_results.json"
    
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    
    print(f"\n💾 Results saved: {output_file.name}")
    
    # Create markdown report
    create_markdown_report(results)
    
    print("\n✅ Branch C complete!")


def create_markdown_report(results: Dict):
    """Create markdown report."""
    report_file = Path(__file__).parent.parent / "docs" / "backtest" / "BRANCH_C_WALKFORWARD_FINDINGS.md"
    
    timestamp = datetime.now().strftime("%Y-%m-%d")
    
    content = f"""# Branch C — Walk-Forward Retrain Findings ({timestamp})

> **Pattern**: doc-alongside-TDD. Follow-up de [BRANCH_A_V2_EXPANDED_FINDINGS.md](BRANCH_A_V2_EXPANDED_FINDINGS.md)
> com walk-forward retrain — testa se thresholds adaptativos rescue edge.

## Objetivo

Branch A/B confirmaram edge negativo com thresholds fixos. Question: thresholds
ótimos mudam por regime? Walk-forward retrain pode rescue edge?

## Methodology

**Walk-Forward Splits**:
- K-folds: {results['k_folds']}
- Embargo: {results['embargo_days']} dias
- Valid folds: {results['n_valid_folds']}

**Threshold Grid Search**:
- Tier S: {TIER_S_GRID}
- Objective: maximizar lift em train set

**Baseline**:
- Fixed thresholds: Tier S={BASELINE_THRESHOLDS['tier_s']}

## Results

### Fold-by-Fold

| Fold | Test Period | N Test | Opt Thresh | Test Lift (Opt) | Test Lift (Base) | Δ |
|------|-------------|--------|------------|-----------------|------------------|---|
"""
    
    for fold in results.get("fold_results", []):
        test_period = f"{fold['test_period'][0]} → {fold['test_period'][1]}"
        opt_thresh = fold['optimized_thresholds']['tier_s']
        lift_opt = fold['test_lift_opt']
        lift_base = fold['test_lift_baseline']
        delta = fold['delta']
        
        content += f"| {fold['fold_idx'] + 1} | {test_period} | {fold['n_test']} | {opt_thresh} | {lift_opt:+.1%} | {lift_base:+.1%} | {delta:+.1%} |\n"
    
    agg = results.get("aggregate", {})
    
    content += f"""

### Aggregate

| Métrica | Valor |
|---------|-------|
| **Mean test lift (optimized)** | **{agg.get('mean_test_lift_opt', 0):+.1%}** |
| **Mean test lift (baseline)** | **{agg.get('mean_test_lift_baseline', 0):+.1%}** |
| **Mean Δ (opt - baseline)** | **{agg.get('mean_delta', 0):+.1%}** |
| **Positive Δ folds** | **{agg.get('positive_delta_folds', 0)}/{agg.get('total_folds', 0)}** |

## Verdict

**{results.get('verdict', 'N/A')}**

**Recommendation**: {results.get('recommendation', 'N/A')}

## Implicações

"""
    
    if agg.get('mean_delta', 0) > 0.05:
        content += """### ✅ Retrain Helps

Thresholds adaptativos melhoram edge significativamente (+5pp+). Implicações:

1. **Deploy adaptive thresholds**: Retreinar thresholds por regime
2. **Regime detection crítico**: Identificar mudanças de regime para retreinar
3. **WSS pode ser auto-trade**: Com thresholds adaptativos

### Próximos Passos

1. Implementar regime detector (MCE-based)
2. Retreinar thresholds automaticamente por regime
3. Testar em paper trade com thresholds adaptativos
"""
    elif agg.get('mean_delta', 0) > 0:
        content += """### ⚠️ Marginal Improvement

Thresholds adaptativos ajudam marginalmente (<5pp). Implicações:

1. **Edge ainda fraco**: Mesmo com thresholds ótimos
2. **Considerar adaptive thresholds**: Mas não é silver bullet
3. **WSS risk-control preferred**: Auto-trade ainda arriscado

### Próximos Passos

1. Aceitar WSS como risk-control
2. Explorar outras predicates (DCA mecânico, etc)
"""
    else:
        content += """### ❌ Retrain Does Not Help

Thresholds adaptativos NÃO melhoram edge. Implicações:

1. **Edge não existe**: Mesmo com thresholds ótimos por regime
2. **WSS risk-control only**: Não usar para auto-trade
3. **Pivot necessário**: Explorar outras strategies

### Próximos Passos

1. Aceitar WSS posture defensiva
2. Freeze auto-trade WSS
3. Explorar DCA mecânico BTC ou outras strategies
"""
    
    content += f"""

## Artefatos

- Script: [backtest/branch_c_walkforward_retrain.py](../../backtest/branch_c_walkforward_retrain.py)
- Results: [journal/branch_c_walkforward_retrain_results.json](../../journal/branch_c_walkforward_retrain_results.json)
- Doc: este arquivo
- Predecessor: [BRANCH_A_V2_EXPANDED_FINDINGS.md](BRANCH_A_V2_EXPANDED_FINDINGS.md)

---

**Timestamp**: {results.get('timestamp', 'N/A')}  
**Author**: Claude Sonnet 4.5
"""
    
    with open(report_file, "w", encoding="utf-8") as f:
        f.write(content)
    
    print(f"📄 Markdown report: {report_file.name}")


if __name__ == "__main__":
    main()
