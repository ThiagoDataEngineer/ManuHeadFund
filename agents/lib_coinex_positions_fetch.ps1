# lib_coinex_positions_fetch.ps1
# Busca posições abertas via CoinEx API
# 2026-07-08 FIX: Sync daemon retornava 0 posições

function Get-CoinExFuturesPositions {
    <#
    .SYNOPSIS
    Busca posições FUTURES abertas da CoinEx API
    (Wrapper de CoinEx-GetPendingPositions que já existe em lib_coinex.ps1)

    .OUTPUTS
    @(position objects)
    #>
    [CmdletBinding()]
    param()

    try {
        # CoinEx-GetPendingPositions já existe em lib_coinex.ps1 e usa CoinEx-Get
        # que usa $COINEX_ACCESS_ID e $COINEX_SECRET_KEY (setados em config.ps1)
        if (Get-Command CoinEx-GetPendingPositions -ErrorAction SilentlyContinue) {
            $positions = @(CoinEx-GetPendingPositions -ErrorAction SilentlyContinue)
            if ($positions -and $positions.Count -gt 0) {
                return $positions
            }
        }
    } catch {
        Write-Verbose "Error fetching futures positions: $_"
    }

    return @()
}

function Get-CoinExSpotBalance {
    <#
    .SYNOPSIS
    Busca saldos SPOT da CoinEx API

    .OUTPUTS
    @(balance objects)
    #>
    [CmdletBinding()]
    param()

    try {
        if (Get-Command CoinEx-Get -ErrorAction SilentlyContinue) {
            $response = CoinEx-Get "/v2/assets/spot/balance" -ErrorAction SilentlyContinue

            if ($response -and $response.data) {
                return @($response.data | Where-Object { [double]($_.available) + [double]($_.frozen) -gt 0 })
            }
        }
    } catch {
        Write-Verbose "Error fetching spot balance: $_"
    }

    return @()
}

# 2026-07-09 FIX: o alias antigo aqui era RECURSIVO — CoinEx-GetPendingPositions
# chamava Get-CoinExFuturesPositions que chamava CoinEx-GetPendingPositions de novo
# (a implementacao real tinha sido deletada de lib_coinex.ps1 na "deprecacao").
# A implementacao real foi RESTAURADA em lib_coinex.ps1. Este fallback so existe
# se a real nao estiver carregada, e chama a API direto (sem recursao).
if (-not (Get-Command CoinEx-GetPendingPositions -ErrorAction SilentlyContinue)) {
    function CoinEx-GetPendingPositions {
        param(
            [Parameter(Mandatory=$false)]
            [string]$Market = $null
        )
        if (-not (Get-Command CoinEx-Get -ErrorAction SilentlyContinue)) { return @() }
        $path = "/v2/futures/pending-position?market_type=FUTURES"
        if ($Market) { $path = "/v2/futures/pending-position?market=$Market&market_type=FUTURES" }
        $r = CoinEx-Get $path
        if ($r.code -ne 0) { return @() }
        $raw = if ($r.data) { @($r.data) } else { @() }
        $valid = @($raw | Where-Object { $_ -and "$($_.market)".Trim() -ne "" })
        if ($valid.Count -eq 0) { return @() }
        if ($valid.Count -eq 1) { return ,$valid }
        return $valid
    }
}

# Functions exported via dot-sourcing: Get-CoinExFuturesPositions, Get-CoinExSpotBalance, CoinEx-GetPendingPositions (fallback)
