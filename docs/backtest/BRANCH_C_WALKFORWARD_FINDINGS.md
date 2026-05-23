# Branch C — Walk-Forward Retrain Findings (2026-05-22)

> **Pattern**: doc-alongside-TDD. Follow-up de [BRANCH_A_V2_EXPANDED_FINDINGS.md](BRANCH_A_V2_EXPANDED_FINDINGS.md)
> com walk-forward retrain — testa se thresholds adaptativos rescue edge.

## Objetivo

Branch A/B confirmaram edge negativo com thresholds fixos. Question: thresholds
ótimos mudam por regime? Walk-forward retrain pode rescue edge?

## Methodology

**Walk-Forward Splits**:
- K-folds: 5
- Embargo: 14 dias
- Valid folds: 2

**Threshold Grid Search**:
- Tier S: [80, 85, 90, 95]
- Objective: maximizar lift em train set

**Baseline**:
- Fixed thresholds: Tier S=85

## Results

### Fold-by-Fold

| Fold | Test Period | N Test | Opt Thresh | Test Lift (Opt) | Test Lift (Base) | Δ |
|------|-------------|--------|------------|-----------------|------------------|---|
| 4 | 2025-12-23 → 2026-01-31 | 31 | 80 | +0.0% | +0.0% | +0.0% |
| 5 | 2026-01-31 → 2026-05-18 | 32 | 80 | +0.0% | +0.0% | +0.0% |


### Aggregate

| Métrica | Valor |
|---------|-------|
| **Mean test lift (optimized)** | **+0.0%** |
| **Mean test lift (baseline)** | **+0.0%** |
| **Mean Δ (opt - baseline)** | **+0.0%** |
| **Positive Δ folds** | **0/2** |

## Verdict

**❌ RETRAIN DOES NOT HELP — edge não existe**

**Recommendation**: Aceitar WSS como risk-control only, não auto-trade

## Implicações

### ❌ Retrain Does Not Help

Thresholds adaptativos NÃO melhoram edge. Implicações:

1. **Edge não existe**: Mesmo com thresholds ótimos por regime
2. **WSS risk-control only**: Não usar para auto-trade
3. **Pivot necessário**: Explorar outras strategies

### Próximos Passos

1. Aceitar WSS posture defensiva
2. Freeze auto-trade WSS
3. Explorar DCA mecânico BTC ou outras strategies


## Artefatos

- Script: [backtest/branch_c_walkforward_retrain.py](../../backtest/branch_c_walkforward_retrain.py)
- Results: [journal/branch_c_walkforward_retrain_results.json](../../journal/branch_c_walkforward_retrain_results.json)
- Doc: este arquivo
- Predecessor: [BRANCH_A_V2_EXPANDED_FINDINGS.md](BRANCH_A_V2_EXPANDED_FINDINGS.md)

---

**Timestamp**: 2026-05-22T23:41:04.728759  
**Author**: Claude Sonnet 4.5
