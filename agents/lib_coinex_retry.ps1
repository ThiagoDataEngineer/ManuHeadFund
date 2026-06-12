# lib_coinex_retry.ps1
# Retry com Backoff Exponencial para CoinEx API
# Implementado com TDD: tests\lib_coinex_retry.Tests.ps1
# 2026-05-23
#
# FUNCIONALIDADES:
# 1. Retry automatico para erros transientes (4213, 3008, timeout)
# 2. Backoff exponencial (300ms -> 600ms -> 1.2s -> ...)
# 3. MaxRetries configuravel (default: 3)
# 4. Classificacao de erros (retryable vs permanent)
# 5. Estatisticas de retry

# ============================================================================
# Initialize-RetryStats - Inicializar estatisticas
# ============================================================================

function Initialize-RetryStats {
    $global:RETRY_STATS = @{
        total_calls = 0
        total_retries = 0
        total_successes = 0
        total_failures = 0
        success_rate = 0
    }
}

# ============================================================================
# Test-IsRetryableError - Classificar erro como retryable
# ============================================================================

function Test-IsRetryableError {
    <#
    .SYNOPSIS
        Verifica se erro e retryable
    
    .PARAMETER ErrorCode
        Codigo de erro da CoinEx API
    
    .OUTPUTS
        Boolean - true se retryable
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$ErrorCode
    )
    
    # Erros retryable (transientes)
    $retryableCodes = @(
        4213,  # Rate limited
        3008   # Service busy
    )
    
    # Erros permanentes (NAO retry)
    $permanentCodes = @(
        3109,  # Saldo insuficiente
        3127,  # Quantidade abaixo do minimo
        3606,  # Preco fora do range
        3639,  # Parametros incorretos
        4005, 4006, 4007, 4008,  # Auth failures
        4017   # Signature issues
    )
    
    if ($permanentCodes -contains $ErrorCode) {
        return $false
    }
    
    if ($retryableCodes -contains $ErrorCode) {
        return $true
    }
    
    # Default: nao retry para codigos desconhecidos
    return $false
}

# ============================================================================
# Test-IsTransientNetworkError - Classificar erro de rede
# ============================================================================

function Test-IsTransientNetworkError {
    <#
    .SYNOPSIS
        Verifica se erro de rede e transiente
    
    .PARAMETER ErrorMessage
        Mensagem de erro
    
    .OUTPUTS
        Boolean - true se transiente
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ErrorMessage
    )
    
    $transientPatterns = @(
        "timeout",
        "timed out",
        "connection reset",
        "503 Service Unavailable",
        "502 Bad Gateway",
        "504 Gateway Timeout"
    )
    
    foreach ($pattern in $transientPatterns) {
        if ($ErrorMessage -match $pattern) {
            return $true
        }
    }
    
    return $false
}

# ============================================================================
# Invoke-CoinExWithRetry - Executar com retry automatico
# ============================================================================

function Invoke-CoinExWithRetry {
    <#
    .SYNOPSIS
        Executa action com retry automatico para erros transientes
    
    .PARAMETER Action
        ScriptBlock a executar
    
    .PARAMETER MaxRetries
        Numero maximo de tentativas (default: 3)
    
    .PARAMETER InitialBackoffMs
        Backoff inicial em ms (default: 300)
    
    .PARAMETER MaxBackoffMs
        Backoff maximo em ms (default: 30000)
    
    .OUTPUTS
        Resultado da action (response da API)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$Action,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxRetries = 3,
        
        [Parameter(Mandatory=$false)]
        [int]$InitialBackoffMs = 300,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxBackoffMs = 30000
    )
    
    # Incrementar contador de chamadas
    if ($global:RETRY_STATS) {
        $global:RETRY_STATS.total_calls++
    }
    
    $attempt = 0
    $backoffMs = $InitialBackoffMs
    
    while ($attempt -lt $MaxRetries) {
        $attempt++
        
        try {
            $response = & $Action
            
            # Verificar se e resposta da CoinEx API
            if ($response -and $response.PSObject.Properties["code"]) {
                $errorCode = $response.code
                
                # Sucesso
                if ($errorCode -eq 0) {
                    if ($global:RETRY_STATS) {
                        $global:RETRY_STATS.total_successes++
                        $global:RETRY_STATS.success_rate = [Math]::Round(
                            ($global:RETRY_STATS.total_successes / $global:RETRY_STATS.total_calls) * 100, 2
                        )
                    }
                    return $response
                }
                
                # Erro - verificar se e retryable
                $isRetryable = Test-IsRetryableError -ErrorCode $errorCode
                
                if (-not $isRetryable) {
                    # Erro permanente - nao retry
                    if ($global:RETRY_STATS) {
                        $global:RETRY_STATS.total_failures++
                    }
                    return $response
                }
                
                # Erro retryable - continuar loop
                if ($attempt -lt $MaxRetries) {
                    if ($global:RETRY_STATS) {
                        $global:RETRY_STATS.total_retries++
                    }
                    
                    Write-Verbose "Retry attempt $attempt/$MaxRetries for error $errorCode, waiting ${backoffMs}ms"
                    Start-Sleep -Milliseconds $backoffMs
                    
                    # Backoff exponencial
                    $backoffMs = [Math]::Min($backoffMs * 2, $MaxBackoffMs)
                }
                else {
                    # Esgotou retries
                    if ($global:RETRY_STATS) {
                        $global:RETRY_STATS.total_failures++
                    }
                    return $response
                }
            }
            else {
                # Resposta sem campo code - retornar como esta
                return $response
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            
            # Verificar se e erro de rede transiente
            $isTransient = Test-IsTransientNetworkError -ErrorMessage $errorMsg
            
            if (-not $isTransient) {
                # Erro nao-transiente - propagar excecao
                throw
            }
            
            # Erro transiente - retry
            if ($attempt -lt $MaxRetries) {
                if ($global:RETRY_STATS) {
                    $global:RETRY_STATS.total_retries++
                }
                
                Write-Verbose "Retry attempt $attempt/$MaxRetries for network error, waiting ${backoffMs}ms"
                Start-Sleep -Milliseconds $backoffMs
                
                # Backoff exponencial
                $backoffMs = [Math]::Min($backoffMs * 2, $MaxBackoffMs)
            }
            else {
                # Esgotou retries - propagar excecao
                throw
            }
        }
    }
    
    # Nao deveria chegar aqui, mas por seguranca
    throw "Max retries exceeded"
}

# ============================================================================
# Get-RetryStats - Estatisticas de retry
# ============================================================================

function Get-RetryStats {
    <#
    .SYNOPSIS
        Retorna estatisticas de retry
    
    .OUTPUTS
        PSCustomObject com stats
    #>
    
    if (-not $global:RETRY_STATS) {
        Initialize-RetryStats
    }
    
    return [PSCustomObject]$global:RETRY_STATS
}

# ============================================================================
# Inicializacao automatica
# ============================================================================

if (-not $global:RETRY_STATS) {
    Initialize-RetryStats
}
