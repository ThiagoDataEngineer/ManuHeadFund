# tori_trades_runner.ps1 - Launcher for Tori Trades analysis
#
# Usage:
#   .\tori_trades_runner.ps1 -MaxPairs 50 -Verbose
#
# Output: Returns PSCustomObject array ready for JSON/HTML export
#
# No writes to project, no API modifications — exploratory only

param(
    [int]$MaxPairs = 100,
    [int]$BatchSize = 20,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# ============================================================================
# LOAD DEPENDENCIES
# ============================================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "Script directory: $scriptDir" -ForegroundColor Cyan

# Load config (for COINEX_BASE_URL, credentials)
$configPath = Join-Path $scriptDir "config.ps1"
if (Test-Path $configPath) {
    Write-Host "Loading config.ps1..." -ForegroundColor Yellow
    . $configPath
} else {
    Write-Warning "config.ps1 not found at $configPath"
}

# Load CoinEx library (for API access)
$coinexPath = Join-Path $scriptDir "lib_coinex.ps1"
if (Test-Path $coinexPath) {
    Write-Host "Loading lib_coinex.ps1..." -ForegroundColor Yellow
    . $coinexPath
} else {
    Write-Error "lib_coinex.ps1 not found at $coinexPath"
    exit 1
}

# Load rate limiter if available
$rateLimiterPath = Join-Path $scriptDir "lib_rate_limiter.ps1"
if (Test-Path $rateLimiterPath) {
    Write-Host "Loading lib_rate_limiter.ps1..." -ForegroundColor Yellow
    . $rateLimiterPath
}

# Load retry logic if available
$retryPath = Join-Path $scriptDir "lib_coinex_retry.ps1"
if (Test-Path $retryPath) {
    Write-Host "Loading lib_coinex_retry.ps1..." -ForegroundColor Yellow
    . $retryPath
}

# Load Tori scanner
$scannerPath = Join-Path $scriptDir "lib_tori_trades_scanner.ps1"
if (Test-Path $scannerPath) {
    Write-Host "Loading lib_tori_trades_scanner.ps1..." -ForegroundColor Yellow
    . $scannerPath
} else {
    Write-Error "lib_tori_trades_scanner.ps1 not found at $scannerPath"
    exit 1
}

# Verify base URL configured
if (-not $COINEX_BASE_URL) {
    Write-Warning "COINEX_BASE_URL not configured; using default https://api.coinex.com"
    $COINEX_BASE_URL = "https://api.coinex.com"
}

Write-Host "CoinEx API Base URL: $COINEX_BASE_URL" -ForegroundColor Cyan

# ============================================================================
# RUN ANALYSIS
# ============================================================================

Write-Host "`n" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host "TORI TRADES TRENDLINE SCANNER" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Config: MaxPairs=$MaxPairs, Verbose=$Verbose" -ForegroundColor Yellow
Write-Host "`n" -ForegroundColor White

try {
    $results = Invoke-ToriTradesAnalysis -MaxPairs $MaxPairs -BatchSize $BatchSize -Verbose:$Verbose

    # ============================================================================
    # DISPLAY RESULTS
    # ============================================================================

    if ($results.Count -eq 0) {
        Write-Host "No setups found." -ForegroundColor Yellow
    } else {
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "TOP 20 HIGHEST-QUALITY SETUPS" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green

        $top20 = $results | Select-Object -First 20 | ForEach-Object {
            [PSCustomObject]@{
                Market      = $_.market
                TF          = $_.timeframe
                Type        = $_.trend_type
                Quality     = $_.trendline_quality
                ActionLine  = "{0:F8}" -f $_.action_line
                Price       = "{0:F8}" -f $_.current_price
                Entry       = "{0:F8}" -f $_.entry_price
                Target      = "{0:F8}" -f $_.target_price
                "Risk:Reward" = "{0:N2}" -f $_.ratio
                Confluence  = $_.confluence_score
                Confirmed   = $_.entry_confirmation
                Scalp       = if ($_.scalp_eligible) { "YES" } else { "NO" }
            }
        }

        $top20 | Format-Table -AutoSize

        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "FILTERED RESULTS BY QUALITY" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green

        $aPlus = $results | Where-Object { $_.trendline_quality -eq "A+" }
        Write-Host "A+ Quality:      $($aPlus.Count) setups"

        $confirmed = $results | Where-Object { $_.entry_confirmation -eq "CONFIRMED" }
        Write-Host "Entry Confirmed: $($confirmed.Count) setups"

        $scalps = $results | Where-Object { $_.scalp_eligible }
        Write-Host "Scalp Eligible:  $($scalps.Count) setups (R:R >= $script:RR_SCALP_THRESHOLD)"

        $highConf = $results | Where-Object { $_.confluence_score -ge 75 }
        Write-Host "High Confluence: $($highConf.Count) setups (score >= 75)"
    }

    # ============================================================================
    # SAVE TO JSON (for later HTML export)
    # ============================================================================

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputFile = Join-Path $scriptDir "..\journal\tori_setups_${timestamp}.json"

    $outputDir = Split-Path -Parent $outputFile
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }

    Export-ToriSetupsToJson -Setups $results -OutputPath $outputFile

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "Output saved to: $outputFile" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green

    # Return for pipeline use
    return $results
}
catch {
    Write-Error "Fatal error during analysis: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}
