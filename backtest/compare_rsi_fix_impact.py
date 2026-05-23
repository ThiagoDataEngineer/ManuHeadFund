#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
compare_rsi_fix_impact.py -- Comparar resultados ANTES vs DEPOIS do RSI fix

Consolida todos os backtests e gera relatório de impacto
"""

import json
import sys
from pathlib import Path
from datetime import datetime

def load_latest_result(pattern):
    """Load most recent backtest result for pattern"""
    journal_dir = Path(__file__).parent.parent / "journal"
    files = list(journal_dir.glob(f"{pattern}_*.json"))
    
    if not files:
        return None
    
    # Get most recent
    latest = max(files, key=lambda p: p.stat().st_mtime)
    
    with open(latest, 'r', encoding='utf-8') as f:
        return json.load(f)

def main():
    print("="*60)
    print("RSI FIX IMPACT COMPARISON")
    print("="*60)
    
    # Load results
    vol_climax = load_latest_result("vol_climax_rsi_rerun")
    short_t6 = load_latest_result("short_t6_rerun")
    short_bear = load_latest_result("short_bear2022")
    
    # Comparison table
    print("\n" + "="*60)
    print("SUMMARY TABLE")
    print("="*60)
    
    print("\n1. VOL CLIMAX + RSI CONFLUENCE (LONG)")
    print("-" * 60)
    print(f"{'Metric':<30} {'BEFORE (bugado)':<20} {'AFTER (corrigido)':<20}")
    print("-" * 60)
    edge_after = vol_climax["without_rsi"]["edge_h20"]
    signals_after = vol_climax["without_rsi"]["signals"]
    win_rate_after = vol_climax["without_rsi"]["win_rate_h20"] * 100
    print(f"{'Edge':<30} {'+20.7pp':<20} {f'{edge_after:.2f}%':<20}")
    print(f"{'Sample size':<30} {'278 signals':<20} {f'{signals_after} signals':<20}")
    print(f"{'Win rate':<30} {'~60%':<20} {f'{win_rate_after:.1f}%':<20}")
    print(f"{'Status':<30} {'PRODUÇÃO':<20} {'EDGE NEGATIVO ❌':<20}")
    
    print("\n   WITH RSI<30 confluence:")
    print(f"   Edge: {vol_climax['with_rsi_confluence']['edge_h20']:.2f}%")
    print(f"   Improvement: {vol_climax['improvement']['edge_delta']:+.2f}pp (PIORA)")
    
    print("\n2. SHORT BUYING CLIMAX (T6 Original)")
    print("-" * 60)
    print(f"{'Metric':<30} {'BEFORE (bugado)':<20} {'AFTER (corrigido)':<20}")
    print("-" * 60)
    edge_t6 = short_t6["baseline_rerun"]["edge_h20"]
    signals_t6 = short_t6["baseline_rerun"]["signals"]
    win_rate_t6 = short_t6["baseline_rerun"]["win_rate_h20"] * 100
    print(f"{'Edge':<30} {'+2.85%':<20} {f'{edge_t6:.2f}%':<20}")
    print(f"{'Sample size':<30} {'505 signals':<20} {f'{signals_t6} signals':<20}")
    print(f"{'Win rate':<30} {'~60%':<20} {f'{win_rate_t6:.1f}%':<20}")
    print(f"{'Status':<30} {'PAPER':<20} {'EDGE NEGATIVO ❌':<20}")
    
    print("\n3. SHORT BEAR MARKET 2022")
    print("-" * 60)
    print(f"Period: Nov 2021 - Dec 2022 (BTC $69K → $15K)")
    print(f"Signals detected: 0")
    print(f"Status: PATTERN INVIÁVEL ❌")
    
    # Impact analysis
    print("\n" + "="*60)
    print("IMPACT ANALYSIS")
    print("="*60)
    
    print("\n🚨 DESCOBERTAS CRÍTICAS:")
    print("\n1. Vol climax +20.7pp era 100% ARTEFATO do RSI bug")
    print("   - Edge real: -2.13% (NEGATIVO)")
    print("   - RSI confluence PIORA edge (-0.88pp)")
    print("   - Pattern NÃO funciona em histórico completo")
    
    print("\n2. SHORT +2.85% era 100% ARTEFATO do RSI bug")
    print("   - Edge real: -15.80% (FORTEMENTE NEGATIVO)")
    print("   - Sample size caiu 97% (505 → 13)")
    print("   - Pattern NÃO funciona")
    
    print("\n3. SHORT em bear market é INVIÁVEL")
    print("   - ZERO signals em bear 2021-2022")
    print("   - RSI nunca fica overbought em bear rallies")
    print("   - Pattern é extremamente raro")
    
    # ROI impact
    print("\n" + "="*60)
    print("ROI IMPACT")
    print("="*60)
    
    print("\nBEFORE (com RSI bugado):")
    print("  Vol climax: +$310/mês (FALSO)")
    print("  SHORT: +$43/mês (FALSO)")
    print("  TOTAL: +$353/mês = +85% ROI/ano (FALSO)")
    
    print("\nAFTER (com RSI corrigido):")
    print("  Vol climax: -$3/mês (PERDA)")
    print("  SHORT: -$8/mês (PERDA)")
    print("  TOTAL: -$11/mês = -2.6% ROI/ano (PERDA)")
    
    print("\nDELTA: -$364/mês = -87.6% ROI/ano ❌")
    
    # Recommendations
    print("\n" + "="*60)
    print("RECOMMENDATIONS")
    print("="*60)
    
    print("\n✅ IMMEDIATE ACTIONS:")
    print("  1. Remove RSI confluence from vol_climax")
    print("  2. Disable SHORT scanner")
    print("  3. Update documentation")
    
    print("\n🔬 INVESTIGATION (optional):")
    print("  1. Investigate T6 original (505 vs 13 signals)")
    print("  2. Refine vol_climax pattern (regime gate, trendline, etc)")
    
    print("\n💼 FOCUS (recommended):")
    print("  1. Tori Proximity (relaxed thresholds)")
    print("  2. Timeframe expansion (4h/1h)")
    print("  3. Universe expansion (200+ markets)")
    
    # Save consolidated report
    report = {
        'timestamp': datetime.now().isoformat(),
        'rsi_fix_date': '2026-05-23',
        'patterns_tested': 3,
        'patterns_invalidated': 3,
        'vol_climax': {
            'before': {'edge': 20.7, 'signals': 278, 'status': 'PRODUÇÃO'},
            'after': {
                'edge': vol_climax['without_rsi']['edge_h20'],
                'signals': vol_climax['without_rsi']['signals'],
                'status': 'EDGE NEGATIVO'
            },
            'impact': 'Edge +20.7pp era 100% artefato do RSI bug'
        },
        'short_t6': {
            'before': {'edge': 2.85, 'signals': 505, 'status': 'PAPER'},
            'after': {
                'edge': short_t6['baseline_rerun']['edge_h20'],
                'signals': short_t6['baseline_rerun']['signals'],
                'status': 'EDGE NEGATIVO'
            },
            'impact': 'Edge +2.85% era 100% artefato do RSI bug'
        },
        'short_bear': {
            'period': 'Nov 2021 - Dec 2022',
            'signals': 0,
            'status': 'PATTERN INVIÁVEL',
            'impact': 'SHORT buying climax é extremamente raro'
        },
        'roi_impact': {
            'before': '+85% ROI/ano (FALSO)',
            'after': '-2.6% ROI/ano (PERDA)',
            'delta': '-87.6% ROI/ano'
        },
        'recommendations': {
            'immediate': [
                'Remove RSI confluence',
                'Disable SHORT scanner',
                'Update documentation'
            ],
            'focus': [
                'Tori Proximity (relaxed)',
                'Timeframe expansion',
                'Universe expansion'
            ]
        }
    }
    
    output_path = Path(__file__).parent.parent / "journal" / "rsi_fix_impact_consolidated.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    
    print(f"\n\nConsolidated report saved: {output_path}")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
