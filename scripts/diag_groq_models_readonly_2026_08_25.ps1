# diag_groq_models_readonly_2026_08_25.ps1 -- ONE-SHOT, so leitura.
#
# 2 tentativas de fallback dinamico do Groq ja falharam em producao real
# (1a: escolheu prompt-guard, um guard-rail; 2a: escolheu orpheus/allam,
# modelos de TTS/nicho) -- precisa ver a lista REAL completa de /v1/models
# antes de tentar um 3o fix as cegas.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")

Write-Host "=== DIAG: lista completa /v1/models da Groq (READ-ONLY) ===" -ForegroundColor Cyan

$key = if ($env:GROQ_API_KEY) { $env:GROQ_API_KEY } else { $null }
if (-not $key) {
    Write-Host "GROQ_API_KEY nao configurada" -ForegroundColor Red
    exit 1
}

try {
    $wr = Invoke-RestMethod -Uri "https://api.groq.com/openai/v1/models" `
        -Headers @{ "Authorization" = "Bearer $key" } -TimeoutSec 15 -ErrorAction Stop
    Write-Host "Total de modelos: $(@($wr.data).Count)`n"
    foreach ($m in @($wr.data) | Sort-Object id) {
        $active = if ($m.PSObject.Properties['active']) { $m.active } else { "?" }
        Write-Host "  id=$($m.id) | active=$active | owned_by=$($m.owned_by) | context_window=$($m.context_window)"
    }
} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
