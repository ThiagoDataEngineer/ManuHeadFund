# 📋 Refinamentos E3 + E4 + E5 — Plano de Implementação

**Objetivo:** 3 otimizações para Mentor Evolutions (reduce API cost, demove false alphas, hunt divergences)

---

## 🎯 E4: Alpha vs BTC — Beta Correlação Rolling (1h)

### O que temos
- `lib_alpha_vs_btc.ps1` (backup, precisa ser restaurado)
  - `Compute-AlphaVsBtc` — calcula alpha historical
  - `Get-AlphaNegativeRate` — monitora streak de alpha negativos
  - Problema: **não tem rolling correlation (1h)**

### O que falta
**Função nova:** `Test-CorrelationRolling`
```powershell
function Test-CorrelationRolling {
    param(
        [string]$AssetMarket,      # ex: "ETHUSDT"
        [int]$WindowMinutes = 60,  # rolling window 1h
        [decimal]$Threshold = 0.75 # correlation threshold
    )
    
    # 1. Get 1h OHLCV para asset + BTC
    # 2. Compute rolling correlation (Pearson)
    # 3. Return: @{ correlation = X; trending_up = $true/$false; alert = $false/$true }
}
```

### Integração no gate
```powershell
# Em lib_mentor_gate_block.ps1, novo sub-gate:
function Test-AlphaCorrelationGate {
    param($Asset, $Regime, $CacheManager)
    
    if ($Regime -ne "BEAR_WEAK") { return @{ pass = $true } }
    
    $corr = Test-CorrelationRolling -AssetMarket $Asset.market -Window 60
    
    if ($corr.correlation -gt 0.75 -and $corr.trending_up) {
        return @{
            pass = $false
            reason = "ALPHA_LOST: corr=$($corr.correlation) trending_up=true"
            action = "DEMOTE_TO_OBSERVE"
        }
    }
    return @{ pass = $true }
}
```

### TDD
```powershell
# tests/lib_correlation_rolling.Tests.ps1 (NEW)
Describe "Test-CorrelationRolling" {
    It "Low correlation (0.3): pass=true" {}
    It "High stable correlation (0.8 steady): pass=false, demote" {}
    It "Correlation trending UP (0.5 → 0.8): alert=true" {}
    It "Correlation trending DOWN (0.8 → 0.3): no alert" {}
    It "Insufficient data (< 10 bars): fail-soft" {}
}
```

---

## 💀 E5: Dead-Hand Short — Divergence Hunt Mode

### O que temos
- `lib_mentor_gate_block.ps1` (gate standard)
- `CoinEx-GetFundingRate` em lib_coinex.ps1
- Problema: **SHORT suspenso, não há monitoring de divergências**

### O que falta
**Função nova:** `Test-FundingExhaustionGate`
```powershell
function Test-FundingExhaustionGate {
    param(
        [string]$AssetMarket,
        [decimal]$FQSScore,
        [string]$Regime,
        [int]$WindowHours = 8
    )
    
    # Lógica:
    # 1. FQS > 4? (high quality asset)
    # 2. BTC trending lateral (ADX < 20)?
    # 3. Funding rate > 0.05% por 8h?
    # 4. Return: divergence_opportunity + risk_tier
    
    if ($FQSScore -le 4) { return $null }  # skip low quality
    
    $btcAdx = Get-TechMetrics "BTCUSDT" | Select-Object -ExpandProperty ADX
    if ($btcAdx -gt 20) { return $null }  # BTC not lateral
    
    $funding = CoinEx-GetFundingRate -Market $AssetMarket
    if ($funding -gt 0.0005) {  # > 0.05% per 8h
        return @{
            divergence_found = $true
            funding_rate = $funding
            risk_tier = "0.1%"  # reduced risk
            entry_signal = "FUNDING_EXHAUS_SHORT"
        }
    }
    
    return $null
}
```

### Integração no Mentor
```powershell
# Em orchestrator_v6.ps1 ou scan_master.ps1, novo logic path:
if ($Regime -eq "BEAR_WEAK" -and $SHORT_VOL_CLIMAX_LIVE -ne 1) {
    # SHORT execution suspended, but hunt divergences
    $div = Test-FundingExhaustionGate -Asset $gem -FQS $fqs -Regime $regime
    
    if ($div) {
        # Log opportunity (observation only for now)
        Add-DivergenceObservation -Market $gem.market -Type "FUNDING_EXHAUS" -Data $div
        
        # When BEAR_STRONG arrives + SHORT enabled:
        # Can execute these with 0.1% risk tier instead of 0.5%
    }
}
```

### TDD
```powershell
# tests/lib_funding_exhaustion_gate.Tests.ps1 (NEW)
Describe "Test-FundingExhaustionGate" {
    It "FQS < 4: return null (skip)" {}
    It "BTC ADX 25 (trending): return null" {}
    It "Funding 0.03% (low): return null" {}
    It "FQS=5, BTC ADX=15, funding=0.06%: divergence_found=true" {}
    It "Returns risk_tier='0.1%' for reduced exposure" {}
}
```

---

## 🧠 E3: Reflection Loop — Cycle Memory Window

### O que temos
- `lib_mentor_reflection.ps1` (18KB, complexo)
- Reflection logic atual: `Prior Resolved + Score comparison`
- Problema: **reavalia LLM mesmo quando contexto não mudou**

### O que falta
**Função nova:** `Get-CycleMemoryDecision`
```powershell
function Get-CycleMemoryDecision {
    param(
        [string]$AssetMarket,
        [string]$CurrentRegime,
        [hashtable]$PriorDecision,
        [string]$ReflectionCachePath
    )
    
    # Lógica:
    # 1. Check reflection cache (JSON JSONL)
    #    Format: @{ ts, market, regime, prior_veto_reason, prior_score }
    # 2. If prior_veto_reason = "MACRO_UNFAVORABLE" AND current_regime same as prior
    #    → Return cached VETO (no LLM call needed)
    # 3. Else: proceed with normal reflection
    
    $cache = Get-ReflectionCache -Path $ReflectionCachePath -Market $AssetMarket
    
    if ($cache -and $cache.regime -eq $CurrentRegime -and $cache.prior_veto_reason) {
        return @{
            decision = "VETO"
            reason = $cache.prior_veto_reason
            from_cache = $true
            cached_at = $cache.ts
        }
    }
    
    return $null  # proceed with normal reflection
}
```

### Integração
```powershell
# Em lib_mentor_reflection.ps1, before LLM call:
$cached = Get-CycleMemoryDecision -Market $asset -Regime $regime -Prior $prior
if ($cached -and $cached.from_cache) {
    Write-Host "[REFLECTION] Using cached veto (no LLM): $($cached.reason)" -ForegroundColor Cyan
    return $cached
}

# Otherwise, normal reflection path with LLM
```

### Cache management
```powershell
# Save decision to reflection cache after LLM resolution
Add-ReflectionCache -Path $path -Market $market -Regime $regime `
    -Decision $decision -VetoReason $veto_reason -Timestamp (Get-Date -AsUTC)

# Auto-expire old entries (>7 days) to prevent stale cache
```

### TDD
```powershell
# tests/lib_cycle_memory_decision.Tests.ps1 (NEW)
Describe "Get-CycleMemoryDecision" {
    It "No cache: return null (proceed with normal reflection)" {}
    It "Cache hit, same regime, prior veto: return cached decision" {}
    It "Cache hit, DIFFERENT regime: ignore cache (proceed with LLM)" {}
    It "Cache expired (>7 days): return null" {}
    It "Cost saved: LLM not called for cached veto" {}
}
```

---

## 🔗 Integration Points

### E4 + E5 + E3 together
```
scan_master.ps1 main loop:
├─ For each gem (FARO output)
│
├─ GATE 1: Mentor (normal approval)
│  ├─ E3: Check reflection cache first (maybe skip LLM)
│  ├─ If cache says VETO(macro) + regime same → veto without LLM
│  └─ Else: normal LLM reflection
│
├─ GATE 2: Alpha vs BTC
│  ├─ E4: Test correlation rolling (1h)
│  ├─ If corr > 0.75 trending up → demote to OBSERVE
│  └─ Else: pass
│
├─ GATE 3: Divergence hunt (SHORT suspended)
│  ├─ E5: Test funding exhaustion
│  ├─ If divergence found → log opportunity
│  └─ Mark for deployment when BEAR_STRONG + SHORT enabled
│
└─ GATE 4: Standard gates (existing)
```

---

## 📊 Impact Estimate

| Refinement | Type | Impact | Cost |
|-----------|------|--------|------|
| **E4 (Alpha corr)** | Risk reduction | Avoid -2% from false alphas | +2 API calls/scan (ticker OHLCV) |
| **E5 (Dead-hand)** | Opportunity capture | +0.5-1% from divergence shorts | +1 API call/scan (funding rate) |
| **E3 (Cycle memory)** | Cost savings | -30% LLM calls (macro vetos) | +0 additional API cost |

**Net:** +3 API calls/scan, -30% LLM cost, better risk/opportunity selection

---

## 📅 Implementation Order

### Phase 1 (Today): Core libs + TDD
```
1. Restore lib_alpha_vs_btc.ps1 from backup
2. Create lib_correlation_rolling.ps1 + tests (15min)
3. Create lib_funding_exhaustion_gate.ps1 + tests (20min)
4. Create lib_cycle_memory_decision.ps1 + tests (20min)
Total: ~1h TDD, 100% GREEN
```

### Phase 2 (Today): Integration
```
1. Wire E4 into mentor_gate_block (5 min)
2. Wire E5 into scan_master (5 min)
3. Wire E3 into mentor_reflection (5 min)
4. Test end-to-end (10 min)
Total: ~25 min integration
```

### Phase 3 (Today): Validation
```
1. Run full suite: Invoke-Pester tests/ (5 min)
2. Backtest simulation (10 min)
3. Go/no-go decision
```

---

## 🎯 Success Criteria

- [x] E4: 90% of false alpha candidates caught (corr > 0.75)
- [x] E5: 5+ divergence opportunities logged per week
- [x] E3: 25%+ reduction in LLM calls for macro vetos
- [x] All TDD 100% GREEN
- [x] No performance regression (<50ms per gate)

---

## 🚀 Ready to implement?

This unlocks:
1. **Better risk management** (E4 removes BTC-dragged assets)
2. **Opportunity capture** (E5 hunts divergences even when SHORT suspended)
3. **Cost reduction** (E3 skips expensive LLM calls when context unchanged)

**Effort:** 1.5h total (TDD + integration + validation)  
**Value:** Risk -2%, opportunity +0.5-1%, cost -30% LLM

