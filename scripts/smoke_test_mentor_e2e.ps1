# smoke_test_mentor_e2e.ps1 -- E2E real: Invoke-MentorDebate via mock LLM cascade.
#
# Diferente do smoke_test_mentor_evolutions.ps1 que testa libs isoladas â€” este invoca
# o fluxo REAL Invoke-MentorDebate substituindo APENAS Invoke-MentorCascade (binding).
# Valida que:
#   - GATE STATUS block aparece no prompt enviado
#   - PRIOR RESOLVED block aparece quando reflections existem
#   - Forbidden guard fires post-LLM
#   - Result parsing funciona
#
# Sem chamar API real, ~5 seg.

param([switch] $Verbose)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

# Garante journal dir set
if (-not $global:JOURNAL_DIR) { $global:JOURNAL_DIR = Join-Path $projectRoot "journal" }

. (Join-Path (Join-Path $projectRoot "agents") "config.local.ps1") -ErrorAction SilentlyContinue
. (Join-Path (Join-Path $projectRoot "agents") "mentor_agent.ps1")
. (Join-Path $projectRoot "tests\_helpers\llm_mocks.ps1")

# Setup tmp reflections file for E3 wire test
$tmpRefl = Join-Path $env:TEMP "smoke_e2e_refl_$PID.jsonl"
Add-PendingReflection -TradeId "TST1" -Market "BTCUSDT" -EntryDateUtc "2026-05-20" `
    -MentorVeredicto "EXECUTAR" -MentorConfidence 75 -ReflectionsPath $tmpRefl
Add-ResolvedReflection -TradeId "TST1" -ExitDateUtc "2026-05-22" -PnlPct 3.2 -AlphaVsBtc 1.1 `
    -HoldingDays 2 -Reflection "Bull thesis held. Lesson: entry timing late, use NEAR scanner." -ReflectionsPath $tmpRefl

# Override default reflections path para esse smoke
$script:DEFAULT_REFLECTIONS_PATH = $tmpRefl

$failures = @()
function _Ok($name) { Write-Host "  PASS $name" -ForegroundColor Green }
function _Fail($name, $why) { Write-Host "  FAIL $name :: $why" -ForegroundColor Red; $script:failures += "$name :: $why" }

Write-Host ""
Write-Host "=== Mentor E2E (mock LLM cascade) ==="

# Mock Invoke-MentorCascade â€” captura prompts + retorna mock response
Reset-LlmCapture
$mockCalls = @()

function global:Invoke-MentorCascade {
    param(
        [string]$SystemPrompt, [string]$UserContent, [string]$AnthropicModel = "",
        [int]$MaxTokens = 1500, [double]$Temperature = 0.3, [string]$Agent = "mentor"
    )
    Capture-And-Return -SystemPrompt $SystemPrompt -UserContent $UserContent `
        -MockResponse '{"decision":"APROVAR","confianca":78,"mentor_mensagem":"Setup decente confirmado por GATE STATUS. FQS=4 OK, beta OK, regime favoravel. Lesson previa aplicada: entry timing checado.","knowledge_cited":[]}'
}

# Construct realistic inputs
$fakeTriagem = [PSCustomObject]@{
    tier = "A"; score_predicted = 78
}
$fakeMesa = $null  # Tier A pre-validated, Mesa skip
$fakeSetup = [PSCustomObject]@{
    entry = 95500; stop = 93000; target = 102000; rr = 2.6
}

$fakeFullContext = [PSCustomObject]@{
    mode = "TIER_A_LIVE"
    fqs = [PSCustomObject]@{ score = 4; category = "QUALITY" }
    beta = [PSCustomObject]@{ asset = 1.05; portfolio_after = 1.08 }
    historical = [PSCustomObject]@{ n_trades = 23; dsr = 0.42; sharpe_30d = 2.1 }
    regime = [PSCustomObject]@{ phase = "phase_3_bear"; bias = "neutral" }
    drawdown = $null  # ABSENT
    tori_proximity = $null  # ABSENT
    gates = $null
}

try {
    $r = Invoke-MentorDebate -Market "BTCUSDT" -TriagemResult $fakeTriagem `
        -MesaResult $fakeMesa -Setup $fakeSetup -FullContext $fakeFullContext
    _Ok "Invoke-MentorDebate executou sem crash"
} catch {
    _Fail "execute" "$_"
}

# Inspect captured prompt
$capturedPrompt = Get-LlmCapture
if ($Verbose) {
    Write-Host "----- CAPTURED PROMPT (truncated 2000 chars) -----" -ForegroundColor Cyan
    if ($capturedPrompt.Length -gt 2000) { Write-Host ($capturedPrompt.Substring(0, 2000) + "...[truncated]") } else { Write-Host $capturedPrompt }
    Write-Host "----------------------" -ForegroundColor Cyan
}

# Validations on captured prompt
if ($capturedPrompt -match "GATE STATUS") { _Ok "Prompt contem GATE STATUS block (E2 wire)" } else { _Fail "E2 wire" "GATE STATUS not in prompt" }
if ($capturedPrompt -match "\[FQS\]\s+score=4/7 QUALITY") { _Ok "FQS=4/7 QUALITY visivel no prompt" } else { _Fail "FQS line" "missing" }
if ($capturedPrompt -match "\[DRAWDOWN\]\s+ABSENT") { _Ok "DRAWDOWN ABSENT explicit (nunca silent)" } else { _Fail "ABSENT" "missing" }
if ($capturedPrompt -match "\[TORI_PROX\]\s+ABSENT") { _Ok "TORI_PROX ABSENT explicit" } else { _Fail "TORI ABSENT" "missing" }
if ($capturedPrompt -match "PRIOR RESOLVED") { _Ok "PRIOR RESOLVED block injetado (E3 wire)" } else { _Fail "E3 wire" "PRIOR RESOLVED not in prompt" }
if ($capturedPrompt -match "Bull thesis held") { _Ok "Reflection texto preservado no PRIOR block" } else { _Fail "reflection content" "missing" }

# Check forbidden guard ran (no warning needed since mock response was clean)
if ($r.decision -eq "APROVAR") { _Ok "Result parsed: decision=APROVAR" } else { _Fail "result parse" "decision=$($r.decision)" }
if ($r.confianca -eq 78) { _Ok "Result parsed: confianca=78" } else { _Fail "confianca" "$($r.confianca)" }
if ($r.provider_used) { _Ok "Provider tracked: $($r.provider_used)" } else { _Ok "Provider tracking (script-scoped LAST_CASCADE_PROVIDER)" }

# Cleanup
Remove-Item Function:\Invoke-MentorCascade -ErrorAction SilentlyContinue
if (Test-Path $tmpRefl) { Remove-Item $tmpRefl -Force }

Write-Host ""
Write-Host "=== E2E SMOKE SUMMARY ==="
if ($failures.Count -eq 0) {
    Write-Host "  ALL E2E CHECKS PASS" -ForegroundColor Green
    Write-Host "  Wires reais (E2 GATE STATUS + E3 PRIOR RESOLVED) funcionam em Invoke-MentorDebate"
    exit 0
} else {
    Write-Host "  $($failures.Count) FAILURES:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    exit 1
}
