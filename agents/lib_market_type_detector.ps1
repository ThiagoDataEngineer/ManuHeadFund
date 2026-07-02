# lib_market_type_detector.ps1 — Deteccao AUTOMATICA de tipo de mercado (FUTURES vs SPOT).
# 2026-06-30: Remove hardcoded whitelist. Puxa da API CoinEx qual tipo suporta.

function Get-AvailableFuturesMarkets {
    <#
    .SYNOPSIS
    Retorna lista de mercados que suportam FUTURES na CoinEx (cached).
    .OUTPUTS
    @( "BTCUSDT", "ETHUSDT", ... )
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([int]$CacheMinutes = 60)

    # Cache em memoria (1h)
    if ($script:__futuresCacheAt -and ((Get-Date) - $script:__futuresCacheAt).TotalMinutes -lt $CacheMinutes) {
        return $script:__futuresCache
    }

    $markets = @()
    try {
        # GET /v2/futures/market retorna array de contratos disponiveis
        $baseUrl = if ($env:COINEX_BASE_URL) { $env:COINEX_BASE_URL } else { 'https://api.coinex.com' }
        $r = Invoke-RestMethod -Uri "$baseUrl/v2/futures/market" `
            -Method GET -TimeoutSec 10 -ErrorAction Stop

        if ($r -and $r.data) {
            $markets = @($r.data | Where-Object { $_.market } | Select-Object -ExpandProperty market | Select-Object -Unique)
        }

        $script:__futuresCacheAt = Get-Date
        $script:__futuresCache = $markets
    } catch {
        Write-Warning "Nao conseguiu puxar /v2/futures/market (usando cache): $_"
        # Fallback: retorna cache antigo ou lista minima conhecida
        if ($script:__futuresCache) { return $script:__futuresCache }
        return @("BTCUSDT", "ETHUSDT", "SOLUSDT")  # fallback minimo
    }

    return $markets
}

function Test-MarketHasFutures {
    <#
    .SYNOPSIS
    Verifica se um mercado especifico tem contrato de FUTURES.
    .OUTPUTS
    $true | $false
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory=$true)][string]$Market)

    $futures = Get-AvailableFuturesMarkets
    return ($Market -in $futures)
}

function Get-MarketType {
    <#
    .SYNOPSIS
    Detecta automaticamente: FUTURES ou SPOT pra um mercado.
    Usa: TEM futures? → FUTURES. Senao → SPOT.
    .OUTPUTS
    "FUTURES" | "SPOT"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory=$true)][string]$Market)

    if (Test-MarketHasFutures -Market $Market) {
        return "FUTURES"
    }
    return "SPOT"
}

# Export automaticamente quando dot-sourced
