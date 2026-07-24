# lib_daemon_singleton_audit.ps1 -- Validacao de singleton locks para todos os daemons

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Invoke-DaemonSingletonAudit {
    param(
        [string] $JournalDir = $global:JOURNAL_DIR,
        [string] $LockDir = $env:TEMP,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $expectedDaemons = @(
        "gem_loop"
        "scan_master"
        "telegram_listener"
        "watchdog_paper"
        "faro_v3_schedule"
    )

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $auditPath = Join-Path $JournalDir "daemon_singleton_audit.jsonl"
    $daemonsStatus = @()

    foreach ($daemon in $expectedDaemons) {
        # 2026-07-24 FIX: Join-Path so aceita 2 args no PowerShell 5.1 (Path +
        # ChildPath) -- "Join-Path X Y Z" com 3 args lanca
        # ParameterBindingException real sempre, quebrando a funcao inteira.
        $lockPath = Join-Path (Join-Path $env:TEMP "manuheadfund") "$daemon.lock"
        $isAlive = $false
        $daemonPid = $null
        $lockStatus = "NO_LOCK"
        $errorMsg = ""

        if (Test-Path $lockPath) {
            try {
                $lock = Get-Content $lockPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if ($lock.pid) {
                    $proc = Get-Process -Id $lock.pid -ErrorAction SilentlyContinue
                    if ($proc) {
                        # Valida start_ticks se disponível
                        if ($lock.start_ticks) {
                            try {
                                if ($proc.StartTime.Ticks -eq [long]$lock.start_ticks) {
                                    $isAlive = $true
                                    $lockStatus = "ALIVE"
                                } else {
                                    $lockStatus = "STALE_PID_REUSED"
                                }
                            } catch {
                                $isAlive = $true
                                $lockStatus = "ALIVE"  # Sem acesso ao StartTime, assume vivo
                            }
                        } else {
                            $isAlive = $true
                            $lockStatus = "ALIVE"
                        }
                        $daemonPid = $lock.pid
                    } else {
                        $lockStatus = "STALE_PID_DEAD"
                    }
                }
            } catch {
                $lockStatus = "LOCK_CORRUPT"
                $errorMsg = $_.Exception.Message
            }
        }

        $daemonsStatus += [PSCustomObject]@{
            daemon = $daemon
            is_alive = $isAlive
            lock_path = $lockPath
            lock_exists = (Test-Path $lockPath)
            lock_status = $lockStatus
            pid = $daemonPid
            error = $errorMsg
        }
    }

    # Registra audit em JSONL
    $auditEntry = [ordered]@{
        timestamp = $timestamp
        daemons = $daemonsStatus | ConvertTo-Json -Compress
    } | ConvertTo-Json -Compress

    Add-Content -Path $auditPath -Value $auditEntry -Encoding UTF8

    return [PSCustomObject]@{
        timestamp = $timestamp
        daemons = $daemonsStatus
        audit_path = $auditPath
    }
}

function Test-DaemonLocked {
    param(
        [Parameter(Mandatory)] [string] $DaemonName
    )

    $lockPath = Join-Path (Join-Path $env:TEMP "manuheadfund") "$DaemonName.lock"
    return Test-Path $lockPath
}

function Get-DaemonLockInfo {
    param(
        [Parameter(Mandatory)] [string] $DaemonName
    )

    $lockPath = Join-Path (Join-Path $env:TEMP "manuheadfund") "$DaemonName.lock"
    if (-not (Test-Path $lockPath)) {
        return $null
    }

    try {
        $lock = Get-Content $lockPath -Raw | ConvertFrom-Json
        return $lock
    } catch {
        return $null
    }
}

function Test-DaemonLockValid {
    param(
        [Parameter(Mandatory)] [string] $DaemonName
    )

    $lock = Get-DaemonLockInfo -DaemonName $DaemonName
    if ($null -eq $lock) {
        return $false
    }

    $proc = Get-Process -Id $lock.pid -ErrorAction SilentlyContinue
    if ($null -eq $proc) {
        return $false  # PID morto
    }

    # Valida start_ticks se disponível
    if ($lock.start_ticks) {
        try {
            if ($proc.StartTime.Ticks -ne [long]$lock.start_ticks) {
                return $false  # PID reusado
            }
        } catch {
            return $true  # Sem acesso ao StartTime, assume valido
        }
    }

    return $true
}
