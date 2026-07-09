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
        [bool]$IsFutures = $false,
        # 2026-07-09: compat com callers legados que passam -Timeframe "1h"/"1D"
        # (lib_gem_discovery, lib_beta_calculator_multitf). Se informado, vence Period.
        [string]$Timeframe = ""
    )

    # Normaliza timeframe legado ("1h") p/ formato period CoinEx v2 ("1hour")
    if ($Timeframe) {
        $tfMap = @{
            "1m" = "1min"; "5m" = "5min"; "15m" = "15min"; "30m" = "30min"
            "1h" = "1hour"; "2h" = "2hour"; "4h" = "4hour"; "1d" = "1day"; "1w" = "1week"
        }
        $Period = if ($tfMap.ContainsKey($Timeframe)) { $tfMap[$Timeframe] } else { $Timeframe }
    }

    try {
        # Detect market type if not specified
        if (-not $IsFutures -and $Market -notmatch "USDT$") {
            $IsFutures = $true
        }

        # 2026-07-09: fallback hardcoded — $global:COINEX_BASE_URL fica VAZIA na nuvem
        # (config.ps1 define sem $global: e o Setup do workflow sobrescreve config.local.ps1)
        $base = if ($global:COINEX_BASE_URL) { $global:COINEX_BASE_URL } else { "https://api.coinex.com" }
        $endpoint = if ($IsFutures) { "/v2/futures/kline" } else { "/v2/spot/kline" }
        $url = "$base$endpoint`?market=$Market&period=$Period&limit=$Limit"

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
