# lib_coinex_cancel_order.Tests.ps1 - TDD para CoinEx-CancelOrder
# Rodar: Invoke-Pester .\tests\lib_coinex_cancel_order.Tests.ps1 -Verbose
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

# ============================================================================
# CoinEx-CancelOrder - Cancelar ordem SPOT ou FUTURES por order_id
# ============================================================================

Describe "CoinEx-CancelOrder - SPOT - cancelamento por order_id" {

    It "cancela ordem SPOT pendente com sucesso" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            # Valida que chamou endpoint correto
            $path | Should Be "/v2/spot/cancel-order"
            $bodyObj.market      | Should Be "BTCUSDT"
            $bodyObj.market_type | Should Be "SPOT"
            $bodyObj.order_id    | Should Be "12345678"
            
            # Retorna sucesso
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{
                    order_id = "12345678"
                    market = "BTCUSDT"
                    status = "cancelled"
                }
            }
        }
        
        $result = CoinEx-CancelOrder -Market "BTCUSDT" -OrderId "12345678" -MarketType "SPOT"
        
        $result | Should Not BeNullOrEmpty
        $result.success | Should Be $true
        $result.order_id | Should Be "12345678"
        $result.status | Should Be "cancelled"
    }

    It "retorna erro quando ordem nao existe" {
        Mock CoinEx-Post {
            return [PSCustomObject]@{
                code = 3008
                message = "Order not found"
                data = $null
            }
        }
        
        $result = CoinEx-CancelOrder -Market "BTCUSDT" -OrderId "99999999" -MarketType "SPOT"
        
        $result.success | Should Be $false
        $result.error_code | Should Be 3008
        $result.error_message | Should Be "Order not found"
    }

    It "retorna erro quando ordem ja foi executada" {
        Mock CoinEx-Post {
            return [PSCustomObject]@{
                code = 3009
                message = "Order already filled"
                data = $null
            }
        }
        
        $result = CoinEx-CancelOrder -Market "BTCUSDT" -OrderId "11111111" -MarketType "SPOT"
        
        $result.success | Should Be $false
        $result.error_code | Should Be 3009
        $result.error_message | Should Be "Order already filled"
    }
}

Describe "CoinEx-CancelOrder - FUTURES - cancelamento por order_id" {

    It "cancela ordem FUTURES pendente com sucesso" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            # Valida endpoint correto
            $path | Should Be "/v2/futures/cancel-order"
            $bodyObj.market      | Should Be "BTCUSDT"
            $bodyObj.market_type | Should Be "FUTURES"
            $bodyObj.order_id    | Should Be "87654321"
            
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{
                    order_id = "87654321"
                    market = "BTCUSDT"
                    status = "cancelled"
                }
            }
        }
        
        $result = CoinEx-CancelOrder -Market "BTCUSDT" -OrderId "87654321" -MarketType "FUTURES"
        
        $result.success | Should Be $true
        $result.order_id | Should Be "87654321"
    }

    It "usa FUTURES como default quando MarketType nao especificado" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $path | Should Be "/v2/futures/cancel-order"
            $bodyObj.market_type | Should Be "FUTURES"
            
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{ order_id = "123"; status = "cancelled" }
            }
        }
        
        $result = CoinEx-CancelOrder -Market "BTCUSDT" -OrderId "123"
        
        $result.success | Should Be $true
    }
}

# ============================================================================
# CoinEx-CancelOrderByClientId - Cancelar por client_id (FUTURES only)
# ============================================================================

Describe "CoinEx-CancelOrderByClientId - FUTURES - cancelamento por client_id" {

    It "cancela ordem FUTURES por client_id com sucesso" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            # Valida endpoint correto (FUTURES tem endpoint especifico)
            $path | Should Be "/v2/futures/cancel-order-by-client-id"
            $bodyObj.market      | Should Be "ETHUSDT"
            $bodyObj.market_type | Should Be "FUTURES"
            $bodyObj.client_id   | Should Be "uuid-12345-abcde"
            
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{
                    order_id = "99887766"
                    client_id = "uuid-12345-abcde"
                    status = "cancelled"
                }
            }
        }
        
        $result = CoinEx-CancelOrderByClientId -Market "ETHUSDT" -ClientId "uuid-12345-abcde"
        
        $result.success | Should Be $true
        $result.client_id | Should Be "uuid-12345-abcde"
        $result.order_id | Should Be "99887766"
    }

    It "retorna erro quando client_id nao existe" {
        Mock CoinEx-Post {
            return [PSCustomObject]@{
                code = 3008
                message = "Order not found"
                data = $null
            }
        }
        
        $result = CoinEx-CancelOrderByClientId -Market "ETHUSDT" -ClientId "uuid-nao-existe"
        
        $result.success | Should Be $false
        $result.error_code | Should Be 3008
    }
}

# ============================================================================
# CoinEx-CancelStopOrder - Cancelar stop order (condicional)
# ============================================================================

Describe "CoinEx-CancelStopOrder - cancelamento de ordem condicional" {

    It "cancela stop order SPOT pendente" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $path | Should Be "/v2/spot/cancel-stop-order"
            $bodyObj.market      | Should Be "BTCUSDT"
            $bodyObj.market_type | Should Be "SPOT"
            $bodyObj.stop_id     | Should Be "stop-123"
            
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{
                    stop_id = "stop-123"
                    status = "cancelled"
                }
            }
        }
        
        $result = CoinEx-CancelStopOrder -Market "BTCUSDT" -StopId "stop-123" -MarketType "SPOT"
        
        $result.success | Should Be $true
        $result.stop_id | Should Be "stop-123"
    }

    It "cancela stop order FUTURES pendente" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $path | Should Be "/v2/futures/cancel-stop-order"
            $bodyObj.market_type | Should Be "FUTURES"

            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{ stop_id = "stop-456"; status = "cancelled" }
            }
        }

        $result = CoinEx-CancelStopOrder -Market "ETHUSDT" -StopId "stop-456" -MarketType "FUTURES"

        $result.success | Should Be $true
    }

    # 2026-06-05: bug real -- stop_id numerico enviado como STRING retornava
    # "Invalid Parameter" e o stop NUNCA cancelava (orphan stops no incidente FIRO).
    It "envia stop_id NUMERICO (int64) quando id e' todo digitos" {
        $script:capturedStopId = $null
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:capturedStopId = $bodyObj.stop_id
            return [PSCustomObject]@{ code = 0; message = "Success"; data = [PSCustomObject]@{ stop_id = "171807267312"; status = "cancelled" } }
        }

        $result = CoinEx-CancelStopOrder -Market "FIROUSDT" -StopId "171807267312" -MarketType "SPOT"

        $result.success | Should Be $true
        ($script:capturedStopId -is [int64]) | Should Be $true
        ([int64]$script:capturedStopId) | Should Be 171807267312
    }

    It "mantem stop_id como STRING quando id NAO e' numerico (back-compat)" {
        $script:capturedStopId2 = $null
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:capturedStopId2 = $bodyObj.stop_id
            return [PSCustomObject]@{ code = 0; message = "Success"; data = [PSCustomObject]@{ status = "cancelled" } }
        }

        $result = CoinEx-CancelStopOrder -Market "BTCUSDT" -StopId "stop-abc" -MarketType "SPOT"

        $result.success | Should Be $true
        ($script:capturedStopId2 -is [string]) | Should Be $true
    }
}

# ============================================================================
# CoinEx-CancelAllOrders - Cancelar todas as ordens de um mercado
# ============================================================================

Describe "CoinEx-CancelAllOrders - cancelamento em massa" {

    It "cancela todas as ordens SPOT de um mercado" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $path | Should Be "/v2/spot/cancel-all-order"
            $bodyObj.market      | Should Be "BTCUSDT"
            $bodyObj.market_type | Should Be "SPOT"
            
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{
                    cancelled_count = 3
                    orders = @("123", "456", "789")
                }
            }
        }
        
        $result = CoinEx-CancelAllOrders -Market "BTCUSDT" -MarketType "SPOT"
        
        $result.success | Should Be $true
        $result.cancelled_count | Should Be 3
    }

    It "cancela todas as ordens FUTURES de um mercado" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $path | Should Be "/v2/futures/cancel-all-order"
            $bodyObj.market_type | Should Be "FUTURES"
            
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{
                    cancelled_count = 5
                }
            }
        }
        
        $result = CoinEx-CancelAllOrders -Market "ETHUSDT" -MarketType "FUTURES"
        
        $result.success | Should Be $true
        $result.cancelled_count | Should Be 5
    }

    It "retorna sucesso mesmo quando nao ha ordens para cancelar" {
        Mock CoinEx-Post {
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{
                    cancelled_count = 0
                }
            }
        }
        
        $result = CoinEx-CancelAllOrders -Market "XRPUSDT" -MarketType "SPOT"
        
        $result.success | Should Be $true
        $result.cancelled_count | Should Be 0
    }
}

# ============================================================================
# Validacao de Parametros
# ============================================================================

Describe "CoinEx-CancelOrder - validacao de parametros" {

    It "requer Market obrigatorio" {
        # PowerShell pede input interativo para parametros obrigatorios
        # Nao da pra testar com Should Throw - skip
        Set-TestInconclusive "PowerShell pede input interativo para parametros obrigatorios"
    }

    It "requer OrderId obrigatorio" {
        # PowerShell pede input interativo para parametros obrigatorios
        # Nao da pra testar com Should Throw - skip
        Set-TestInconclusive "PowerShell pede input interativo para parametros obrigatorios"
    }

    It "aceita MarketType SPOT ou FUTURES" {
        Mock CoinEx-Post { return [PSCustomObject]@{ code=0; data=[PSCustomObject]@{} } }
        
        { CoinEx-CancelOrder -Market "BTCUSDT" -OrderId "123" -MarketType "SPOT" } | Should Not Throw
        { CoinEx-CancelOrder -Market "BTCUSDT" -OrderId "123" -MarketType "FUTURES" } | Should Not Throw
    }

    It "rejeita MarketType invalido" {
        { CoinEx-CancelOrder -Market "BTCUSDT" -OrderId "123" -MarketType "INVALID" } | Should Throw
    }
}

# ============================================================================
# Retry Safety (idempotencia)
# ============================================================================

Describe "CoinEx-CancelOrder - retry safety (idempotente)" {

    It "retry de cancelamento e seguro (idempotente)" {
        # Primeira chamada: sucesso
        # Segunda chamada: ordem ja cancelada (ainda retorna sucesso)
        $callCount = 0
        Mock CoinEx-Post {
            $script:callCount++
            if ($script:callCount -eq 1) {
                return [PSCustomObject]@{
                    code = 0
                    message = "Success"
                    data = [PSCustomObject]@{ order_id = "123"; status = "cancelled" }
                }
            } else {
                # Segunda chamada: ordem ja cancelada
                return [PSCustomObject]@{
                    code = 3009
                    message = "Order already cancelled"
                    data = $null
                }
            }
        }
        
        $result1 = CoinEx-CancelOrder -Market "BTCUSDT" -OrderId "123"
        $result2 = CoinEx-CancelOrder -Market "BTCUSDT" -OrderId "123"
        
        $result1.success | Should Be $true
        $result2.success | Should Be $false
        $result2.error_code | Should Be 3009
    }
}
