# _restart_all.ps1 -- Restart completo de todos os daemons com novo codigo
# 2026-05-28: inclui mudancas Living Whitelist + Regime-Aware Candidates
# PS 5.1. UTF-8 BOM. Sem acentos.

param([switch]$SkipTests)

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$logDir      = Join-Path $projectRoot "logs"
$journalDir  = Join-Path $projectRoot "journal"
$scriptsDir  = Join-Path $projectRoot "scripts"

function Log {
    param([string]$M, [string]$C = "White")
    Write-Host ("[" + (Get-Date).ToString("HH:mm:ss") + "] " + $M) -ForegroundColor $C
}

Log "============================================================" Cyan
Log "  RESTART COMPLETO -- $(Get-Date -Format 'yyyy-MM-dd HH:mm')" Cyan
Log "============================================================" Cyan

# ── 1. STATUS ATUAL ──────────────────────────────────────────────────────────
Log "" White
Log "=== 1. STATUS ATUAL ===" Yellow

$masterLog = Get-ChildItem $logDir -Filter "master_*.log" -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($masterLog) {
    $ageMin = [math]::Round(((Get-Date) - $masterLog.LastWriteTime).TotalMinutes)
    $col = if ($ageMin -lt 30) { "Green" } else { "Yellow" }
    Log ("  master log: " + $masterLog.Name + " | " + $ageMin + " min atras") $col
    Get-Content $masterLog.FullName -Tail 3 | ForEach-Object { Log ("    " + $_) Gray }
} else {
    Log "  master log: NAO ENCONTRADO" Red
}

$watchdogLog = Join-Path $journalDir "watchdog.log"
if (Test-Path $watchdogLog) {
    $wAge = [math]::Round(((Get-Date) - (Get-Item $watchdogLog).LastWriteTime).TotalMinutes)
    $col = if ($wAge -lt 5) { "Green" } else { "Yellow" }
    Log ("  watchdog log: " + $wAge + " min atras") $col
    Get-Content $watchdogLog -Tail 3 | ForEach-Object { Log ("    " + $_) Gray }
}

# ── 2. VALIDAR TESTES ────────────────────────────────────────────────────────
if (-not $SkipTests) {
    Log "" White
    Log "=== 2. VALIDANDO TESTES CRITICOS ===" Yellow

    $testSuites = @(
        "tests\lib_quant_whitelist_regime.Tests.ps1",
        "tests\living_whitelist_cron.Tests.ps1",
        "tests\lib_quant_whitelist.Tests.ps1",
        "tests\living_whitelist.Tests.ps1",
        "tests\living_whitelist_autoadd.Tests.ps1",
        "tests\beta_hallucination_fix.Tests.ps1",
        "tests\dsr_forbidden_phrases.Tests.ps1",
        "tests\lib_mentor_gate_block.Tests.ps1",
        "tests\mentor_prompt_unified.Tests.ps1",
        "tests\mesa_lidar_direction_fix.Tests.ps1",
        "tests\gemini_provider_state.Tests.ps1"
    )

    $allPass = $true
    foreach ($suite in $testSuites) {
        $path = Join-Path $projectRoot $suite
        if (-not (Test-Path $path)) { Log ("  SKIP (nao encontrado): " + $suite) Gray; continue }
        try {
            $result = Invoke-Pester $path -PassThru -Quiet 2>&1
            $passed = $result.PassedCount
            $failed = $result.FailedCount
            if ($failed -eq 0) {
                Log ("  PASS " + $passed + "/" + ($passed + $failed) + " -- " + $suite) Green
            } else {
                Log ("  FAIL " + $failed + " falhas -- " + $suite) Red
                $allPass = $false
            }
        } catch {
            Log ("  ERRO ao rodar " + $suite + " : " + $_) Red
            $allPass = $false
        }
    }

    if (-not $allPass) {
        Log "" White
        Log "ABORTANDO: testes falharam. Corrija antes de reiniciar." Red
        exit 1
    }
    Log "  Todos os testes passaram." Green
} else {
    Log "  Testes pulados (-SkipTests)" Yellow
}

# ── 3. MATAR DAEMONS ─────────────────────────────────────────────────────────
Log "" White
Log "=== 3. PARANDO DAEMONS ===" Yellow

$killPatterns = @(
    @{ name = "watchdog_paper";    pattern = "*watchdog_paper*" },
    @{ name = "scan_master";       pattern = "*scan_master.ps1*" },
    @{ name = "gem_loop";          pattern = "*gem_loop.ps1*" },
    @{ name = "telegram_listener"; pattern = "*telegram_listener.ps1*" }
)

foreach ($d in $killPatterns) {
    $procs = @(Get-Process powershell -ErrorAction SilentlyContinue | Where-Object {
        try {
            $ci = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $_.Id) -ErrorAction Stop
            ($ci.CommandLine -like $d.pattern) -and ($ci.CommandLine -notlike "*_restart_all*")
        } catch { $false }
    })
    if ($procs.Count -gt 0) {
        foreach ($p in $procs) {
            $age = [math]::Round(((Get-Date) - $p.StartTime).TotalHours, 1)
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Log ("  Killed " + $d.name + " PID=" + $p.Id + " age=" + $age + "h") Yellow
        }
    } else {
        Log ("  " + $d.name + ": nao estava rodando") Gray
    }
    Start-Sleep -Seconds 1
}

Start-Sleep -Seconds 3
Log "  Daemons parados." Green

# ── 4. WARMUP LLM ────────────────────────────────────────────────────────────
Log "" White
Log "=== 4. WARMUP LLM ===" Yellow
$warmupPath = Join-Path $scriptsDir "warmup_llm_endpoints.ps1"
if (Test-Path $warmupPath) {
    Log "  Iniciando warmup async..." Gray
    Start-Process powershell.exe -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$warmupPath) `
        -WorkingDirectory $projectRoot -WindowStyle Hidden | Out-Null
    Log "  Warmup disparado (async, aguardando 8s)" Gray
    Start-Sleep -Seconds 8
} else {
    Log "  warmup_llm_endpoints.ps1 nao encontrado, pulando" Yellow
}

# ── 5. RESPAWN DAEMONS ───────────────────────────────────────────────────────
Log "" White
Log "=== 5. INICIANDO DAEMONS ===" Yellow

$spawns = @(
    @{ name = "gem_loop";          script = "scripts\gem_loop.ps1";          args = @("-Force") },
    @{ name = "scan_master";       script = "scripts\scan_master.ps1";       args = @() },
    @{ name = "telegram_listener"; script = "scripts\telegram_listener.ps1"; args = @() },
    @{ name = "watchdog_paper";    script = "scripts\watchdog_paper.ps1";    args = @("-Force") }
)

$pids = @{}
foreach ($d in $spawns) {
    $scriptPath = Join-Path $projectRoot $d.script
    if (-not (Test-Path $scriptPath)) {
        Log ("  SKIP " + $d.name + ": script nao encontrado") Yellow
        continue
    }
    $psArgs = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$scriptPath) + $d.args
    try {
        $proc = Start-Process powershell.exe -ArgumentList $psArgs `
            -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru
        Start-Sleep -Seconds 5
        $alive = $null -ne (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
        if ($alive) {
            Log ("  STARTED " + $d.name + " PID=" + $proc.Id) Green
            $pids[$d.name] = $proc.Id
        } else {
            Log ("  FAILED " + $d.name + " (morreu em 5s)") Red
        }
    } catch {
        Log ("  ERRO ao spawnar " + $d.name + ": " + $_) Red
    }
    Start-Sleep -Seconds 2
}

# ── 6. VERIFICACAO POS-RESTART ───────────────────────────────────────────────
Log "" White
Log "=== 6. VERIFICACAO (aguardando 30s) ===" Yellow
Start-Sleep -Seconds 30

$masterLogNew = Get-ChildItem $logDir -Filter "master_*.log" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($masterLogNew) {
    $ageMin = [math]::Round(((Get-Date) - $masterLogNew.LastWriteTime).TotalMinutes)
    $col = if ($ageMin -lt 5) { "Green" } else { "Yellow" }
    Log ("  master log: " + $masterLogNew.Name + " | " + $ageMin + " min atras") $col
    Get-Content $masterLogNew.FullName -Tail 5 | ForEach-Object { Log ("    " + $_) Gray }
}

$gemLogPath = Join-Path $journalDir "gem_loop.log"
if (Test-Path $gemLogPath) {
    $gAge = [math]::Round(((Get-Date) - (Get-Item $gemLogPath).LastWriteTime).TotalMinutes)
    $col = if ($gAge -lt 5) { "Green" } else { "Yellow" }
    Log ("  gem_loop log: " + $gAge + " min atras") $col
}

if (Test-Path $watchdogLog) {
    $wAge = [math]::Round(((Get-Date) - (Get-Item $watchdogLog).LastWriteTime).TotalMinutes)
    $col = if ($wAge -lt 5) { "Green" } else { "Yellow" }
    Log ("  watchdog log: " + $wAge + " min atras") $col
    Get-Content $watchdogLog -Tail 4 | ForEach-Object { Log ("    " + $_) Gray }
}

# ── 7. RESUMO ────────────────────────────────────────────────────────────────
Log "" White
Log "============================================================" Cyan
Log ("  RESTART CONCLUIDO -- " + (Get-Date -Format "HH:mm:ss")) Cyan
Log "============================================================" Cyan
Log "" White
Log "PIDs iniciados:" White
foreach ($k in $pids.Keys) { Log ("  " + $k + " : " + $pids[$k]) Green }
Log "" White
Log "Proximos passos:" White
Log "  1. Aguardar proximo ciclo scan_master (~30min janela SLOW)" Gray
Log "  2. Verificar logs\master_$(Get-Date -Format 'yyyyMMdd').log" Gray
Log "  3. Confirmar candidatos organicos no top-10" Gray
Log "  4. Verificar regime-aware tier_level rebaixando ativos BEAR" Gray
Log "" White
