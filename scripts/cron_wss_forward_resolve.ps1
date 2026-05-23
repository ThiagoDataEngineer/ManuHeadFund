# cron_wss_forward_resolve.ps1 -- Weekly: resolve WSS forward signals + audit alert.
#
# Caminho 2 final wire: completa o forward validation loop.
#
# Operacao:
#   1. Read pending signals (lib_wss_forward_tracker:Get-PendingWssSignals)
#   2. For each pending: fetch CoinEx 1day candles + check se passou window_bars
#   3. If yes: compute outcome max-close em window_bars after triggered_at
#      hit = outcome >= 1.6% net (matches WSS threshold)
#   4. Resolve-WssSignal (append resolved entry)
#   5. After all: Get-WssForwardStats + compare predicted vs realized
#   6. TG alert se realized lift desvia >2sigma do predicted
#
# Cron: weekly Sat 22:00 BRT (after WeeklyDataRefresh).
# Fail-soft em cada step.

param([switch] $DryRun)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

. (Join-Path $projectRoot "agents\config.local.ps1") -ErrorAction SilentlyContinue
. (Join-Path $projectRoot "agents\lib_wss_forward_tracker.ps1")
. (Join-Path $projectRoot "agents\lib_coinex.ps1") -ErrorAction SilentlyContinue
. (Join-Path $projectRoot "agents\lib_telegram.ps1") -ErrorAction SilentlyContinue

$logFile = Join-Path $projectRoot ("logs\wss_forward_resolve_" + (Get-Date -Format "yyyyMMdd") + ".log")
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
function Log { param($M) "[$((Get-Date).ToString('HH:mm:ss'))] $M" | Tee-Object -FilePath $logFile -Append }

Log "=== WSS Forward Resolve cron START ==="

$pending = Get-PendingWssSignals
Log "  Pending: $(@($pending).Count)"

if (@($pending).Count -eq 0) {
    Log "  Nothing to resolve."
    Log "=== Done ==="
    exit 0
}

# Helper: fetch CoinEx daily candles
function _FetchDaily {
    param([string]$Market, [int]$Limit=30)
    foreach ($mtype in @("futures","spot")) {
        try {
            $url = "https://api.coinex.com/v2/$mtype/kline?market=$Market&period=1day&limit=$Limit"
            $r = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 10 -ErrorAction Stop
            if ($r.code -eq 0 -and $r.data) {
                return @($r.data | ForEach-Object {
                    [PSCustomObject]@{
                        ts = $_.created_at
                        close = [double]$_.close
                    }
                })
            }
        } catch {}
    }
    return @()
}

$NET_THRESHOLD = 1.6  # 1% gross + 0.6% costs
$resolved = 0
$skipped = 0

foreach ($p in $pending) {
    $market = $p.market
    $triggeredAt = $p.triggered_at
    $entryPrice = [double]$p.entry_price
    $windowBars = [int]$p.window_bars

    # Parse triggered date
    try {
        $triggeredDt = [System.DateTimeOffset]::Parse($triggeredAt).UtcDateTime
    } catch {
        Log "  SKIP $market -- triggered_at parse fail"
        $skipped++
        continue
    }

    # Check se passou window_bars dias
    $daysElapsed = ((Get-Date).ToUniversalTime() - $triggeredDt).TotalDays
    if ($daysElapsed -lt ($windowBars + 0.5)) {
        Log "  SKIP $market -- only $([math]::Round($daysElapsed,1))d elapsed (need $windowBars)"
        $skipped++
        continue
    }

    # Fetch candles
    $candles = _FetchDaily -Market $market -Limit 30
    if (-not $candles -or $candles.Count -lt $windowBars + 1) {
        Log "  SKIP $market -- insufficient candles ($($candles.Count))"
        $skipped++
        continue
    }

    # Find triggered bar index
    $triggeredTs = $triggeredDt.ToString("yyyy-MM-dd")
    $startIdx = -1
    for ($i = 0; $i -lt $candles.Count; $i++) {
        $ts = $candles[$i].ts
        # Convert milliseconds to date
        try {
            $candleDt = (Get-Date "1970-01-01Z").AddMilliseconds([int64]$ts)
            $candleStr = $candleDt.ToString("yyyy-MM-dd")
            if ($candleStr -eq $triggeredTs) { $startIdx = $i; break }
        } catch {}
    }
    if ($startIdx -lt 0 -or $startIdx + $windowBars -ge $candles.Count) {
        Log "  SKIP $market -- triggered bar not found in cache window"
        $skipped++
        continue
    }

    # Max close em window_bars after entry
    $maxClose = $entryPrice
    for ($j = $startIdx + 1; $j -le $startIdx + $windowBars; $j++) {
        if ($candles[$j].close -gt $maxClose) { $maxClose = $candles[$j].close }
    }
    $outcomePct = ($maxClose - $entryPrice) / $entryPrice * 100
    $netOutcome = $outcomePct - 0.6  # net of costs
    $hit = $netOutcome -ge 1.0

    if ($DryRun) {
        Log "  DRYRUN $market -- outcome=$([math]::Round($outcomePct,2))% net=$([math]::Round($netOutcome,2))% hit=$hit"
    } else {
        Resolve-WssSignal -Market $market -TriggeredAtDate $triggeredTs -ExitPrice $maxClose `
            -RealizedPct $outcomePct -Hit $hit
        Log "  RESOLVED $market -- outcome=$([math]::Round($outcomePct,2))% hit=$hit"
    }
    $resolved++
}

# Stats post-resolve
$stats = Get-WssForwardStats
Log ""
Log "=== Stats ==="
Log "  Total resolved (cumulative): $($stats.n_resolved)"
Log "  Hit count: $($stats.hit_count) ($($stats.hit_rate_pct)%)"
Log "  Mean realized: $($stats.mean_realized_pct)%"
Log "  Still pending: $($stats.n_pending)"

# Audit: realized vs predicted (WSS predicted CI was [-44, +26] em Branch A v2)
# Se hit_rate_pct > 60% sobre n>=10: lift positivo confirmado = TG alert ALPHA OK
# Se hit_rate_pct < 30% sobre n>=10: edge confirmadamente negativo = TG alert KILL
if ($stats.n_resolved -ge 10) {
    if ($stats.hit_rate_pct -ge 60) {
        $msg = "[WSS FORWARD AUDIT] Hit rate FORTE`nresolved n=$($stats.n_resolved)`nhit_rate=$($stats.hit_rate_pct)% (vs baseline ~50%)`nmean realized=$($stats.mean_realized_pct)%`nThesis CONFIRMADA -- considerar paper deploy"
        if (-not $DryRun -and (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue)) {
            try { Send-TelegramAlert -Message $msg | Out-Null } catch {}
        }
        Log "  ALERT: thesis confirmed"
    } elseif ($stats.hit_rate_pct -le 30) {
        $msg = "[WSS FORWARD AUDIT] Hit rate FRACO`nresolved n=$($stats.n_resolved)`nhit_rate=$($stats.hit_rate_pct)% (vs baseline ~50%)`nmean realized=$($stats.mean_realized_pct)%`nThesis REFUTADA -- considerar kill WSS"
        if (-not $DryRun -and (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue)) {
            try { Send-TelegramAlert -Message $msg | Out-Null } catch {}
        }
        Log "  ALERT: thesis refuted"
    } else {
        Log "  Inconclusive (hit_rate $($stats.hit_rate_pct)% between 30-60%)"
    }
} else {
    Log "  n=$($stats.n_resolved) < 10, sample insufficient for audit"
}

Log "=== Done -- resolved=$resolved skipped=$skipped ==="
exit 0
