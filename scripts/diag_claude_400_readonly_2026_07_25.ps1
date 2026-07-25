# diag_claude_400_readonly_2026_07_25.ps1 -- diagnostico ONE-SHOT, so leitura
# Sonnet/Haiku retornam 400 em 100% das chamadas mesmo apos corrigir os IDs
# de modelo (ed994aa). Mensagem de log trunca em 80 chars antes do corpo real
# do erro (5baf7a2 adicionou captura do body mas o Write-Host chamador ainda
# corta cedo demais). Este script chama Invoke-Claude direto e imprime a
# excecao INTEIRA, sem truncar, pra ver a mensagem real da API Anthropic.
# NAO envia nenhuma ordem, so 1 chamada de teste minima ao LLM. Remover job
# apos uso.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_claude.ps1")

Write-Host "=== DIAG CLAUDE 400 (READ-ONLY) ===" -ForegroundColor Cyan
Write-Host "CLAUDE_MODEL=$CLAUDE_MODEL" -ForegroundColor Cyan
Write-Host "CLAUDE_MODEL_CHEAP=$CLAUDE_MODEL_CHEAP" -ForegroundColor Cyan
Write-Host "ANTHROPIC_API_KEY set: $([bool]$env:ANTHROPIC_API_KEY)" -ForegroundColor Cyan
if ($env:ANTHROPIC_API_KEY) {
    Write-Host "ANTHROPIC_API_KEY length: $($env:ANTHROPIC_API_KEY.Length)" -ForegroundColor Cyan
    Write-Host "ANTHROPIC_API_KEY prefix: $($env:ANTHROPIC_API_KEY.Substring(0, [Math]::Min(10, $env:ANTHROPIC_API_KEY.Length)))" -ForegroundColor Cyan
}

Write-Host "PSVersion: $($PSVersionTable.PSVersion) Edition: $($PSVersionTable.PSEdition)" -ForegroundColor Cyan

# Chamada RAW direta (bypass Invoke-Claude) pra ver o erro sem nenhuma camada
# de abstracao -- descobrir se o problema e no pwsh Core (Linux runner) que
# expoe erro HTTP diferente do Windows PowerShell 5.1 Desktop testado local.
try {
    $body = @{ model = $CLAUDE_MODEL; max_tokens = 10; messages = @(@{role="user";content="teste"}) } | ConvertTo-Json -Compress
    $wr = Invoke-WebRequest -Uri "https://api.anthropic.com/v1/messages" -Method POST `
        -Headers @{ "x-api-key" = $env:ANTHROPIC_API_KEY; "anthropic-version" = "2023-06-01"; "content-type" = "application/json" } `
        -Body $body -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
    Write-Host "RAW SUCESSO: $($wr.Content)" -ForegroundColor Green
} catch {
    Write-Host "RAW ERRO -- tipo excecao: $($_.Exception.GetType().FullName)" -ForegroundColor Red
    Write-Host "RAW ERRO -- Exception.Message: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "RAW ERRO -- ErrorDetails.Message: $($_.ErrorDetails.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        Write-Host "RAW ERRO -- Response tipo: $($_.Exception.Response.GetType().FullName)" -ForegroundColor Red
        try {
            $content = $_.Exception.Response.Content.ReadAsStringAsync().Result
            Write-Host "RAW ERRO -- Response.Content (HttpResponseMessage): $content" -ForegroundColor Red
        } catch { Write-Host "RAW ERRO -- Response.Content falhou: $_" -ForegroundColor Red }
    }
}

try {
    $r = Invoke-Claude -SystemPrompt "Responda apenas com a palavra OK." -UserContent "teste" `
        -Model $CLAUDE_MODEL -MaxTokens 10 -Temperature 0 -Agent "diag_400"
    Write-Host "SONNET SUCESSO: $r" -ForegroundColor Green
} catch {
    Write-Host "SONNET ERRO COMPLETO:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

try {
    $r2 = Invoke-Claude -SystemPrompt "Responda apenas com a palavra OK." -UserContent "teste" `
        -Model $CLAUDE_MODEL_CHEAP -MaxTokens 10 -Temperature 0 -Agent "diag_400_haiku"
    Write-Host "HAIKU SUCESSO: $r2" -ForegroundColor Green
} catch {
    Write-Host "HAIKU ERRO COMPLETO:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
