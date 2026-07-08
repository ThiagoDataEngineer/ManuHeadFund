# 🚀 IMMEDIATE ACTION PLAN — 2026-07-08

**Você está aqui:** Código FIXADO, safeguards implementados  
**Próximo passo:** Manual restart + 30 minutos de monitoramento

---

## ⏱️ ROADMAP (Próximas 2 horas)

### 🕐 AGORA (17:55):
```powershell
# 1. Verify pre-flight check passes
.\agents\pre_flight_check.ps1

# Expected: ✅ ALL CHECKS PASSED
# If fails: READ ERROR and fix immediately (don't proceed)
```

### 🕐 +2 MIN (17:57):
```powershell
# 2. Kill any running daemons
Get-Job | Remove-Job -Force

# 3. Restart scan_master with fresh code
.\scripts\scan_master.ps1

# 4. Verify it starts without crashing
Start-Sleep -Seconds 3
Get-Content journal\scan_master_stderr.txt  # Should be EMPTY

if (!$(Get-Content journal\scan_master_stderr.txt)) {
    Write-Host "✅ scan_master started cleanly"
} else {
    Write-Host "❌ STDERR found — scan_master failed"
    exit 1
}
```

### 🕐 +5 MIN (18:00):
```powershell
# 5. Monitor watchdog log for 3 minutes
# Should NOT show "[DOWN] scan_master" anymore

$initialLines = (Get-Content journal\watchdog_loop.log | Measure-Object -Line).Lines

Start-Sleep -Seconds 180

$finalLines = (Get-Content journal\watchdog_loop.log | Measure-Object -Line).Lines
$newLines = $finalLines - $initialLines

Get-Content journal\watchdog_loop.log -Tail $newLines | 
    Select-String -Pattern "DOWN|ERROR" | 
    ForEach-Object { Write-Host "❌ $_" -ForegroundColor Red }

if (!(Get-Content journal\watchdog_loop.log -Tail $newLines | Select-String "DOWN")) {
    Write-Host "✅ No crashes detected in last 3 minutes"
} else {
    Write-Host "❌ Still crashing — DO NOT PROCEED"
    exit 1
}
```

### 🕐 +8 MIN (18:03):
```powershell
# 6. Check if gem_loop is executing
$lastEntry = Get-Content journal\gem_loop.log -Tail 1

Write-Host "Last gem_loop entry:"
Write-Host $lastEntry

# Should show EITHER:
# - "[ENTRY] BTCUSDT..." (found signal)
# - "[BLOCKED] BTCUSDT..." (rejected by gate)
# NOT: "Dormindo 60min" (unless <60min has passed)
```

### 🕐 +10 MIN (18:05):
```powershell
# 7. Start Tori daemon if scan_master is stable
if (!(Get-Content journal\watchdog_loop.log -Tail 20 | Select-String "scan_master.*DOWN")) {
    .\agents\Start-ToriDaemon.ps1
    Write-Host "✅ Tori daemon started"
}
```

### 🕐 +30 MIN (18:25):
```powershell
# 8. Final verification
Write-Host "═══════════════════════════════════════" -ForegroundColor Green
Write-Host "FINAL STATUS CHECK" -ForegroundColor Green
Write-Host "═══════════════════════════════════════" -ForegroundColor Green

# Check all 4 critical daemons
$daemons = @(
    @{name="gem_loop"; log="gem_loop.log"}
    @{name="scan_master"; log="scan_master.log"}
    @{name="tori_daemon"; log="tori_daemon.log"}
    @{name="watchdog"; log="watchdog_loop.log"}
)

foreach ($daemon in $daemons) {
    $lastEntry = (Get-Content "journal\$($daemon.log)" -Tail 1 -ErrorAction SilentlyContinue)
    $age = if ($lastEntry -match "\[([^\]]+)\]") {
        $timestamp = [DateTime]::Parse($Matches[1])
        [Math]::Round(((Get-Date) - $timestamp).TotalMinutes)
    } else { "?" }

    $status = if ($age -lt 5) { "✅ LIVE" } else { "⚠️  STALE ($age min)" }
    Write-Host "$($daemon.name): $status"
}

Write-Host ""
Write-Host "If ALL show ✅ LIVE — System is OPERATIONAL" -ForegroundColor Green
Write-Host "If ANY show ⚠️ STALE — Need to debug" -ForegroundColor Yellow
```

---

## 📊 SUCCESS CRITERIA

System is **FULLY OPERATIONAL** when:
- [ ] ✅ scan_master running (no crashes)
- [ ] ✅ gem_loop finding signals
- [ ] ✅ Tori daemon scanning pairs
- [ ] ✅ NO entries in stderr files
- [ ] ✅ watchdog shows all daemons "[OK]"
- [ ] ✅ All 4 logs updated in last 5 minutes

---

## 🚨 IF SOMETHING FAILS

### If pre_flight_check fails:
```powershell
# 1. Read the exact error message
# 2. Identify which file has the problem
# 3. Look at that file's error
# 4. Fix it (likely Export-ModuleMember or smart quote)
# 5. Re-run pre_flight_check
# 6. DO NOT bypass — system is protecting you
```

### If scan_master still crashes:
```powershell
# 1. Check scan_master_stderr.txt
# 2. Read full error (not just first line)
# 3. If "Export-ModuleMember" → remove it
# 4. If "parsing error" → look for smart quotes
# 5. If "undefined function" → missing lib load
# 6. Fix and retry
```

### If gates aren't blocking/allowing:
```powershell
# 1. Check gem_executor.ps1 loaded correctly
# 2. Run pre_flight_check on gem_executor.ps1
# 3. Check gem_loop.log for gate decisions
# 4. Look for "[ENTRY]" or "[BLOCKED]" messages
# 5. If missing → gates not running
```

---

## 📞 TELEGRAM ALERTS EXPECTED

During next 30 minutes, you should see:
- ✅ "scan_master started" (if integrated with alerts)
- ✅ "gem_loop: N signals found"
- ✅ "Tori daemon: scanning 10 pairs"

If you DON'T see any alerts → Check `journal/alert_failures.log`

---

## ✅ AFTER 30 MINUTES (18:25)

If everything shows ✅ LIVE:
```powershell
# System is ready for:
# 1. Manual trading (via CoinEx app)
# 2. Monitoring with alerts
# 3. Collecting real data
# 4. Next: Enable auto-trading (after 24h validation)
```

If anything shows ⚠️ STALE:
```powershell
# 1. DO NOT trade yet
# 2. Investigate the stale daemon
# 3. Check its log for errors
# 4. Fix the root cause
# 5. Retry
```

---

## 🎯 GOLDEN RULE

**If you see something suspicious → ASK before proceeding**

System is now AGGRESSIVE about protecting integrity:
- ❌ Bad code gets blocked
- ❌ Silent errors get alerted
- ❌ Crashes get restarted
- ✅ But YOU are still the decision maker

**Never trade with system in ⚠️ STALE state.**

---

## 📋 CHECKLIST

- [ ] Run pre_flight_check.ps1 (must pass)
- [ ] Restart scan_master
- [ ] Monitor 3 minutes (no crashes)
- [ ] Check gem_loop activity
- [ ] Start Tori daemon
- [ ] Monitor 30 minutes total
- [ ] Verify all 4 daemons show ✅ LIVE
- [ ] System ready for trading

---

**Time estimate: 35 minutes total**  
**Difficulty: Easy (just run commands + monitor logs)**  
**Risk: Very low (all fixes tested, safeguards active)**

**NUNCA MAIS você fica sem saber se algo deu errado.**

