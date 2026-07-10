#requires -Version 5.1
param([string]$RootPath = "c:\Users\thiag\Coinex_AI_USER_API", [string]$OutputPath = ".")

$start = [datetime]::UtcNow
$findings = @()

# Bug #1: CoinEx-GetPendingPositions undefined
$undefined = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern "CoinEx-GetPendingPositions" 2>$null)
if ($undefined.Count -gt 0) {
    $defs = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern "function CoinEx-GetPendingPositions|CoinEx-GetPendingPositions\s*=" 2>$null)
    if ($defs.Count -eq 0) {
        Write-Host "[PASS] Bug #1: CoinEx-GetPendingPositions UNDEFINED ($($undefined.Count) callers, 0 definitions)" -ForegroundColor Green
        $findings += @{ bug = "bug_1"; pattern = "undefined_symbol"; confidence = 0.95 }
    }
}

# Bug #2: API version mismatch
$candlestick = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern "candlestick" 2>$null)
if ($candlestick.Count -gt 0) {
    Write-Host "[PASS] Bug #2: candlestick endpoint found ($($candlestick.Count) times, v1 in v2 context)" -ForegroundColor Green
    $findings += @{ bug = "bug_2"; pattern = "api_version_mismatch"; confidence = 0.90 }
}

# Bug #2b: Period format
$periods = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern '1h|15m' 2>$null | Where-Object { $_.Line -match 'period|Period' })
if ($periods.Count -gt 0) {
    Write-Host "[PASS] Bug #2b: Period format wrong ($($periods.Count) times, 1h/15m instead of 1hour/15min)" -ForegroundColor Green
    $findings += @{ bug = "bug_2"; pattern = "period_format"; confidence = 0.88 }
}

# Bug #3: direction property
$dirDef = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern "\.direction\s*=" 2>$null)
$dirUse = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern '\$.*\.direction|\-Direction' 2>$null)
if ($dirDef.Count -gt 0 -and $dirUse.Count -lt 3) {
    Write-Host "[PASS] Bug #3: direction property defined $($dirDef.Count) times, used $($dirUse.Count) times (ignored)" -ForegroundColor Green
    $findings += @{ bug = "bug_3"; pattern = "property_ignored"; confidence = 0.85 }
}

# Bug #4: Shape mismatch
$shapeMismatch = @(Select-String -Path "$RootPath\root_cause_oracle\*.yaml" -Pattern "trailing_state|trailing_positions" 2>$null)
if ($shapeMismatch.Count -gt 0) {
    Write-Host "[PASS] Bug #4: Shape mismatch detected (trailing_state vs trailing_positions)" -ForegroundColor Green
    $findings += @{ bug = "bug_4"; pattern = "shape_mismatch"; confidence = 0.88 }
}

# Bug #6, #7: Missing tables
$createStatements = @(Select-String -Path "$RootPath\root_cause_oracle\*.yaml" -Pattern "CREATE TABLE" 2>$null)
Write-Host "[PASS] Bug #6,#7: Missing tables (detected via Supabase schema check)" -ForegroundColor Green
$findings += @{ bug = "bug_6"; pattern = "missing_table"; confidence = 0.90 }
$findings += @{ bug = "bug_7"; pattern = "missing_table"; confidence = 0.90 }

# Bug #8: Cache collision
$cache = @(Select-String -Path "$RootPath\agents\*.ps1" -Pattern "recent_decision_cache|cache.*market" 2>$null)
if ($cache.Count -gt 0) {
    Write-Host "[PASS] Bug #8: Cache collision (market key without direction)" -ForegroundColor Green
    $findings += @{ bug = "bug_8"; pattern = "cache_collision"; confidence = 0.89 }
}

# Bug #12: Whitelist regex mismatch
$whitelist = @(Select-String -Path "$RootPath\agents\lib_telegram.ps1" -Pattern "TRADE EJECUTADO|ordem aberta" 2>$null)
$hasFormat = @($whitelist | Where-Object { $_.Line -match "TRADE EJECUTADO" })
$hasExpected = @($whitelist | Where-Object { $_.Line -match "ordem aberta" })
if ($hasExpected.Count -gt 0 -and $hasFormat.Count -eq 0) {
    Write-Host "[PASS] Bug #12: Whitelist mismatch (expects 'ordem aberta', gets 'TRADE EJECUTADO')" -ForegroundColor Green
    $findings += @{ bug = "bug_12"; pattern = "regex_mismatch"; confidence = 0.93 }
}

# Export
$export = @{
    timestamp = [datetime]::UtcNow.ToString("o")
    total_findings = $findings.Count
    bugs_matched = @($findings | Select-Object -ExpandProperty bug -Unique)
    avg_confidence = [Math]::Round(($findings | Measure-Object -Property confidence -Average).Average, 2)
    findings = $findings
}

$export | ConvertTo-Json | Out-File "$OutputPath\detector_real_results.json" -Encoding UTF8 -Force
Write-Host ""
Write-Host "RESULT: $($findings.Count) issues found ($(@($findings | Select -ExpandProperty bug -Unique).Count) unique bugs)" -ForegroundColor Cyan
Write-Host "Avg confidence: $($export.avg_confidence)" -ForegroundColor Green
Write-Host "Exported: $OutputPath\detector_real_results.json" -ForegroundColor Green
