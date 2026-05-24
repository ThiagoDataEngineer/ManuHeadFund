# tests/lib_rate_limiter.Tests.ps1
# TDD para Rate Limiter com Token Bucket Algorithm
# 2026-05-23

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_rate_limiter.ps1")

Describe "Initialize-RateLimiter - Setup inicial" {
    
    It "cria buckets para todas as categorias" {
        Initialize-RateLimiter
        
        $global:RATE_LIMITER | Should Not BeNullOrEmpty
        $global:RATE_LIMITER.ContainsKey("spot_place") | Should Be $true
        $global:RATE_LIMITER.ContainsKey("futures_place") | Should Be $true
        $global:RATE_LIMITER.ContainsKey("spot_cancel") | Should Be $true
        $global:RATE_LIMITER.ContainsKey("futures_cancel") | Should Be $true
    }
    
    It "spot_place tem capacidade 30 tokens" {
        Initialize-RateLimiter
        
        $bucket = $global:RATE_LIMITER["spot_place"]
        $bucket.capacity | Should Be 30
        $bucket.tokens | Should Be 30
        $bucket.refill_rate | Should Be 30
    }
    
    It "futures_place tem capacidade 20 tokens" {
        Initialize-RateLimiter
        
        $bucket = $global:RATE_LIMITER["futures_place"]
        $bucket.capacity | Should Be 20
        $bucket.tokens | Should Be 20
        $bucket.refill_rate | Should Be 20
    }
    
    It "inicializa com tokens cheios" {
        Initialize-RateLimiter
        
        foreach ($key in $global:RATE_LIMITER.Keys) {
            $bucket = $global:RATE_LIMITER[$key]
            $bucket.tokens | Should Be $bucket.capacity
        }
    }
}

Describe "Test-RateLimitAllowed - Verificar se pode executar" {
    
    BeforeEach {
        Initialize-RateLimiter
    }
    
    It "permite quando tem tokens disponiveis" {
        $result = Test-RateLimitAllowed -Category "spot_place" -Cost 1
        
        $result.allowed | Should Be $true
        $result.tokens_available | Should Be 30
        $result.cost | Should Be 1
    }
    
    It "bloqueia quando nao tem tokens suficientes" {
        # Consumir todos os tokens rapidamente
        $bucket = $global:RATE_LIMITER["spot_place"]
        $bucket.tokens = 0  # Forcar zero
        
        $result = Test-RateLimitAllowed -Category "spot_place" -Cost 1
        
        $result.allowed | Should Be $false
        $result.wait_ms | Should BeGreaterThan 0
    }
    
    It "permite batch quando tem tokens suficientes" {
        $result = Test-RateLimitAllowed -Category "spot_place" -Cost 10
        
        $result.allowed | Should Be $true
        $result.tokens_available | Should Be 30
    }
    
    It "bloqueia batch quando nao tem tokens suficientes" {
        # Consumir 25 tokens
        Invoke-RateLimitedCall -Category "spot_place" -Cost 25 -Action { "ok" }
        
        $result = Test-RateLimitAllowed -Category "spot_place" -Cost 10
        
        $result.allowed | Should Be $false
        $result.tokens_available | Should BeLessThan 10
    }
}

Describe "Invoke-RateLimitedCall - Executar com rate limiting" {
    
    BeforeEach {
        Initialize-RateLimiter
    }
    
    It "executa action quando tem tokens" {
        $result = Invoke-RateLimitedCall -Category "spot_place" -Cost 1 -Action {
            return "executed"
        }
        
        $result.success | Should Be $true
        $result.result | Should Be "executed"
        $result.waited_ms | Should Be 0
    }
    
    It "consome tokens apos execucao" {
        Invoke-RateLimitedCall -Category "spot_place" -Cost 5 -Action { "ok" }
        
        $bucket = $global:RATE_LIMITER["spot_place"]
        $bucket.tokens | Should BeLessThan 30
        ($bucket.tokens -ge 24) | Should Be $true
    }
    
    It "aguarda quando nao tem tokens (com timeout curto)" {
        # Consumir todos os tokens
        1..30 | ForEach-Object { 
            Invoke-RateLimitedCall -Category "spot_place" -Cost 1 -Action { "ok" }
        }
        
        $start = Get-Date
        $result = Invoke-RateLimitedCall -Category "spot_place" -Cost 1 -Action { "ok" } -MaxWaitMs 100
        $elapsed = ((Get-Date) - $start).TotalMilliseconds
        
        # Deve ter aguardado ou retornado timeout
        ($result.success -eq $false -or $elapsed -gt 50) | Should Be $true
    }
    
    It "retorna timeout quando MaxWaitMs excedido" {
        # Consumir todos os tokens
        1..30 | ForEach-Object { 
            Invoke-RateLimitedCall -Category "spot_place" -Cost 1 -Action { "ok" }
        }
        
        $result = Invoke-RateLimitedCall -Category "spot_place" -Cost 1 -Action { "ok" } -MaxWaitMs 50
        
        # Pode ter sucesso se refill rapido OU timeout
        ($result.success -eq $false -or $result.waited_ms -gt 0) | Should Be $true
    }
    
    It "executa action com parametros" {
        $result = Invoke-RateLimitedCall -Category "spot_place" -Cost 1 -Action {
            param($a, $b)
            return $a + $b
        } -ActionParams @(10, 20)
        
        $result.success | Should Be $true
        $result.result | Should Be 30
    }
}

Describe "Update-RateLimitTokens - Refill de tokens" {
    
    BeforeEach {
        Initialize-RateLimiter
    }
    
    It "refill adiciona tokens baseado no tempo decorrido" {
        # Consumir 10 tokens
        Invoke-RateLimitedCall -Category "spot_place" -Cost 10 -Action { "ok" }
        
        $bucket = $global:RATE_LIMITER["spot_place"]
        $tokensBefore = $bucket.tokens
        
        # Simular 1 segundo de espera (30 tokens/s = 30 tokens)
        Start-Sleep -Milliseconds 1100
        Update-RateLimitTokens -Category "spot_place"
        
        $tokensAfter = $global:RATE_LIMITER["spot_place"].tokens
        $tokensAfter | Should BeGreaterThan $tokensBefore
    }
    
    It "refill nao excede capacidade maxima" {
        $bucket = $global:RATE_LIMITER["spot_place"]
        $bucket.tokens = 30  # Ja cheio
        
        Start-Sleep -Milliseconds 1100
        Update-RateLimitTokens -Category "spot_place"
        
        $global:RATE_LIMITER["spot_place"].tokens | Should Be 30
    }
    
    It "refill e chamado automaticamente em Test-RateLimitAllowed" {
        # Consumir tokens
        Invoke-RateLimitedCall -Category "spot_place" -Cost 20 -Action { "ok" }
        
        Start-Sleep -Milliseconds 1100
        
        # Test-RateLimitAllowed deve fazer refill automatico
        $result = Test-RateLimitAllowed -Category "spot_place" -Cost 1
        
        $result.tokens_available | Should BeGreaterThan 10
    }
}

Describe "Get-RateLimitStats - Estatisticas" {
    
    BeforeEach {
        Initialize-RateLimiter
    }
    
    It "retorna stats de todas as categorias" {
        $stats = Get-RateLimitStats
        
        $stats.Count | Should BeGreaterThan 0
        $stats.ContainsKey("spot_place") | Should Be $true
        $stats.ContainsKey("futures_place") | Should Be $true
    }
    
    It "stats contem tokens disponiveis e capacidade" {
        $stats = Get-RateLimitStats
        
        $spotStats = $stats["spot_place"]
        $spotStats.tokens | Should Be 30
        $spotStats.capacity | Should Be 30
        $spotStats.refill_rate | Should Be 30
        $spotStats.utilization_pct | Should Be 0
    }
    
    It "calcula utilizacao corretamente" {
        # Consumir 15 tokens (50%)
        Invoke-RateLimitedCall -Category "spot_place" -Cost 15 -Action { "ok" }
        
        $stats = Get-RateLimitStats
        $spotStats = $stats["spot_place"]
        
        $spotStats.utilization_pct | Should BeGreaterThan 40
        $spotStats.utilization_pct | Should BeLessThan 60
    }
}

Describe "Reset-RateLimiter - Reset manual" {
    
    It "reseta todos os buckets para capacidade maxima" {
        Initialize-RateLimiter
        
        # Consumir tokens
        Invoke-RateLimitedCall -Category "spot_place" -Cost 20 -Action { "ok" }
        Invoke-RateLimitedCall -Category "futures_place" -Cost 10 -Action { "ok" }
        
        Reset-RateLimiter
        
        $global:RATE_LIMITER["spot_place"].tokens | Should Be 30
        $global:RATE_LIMITER["futures_place"].tokens | Should Be 20
    }
}

Describe "Invoke-RateLimitedCall - Categorias especificas" {
    
    BeforeEach {
        Initialize-RateLimiter
    }
    
    It "spot_place e futures_place sao independentes" {
        # Consumir todos spot_place
        1..30 | ForEach-Object { 
            Invoke-RateLimitedCall -Category "spot_place" -Cost 1 -Action { "ok" }
        }
        
        # futures_place ainda deve ter tokens
        $result = Invoke-RateLimitedCall -Category "futures_place" -Cost 1 -Action { "ok" }
        
        $result.success | Should Be $true
    }
    
    It "spot_cancel tem limite 60 req/s" {
        Initialize-RateLimiter
        
        $bucket = $global:RATE_LIMITER["spot_cancel"]
        $bucket.capacity | Should Be 60
        $bucket.refill_rate | Should Be 60
    }
    
    It "futures_cancel tem limite 40 req/s" {
        Initialize-RateLimiter
        
        $bucket = $global:RATE_LIMITER["futures_cancel"]
        $bucket.capacity | Should Be 40
        $bucket.refill_rate | Should Be 40
    }
    
    It "account_query tem limite 10 req/s" {
        Initialize-RateLimiter
        
        $bucket = $global:RATE_LIMITER["account_query"]
        $bucket.capacity | Should Be 10
        $bucket.refill_rate | Should Be 10
    }
}

Describe "Invoke-RateLimitedCall - Error handling" {
    
    BeforeEach {
        Initialize-RateLimiter
    }
    
    It "captura excecao da action e retorna erro" {
        $result = Invoke-RateLimitedCall -Category "spot_place" -Cost 1 -Action {
            throw "API Error"
        }
        
        $result.success | Should Be $false
        $result.error | Should Match "API Error"
    }
    
    It "consome tokens mesmo se action falhar" {
        $tokensBefore = $global:RATE_LIMITER["spot_place"].tokens
        
        Invoke-RateLimitedCall -Category "spot_place" -Cost 5 -Action {
            throw "Error"
        }
        
        $tokensAfter = $global:RATE_LIMITER["spot_place"].tokens
        $tokensAfter | Should BeLessThan $tokensBefore
    }
}

Describe "Invoke-RateLimitedCall - Batch operations" {
    
    BeforeEach {
        Initialize-RateLimiter
    }
    
    It "batch de 10 ordens consome 10 tokens" {
        $tokensBefore = $global:RATE_LIMITER["spot_place"].tokens
        
        Invoke-RateLimitedCall -Category "spot_place" -Cost 10 -Action {
            return "batch executed"
        }
        
        $tokensAfter = $global:RATE_LIMITER["spot_place"].tokens
        ($tokensBefore - $tokensAfter -ge 10) | Should Be $true
    }
    
    It "bloqueia batch grande quando nao tem tokens" {
        # Consumir 25 tokens
        Invoke-RateLimitedCall -Category "spot_place" -Cost 25 -Action { "ok" }
        
        # Tentar batch de 10 (precisa de 10, tem ~5)
        $result = Invoke-RateLimitedCall -Category "spot_place" -Cost 10 -Action { "ok" } -MaxWaitMs 100
        
        $result.success | Should Be $false
    }
}
