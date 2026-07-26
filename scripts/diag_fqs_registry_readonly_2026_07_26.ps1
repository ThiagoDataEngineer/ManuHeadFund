# diag_fqs_registry_readonly_2026_07_26.ps1 -- diagnostico ONE-SHOT, so leitura
# Owner reportou "zero trades" -- investigacao encontrou que TODOS os candidatos
# avaliados pelo Mentor real hoje mostravam FQS=3/7 SPECULATIVE (DOGE, SKY, XRP,
# ARB, SUI, RENDER), mas o calculo manual local (journal/coin_registry.json via
# Get-FundamentalScore) da valores diferentes (ex: XRP=5, ARB=5, RENDER=5 =
# QUALITY, nao SPECULATIVE). mentor_agent.ps1 tenta Supabase "fqs_registry"
# PRIMEIRO, so cai no calculo local se a tabela nao tiver o registro -- ou seja,
# o valor real usado pelo Mentor vem de uma fonte diferente da que calculei
# manualmente. Este script le a tabela real pra confirmar o que esta la.
# NAO escreve nada.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_fundamental_quality.ps1")

Write-Host "=== DIAG FQS REGISTRY (READ-ONLY) ===" -ForegroundColor Cyan
Write-Host "Backend: $(Test-StateBackend)" -ForegroundColor Cyan

$markets = @("DOGEUSDT","SKYUSDT","XRPUSDT","ARBUSDT","SUIUSDT","RENDERUSDT","OPUSDT","ADAUSDT")

foreach ($mkt in $markets) {
    Write-Host "--- $mkt ---" -ForegroundColor Yellow
    try {
        $records = @(Get-StateRecords -Table "fqs_registry" -Filter @{ market = $mkt })
        if ($records.Count -gt 0) {
            Write-Host "  SUPABASE: $($records[0] | ConvertTo-Json -Compress)" -ForegroundColor Green
        } else {
            Write-Host "  SUPABASE: sem registro" -ForegroundColor DarkYellow
        }
    } catch {
        Write-Host "  SUPABASE ERRO: $_" -ForegroundColor Red
    }

    try {
        $local = Get-FundamentalScore -Market $mkt
        Write-Host "  LOCAL (coin_registry.json): fqs=$($local.fqs) category=$($local.category) reason=$($local.reason)" -ForegroundColor Cyan
    } catch {
        Write-Host "  LOCAL ERRO: $_" -ForegroundColor Red
    }
}

Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
