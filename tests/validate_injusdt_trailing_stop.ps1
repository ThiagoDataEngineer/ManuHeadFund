# validate_injusdt_trailing_stop.ps1
# Validar implementação de trailing stop automático para INJUSDT
# 2026-05-29

# Carregar dependências
$scriptRoot = Split-Path -Parent $PSScriptRoot
$agentsPath = Join-Path $scriptRoot "agents"

# Dot-source as funções
$trailingStopPath = Join-Path $agentsPath "lib_trailing_stop_intelligent.ps1"
$coinexAIPath = Join-Path $agentsPath "lib_coinex_ai_integration.ps1"

if (Test-Path $trailingStopPath) {
    . $trailingStopPath
    Write-Host "✅ Loaded: lib_trailing_stop_intelligent.ps1"
} else {
    Write-Host "❌ Not found: $trailingStopPath"
    exit 1
}

if (Test-Path $coinexAIPath) {
    . $coinexAIPath
    Write-Host "✅ Loaded: lib_coinex_ai_integration.ps1"
} else {
    Write-Host "❌ Not found: $coinexAIPath"
    exit 1
}

Write-Host ""

# ============================================================================
# TEST 1: Initialize-AutomaticTPSL
# ============================================================================

Write-Host "=" * 80
Write-Host "TEST 1: Initialize-AutomaticTPSL"
Write-Host "=" * 80

$tpsl = Initialize-AutomaticTPSL `
    -Entry 6.4335 `
    -CurrentPrice 6.4266 `
    -Peak24h 6.7004 `
    -Qty 18.583278 `
    -Mode "GEM"

Write-Host "✅ TP/SL Automático Inicializado:"
Write-Host "   Entry: $($tpsl.Entry)"
Write-Host "   TP Base: $($tpsl.TPBase)"
Write-Host "   SL Base: $($tpsl.SLBase)"
Write-Host "   Trailing Stop: $($tpsl.TrailingStop)"
Write-Host "   Total Qty: $($tpsl.TotalQty)"
Write-Host ""
Write-Host "Saídas Parciais:"
foreach ($exit in $tpsl.PartialExits) {
    Write-Host "   Nível $($exit.Level): $($exit.Price) (Qty: $($exit.Qty), $($exit.Percent)%)"
}

# Validações
$test1Pass = $true

if ($tpsl.TPBase -ne 8.5) {
    Write-Host "❌ TP Base incorreto: $($tpsl.TPBase) (esperado: 8.5)"
    $test1Pass = $false
}

if ($tpsl.SLBase -ne 4.3323) {
    Write-Host "❌ SL Base incorreto: $($tpsl.SLBase) (esperado: 4.3323)"
    $test1Pass = $false
}

if ($tpsl.TrailingStop -lt 5.7 -or $tpsl.TrailingStop -gt 5.8) {
    Write-Host "❌ Trailing Stop incorreto: $($tpsl.TrailingStop) (esperado: ~5.73)"
    $test1Pass = $false
}

if ($tpsl.PartialExits.Count -ne 3) {
    Write-Host "❌ Número de saídas parciais incorreto: $($tpsl.PartialExits.Count) (esperado: 3)"
    $test1Pass = $false
}

# Validar saídas parciais
$level1Qty = $tpsl.PartialExits[0].Qty
$level2Qty = $tpsl.PartialExits[1].Qty
$level3Qty = $tpsl.PartialExits[2].Qty
$totalExitQty = $level1Qty + $level2Qty + $level3Qty

if ([Math]::Abs($totalExitQty - $tpsl.TotalQty) -gt 0.00001) {
    Write-Host "❌ Quantidade total de saídas incorreta: $totalExitQty (esperado: $($tpsl.TotalQty))"
    $test1Pass = $false
}

if ($test1Pass) {
    Write-Host "✅ TEST 1 PASSOU"
} else {
    Write-Host "❌ TEST 1 FALHOU"
}

Write-Host ""

# ============================================================================
# TEST 2: Get-CoinExAIAnalysis
# ============================================================================

Write-Host "=" * 80
Write-Host "TEST 2: Get-CoinExAIAnalysis"
Write-Host "=" * 80

$coinexAnalysis = Get-CoinExAIAnalysis -Symbol "INJUSDT"

Write-Host "✅ Análise CoinEx Consumida:"
Write-Host "   Source: $($coinexAnalysis.Source)"
Write-Host "   Symbol: $($coinexAnalysis.Symbol)"
Write-Host "   Confidence: $($coinexAnalysis.Confidence)"
Write-Host "   Key Takeaways: $($coinexAnalysis.KeyTakeaways.Count)"
Write-Host ""
Write-Host "Key Takeaways:"
foreach ($takeaway in $coinexAnalysis.KeyTakeaways) {
    Write-Host "   - $takeaway"
}

# Validações
$test2Pass = $true

if (-not $coinexAnalysis.Success) {
    Write-Host "❌ Falha ao consumir análise CoinEx"
    $test2Pass = $false
}

if ($coinexAnalysis.KeyTakeaways.Count -eq 0) {
    Write-Host "❌ Nenhum key takeaway encontrado"
    $test2Pass = $false
}

if ($coinexAnalysis.Confidence -lt 0.8) {
    Write-Host "❌ Confidence baixa: $($coinexAnalysis.Confidence)"
    $test2Pass = $false
}

if ($test2Pass) {
    Write-Host "✅ TEST 2 PASSOU"
} else {
    Write-Host "❌ TEST 2 FALHOU"
}

Write-Host ""

# ============================================================================
# TEST 3: Validate-CoinExAnalysis
# ============================================================================

Write-Host "=" * 80
Write-Host "TEST 3: Validate-CoinExAnalysis"
Write-Host "=" * 80

$validation = Validate-CoinExAnalysis -Analysis $coinexAnalysis

Write-Host "✅ Validação CoinEx:"
Write-Host "   IsValid: $($validation.IsValid)"
Write-Host "   Valid Checks: $($validation.ValidCount)/$($validation.TotalChecks)"
Write-Host ""
Write-Host "Detalhes:"
foreach ($check in $validation.Validations.GetEnumerator()) {
    $status = if ($check.Value) { "✅" } else { "❌" }
    Write-Host "   $status $($check.Name): $($check.Value)"
}

# Validações
$test3Pass = $validation.IsValid

if (-not $test3Pass) {
    Write-Host "❌ TEST 3 FALHOU"
} else {
    Write-Host "✅ TEST 3 PASSOU"
}

Write-Host ""

# ============================================================================
# TEST 4: Compare-TechnicalAnalysis
# ============================================================================

Write-Host "=" * 80
Write-Host "TEST 4: Compare-TechnicalAnalysis"
Write-Host "=" * 80

$ourAnalysis = [PSCustomObject]@{
    RSI = 72
    MACD = 0.15
    Resistance = 6.70
    Support = 6.40
    Volume = 8320000
}

$technicalComparison = Compare-TechnicalAnalysis -CoinExAnalysis $coinexAnalysis -OurAnalysis $ourAnalysis

Write-Host "✅ Comparação Técnica:"
Write-Host "   Alignment Score: $([Math]::Round($technicalComparison.AlignmentScore * 100, 1))%"
Write-Host "   Is Aligned: $($technicalComparison.IsAligned)"
Write-Host ""
Write-Host "Detalhes:"
foreach ($detail in $technicalComparison.Details) {
    Write-Host "   $detail"
}

# Validações
$test4Pass = $technicalComparison.AlignmentScore -ge 0.6

if (-not $test4Pass) {
    Write-Host "❌ TEST 4 FALHOU (alignment score baixo)"
} else {
    Write-Host "✅ TEST 4 PASSOU"
}

Write-Host ""

# ============================================================================
# TEST 5: Compare-Sentiment
# ============================================================================

Write-Host "=" * 80
Write-Host "TEST 5: Compare-Sentiment"
Write-Host "=" * 80

$ourSentiment = [PSCustomObject]@{
    LongTerm = "BULLISH"
    ShortTerm = "BEARISH"
    Macro = "CAUTIOUS"
    MarketSentiment = "MIXED"
}

$sentimentComparison = Compare-Sentiment -CoinExAnalysis $coinexAnalysis -OurAnalysis $ourSentiment

Write-Host "✅ Comparação Sentimento:"
Write-Host "   Alignment Score: $([Math]::Round($sentimentComparison.AlignmentScore * 100, 1))%"
Write-Host "   Is Aligned: $($sentimentComparison.IsAligned)"
Write-Host ""
Write-Host "Detalhes:"
foreach ($detail in $sentimentComparison.Details) {
    Write-Host "   $detail"
}

# Validações
$test5Pass = $sentimentComparison.AlignmentScore -ge 0.6

if (-not $test5Pass) {
    Write-Host "❌ TEST 5 FALHOU (alignment score baixo)"
} else {
    Write-Host "✅ TEST 5 PASSOU"
}

Write-Host ""

# ============================================================================
# RESUMO
# ============================================================================

Write-Host "=" * 80
Write-Host "RESUMO DOS TESTES"
Write-Host "=" * 80

$allTests = @(
    @{ Name = "TEST 1: Initialize-AutomaticTPSL"; Pass = $test1Pass }
    @{ Name = "TEST 2: Get-CoinExAIAnalysis"; Pass = $test2Pass }
    @{ Name = "TEST 3: Validate-CoinExAnalysis"; Pass = $test3Pass }
    @{ Name = "TEST 4: Compare-TechnicalAnalysis"; Pass = $test4Pass }
    @{ Name = "TEST 5: Compare-Sentiment"; Pass = $test5Pass }
)

$passCount = ($allTests | Where-Object { $_.Pass }).Count
$totalCount = $allTests.Count

foreach ($test in $allTests) {
    $status = if ($test.Pass) { "✅ PASSOU" } else { "❌ FALHOU" }
    Write-Host "$status - $($test.Name)"
}

Write-Host ""
Write-Host "RESULTADO FINAL: $passCount/$totalCount testes passaram"

if ($passCount -eq $totalCount) {
    Write-Host "🎉 TODOS OS TESTES PASSARAM!"
    exit 0
} else {
    Write-Host "⚠️  ALGUNS TESTES FALHARAM"
    exit 1
}
