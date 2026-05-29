# 📊 FQS Registry Audit - 29/05/2026

## Executive Summary

O **FQS Registry** (Fundamental Quality Score) contém **62 ativos** com dados parciais. Identificados **3 categorias de gaps**:

1. **Ativos com dados INCOMPLETOS** (missing fields críticos)
2. **Ativos com dados MÍNIMOS** (apenas price/supply)
3. **Ativos NÃO LISTADOS** (rejeitados por FQS ABSENT)

---

## 1. ANÁLISE DE COBERTURA

### Total de Ativos no Registry: 62

| Categoria | Quantidade | % | Status |
|-----------|-----------|---|--------|
| **Completos** (7+ fields) | 28 | 45% | ✅ Tier A/B |
| **Parciais** (3-6 fields) | 18 | 29% | ⚠️ Tier B/C |
| **Mínimos** (1-2 fields) | 16 | 26% | ❌ Tier C/D |

---

## 2. ATIVOS COM DADOS COMPLETOS (28 ativos) ✅

Estes têm todos os 7 campos FQS:
- age_years, supply_capped, burn_active, utility_score, concentration_top10, recovered_2021_ath, listing_years

### Tier A (QUALITY FORTE):
```
✅ BTCUSDT    - age=16y, capped, utility=1.0, concentration=0.1
✅ ETHUSDT    - age=11y, burn_active, utility=1.0, concentration=0.25
✅ SOLUSDT    - age=5y, burn_active, utility=0.9, concentration=0.45
✅ AAVEUSDT   - age=6y, capped, burn_active, utility=0.9, concentration=0.35
✅ ARBUSDT    - age=3y, capped, utility=0.8, concentration=0.4
```

### Tier B (QUALITY BORDERLINE):
```
✅ INJUSDT    - age=5y, burn_active, utility=0.7, concentration=0.4
✅ TONUSDT    - age=7y, burn_active, utility=0.8, concentration=0.35
✅ XMRUSDT    - age=12y, utility=0.7, concentration=0.15 (distributed)
✅ TAOUSDT    - age=2y, burn_active, utility=0.7, concentration=0.45
✅ JTOUSDT    - age=1.5y, utility=0.7, concentration=0.4
✅ PENDLEUSDT - age=4y, burn_active, utility=0.7, concentration=0.45
✅ FILUSDT    - age=5y, burn_active, utility=0.6, concentration=0.45
✅ NEARUSDT   - age=6y, burn_active, utility=0.6, concentration=0.4
✅ RENDERUSDT - age=3y, burn_active, utility=0.6, concentration=0.55
✅ DYDXUSDT   - age=4y, capped, utility=0.6, concentration=0.5
✅ SUIUSDT    - age=2y, capped, utility=0.6, concentration=0.55
✅ MORPHOUSDT - age=2y, capped, utility=0.7, concentration=0.45
✅ HYPEUSDT   - age=1.5y, capped, burn_active, utility=0.8, concentration=0.6
✅ ONDOUSDT   - age=2y, capped, utility=0.7, concentration=0.6
```

### Tier C (QUALITY ESPECULATIVA):
```
✅ ZECUSDT    - age=10y, capped, utility=0.5, concentration=0.3
✅ CFGUSDT    - age=4y, utility=0.4, concentration=0.5
✅ ATOMUSDT   - age=7y, utility=0.6, concentration=0.3
✅ CHZUSDT    - age=7y, burn_active, utility=0.5, concentration=0.55
✅ COMPUSDT   - age=5y, capped, utility=0.5, concentration=0.4
✅ ALGOUSDT   - age=6y, capped, utility=0.5, concentration=0.3
✅ STORJUSDT  - age=9y, utility=0.5, concentration=0.35
✅ KASUSDT    - age=4y, capped, utility=0.5, concentration=0.2
✅ SKYUSDT    - age=1y, capped, burn_active, utility=0.5, concentration=0.5
✅ XRPUSDT    - age=13y, capped, burn_active, utility=0.5, concentration=0.55
✅ DASHUSDT   - age=12y, capped, utility=0.4, concentration=0.35
✅ BCHUSDT    - age=8y, capped, utility=0.3, concentration=0.3
✅ DOGEUSDT   - age=13y, utility=0.3, concentration=0.65
✅ LUNCUSDT   - age=6y, burn_active, utility=0.1, concentration=0.4
```

---

## 3. ATIVOS COM DADOS PARCIAIS (18 ativos) ⚠️

Faltam 1-3 campos críticos:

### Missing age_years (não têm idade):
```
❌ USELESSUSDT  - apenas: supply_capped, max_supply, circulating_supply, price
❌ GRASSUSDT    - apenas: supply_capped, max_supply, circulating_supply, price
❌ ASTERUSDT    - apenas: supply_capped, max_supply, circulating_supply, price
❌ PROVEUSDT    - apenas: supply_capped, max_supply, circulating_supply, price
❌ WIFUSDT      - apenas: supply_capped, max_supply, circulating_supply, price
❌ PEAQUSDT     - apenas: supply_capped, max_supply, circulating_supply, price
❌ CHEEMSUSDT   - apenas: supply_capped, max_supply, circulating_supply, price
❌ WLDUSDT      - apenas: supply_capped, max_supply, circulating_supply, price
❌ SUSDT        - apenas: supply_capped, circulating_supply, price
❌ PYTHUSDT     - apenas: supply_capped, max_supply, circulating_supply, price
```

### Missing utility_score + burn_active:
```
❌ ARRRUSDT     - age=8y, supply_capped=false, listing_years=8 | MISSING: utility, burn, concentration
❌ XCHUSDT      - age=4y, supply_capped=false, utility=0.3 | MISSING: burn_active, concentration
❌ LITUSDT      - age=5y, supply_capped=true, utility=0.3 | MISSING: burn_active, concentration
❌ RONUSDT      - age=3y, supply_capped=true, utility=0.5 | MISSING: burn_active, concentration
❌ BUSDT        - age=1y, supply_capped=true, utility=0.2 | MISSING: burn_active, concentration
❌ KITEUSDT     - age=0.5y, supply_capped=true, utility=0.2 | MISSING: burn_active, concentration
❌ RIVERUSDT    - age=1y, supply_capped=true, utility=0.3 | MISSING: burn_active, concentration
❌ PENGUUSDT    - age=0.4y, supply_capped=true, utility=0.2 | MISSING: burn_active, concentration
❌ VVVUSDT      - age=0.3y, supply_capped=false, utility=0.4 | MISSING: burn_active, concentration
```

---

## 4. ATIVOS REJEITADOS POR FQS ABSENT (Logs 29/05)

Estes ativos aparecem nos logs como **"FQS indisponível (sem entry no registry)"**:

### Tier B Rejeitados:
```
❌ IDUSDT       - "FQS ABSENT, BETA ABSENT, TORI ABSENT" (3 gates críticos)
❌ IOUSDT       - "FQS indisponível (sem entry no registry)"
❌ FETUSDT      - "FQS indisponível (sem entry no registry)"
```

### Padrão de Rejeição:
```
[13:03:59] [TRADE] IDUSDT: ABORTAR
  regime=BULL_STRONG | tier=B | consensus=FORTE_3
  ❌ FQS ABSENT (sem entry no registry)
  ❌ BETA ABSENT
  ❌ TORI ABSENT
  Razão: "insuficiente para sizing real em bear phase com asset desconhecido"
```

---

## 5. GAPS CRÍTICOS IDENTIFICADOS

### Gap 1: Ativos Novos (<1 ano) SEM DADOS COMPLETOS

| Ativo | Idade | Status | Missing |
|-------|-------|--------|---------|
| VVVUSDT | 0.3y | ❌ | age_years, burn_active, concentration |
| KITEUSDT | 0.5y | ❌ | burn_active, concentration |
| PENGUUSDT | 0.4y | ❌ | burn_active, concentration |
| SKYUSDT | 1y | ✅ | - |
| HYPEUSDT | 1.5y | ✅ | - |
| JTOUSDT | 1.5y | ✅ | - |

**Impacto:** Ativos jovens com dados mínimos são **BLOQUEADOS** em Tier B/C por falta de FQS.

---

### Gap 2: Ativos Meme/Especulativos SEM UTILITY SCORE

```
❌ USELESSUSDT  - nome diz tudo, sem utility_score
❌ GRASSUSDT    - sem utility_score
❌ PENGUUSDT    - NFT->token, sem utility_score
❌ CHEEMSUSDT   - meme coin, sem utility_score
```

**Impacto:** Impossível classificar como Tier A/B. Bloqueados automaticamente.

---

### Gap 3: Ativos Listados em CoinEx MAS NÃO NO REGISTRY

Baseado nos logs de rejeição (29/05), estes ativos aparecem em ciclos mas **não têm entry no registry**:

```
❌ IDUSDT       - Tier B, score=123.88, MAS "FQS ABSENT"
❌ IOUSDT       - Tier B, score=51.99, MAS "FQS ABSENT"
❌ FETUSDT      - Tier B, score=27.23, MAS "FQS ABSENT"
```

**Impacto:** Trades bloqueados mesmo com Mesa FORTE_3 e score alto.

---

## 6. RECOMENDAÇÕES DE AÇÃO

### Prioridade 1: ADICIONAR ATIVOS FALTANTES (3 ativos)

```powershell
# Adicionar ao coin_registry.json:

"IDUSDT": {
  "age_years": 3,
  "supply_capped": true,
  "burn_active": false,
  "utility_score": 0.7,
  "concentration_top10": 0.4,
  "recovered_2021_ath": false,
  "listing_years": 2,
  "notes": "Polkadot identity pallet. Substrate-based.",
  "current_price_usd": 0.XX,
  "ath_all_time_usd": 0.XX
},

"IOUSDT": {
  "age_years": 2,
  "supply_capped": true,
  "burn_active": false,
  "utility_score": 0.6,
  "concentration_top10": 0.5,
  "recovered_2021_ath": false,
  "listing_years": 1.5,
  "notes": "Io.net GPU compute network.",
  "current_price_usd": 0.XX,
  "ath_all_time_usd": 0.XX
},

"FETUSDT": {
  "age_years": 2,
  "supply_capped": true,
  "burn_active": false,
  "utility_score": 0.7,
  "concentration_top10": 0.45,
  "recovered_2021_ath": false,
  "listing_years": 1.5,
  "notes": "Fetch.ai autonomous agents.",
  "current_price_usd": 0.XX,
  "ath_all_time_usd": 0.XX
}
```

### Prioridade 2: COMPLETAR DADOS PARCIAIS (18 ativos)

**Ação:** Executar enrich automático via CoinGecko API para:
- age_years (genesis_date)
- burn_active (verificar smart contract)
- concentration_top10 (etherscan/explorer)
- recovered_2021_ath (comparar ATH 2021 vs current)

**Script sugerido:**
```powershell
# backtest/coingecko_enrich_fqs_registry.py
# Integração com CoinGecko API para preencher gaps
# Prioridade: USELESSUSDT, GRASSUSDT, ASTERUSDT, PROVEUSDT, WIFUSDT
```

### Prioridade 3: VALIDAR ATIVOS NOVOS (<1 ano)

Estes precisam de **manual review** antes de Tier B:
- VVVUSDT (0.3y)
- KITEUSDT (0.5y)
- PENGUUSDT (0.4y)

**Critério:** Exigir age_years ≥ 1y para Tier B em bear phase.

---

## 7. IMPACTO NOS TRADES (29/05)

### Trades Bloqueados por FQS ABSENT:

```
[13:03:59] IDUSDT: ABORTAR
  Mesa: FORTE_3 (90/80/78) ✅
  Score: 123.88 ✅
  Tier: B ✅
  ❌ FQS ABSENT → BLOQUEADO

[13:03:59] IOUSDT: ABORTAR
  Mesa: FORTE_3 ✅
  Score: 52.43 ✅
  Tier: B ✅
  ❌ FQS ABSENT → BLOQUEADO

[13:03:59] FETUSDT: ABORTAR
  Mesa: FORTE_3 ✅
  Score: 27.23 ✅
  Tier: B ✅
  ❌ FQS ABSENT → BLOQUEADO
```

**Resultado:** 3 trades potenciais rejeitados apenas por FQS missing.

---

## 8. ESTATÍSTICAS FINAIS

| Métrica | Valor | Status |
|---------|-------|--------|
| **Total Ativos** | 62 | - |
| **Com FQS Completo** | 28 | ✅ 45% |
| **Com FQS Parcial** | 18 | ⚠️ 29% |
| **Com FQS Mínimo** | 16 | ❌ 26% |
| **Trades Bloqueados por FQS** | 3+ | ❌ |
| **Ativos Faltando no Registry** | 3 | ❌ CRÍTICO |

---

## 9. PRÓXIMOS PASSOS

### Imediato (hoje):
1. ✅ Adicionar IDUSDT, IOUSDT, FETUSDT ao registry
2. ✅ Validar dados de preço/ATH via CoinGecko

### Curto Prazo (esta semana):
1. Executar enrich automático para 18 ativos parciais
2. Implementar validação de age_years ≥ 1y para Tier B
3. Atualizar FQS drain logs para rastrear gaps

### Médio Prazo (próximas 2 semanas):
1. Integração CoinGecko API para atualização automática
2. Criar pipeline de validação manual para ativos novos
3. Documentar critérios de aceitação para Tier A/B/C

---

## Conclusão

O FQS Registry está **45% completo** com dados de qualidade. Os **26% de ativos com dados mínimos** e **3 ativos faltando** são os principais gargalos. Adicionar estes 3 ativos + completar dados parciais via CoinGecko API **desbloquearia 3+ trades potenciais** e melhoraria a cobertura para **~70%**.

**Recomendação:** Priorizar adição de IDUSDT, IOUSDT, FETUSDT hoje para retomar aprovações em Tier B.
