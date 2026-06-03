# funding_scanner.ps1 -- Scanner de funding exhaustion (cron 1h default).
#
# Filosofia: funding rate extremo = posicionamento lotado que precede squeeze.
# Positivo alto (>=0.05%/8h) = longs lotados -> exhaustion -> SHORT bias.
# Negativo extremo = shorts lotados -> LONG bias. Sinal-lider (posicionamento
# precede o move). Enfileira trigger conviction-gated no bus -> scan_master roda
# analise full direcionada (que decide entrada com todos os gates).
#
# Universe: Get-QuantWhitelistMarkets -Mode PAPER. ClusterKey market+dia (1/dia/market).
# Zero LLM. ~N fetches CoinEx (1 por market).
#
# PS 5.1. UTF-8 BOM.

param(
    [string[]] $Markets = @(),
    [switch]   $DryRun
)

$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$agentsDir   = Join-Path $projectRoot "agents"
$journalDir  = Join-Path $projectRoot "journal"
$logPath     = Join-Path $journalDir ("funding_scanner_" + (Get-Date -Format "yyyyMMdd") + ".log")

Set-Location $projectRoot

function Write-FundLog {
    param([string]$Level, [string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] [$Level] $Message"
    if (-not (Test-Path $journalDir)) { New-Item -ItemType Directory -Path $journalDir -Force | Out-Null }
    Add-Content -Path $logPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Host $line
}

try {
    . (Join-Path $agentsDir "config.local.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "config.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_coinex.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_quant_whitelist.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_funding_exhaustion_gate.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_signal_trigger_bus.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction SilentlyContinue
} catch {
    Write-FundLog "ERROR" "Falha libs: $($_.Exception.Message)"
    exit 1
}

if (-not $Markets -or @($Markets).Count -eq 0) {
    try { $Markets = @(Get-QuantWhitelistMarkets -Mode PAPER) } catch {
        Write-FundLog "ERROR" "Falha whitelist: $($_.Exception.Message)"; exit 1
    }
}
$Markets = @($Markets | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique)
if (@($Markets).Count -eq 0) { Write-FundLog "WARN" "Nenhum market. Saindo."; exit 0 }

Write-FundLog "CYCLE" "Funding scan -- $(@($Markets).Count) markets | dry=$DryRun"

$today = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
$enqueued = 0
foreach ($mkt in $Markets) {
    try {
        $rate = CoinEx-GetFundingRate $mkt
        if ($null -eq $rate) { continue }
        $conv = Get-FundingConviction -FundingRate ([double]$rate)
        if ($conv.conviction -le 0) {
            Write-FundLog "WATCH" "$mkt -- funding=$rate (abaixo exhaustion)"
            continue
        }
        Write-FundLog "EXHAUST" "$mkt -- funding=$rate conv=$($conv.conviction) dir=$($conv.direction)"
        if ((-not $DryRun) -and (Get-Command Add-SignalTrigger -ErrorAction SilentlyContinue)) {
            $add = Add-SignalTrigger -Market $mkt -Signal "funding" -Conviction $conv.conviction `
                -Direction $conv.direction -ClusterKey "$mkt-$today" -Notes "funding=$rate/8h"
            if ($add.enqueued) { $enqueued++ }
        }
    } catch {
        Write-FundLog "ERROR" "$mkt -- $($_.Exception.Message)"
    }
}

Write-FundLog "DONE" "Cycle completo -- markets=$(@($Markets).Count) enqueued=$enqueued"
exit 0
