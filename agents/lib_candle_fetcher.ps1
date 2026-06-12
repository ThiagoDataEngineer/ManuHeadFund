# lib_candle_fetcher.ps1 — Fetch OHLCV candles from CoinEx
# 2026-06-08: Multi-timeframe candle retrieval for HTF confirmation

# ─────────────────────────────────────────────────────────────────────────────
# Get-CoinExCandles — Fetch candles from CoinEx API
# ─────────────────────────────────────────────────────────────────────────────
function Get-CoinExCandles {
    param(
        [Parameter(Mandatory)] [string]$Market,
        [string]$Period = "1day",    # "1min", "5min", "1hour", "4hour", "1day", "1week"
        [int]$Limit = 50,
        [bool]$IsFutures = $false
    )

    try {
        # Detect market type if not specified
        if (-not $IsFutures -and $Market -notmatch "USDT$") {
            $IsFutures = $true
        }

        $endpoint = if ($IsFutures) { "/v2/futures/kline" } else { "/v2/spot/kline" }
        $url = "$global:COINEX_BASE_URL$endpoint`?market=$Market&period=$Period&limit=$Limit"

        $r = Invoke-RestMethod -Uri $url -Method GET -ErrorAction Stop
        if ($r.code -ne 0 -or -not $r.data) {
            return @()
        }

        # Parse and return candles
        $candles = @()
        foreach ($d in $r.data) {
            $candles += [PSCustomObject]@{
                open   = [double]$d.open
                high   = [double]$d.high
                low    = [double]$d.low
                close  = [double]$d.close
                volume = [double]$d.volume
                ts     = [long]$d.created_at
            }
        }

        return $candles
    } catch {
        Write-Host "  [WARN] Failed to fetch candles for $Market/$Period : $_" -ForegroundColor Yellow
        return @()
    }
}

# Function automatically available after dot-sourcing
