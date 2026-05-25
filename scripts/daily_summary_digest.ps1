# daily_summary_digest.ps1 -- End-of-day report ao Telegram (23:55 BRT)
#
# Roda 1x/dia, agrega tudo do dia:
#   - Mentor decisions (APROVAR/VETAR breakdown)
#   - Provider distribution
#   - Drawdown Tier A LIVE
#   - Crons que rodaram + status
#   - Hallucination counts (sanity check)
#   - Missing commands warnings

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$journalDir = Join-Path $projectRoot "journal"
Set-Location $projectRoot

. (Join-Path (Join-Path $projectRoot "agents") "lib_telegram.ps1")

$today = Get-Date -Format "yyyy-MM-dd"
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("=== DAILY DIGEST $today ===")

# 1. Mentor decisions
try {
    $decPath = Join-Path $journalDir "decisions.csv"
    if (Test-Path $decPath) {
        $rows = Import-Csv $decPath -Encoding UTF8
        $todayRows = @($rows | Where-Object { $_.timestamp -like "$today*" })
        $aprovar = @($todayRows | Where-Object { $_.mentor_decision -eq "APROVAR" }).Count
        $vetar   = @($todayRows | Where-Object { $_.mentor_decision -eq "VETAR" }).Count
        $skip    = @($todayRows | Where-Object { $_.decision -eq "SKIP" }).Count
        $halluc  = @($todayRows | Where-Object { $_.reason -match "Mesa pulou" }).Count
        $lines.Add("Mentor: APROVAR=$aprovar VETAR=$vetar SKIP=$skip | hallucination=$halluc")

        # Provider distribution
        $provs = @{}
        foreach ($r in $todayRows) {
            $p = $r.provider_used; if (-not $p) { $p = "none" }
            if (-not $provs.ContainsKey($p)) { $provs[$p] = 0 }
            $provs[$p]++
        }
        $provStr = ($provs.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "$($_.Key):$($_.Value)" }) -join " "
        $lines.Add("Providers: $provStr")
    }
} catch { $lines.Add("Mentor stats: ERR $_") }

# 2. Drawdown Tier A
try {
    $ddFile = Get-ChildItem -Path $journalDir -Filter "tier_a_drawdown_*.json" -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($ddFile) {
        $dd = Get-Content $ddFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $worst = ($dd.drawdowns | Sort-Object vs_peak_pct | Select-Object -First 1)
        $crit = @($dd.drawdowns | Where-Object { $_.status -eq "CRITICAL" }).Count
        $flag = @($dd.drawdowns | Where-Object { $_.status -eq "FLAGGED" }).Count
        $lines.Add("Tier A DD: worst=$($worst.market) $($worst.vs_peak_pct)% | crit=$crit flag=$flag")
    }
} catch {}

# 3. Cron last runs
try {
    $crons = @("CoinExPromotionCron","CoinExKellyGraduation","CoinExParallelGraduation","CoinExWeeklyDataRefresh","CoinExHourlyHeartbeat")
    foreach ($c in $crons) {
        $t = Get-ScheduledTask -TaskName $c -ErrorAction SilentlyContinue
        if ($t) {
            $info = Get-ScheduledTaskInfo -TaskName $c
            $lr = $info.LastRunTime.ToString("HH:mm")
            $code = "0x" + $info.LastTaskResult.ToString("X")
            $lines.Add("  $c last=$lr result=$code")
        }
    }
} catch {}

# 4. Missing commands report
try {
    . (Join-Path (Join-Path $projectRoot "agents") "lib_runspace_warnings.ps1")
    $mc = Get-MissingCommandsReport -LastHours 24
    if ($mc.total -gt 0) {
        $lines.Add("Missing cmds 24h: $($mc.total) - " + (($mc.by_command.GetEnumerator() | ForEach-Object { "$($_.Key)x$($_.Value)" }) -join ","))
    } else {
        $lines.Add("Missing cmds 24h: 0")
    }
} catch {}

# 5. Trade outcomes
try {
    $outPath = Join-Path $journalDir "trade_outcomes.jsonl"
    $count = if (Test-Path $outPath) { @(Get-Content $outPath -ErrorAction SilentlyContinue).Count } else { 0 }
    $lines.Add("Trade outcomes: $count (Kelly needs 10+)")
} catch {}

# 6. V6 flag state
$v6 = Test-Path (Join-Path $journalDir "V6_LIVE_ENABLED.flag")
$live = Test-Path (Join-Path $journalDir "LIVE_MODE_ENABLED.flag")
$mode = if ($v6 -and $live) { "LIVE_V6" } elseif ($live) { "PAPER_V6_LIVE_GEM" } else { "DRYRUN" }
$lines.Add("Mode: $mode")

# 7. Schema audit promotion_pipeline (C6 â€” detecta entries com schema invalido tipo HYPE)
try {
    $svPath = Join-Path $projectRoot "agents\lib_schema_validators.ps1"
    if (Test-Path $svPath) {
        . $svPath
        $rep = Invoke-PromotionPipelineAudit -Path (Join-Path $journalDir "promotion_pipeline.jsonl")
        if ($rep.total_lines -gt 0) {
            $pct = [math]::Round(100*$rep.invalid/$rep.total_lines, 1)
            $by = ($rep.violations_by_market.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Key)x$($_.Value)" }) -join ","
            $lines.Add("Schema audit: $($rep.invalid)/$($rep.total_lines) invalid ($pct%) [$by]")
        }
    }
} catch { $lines.Add("Schema audit: ERR $_") }

# 8. Replay analyzer (auto daily â€” mostra metricas merit-only)
try {
    $replayScript = Join-Path $scriptDir "replay_decisions_analyzer.ps1"
    if (Test-Path $replayScript) {
        $out = & $replayScript -LastN 50 -JsonOutput 2>&1 | Out-String
        try {
            $rep = $out | ConvertFrom-Json
            if ($rep.summary) {
                $merit = $rep.summary.total - $rep.summary.improved
                $lines.Add("Replay 50: merit=$merit improved=$($rep.summary.improved) needs_attn=$($rep.summary.needs_attention)")
            }
        } catch {}
    }
} catch {}

$msg = $lines -join "`n"
Write-Host $msg
Send-TelegramAlert -Message $msg | Out-Null
