# 48h Paper Validation Guide — Layer 1 Trailing Adaptativo

**Início:** 2026-05-25 14:00 (ou agora)  
**Fim:** 2026-05-27 14:00 (48 horas)  
**Objetivo:** Validar Layer 1 (ATR-Dinâmico + Regime-Aware) antes de Layer 2

---

## 🚀 COMO COMEÇAR (5 min)

### 1. Preparar Environment

```powershell
cd c:\Users\thiag\Coinex_AI_USER_API

# Verificar que Layer 1 está integrado
$content = Get-Content .\scripts\scan_master.ps1 -Raw
if ($content -match "Update-TrailingStopsAdaptive") {
    Write-Host "✅ Layer 1 integrado" -ForegroundColor Green
} else {
    Write-Host "❌ Problema na integração" -ForegroundColor Red
}
```

### 2. Iniciar Paper Loop

```powershell
# Terminal 1: Paper trades (GEM + Trailing Adaptativo, sem Orchestrator)
cd .\scripts
.\scan_master.ps1 -SkipOrchestrator -Verbose

# Terminal 2: Monitor em tempo real (nova janela PowerShell)
cd .\scripts
while ($true) {
    cls
    Get-Content ..\journal\trades.csv | Select-Object -Last 5
    Start-Sleep 300  # refresh a cada 5 min
}

# Terminal 3: Coletar métricas (na hora)
cd .\scripts
.\collect_paper_metrics.ps1 -Verbose
```

---

## 📊 O QUE MONITORAR

### 1. Trailing Stops (a cada 1-2h)

```powershell
# Verificar se stops estão atualizando
Get-Content .\journal\trades.csv | 
  Where-Object { $_ -match "trailing_updated" } | 
  Measure-Object | Select-Object Count
  
# Esperado: 2-5 updates por hora em mercado ativo
```

### 2. Regime Distribution (a cada 4h)

```
Monitor no Telegram (se conectado):
  /status → mostra regime atual + posições
  
Esperado:
  • SIDEWAYS: 50-70% do tempo (consolidação típica)
  • BULL_STRONG: 15-30%
  • BEAR_STRONG: 5-15%
  • Outros: <5%
```

### 3. Phase Distribution (a cada 6h)

```
Fases esperadas (por posição):
  • Fase 0: 2-4h (entrada até 33% do alvo)
  • Fase 1: 2-4h (breakeven até 66%)
  • Fase 2: 1-2h (lock profits até target)
  • Fase 3: variável (trailing)

Distribuição ideal (% de posições):
  • Fase 0: ~30% (abertas recentes)
  • Fase 1: ~25%
  • Fase 2: ~15%
  • Fase 3: ~20%
  • Fechadas: ~10%
```

### 4. Stop Effectiveness (a cada 8h)

```
Métricas:
  • Stops hit: <20% of closed trades (queremos atingir targets)
  • Targets reached: >70% (objetivo é lucro)
  • Avg profit/win: >1% per trade
  • Avg loss/loss: <0.5% per trade (stops protegem bem)
```

---

## 📈 CRONOGRAMA 48H

### Hour 0-6 (Startup Phase)
**What:** Primeira execução, validar que não há crashes  
**Monitor:**
- ✅ scan_master rodando sem erros
- ✅ Primeiro trade aberto (GEM ou Orchestrator)
- ✅ Trailing stops calculando

**Action:**
```powershell
# Verificar logs para erros
Get-Content ..\logs\*.log -Tail 50 | Where-Object { $_ -match "ERROR|WARN" }
```

**Expect:** 1-3 trades abertos, 0 crashes

---

### Hour 6-12 (Phase 1 Validation)
**What:** Posições passando por transições de fase  
**Monitor:**
- ✅ Fase 0→1 transições (breakeven+buffer)
- ✅ Stops atualizando com novo buffer
- ✅ Regime detection ativo

**Action:**
```powershell
# Coletar primeira batch de métricas
.\collect_paper_metrics.ps1 -StartTime "2026-05-25 14:00" -EndTime "2026-05-25 20:00"

# Revisar: trailing updates, phase distribution
```

**Expect:** 3-8 trades, 5-15 stop updates, regime shift detectado

---

### Hour 12-24 (Full Cycle Validation)
**What:** Primeiro ciclo completo (overnight)  
**Monitor:**
- ✅ Comportamento em low-volume (madrugada)
- ✅ Trades durando >6h (validar peak persistence)
- ✅ Closes via stop vs target

**Action:**
```powershell
# Coletar métricas 12h
.\collect_paper_metrics.ps1 -StartTime "2026-05-25 14:00" -EndTime "2026-05-26 02:00"

# Analisar: qual regime predominou? Win rate?
```

**Expect:** 5-15 trades, 15-40 stop updates, 65%+ win rate

---

### Hour 24-36 (Regime Shift Testing)
**What:** Testar adaptação durante shift (se houver)  
**Monitor:**
- ✅ Como reagir a BULL→BEAR shift?
- ✅ Buffer expansion vs contração
- ✅ False stops minimizados?

**Action:**
```powershell
# Se houver regime shift:
Get-Content ..\logs\*.log -Tail 100 | 
  Where-Object { $_ -match "regime.*changed|macro.*shift" }

# Coletar métricas por regime
.\collect_paper_metrics.ps1 -StartTime "2026-05-26 02:00" -EndTime "2026-05-26 14:00"
```

**Expect:** Stops adaptando ao regime, não travando

---

### Hour 36-48 (Final Validation)
**What:** Confirmar 48h completo, coletar resultados finais  
**Monitor:**
- ✅ Total trades: 10-30 (target 1 trade a cada 2-3h)
- ✅ Win rate: >65% (vs 68% histórico BNB, 74% BTC)
- ✅ PnL: >0.5% capital ganho (paper)
- ✅ Crashes/errors: 0

**Action:**
```powershell
# Final metrics (full 48h)
.\collect_paper_metrics.ps1 `
  -StartTime "2026-05-25 14:00" `
  -EndTime "2026-05-27 14:00" `
  -OutputDir ".\metrics\FINAL_48H_LAYER_1"

# Export to JSON for analysis
$metrics = Get-Content ".\metrics\FINAL_48H_LAYER_1\paper_metrics_*.json" | ConvertFrom-Json
$metrics | ConvertTo-Json -Depth 10 | Out-File ".\metrics\FINAL_ANALYSIS.json"

# Print summary
Write-Host "📊 FINAL RESULTS:" -ForegroundColor Cyan
Write-Host "  Trades: $($metrics.performance.total_trades)" -ForegroundColor Yellow
Write-Host "  Closed: $($metrics.performance.closed_trades)" -ForegroundColor Yellow
Write-Host "  Win rate: $($metrics.performance.win_rate)%" -ForegroundColor Yellow
Write-Host "  Total PnL: $($metrics.performance.total_pnl)" -ForegroundColor Yellow
Write-Host "  Trailing updates: $($metrics.trailing.total_updates)" -ForegroundColor Yellow
```

**Expect:** ✅ All metrics within expected ranges

---

## 🎯 SUCCESS CRITERIA (to PASS Layer 1)

### Must Have (Blocking)
- [ ] **0 crashes** in 48h (scan_master runs clean)
- [ ] **>60% win rate** (vs 65% target)
- [ ] **>10 trades** executed (enough sample size)
- [ ] **Stops adapting** (10+ updates visible)
- [ ] **No stuck stops** (stops transitioning between phases)

### Should Have (Important)
- [ ] **>65% win rate** (actual target)
- [ ] **Peak persistence** visible (peaks updating even without phase change)
- [ ] **Regime detection** working (shifts detected appropriately)
- [ ] **Buffer variance** observed (different buffers for BULL vs BEAR)
- [ ] **<0.3 false alerts** per trade (Telegram noise metric)

### Nice to Have (Enhancement)
- [ ] **>70% win rate** (stretch goal)
- [ ] **Mentor could detect** opportunity (for Layer 2 design)
- [ ] **0 unrecoverable errors** (only transient retries)
- [ ] **Load test**: 5+ concurrent pairs adapting correctly

---

## ⚠️ RED FLAGS (Stop and Fix)

### Critical Issues
```
❌ Scan_master crashes repeatedly
  → Check logs: ..\logs\scan_master_*.log
  → Rollback last change, debug
  
❌ Win rate <50%
  → Check: Are stops too tight (BULL_STRONG multiplier)?
  → Or too loose (CAPITULATION)?
  → Adjust config.ps1 multipliers, retest
  
❌ Stops not updating (0 trailing updates in 6h)
  → Check: Is Update-TrailingStopsAdaptive being called?
  → Check: Are positions in scope (active)?
  → Debug: Add Write-Host in Update-TrailingStopsAdaptive
```

### Warning Issues
```
⚠️ Win rate 60-65% (just below target)
  → Acceptable for now, investigate after Layer 1 paper ends
  → Could be: regime detection needs tuning, ATR placeholder
  
⚠️ Only 5-8 trades (low sample size)
  → GEM is selective, might be normal
  → Monitor for another 12h, ensure 10+ minimum
  
⚠️ Telegram alerts verbose (>0.5/trade)
  → Lower noise, but not blocking
  → Can suppress in final run
```

---

## 📊 SAMPLE METRICS OUTPUT

After 48h, `collect_paper_metrics.ps1` produces JSON:

```json
{
  "period": {
    "start": "2026-05-25T14:00:00",
    "end": "2026-05-27T14:00:00",
    "duration_hours": 48.0
  },
  "trailing": {
    "total_updates": 24,
    "by_regime": {
      "BULL_STRONG": 8,
      "SIDEWAYS": 12,
      "BEAR_STRONG": 4
    },
    "by_phase": {
      "1": 6,
      "2": 8,
      "3": 10
    },
    "by_market": {
      "BTCUSDT": 10,
      "BNBUSDT": 8,
      "SOLUSDT": 6
    },
    "avg_buffer": 2.3
  },
  "performance": {
    "total_trades": 18,
    "closed_trades": 16,
    "win_rate": 68.75,
    "avg_pnl": 0.47,
    "total_pnl": 7.52,
    "stops_hit": 3,
    "targets_reached": 13
  },
  "phases": {
    "phase_0": 4,
    "phase_1": 3,
    "phase_2": 5,
    "phase_3": 6
  }
}
```

### Interpret Results

```
✅ PASS if:
  - win_rate >= 65%
  - total_updates >= 15
  - stops_hit <= 3 (out of 16 closed)
  - avg_buffer in range 1.5-3.5%
  
⚠️ INVESTIGATE if:
  - win_rate 60-64% (slightly below target)
  - avg_buffer > 4% (possibly too loose)
  - phase_3 > 50% of trades (possibly stuck in trailing)
  
❌ FAIL if:
  - win_rate < 60%
  - total_updates < 5 (stops not adapting)
  - total_trades < 10 (insufficient sample)
```

---

## 🔧 TROUBLESHOOTING

### Problem: "Win rate only 55%, too low"

**Root Cause Analysis:**
1. Check config multipliers (might be too tight/loose)
2. Check regime detection (macro context working?)
3. Check ATR calculation (placeholder or real?)

**Fix Steps:**
```powershell
# 1. Review current multipliers
Get-Content .\agents\config.ps1 | 
  Where-Object { $_ -match "WEIGHTS_BULL|WEIGHTS_BEAR" }

# 2. Check macro context
Get-MacroContext | ConvertTo-Json

# 3. Tighten multipliers by 10% if BULL_STRONG too loose
# Or loosen by 10% if SIDEWAYS too tight
# Retest 6h
```

---

### Problem: "Stops not updating, 0 trailing_updated in 6h"

**Root Cause Analysis:**
1. Are positions open long enough (need 30+ min for fase change)
2. Is regime detection working?
3. Is Update-TrailingStopsAdaptive being called?

**Fix Steps:**
```powershell
# 1. Check active positions
Get-TrailingPositions | Where-Object { $_.active }

# 2. Add debug output
$VerbosePreference = "Continue"
.\scan_master.ps1 -SkipOrchestrator -Verbose 2>&1 | 
  Where-Object { $_ -match "Adaptive Trailing" }

# 3. Verify function exists
Get-Command Update-TrailingStopsAdaptive -ErrorAction Stop
```

---

### Problem: "Peaks not updating, peak persistence broken"

**Fix Steps:**
```powershell
# 1. Check if peak field exists in trades.csv
Get-Content .\journal\trades.csv | Select-Object -First 3

# 2. Verify Get-TrailingNewStopAdaptive returns newPeak
# 3. Check if Update-TrailingStopsAdaptive calls $_.peak = $calc.newPeak
```

---

## 📞 ESCALATION

If ANY critical issue blocks validation:

1. **First:** Review logs (`..\logs\scan_master_*.log`)
2. **Second:** Check config (`agents\config.ps1` multipliers)
3. **Third:** Re-run failed layer tests
   ```powershell
   Invoke-Pester -Path .\tests\lib_trailing_adaptive.Tests.ps1
   Invoke-Pester -Path .\tests\lib_trailing_adaptive_integration.Tests.ps1
   ```
4. **Last:** Debug specific function
   ```powershell
   . .\agents\lib_trailing_adaptive.ps1
   $testPos = [PSCustomObject]@{ entry=100; target=110; ... }
   Get-TrailingNewStopAdaptive -Pos $testPos -CurrentPrice 105
   ```

---

## 📅 TIMELINE SUMMARY

| Time | Milestone | Status |
|------|-----------|--------|
| Hour 0 | Start paper loop | ⏳ TODO |
| Hour 6 | First metrics batch | ⏳ TODO |
| Hour 12 | First cycle close | ⏳ TODO |
| Hour 24 | 48h halfway | ⏳ TODO |
| Hour 36 | Second metrics batch | ⏳ TODO |
| Hour 48 | **Final analysis** | ⏳ TODO |

**After Hour 48:**
- If ✅ PASS: Proceed to Layer 2 (Mentor Reflection)
- If ⚠️ INVESTIGATE: Tune config, run another 24h
- If ❌ FAIL: Debug root cause, fix tests, revalidate

---

## 🎯 NEXT STEPS (After Validation)

If Layer 1 validation PASSES:
1. Archive metrics to `.\metrics\LAYER_1_FINAL_20260527.json`
2. Update `docs/TASK_5_COMPLETION_SUMMARY.md` with actual results
3. Start Layer 2 (Mentor) TDD + implementation (2-3 days)

If Layer 1 needs tuning:
1. Identify root cause (config, regime detection, ATR, etc.)
2. Make minimal fix
3. Re-run 24h validation (not full 48h)
4. Proceed when SUCCESS criteria met

---

**Go live date target:** After all 5 layers validated (est. 2026-06-24)

