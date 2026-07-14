# start_fleet.ps1 — Launcher idempotente da frota (2026-07-04)
# CAUSA RAIZ: em 07-04 ~23h a frota INTEIRA estava morta (incluindo o guardian,
# entao nada se auto-curou). Nada religava os daemons apos reboot/logon.
# Este launcher roda no LOGON (Scheduled Task ManuHeadFund_Fleet) e sobe os 4.
# Idempotente: cada daemon tem singleton (pid/lock) proprio; rodar 2x nao duplica.
# PS 5.1, BOM.

$root = Split-Path $PSScriptRoot -Parent
$journal = Join-Path $root "journal"

function Start-DaemonIfDead {
    param([string]$ScriptName, [string]$StdoutFile = "")
    $alive = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match [regex]::Escape($ScriptName) } | Select-Object -First 1
    if ($alive) {
        Write-Host "$ScriptName ja vivo (PID=$($alive.ProcessId))"
        return
    }
    $args = @("-NoProfile","-ExecutionPolicy","Bypass","-File",(Join-Path $root "scripts\$ScriptName"))
    if ($StdoutFile) {
        Start-Process powershell -ArgumentList $args -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $journal $StdoutFile) `
            -RedirectStandardError (Join-Path $journal ($StdoutFile -replace 'stdout','stderr'))
    } else {
        Start-Process powershell -ArgumentList $args -WindowStyle Hidden
    }
    Write-Host "$ScriptName iniciado"
}

Start-DaemonIfDead -ScriptName "scan_master.ps1" -StdoutFile "scan_master_stdout.txt"
Start-DaemonIfDead -ScriptName "sentinel_movers.ps1"
Start-DaemonIfDead -ScriptName "collect_1h_klines.ps1"
Start-DaemonIfDead -ScriptName "gem_loop.ps1"
Start-DaemonIfDead -ScriptName "daemon_watchdog_loop.ps1" # ← Watchdog auto-recovery infinito
# 2026-07-14: self_heal_guardian.ps1 e o "guardiao de auto-cura" (DETECTA->CURA->
# REGISTRA->APRENDE->ESCALA) mas NUNCA estava neste launcher -- mesma causa raiz
# do comentario acima (07-04: guardian tambem morria e nada o religava). Achado
# ao investigar por que balance_snapshot_stale ficou 5 dias sem escalar Telegram:
# o proprio guardian estava morto desde 07-06, sem ninguem religar.
Start-DaemonIfDead -ScriptName "self_heal_guardian.ps1"

Add-Content -Path (Join-Path $journal "fleet_boot.log") -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] start_fleet executado + watchdog_loop (auto-recovery ativo)" -Encoding utf8
