# tests/lib_circuit_breaker.Tests.ps1
# TDD para Circuit Breaker Pattern
# 2026-05-23

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_circuit_breaker.ps1")

Describe "Initialize-CircuitBreaker - Setup inicial" {
    
    It "cria circuit breaker para cada categoria" {
        Initialize-CircuitBreaker
        
        $global:CIRCUIT_BREAKERS | Should Not BeNullOrEmpty
        $global:CIRCUIT_BREAKERS.ContainsKey("spot_place") | Should Be $true
        $global:CIRCUIT_BREAKERS.ContainsKey("futures_place") | Should Be $true
    }
    
    It "circuit breaker inicia em estado CLOSED" {
        Initialize-CircuitBreaker
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.state | Should Be "CLOSED"
    }
    
    It "circuit breaker tem contadores zerados" {
        Initialize-CircuitBreaker
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.failure_count | Should Be 0
        $breaker.success_count | Should Be 0
    }
    
    It "circuit breaker tem threshold configuravel" {
        Initialize-CircuitBreaker -FailureThreshold 5
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.failure_threshold | Should Be 5
    }
}

Describe "Test-CircuitBreakerOpen - Verificar estado" {
    
    BeforeEach {
        Initialize-CircuitBreaker -FailureThreshold 3
    }
    
    It "retorna false quando CLOSED" {
        $result = Test-CircuitBreakerOpen -Category "spot_place"
        
        $result | Should Be $false
    }
    
    It "retorna true quando OPEN" {
        # Forcar estado OPEN
        $global:CIRCUIT_BREAKERS["spot_place"].state = "OPEN"
        
        $result = Test-CircuitBreakerOpen -Category "spot_place"
        
        $result | Should Be $true
    }
    
    It "retorna false quando HALF_OPEN" {
        $global:CIRCUIT_BREAKERS["spot_place"].state = "HALF_OPEN"
        
        $result = Test-CircuitBreakerOpen -Category "spot_place"
        
        $result | Should Be $false
    }
}

Describe "Record-CircuitBreakerSuccess - Registrar sucesso" {
    
    BeforeEach {
        Initialize-CircuitBreaker -FailureThreshold 3
    }
    
    It "incrementa contador de sucesso" {
        Record-CircuitBreakerSuccess -Category "spot_place"
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.success_count | Should Be 1
    }
    
    It "reseta contador de falhas" {
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.failure_count = 2
        
        Record-CircuitBreakerSuccess -Category "spot_place"
        
        $breaker.failure_count | Should Be 0
    }
    
    It "mantem estado CLOSED" {
        Record-CircuitBreakerSuccess -Category "spot_place"
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.state | Should Be "CLOSED"
    }
    
    It "fecha circuit breaker quando em HALF_OPEN" {
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.state = "HALF_OPEN"
        
        Record-CircuitBreakerSuccess -Category "spot_place"
        
        $breaker.state | Should Be "CLOSED"
    }
}

Describe "Record-CircuitBreakerFailure - Registrar falha" {
    
    BeforeEach {
        Initialize-CircuitBreaker -FailureThreshold 3
    }
    
    It "incrementa contador de falhas" {
        Record-CircuitBreakerFailure -Category "spot_place"
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.failure_count | Should Be 1
    }
    
    It "mantem CLOSED quando abaixo do threshold" {
        Record-CircuitBreakerFailure -Category "spot_place"
        Record-CircuitBreakerFailure -Category "spot_place"
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.state | Should Be "CLOSED"
        $breaker.failure_count | Should Be 2
    }
    
    It "abre circuit breaker quando atinge threshold" {
        Record-CircuitBreakerFailure -Category "spot_place"
        Record-CircuitBreakerFailure -Category "spot_place"
        Record-CircuitBreakerFailure -Category "spot_place"
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.state | Should Be "OPEN"
    }
    
    It "registra timestamp quando abre" {
        1..3 | ForEach-Object {
            Record-CircuitBreakerFailure -Category "spot_place"
        }
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.opened_at | Should Not BeNullOrEmpty
        $breaker.opened_at | Should BeOfType [DateTime]
    }
    
    It "volta para OPEN quando falha em HALF_OPEN" {
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.state = "HALF_OPEN"
        $breaker.failure_count = 0
        
        Record-CircuitBreakerFailure -Category "spot_place"
        
        $breaker.state | Should Be "OPEN"
    }
}

Describe "Invoke-WithCircuitBreaker - Executar com circuit breaker" {
    
    BeforeEach {
        Initialize-CircuitBreaker -FailureThreshold 3
    }
    
    It "executa action quando CLOSED" {
        $result = Invoke-WithCircuitBreaker -Category "spot_place" -Action {
            return "executed"
        }
        
        $result.success | Should Be $true
        $result.result | Should Be "executed"
    }
    
    It "bloqueia execucao quando OPEN" {
        # Forcar OPEN
        1..3 | ForEach-Object {
            Record-CircuitBreakerFailure -Category "spot_place"
        }
        
        $result = Invoke-WithCircuitBreaker -Category "spot_place" -Action {
            return "should not execute"
        }
        
        $result.success | Should Be $false
        $result.error | Should Match "circuit breaker open|blocked"
    }
    
    It "registra sucesso quando action bem-sucedida" {
        Invoke-WithCircuitBreaker -Category "spot_place" -Action {
            return "ok"
        }
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.success_count | Should Be 1
    }
    
    It "registra falha quando action lanca excecao" {
        Invoke-WithCircuitBreaker -Category "spot_place" -Action {
            throw "API Error"
        }
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.failure_count | Should Be 1
    }
    
    It "abre circuit breaker apos 3 falhas consecutivas" {
        1..3 | ForEach-Object {
            Invoke-WithCircuitBreaker -Category "spot_place" -Action {
                throw "Error"
            }
        }
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.state | Should Be "OPEN"
    }
}

Describe "Update-CircuitBreakerState - Transicao OPEN -> HALF_OPEN" {
    
    BeforeEach {
        Initialize-CircuitBreaker -FailureThreshold 3 -TimeoutSeconds 2
    }
    
    It "mantem OPEN quando timeout nao expirou" {
        # Forcar OPEN
        1..3 | ForEach-Object {
            Record-CircuitBreakerFailure -Category "spot_place"
        }
        
        Update-CircuitBreakerState -Category "spot_place"
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.state | Should Be "OPEN"
    }
    
    It "transiciona para HALF_OPEN apos timeout" {
        # Forcar OPEN
        1..3 | ForEach-Object {
            Record-CircuitBreakerFailure -Category "spot_place"
        }
        
        # Simular timeout expirado
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.opened_at = (Get-Date).AddSeconds(-3)
        
        Update-CircuitBreakerState -Category "spot_place"
        
        $breaker.state | Should Be "HALF_OPEN"
    }
    
    It "reseta failure_count ao transicionar para HALF_OPEN" {
        1..3 | ForEach-Object {
            Record-CircuitBreakerFailure -Category "spot_place"
        }
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.opened_at = (Get-Date).AddSeconds(-3)
        
        Update-CircuitBreakerState -Category "spot_place"
        
        $breaker.failure_count | Should Be 0
    }
}

Describe "Get-CircuitBreakerStats - Estatisticas" {
    
    BeforeEach {
        Initialize-CircuitBreaker
    }
    
    It "retorna stats de todos os circuit breakers" {
        $stats = Get-CircuitBreakerStats
        
        $stats.Count | Should BeGreaterThan 0
        $stats.ContainsKey("spot_place") | Should Be $true
    }
    
    It "stats contem estado e contadores" {
        Record-CircuitBreakerSuccess -Category "spot_place"
        Record-CircuitBreakerFailure -Category "spot_place"
        
        $stats = Get-CircuitBreakerStats
        $spotStats = $stats["spot_place"]
        
        $spotStats.state | Should Be "CLOSED"
        $spotStats.success_count | Should Be 1
        $spotStats.failure_count | Should Be 1
    }
    
    It "stats incluem tempo desde abertura quando OPEN" {
        1..3 | ForEach-Object {
            Record-CircuitBreakerFailure -Category "spot_place"
        }
        
        $stats = Get-CircuitBreakerStats
        $spotStats = $stats["spot_place"]
        
        $spotStats.state | Should Be "OPEN"
        $spotStats.open_duration_seconds | Should BeGreaterOrEqual 0
    }
}

Describe "Reset-CircuitBreaker - Reset manual" {
    
    BeforeEach {
        Initialize-CircuitBreaker
    }
    
    It "reseta circuit breaker para CLOSED" {
        # Forcar OPEN
        1..3 | ForEach-Object {
            Record-CircuitBreakerFailure -Category "spot_place"
        }
        
        Reset-CircuitBreaker -Category "spot_place"
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.state | Should Be "CLOSED"
    }
    
    It "zera contadores" {
        Record-CircuitBreakerSuccess -Category "spot_place"
        Record-CircuitBreakerFailure -Category "spot_place"
        
        Reset-CircuitBreaker -Category "spot_place"
        
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.success_count | Should Be 0
        $breaker.failure_count | Should Be 0
    }
    
    It "reseta todos os circuit breakers quando sem categoria" {
        Record-CircuitBreakerFailure -Category "spot_place"
        Record-CircuitBreakerFailure -Category "futures_place"
        
        Reset-CircuitBreaker
        
        $global:CIRCUIT_BREAKERS["spot_place"].failure_count | Should Be 0
        $global:CIRCUIT_BREAKERS["futures_place"].failure_count | Should Be 0
    }
}

Describe "Invoke-WithCircuitBreaker - HALF_OPEN behavior" {
    
    BeforeEach {
        Initialize-CircuitBreaker -FailureThreshold 3 -TimeoutSeconds 1
    }
    
    It "permite uma tentativa em HALF_OPEN" {
        # Forcar OPEN
        1..3 | ForEach-Object {
            Record-CircuitBreakerFailure -Category "spot_place"
        }
        
        # Simular timeout
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.opened_at = (Get-Date).AddSeconds(-2)
        Update-CircuitBreakerState -Category "spot_place"
        
        # Deve permitir execucao
        $result = Invoke-WithCircuitBreaker -Category "spot_place" -Action {
            return "test"
        }
        
        $result.success | Should Be $true
    }
    
    It "fecha circuit breaker quando sucesso em HALF_OPEN" {
        # Forcar HALF_OPEN
        1..3 | ForEach-Object {
            Record-CircuitBreakerFailure -Category "spot_place"
        }
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.opened_at = (Get-Date).AddSeconds(-2)
        Update-CircuitBreakerState -Category "spot_place"
        
        # Sucesso deve fechar
        Invoke-WithCircuitBreaker -Category "spot_place" -Action {
            return "ok"
        }
        
        $breaker.state | Should Be "CLOSED"
    }
    
    It "reabre circuit breaker quando falha em HALF_OPEN" {
        # Forcar HALF_OPEN
        1..3 | ForEach-Object {
            Record-CircuitBreakerFailure -Category "spot_place"
        }
        $breaker = $global:CIRCUIT_BREAKERS["spot_place"]
        $breaker.opened_at = (Get-Date).AddSeconds(-2)
        Update-CircuitBreakerState -Category "spot_place"
        
        # Falha deve reabrir
        Invoke-WithCircuitBreaker -Category "spot_place" -Action {
            throw "Error"
        }
        
        $breaker.state | Should Be "OPEN"
    }
}
