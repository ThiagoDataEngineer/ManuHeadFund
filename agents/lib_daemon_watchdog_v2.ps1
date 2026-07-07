# lib_daemon_watchdog_v2.ps1 — Auto-recovery ROBUST para daemons stale/mortos
# Camada 1: Self-heal dentro do próprio daemon (heartbeat + liveness check)
# Camada 2: External watchdog (polling independente)
# Camada 3: Scheduled task (fallback se 1+2 falhem)
#
# Design: FAIL-CLOSED. Qualquer daemon morto por >5min é reiniciado automaticamente.
# PS 5.1, UTF-8 BOM.

function Test-DaemonHealthy {
    <#
    .SYNOPSIS
    Verifica se daemon está VIVO (lock recente + PID existe)
    Retorna: $true=saudável, $false=morto/stale
    #>
    param(
        [string]$DaemonName,
        [string]$LockDir,
        [int]$MaxAgeMinutes = 5
    )

    $lockPath = Join-Path $LockDir "$DaemonName.lock"

    if (-not (Test-Path $lockPath)) {
        # 2026-07-07 FIX: nem todo daemon usa daemon_locks/<name>.lock. sentinel_movers
        # e collect_1h_klines gravam liveness em journal/<name>.pid (nomes curtos).
        # Sem este fallback, esses 2 apareciam SEMPRE down (lock inexistente) -> Down>=2
        # perpetuo + tentativas de restart inuteis (singleton recusa). Checa o pidfile.
        $journalDir = Split-Path $LockDir -Parent   # journal/daemon_locks -> journal
        $pidMap = @{
            "sentinel_movers"   = "sentinel.pid"
            "collect_1h_klines" = "collect_1h.pid"
        }
        $pidFileName = if ($pidMap.ContainsKey($DaemonName)) { $pidMap[$DaemonName] } else { "$DaemonName.pid" }
        $pidPath = Join-Path $journalDir $pidFileName
        if (Test-Path $pidPath) {
            $pidRaw = (Get-Content $pidPath -Raw -ErrorAction SilentlyContinue)
            $pidNum = 0
            if ([int]::TryParse(($pidRaw -replace '\s',''), [ref]$pidNum) -and $pidNum -gt 0) {
                if (Get-Process -Id $pidNum -ErrorAction SilentlyContinue) { return $true }
            }
            return $false
        }
        return $false  # Sem lock nem pidfile = morto
    }

    try {
        $lock = Get-Content $lockPath -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $pidValue = [int]$lock.pid

        # Check 1: PID existe? (liveness AUTORITATIVA)
        # 2026-07-07 FIX: o lock 'ts' e um START timestamp gravado UMA vez no boot
        # do singleton (nao um heartbeat rolante). O check antigo tratava 'ts' como
        # heartbeat e marcava stale qualquer daemon > MaxAgeMinutes de vida -> TODO
        # daemon saudavel aparecia "dead/stale" 5min apos subir (Down=4 eterno na
        # frota religada). Se o PID do lock esta VIVO, o daemon esta saudavel. Ponto.
        $proc = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
        if (-not $proc) {
            return $false  # PID morto = realmente down
        }

        return $true
    } catch {
        return $false  # Parse error = lock corrupted
    }
}

function Repair-StaleLocks {
    <#
    .SYNOPSIS
    Remove lock files para PIDs que não existem mais
    #>
    param([string]$LockDir)

    Get-ChildItem $LockDir -Filter "*.lock" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $lock = Get-Content $_.FullName | ConvertFrom-Json
            $pidValue = [int]$lock.pid

            $proc = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
            if (-not $proc) {
                # PID morto → remover lock
                Remove-Item $_.FullName -Force
                return @{locked=$true; daemon=$_.BaseName; action="DELETED"}
            }
        } catch {}
    }
}

function Invoke-DaemonRestart {
    <#
    .SYNOPSIS
    Reinicia daemon morto
    Retorna: @{success=$true/false; daemon=name; reason=msg}
    #>
    param(
        [string]$DaemonName,
        [string]$ScriptPath,
        [string]$LockDir
    )

    if (-not (Test-Path $ScriptPath)) {
        return @{success=$false; daemon=$DaemonName; reason="Script not found: $ScriptPath"}
    }

    try {
        # Remove stale lock
        $lockPath = Join-Path $LockDir "$DaemonName.lock"
        Remove-Item $lockPath -Force -ErrorAction SilentlyContinue

        # Start daemon
        Start-Process pwsh -ArgumentList "-NoProfile", "-File", $ScriptPath -WindowStyle Hidden

        return @{success=$true; daemon=$DaemonName; reason="Started"; timestamp=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')}
    } catch {
        return @{success=$false; daemon=$DaemonName; reason=$_.Exception.Message}
    }
}

function Watch-DaemonsLoopInfinite {
    <#
    .SYNOPSIS
    Loop infinito que monitora daemons a cada INTERVAL minutos
    Se algum cair → restart automático
    Roda até ser morto manualmente
    #>
    param(
        [int]$IntervalSeconds = 60,
        [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
        [string]$LogFile
    )

    # 2026-07-07 FIX: Join-Path com 3 args e PS7-only; no PS 5.1 LANCA "parametro
    # posicional" e o loop rodava com $lockDir vazio -> Test-DaemonHealthy nunca
    # achava lock -> Down=4 eterno (todos os criticos "dead/stale"). Usa 2-arg.
    $lockDir = Join-Path (Join-Path $ProjectRoot "journal") "daemon_locks"
    $scriptsDir = Join-Path $ProjectRoot "scripts"

    # Daemons que DEVEM estar rodando
    $criticalDaemons = @(
        @{name="scan_master"; path=(Join-Path $scriptsDir "scan_master.ps1")}
        @{name="sentinel_movers"; path=(Join-Path $scriptsDir "sentinel_movers.ps1")}
        @{name="collect_1h_klines"; path=(Join-Path $scriptsDir "collect_1h_klines.ps1")}
        @{name="gem_loop"; path=(Join-Path $scriptsDir "gem_loop.ps1")}
    )

    function Log-Watch($msg) {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "[$ts] $msg"
        if ($LogFile) {
            Add-Content $LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        Write-Host $line
    }

    Log-Watch "[WATCHDOG-V2] Iniciado (interval=${IntervalSeconds}s)"

    $cycle = 0
    while ($true) {
        $cycle++
        $downCount = 0
        $restartedCount = 0

        # Limpar locks stale (não bloqueia ciclo)
        Repair-StaleLocks $lockDir | Where-Object {$_ -ne $null} | ForEach-Object {
            Log-Watch "[STALE-CLEANUP] Removed: $($_.daemon) (PID $($_.pid))"
        }

        # Verificar cada daemon crítico
        foreach ($daemon in $criticalDaemons) {
            $healthy = Test-DaemonHealthy -DaemonName $daemon.name -LockDir $lockDir -MaxAgeMinutes 5

            if (-not $healthy) {
                $downCount++
                Log-Watch "[DOWN] $($daemon.name) detected as dead/stale"

                # Restart
                $result = Invoke-DaemonRestart -DaemonName $daemon.name -ScriptPath $daemon.path -LockDir $lockDir
                if ($result.success) {
                    $restartedCount++
                    Log-Watch "[RESTARTED] $($daemon.name) — OK"
                } else {
                    Log-Watch "[RESTART-FAILED] $($daemon.name) — $($result.reason)"
                }
            }
        }

        # Log ciclo
        if ($downCount -eq 0) {
            Log-Watch "[CYCLE $cycle] All daemons healthy"
        } else {
            Log-Watch "[CYCLE $cycle] Down=$downCount | Restarted=$restartedCount"
        }

        Start-Sleep $IntervalSeconds
    }
}

# Export
Export-ModuleMember -Function Test-DaemonHealthy, Repair-StaleLocks, Invoke-DaemonRestart, Watch-DaemonsLoopInfinite
