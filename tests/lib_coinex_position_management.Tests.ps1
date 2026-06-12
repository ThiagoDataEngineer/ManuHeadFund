# lib_coinex_position_management.Tests.ps1 - TDD para Position Management
# Rodar: Invoke-Pester .\tests\lib_coinex_position_management.Tests.ps1 -Verbose
#
# FASE RED: Testes escritos ANTES da implementacao
# FASE GREEN: Implementar funcoes ate testes passarem
# FASE REFACTOR: Otimizar sem quebrar testes

$global:COINEX_BASE_URL   = "https://api.coinex.com"
$global:COINEX_ACCESS_ID  = "test_access_id"
$global:COINEX_SECRET_KEY = "test_secret_key"

function Write-Host { param() }
function Write-Warning { param() }

. "$PSScriptRoot\..\agents\lib_coinex.ps1"
. "$PSScriptRoot\..\agents\lib_coinex_position_management.ps1"

# ============================================================================
# CoinEx-AdjustPositionLeverage - Ajustar leverage + margin mode (CRÍTICO)
# ============================================================================

Describe "CoinEx-AdjustPositionLeverage - ajustar leverage e margin mode" {

    It "ajusta leverage para 10x em modo isolated" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $path | Should Be "/v2/futures/adjust-position-leverage"
            $bodyObj.market      | Should Be "BTCUSDT"
            $bodyObj.market_type | Should Be "FUTURES"
            $bodyObj.leverage    | Should Be 10
            $bodyObj.margin_mode | Should Be "isolated"
            
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{
                    market = "BTCUSDT"
                    leverage = 10
                    margin_mode = "isolated"
                }
            }
        }
        
        $result = CoinEx-AdjustPositionLeverage -Market "BTCUSDT" -Leverage 10 -MarginMode "isolated"
        
        $result.success | Should Be $true
        $result.leverage | Should Be 10
        $result.margin_mode | Should Be "isolated"
    }

    It "ajusta leverage para 5x em modo cross" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $bodyObj.leverage    | Should Be 5
            $bodyObj.margin_mode | Should Be "cross"
            
            return [PSCustomObject]@{
                code = 0
                data = [PSCustomObject]@{ leverage = 5; margin_mode = "cross" }
            }
        }
        
        $result = CoinEx-AdjustPositionLeverage -Market "ETHUSDT" -Leverage 5 -MarginMode "cross"
        
        $result.success | Should Be $true
        $result.leverage | Should Be 5
        $result.margin_mode | Should Be "cross"
    }

    It "usa isolated como default quando MarginMode nao especificado" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $bodyObj.margin_mode | Should Be "isolated"
            
            return [PSCustomObject]@{
                code = 0
                data = [PSCustomObject]@{ leverage = 10; margin_mode = "isolated" }
            }
        }
        
        $result = CoinEx-AdjustPositionLeverage -Market "BTCUSDT" -Leverage 10
        
        $result.margin_mode | Should Be "isolated"
    }

    It "retorna erro quando leverage invalido (fora de 1-100)" {
        Mock CoinEx-Post {
            return [PSCustomObject]@{
                code = 3639
                message = "Invalid leverage"
                data = $null
            }
        }
        
        $result = CoinEx-AdjustPositionLeverage -Market "BTCUSDT" -Leverage 150
        
        $result.success | Should Be $false
        $result.error_code | Should Be 3639
    }

    It "rejeita MarginMode invalido" {
        { CoinEx-AdjustPositionLeverage -Market "BTCUSDT" -Leverage 10 -MarginMode "invalid" } | Should Throw
    }
}

# ============================================================================
# CoinEx-AdjustPositionMargin - Add/Remove margin (salva de liquidacao)
# ============================================================================

Describe "CoinEx-AdjustPositionMargin - adicionar ou remover margin" {

    It "adiciona 100 USDT de margin a posicao" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $path | Should Be "/v2/futures/adjust-position-margin"
            $bodyObj.market      | Should Be "BTCUSDT"
            $bodyObj.market_type | Should Be "FUTURES"
            $bodyObj.amount      | Should Be "100"
            $bodyObj.type        | Should Be "add"
            
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{
                    market = "BTCUSDT"
                    amount = "100"
                    type = "add"
                }
            }
        }
        
        $result = CoinEx-AdjustPositionMargin -Market "BTCUSDT" -Amount 100 -Type "add"
        
        $result.success | Should Be $true
        $result.amount | Should Be "100"
        $result.type | Should Be "add"
    }

    It "remove 50 USDT de margin da posicao" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $bodyObj.amount | Should Be "50"
            $bodyObj.type   | Should Be "remove"
            
            return [PSCustomObject]@{
                code = 0
                data = [PSCustomObject]@{ amount = "50"; type = "remove" }
            }
        }
        
        $result = CoinEx-AdjustPositionMargin -Market "ETHUSDT" -Amount 50 -Type "remove"
        
        $result.success | Should Be $true
        $result.type | Should Be "remove"
    }

    It "retorna erro quando tenta remover mais margin que disponivel" {
        Mock CoinEx-Post {
            return [PSCustomObject]@{
                code = 3109
                message = "Insufficient margin"
                data = $null
            }
        }
        
        $result = CoinEx-AdjustPositionMargin -Market "BTCUSDT" -Amount 1000 -Type "remove"
        
        $result.success | Should Be $false
        $result.error_code | Should Be 3109
    }

    It "rejeita Type invalido (nao add ou remove)" {
        { CoinEx-AdjustPositionMargin -Market "BTCUSDT" -Amount 100 -Type "invalid" } | Should Throw
    }
}

# ============================================================================
# CoinEx-ModifyPositionStopLoss - Modificar SL sem cancelar (economiza fees)
# ============================================================================

Describe "CoinEx-ModifyPositionStopLoss - modificar stop loss" {

    It "modifica stop loss para 95000" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $path | Should Be "/v2/futures/modify-position-stop-loss"
            $bodyObj.market           | Should Be "BTCUSDT"
            $bodyObj.market_type      | Should Be "FUTURES"
            $bodyObj.stop_loss_price  | Should Be "95000"
            $bodyObj.stop_loss_type   | Should Be "mark_price"
            
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{
                    market = "BTCUSDT"
                    stop_loss_price = "95000"
                }
            }
        }
        
        $result = CoinEx-ModifyPositionStopLoss -Market "BTCUSDT" -Price 95000
        
        $result.success | Should Be $true
        $result.stop_loss_price | Should Be "95000"
    }

    It "usa mark_price como default para trigger type" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $bodyObj.stop_loss_type | Should Be "mark_price"
            
            return [PSCustomObject]@{
                code = 0
                data = [PSCustomObject]@{ stop_loss_price = "95000" }
            }
        }
        
        $result = CoinEx-ModifyPositionStopLoss -Market "BTCUSDT" -Price 95000
        
        $result.success | Should Be $true
    }

    It "aceita latest_price como trigger type" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $bodyObj.stop_loss_type | Should Be "latest_price"
            
            return [PSCustomObject]@{
                code = 0
                data = [PSCustomObject]@{ stop_loss_price = "95000" }
            }
        }
        
        $result = CoinEx-ModifyPositionStopLoss -Market "BTCUSDT" -Price 95000 -TriggerType "latest_price"
        
        $result.success | Should Be $true
    }

    It "retorna erro quando nao ha posicao aberta" {
        Mock CoinEx-Post {
            return [PSCustomObject]@{
                code = 3008
                message = "Position not found"
                data = $null
            }
        }
        
        $result = CoinEx-ModifyPositionStopLoss -Market "XRPUSDT" -Price 0.5
        
        $result.success | Should Be $false
        $result.error_code | Should Be 3008
    }
}

# ============================================================================
# CoinEx-ModifyPositionTakeProfit - Modificar TP sem cancelar
# ============================================================================

Describe "CoinEx-ModifyPositionTakeProfit - modificar take profit" {

    It "modifica take profit para 105000" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $path | Should Be "/v2/futures/modify-position-take-profit"
            $bodyObj.market             | Should Be "BTCUSDT"
            $bodyObj.market_type        | Should Be "FUTURES"
            $bodyObj.take_profit_price  | Should Be "105000"
            $bodyObj.take_profit_type   | Should Be "mark_price"
            
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{
                    market = "BTCUSDT"
                    take_profit_price = "105000"
                }
            }
        }
        
        $result = CoinEx-ModifyPositionTakeProfit -Market "BTCUSDT" -Price 105000
        
        $result.success | Should Be $true
        $result.take_profit_price | Should Be "105000"
    }

    It "usa mark_price como default" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $bodyObj.take_profit_type | Should Be "mark_price"
            
            return [PSCustomObject]@{
                code = 0
                data = [PSCustomObject]@{ take_profit_price = "105000" }
            }
        }
        
        $result = CoinEx-ModifyPositionTakeProfit -Market "BTCUSDT" -Price 105000
        
        $result.success | Should Be $true
    }
}

# ============================================================================
# CoinEx-CancelPositionStopLoss - Cancelar SL da posicao
# ============================================================================

Describe "CoinEx-CancelPositionStopLoss - cancelar stop loss" {

    It "cancela stop loss da posicao" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $path | Should Be "/v2/futures/cancel-position-stop-loss"
            $bodyObj.market      | Should Be "BTCUSDT"
            $bodyObj.market_type | Should Be "FUTURES"
            
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{
                    market = "BTCUSDT"
                    status = "cancelled"
                }
            }
        }
        
        $result = CoinEx-CancelPositionStopLoss -Market "BTCUSDT"
        
        $result.success | Should Be $true
        $result.status | Should Be "cancelled"
    }

    It "retorna erro quando nao ha stop loss para cancelar" {
        Mock CoinEx-Post {
            return [PSCustomObject]@{
                code = 3008
                message = "Stop loss not found"
                data = $null
            }
        }
        
        $result = CoinEx-CancelPositionStopLoss -Market "ETHUSDT"
        
        $result.success | Should Be $false
        $result.error_code | Should Be 3008
    }
}

# ============================================================================
# CoinEx-CancelPositionTakeProfit - Cancelar TP da posicao
# ============================================================================

Describe "CoinEx-CancelPositionTakeProfit - cancelar take profit" {

    It "cancela take profit da posicao" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $path | Should Be "/v2/futures/cancel-position-take-profit"
            $bodyObj.market      | Should Be "BTCUSDT"
            $bodyObj.market_type | Should Be "FUTURES"
            
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{
                    market = "BTCUSDT"
                    status = "cancelled"
                }
            }
        }
        
        $result = CoinEx-CancelPositionTakeProfit -Market "BTCUSDT"
        
        $result.success | Should Be $true
        $result.status | Should Be "cancelled"
    }

    It "retorna erro quando nao ha take profit para cancelar" {
        Mock CoinEx-Post {
            return [PSCustomObject]@{
                code = 3008
                message = "Take profit not found"
                data = $null
            }
        }
        
        $result = CoinEx-CancelPositionTakeProfit -Market "ETHUSDT"
        
        $result.success | Should Be $false
        $result.error_code | Should Be 3008
    }
}

# ============================================================================
# CoinEx-GetFinishedPositions - Historico de posicoes (analytics)
# ============================================================================

Describe "CoinEx-GetFinishedPositions - historico de posicoes" {

    It "retorna historico de posicoes finalizadas" {
        Mock CoinEx-Get {
            param($path)
            $path | Should Match "/v2/futures/finished-position"
            
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = @(
                    [PSCustomObject]@{
                        market = "BTCUSDT"
                        side = "long"
                        amount = "0.001"
                        entry_price = "100000"
                        exit_price = "105000"
                        pnl = "5"
                        closed_at = 1700490703564
                    },
                    [PSCustomObject]@{
                        market = "ETHUSDT"
                        side = "short"
                        amount = "0.1"
                        entry_price = "3000"
                        exit_price = "2900"
                        pnl = "10"
                        closed_at = 1700490603564
                    }
                )
            }
        }
        
        $result = CoinEx-GetFinishedPositions -Market "BTCUSDT" -Limit 100
        
        $result.success | Should Be $true
        $result.positions.Count | Should Be 2
        $result.positions[0].market | Should Be "BTCUSDT"
        $result.positions[0].pnl | Should Be "5"
    }

    It "retorna lista vazia quando nao ha historico" {
        Mock CoinEx-Get {
            return [PSCustomObject]@{
                code = 0
                data = @()
            }
        }
        
        $result = CoinEx-GetFinishedPositions -Market "XRPUSDT"
        
        $result.success | Should Be $true
        $result.positions.Count | Should Be 0
    }

    It "aceita filtro por market" {
        Mock CoinEx-Get {
            param($path)
            $path | Should Match "market=BTCUSDT"
            
            return [PSCustomObject]@{
                code = 0
                data = @()
            }
        }
        
        $result = CoinEx-GetFinishedPositions -Market "BTCUSDT"
        
        $result.success | Should Be $true
    }

    It "aceita limite de resultados" {
        Mock CoinEx-Get {
            param($path)
            $path | Should Match "limit=50"
            
            return [PSCustomObject]@{
                code = 0
                data = @()
            }
        }
        
        $result = CoinEx-GetFinishedPositions -Limit 50
        
        $result.success | Should Be $true
    }
}

# ============================================================================
# Validacao de Parametros - REMOVIDO (PowerShell valida automaticamente)
# ============================================================================
# PowerShell ja valida parametros [Mandatory=$true] automaticamente
# Nao precisamos testar isso - economiza tempo de execucao
