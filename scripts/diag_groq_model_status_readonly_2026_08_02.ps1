# diag_groq_model_status_readonly_2026_08_02.ps1 -- ONE-SHOT, so leitura.
#
# Owner notou 429 constante da Groq na madrugada de 2026-08-02 (fallback pro
# Mistral em quase toda chamada do Mentor). Pesquisa na web deu resultado
# CONFLITANTE: alguns sites de 3os dizem llama-3.3-70b-versatile foi
# deprecado em 2026-06-17 pro tier free/developer; a doc oficial da Groq
# (console.groq.com/docs/deprecations) diz que o modelo esta ATIVO, so
# lista recomendacoes de substituicao (openai/gpt-oss-120b, qwen/qwen3.6-27b)
# sem confirmar deprecacao efetiva. Teste definitivo: chamada real na API.
#
# Testa 3 modelos: o atual (llama-3.3-70b-versatile, hardcoded em
# lib_claude.ps1) + os 2 recomendados como substituto, pra confirmar qual(is)
# respondem de verdade e comparar o codigo de erro exato se algum falhar
# (429 rate-limit != 404 modelo removido != outro erro).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }

if (-not $env:GROQ_API_KEY) {
    Write-Host "GROQ_API_KEY nao configurada -- abortando." -ForegroundColor Red
    exit 1
}

Write-Host "=== DIAG: status real dos modelos Groq ===" -ForegroundColor Cyan

$modelsToTest = @(
    "llama-3.3-70b-versatile",
    "openai/gpt-oss-120b",
    "qwen/qwen3.6-27b"
)

foreach ($model in $modelsToTest) {
    Write-Host "`n--- Testando: $model ---" -ForegroundColor Yellow
    $body = @{
        model = $model
        messages = @(@{ role = "user"; content = "Responda apenas: OK" })
        max_tokens = 10
    } | ConvertTo-Json -Depth 5

    try {
        $resp = Invoke-RestMethod -Uri "https://api.groq.com/openai/v1/chat/completions" `
            -Method POST `
            -Headers @{ "Authorization" = "Bearer $env:GROQ_API_KEY"; "Content-Type" = "application/json" } `
            -Body $body -TimeoutSec 15 -ErrorAction Stop
        Write-Host "OK -- resposta: $($resp.choices[0].message.content)" -ForegroundColor Green
    } catch {
        $statusCode = $null
        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
        $errBody = $null
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $errBody = $reader.ReadToEnd()
        } catch {}
        Write-Host "FALHOU -- status=$statusCode" -ForegroundColor Red
        if ($errBody) { Write-Host "  body: $errBody" -ForegroundColor Red }
        else { Write-Host "  erro: $($_.Exception.Message)" -ForegroundColor Red }
    }
}

Write-Host "`n=== FIM ===" -ForegroundColor Cyan
