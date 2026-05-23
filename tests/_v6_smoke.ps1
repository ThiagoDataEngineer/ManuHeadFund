# _v6_smoke.ps1 -- smoke test end-to-end V6 com mocks A+B
# Valida que orchestrator_v6 + lib_esquadrao_mocks + mentor_debate trabalham juntos
# sem chamar Claude/CoinEx reais.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agents = Join-Path $here "..\agents"

# Stubs config + IO
$global:CLAUDE_MODEL      = "claude-sonnet-4"
$global:CLAUDE_MAX_TOKENS = 4000
$global:CLAUDE_TEMP_TRADE = 0.3
$global:ANTHROPIC_API_KEY = "test-key"
$env:TELEGRAM_ENABLED     = "false"

. (Join-Path $agents "mentor_agent.ps1")
. (Join-Path $agents "lib_telegram.ps1")
. (Join-Path $agents "orchestrator_v6.ps1")
. (Join-Path $agents "lib_esquadrao_mocks.ps1")

# Stub Invoke-ClaudeJson APOS sources (caminho do mentor real)
function Invoke-ClaudeJson {
    param($SystemPrompt,$UserContent,$Model,$MaxTokens,$Temperature,$MaxRetries,$Agent)
    return [PSCustomObject]@{
        decision="APROVAR"; confianca=82
        mentor_mensagem="Setup limpo, Mesa unida, R:R favoravel. Tudor aprovaria."
        knowledge_cited=@("MENTOR.md:tudor_risk_1pct")
    }
}

Write-Host "`n=== SMOKE V6 -- BTCUSDT (mocks A+B + mentor stub) ===" -ForegroundColor Cyan

$ctx   = [PSCustomObject]@{ macro="NEUTRO"; capital=1000 }
$setup = [PSCustomObject]@{ entry=70000; stop=68000; target=78000; rr=4 }

$out = Invoke-V6Cascade -Market "BTCUSDT" -Context $ctx -Setup $setup

Write-Host "Decisao: $($out.decisao)"          -ForegroundColor Green
Write-Host "Triagem: tier=$($out.triagem.tier) score=$($out.triagem.score_predicted)"
Write-Host "Mesa:    $($out.mesa.consensus) $($out.mesa.sinal_consenso) avg=$($out.mesa.score_avg)"
Write-Host "Mentor:  $($out.mentor.decision) conf=$($out.mentor.confianca)"
Write-Host "Telegram fire: $($out.telegramFire)"

# Formato Telegram
$tg = Format-TgEsquadraoResult -Market "BTCUSDT" -Triagem $out.triagem `
    -Mesa $out.mesa -Mentor $out.mentor -Decisao $out.decisao
Write-Host "`n--- Telegram preview ---" -ForegroundColor Cyan
Write-Host $tg

# Cycle filter
$hasNews1 = Test-CycleHasNews -GemCount 1 -MesaPassed 0 -TrailPhaseChg 0 -Executions 0
$hasNews0 = Test-CycleHasNews -GemCount 0 -MesaPassed 0 -TrailPhaseChg 0 -Executions 0
Write-Host "`n--- Cycle filter ---" -ForegroundColor Cyan
Write-Host "1 gem,  0 outras: hasNews=$hasNews1 (esperado True)"
Write-Host "0 gems, 0 outras: hasNews=$hasNews0 (esperado False)"

if ($out.decisao -eq "EXECUTAR" -and $hasNews1 -eq $true -and $hasNews0 -eq $false) {
    Write-Host "`nSMOKE V6 OK" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nSMOKE V6 FALHOU" -ForegroundColor Red
    exit 1
}
