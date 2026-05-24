# tests/lib_coinex_retry.Tests.ps1
# TDD para Retry com Backoff Exponencial (erro 4213 e transientes)
# 2026-05-23

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_coinex.ps1")
. (Join-Path $projectRoot "agents\lib_coinex_retry.ps1")

Describe "Invoke-CoinExWithRetry - Retry basico" {
    
    It "executa action sem retry quando sucesso" {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{
                code = 0
                data = "success"
                message = "OK"
            }
        }
        
        $script:callCount = 0
        $result = Invoke-CoinExWithRetry -Action {
            $script:callCount++
            Invoke-RestMethod -Uri "https://api.coinex.com/test"
        }
        
        $result.code | Should Be 0
        $script:callCount | Should Be 1
    }
    
    It "retenta quando erro 4213 (rate limited)" {
        $script:attemptCount = 0
        Mock Invoke-RestMethod {
            $script:attemptCount++
            if ($script:attemptCount -lt 3) {
                return [PSCustomObject]@{
                    code = 4213
                    message = "Rate limit exceeded"
                }
            }
            return [PSCustomObject]@{
                code = 0
                data = "success"
            }
        }
        
        $result = Invoke-CoinExWithRetry -Action {
            Invoke-RestMethod -Uri "https://api.coinex.com/test"
        } -MaxRetries 3
        
        $result.code | Should Be 0
        $attemptCount | Should Be 3
    }
    
    It "retenta quando erro 3008 (service busy)" {
        $script:attemptCount = 0
        Mock Invoke-RestMethod {
            $script:attemptCount++
            if ($script:attemptCount -lt 2) {
                return [PSCustomObject]@{
                    code = 3008
                    message = "Service busy"
                }
            }
            return [PSCustomObject]@{
                code = 0
                data = "success"
            }
        }
        
        $result = Invoke-CoinExWithRetry -Action {
            Invoke-RestMethod -Uri "https://api.coinex.com/test"
        }
        
        $result.code | Should Be 0
        $attemptCount | Should Be 2
    }
    
    It "NAO retenta quando erro permanente (3109 - saldo insuficiente)" {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{
                code = 3109
                message = "Insufficient balance"
            }
        }
        
        $script:callCount = 0
        $result = Invoke-CoinExWithRetry -Action {
            $script:callCount++
            Invoke-RestMethod -Uri "https://api.coinex.com/test"
        }
        
        $result.code | Should Be 3109
        $script:callCount | Should Be 1
    }
    
    It "NAO retenta quando erro de autenticacao (4005-4008)" {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{
                code = 4006
                message = "Invalid signature"
            }
        }
        
        $script:callCount = 0
        $result = Invoke-CoinExWithRetry -Action {
            $script:callCount++
            Invoke-RestMethod -Uri "https://api.coinex.com/test"
        }
        
        $result.code | Should Be 4006
        $script:callCount | Should Be 1
    }
}

Describe "Invoke-CoinExWithRetry - Backoff exponencial" {
    
    It "aguarda 300ms no primeiro retry" {
        $script:attemptCount = 0
        Mock Invoke-RestMethod {
            $script:attemptCount++
            if ($script:attemptCount -lt 2) {
                return [PSCustomObject]@{ code = 4213; message = "Rate limited" }
            }
            return [PSCustomObject]@{ code = 0; data = "ok" }
        }
        
        $script:lastSleep = 0
        Mock Start-Sleep { param($Milliseconds) $script:lastSleep = $Milliseconds }
        
        Invoke-CoinExWithRetry -Action {
            Invoke-RestMethod -Uri "https://api.coinex.com/test"
        }
        
        ($script:lastSleep -ge 250) | Should Be $true
        ($script:lastSleep -lt 400) | Should Be $true
    }
    
    It "dobra o backoff a cada retry (exponencial)" {
        $script:attemptCount = 0
        $script:sleepTimes = @()
        
        Mock Invoke-RestMethod {
            $script:attemptCount++
            if ($script:attemptCount -le 3) {
                return [PSCustomObject]@{ code = 4213; message = "Rate limited" }
            }
            return [PSCustomObject]@{ code = 0; data = "ok" }
        }
        
        Mock Start-Sleep { 
            param($Milliseconds) 
            $script:sleepTimes += $Milliseconds
        }
        
        Invoke-CoinExWithRetry -Action {
            Invoke-RestMethod -Uri "https://api.coinex.com/test"
        } -MaxRetries 4
        
        # Deve ter 3 sleeps (entre 4 tentativas)
        $sleepTimes.Count | Should Be 3
        
        # Cada sleep deve ser ~2x o anterior
        if ($sleepTimes.Count -ge 2) {
            $sleepTimes[1] | Should BeGreaterThan $sleepTimes[0]
        }
    }
    
    It "respeita MaxBackoffMs (nao excede 30s)" {
        $script:attemptCount = 0
        $script:maxSleep = 0
        
        Mock Invoke-RestMethod {
            $script:attemptCount++
            if ($script:attemptCount -le 10) {
                return [PSCustomObject]@{ code = 4213; message = "Rate limited" }
            }
            return [PSCustomObject]@{ code = 0; data = "ok" }
        }
        
        Mock Start-Sleep { 
            param($Milliseconds)
            if ($Milliseconds -gt $script:maxSleep) {
                $script:maxSleep = $Milliseconds
            }
        }
        
        Invoke-CoinExWithRetry -Action {
            Invoke-RestMethod -Uri "https://api.coinex.com/test"
        } -MaxRetries 10 -MaxBackoffMs 30000
        
        $maxSleep | Should BeLessThan 31000
    }
}

Describe "Invoke-CoinExWithRetry - MaxRetries" {
    
    It "desiste apos MaxRetries tentativas" {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{
                code = 4213
                message = "Rate limited"
            }
        }
        
        $script:callCount = 0
        $result = Invoke-CoinExWithRetry -Action {
            $script:callCount++
            Invoke-RestMethod -Uri "https://api.coinex.com/test"
        } -MaxRetries 3
        
        $result.code | Should Be 4213
        $script:callCount | Should Be 3
    }
    
    It "MaxRetries default e 3" {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{ code = 4213; message = "Rate limited" }
        }
        
        $script:callCount = 0
        Invoke-CoinExWithRetry -Action {
            $script:callCount++
            Invoke-RestMethod -Uri "https://api.coinex.com/test"
        }
        
        $script:callCount | Should Be 3
    }
}

Describe "Invoke-CoinExWithRetry - Timeout de rede" {
    
    It "retenta quando timeout de rede" {
        $script:attemptCount = 0
        Mock Invoke-RestMethod {
            $script:attemptCount++
            if ($script:attemptCount -lt 2) {
                throw "The operation has timed out"
            }
            return [PSCustomObject]@{ code = 0; data = "ok" }
        }
        
        $result = Invoke-CoinExWithRetry -Action {
            Invoke-RestMethod -Uri "https://api.coinex.com/test"
        }
        
        $result.code | Should Be 0
        $attemptCount | Should Be 2
    }
    
    It "retenta quando connection reset" {
        $script:attemptCount = 0
        Mock Invoke-RestMethod {
            $script:attemptCount++
            if ($script:attemptCount -lt 2) {
                throw "Connection reset by peer"
            }
            return [PSCustomObject]@{ code = 0; data = "ok" }
        }
        
        $result = Invoke-CoinExWithRetry -Action {
            Invoke-RestMethod -Uri "https://api.coinex.com/test"
        }
        
        $result.code | Should Be 0
        $attemptCount | Should Be 2
    }
    
    It "NAO retenta quando erro nao-transiente" {
        Mock Invoke-RestMethod {
            throw "Invalid JSON"
        }
        
        $script:callCount = 0
        try {
            Invoke-CoinExWithRetry -Action {
                $script:callCount++
                Invoke-RestMethod -Uri "https://api.coinex.com/test"
            }
        } catch {
            # Esperado
        }
        
        $script:callCount | Should Be 1
    }
}

Describe "Test-IsRetryableError - Classificacao de erros" {
    
    It "4213 e retryable" {
        $result = Test-IsRetryableError -ErrorCode 4213
        $result | Should Be $true
    }
    
    It "3008 e retryable" {
        $result = Test-IsRetryableError -ErrorCode 3008
        $result | Should Be $true
    }
    
    It "3109 NAO e retryable (saldo insuficiente)" {
        $result = Test-IsRetryableError -ErrorCode 3109
        $result | Should Be $false
    }
    
    It "4006 NAO e retryable (auth error)" {
        $result = Test-IsRetryableError -ErrorCode 4006
        $result | Should Be $false
    }
    
    It "3127 NAO e retryable (quantidade minima)" {
        $result = Test-IsRetryableError -ErrorCode 3127
        $result | Should Be $false
    }
    
    It "3606 NAO e retryable (preco fora do range)" {
        $result = Test-IsRetryableError -ErrorCode 3606
        $result | Should Be $false
    }
}

Describe "Test-IsTransientNetworkError - Erros de rede" {
    
    It "timeout e transiente" {
        $result = Test-IsTransientNetworkError -ErrorMessage "The operation has timed out"
        $result | Should Be $true
    }
    
    It "connection reset e transiente" {
        $result = Test-IsTransientNetworkError -ErrorMessage "Connection reset by peer"
        $result | Should Be $true
    }
    
    It "503 service unavailable e transiente" {
        $result = Test-IsTransientNetworkError -ErrorMessage "503 Service Unavailable"
        $result | Should Be $true
    }
    
    It "502 bad gateway e transiente" {
        $result = Test-IsTransientNetworkError -ErrorMessage "502 Bad Gateway"
        $result | Should Be $true
    }
    
    It "invalid JSON NAO e transiente" {
        $result = Test-IsTransientNetworkError -ErrorMessage "Invalid JSON"
        $result | Should Be $false
    }
}

Describe "Get-RetryStats - Estatisticas de retry" {
    
    It "retorna stats vazias inicialmente" {
        Initialize-RetryStats
        
        $stats = Get-RetryStats
        $stats.total_calls | Should Be 0
        $stats.total_retries | Should Be 0
        $stats.success_rate | Should Be 0
    }
    
    It "incrementa total_calls a cada chamada" {
        Initialize-RetryStats
        
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{ code = 0; data = "ok" }
        }
        
        Invoke-CoinExWithRetry -Action {
            Invoke-RestMethod -Uri "https://api.coinex.com/test"
        }
        
        $stats = Get-RetryStats
        $stats.total_calls | Should Be 1
    }
    
    It "incrementa total_retries quando retenta" {
        Initialize-RetryStats
        
        $script:attemptCount = 0
        Mock Invoke-RestMethod {
            $script:attemptCount++
            if ($script:attemptCount -lt 2) {
                return [PSCustomObject]@{ code = 4213; message = "Rate limited" }
            }
            return [PSCustomObject]@{ code = 0; data = "ok" }
        }
        
        Invoke-CoinExWithRetry -Action {
            Invoke-RestMethod -Uri "https://api.coinex.com/test"
        }
        
        $stats = Get-RetryStats
        $stats.total_retries | Should Be 1
    }
    
    It "calcula success_rate corretamente" {
        Initialize-RetryStats
        
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{ code = 0; data = "ok" }
        }
        
        # 3 chamadas bem-sucedidas
        1..3 | ForEach-Object {
            Invoke-CoinExWithRetry -Action {
                Invoke-RestMethod -Uri "https://api.coinex.com/test"
            }
        }
        
        $stats = Get-RetryStats
        $stats.success_rate | Should Be 100
    }
}

Describe "Invoke-CoinExWithRetry - Integracao com lib_coinex" {
    
    It "CoinEx-Post usa retry automaticamente" {
        # Este teste valida que CoinEx-Post foi modificado para usar retry
        # Mock sera implementado em lib_coinex.ps1
        
        $true | Should Be $true  # Placeholder - validar apos implementacao
    }
}
