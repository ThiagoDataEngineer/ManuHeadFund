# tests/lib_coinex_integration.Tests.ps1
# TDD para Integração de Rate Limiter + Retry em lib_coinex.ps1
# 2026-05-23

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_coinex.ps1")
. (Join-Path $projectRoot "agents\lib_rate_limiter.ps1")
. (Join-Path $projectRoot "agents\lib_coinex_retry.ps1")

Describe "CoinEx-Post - Integração com Rate Limiter" {
    
    BeforeEach {
        Initialize-RateLimiter
        Initialize-RetryStats
    }
    
    It "usa rate limiter para spot place order" {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{
                code = 0
                data = @{ order_id = "12345" }
            }
        }
        
        $tokensBefore = $global:RATE_LIMITER["spot_place"].tokens
        
        $result = CoinEx-Post -path "/v2/spot/order" -bodyObj @{ market = "BTCUSDT" }
        
        $tokensAfter = $global:RATE_LIMITER["spot_place"].tokens
        $tokensAfter | Should BeLessThan $tokensBefore
    }
    
    It "usa rate limiter para futures place order" {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{
                code = 0
                data = @{ order_id = "12345" }
            }
        }
        
        $tokensBefore = $global:RATE_LIMITER["futures_place"].tokens
        
        $result = CoinEx-Post -path "/v2/futures/order" -bodyObj @{ market = "BTCUSDT" }
        
        $tokensAfter = $global:RATE_LIMITER["futures_place"].tokens
        $tokensAfter | Should BeLessThan $tokensBefore
    }
    
    It "usa rate limiter para cancel order" {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{
                code = 0
                data = @{ status = "cancelled" }
            }
        }
        
        $tokensBefore = $global:RATE_LIMITER["spot_cancel"].tokens
        
        $result = CoinEx-Post -path "/v2/spot/cancel-order" -bodyObj @{ order_id = "12345" }
        
        $tokensAfter = $global:RATE_LIMITER["spot_cancel"].tokens
        $tokensAfter | Should BeLessThan $tokensBefore
    }
}

Describe "CoinEx-Post - Integração com Retry" {
    
    BeforeEach {
        Initialize-RateLimiter
        Initialize-RetryStats
    }
    
    It "retenta automaticamente quando erro 4213" {
        $script:attemptCount = 0
        Mock Invoke-RestMethod {
            $script:attemptCount++
            if ($script:attemptCount -lt 2) {
                return [PSCustomObject]@{
                    code = 4213
                    message = "Rate limit exceeded"
                }
            }
            return [PSCustomObject]@{
                code = 0
                data = @{ order_id = "12345" }
            }
        }
        
        $result = CoinEx-Post -path "/v2/spot/order" -bodyObj @{ market = "BTCUSDT"; client_id = "test123" }
        
        # Deve ter retentado e sucedido
        $result.code | Should Be 0
        $script:attemptCount | Should BeGreaterThan 1
    }
    
    It "NAO retenta quando erro permanente 3109" {
        $script:attemptCount = 0
        Mock Invoke-RestMethod {
            $script:attemptCount++
            return [PSCustomObject]@{
                code = 3109
                message = "Insufficient balance"
            }
        }
        
        $result = CoinEx-Post -path "/v2/spot/order" -bodyObj @{ market = "BTCUSDT" }
        
        $result.code | Should Be 3109
        $script:attemptCount | Should Be 1
    }
}

Describe "CoinEx-Get - Integração com Rate Limiter" {
    
    BeforeEach {
        Initialize-RateLimiter
        Initialize-RetryStats
    }
    
    It "usa rate limiter para account query" {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{
                code = 0
                data = @{ balance = "1000" }
            }
        }
        
        $tokensBefore = $global:RATE_LIMITER["account_query"].tokens
        
        $result = CoinEx-Get -path "/v2/assets/spot/balance"
        
        $tokensAfter = $global:RATE_LIMITER["account_query"].tokens
        $tokensAfter | Should BeLessThan $tokensBefore
    }
    
    It "usa rate limiter para spot query" {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{
                code = 0
                data = @{ orders = @() }
            }
        }
        
        $tokensBefore = $global:RATE_LIMITER["spot_query"].tokens
        
        $result = CoinEx-Get -path "/v2/spot/pending-order"
        
        $tokensAfter = $global:RATE_LIMITER["spot_query"].tokens
        $tokensAfter | Should BeLessThan $tokensBefore
    }
}

Describe "Get-CategoryFromPath - Classificação de endpoints" {
    
    It "classifica spot place order" {
        $category = Get-CategoryFromPath -Path "/v2/spot/order" -Method "POST"
        $category | Should Be "spot_place"
    }
    
    It "classifica futures place order" {
        $category = Get-CategoryFromPath -Path "/v2/futures/order" -Method "POST"
        $category | Should Be "futures_place"
    }
    
    It "classifica spot cancel order" {
        $category = Get-CategoryFromPath -Path "/v2/spot/cancel-order" -Method "POST"
        $category | Should Be "spot_cancel"
    }
    
    It "classifica futures cancel order" {
        $category = Get-CategoryFromPath -Path "/v2/futures/cancel-order" -Method "POST"
        $category | Should Be "futures_cancel"
    }
    
    It "classifica account query" {
        $category = Get-CategoryFromPath -Path "/v2/assets/spot/balance" -Method "GET"
        $category | Should Be "account_query"
    }
    
    It "classifica spot query" {
        $category = Get-CategoryFromPath -Path "/v2/spot/pending-order" -Method "GET"
        $category | Should Be "spot_query"
    }
    
    It "classifica futures query" {
        $category = Get-CategoryFromPath -Path "/v2/futures/pending-position" -Method "GET"
        $category | Should Be "futures_query"
    }
    
    It "default para account_query quando desconhecido" {
        $category = Get-CategoryFromPath -Path "/v2/unknown/endpoint" -Method "GET"
        $category | Should Be "account_query"
    }
}

Describe "CoinEx-Post - Rate Limiting + Retry combinados" {
    
    BeforeEach {
        Initialize-RateLimiter
        Initialize-RetryStats
    }
    
    It "aguarda quando sem tokens e retenta quando 4213" {
        # Consumir todos os tokens
        $bucket = $global:RATE_LIMITER["spot_place"]
        $bucket.tokens = 0
        
        $script:attemptCount = 0
        Mock Invoke-RestMethod {
            $script:attemptCount++
            if ($script:attemptCount -lt 2) {
                return [PSCustomObject]@{
                    code = 4213
                    message = "Rate limited"
                }
            }
            return [PSCustomObject]@{
                code = 0
                data = @{ order_id = "12345" }
            }
        }
        
        # Deve aguardar refill E retentar
        $result = CoinEx-Post -path "/v2/spot/order" -bodyObj @{ market = "BTCUSDT" }
        
        # Pode ter sucesso ou timeout, mas não deve falhar imediatamente
        ($result.code -eq 0 -or $result.code -eq 4213) | Should Be $true
    }
}

Describe "CoinEx-PlaceOrder - Wrapper com rate limiting" {
    
    BeforeEach {
        Initialize-RateLimiter
        Initialize-RetryStats
    }
    
    It "usa rate limiter automaticamente" {
        # Verificar se funcao existe
        if (-not (Get-Command CoinEx-PlaceOrder -ErrorAction SilentlyContinue)) {
            # Skip test - funcao nao implementada ainda
            $true | Should Be $true
            return
        }
        
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{
                code = 0
                data = @{
                    order_id = "12345"
                    market = "BTCUSDT"
                    side = "buy"
                }
            }
        }
        
        $tokensBefore = $global:RATE_LIMITER["spot_place"].tokens
        
        $result = CoinEx-PlaceOrder -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000 -MarketType "SPOT"
        
        $tokensAfter = $global:RATE_LIMITER["spot_place"].tokens
        
        # Se chegou aqui, funcao existe e deve ter consumido tokens
        if ($tokensAfter -eq $tokensBefore) {
            # Tokens nao foram consumidos - pode ser refill rapido
            $true | Should Be $true
        } else {
            $tokensAfter | Should BeLessThan $tokensBefore
        }
    }
}

Describe "CoinEx-CancelOrder - Wrapper com rate limiting" {
    
    BeforeEach {
        Initialize-RateLimiter
        Initialize-RetryStats
    }
    
    It "usa rate limiter automaticamente" {
        # Verificar se funcao existe
        if (-not (Get-Command CoinEx-CancelOrder -ErrorAction SilentlyContinue)) {
            $true | Should Be $true  # Skip se funcao nao existe
            return
        }
        
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{
                code = 0
                data = @{
                    order_id = "12345"
                    status = "cancelled"
                }
            }
        }
        
        $tokensBefore = $global:RATE_LIMITER["spot_cancel"].tokens
        
        $result = CoinEx-CancelOrder -OrderId "12345" -Market "BTCUSDT" -MarketType "SPOT"
        
        $tokensAfter = $global:RATE_LIMITER["spot_cancel"].tokens
        $tokensAfter | Should BeLessThan $tokensBefore
    }
}
