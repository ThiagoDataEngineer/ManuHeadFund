# lib_coinex.ps1 — Etapa 6: equity total inclui margem alocada + PnL nao realizado
#
# Antes: CoinEx-GetFuturesCapitalUSDT retornava apenas $available (margem livre).
# Depois: retorna available + margin + unrealized_pnl (= equity total da conta)
#
# Justificativa: Layer 1 sizing (1% por trade) precisa do capital REAL da carteira,
# nao apenas o que esta livre. Senao subaloca progressivamente.

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

# Limpar credenciais pra evitar fallback
$env:COINEX_ACCESS_ID = "test_id"
$env:COINEX_SECRET_KEY = "test_secret"

. (Join-Path $agentsDir "config.ps1") -ErrorAction SilentlyContinue
. (Join-Path $agentsDir "lib_coinex.ps1")

# Mock APOS dot-source pra sobrescrever as funcoes reais
$script:mockBalanceResponse = $null

function CoinEx-Get {
    param($Path)
    return $script:mockBalanceResponse
}
function CoinEx-Post { param($Path, $Body) return @{} }

Describe "CoinEx-GetFuturesCapitalUSDT - equity calculation" {

    It "Returns available + margin + unrealized_pnl (positive PnL)" {
        $script:mockBalanceResponse = [PSCustomObject]@{
            code = 0
            data = @(
                [PSCustomObject]@{
                    ccy             = "USDT"
                    available       = "1000"
                    margin          = "500"
                    unrealized_pnl  = "50"
                    frozen          = "0"
                }
            )
        }
        $r = CoinEx-GetFuturesCapitalUSDT
        # 1000 + 500 + 50 = 1550
        $r | Should Be 1550
    }

    It "Returns equity correctly with negative PnL (real scenario)" {
        $script:mockBalanceResponse = [PSCustomObject]@{
            code = 0
            data = @(
                [PSCustomObject]@{
                    ccy             = "USDT"
                    available       = "1654.99"
                    margin          = "1068.10"
                    unrealized_pnl  = "-48.60"
                    frozen          = "0"
                }
            )
        }
        $r = CoinEx-GetFuturesCapitalUSDT
        # 1654.99 + 1068.10 - 48.60 = 2674.49
        ($r -ge 2674.0 -and $r -le 2675.0) | Should Be $true
    }

    It "Returns only available when no positions (margin=0, pnl=0)" {
        $script:mockBalanceResponse = [PSCustomObject]@{
            code = 0
            data = @(
                [PSCustomObject]@{
                    ccy             = "USDT"
                    available       = "2000"
                    margin          = "0"
                    unrealized_pnl  = "0"
                    frozen          = "0"
                }
            )
        }
        $r = CoinEx-GetFuturesCapitalUSDT
        $r | Should Be 2000
    }

    It "Handles missing margin field gracefully (legacy response)" {
        $script:mockBalanceResponse = [PSCustomObject]@{
            code = 0
            data = @(
                [PSCustomObject]@{
                    ccy       = "USDT"
                    available = "1500"
                    frozen    = "0"
                }
            )
        }
        $r = CoinEx-GetFuturesCapitalUSDT
        # Sem margin/pnl, retorna apenas available
        $r | Should Be 1500
    }

    It "Returns 0 (or fallback) on API error" {
        $script:mockBalanceResponse = [PSCustomObject]@{
            code    = 3001
            message = "API error"
            data    = @()
        }
        $global:CAPITAL_FUTURES = 999.0
        $r = CoinEx-GetFuturesCapitalUSDT
        # Fallback global se API falha
        $r | Should Be 999.0
    }
}
