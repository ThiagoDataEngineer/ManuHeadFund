# lib_rate_limiter.ps1
# Rate Limiter com Token Bucket Algorithm
# Implementado com TDD: tests\lib_rate_limiter.Tests.ps1
# 2026-05-23
#
# FUNCIONALIDADES:
# 1. Token bucket por categoria (spot_place, futures_place, etc.)
# 2. Refill automatico baseado em tempo
# 3. Suporte a batch operations (cost > 1)
# 4. Blocking com timeout configuravel
# 5. Estatisticas de utilizacao

# ============================================================================
# Initialize-RateLimiter - Setup inicial
# ============================================================================

function Initialize-RateLimiter {
    <#
    .SYNOPSIS
        Inicializa rate limiter com buckets para cada categoria
    
    .DESCRIPTION
        Cria token buckets baseados nos limites da CoinEx API v2:
        - spot_place: 30 req/s
        - futures_place: 20 req/s
        - spot_cancel: 60 req/s
        - futures_cancel: 40 req/s
        - account_query: 10 req/s
    #>
    
    $global:RATE_LIMITER = @{
        "spot_place" = @{
            capacity = 30
            tokens = 30
            refill_rate = 30  # tokens por segundo
            last_refill = Get-Date
        }
        "futures_place" = @{
            capacity = 20
            tokens = 20
            refill_rate = 20
            last_refill = Get-Date
        }
        "spot_cancel" = @{
            capacity = 60
            tokens = 60
            refill_rate = 60
            last_refill = Get-Date
        }
        "futures_cancel" = @{
            capacity = 40
            tokens = 40
            refill_rate = 40
            last_refill = Get-Date
        }
        "spot_query" = @{
            capacity = 50
            tokens = 50
            refill_rate = 50
            last_refill = Get-Date
        }
        "futures_query" = @{
            capacity = 50
            tokens = 50
            refill_rate = 50
            last_refill = Get-Date
        }
        "account_query" = @{
            capacity = 10
            tokens = 10
            refill_rate = 10
            last_refill = Get-Date
        }
    }
}

# ============================================================================
# Update-RateLimitTokens - Refill de tokens baseado em tempo
# ============================================================================

function Update-RateLimitTokens {
    <#
    .SYNOPSIS
        Atualiza tokens baseado no tempo decorrido
    
    .PARAMETER Category
        Categoria do bucket (spot_place, futures_place, etc.)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Category
    )
    
    if (-not $global:RATE_LIMITER.ContainsKey($Category)) {
        Write-Warning "Category $Category not found in rate limiter"
        return
    }
    
    $bucket = $global:RATE_LIMITER[$Category]
    $now = Get-Date
    $elapsed = ($now - $bucket.last_refill).TotalSeconds
    
    if ($elapsed -gt 0) {
        # Calcular tokens a adicionar
        $tokensToAdd = [Math]::Floor($elapsed * $bucket.refill_rate)
        
        if ($tokensToAdd -gt 0) {
            $bucket.tokens = [Math]::Min($bucket.capacity, $bucket.tokens + $tokensToAdd)
            $bucket.last_refill = $now
        }
    }
}

# ============================================================================
# Test-RateLimitAllowed - Verificar se pode executar
# ============================================================================

function Test-RateLimitAllowed {
    <#
    .SYNOPSIS
        Verifica se tem tokens disponiveis para executar
    
    .PARAMETER Category
        Categoria do bucket
    
    .PARAMETER Cost
        Custo da operacao em tokens (default: 1, batch: N)
    
    .OUTPUTS
        PSCustomObject com allowed, tokens_available, cost, wait_ms
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Category,
        
        [Parameter(Mandatory=$false)]
        [int]$Cost = 1
    )
    
    # Refill automatico
    Update-RateLimitTokens -Category $Category
    
    $bucket = $global:RATE_LIMITER[$Category]
    $allowed = $bucket.tokens -ge $Cost
    
    $waitMs = 0
    if (-not $allowed) {
        # Calcular tempo de espera
        $tokensNeeded = $Cost - $bucket.tokens
        $waitMs = [Math]::Ceiling(($tokensNeeded / $bucket.refill_rate) * 1000)
    }
    
    return [PSCustomObject]@{
        allowed = $allowed
        tokens_available = $bucket.tokens
        cost = $Cost
        wait_ms = $waitMs
    }
}

# ============================================================================
# Invoke-RateLimitedCall - Executar com rate limiting
# ============================================================================

function Invoke-RateLimitedCall {
    <#
    .SYNOPSIS
        Executa action respeitando rate limit
    
    .PARAMETER Category
        Categoria do bucket
    
    .PARAMETER Cost
        Custo da operacao em tokens
    
    .PARAMETER Action
        ScriptBlock a executar
    
    .PARAMETER ActionParams
        Parametros para o ScriptBlock
    
    .PARAMETER MaxWaitMs
        Tempo maximo de espera em ms (default: 5000)
    
    .OUTPUTS
        PSCustomObject com success, result, waited_ms, error
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Category,
        
        [Parameter(Mandatory=$false)]
        [int]$Cost = 1,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$Action,
        
        [Parameter(Mandatory=$false)]
        [array]$ActionParams = @(),
        
        [Parameter(Mandatory=$false)]
        [int]$MaxWaitMs = 5000
    )
    
    $totalWaited = 0
    $startTime = Get-Date
    
    while ($true) {
        $check = Test-RateLimitAllowed -Category $Category -Cost $Cost
        
        if ($check.allowed) {
            # Consumir tokens
            $bucket = $global:RATE_LIMITER[$Category]
            $bucket.tokens -= $Cost
            
            # Executar action
            try {
                if ($ActionParams.Count -gt 0) {
                    $result = & $Action @ActionParams
                } else {
                    $result = & $Action
                }
                
                return [PSCustomObject]@{
                    success = $true
                    result = $result
                    waited_ms = $totalWaited
                }
            }
            catch {
                return [PSCustomObject]@{
                    success = $false
                    error = $_.Exception.Message
                    waited_ms = $totalWaited
                }
            }
        }
        else {
            # Verificar timeout
            if ($totalWaited -ge $MaxWaitMs) {
                return [PSCustomObject]@{
                    success = $false
                    error = "Rate limit timeout exceeded (waited ${totalWaited}ms)"
                    waited_ms = $totalWaited
                }
            }
            
            # Aguardar
            $waitMs = [Math]::Min($check.wait_ms, $MaxWaitMs - $totalWaited)
            Start-Sleep -Milliseconds $waitMs
            $totalWaited += $waitMs
        }
    }
}

# ============================================================================
# Get-RateLimitStats - Estatisticas
# ============================================================================

function Get-RateLimitStats {
    <#
    .SYNOPSIS
        Retorna estatisticas de todos os buckets
    
    .OUTPUTS
        Hashtable com stats por categoria
    #>
    
    $stats = @{}
    
    foreach ($category in $global:RATE_LIMITER.Keys) {
        Update-RateLimitTokens -Category $category
        
        $bucket = $global:RATE_LIMITER[$category]
        $utilizationPct = [Math]::Round((1 - ($bucket.tokens / $bucket.capacity)) * 100, 2)
        
        $stats[$category] = [PSCustomObject]@{
            tokens = $bucket.tokens
            capacity = $bucket.capacity
            refill_rate = $bucket.refill_rate
            utilization_pct = $utilizationPct
        }
    }
    
    return $stats
}

# ============================================================================
# Reset-RateLimiter - Reset manual
# ============================================================================

function Reset-RateLimiter {
    <#
    .SYNOPSIS
        Reseta todos os buckets para capacidade maxima
    #>
    
    foreach ($category in $global:RATE_LIMITER.Keys) {
        $bucket = $global:RATE_LIMITER[$category]
        $bucket.tokens = $bucket.capacity
        $bucket.last_refill = Get-Date
    }
}

# ============================================================================
# Inicializacao automatica
# ============================================================================

if (-not $global:RATE_LIMITER) {
    Initialize-RateLimiter
}
