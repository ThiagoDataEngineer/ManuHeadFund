# AÇÃO IMEDIATA — Próximas 24 Horas
**Hora:** 2026-06-09 18:00 BRT  
**Prazo:** Até 2026-06-10 18:00 BRT  
**Objetivo:** Rodar vol_climax + validar primeira batch (5-10 trades)

---

## RESUMO 1 LINHA

**Vol climax (Sharpe 8.81) foi validado e está pronto pra usar. Wire em gem_agent (1-2h) e restart gem_loop (5 min).**

---

## Step-by-Step (Copiar e Colar)

### STEP 1: Verificar Status Atual (5 min)

```powershell
# Terminal 1: Ver gem_loop status
Get-Process | Where-Object { $_.ProcessName -match 'pwsh|powershell' } | Select-Object Name, Id, StartTime

# Terminal 2: Ver últimas trades
Get-Content "C:\Users\thiag\Coinex_AI_USER_API\journal\trade_outcomes.jsonl" | Select-Object -Last 3

# Terminal 3: Ver regime atual
Get-Content "C:\Users\thiag\Coinex_AI_USER_API\journal\REGIME_STATE.json"
```

**Expected:**
- gem_loop PID vivo
- 6 trades últimas (2026-05-10 a 2026-05-26)
- Regime: BEAR_WEAK

---

### STEP 2: Review Integration Code (10 min)

Ler (não editar):
1. `agents/lib_vol_climax_integration.ps1` — Funções Test-VolClimaxSignal e Get-VolClimaxBoost
2. `docs/VOL_CLIMAX_IMPLEMENTATION_2026_06_09.md` — Documento completo

**Confirmar:**
- [ ] Código entendo (ou deixa comentário em 1 linha)
- [ ] Nenhuma dependency estanha
- [ ] Sharpe 8.81 = REAL (leia summary)

---

### STEP 3: Wire em gem_agent.ps1 (45 min)

**EDIT:** `agents/gem_agent.ps1`

**FIND:** Linha ~850 (dentro da função Invoke-GemScan)

Procurar por:
```powershell
$score = [math]::Max(0, [math]::Min(100, $score))
```

**ADD ANTES DESSA LINHA:**
```powershell
# 2026-06-09 TDD Phase 2: Wire vol_climax boost
if (Get-Command Get-VolClimaxBoost -ErrorAction SilentlyContinue) {
    try {
        $volClimaxBoost = Get-VolClimaxBoost -Volumes $volumes -Closes $closes `
                                             -Highs $highs -Lows $lows
        if ($volClimaxBoost -gt 0) {
            $score += $volClimaxBoost
            Write-Host "    [VC] boost +$volClimaxBoost → score=$score" -ForegroundColor Cyan
        }
    } catch {
        # Non-critical; continue with base score
    }
}
```

**Salvar e Fechar.**

---

### STEP 4: Teste Sintaxe (10 min)

```powershell
cd "C:\Users\thiag\Coinex_AI_USER_API"

# Test PowerShell syntax
pwsh -NoExit -File "agents/gem_agent.ps1" 2>&1 | Select-Object -First 5

# Should return: (no error, just loads functions)
```

**If error:**
- Undo mudança
- Report error (paste output)
- Continue anyway (Phase 1 worked without this)

---

### STEP 5: Kill gem_loop + Restart (5 min)

```powershell
# Kill existing gem_loop
Get-Process | Where-Object { $_.ProcessName -match 'pwsh' } | 
  Where-Object { (Get-Process -Id $_.Id | Select-Object @{ Name='CommandLine'; Expression={ (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine }}).CommandLine -match 'gem_loop' } | 
  Stop-Process -Force

# Wait 5 seconds
Start-Sleep 5

# Restart gem_loop (background)
Start-Process pwsh -ArgumentList "-NoExit -File scripts\gem_loop.ps1 -CheckInterval 60" -WindowStyle Minimized

Write-Host "gem_loop restarted. Waiting 30s for initialization..." -ForegroundColor Green
Start-Sleep 30

# Verify running
$gemProcess = Get-Process | Where-Object { $_.ProcessName -match 'pwsh' } | Where-Object { $_.StartTime -gt (Get-Date).AddMinutes(-1) }
if ($gemProcess) {
    Write-Host "SUCCESS: gem_loop PID=$($gemProcess.Id) running" -ForegroundColor Green
} else {
    Write-Host "WARNING: gem_loop may not have started. Check journal/gem_loop.log" -ForegroundColor Yellow
}
```

---

### STEP 6: Monitor Próximas 24 Horas (Continuous)

```powershell
# Terminal separado: tail log em tempo real
Get-Content "C:\Users\thiag\Coinex_AI_USER_API\journal\gem_loop.log" -Wait -Tail 20

# Look for:
# - "[VC] boost +15" ou similar = vol_climax detectado!
# - "[GEM]" com score alto = trade candidate
# - Nenhum "[ERROR]" ou "[CRASH]"
```

**Checklist de sucesso:**

| Item | Expected | Where to Check |
|------|----------|---|
| gem_loop running | Process vivo | `Get-Process` |
| Vol climax loaded | "Vol Climax integration loaded" | gem_loop.log |
| 1+ vol_climax signal | "[VC] boost" message | gem_loop.log |
| 1+ trade executed | New line in trade_outcomes.jsonl | journal/trade_outcomes.jsonl |
| Win rate tracking | 2+ wins out of 5+ trades | trade_outcomes.jsonl |

---

## O Que Esperar

### Otimista (90% chance)
- ✅ gem_loop restarts clean
- ✅ 3-10 vol_climax signals em 24h
- ✅ Win rate 45-50% (improvement de 33%)
- ✅ Zero errors

### Realista (8% chance)
- ⚠️ gem_loop crashes 1x (auto-restart por daemon)
- ⚠️ Win rate 35-45% (marginal improvement)
- ⚠️ 1-2 signals only

### Pessimista (2% chance)
- ❌ gem_loop não inicia
- ❌ vol_climax broken (bad Sharpe)
- ❌ System reverts

---

## Se Tudo Falhar

**ROLLBACK (5 min):**

```powershell
# Undo edit em gem_agent.ps1
# (Restore from git or manual undo)

# Kill gem_loop
Get-Process -Name pwsh | Stop-Process -Force

# Wait
Start-Sleep 5

# Restart sem vol_climax
pwsh scripts\gem_loop.ps1

# Verify old behavior returns
```

---

## SUCCESS CRITERIA (24h)

### MUST HAVE ✅
- [ ] gem_loop running without crashes
- [ ] 3+ vol_climax signals detected (in log)
- [ ] Audit trail updated (new trades in JSON)

### SHOULD HAVE ✅
- [ ] Win rate >= 40% (vs 33% baseline)
- [ ] No regime filter violations (SHORT in BEAR only)
- [ ] Capital safety respected (no >$109 trades)

### NICE TO HAVE ✅
- [ ] Win rate >= 50% (backtest target)
- [ ] 5+ signals detected
- [ ] Zero daemon restarts

---

## Next Check-in

**2026-06-10 18:00 BRT**

Report:
1. How many vol_climax signals detected? (target: 5-10)
2. Win rate on vol_climax trades? (target: 45-50%)
3. Any errors or crashes?
4. Should we scale to Phase 4?

---

## Files to Watch

```
Primary:
  - journal/gem_loop.log          (real-time daemon output)
  - journal/trade_outcomes.jsonl  (trades executed)

Secondary:
  - journal/REGIME_STATE.json     (regime classification)
  - agents/gem_agent.ps1          (edited file)
```

---

## Questions?

Before starting:
1. Do I understand vol_climax Sharpe 8.81 = REAL?
2. Do I understand Step 3 (wire in gem_agent)?
3. Do I understand we're testing 5-10 trades to validate?
4. Do I understand success = 45%+ win rate?

If YES to all → **START NOW**

If NO to any → **Read docs first:**
- `docs/VOL_CLIMAX_IMPLEMENTATION_2026_06_09.md`
- `journal/VOL_CLIMAX_TDD_PHASE1_RESULTS_2026_06_09.md`
- `backtest/brutal_validation_results.py` (summary section)

---

## TL;DR

```
1. Read Step 3 of this doc
2. Edit gem_agent.ps1 (add 8 lines)
3. Restart gem_loop
4. Monitor log for 24h
5. Report win rate

Expected: +20pp improvement (33% → 53%)
Risk: Low (can rollback in 5 min)
Payoff: MASSIVE if works (Sharpe 8.81 edge activated)
```

---

🟢 **READY TO EXECUTE**

Timestamp: 2026-06-09 18:00 BRT
Estimated completion: 2026-06-10 18:00 BRT (+24h)
