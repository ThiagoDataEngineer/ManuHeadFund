# watchdog_paper.ps1 — Monitora scan_master + gem_loop e respawn se morrer
#
# Detecta:
#   1. Processo scan_master morto (não aparece em Get-Process)
#   2. Log scan_master stale (sem atividade > MaxLogAge min)
#   3. Processo gem_loop morto
#   4. Log gem_loop stale (sem atividade > MaxGemLogAge min, default 90min)
#
# Ação: respawn cada um com working dir correto.
# Loop infinito até Ctrl+C. Logs em journal/watchdog.log.
#
# Uso:
#   pwsh -File scripts\watchdog_paper.ps1                    # loop default 60s
#   pwsh -File scripts\watchdog_paper.ps1 -CheckInterval 30  # check a cada 30s
#   pwsh -File scripts\watchdog_paper.ps1 -MaxLogAge 45      # tolerar 45min stale
#
# UTF-8 BOM. PS 5.1. Stateless (nenhum file-lock).

param(
    [int]$CheckInterval = 60,        # segundos entre checks
    [int]$MaxLogAge     = 1500,      # 2026-05-18: aumentado de 45min -> 1500min (25h)
                                     # Em DAILY_CYCLE_MODE paper dorme 1440min entre
                                     # cycles. 45min causava respawn loop spurious.
    [int]$MaxGemLogAge  = 90,        # gem_loop cycle=60min; tolera 90min (+50% slack)
    [switch]$Once,                   # roda 1 check e sai (para testes)
    [switch]$Force,                  # ignora idempotent check (usar com cuidado)
    [switch]$NoGemLoop,              # opt-out de monitorar gem_loop (compat)
    [switch]$NoTgListener            # opt-out de monitorar telegram_listener (NEW 2026-05-19)
)

$scriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot  = Split-Path -Parent $scriptRoot
$scanMaster   = Join-Path $scriptRoot "scan_master.ps1"
$gemLoopPath  = Join-Path $scriptRoot "gem_loop.ps1"
$tgListenerPath = Join-Path $scriptRoot "telegram_listener.ps1"
$logDir       = Join-Path $projectRoot "logs"
$watchdogLog  = Join-Path $projectRoot "journal\watchdog.log"
$gemLog       = Join-Path $projectRoot "journal\gem_loop.log"

# IDEMPOTENT: se outro watchdog ja esta rodando E vivo, exit gracefully.
# -Force bypassa o check (util quando CIM tem cache stale).
$myPid = $PID
if (-not $Force) {
    try {
        $others = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                    Where-Object { $_.CommandLine -like "*watchdog_paper*" -and $_.ProcessId -ne $myPid })
        # Filtra apenas WDs que realmente ESTAO vivos (Get-Process valida CIM stale data)
        $aliveOthers = @($others | Where-Object {
            $null -ne (Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue)
        })
        if ($aliveOthers.Count -gt 0) {
            $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $msg = "[$ts] [SKIP] Outro watchdog VIVO ja rodando (PID=$($aliveOthers[0].ProcessId)); este PID=$myPid exit."
            Add-Content -Path $watchdogLog -Value $msg -Encoding UTF8 -ErrorAction SilentlyContinue
            Write-Host $msg
            exit 0
        }
    } catch {
        # Se CIM falhar, segue adiante (fallback safe)
    }
}


function Test-PaperAlive {
    [CmdletBinding()]
    param([string]$ProcessFilter = "*scan_master.ps1*")
    $procs = @(Get-PaperProcess -ProcessFilter $ProcessFilter)
    return ($procs.Count -gt 0)
}


function Get-PaperProcess {
    [CmdletBinding()]
    param([string]$ProcessFilter = "*scan_master.ps1*")
    try {
        $found = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                    Where-Object { $_.CommandLine -like $ProcessFilter -and $_.CommandLine -notlike "*Get-CimInstance*" -and $_.CommandLine -notlike "*watchdog*" })
        return $found
    } catch {
        return @()
    }
}


function Test-LogActivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $LogPath,
        [Parameter()] [int] $MaxAgeMinutes = 45
    )
    if (-not (Test-Path $LogPath)) { return $false }
    $age = ((Get-Date) - (Get-Item $LogPath).LastWriteTime).TotalMinutes
    return ($age -le $MaxAgeMinutes)
}


function Get-LatestLog {
    param([string]$LogDir)
    $latest = Get-ChildItem -Path $LogDir -Filter "master_*.log" -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    return $latest
}


function Start-Paper {
    [CmdletBinding()]
    param([string]$ProjectRoot, [string]$ScanMasterPath)
    $stdout = Join-Path $env:TEMP "paper_watchdog_$((Get-Date -Format 'yyyyMMdd_HHmmss')).log"

    # 2026-05-18: LIVE mode via flag file journal/LIVE_MODE_ENABLED.flag
    # Presenca = LIVE (sem -DryRun). Ausencia = DryRun (default seguro).
    # User: criar arquivo pra ativar, deletar pra desativar. Reversivel.
    $liveFlag = Join-Path $ProjectRoot "journal\LIVE_MODE_ENABLED.flag"
    $psArgs = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$ScanMasterPath)
    if (-not (Test-Path $liveFlag)) {
        $psArgs += "-DryRun"
    }

    $p = Start-Process -FilePath "powershell.exe" `
        -ArgumentList $psArgs `
        -WorkingDirectory $ProjectRoot -PassThru `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError ($stdout -replace '\.log$','_err.log')
    Start-Sleep 10
    $alive = (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) -ne $null
    return [PSCustomObject]@{
        ProcessId = $p.Id
        Alive     = $alive
        StdoutLog = $stdout
        StartTime = (Get-Date)
        Mode      = if (Test-Path $liveFlag) { "LIVE" } else { "DRY" }
    }
}


function Write-WatchdogLog {
    param([string]$LogPath, [string]$Level, [string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] [$Level] $Message"
    $line | Out-File -FilePath $LogPath -Append -Encoding utf8
    $color = if ($Level -eq "ERROR") { "Red" } elseif ($Level -eq "WARN") { "Yellow" } elseif ($Level -eq "RESPAWN") { "Cyan" } else { "Gray" }
    Write-Host $line -ForegroundColor $color
}


function Get-GemLoopProcess {
    [CmdletBinding()]
    param()
    # 2026-05-20 v2: usa Get-Process como primary (mais barato e confiavel) e
    # CIM apenas pra filter por command line. CIM intermitente sob carga
    # causava 3699 false respawn events 05/18-05/20.
    $candidates = @()
    try {
        $candidates = @(Get-Process -Name powershell -ErrorAction SilentlyContinue)
    } catch {}
    if ($candidates.Count -eq 0) { return @() }

    $alive = @()
    foreach ($p in $candidates) {
        # Tenta obter CommandLine via CIM com retry. Se falhar 3x, assume nao-match.
        $cmd = $null
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $ci = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction Stop
                if ($ci -and $ci.CommandLine) { $cmd = $ci.CommandLine; break }
            } catch {}
            if ($attempt -lt 3) { Start-Sleep -Milliseconds 300 }
        }
        if (-not $cmd) { continue }
        if ($cmd -like "*gem_loop.ps1*" -and $cmd -notlike "*Get-CimInstance*" -and $cmd -notlike "*watchdog*") {
            $alive += [PSCustomObject]@{ ProcessId = $p.Id; CommandLine = $cmd }
        }
    }
    return $alive
}


function Test-GemLoopAlive {
    [CmdletBinding()]
    param()
    return ((Get-GemLoopProcess).Count -gt 0)
}


function Start-GemLoop {
    [CmdletBinding()]
    param([string]$ProjectRoot, [string]$GemLoopPath)
    # 2026-05-18 fix: REMOVIDO -RedirectStandardOutput porque cria pipe vinculado
    # ao watchdog que mata o child quando pipe fica idle/full. gem_loop tem
    # logger proprio em journal/gem_loop.log via Add-Content (nao precisa redirect).
    # -WindowStyle Hidden roda detached sem console parent dependency.
    $psArgs = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$GemLoopPath)
    $p = Start-Process -FilePath "powershell.exe" `
        -ArgumentList $psArgs `
        -WorkingDirectory $ProjectRoot -PassThru `
        -WindowStyle Hidden
    Start-Sleep 10
    $alive = $null -ne (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)
    return [PSCustomObject]@{
        ProcessId = $p.Id
        Alive     = $alive
        StdoutLog = $null   # logger interno em journal/gem_loop.log
        StartTime = (Get-Date)
    }
}


# ── Telegram Listener supervision (NEW 2026-05-19) ──────────────────────────
# Padrao identico ao gem_loop: CIM filter + Get-Process dual-check.
# tg_listener nao tem cycle log explicito (poll 5s + 60s ideas check), entao
# soh checamos processo vivo (sem log staleness).

function Get-TgListenerProcess {
    [CmdletBinding()]
    param()
    try {
        $found = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                    Where-Object { $_.CommandLine -like "*telegram_listener.ps1*" -and $_.CommandLine -notlike "*Get-CimInstance*" -and $_.CommandLine -notlike "*watchdog*" })
        $alive = @($found | Where-Object {
            $null -ne (Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue)
        })
        return $alive
    } catch {
        return @()
    }
}


function Test-TgListenerAlive {
    # 2026-05-19 robust check: CIM primary + heartbeat file fallback.
    # tg_listener escreve mtime no journal/tg_listener_hb a cada 60s. Mtime fresh = alive.
    # NUNCA usar tg_listener.log freshness — pode ter SKIP messages falsos.
    [CmdletBinding()]
    param()
    if ((Get-TgListenerProcess).Count -gt 0) { return $true }
    $hbFile = Join-Path $projectRoot "journal\tg_listener_hb"
    if (Test-Path $hbFile) {
        $age = ((Get-Date) - (Get-Item $hbFile).LastWriteTime).TotalMinutes
        if ($age -le 3) { return $true }
    }
    return $false
}


function Start-TgListener {
    [CmdletBinding()]
    param([string]$ProjectRoot, [string]$TgListenerPath)
    $psArgs = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$TgListenerPath)
    $p = Start-Process -FilePath "powershell.exe" `
        -ArgumentList $psArgs `
        -WorkingDirectory $ProjectRoot -PassThru `
        -WindowStyle Hidden
    Start-Sleep 8
    $alive = $null -ne (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)
    return [PSCustomObject]@{
        ProcessId = $p.Id
        Alive     = $alive
        StartTime = (Get-Date)
    }
}


# ── Main loop ───────────────────────────────────────────────────────────────

if (-not (Test-Path (Split-Path $watchdogLog))) {
    New-Item -ItemType Directory -Path (Split-Path $watchdogLog) -Force | Out-Null
}

$gemLabel = if ($NoGemLoop) { "off" } else { "on (MaxGemLogAge=${MaxGemLogAge}min)" }
$tgLabel  = if ($NoTgListener) { "off" } else { "on" }
Write-WatchdogLog $watchdogLog "INFO" "Watchdog iniciado. Check=${CheckInterval}s | MaxLogAge=${MaxLogAge}min | GemLoop=$gemLabel | TgListener=$tgLabel"

# B16 fix 2026-05-20 PM6+390min: backoff + kill switch
$backoffLib = Join-Path $projectRoot "agents\lib_watchdog_backoff.ps1"
if (Test-Path $backoffLib) { . $backoffLib }
$respawnStatePath = Join-Path $projectRoot "journal\watchdog_respawn_state.json"

# B4 prevention 2026-05-20 PM6+: drift-respawn proativo.
# Antes: watchdog so respawn em (dead || stale-log). Mas daemon vivo+log fresh pode
# rodar codigo VELHO (file edit posterior ao StartTime). Drift virava bug invisivel.
# Agora: alem das 2 condicoes, drift > $DriftThresholdHours = respawn.
# 2026-05-21 R2 fix: 1h era agressivo demais. Dev sessions com edits multiplos
# disparam respawn a cada 15-30min, criando "DAILY_CYCLE_MODE teatro" (cycles
# multiplos quando esperado eh 1/dia). Bumped 1h -> 6h (1 cycle DAILY tolerado).
# Override via env var WATCHDOG_DRIFT_THRESHOLD_H pra dev mode rapido (=1).
$DriftThresholdHours = if ($env:WATCHDOG_DRIFT_THRESHOLD_H) { [double]$env:WATCHDOG_DRIFT_THRESHOLD_H } else { 6 }
$agentsDir = Join-Path $projectRoot "agents"
function Test-DaemonDrift {
    param([int] $ProcessId, [string] $AgentsDir, [double] $ThresholdHours = 1)
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $proc) { return $false }
    $startTime = $proc.StartTime
    if (-not $startTime) { return $false }
    $cutoff = $startTime.AddHours($ThresholdHours)
    $newer = Get-ChildItem -Path $AgentsDir -Filter "*.ps1" -ErrorAction SilentlyContinue |
             Where-Object { $_.LastWriteTime -gt $cutoff } |
             Select-Object -First 1
    return ($null -ne $newer)
}

do {
    # ── 1. scan_master (paper) ──────────────────────────────────────────────
    $alive = Test-PaperAlive
    $latestLog = Get-LatestLog -LogDir $logDir
    $logActive = $false
    if ($latestLog) {
        $logActive = Test-LogActivity -LogPath $latestLog.FullName -MaxAgeMinutes $MaxLogAge
    }

    # B4 prevention: drift respawn
    $drift = $false
    if ($alive) {
        $p = (Get-PaperProcess)[0]
        if ($p) {
            $drift = Test-DaemonDrift -ProcessId $p.ProcessId -AgentsDir $agentsDir -ThresholdHours $DriftThresholdHours
        }
    }
    $needsRespawn = (-not $alive) -or (-not $logActive) -or $drift

    if ($needsRespawn) {
        $reason = if (-not $alive) { "processo morto" } elseif (-not $logActive) { "log stale (>${MaxLogAge}min sem atividade)" } else { "DRIFT (codigo .ps1 modificado pos-StartTime)" }
        Write-WatchdogLog $watchdogLog "WARN" "Paper precisa respawn: $reason"

        # B16 backoff + kill switch
        if (Get-Command Test-RespawnAllowed -ErrorAction SilentlyContinue) {
            $rbk = Test-RespawnAllowed -Path $respawnStatePath -ProcName "scan_master"
            if ($rbk.killed_switch) {
                Write-WatchdogLog $watchdogLog "KILL_SWITCH" "scan_master falhou $($rbk.failures)x consecutivas -- intervencao manual requerida (deletar $respawnStatePath)"
                Start-Sleep $CheckInterval; continue
            }
            if (-not $rbk.allowed) {
                Write-WatchdogLog $watchdogLog "BACKOFF" "scan_master aguardando $($rbk.wait_seconds)s (failures=$($rbk.failures))"
                Start-Sleep $CheckInterval; continue
            }
            Add-RespawnFailure -Path $respawnStatePath -ProcName "scan_master"
        }

        Get-PaperProcess | ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
        }
        Start-Sleep 2

        $r = Start-Paper -ProjectRoot $projectRoot -ScanMasterPath $scanMaster
        if ($r.Alive) {
            Write-WatchdogLog $watchdogLog "RESPAWN" "Paper ressuscitado: PID=$($r.ProcessId) | stdout=$($r.StdoutLog)"
            # B16: reset failure counter on success
            if (Get-Command Reset-RespawnState -ErrorAction SilentlyContinue) {
                Reset-RespawnState -Path $respawnStatePath -ProcName "scan_master"
            }
        } else {
            Write-WatchdogLog $watchdogLog "ERROR" "Falha ao respawn (PID $($r.ProcessId) morreu em 10s)"
        }
    } else {
        $p = (Get-PaperProcess)[0]
        $cpu = try { (Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue).CPU } catch { "?" }
        $logAge = if ($latestLog) { [math]::Round(((Get-Date) - $latestLog.LastWriteTime).TotalMinutes, 1) } else { "?" }
        Write-WatchdogLog $watchdogLog "INFO" "Paper OK | PID=$($p.ProcessId) CPU=${cpu}s | LogAge=${logAge}min"
    }

    # ── 2. gem_loop ─────────────────────────────────────────────────────────
    if (-not $NoGemLoop) {
        $gemAlive = Test-GemLoopAlive
        # Double-check: se primeira leitura disse "morto", espera 3s e re-checa
        # (mitiga CIM cache stale ao spawnar novo gem_loop)
        if (-not $gemAlive) {
            Start-Sleep -Seconds 3
            $gemAlive = Test-GemLoopAlive
        }
        $gemLogActive = $false
        if (Test-Path $gemLog) {
            $gemLogActive = Test-LogActivity -LogPath $gemLog -MaxAgeMinutes $MaxGemLogAge
        }
        # 2026-05-20 PM4 v2: log activity eh AUTORIDADE PRIMARIA (gem_loop escreve SKIP guard
        # E cycle logs frequentemente). Detection via Get-Process/CIM se mostrou unreliable
        # em context de hidden window (PID detectavel em main shell mas nao em watchdog hidden).
        # Logica: log fresh = trust, respawn so se log REALMENTE stale (>90min) AND process dead.
        # B4 prevention: drift detection p/ gem_loop
        $gemDrift = $false
        if ($gemAlive) {
            $gp = Get-GemLoopProcess
            if ($gp) {
                $gemDrift = Test-DaemonDrift -ProcessId $gp.ProcessId -AgentsDir $agentsDir -ThresholdHours $DriftThresholdHours
            }
        }
        $gemNeedsRespawn = ((-not $gemAlive) -and (-not $gemLogActive)) -or $gemDrift

        if ($gemNeedsRespawn) {
            $gemReason = if (-not $gemAlive) { "processo morto" } elseif (-not $gemLogActive) { "log stale (>${MaxGemLogAge}min sem atividade)" } else { "DRIFT (codigo .ps1 modificado pos-StartTime)" }
            Write-WatchdogLog $watchdogLog "WARN" "GemLoop precisa respawn: $gemReason"

            # B16 backoff + kill switch
            $gemSkipRespawn = $false
            if (Get-Command Test-RespawnAllowed -ErrorAction SilentlyContinue) {
                $gbk = Test-RespawnAllowed -Path $respawnStatePath -ProcName "gem_loop"
                if ($gbk.killed_switch) {
                    Write-WatchdogLog $watchdogLog "KILL_SWITCH" "gem_loop falhou $($gbk.failures)x consecutivas -- intervencao manual requerida"
                    $gemSkipRespawn = $true
                } elseif (-not $gbk.allowed) {
                    Write-WatchdogLog $watchdogLog "BACKOFF" "gem_loop aguardando $($gbk.wait_seconds)s (failures=$($gbk.failures))"
                    $gemSkipRespawn = $true
                } else {
                    Add-RespawnFailure -Path $respawnStatePath -ProcName "gem_loop"
                }
            }

            # 2026-05-18 fix: REMOVIDO Stop-Process pre-spawn. Causava kill de gem_loop
            # VIVO quando CIM atualizava entre Test-Alive (false) e Get-Process (true).
            # gem_loop.ps1 ja tem idempotent check que aborta novos spawns se outro
            # esta vivo. Confiamos nele.

            if (-not $gemSkipRespawn) {
                $gr = Start-GemLoop -ProjectRoot $projectRoot -GemLoopPath $gemLoopPath
                if ($gr.Alive) {
                    Write-WatchdogLog $watchdogLog "RESPAWN" "GemLoop ressuscitado: PID=$($gr.ProcessId)"
                    if (Get-Command Reset-RespawnState -ErrorAction SilentlyContinue) {
                        Reset-RespawnState -Path $respawnStatePath -ProcName "gem_loop"
                    }
                } else {
                    # Detecta caso comum: novo PID saiu via idempotent SKIP (outro gem_loop ja vivo)
                    Start-Sleep 2
                    $anyAlive = Test-GemLoopAlive
                    if ($anyAlive) {
                        Write-WatchdogLog $watchdogLog "INFO" "Respawn skipped (outro gem_loop ja vivo, idempotent OK)"
                    } else {
                        Write-WatchdogLog $watchdogLog "ERROR" "Falha real ao respawn GemLoop"
                    }
                }
            }
        } else {
            $gp = (Get-GemLoopProcess)[0]
            $gemLogAge = if (Test-Path $gemLog) { [math]::Round(((Get-Date) - (Get-Item $gemLog).LastWriteTime).TotalMinutes, 1) } else { "?" }
            Write-WatchdogLog $watchdogLog "INFO" "GemLoop OK | PID=$($gp.ProcessId) | LogAge=${gemLogAge}min"
        }
    }

    # ── 3. tg_listener (NEW 2026-05-19) ─────────────────────────────────────
    if (-not $NoTgListener) {
        $tgAlive = Test-TgListenerAlive
        if (-not $tgAlive) {
            Start-Sleep -Seconds 3
            $tgAlive = Test-TgListenerAlive
        }
        if (-not $tgAlive) {
            Write-WatchdogLog $watchdogLog "WARN" "tg_listener morto, respawn..."
            $tgr = Start-TgListener -ProjectRoot $projectRoot -TgListenerPath $tgListenerPath
            if ($tgr.Alive) {
                Write-WatchdogLog $watchdogLog "RESPAWN" "tg_listener ressuscitado: PID=$($tgr.ProcessId)"
            } else {
                Start-Sleep 2
                if (Test-TgListenerAlive) {
                    Write-WatchdogLog $watchdogLog "INFO" "tg_listener respawn skip (idempotent)"
                } else {
                    Write-WatchdogLog $watchdogLog "ERROR" "tg_listener falha ao respawn"
                }
            }
        } else {
            $tp = (Get-TgListenerProcess)[0]
            Write-WatchdogLog $watchdogLog "INFO" "tg_listener OK | PID=$($tp.ProcessId)"
        }
    }

    if ($Once) { break }
    Start-Sleep -Seconds $CheckInterval
} while ($true)
