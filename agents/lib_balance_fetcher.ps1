# lib_balance_fetcher.ps1 — Fetch real SPOT + FUTURES balance from CoinEx API
# 2026-07-03: Salva em journal/balance_snapshot.json a cada ciclo

function Get-RealBalance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $CoinExConfig
    )

    $result = @{
        timestamp = [datetime]::UtcNow.ToString("O")
        spot = @{ usdt = 0; total_pairs = 0 }
        futures = @{ usdt = 0; total_pairs = 0 }
        primary_carteira = "UNKNOWN"
    }

    # SPOT
    try {
        $spotResp = Invoke-RestMethod `
            -Uri "https://api.coinex.com/v2/spot/balance" `
            -Method GET `
            -Headers @{
                "X-COINEX-KEY" = $CoinExConfig.api_key
                "User-Agent" = "ManuHeadFund/2026"
            } `
            -TimeoutSec 10 -ErrorAction Stop

        if ($spotResp.data -and $spotResp.data.balances) {
            $usdtSpot = $spotResp.data.balances | Where-Object { $_.ccy -eq "USDT" }
            if ($usdtSpot) {
                $result.spot.usdt = [double]$usdtSpot.available
                $result.spot.total_pairs = ($spotResp.data.balances | Measure-Object).Count
            }
        }
    }
    catch {
        # Silent — API pode estar lento
        $result.spot.usdt = 0
    }

    # FUTURES
    try {
        $futuresResp = Invoke-RestMethod `
            -Uri "https://api.coinex.com/v2/futures/balance" `
            -Method GET `
            -Headers @{
                "X-COINEX-KEY" = $CoinExConfig.api_key
                "User-Agent" = "ManuHeadFund/2026"
            } `
            -TimeoutSec 10 -ErrorAction Stop

        if ($futuresResp.data -and $futuresResp.data.balances) {
            $usdtFutures = $futuresResp.data.balances | Where-Object { $_.ccy -eq "USDT" }
            if ($usdtFutures) {
                $result.futures.usdt = [double]$usdtFutures.available
                $result.futures.total_pairs = ($futuresResp.data.balances | Measure-Object).Count
            }
        }
    }
    catch {
        # Silent
        $result.futures.usdt = 0
    }

    # Determina primary
    if ($result.spot.usdt -gt $result.futures.usdt) {
        $result.primary_carteira = "SPOT"
    }
    elseif ($result.futures.usdt -gt 0) {
        $result.primary_carteira = "FUTURES"
    }

    return $result
}

function Save-BalanceSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Balance,
        [string] $Path = "journal/balance_snapshot.json"
    )

    try {
        $json = $Balance | ConvertTo-Json -Depth 10
        $json | Out-File -FilePath $Path -Encoding UTF8 -NoNewline -Force
        return $true
    }
    catch {
        return $false
    }
}

function Read-LatestBalance {
    [CmdletBinding()]
    param(
        [string] $Path = "journal/balance_snapshot.json"
    )

    if (Test-Path $Path) {
        try {
            return Get-Content $Path | ConvertFrom-Json
        }
        catch {
            return $null
        }
    }
    return $null
}

# Export by dot-source
