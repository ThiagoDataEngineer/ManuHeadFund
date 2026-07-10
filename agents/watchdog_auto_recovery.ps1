#requires -Version 5.1
<#
.SYNOPSIS
    Watchdog — Auto-recovery para daemons (verifica a cada 60 segundos)
.DESCRIPTION
    Monitora status de 4 daemons críticos
    Se algum cair, reinicia automaticamente
    Executa indefinidamente (24/7)
#>

Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$workdir = "C:\Users\thiag\Coinex_AI_USER_API"
Set-Location $workdir

$daemons = @("gem_loop", "scan_master", "position_watcher", "tori_daemon")

Write-Host "Watchdog started" -ForegroundColor Green

while ($true) {
    foreach ($daemon in $daemons) {
        $job = Get-Job -Name $daemon -ErrorAction SilentlyContinue
        if ($null -eq $job -or $job.State -ne "Running") {
            Write-Host "[WATCHDOG] $daemon restarting..." -ForegroundColor Yellow
            $scriptPath = Join-Path $workdir "agents\${daemon}.ps1"
            if (Test-Path $scriptPath) {
                try {
                    Start-Job -ScriptBlock {
                        param($script, $wd)
                        Set-Location $wd
                        . $script
                    } -ArgumentList $scriptPath, $workdir -Name $daemon -ErrorAction Stop | Out-Null
                    Write-Host "[WATCHDOG] $daemon RESTARTED" -ForegroundColor Green
                } catch {
                    Write-Host "[WATCHDOG] $daemon FAILED" -ForegroundColor Red
                }
            }
        }
    }
    Start-Sleep -Seconds 60
}
