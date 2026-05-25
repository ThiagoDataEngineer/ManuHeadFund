# audit_alpha_negative_rate.ps1 -- Audit script: pipeline esta perdendo pra BTC?
#
# Le trades fechados de journal/gem_trades.csv + journal/journal.csv (se houver
# alpha_vs_btc field). Computa rolling negative rate sobre N most recent.
#
# Se rate >60% sobre N>=20: prints ALERT + opcionalmente envia TG.
#
# Pra ser rodado:
#   - Manual: powershell -File scripts/audit_alpha_negative_rate.ps1
#   - Cron: registrar como CoinExAlphaAudit weekly
#
# PS 5.1. UTF-8 BOM.

param([switch] $SendTelegram)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

. (Join-Path (Join-Path $projectRoot "agents") "config.local.ps1") -ErrorAction SilentlyContinue
. (Join-Path (Join-Path $projectRoot "agents") "lib_alpha_vs_btc.ps1")

Write-Host "=== Alpha vs BTC Audit ==="
Write-Host ""

$alphas = @()
$tradesAudited = 0

# Source 1: gem_trades.csv
$gemTrades = Join-Path $projectRoot "journal\gem_trades.csv"
if (Test-Path $gemTrades) {
    try {
        $rows = Import-Csv -Path $gemTrades -Encoding UTF8
        foreach ($row in $rows) {
            $tradesAudited++
            if ($row.PSObject.Properties['alpha_vs_btc'] -and $row.alpha_vs_btc -and $row.alpha_vs_btc -ne "") {
                try { $alphas += [double]$row.alpha_vs_btc } catch {}
            }
        }
        Write-Host "  Source: gem_trades.csv ($($rows.Count) total rows)"
    } catch {
        Write-Warning "  gem_trades.csv parse error: $_"
    }
}

# Source 2: journal.csv
$journalCsv = Join-Path $projectRoot "journal\journal.csv"
if (Test-Path $journalCsv) {
    try {
        $rows = Import-Csv -Path $journalCsv -Encoding UTF8
        foreach ($row in $rows) {
            $tradesAudited++
            if ($row.PSObject.Properties['alpha_vs_btc'] -and $row.alpha_vs_btc -and $row.alpha_vs_btc -ne "") {
                try { $alphas += [double]$row.alpha_vs_btc } catch {}
            }
        }
        Write-Host "  Source: journal.csv ($($rows.Count) total rows)"
    } catch {
        Write-Warning "  journal.csv parse error: $_"
    }
}

Write-Host ""
Write-Host "  Trades audited: $tradesAudited"
Write-Host "  Trades with alpha_vs_btc computed: $($alphas.Count)"
Write-Host ""

if ($alphas.Count -eq 0) {
    Write-Host "  No alpha data available yet. Audit skipped." -ForegroundColor Yellow
    Write-Host "  (lib_alpha_vs_btc not wired into Close-Trade yet, OR BTC cache empty)"
    exit 0
}

$result = Get-AlphaNegativeRate -Alphas $alphas -MinSampleSize 20 -AlertThresholdPct 60

Write-Host "=== Result ==="
Write-Host "  n: $($result.n)"
Write-Host "  Negative count: $($result.negative_count)"
Write-Host "  Negative rate: $($result.negative_rate_pct)%"
Write-Host "  Threshold: $($result.threshold_pct)%"
Write-Host "  Reason: $($result.reason)"

if ($result.alert) {
    Write-Host "  ALERT TRIGGERED" -ForegroundColor Red
    if ($SendTelegram -and (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue)) {
        $msg = "[ALPHA AUDIT ALERT] Pipeline perdendo pra BTC`nNegative rate: $($result.negative_rate_pct)% over $($result.n) trades`nThreshold: $($result.threshold_pct)%`nConsiderar: pivotar pra BTC-only OR re-validar predicate edge"
        Send-TelegramAlert -Message $msg | Out-Null
        Write-Host "  Telegram alert sent."
    }
    exit 1
} else {
    Write-Host "  OK ($($result.reason))" -ForegroundColor Green
    exit 0
}
