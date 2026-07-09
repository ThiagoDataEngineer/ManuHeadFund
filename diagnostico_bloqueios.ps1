# diagnostico_bloqueios.ps1 - Identifica todos os 3 bloqueios para trades
# 2026-07-09

Write-Host "`n🔍 DIAGNÓSTICO COMPLETO — 3 BLOQUEIOS IDENTIFICADOS`n" -ForegroundColor Cyan

# ============================================================================
# BLOQUEIO 1: Credenciais LLM faltam (GROQ/Anthropic)
# ============================================================================

Write-Host "BLOQUEIO 1: LLM API Keys" -ForegroundColor Yellow
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

$groqKey = $env:GROQ_API_KEY
$anthropicKey = $env:ANTHROPIC_API_KEY

Write-Host "  GROQ_API_KEY: $(if ([string]::IsNullOrEmpty($groqKey)) {'❌ MISSING'} else {'✅ SET (' + $groqKey.Length + ' chars)'})" -ForegroundColor ($(if ($groqKey) {'Green'} else {'Red'}))
Write-Host "  ANTHROPIC_API_KEY: $(if ([string]::IsNullOrEmpty($anthropicKey)) {'❌ MISSING'} else {'✅ SET (' + $anthropicKey.Length + ' chars)'})" -ForegroundColor ($(if ($anthropicKey) {'Green'} else {'Red'}))

Write-Host "`n  💡 SOLUÇÃO:" -ForegroundColor Cyan
Write-Host "     1. Obter keys em:" -ForegroundColor White
Write-Host "        - GROQ: https://console.groq.com/keys" -ForegroundColor White
Write-Host "        - Anthropic: https://console.anthropic.com/" -ForegroundColor White
Write-Host "     2. Settar no PowerShell:" -ForegroundColor White
Write-Host '        `$env:GROQ_API_KEY = "gsk_..."' -ForegroundColor Cyan
Write-Host '        `$env:ANTHROPIC_API_KEY = "sk-ant-..."' -ForegroundColor Cyan
Write-Host "     3. OU adicionar em config.local.ps1" -ForegroundColor White
Write-Host ""

# ============================================================================
# BLOQUEIO 2: CoinEx credenciais são placeholders
# ============================================================================

Write-Host "BLOQUEIO 2: CoinEx API Credentials" -ForegroundColor Yellow
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

. agents/config.local.ps1 -ErrorAction SilentlyContinue

$coinexId = $script:COINEX_ACCESS_ID
$coinexSecret = $script:COINEX_SECRET_KEY

$isPlaceholderID = $coinexId -like "*placeholder*" -or $coinexId -like "*unknown*"
$isPlaceholderSecret = $coinexSecret -like "*placeholder*" -or $coinexSecret -like "*unknown*"

Write-Host "  COINEX_ACCESS_ID: $(if ($isPlaceholderID) {'❌ PLACEHOLDER'} else {'✅ REAL (' + $coinexId.Substring(0,10) + '...)'})" -ForegroundColor ($(if ($isPlaceholderID) {'Red'} else {'Green'}))
Write-Host "  COINEX_SECRET_KEY: $(if ($isPlaceholderSecret) {'❌ PLACEHOLDER'} else {'✅ REAL (' + $coinexSecret.Substring(0,10) + '...)'})" -ForegroundColor ($(if ($isPlaceholderSecret) {'Red'} else {'Green'}))

Write-Host "`n  💡 SOLUÇÃO:" -ForegroundColor Cyan
Write-Host "     1. Ir para: https://www.coinex.com/user/setting/api" -ForegroundColor White
Write-Host "     2. Criar nova API key (ou copiar existente)" -ForegroundColor White
Write-Host "     3. Atualizar config.local.ps1 ou settar env vars:" -ForegroundColor White
Write-Host '        `$env:COINEX_ACCESS_ID = "..."' -ForegroundColor Cyan
Write-Host '        `$env:COINEX_SECRET_KEY = "..."' -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# BLOQUEIO 3: Funções usam nomes de parâmetro errados
# ============================================================================

Write-Host "BLOQUEIO 3: Function Parameter Mismatch" -ForegroundColor Yellow
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

$betaFile = "agents/lib_beta_calculator_multitf.ps1"
$gemFile = "agents/lib_gem_discovery.ps1"

# Verificar se beta_calculator foi corrigido
$betaContent = Get-Content $betaFile -Raw
$hasBetaFix = $betaContent -match 'Get-CoinexCandles.*-Market.*-Timeframe'
$hasBetaBug = $betaContent -match 'Get-CoinexCandles.*-Symbol.*-Period'

Write-Host "  lib_beta_calculator_multitf.ps1:" -ForegroundColor White
if ($hasBetaFix) {
    Write-Host "     ✅ FIXED: Usa -Market/-Timeframe (correto)" -ForegroundColor Green
} elseif ($hasBetaBug) {
    Write-Host "     ❌ BUG: Usa -Symbol/-Period (INCORRETO)" -ForegroundColor Red
} else {
    Write-Host "     ❓ Função não encontrada ou comentada" -ForegroundColor Yellow
}

# Verificar gem_discovery
$gemContent = Get-Content $gemFile -Raw
$hasGemCorrect = $gemContent -match 'Get-CoinExCandles.*-Timeframe'
$hasGemBug = $gemContent -match 'Get-CoinExCandles.*-Symbol'

Write-Host "  lib_gem_discovery.ps1:" -ForegroundColor White
if ($hasGemCorrect) {
    Write-Host "     ✅ OK: Usa -Market/-Timeframe (correto)" -ForegroundColor Green
} elseif ($hasGemBug) {
    Write-Host "     ❌ BUG: Pode estar usando -Symbol (verificar manualmente)" -ForegroundColor Red
} else {
    Write-Host "     ❓ Função Get-CoinExCandles não encontrada ou comentada" -ForegroundColor Yellow
}

Write-Host "`n  💡 CORREÇÃO: Todas as chamadas para Get-CoinexCandles devem usar:" -ForegroundColor Cyan
Write-Host "     Get-CoinexCandles -Market `<string`> -Timeframe `<string`> -Limit `<int`>" -ForegroundColor White
Write-Host ""

# ============================================================================
# RESUMO & PRÓXIMOS PASSOS
# ============================================================================

Write-Host "RESUMO DOS BLOQUEIOS" -ForegroundColor Yellow
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

$blockerCount = 0
$blockerCount += if ([string]::IsNullOrEmpty($groqKey)) { 1 } else { 0 }
$blockerCount += if ([string]::IsNullOrEmpty($anthropicKey)) { 1 } else { 0 }
$blockerCount += if ($isPlaceholderID -or $isPlaceholderSecret) { 1 } else { 0 }
$blockerCount += if (-not $hasBetaFix) { 1 } else { 0 }

Write-Host "  Total bloqueios ativos: $blockerCount / 4" -ForegroundColor ($(if ($blockerCount -eq 0) {'Green'} else {'Red'}))

Write-Host "`n🎯 PRÓXIMOS PASSOS:" -ForegroundColor Cyan
Write-Host "   1️⃣  Obter GROQ_API_KEY e ANTHROPIC_API_KEY" -ForegroundColor White
Write-Host "   2️⃣  Obter COINEX_ACCESS_ID e COINEX_SECRET_KEY reais" -ForegroundColor White
Write-Host "   3️⃣  Settar env vars OU atualizar config.local.ps1" -ForegroundColor White
Write-Host "   4️⃣  Reiniciar gem_loop daemon" -ForegroundColor White
Write-Host "   5️⃣  Validar com: gem_executor.Tests.ps1" -ForegroundColor White
Write-Host ""
