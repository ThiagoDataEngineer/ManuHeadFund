# gem_loop.ps1 -- Loop dedicado GemAgent (paralelo ao scan_master daily).
#
# Por que existe (2026-05-18):
# - scan_master roda DAILY (1x/dia) -- ideal para orchestrator V6 + trailing
# - GemAgent precisa de ritmo INTRA-DAY (micro-cap pumps tempo-sensiveis)
# - Loop separado: cycle 1h default
#
# Mesmos guards do gem_executor (tier filter + sizing + freq + custodial removido).
# Idempotent: nao spawna se ja tem gem_loop rodando.
#
# Uso:
#   pwsh -File scripts\gem_loop.ps1                       # cycle default 60min
#   pwsh -File scripts\gem_loop.ps1 -CheckInterval 30     # 30min cycle
#   pwsh -File scripts\gem_loop.ps1 -Force                # bypassa idempotent
#
# PS 5.1. UTF-8 BOM.

param(
    [int]$CheckInterval = 60,   # minutos entre cycles GemScan
    [switch]$Once,              # roda 1 cycle e sai (teste)
    [switch]$Force              # ignora idempotent
)

$scriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot  = Split-Path -Parent $scriptRoot
$agentsDir    = Join-Path $projectRoot "agents"
$gemLog       = Join-Path $projectRoot "journal\gem_loop.log"

function Write-GemLog {
    param([string]$Level, [string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $gemLog -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Host $line
}

# IDEMPOTENT: se outro gem_loop ja esta rodando E vivo, exit gracefully
$myPid = $PID
if (-not $Force) {
    try {
        $others = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                    Where-Object { $_.CommandLine -like "*gem_loop*" -and $_.ProcessId -ne $myPid })
        $aliveOthers = @($others | Where-Object {
            $null -ne (Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue)
        })
        if ($aliveOthers.Count -gt 0) {
            Write-GemLog "SKIP" "Outro gem_loop VIVO ja rodando (PID=$($aliveOthers[0].ProcessId)); este PID=$myPid exit."
            exit 0
        }
    } catch {}
}

# Verifica LIVE mode flag (mesmo flag do scan_master)
$liveFlag = Join-Path $projectRoot "journal\LIVE_MODE_ENABLED.flag"
$isLive = Test-Path $liveFlag
$modeLabel = if ($isLive) { "LIVE" } else { "DRY" }

# Carrega config + libs
Set-Location $projectRoot

# Config
try {
    . (Join-Path $agentsDir "config.local.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "config.ps1") -ErrorAction Stop
} catch {
    Write-GemLog "ERROR" "Falha ao carregar config: $($_.Exception.Message)"
    exit 1
}

# Core libs (ordem importa)
try {
    . (Join-Path $agentsDir "lib_coinex.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_idempotency.ps1") -ErrorAction SilentlyContinue  # B14 callback idempotency
    . (Join-Path $agentsDir "lib_retry.ps1") -ErrorAction SilentlyContinue  # B19 retry transient
    . (Join-Path $agentsDir "lib_order_idempotency.ps1") -ErrorAction SilentlyContinue  # B19b PlaceOrder client_id
    . (Join-Path $agentsDir "lib_price_freshness.ps1") -ErrorAction SilentlyContinue  # B18 stale price
    . (Join-Path $agentsDir "lib_mentor_hallucination_detector.ps1") -ErrorAction SilentlyContinue  # P0b FQS hallucination
    . (Join-Path $agentsDir "lib_journal.ps1") -ErrorAction Stop
} catch {
    Write-GemLog "ERROR" "Falha ao carregar core libs: $($_.Exception.Message)"
    exit 1
}

# Guards + safety
try {
    . (Join-Path $agentsDir "lib_live_guards.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_quant_whitelist.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_gem_safety.ps1") -ErrorAction SilentlyContinue
    # B9 fix: TTL cache pra GEM re-veto loop
    . (Join-Path $agentsDir "lib_gem_decision_cache.ps1") -ErrorAction SilentlyContinue
} catch {
    Write-GemLog "WARN" "Falha ao carregar guards: $($_.Exception.Message)"
}

# Tech agent (precisa estar disponivel para gem_executor)
# Carrega com erro visivel (Stop) — catch loga + continua (fallback no gem_executor)
try {
    . (Join-Path $agentsDir "tech_agent_ai.ps1") -ErrorAction Stop
    if (Get-Command Get-ToriTrendlineSignal -ErrorAction SilentlyContinue) {
        Write-GemLog "DEBUG" "Tech agent carregado com sucesso"
    } else {
        Write-GemLog "WARN" "tech_agent_ai carregou mas Get-ToriTrendlineSignal nao disponivel"
    }
} catch {
    Write-GemLog "WARN" "Falha ao carregar tech_agent_ai (fallback gem_executor): $($_.Exception.Message)"
}

# Gem agents (GemAgent DEVE vir antes de gem_executor)
try {
    . (Join-Path $agentsDir "gem_agent.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "gem_executor.ps1") -ErrorAction Stop
} catch {
    Write-GemLog "ERROR" "Falha ao carregar gem agents: $($_.Exception.Message)"
    exit 1
}

# Validar que Invoke-GemScan está disponível
if (-not (Get-Command "Invoke-GemScan" -ErrorAction SilentlyContinue)) {
    Write-GemLog "ERROR" "Invoke-GemScan nao esta disponivel apos sourcing"
    exit 1
}

Write-GemLog "INFO" "GemLoop iniciado. Interval=${CheckInterval}min | Mode=$modeLabel | PID=$myPid"

# Validar carregamentos
Write-GemLog "DEBUG" "Libs loaded: Invoke-GemScan=$(Get-Command 'Invoke-GemScan' -ErrorAction SilentlyContinue | % {$_.Name})"

function Invoke-GemCycle-Once {
    param([bool]$DryRun)
    try {
        Write-GemLog "CYCLE" "Iniciando GemScan (mode=$(if ($DryRun) {'DRY'} else {'LIVE'}))"
        $gems = @(Invoke-GemScan -TopN 5)
        # R4 fix 2026-05-21: cache check ANTES do log "encontrados" + Invoke-GemExecute.
        # Resolve PEAQ/PROVE re-detection spam.
        if (Get-Command Test-GemRecentlyRejected -ErrorAction SilentlyContinue -and $gems.Count -gt 0) {
            $cachePath = Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json"
            $filtered = @(); $skipped = @()
            foreach ($g in $gems) {
                # 2026-06-03: Reduzido TTL de 60 para 5 minutos
                # Tori agora FORÇA ENTRY, então gems rejeitados devem ser re-tentados rapidamente
                if (Test-GemRecentlyRejected -Path $cachePath -Market $g.market -TtlMinutes 5) {
                    $skipped += $g.market
                } else { $filtered += $g }
            }
            if ($skipped.Count -gt 0) {
                Write-GemLog "INFO" "Cache hit: $($skipped.Count) gem(s) skip -- $($skipped -join ',')"
            }
            $gems = $filtered
        }
        Write-GemLog "INFO" "GemScan: $($gems.Count) gem(s) encontrados"

        foreach ($g in $gems) {
            $mkt = if ($g.market) { $g.market } else { "?" }
            $score = if ($g.score) { $g.score } else { 0 }
            Write-GemLog "GEM" "$mkt score=$score mode=$($g.mode)"
            # gem_executor ja tem guards (tier + sizing + freq)
            try {
                $r = Invoke-GemExecute -Gem $g -DryRun:$DryRun
                if ($r.blocked) {
                    Write-GemLog "BLOCKED" "$mkt -- $($r.blocked_by -join '; ')"
                } elseif ($r.order_id) {
                    Write-GemLog "EXEC" "$mkt order=$($r.order_id) qty=$($r.qty)"
                } elseif ($r.dry_run) {
                    Write-GemLog "DRY" "$mkt simulado (sizing=$($r.sizing_usd))"
                }
            } catch {
                Write-GemLog "ERROR" "Invoke-GemExecute $mkt -- $($_.Exception.Message)"
            }
        }
    } catch {
        Write-GemLog "ERROR" "GemCycle: $($_.Exception.Message)"
    }
}

# Main loop
if ($Once) {
    Invoke-GemCycle-Once -DryRun (-not $isLive)
    Write-GemLog "INFO" "Once mode -- exit"
    exit 0
}

while ($true) {
    Invoke-GemCycle-Once -DryRun (-not $isLive)
    $sleepSec = $CheckInterval * 60
    Write-GemLog "INFO" "Dormindo ${CheckInterval}min ate proximo cycle"
    Start-Sleep -Seconds $sleepSec
}
