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

# Alias para compatibilidade
function CoinEx-GetPendingPositions {
    [CmdletBinding()]
    param([bool]$IsFutures = $true)

    if ($IsFutures) {
        Get-CoinExFuturesPositions
    } else {
        Get-CoinExSpotBalance
    }
}

Export-ModuleMember -Function @('Get-CoinExFuturesPositions', 'Get-CoinExSpotBalance', 'CoinEx-GetPendingPositions')
