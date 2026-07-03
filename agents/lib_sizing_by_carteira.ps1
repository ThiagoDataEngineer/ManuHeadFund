# lib_sizing_by_carteira.ps1 — Aloca sizing automático baseado em carteira disponível
# 2026-07-03: SHORT v2.5 usa 1% de SPOT ou FUTURES (qualquer um que tenha capital)

function Get-AvailableCapitalByCarteira {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $CoinExConfig
    )

    $result = [PSCustomObject]@{
        spot_available = 0
        futures_available = 0
        spot_usdt = 0
        futures_usdt = 0
        primary_carteira = "unknown"
        reason = ""
    }

    # SPOT balance
    try {
        $spotBal = CoinEx-GetBalance -Config $CoinExConfig -AccountType "spot" -ErrorAction Stop
        if ($spotBal) {
            $spotUsdt = ($spotBal | Where-Object { $_.currency -eq "USDT" } | Select-Object -First 1)
            if ($spotUsdt) {
                $result.spot_usdt = [double]$spotUsdt.available
                $result.spot_available = $result.spot_usdt
            }
        }
    }
    catch {
        # Silent fail — carteira pode não estar disponível agora
    }

    # FUTURES balance
    try {
        $futuresBal = CoinEx-GetBalance -Config $CoinExConfig -AccountType "futures" -ErrorAction Stop
        if ($futuresBal) {
            $futuresUsdt = ($futuresBal | Where-Object { $_.currency -eq "USDT" } | Select-Object -First 1)
            if ($futuresUsdt) {
                $result.futures_usdt = [double]$futuresUsdt.available
                $result.futures_available = $result.futures_usdt
            }
        }
    }
    catch {
        # Silent fail
    }

    # Determina qual carteira usar
    if ($result.spot_available -gt $result.futures_available -and $result.spot_available -gt 0) {
        $result.primary_carteira = "SPOT"
        $result.reason = "SPOT available: $($result.spot_available)"
    }
    elseif ($result.futures_available -gt 0) {
        $result.primary_carteira = "FUTURES"
        $result.reason = "FUTURES available: $($result.futures_available)"
    }
    else {
        $result.primary_carteira = "NONE"
        $result.reason = "No capital in either carteira"
    }

    return $result
}

function Calculate-SizingByCarteira {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $TotalCapital,  # Available capital em SPOT ou FUTURES
        [Parameter(Mandatory)] [double] $SizingPercent, # 1.0 = 1%
        [string] $Carteira = "SPOT"
    )

    $sizeUsdt = $TotalCapital * ($SizingPercent / 100)

    return [PSCustomObject]@{
        carteira = $Carteira
        total_capital = $TotalCapital
        sizing_pct = $SizingPercent
        size_usdt = [math]::Round($sizeUsdt, 2)
        max_leverage = if ($Carteira -eq "FUTURES") { 5 } else { 1 }  # FUTURES pode usar leverage
    }
}

# Exporta por dot-source
