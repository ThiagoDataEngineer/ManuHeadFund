# gem_scanner_live.ps1 — Scan CoinEx gainers/losers → Insere em gems_candidates Supabase
# Origem de candidatos para gem_executor_live.ps1
# 2026-07-15: Discovery pipeline

param(
    [int] $Limit = 50,
    [bool] $UseCache = $true,
    [int] $CacheMinutes = 5
)

$ErrorActionPreference = "Stop"

# =========================================================================
# CONFIG
# =========================================================================
$configPath = Join-Path $PSScriptRoot "..\agents\config.local.ps1"
if (Test-Path $configPath) {
    . $configPath
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "GEM SCANNER LIVE — Scan CoinEx > Supabase" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# =========================================================================
# FETCH GAINERS/LOSERS FROM COINEX (usar config/universos)
# =========================================================================
Write-Host "[1] Fetching CoinEx data..." -ForegroundColor Yellow

$tickers = @()

# Carregar universos do config
$shortUniversePath = Join-Path $PSScriptRoot "..\config\short_universe.json"
$longUniversePath = Join-Path $PSScriptRoot "..\config\long_universe.json"

$topMarkets = @()
if (Test-Path $shortUniversePath) {
    $shortUni = Get-Content $shortUniversePath -Raw | ConvertFrom-Json
    $topMarkets += @($shortUni.markets | Select-Object -ExpandProperty market | Select-Object -First 15)
}
if (Test-Path $longUniversePath) {
    $longUni = Get-Content $longUniversePath -Raw | ConvertFrom-Json
    $topMarkets += @($longUni.markets | Select-Object -ExpandProperty market | Select-Object -First 15)
}

# Se nao conseguir carregar, usar fallback
if ($topMarkets.Count -eq 0) {
    $topMarkets = @("BTCUSDT", "ETHUSDT", "LINKUSDT", "DOGEUSDT", "AVAXUSDT", "BNBUSDT", "XRPUSDT")
}

try {
    foreach ($market in $topMarkets) {
        try {
            $url = 'https://api.coinex.com/v2/spot/kline?market=' + $market + '&period=1day&limit=30'
            $resp = Invoke-RestMethod -Uri $url -TimeoutSec 5 -ErrorAction Stop

            if ($resp.data -and @($resp.data).Count -gt 0) {
                $closes = @($resp.data | ForEach-Object { [double]$_.close })
                $change24h = if ($closes.Count -ge 2) {
                    (($closes[-1] - $closes[-2]) / $closes[-2]) * 100
                } else { 0 }

                $tickers += [PSCustomObject]@{
                    symbol = $market
                    change24h = $change24h
                    volume24h = if ($resp.data[0].volume) { [double]$resp.data[0].volume } else { 0 }
                }
            }
        } catch {
            # Continua com proximo market
        }
    }

    $tickers = $tickers | Sort-Object -Property change24h -Descending

    Write-Host "  ✓ Fetched $($tickers.Count) coins from config universos" -ForegroundColor Green
} catch {
    Write-Host "  ✗ CoinEx API error: $_" -ForegroundColor Red
    Write-Host "  (Continuing with fallback)" -ForegroundColor Yellow
}

# =========================================================================
# GENERATE CANDIDATES
# =========================================================================
Write-Host ""
Write-Host "[2] Generating candidates..." -ForegroundColor Yellow

$candidates = @()

foreach ($ticker in $tickers) {
    # Skip pure stablecoins (USDT, USDC, BUSD como base, nao par)
    if ($ticker.symbol -match "^(USDT|USDC|BUSD|TUSD)$") {
        continue
    }

    # Skip if volume too low (< $100k 24h)
    if ([double]$ticker.volume24h -lt 100000) {
        continue
    }

    # Determinar direcao baseado em change24h
    $change = [double]$ticker.change24h
    $direction = "LONG"

    if ($change -lt -5) {
        $direction = "SHORT"  # Downtrend candidate
    } elseif ($change -gt 10) {
        $direction = "LONG"   # Uptrend candidate (mas precisa validar)
    }

    # Tori score placeholder (sera calculado por gem_executor)
    $toriScore = 65  # Default neutral score

    $candidate = [PSCustomObject]@{
        market = $ticker.symbol
        direction = $direction
        tori_score = $toriScore
        change_24h = $change
        volume_24h = [double]$ticker.volume24h
        discovered_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        status = "pending"
    }

    $candidates += $candidate
}

Write-Host "  ✓ Generated $($candidates.Count) candidates" -ForegroundColor Green
if ($candidates.Count -gt 0) {
    Write-Host "  Sample:" -ForegroundColor Cyan
    $candidates | Select-Object -First 3 | ForEach-Object {
        Write-Host "    • $($_.market) $($_.direction) (change: $($_.change_24h)%)" -ForegroundColor Gray
    }
}

# =========================================================================
# INSERT INTO SUPABASE
# =========================================================================
Write-Host ""
Write-Host "[3] Inserting into Supabase gems_candidates..." -ForegroundColor Yellow

if (-not $env:SUPABASE_URL -or -not $env:SUPABASE_ANON_KEY) {
    Write-Host "  ✗ SUPABASE env vars missing" -ForegroundColor Red
    Write-Host "  (Skipping insert)" -ForegroundColor Yellow
    exit 0
}

$inserted = 0
$failed = 0

foreach ($gem in $candidates) {
    try {
        $body = $gem | ConvertTo-Json

        $url = "$env:SUPABASE_URL/rest/v1/gems_candidates"
        $headers = @{
            "Authorization" = "Bearer $env:SUPABASE_ANON_KEY"
            "apikey" = $env:SUPABASE_ANON_KEY
            "Content-Type" = "application/json"
            "Prefer" = "return=minimal"
        }

        $response = Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body $body -ErrorAction Stop

        $inserted++
        Write-Host "  ✓ $($gem.market) inserted" -ForegroundColor Green

    } catch {
        $failed++
        Write-Host "  ✗ $($gem.market) failed: $_" -ForegroundColor Red
    }
}

# =========================================================================
# SUMMARY
# =========================================================================
Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "SUMMARY" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Fetched: $($tickers.Count) coins from CoinEx" -ForegroundColor Cyan
Write-Host "Generated: $($candidates.Count) candidates" -ForegroundColor Cyan
Write-Host "Inserted: $inserted" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($inserted -gt 0) {
    Write-Host "✓ Candidates ready for gem_executor_live.ps1" -ForegroundColor Green
    Write-Host "  Next: GitHub Actions will run gem_executor in 5 minutes" -ForegroundColor Cyan
} else {
    Write-Host "⚠ No candidates inserted" -ForegroundColor Yellow
}

Write-Host ""
