# lib_retry.ps1 -- B19 fix 2026-05-20 PM6+420min.
#
# Retry helper generico pra erros transient (429/503/502/504/timeout/connection).
# Necessario porque CoinEx-PlaceOrder atualmente: Invoke-RestMethod -ErrorAction Stop
# throws em qualquer falha -> caller perde trade sem retry.
#
# IMPORTANTE — gap residual (deferred):
#   Se request HIT a exchange mas resposta cortada antes de chegar ao client (503 no
#   path de volta), ordem PODE TER SIDO COLOCADA na corretora mas client nao tem state.
#   Retry naive cria ordem duplicada. Solucao real: idempotency key (client_id) por
#   chamada PlaceOrder; CoinEx aceita campo `client_id` em /v2/futures/order. Tarefa
#   deferred — requer audit de quais endpoints aceitam idempotency key + integration.
#
# Por hora: retry apenas erros que sabidamente NAO chegaram ao servidor (timeout
# antes da request, DNS, connection refused). 429/503 que JA executaram tem risco
# de duplicate -- por isso CB conservador (max 2 retries).
#
# PS 5.1, UTF-8 BOM.

function Test-CoinExRetriable {
    <#
    .SYNOPSIS
        True se mensagem de erro indica transient/safe-to-retry.
    #>
    [CmdletBinding()]
    param([string] $ErrorMessage)
    if ([string]::IsNullOrEmpty($ErrorMessage)) { return $false }
    $patterns = @(
        '\b429\b', '\b503\b', '\b502\b', '\b504\b',
        'too many requests', 'service unavailable', 'gateway',
        'timed out', 'timeout', 'connection.*(refused|reset|closed)',
        'dns', 'unable to connect'
    )
    foreach ($p in $patterns) {
        if ($ErrorMessage -imatch $p) { return $true }
    }
    return $false
}

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Executa $ScriptBlock com retry exponencial em erros transient.
    .PARAMETER MaxAttempts
        Total de tentativas (1 = sem retry). Default 3 = ate 2 retries.
    .PARAMETER BaseDelayMs
        Delay base; backoff = BaseDelayMs * 2^(attempt-1). Default 500ms.
    .PARAMETER RetryablePredicate
        ScriptBlock que recebe a exception e retorna $true se deve retry.
        Default = Test-CoinExRetriable na .Exception.Message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [scriptblock] $ScriptBlock,
        [int] $MaxAttempts = 3,
        [int] $BaseDelayMs = 500,
        [scriptblock] $RetryablePredicate = $null
    )
    if (-not $RetryablePredicate) {
        $RetryablePredicate = { param($err) Test-CoinExRetriable ([string]$err.Exception.Message) }
    }
    $attempt = 0
    $lastErr = $null
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        try {
            return & $ScriptBlock
        } catch {
            $lastErr = $_
            $shouldRetry = $false
            try { $shouldRetry = [bool](& $RetryablePredicate $_) } catch { $shouldRetry = $false }
            if (-not $shouldRetry) { throw }
            if ($attempt -ge $MaxAttempts) { throw }
            $delay = $BaseDelayMs * [Math]::Pow(2, $attempt - 1)
            Start-Sleep -Milliseconds $delay
        }
    }
    if ($lastErr) { throw $lastErr }
}
