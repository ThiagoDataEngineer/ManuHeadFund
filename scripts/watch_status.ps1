# watch_status.ps1 -- Snapshot KPIs do sistema (sem efeito colateral)
#
# Uso:
#   pwsh -File scripts\watch_status.ps1
#   pwsh -File scripts\watch_status.ps1 -Telegram   # tambem envia ao TG
#
# Mostra:
#   - Tier A LIVE drawdown atual + status (OK/FLAG/CRITICAL)
#   - Mentor decisions last 24h (count APROVAR/VETAR/hallucination markers)
#   - Provider distribution (qual LLM respondeu)
#   - Watchdog status (workers vivos)
#   - V6 flag state (paper-only vs live)
#   - Kelly graduation progress (outcomes count)

param([switch]$Telegram)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$journalDir = Join-Path $projectRoot "journal"
Set-Location $projectRoot

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Get-LatestFile {
    param([string]$Pattern)
    Get-ChildItem -Path $journalDir -Filter $Pattern -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

$report = New-Object System.Collections.Generic.List[string]
$report.Add("[STATUS SNAPSHOT $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]")

# 1. Tier A drawdown
Write-Section "Tier A LIVE drawdown"
$ddFile = Get-LatestFile "tier_a_drawdown_*.json"
if ($ddFile) {
    try {
        $dd = Get-Content $ddFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($d in $dd.drawdowns) {
            $color = switch ($d.status) {
                "CRITICAL" { "Red" }
                "FLAGGED"  { "Yellow" }
                default    { "Green" }
            }
            $line = "  {0,-14} {1,6}% [{2}]" -f $d.market, $d.vs_peak_pct, $d.status
            Write-Host $line -ForegroundColor $color
            $report.Add($line)
        }
    } catch {
        Write-Host "  Erro lendo drawdown: $_" -ForegroundColor Red
    }
}

# 2. Mentor decisions last 24h
Write-Section "Mentor decisions (24h)"
$decisionsPath = Join-Path $journalDir "decisions.csv"
if (Test-Path $decisionsPath) {
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-24)
    $rows = Import-Csv $decisionsPath -Encoding UTF8
    $recent = @($rows | Where-Object {
        try { [datetime]::Parse($_.timestamp) -ge $cutoff } catch { $false }
    })
    $aprovar = @($recent | Where-Object { $_.mentor_decision -eq "APROVAR" }).Count
    $vetar   = @($recent | Where-Object { $_.mentor_decision -eq "VETAR" }).Count
    $halluc  = @($recent | Where-Object { $_.reason -match "Mesa pulou" }).Count
    $line = "  Decisoes: $($recent.Count) | APROVAR=$aprovar VETAR=$vetar | hallucination='Mesa pulou'=$halluc"
    Write-Host $line -ForegroundColor White
    $report.Add($line)
}

# 3. Watchdog workers + drift detection
Write-Section "Watchdog workers + drift"
$workers = @{
    "scan_master"      = "*scan_master.ps1*"
    "gem_loop"         = "*gem_loop.ps1*"
    "tg_listener"      = "*telegram_listener.ps1*"
    "watchdog_paper"   = "*watchdog_paper.ps1*"
}
# 2026-05-20 PM4: drift detection -- libs/config alteradas APOS daemon start = stale
$configMtime = (Get-Item (Join-Path (Split-Path $scriptDir -Parent) "agents\config.ps1") -ErrorAction SilentlyContinue).LastWriteTime
$libsModified = @()
$libsDir = Join-Path (Split-Path $scriptDir -Parent) "agents"
Get-ChildItem $libsDir -Filter "*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.LastWriteTime -gt (Get-Date).AddHours(-24)) {
        $libsModified += $_.Name
    }
}

foreach ($w in $workers.GetEnumerator()) {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -like $w.Value -and $_.CommandLine -notlike "*Get-CimInstance*" -and $_.CommandLine -notlike "*watch_status*" })
    $alive = @($procs | Where-Object { $null -ne (Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue) })
    $count = $alive.Count

    $driftWarn = ""
    if ($alive.Count -gt 0) {
        $oldest = ($alive | ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }) | Sort-Object StartTime | Select-Object -First 1
        if ($oldest -and $configMtime -and $oldest.StartTime -lt $configMtime) {
            $age = [math]::Round(((Get-Date) - $oldest.StartTime).TotalHours, 1)
            $driftWarn = " [DRIFT: ${age}h pre-config update]"
        }
    }

    $color = if ($count -gt 0 -and -not $driftWarn) { "Green" } elseif ($driftWarn) { "Yellow" } else { "Red" }
    $line = "  $($w.Key,-16) count=$count$driftWarn"
    Write-Host $line -ForegroundColor $color
    $report.Add($line)
}
if ($libsModified.Count -gt 0) {
    $line = "  libs alteradas 24h: $($libsModified -join ', ')"
    Write-Host $line -ForegroundColor DarkYellow
    $report.Add($line)
}

# 4. V6 flag state
Write-Section "V6 execution mode"
$liveFlag = Test-Path (Join-Path $journalDir "LIVE_MODE_ENABLED.flag")
$v6Flag   = Test-Path (Join-Path $journalDir "V6_LIVE_ENABLED.flag")
$mode = if ($liveFlag -and $v6Flag) { "LIVE (A: real money STANDARD V6)" }
        elseif ($liveFlag) { "PAPER (B: V6=paper, GEM=live)" }
        else { "DRYRUN" }
$report.Add("  Mode: $mode | LIVE_MODE=$liveFlag | V6_LIVE=$v6Flag")
Write-Host "  Mode: $mode" -ForegroundColor $(if ($v6Flag) { "Red" } else { "Yellow" })

# 5b. Runspace audit (preventivo — 2026-05-20 PM3)
Write-Section "Runspace libs audit"
try {
    $auditLib = Join-Path (Split-Path $scriptDir -Parent) "agents\lib_runspace_audit.ps1"
    if (Test-Path $auditLib) {
        . $auditLib
        $orchPath = Join-Path (Split-Path $scriptDir -Parent) "agents\orchestrator_v6.ps1"
        $parPath  = Join-Path (Split-Path $scriptDir -Parent) "agents\lib_orchestrator_parallel.ps1"
        $agentsP  = Join-Path (Split-Path $scriptDir -Parent) "agents"
        $audit = Test-RunspaceLibsComplete -OrchestratorPath $orchPath -ParallelPath $parPath -AgentsDir $agentsP
        $color = if ($audit.all_covered) { "Green" } else { "Red" }
        $line = "  all_covered=$($audit.all_covered) | refs=$($audit.total_refs) | libs=$($audit.total_libs) | missing=$($audit.missing_libs.Count) | orphan=$($audit.orphan_refs.Count)"
        Write-Host $line -ForegroundColor $color
        $report.Add($line)
        if (-not $audit.all_covered) {
            $report.Add("  MISSING LIBS: $($audit.missing_libs -join ', ')")
            Write-Host "  ALERTA: lib orfa em runspace! $($audit.missing_libs -join ', ')" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "  Runspace audit falhou: $_" -ForegroundColor DarkYellow
}

# 6. Kelly graduation
Write-Section "Kelly graduation"
$outcomesPath = Join-Path $journalDir "trade_outcomes.jsonl"
$count = if (Test-Path $outcomesPath) { @(Get-Content $outcomesPath -ErrorAction SilentlyContinue).Count } else { 0 }
$kellyFlag = Test-Path (Join-Path $journalDir "USE_KELLY_SIZING.flag")
$line = "  outcomes=$count (need 10+) | USE_KELLY=$kellyFlag"
Write-Host $line -ForegroundColor White
$report.Add($line)

# 6. Telegram envio (opt-in)
if ($Telegram) {
    try {
        $libTg = Join-Path (Split-Path $scriptDir -Parent) "agents\lib_telegram.ps1"
        if (Test-Path $libTg) { . $libTg }
        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
            # Usa Format-TgStatusSnapshot se disponivel (mensagem estruturada)
            $tgMsg = if (Get-Command Format-TgStatusSnapshot -ErrorAction SilentlyContinue) {
                # Coleta dados para o formato rico
                $ddArr = @()
                if ($ddFile) {
                    try { $ddArr = @((Get-Content $ddFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).drawdowns) } catch {}
                }
                $daemonMap = @{}
                foreach ($w in $workers.GetEnumerator()) {
                    $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                               Where-Object { $_.CommandLine -like $w.Value -and $_.CommandLine -notlike "*Get-CimInstance*" })
                    $alive = @($procs | Where-Object { $null -ne (Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue) })
                    $daemonMap[$w.Key] = @{ alive = ($alive.Count -gt 0) }
                }
                $modeStr = if ($liveFlag -and $v6Flag) { "LIVE" } elseif ($liveFlag) { "PAPER" } else { "DRYRUN" }
                Format-TgStatusSnapshot `
                    -Drawdowns $ddArr `
                    -NDecisions ($recent.Count) `
                    -NAprovar $aprovar `
                    -NVetar $vetar `
                    -NHalluc $halluc `
                    -Daemons $daemonMap `
                    -Mode $modeStr `
                    -NOutcomes $count `
                    -KellyActive $kellyFlag
            } else {
                $report -join "`n"
            }
            Send-TelegramAlert -Message $tgMsg | Out-Null
            Write-Host "`n[TG] Snapshot enviado" -ForegroundColor Green
        }
    } catch {
        Write-Host "[TG] Falha: $_" -ForegroundColor DarkYellow
    }
}
