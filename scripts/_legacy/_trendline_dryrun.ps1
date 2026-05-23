. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_claude.ps1"

# ── Mock de Claude quando API indisponivel ────────────────────────────────────
# $MOCK_ACTIVE = $true  -> usa JSON pre-fabricado (sem gastar API)
# $MOCK_ACTIVE = $false -> usa Claude real (lib_claude.ps1 carregado acima)
$MOCK_ACTIVE = $false

if ($MOCK_ACTIVE) {
    function Invoke-ClaudeJson {
        param([string]$SystemPrompt, [string]$UserContent,
              [string]$Model, [int]$MaxTokens, [double]$Temperature, [int]$MaxRetries)
        Write-Host "  [MOCK] Retornando JSON pre-fabricado (Claude API indisponivel)" -ForegroundColor DarkMagenta
        $price = 80700.0
        return [PSCustomObject]@{
            sinal                  = "LONG"
            forca                  = 74
            qualidade_setup        = "B+"
            timeframe_dominante    = "4H"
            preco_entrada          = $price
            stop_loss              = 78200.0
            stop_estrutural_razao  = "Abaixo do ultimo swing low 4H e Order Block bullish em 78.2k"
            alvo1                  = 84500.0
            alvo2                  = 88000.0
            rr_calculado           = 2.96
            confluencias           = @("EMA9 cruzou EMA21 no 4H","RSI2 saindo de sobrevenda","VWAP como suporte","Wyckoff Spring 1D")
            riscos                 = @("ADX 4H em 18 - range pode absorver rompimento","Funding positivo 0.02%")
            weinstein_fase         = "2 - uptrend confirmado, acima MA30W"
            wyckoff_contexto       = "Possivel Spring apos teste de suporte - estrutura de acumulacao no 1D"
            elder_screen           = "ATIVO"
            trendline              = [PSCustomObject]@{
                quality       = "A+"
                setup_type    = "BOUNCE"
                action_line   = 80650.0
                safety_line   = 78200.0
                touchpoints   = 4
                weeks_of_data = 6
                entry_timing  = "ON_LINE"
                htf_aligned   = $true
                sweep_risk    = "LOW"
                verdict       = "ENTER"
                reason        = "4 toques limpos em 6 semanas, preco testando linha agora com HTF alinhado"
            }
            trendline_invalid      = $false
            justificativa          = "Estrutura bullish clara no 4H com Spring Wyckoff confirmado. Trendline A+ com 4 toques oferece entrada precisa em 80.6k. RR 1:3 aceitavel apesar do ADX baixo."
        }
    }
}
# ─────────────────────────────────────────────────────────────────────────────

. "$PSScriptRoot\agents\tech_agent_ai.ps1"

Write-Host "=== TechAgent Trendline Dry-Run $(if ($MOCK_ACTIVE) {'[MOCK]'} else {'[REAL]'}) ===" -ForegroundColor Cyan
Write-Host "Mercado: BTCUSDT" -ForegroundColor White
Write-Host ""

$r = Invoke-TechAgent -Market "BTCUSDT"

Write-Host ""
Write-Host "=== RESULTADO PRINCIPAL ===" -ForegroundColor Cyan
Write-Host "Sinal:             $($r.sinal)" -ForegroundColor $(if($r.sinal -eq "LONG"){"Green"}elseif($r.sinal -eq "SHORT"){"Red"}else{"Yellow"})
Write-Host "Forca:             $($r.forca)" -ForegroundColor White
Write-Host "Qualidade Setup:   $($r.qualidade_setup)" -ForegroundColor White
Write-Host "Trendline Invalid: $($r.trendline_invalid)" -ForegroundColor $(if($r.trendline_invalid){"Red"}else{"Green"})

Write-Host ""
Write-Host "=== TRENDLINE BLOCK ===" -ForegroundColor Cyan
if ($r.trendline) {
    $verdictColor = switch ($r.trendline.verdict) { "ENTER"{"Green"} "SKIP"{"Red"} default{"Yellow"} }
    Write-Host "  verdict:       $($r.trendline.verdict)" -ForegroundColor $verdictColor
    Write-Host "  quality:       $($r.trendline.quality)" -ForegroundColor Yellow
    Write-Host "  setup_type:    $($r.trendline.setup_type)" -ForegroundColor Yellow
    Write-Host "  action_line:   $($r.trendline.action_line)" -ForegroundColor Yellow
    Write-Host "  safety_line:   $($r.trendline.safety_line)" -ForegroundColor Yellow
    Write-Host "  touchpoints:   $($r.trendline.touchpoints)" -ForegroundColor Yellow
    Write-Host "  weeks_of_data: $($r.trendline.weeks_of_data)" -ForegroundColor Yellow
    Write-Host "  entry_timing:  $($r.trendline.entry_timing)" -ForegroundColor Yellow
    Write-Host "  htf_aligned:   $($r.trendline.htf_aligned)" -ForegroundColor Yellow
    Write-Host "  sweep_risk:    $($r.trendline.sweep_risk)" -ForegroundColor Yellow
    Write-Host "  reason:        $($r.trendline.reason)" -ForegroundColor Yellow
} else {
    Write-Host "  [ERRO] Campo trendline ausente ou null!" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== CONFLUENCIAS (pos-Tori) ===" -ForegroundColor Cyan
if ($r.confluencias) {
    $r.confluencias | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
} else {
    Write-Host "  [vazio]" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "=== LEVELS ===" -ForegroundColor Cyan
Write-Host "  Entrada:  $($r.preco_entrada)" -ForegroundColor White
Write-Host "  Stop:     $($r.stop_loss)" -ForegroundColor White
Write-Host "  Alvo1:    $($r.alvo1)" -ForegroundColor White
Write-Host "  Alvo2:    $($r.alvo2)" -ForegroundColor White
Write-Host "  RR calc:  $($r.rr_calculado)" -ForegroundColor White

Write-Host ""
Write-Host "=== JUSTIFICATIVA ===" -ForegroundColor Cyan
Write-Host $r.justificativa -ForegroundColor White

# Validacoes automaticas
Write-Host ""
Write-Host "=== VALIDACOES ===" -ForegroundColor Cyan
$erros = 0

function Check($label, $cond) {
    if ($cond) { Write-Host "  [OK] $label" -ForegroundColor Green }
    else       { Write-Host "  [FAIL] $label" -ForegroundColor Red; $script:erros++ }
}

Check "trendline block presente"           ($r.trendline -ne $null)
Check "trendline.verdict preenchido"       ($r.trendline.verdict -match "ENTER|WAIT|SKIP")
Check "trendline.quality preenchido"       ($r.trendline.quality -match "A\+|A|B|C|NONE")
Check "trendline.action_line > 0"          ($r.trendline.action_line -gt 0)
Check "trendline.touchpoints >= 2"         ($r.trendline.touchpoints -ge 2)
Check "stop_loss < preco_entrada (LONG)"   ($r.sinal -ne "LONG" -or $r.stop_loss -lt $r.preco_entrada)
Check "confluencias nao vazias"            ($r.confluencias.Count -gt 0)
Check "ToriLayer ENTER adicionou label"    ($r.confluencias -match "Trendline" | Measure-Object).Count -gt 0

if ($erros -eq 0) { Write-Host "`n  TUDO OK - pipeline validado com mock" -ForegroundColor Green }
else              { Write-Host "`n  $erros FALHA(S) detectada(s)" -ForegroundColor Red }
