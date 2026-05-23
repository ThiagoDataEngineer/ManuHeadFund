#!/usr/bin/env powershell
# Start services - Windows PowerShell 5.1 compatible

$wd = "C:\Users\thiag\Coinex_AI_USER_API"
$logsDir = Join-Path $wd "journal"

Write-Host ""
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  INICIANDO GEM_LOOP + GEMS INTRADAY" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Ensure journal dir
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

Write-Host "WorkDir: $wd" -ForegroundColor Gray
Write-Host "LogsDir: $logsDir" -ForegroundColor Gray
Write-Host ""

# Kill old instances silently
Write-Host "[1/3] Limpando processos antigos..." -ForegroundColor Yellow
$oldCount = 0
Get-Process powershell -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.CommandLine -like "*gem_loop*") {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        $oldCount++
    }
}
if ($oldCount -gt 0) {
    Write-Host "  ✓ Matou $oldCount processo(s) antigo(s)" -ForegroundColor Yellow
} else {
    Write-Host "  (nenhum processo antigo)" -ForegroundColor Gray
}

Start-Sleep -Seconds 1

# Validate sourcing
Write-Host ""
Write-Host "[2/3] Validando gem_loop.ps1..." -ForegroundColor Yellow
Set-Location $wd

$agentsDir = Join-Path $wd "agents"
try {
    . (Join-Path $agentsDir "config.local.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "config.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_coinex.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_journal.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "gem_agent.ps1") -ErrorAction Stop
    
    if (Get-Command "Invoke-GemScan" -ErrorAction SilentlyContinue) {
        Write-Host "  ✓ Sourcing OK - Invoke-GemScan available" -ForegroundColor Green
    } else {
        throw "Invoke-GemScan not found"
    }
} catch {
    Write-Host "  ✗ ERRO: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Start gem_loop
Write-Host ""
Write-Host "[3/3] Iniciando gem_loop..." -ForegroundColor Yellow

$gemProc = Start-Process powershell.exe -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $wd "scripts\gem_loop.ps1"),
    "-Force"
) -WorkingDirectory $wd -PassThru

Write-Host "  • PID=$($gemProc.Id)" -ForegroundColor Yellow

Start-Sleep -Seconds 4

# Verify alive
if (Get-Process -Id $gemProc.Id -ErrorAction SilentlyContinue) {
    Write-Host "  ✓ gem_loop ALIVE" -ForegroundColor Green
} else {
    Write-Host "  ✗ gem_loop FALHOU" -ForegroundColor Red
    exit 1
}

# Show log
$gemLog = Join-Path $logsDir "gem_loop.log"
if (Test-Path $gemLog) {
    Write-Host ""
    Write-Host "Últimos eventos:" -ForegroundColor Cyan
    Get-Content $gemLog -Tail 6 -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✓ SISTEMA ONLINE" -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "gem_loop PID=$($gemProc.Id) - RODANDO" -ForegroundColor Cyan
Write-Host ""
Write-Host "Monitorar:" -ForegroundColor Yellow
Write-Host "  tail -f $gemLog" -ForegroundColor Gray
Write-Host ""
