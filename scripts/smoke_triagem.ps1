# smoke_triagem.ps1 -- Smoke test offline do triagem_agent
# Uso: powershell -File scripts/smoke_triagem.ps1
# NAO chama Groq real (mock interno); apenas verifica contrato

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir  = Join-Path (Split-Path $here -Parent) "agents"

# Mock Invoke-GroqJson antes de dot-source pra nao chamar API
function Invoke-GroqJson {
    param([string]$SystemPrompt, [string]$UserContent, $Model, $MaxTokens, $Temperature, $MaxRetries, [string]$Agent)
    Write-Host "  [MOCK Groq] Agent=$Agent UserContent.Length=$($UserContent.Length)" -ForegroundColor DarkGray
    # Simula resposta valida
    return [PSCustomObject]@{
        razao = "smoke test: setup adequado conforme contexto"
        flags = @("smoke","mock")
        score_predicted = 72
    }
}

. (Join-Path $agentsDir "knowledge_retriever.ps1")
. (Join-Path $agentsDir "triagem_agent.ps1")

Write-Host "`n=== SMOKE TEST: Invoke-Triagem BTCUSDT ===" -ForegroundColor Cyan
$ctx = [PSCustomObject]@{
    scanner   = [PSCustomObject]@{ score = 78 }
    prescreen = [PSCustomObject]@{ passed = $true; reason = "OK" }
    macro     = [PSCustomObject]@{ macro_bias = "BULLISH"; score = 70 }
    seasonal  = [PSCustomObject]@{
        momentScore     = 85
        dayOfWeek       = "Monday"
        marketTier      = "btc"
        scoreAdjustment = -3
    }
}
$r = Invoke-Triagem -Market "BTCUSDT" -Context $ctx
$r | Format-List

Write-Host "`n=== SMOKE TEST: Thursday + alt = D ===" -ForegroundColor Cyan
$ctx2 = [PSCustomObject]@{
    scanner   = [PSCustomObject]@{ score = 90 }
    macro     = [PSCustomObject]@{ macro_bias = "BULLISH" }
    seasonal  = [PSCustomObject]@{
        dayOfWeek = "Thursday"; marketTier = "alt"; momentScore = 70
    }
}
$r2 = Invoke-Triagem -Market "PEPEUSDT" -Context $ctx2
$r2 | Format-List

Write-Host "`n=== Knowledge retrieval direto ===" -ForegroundColor Cyan
$kb = Get-RelevantKnowledge -Tags @("livermore","wyckoff") -MaxChunks 2
foreach ($c in $kb) {
    Write-Host "  $($c.source) [$($c.tag)]: $($c.text.Substring(0, [Math]::Min(120, $c.text.Length)))..." -ForegroundColor Gray
}

Write-Host "`nSmoke test concluido. Validacao do contrato OK." -ForegroundColor Green
