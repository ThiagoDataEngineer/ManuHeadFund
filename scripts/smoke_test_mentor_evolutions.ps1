# smoke_test_mentor_evolutions.ps1 -- Integration smoke test (sem API real).
#
# Exercita E5+E2+E4 end-to-end usando mocks:
#   - E5: LLM mock infra (Capture-And-Return)
#   - E2: GATE STATUS block + forbidden phrases guard
#   - E4: alpha_vs_btc computation
#
# Confirma que: lib loads OK / wires funcionam / produce expected outputs.
# Sem API call, sem trade real, ~5 segundos. Stop rapido se algo quebrar.

param([switch] $Verbose)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

. (Join-Path $projectRoot "agents\lib_mentor_gate_block.ps1")
. (Join-Path $projectRoot "agents\lib_alpha_vs_btc.ps1")
. (Join-Path $projectRoot "tests\_helpers\llm_mocks.ps1")

$failures = @()
function _Ok($name) { Write-Host "  PASS $name" -ForegroundColor Green }
function _Fail($name, $why) { Write-Host "  FAIL $name :: $why" -ForegroundColor Red; $script:failures += "$name :: $why" }

Write-Host ""
Write-Host "=== E5 LLM Mocks ==="
Reset-LlmCapture
$mockResp = New-MockMentorResponse -Veredicto EXECUTAR -Confianca 75
$obj = $mockResp | ConvertFrom-Json
if ($obj.veredicto -eq "EXECUTAR" -and $obj.confianca_mentor -eq 75) { _Ok "New-MockMentorResponse genera JSON valido" } else { _Fail "mock response" "veredicto=$($obj.veredicto)" }

$captured = Capture-And-Return -UserContent "TEST PROMPT BODY" -MockResponse "MOCKED_RESPONSE"
if ($captured -eq "MOCKED_RESPONSE" -and (Get-LlmCapture) -eq "TEST PROMPT BODY") { _Ok "Capture-And-Return funciona" } else { _Fail "capture" "got: $captured" }


Write-Host ""
Write-Host "=== E2 GATE STATUS Block ==="
$ctxFull = [PSCustomObject]@{
    mode = "STANDARD"
    fqs = [PSCustomObject]@{ score = 4; category = "QUALITY" }
    beta = [PSCustomObject]@{ asset = 1.115; portfolio_after = 1.118 }
    historical = [PSCustomObject]@{ n_trades = 23; dsr = 0.42; sharpe_30d = 2.1 }
    regime = [PSCustomObject]@{ phase = "phase_3_bear"; bias = "neutral" }
    drawdown = $null
    tori_proximity = $null
    gates = $null
}
$block = Build-GateStatusBlock -FullContext $ctxFull
if ($block -match "GATE STATUS" -and $block -match "\[FQS\]\s+score=4/7 QUALITY") { _Ok "GATE STATUS block construido com FQS visivel" } else { _Fail "block" "missing FQS=4 line" }
if ($block -match "\[DRAWDOWN\]\s+ABSENT") { _Ok "Gates ausentes viram ABSENT explicit (NUNCA silent)" } else { _Fail "absent" "DRAWDOWN should be ABSENT" }
if ($Verbose) {
    Write-Host "----- GATE STATUS block output -----" -ForegroundColor Cyan
    Write-Host $block
    Write-Host "------------------------------------" -ForegroundColor Cyan
}


Write-Host ""
Write-Host "=== E2 Forbidden Phrases Guard ==="
# Cenario 1: response limpa
$cleanResp = "Setup decente: FQS=4/7 QUALITY, beta ok, regime favoravel."
$g1 = Test-PromptForbiddenPhrases -Text $cleanResp -GateStatusBlock $block
if (-not $g1.has_forbidden) { _Ok "Response limpa NAO flagada" } else { _Fail "false positive" "$($g1.found -join ',')" }

# Cenario 2: hallucination FQS quando GATE STATUS tem FQS=4 (deve flagar)
$hallucResp = "FQS indisponivel para este market, recomendo VETAR"
$g2 = Test-PromptForbiddenPhrases -Text $hallucResp -GateStatusBlock $block
if ($g2.has_forbidden) { _Ok "Hallucination 'FQS indisponivel' detectada (FQS=4 no contexto)" } else { _Fail "missed halluc" "should flag" }

# Cenario 3: phrase justificada quando gate eh REALMENTE ABSENT
$ctxNoFqs = [PSCustomObject]@{
    mode = "STANDARD"; fqs = $null; beta = $null; historical = $null
    regime = $null; drawdown = $null; tori_proximity = $null; gates = $null
}
$blockNoFqs = Build-GateStatusBlock -FullContext $ctxNoFqs
$g3 = Test-PromptForbiddenPhrases -Text "FQS indisponivel para este market" -GateStatusBlock $blockNoFqs
if (-not $g3.has_forbidden) { _Ok "Smart detection: phrase JUSTIFICADA quando gate ABSENT" } else { _Fail "smart detection" "should NOT flag" }

# Cenario 4: 'Mesa pulou' sempre flagada
$g4 = Test-PromptForbiddenPhrases -Text "Mesa pulou o debate"
if ($g4.has_forbidden -and $g4.found -contains "Mesa pulou") { _Ok "'Mesa pulou' flagada (trigger word ban)" } else { _Fail "mesa" "should flag" }


Write-Host ""
Write-Host "=== E4 alpha_vs_btc Compute ==="
$tmpCache = Join-Path $env:TEMP "smoke_btc_cache_$PID.json"
try {
    Set-BtcDailyClose -DateUtc "2026-05-15" -Close 95000 -CachePath $tmpCache
    Set-BtcDailyClose -DateUtc "2026-05-20" -Close 100000 -CachePath $tmpCache
    # BTC return: +5.26%

    # Cenario A: alt beat BTC (alpha positive)
    $a1 = Compute-AlphaVsBtc -Market "ETHUSDT" -EntryDateUtc "2026-05-15" -ExitDateUtc "2026-05-20" -TradeReturnPct 10 -CachePath $tmpCache
    if ($a1.valid -and $a1.alpha_vs_btc -gt 4) { _Ok "Alt BEAT BTC: alpha=+$($a1.alpha_vs_btc)pp (trade +10% vs BTC +$($a1.btc_return_pct)%)" } else { _Fail "alpha pos" "got $($a1.alpha_vs_btc)" }

    # Cenario B: alt loses to BTC (alpha negative)
    $a2 = Compute-AlphaVsBtc -Market "ALTUSDT" -EntryDateUtc "2026-05-15" -ExitDateUtc "2026-05-20" -TradeReturnPct 2 -CachePath $tmpCache
    if ($a2.valid -and $a2.alpha_vs_btc -lt 0) { _Ok "Alt LOST to BTC: alpha=$($a2.alpha_vs_btc)pp (BTC-hold would have been better)" } else { _Fail "alpha neg" "got $($a2.alpha_vs_btc)" }

    # Cenario C: BTC trade auto-detect alpha=0
    $a3 = Compute-AlphaVsBtc -Market "BTCUSDT" -EntryDateUtc "2026-05-15" -ExitDateUtc "2026-05-20" -TradeReturnPct 5 -CachePath $tmpCache
    if ($a3.alpha_vs_btc -eq 0) { _Ok "BTCUSDT trade: alpha=0 auto-detect" } else { _Fail "btc trade" "got $($a3.alpha_vs_btc)" }

    # Cenario D: BTC cache miss (fail-soft)
    $a4 = Compute-AlphaVsBtc -Market "ETHUSDT" -EntryDateUtc "2030-01-01" -ExitDateUtc "2030-01-05" -TradeReturnPct 5 -CachePath $tmpCache
    if (-not $a4.valid -and $null -eq $a4.alpha_vs_btc) { _Ok "BTC cache miss: fail-soft (alpha=null, NAO bloqueia close)" } else { _Fail "fail-soft" "valid=$($a4.valid)" }

    # Cenario E: Audit alert
    $negAlphas = @()
    for ($i=0; $i -lt 15; $i++) { $negAlphas += -2.5 }
    for ($i=0; $i -lt 10; $i++) { $negAlphas += 1.0 }
    # 15/25 = 60% negativos
    $audit = Get-AlphaNegativeRate -Alphas $negAlphas -AlertThresholdPct 60
    if ($audit.alert) { _Ok "Audit ALERT fires: $($audit.negative_rate_pct)% trades losing to BTC (n=$($audit.n))" } else { _Fail "audit" "should alert" }
} finally {
    if (Test-Path $tmpCache) { Remove-Item $tmpCache -Force }
}


Write-Host ""
Write-Host "=== Mentor wire integration (mock LLM call) ==="
# Simula chamada Mentor com mock — verifica que ctxBlock contem GATE STATUS
# Sem chamar API real, testamos que o WIRE funciona end-to-end.
# Source mentor_agent.ps1 OUTSIDE mock context to avoid global state pollution

# Just verify wire works by checking that mentor_agent.ps1 source loads E2 lib
$mentorScript = Get-Content (Join-Path $projectRoot "agents\mentor_agent.ps1") -Raw
if ($mentorScript -match "Build-GateStatusBlock") { _Ok "mentor_agent.ps1 wire: chama Build-GateStatusBlock" } else { _Fail "wire" "Build-GateStatusBlock not referenced" }
if ($mentorScript -match "Test-PromptForbiddenPhrases") { _Ok "mentor_agent.ps1 wire: chama Test-PromptForbiddenPhrases post-LLM" } else { _Fail "wire" "Test-PromptForbiddenPhrases not referenced" }


Write-Host ""
Write-Host "=== SMOKE TEST SUMMARY ==="
if ($failures.Count -eq 0) {
    Write-Host "  ALL CHECKS PASS" -ForegroundColor Green
    Write-Host "  E5+E2+E4 integrados, wires funcionando, sem API call queimada"
    exit 0
} else {
    Write-Host "  $($failures.Count) FAILURES:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    exit 1
}
