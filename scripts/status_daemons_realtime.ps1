# status_daemons_realtime.ps1 — Dashboard em tempo real do status dos daemons
# Roda num loop, mostra health + restart count + age
# Uso: pwsh -File scripts\status_daemons_realtime.ps1

$projectRoot = Split-Path -Parent $PSScriptRoot
$journalDir = Join-Path $projectRoot "journal"
$lockDir = Join-Path $journalDir "daemon_locks"

function Show-Status {
    Clear-Host
    Write-Host "╔════════════════════════════════════════════════════════════╗"
    Write-Host "║          DAEMON STATUS DASHBOARD — $(Get-Date -Format 'HH:mm:ss')                  ║"
    Write-Host "╚════════════════════════════════════════════════════════════╝"
    Write-Host ""

    $daemons = @(
        @{name="scan_master"; critical=$true}
        @{name="sentinel_movers"; critical=$true}
        @{name="collect_1h_klines"; critical=$true}
        @{name="gem_loop"; critical=$true}
        @{name="watchdog_loop"; critical=$true}
    )

    foreach ($daemon in $daemons) {
        $lockFile = Join-Path $lockDir "$($daemon.name).lock"

        if (Test-Path $lockFile) {
            try {
                $lock = Get-Content $lockFile -Encoding UTF8 | ConvertFrom-Json
                $pidValue = [int]$lock.pid
                $lockAge = [int]((Get-Date) - [datetime]$lock.ts).TotalSeconds

                $proc = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
                if ($proc) {
                    $status = "🟢 RUNNING"
                    $detail = "PID=$pidValue | Age=$('{0:D2}:{1:D2}:{2:D2}' -f ($lockAge/3600), (($lockAge%3600)/60), ($lockAge%60))"
                } else {
                    $status = "🔴 DEAD"
                    $detail = "PID=$pidValue (não encontrado)"
                }
            } catch {
                $status = "🟡 CORRUPTED"
                $detail = "Lock inválido"
            }
        } else {
            $status = "⚫ NO LOCK"
            $detail = "Nunca iniciado ou morto"
        }

        $critical = if ($daemon.critical) { "[CRITICAL]" } else { "[OPTIONAL]" }
        Write-Host "  $($daemon.name.PadRight(20)) $status $critical $detail"
    }

    Write-Host ""
    Write-Host "  Últimas ações do watchdog:"
    if (Test-Path "$journalDir\watchdog_loop.log") {
        (Get-Content "$journalDir\watchdog_loop.log" -Tail 5 -ErrorAction SilentlyContinue) | ForEach-Object {
            Write-Host "    $_"
        }
    }

    Write-Host ""
    Write-Host "  [Refresh a cada 5 sec... Ctrl+C para sair]"
}

$cycle = 0
while ($true) {
    Show-Status
    $cycle++
    Start-Sleep 5
}
