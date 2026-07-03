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

    # 2026-07-03 v2: delega as funcoes ASSINADAS de lib_coinex (a v1 chamava
    # CoinEx-GetBalance com assinatura inexistente -> sempre 0).
    try {
        if (Get-Command CoinEx-GetSpotCapitalUSDT -ErrorAction SilentlyContinue) {
            $result.spot_usdt = [double](CoinEx-GetSpotCapitalUSDT)
            $result.spot_available = $result.spot_usdt
        }
    } catch { }

    try {
        if (Get-Command CoinEx-GetFuturesCapitalUSDT -ErrorAction SilentlyContinue) {
            $result.futures_usdt = [double](CoinEx-GetFuturesCapitalUSDT)
            $result.futures_available = $result.futures_usdt
        }
    } catch { }

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
