# gem_executor.ps1 -- Execucao real de gems na CoinEx
# Padrao: FUTURES (isolated margin). Fallback: SPOT quando par nao tem futuros.
# Dot-source: . (Join-Path $PSScriptRoot "gem_executor.ps1")

# 2026-06-28 CAUSA RAIZ (Add-TrailingPosition caia no default "public",
# schema compartilhado com outro app -- congelamento 26/06): FORCAR
# STATE_STORE_SCHEMA=manuheadfund ANTES de qualquer persistencia deste
# arquivo. 2026-08-15 FIX: o force original ficava so na linha ~2555
# (dentro do registro de trade ABERTO, Add-TrailingPosition) -- mas
# Write-SignalSkip (candidatos REJEITADOS, a materia-prima real de
# trade_rejections/mce_counterfactual_agg/Evolution Engine) e chamada 6x
# ANTES desse ponto no arquivo (linhas ~469-2230), sempre sem o schema
# forcado ainda. Resultado real medido: trade_rejections ficou vazia por
# ~1 mes em producao, mce_counterfactual_agg parou de atualizar em 07-17,
# e a regra C de Get-EvolutionProposals (calibragem automatica do
# tori_confluence_threshold, ja escrita e testada desde 07-17) nunca teve
# evidencia real pra agir -- ficava sempre com n=0. Fix: forcar uma unica
# vez aqui no topo do arquivo, antes de QUALQUER chamada de persistencia.
$env:STATE_STORE_SCHEMA = "manuheadfund"

# 2026-07-02 FIX: Auto-loader para NÃO perder libs novamente
. (Join-Path $PSScriptRoot "lib_loader_auto.ps1")

. (Join-Path $PSScriptRoot "lib_coinex.ps1")
. (Join-Path $PSScriptRoot "lib_journal.ps1")
. (Join-Path $PSScriptRoot "lib_telegram.ps1")
. (Join-Path $PSScriptRoot "lib_gem_safety.ps1")
. (Join-Path $PSScriptRoot "lib_btc_regime_gate.ps1")  # 2026-06-24: BTC-core gate (bloqueia LONG alt em bear)
. (Join-Path $PSScriptRoot "lib_market_scenario.ps1")  # 2026-06-24: motor de cenario (capitulacao/bear/bull -> estrategia)
# 2026-07-15 GATES PARALELAS: altcoin breadth + pump classifier + entry timing (3-camada decisao)
$__gate1Path = Join-Path $PSScriptRoot "lib_breadth_monitor.ps1"
if (Test-Path $__gate1Path) { . $__gate1Path }
$__gate3Path = Join-Path $PSScriptRoot "lib_pump_dump_classifier.ps1"
if (Test-Path $__gate3Path) { . $__gate3Path }
$__gate2Path = Join-Path $PSScriptRoot "lib_entry_timing_15m.ps1"
if (Test-Path $__gate2Path) { . $__gate2Path }
$__entryDirPath = Join-Path $PSScriptRoot "lib_entry_direction.ps1"
if (Test-Path $__entryDirPath) { . $__entryDirPath }  # 2026-07-22: cerebro bidirecional -- ver secao [DIRECTION] abaixo
. (Join-Path $PSScriptRoot "lib_regime_surf_executor.ps1")  # 2026-06-30: surf SHORT no bear (shadow-first)
. (Join-Path $PSScriptRoot "lib_market_router.ps1")
# 2026-06-08: Multi-TF alignment validation before execution
. (Join-Path $PSScriptRoot "lib_multiframe_analysis.ps1")
. (Join-Path $PSScriptRoot "lib_candle_fetcher.ps1")
# 2026-06-21: gate fail-closed de qualidade de entrada (direcao + entrada cega)
. (Join-Path $PSScriptRoot "lib_entry_quality_gate.ps1")
# 2026-06-09: Direction learning (counterfactual: learn from rejections)
. (Join-Path $PSScriptRoot "lib_direction_learning.ps1")
. (Join-Path $PSScriptRoot "lib_position_protection.ps1")  # 2026-07-02 FIX: SL+TP placement CRÍTICO
# 2026-06-17: Triagem agent (aplica aprendizado a conviction scores)
. (Join-Path $PSScriptRoot "triagem_agent.ps1")
# 2026-07-08: Trailing stop learning logger (enrich logs para auto-aprendizado)
$__trailingLoggerPath = Join-Path $PSScriptRoot "lib_trailing_learning_logger.ps1"
if (Test-Path $__trailingLoggerPath) { . $__trailingLoggerPath }
# 2026-07-08: Essential alerts only (remove spam, critical only)
$__essentialAlertsPath = Join-Path $PSScriptRoot "lib_telegram_essential_alerts.ps1"
if (Test-Path $__essentialAlertsPath) { . $__essentialAlertsPath }
# 2026-07-09: Mentor Supabase enrichment (decision grades + counterfactual) + Signal Booster
$__enrichmentPath = Join-Path $PSScriptRoot "lib_mentor_supabase_enrichment.ps1"
if (Test-Path $__enrichmentPath) { . $__enrichmentPath }
$__boosterPath = Join-Path $PSScriptRoot "lib_signal_booster_llm.ps1"
if (Test-Path $__boosterPath) { . $__boosterPath }
# 2026-07-24: Mentor LLM shadow mode (Fase 0 do plano de integracao) -- so
# carrega orchestrator_v6.ps1 (Triagem+Mesa+Mentor via Invoke-V6Cascade) para
# LOGAR a opiniao do LLM, nunca para influenciar a execucao real. Ver
# Invoke-MentorShadowObservation abaixo e lib_mentor_shadow.ps1.
$__mentorShadowPath = Join-Path $PSScriptRoot "lib_mentor_shadow.ps1"
if (Test-Path $__mentorShadowPath) { . $__mentorShadowPath }
# 2026-07-24: Mentor LLM com poder REAL de destravar gates de qualidade/sinal
# (ver docs/DESIGN_MENTOR_LLM_OVERRIDE_2026_07_24.md). Gated por
# journal/MENTOR_OVERRIDE_ENABLED.flag -- ausencia = no-op total, gates
# continuam bloqueando exatamente como hoje. Test-MentorOverride NUNCA e'
# chamada pelos gates de SEGURANCA/INFRAESTRUTURA nem CALCULO/VALIDACAO
# (whitelist interna, defesa em profundidade).
$__mentorLivePath = Join-Path $PSScriptRoot "lib_mentor_live.ps1"
if (Test-Path $__mentorLivePath) { . $__mentorLivePath }
# 2026-05-21: B9 cache TTL (Add-GemRejection + Test-GemRecentlyRejected).
# Bug encontrado: scan_master dot-sourced gem_executor mas NAO lib_gem_decision_cache,
# entao Get-Command Test-GemRecentlyRejected returnava null silently -> cache check
# nunca firing -> Tori path executando sempre -> custo LLM desperdiçado (PEAQ loop).
$__gemCachePath = Join-Path $PSScriptRoot "lib_gem_decision_cache.ps1"
if (Test-Path $__gemCachePath) { . $__gemCachePath }
# 2026-05-20: Invoke-OrderRouted era codigo morto -- agora wired aqui.
$__orderRoutedPath = Join-Path $PSScriptRoot "lib_order_routed.ps1"
if (Test-Path $__orderRoutedPath) { . $__orderRoutedPath }

# Exit Ladder (Haiku) + Tracker (Agent B). Dot-source defensivo: testes podem
# substituir Get-ExitLadder por mock antes da chamada.
$__ladderPath = Join-Path $PSScriptRoot "lib_exit_ladder.ps1"
if (Test-Path $__ladderPath) { . $__ladderPath }
$__trackerPath = Join-Path $PSScriptRoot "lib_ladder_tracker.ps1"
if (Test-Path $__trackerPath) { . $__trackerPath }

# Carrega tech_agent_ai (provedor de Get-ToriTrendlineSignal) se ainda nao dot-sourced.
# Usa multiplos fallbacks de path pois $PSScriptRoot e vazio em runspace isolado.
if (-not (Get-Command Get-ToriTrendlineSignal -ErrorAction SilentlyContinue)) {
    # Bases de path (algumas podem ser null em runspace/dot-source standalone).
    # Join-Path lanca com base null, entao filtra bases ANTES de compor o path.
    $__invPath = $MyInvocation.MyCommand.Path
    $__toriBases = @(
        $PSScriptRoot,
        $agentsDir,
        $(if ($__invPath) { Split-Path $__invPath -Parent } else { $null })
    ) | Where-Object { $_ }
    $__toriCandidates = @(
        $__toriBases | ForEach-Object { Join-Path $_ "tech_agent_ai.ps1" }
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($__toriCandidates) {
        try   { . $__toriCandidates -ErrorAction Stop }
        catch { Write-Host "[WARN] Falha ao carregar tech_agent_ai.ps1: $($_.Exception.Message)" -ForegroundColor Yellow }
    } else {
        Write-Host "[WARN] tech_agent_ai.ps1 nao encontrado (PSScriptRoot='$PSScriptRoot' agentsDir='$agentsDir')" -ForegroundColor Yellow
    }
}

# 2026-05-21: auto-enqueue FQS para GEMs sem registry (skip se ja registrado/recente).
# Defesa contra gap: gem_executor pode bloquear via Tori ANTES de chamar Mentor,
# entao o enqueue do Mentor nunca dispara. Cobrir aqui.
$__fqsQueuePath = Join-Path $PSScriptRoot "lib_fqs_enrichment_queue.ps1"
if (Test-Path $__fqsQueuePath) { . $__fqsQueuePath }
# 2026-06-15: FQS lazy enrich SINCRONO (in-the-moment) — enqueue e async nao resolvem no ciclo.
# Invoke-FqsLazyEnrich tenta CoinGecko agora (1-3s) para mercados sem registry.
$__fqsLazyPath = Join-Path $PSScriptRoot "lib_fqs_lazy_enrich.ps1"
if (Test-Path $__fqsLazyPath) { . $__fqsLazyPath }
# 2026-08-02: carrega explicito (nao depende mais de Invoke-FqsLazyEnrich rodar
# primeiro na mesma chamada pra popular Get-FundamentalScore via auto-load
# condicional) -- usado no route override LONG-futures.
$__fqLibPath = Join-Path $PSScriptRoot "lib_fundamental_quality.ps1"
if (Test-Path $__fqLibPath) { . $__fqLibPath }
$__longFuturesRoutePath = Join-Path $PSScriptRoot "lib_long_futures_route.ps1"
if (Test-Path $__longFuturesRoutePath) { . $__longFuturesRoutePath }

# 2026-05-23: Position Management - trailing stops automaticos + risk management
$__posManagementPath = Join-Path $PSScriptRoot "lib_coinex_position_management.ps1"
if (Test-Path $__posManagementPath) { . $__posManagementPath }
$__riskManagerPath = Join-Path $PSScriptRoot "lib_position_risk_manager.ps1"
if (Test-Path $__riskManagerPath) { . $__riskManagerPath }

# 2026-06-17: Dynamic sizing based on capital + regime (feedback loop)
$__sizingDynamicsPath = Join-Path $PSScriptRoot "lib_sizing_dynamics.ps1"
if (Test-Path $__sizingDynamicsPath) { . $__sizingDynamicsPath }

# 2026-06-17: Entry Conviction Ensemble (eixos ortogonais; modo observacao por flag)
foreach ($__convDep in @("lib_btc_relative_strength.ps1","lib_entry_conviction_ensemble.ps1")) {
    $__convPath = Join-Path $PSScriptRoot $__convDep
    if (Test-Path $__convPath) { . $__convPath }
}

# 2026-07-07 ATIVAÇÃO: Learning + Evolution Motors
# 2026-07-29: lib_regime_rr_calibration depende de _Get-LearningFromSupabase
# (lib_direction_learning.ps1) -- carregada por ULTIMO nesta lista.
# 2026-07-29: lib_gem_position_events -- fonte real (Supabase) pro guard de
# cascata de Add Position (ver comentario completo no arquivo).
foreach ($__learnDep in @("lib_learning_engine.ps1","lib_evolution_engine.ps1","lib_direction_learning.ps1","lib_regime_rr_calibration.ps1","lib_gem_position_events.ps1")) {
    $__learnPath = Join-Path $PSScriptRoot $__learnDep
    if (Test-Path $__learnPath) { . $__learnPath }
}

# 2026-07-08: TORI TRADES INTEGRATION — confluence gate + analysis layer
# 2026-07-09: Libs ja foram carregadas por gem_loop caller. Nao recarregar aqui.
# Se funcoes não estão disponíveis, erro ocorrerá quando chamadas (fail-closed via try/catch).

# 2026-06-18: Wire gates_drift.json — dynamic gate application (mesa score override + conviction threshold)
$__gatesDriftPath = Join-Path $PSScriptRoot "lib_gates_drift_wire.ps1"
if (Test-Path $__gatesDriftPath) { . $__gatesDriftPath }

# 2026-06-18: TDD rebuild — all critical libs
foreach ($__tddLib in @("lib_sizing_centralized.ps1","lib_leverage_cap.ps1","lib_tori_simplified.ps1","lib_fqs_default_quality.ps1","lib_entry_conviction_ensemble.ps1")) {
    $__tddPath = Join-Path $PSScriptRoot $__tddLib
    if (Test-Path $__tddPath) {
        try { . $__tddPath }
        catch { Write-Host "[WARN] Failed to load ${__tddLib}: $_" -ForegroundColor Yellow }
    }
}

# 2026-06-18: Chart patterns as ACTIVE BLOCKER (reject pump-chase, topping, fake breakouts)
$__chartGatePath = Join-Path $PSScriptRoot "lib_chart_gate_active.ps1"
if (Test-Path $__chartGatePath) { . $__chartGatePath }

# 2026-07-08 CRÍTICO FIX: Position sync — sincroniza CoinEx app com tracking.jsonl a cada ciclo
$__posSyncPath = Join-Path $PSScriptRoot "lib_position_sync_realtime.ps1"
if (Test-Path $__posSyncPath) {
    try { . $__posSyncPath }
    catch { Write-Host "[WARN] Failed to load position sync: $_" -ForegroundColor Yellow }
}

# 2026-05-29: Order validation (retry+fallback SL/TP) + Position protection (garante TP/SL reais).
# Causa raiz corrigida: SL/TP embutido em ordem MARKET nao aplica confiavel na CoinEx V2.
# Solucao: aplicar SL/TP via set-position-* APOS fill + validar + retry.
$__orderValidationPath = Join-Path $PSScriptRoot "lib_order_validation.ps1"
if (Test-Path $__orderValidationPath) { . $__orderValidationPath }
$__posProtectionPath = Join-Path $PSScriptRoot "lib_position_protection.ps1"
if (Test-Path $__posProtectionPath) { . $__posProtectionPath }

# 2026-05-29: Analise de mercado automatica (nossa "AI Analysis" interna,
# multi-timeframe 1h/4h/1d). Enviada no alerta de abertura de trade.
foreach ($__amaDep in @("lib_chart_patterns.ps1","lib_trailing_stop_intelligent.ps1","lib_auto_market_analysis.ps1")) {
    $__amaPath = Join-Path $PSScriptRoot $__amaDep
    if (Test-Path $__amaPath) { . $__amaPath }
}

# ─────────────────────────────────────────────────────────────────────────────
# CoinEx-HasFuturesMarket
# Verifica se o par existe no mercado de futuros da CoinEx
# ─────────────────────────────────────────────────────────────────────────────
function CoinEx-HasFuturesMarket {
    param([string]$Market)
    try {
        $r = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/futures/market?market=$Market" -Method GET -ErrorAction Stop
        return ($r.code -eq 0 -and $r.data -and $r.data.Count -gt 0)
    } catch { return $false }
}

# NOTA: CoinEx-PlaceSpotOrder e CoinEx-PlaceSpotStopOrder vivem em lib_coinex.ps1
# (movidos para corrigir bug code 3639 "Invalid Parameter" -- exige campo ccy).

# -----------------------------------------------------------------------------
# Calculate-StopTarget
# Funcao pura de calculo stop/target. Resolve bug 2026-05-14 (AIUSDT sub-dollar):
#   - Usa [decimal] para preservar precisao em pares < $1
#   - Serializa com InvariantCulture (evita virgula PT-BR corromper CSV/JSON/API)
#   - Valida invariantes geometricos (target>entry>stop em LONG)
#   - Valida entradas (entry>0, pct em range valido)
#
# Retorna: PSCustomObject { stop_price; target_price; stop_price_str; target_price_str;
#                          stop_pct_actual; target_pct_actual; rr_ratio }
# Lanca excecao em entradas invalidas (fail-fast antes de PlaceOrder).
# -----------------------------------------------------------------------------
function Calculate-StopTarget {
    param(
        [Parameter(Mandatory)] [double] $Entry,
        [Parameter(Mandatory)] [double] $StopPct,
        [Parameter(Mandatory)] [double] $TargetPct,
        [Parameter(Mandatory)] [string] $Direction,   # "LONG" | "SHORT"
        [int] $Precision = 8,
        [double] $MaxDeviationPct = 0.05              # 5% desvio max entre pct config e pct calculado
    )

    # 1. Validacoes de entrada (fail-fast)
    if ($Entry -le 0) {
        throw "Calculate-StopTarget: Entry deve ser > 0 (recebido $Entry)"
    }
    if ($StopPct -le 0 -or $StopPct -ge 1) {
        throw "Calculate-StopTarget: StopPct deve estar em (0,1) (recebido $StopPct -- esperado fracao tipo 0.50 para -50%)"
    }
    if ($TargetPct -le 0) {
        throw "Calculate-StopTarget: TargetPct deve ser > 0 em LONG (recebido $TargetPct)"
    }
    if ($Direction -notin @("LONG","SHORT")) {
        throw "Calculate-StopTarget: Direction deve ser LONG ou SHORT (recebido '$Direction')"
    }

    # 2. Calculo em [decimal] (precisao exata em sub-dollar)
    $entryD  = [decimal]$Entry
    $stopD   = [decimal]$StopPct
    $tgtD    = [decimal]$TargetPct
    $oneD    = [decimal]1

    if ($Direction -eq "LONG") {
        $stopPriceD   = [math]::Round($entryD * ($oneD - $stopD), $Precision)
        $targetPriceD = [math]::Round($entryD * ($oneD + $tgtD),  $Precision)
    } else {
        # SHORT: stop acima, target abaixo
        $stopPriceD   = [math]::Round($entryD * ($oneD + $stopD), $Precision)
        $targetPriceD = [math]::Round($entryD * ($oneD - $tgtD),  $Precision)
    }

    $stopPrice   = [double]$stopPriceD
    $targetPrice = [double]$targetPriceD

    # 3. Invariantes geometricos (defensive double-check)
    if ($Direction -eq "LONG") {
        if ($stopPrice -ge $Entry) {
            throw "Calculate-StopTarget: LONG stop ($stopPrice) >= entry ($Entry) -- INVERTIDO. Abortando."
        }
        if ($targetPrice -le $Entry) {
            throw "Calculate-StopTarget: LONG target ($targetPrice) <= entry ($Entry) -- INVERTIDO. Abortando."
        }
        if ($targetPrice -le $stopPrice) {
            throw "Calculate-StopTarget: LONG target ($targetPrice) <= stop ($stopPrice) -- R:R invalido."
        }
    } else {
        if ($stopPrice -le $Entry)   { throw "Calculate-StopTarget: SHORT stop ($stopPrice) <= entry -- INVERTIDO." }
        if ($targetPrice -ge $Entry) { throw "Calculate-StopTarget: SHORT target ($targetPrice) >= entry -- INVERTIDO." }
    }

    # 4. Desvio efetivo vs configurado (detecta corrupcao de tipos -- ex: string ',' decimal)
    $stopPctActual   = [math]::Abs(($Entry - $stopPrice) / $Entry)
    $targetPctActual = [math]::Abs(($targetPrice - $Entry) / $Entry)
    $stopDeviation   = [math]::Abs($stopPctActual   - $StopPct)
    $targetDeviation = [math]::Abs($targetPctActual - $TargetPct)
    if ($stopDeviation -gt $MaxDeviationPct) {
        throw "Calculate-StopTarget: stop_pct desvio $stopDeviation (configurado=$StopPct, real=$stopPctActual) > max $MaxDeviationPct. Possivel corrupcao."
    }
    if ($targetDeviation -gt ($MaxDeviationPct * $TargetPct + $MaxDeviationPct)) {
        # tolerancia maior em target (escala 2.00 = 200%)
        throw "Calculate-StopTarget: target_pct desvio $targetDeviation (configurado=$TargetPct, real=$targetPctActual) > tolerancia. Possivel corrupcao."
    }

    # 5. Serializacao com InvariantCulture (evita virgula PT-BR corromper API/CSV)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $stopStr   = $stopPrice.ToString($inv)
    $targetStr = $targetPrice.ToString($inv)

    $rrRatio = if ($stopPctActual -gt 0) {
        [math]::Round($targetPctActual / $stopPctActual, 2)
    } else { 0 }

    return [PSCustomObject]@{
        stop_price        = $stopPrice
        target_price      = $targetPrice
        stop_price_str    = $stopStr
        target_price_str  = $targetStr
        stop_pct_actual   = [math]::Round($stopPctActual, 6)
        target_pct_actual = [math]::Round($targetPctActual, 6)
        rr_ratio          = $rrRatio
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-LadderTemplateForSetup
# Decide qual template de exit ladder usar baseado em contexto do setup.
#
# Politica:
#  - GEM FUTURES + spike BULLISH       -> gem_runner (recupera capital + runner)
#  - GEM (qualquer)  + score < 70       -> tori     (conservador, 3 TPs progressivos)
#  - GEM (demais)                       -> tori     (default seguro)
#  - STANDARD regime=BULL_STRONG        -> bull_strong_conservative (RR 1:2 + 1:5)
#  - STANDARD regime=TRANSITION_UP (+Mon)-> melao_kelly (Kelly fracionario 4 TPs)
#  - STANDARD outro                      -> tori (fallback seguro)
#
# Retorna string template_id (validado contra ValidateSet do Get-ExitLadder).
# ─────────────────────────────────────────────────────────────────────────────
function Get-LadderTemplateForSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Setup,
        [string] $Regime  = "",
        [bool]   $GemMode = $false,
        [string] $DayOfWeek = ""    # opcional ("Monday"...) p/ TRANSITION_UP rule
    )

    $score      = if ($Setup.PSObject.Properties['score']) { [int]$Setup.score } else { 0 }
    $marketType = if ($Setup.PSObject.Properties['market_type']) { [string]$Setup.market_type } else { "" }
    $spike      = ""
    if ($Setup.PSObject.Properties['vol_data'] -and $Setup.vol_data) {
        if ($Setup.vol_data.PSObject.Properties['spike_type']) {
            $spike = [string]$Setup.vol_data.spike_type
        }
    }

    if ($GemMode) {
        if ($marketType -eq "FUTURES" -and $spike -eq "BULLISH" -and $score -ge 70) {
            return "gem_runner"
        }
        if ($score -lt 70) {
            return "tori"
        }
        return "tori"
    }

    $reg = $Regime.ToUpper()
    if ($reg -eq "BULL_STRONG") {
        return "bull_strong_conservative"
    }
    if ($reg -eq "TRANSITION_UP") {
        return "melao_kelly"
    }
    return "tori"
}

# ─────────────────────────────────────────────────────────────────────────────
# Invoke-GemExecute
# Pipeline: valida gem -> detecta mercado -> sizing -> executa -> stop loss
#
# Uso:
#   Invoke-GemExecute -Gem $gem -DryRun    # simula sem enviar ordem
#   Invoke-GemExecute -Gem $gem            # executa com capital real
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-GemExecute {
    param(
        [Parameter(Mandatory)] [object] $Gem,
        [switch] $DryRun
    )

    $mkt = $Gem.market
    $sizing_pct = if ($Gem.sizing_pct -and $Gem.sizing_pct -gt 0) { $Gem.sizing_pct } else {
        # Fallback: se gem_agent não preencheu, calcular default (3% de capital = agressivo)
        if ($global:GEM_CAPITAL_MOMENTUM) { $global:GEM_CAPITAL_MOMENTUM } else { 0.03 }
    }
    $vd  = $Gem.vol_data

    # 2026-07-14 fix (rodada 1, REVERTIDA): tentei $global:CURRENT_REGIME <-
    # journal/regime_state.json como fallback. NAO funcionou na nuvem: esse
    # arquivo e gitignored (journal/*state.json), nunca existe no runner
    # efemero (checkout limpo por job). Investigado mais fundo: NENHUMA fonte
    # de regime sobrevive no runner cloud hoje -- MARKET_REGIME.flag tambem
    # gitignored, e a tabela Supabase public.regime_state e escrita com
    # 'market' ausente (NOT NULL UNIQUE -> insert sempre falha) e phase="BULL"
    # hardcoded (nao reflete BEAR_WEAK real). $global:CURRENT_REGIME
    # literalmente nunca e atribuido em nenhum arquivo de producao (so em
    # teste). Corrigir essa infra e trabalho separado (Supabase regime_state
    # com escrita real, fora do escopo deste fix pontual).
    #
    # RODADA 2 (esta): em vez de depender de uma fonte de regime externa
    # quebrada, uso o dado que Get-MarketScenario JA calcula ao vivo nesta
    # mesma chamada (momentum_30d do BTC, sempre fresco, zero infra externa).
    # bear real = momentum negativo -- mesmo sinal que Resolve-MarketScenario
    # usa internamente pra decidir BEAR vs NEUTRO, so exposto agora no retorno.

    Write-Host ""
    Write-Host "=== GEM EXECUTOR -- $mkt ===" -ForegroundColor Cyan

    # 2026-06-15: FQS lazy enrich SINCRONO — tenta CoinGecko NOW (1-3s) pra mercados sem registry.
    # Rate-limit aware (CoinGecko 10/min), fallback gracioso. Ciclo nao bloqueia.
    if (Get-Command Invoke-FqsLazyEnrich -ErrorAction SilentlyContinue) {
        try {
            $fqsResult = Invoke-FqsLazyEnrich -Market $mkt -TimeoutSec 5
            if ($fqsResult.success) {
                Write-Host "  [FQS] LAZY ENRICH OK: $mkt → category=$($fqsResult.new_fqs_category)" -ForegroundColor Green
            }
        } catch {
            # Fail-gracious: lazy enrich timeout ou erro nao bloqueia gem pipeline
        }
    }

    # 2026-05-21: auto-enqueue FQS antes de qualquer block. Garante que GEMs novos
    # (ARRR/PROVE patterns) eventualmente recebem entry no registry mesmo bloqueados.
    if (Get-Command Add-FqsEnrichmentRequest -ErrorAction SilentlyContinue) {
        try { [void](Add-FqsEnrichmentRequest -Market $mkt -Source "gem_executor") } catch {}
    }

    # B9 fix 2026-05-20 PM6+: TTL cache pra evitar re-veto loop.
    # DASH rejeitado 5x hoje com mesmo MCE_BLOCK 0.1823 -> ~$0.03 desperdicio LLM.
    # Skip silencioso se mesma (market, score-block) <60min.
    if (Get-Command Test-GemRecentlyRejected -ErrorAction SilentlyContinue) {
        $cachePath = Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json"
        $skipReason = "score=$($Gem.score) mode=$($Gem.mode)"
        # 2026-07-09 FIX: chave do cache ganha DIRECAO quando o gem traz direcao
        # explicita (TORI_SHORT/TRIGGER). Antes: rejeicao do ARB LONG (DISCOVERY,
        # tori 65<80) matava o ARB SHORT (tori 100) no mesmo ciclo — o melhor
        # candidato nunca era avaliado. Rejeicoes de gems sem direcao continuam
        # gravadas/lidas com market puro (comportamento original).
        $cacheMkt = $mkt
        $__gemDirCache = "$($Gem.direction)".ToUpper()
        if ($__gemDirCache -in @("LONG","SHORT")) { $cacheMkt = "$mkt|$__gemDirCache" }
        # 2026-06-17: bypass tori_skip/wait com CONVICTION_GATE on (deixa re-chegar ao gate)
        $__cacheBypass = @()
        if (Test-Path (Join-Path $global:JOURNAL_DIR "CONVICTION_GATE.flag")) { $__cacheBypass = @("tori_skip","tori_wait") }
        if (Test-GemRecentlyRejected -Path $cachePath -Market $cacheMkt -Reason $skipReason -TtlMinutes 60 -BypassReasons $__cacheBypass) {
            Write-Host "SKIP CACHE: $cacheMkt mesma condicao <60min (poupanca LLM)" -ForegroundColor DarkGray
            return [PSCustomObject]@{ blocked = $true; blocked_by = @("recent_decision_cache"); cache_hit = $true }
        }
    }

    # ── CIRCUIT BREAKER: -2% daily loss pause ──────────────────────────────────
    # 2026-06-09: bloqueia trades se PnL < -2% do capital hoje
    # 2026-07-27 FIX (achado real: 11/11 candidatos bloqueados hoje por PnL de
    # so -$7.75, incluindo XRPUSDT com FQS QUALITY): $global:CAPITAL_TOTAL
    # NUNCA e setado neste caminho de execucao ($CAPITAL_TOTAL existe so em
    # escopo de SCRIPT em config.ps1, sem $global: -- so gem_agent.ps1, nunca
    # chamado por producao real, seta a versao global). PowerShell coage o
    # $null resultante pra 0 no parametro [double]$Capital -- o default de
    # 3645.0 NUNCA e usado pq o parametro foi passado explicitamente (ainda
    # que vazio). threshold = 0 * -0.02 = 0, entao QUALQUER pnl negativo
    # (mesmo centavos) travava o dia inteiro. Fix: usa o capital REAL da
    # conta (Get-ExecutableCapitalUSDT, mesmo cache de 30min ja usado mais
    # adiante nesta funcao pro sizing real).
    if (Get-Command Test-CircuitBreakerTriggered -ErrorAction SilentlyContinue) {
        $__cbCapital = if (Get-Command Get-ExecutableCapitalUSDT -ErrorAction SilentlyContinue) {
            (Get-ExecutableCapitalUSDT -MarketType "FUTURES" -MarginMode "cross").capital
        } else { 0 }
        if ($__cbCapital -le 0) { $__cbCapital = 3645.0 }
        if (Test-CircuitBreakerTriggered -Capital $__cbCapital -DailyLossThreshold -0.02) {
            Write-Host "CIRCUIT BREAKER ATIVADO: -2% daily loss (capital=$__cbCapital). Nenhum trade hoje." -ForegroundColor Red
            try { Send-TelegramAlert -Message "🚨 **CIRCUIT BREAKER ATIVADO** — Perdemos -2% do capital hoje. Sistema pausado." | Out-Null } catch {}
            return [PSCustomObject]@{ blocked = $true; blocked_by = @("circuit_breaker_daily_loss"); market = $mkt }
        }
    }

    # ── Validacoes ────────────────────────────────────────────────────────────
    $scoreMin = if ($Gem.mode -eq "DISCOVERY") { $global:GEM_SCORE_MIN_DISC } else { $global:GEM_SCORE_MIN_MOM }
    if ($Gem.score -lt $scoreMin) {
        Write-Host "BLOQUEADO: score $($Gem.score) abaixo do minimo $scoreMin" -ForegroundColor Red
        # 2026-06-09: Captura skip pra counterfactual
        if (Get-Command Write-SignalSkip -ErrorAction SilentlyContinue) {
            $regime = if ($global:MARKET_REGIME) { "$($global:MARKET_REGIME)" } else { "UNKNOWN" }
            try { Write-SignalSkip -Market $mkt -Direction "LONG" -Gate "score_below_$scoreMin" -EntryPrice $price -Regime $regime -Source "gem_score" | Out-Null } catch {}
        }
        # Add to cache pra evitar re-veto
        if (Get-Command Add-GemRejection -ErrorAction SilentlyContinue) {
            try { Add-GemRejection -Path (Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json") -Market $mkt -Reason "score_below_min $($Gem.score)" } catch {}
        }
        # B fix 2026-05-21: retornar PSCustomObject blocked com reason explicit pra caller
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("score_below_min_$($Gem.score)_lt_$scoreMin"); market = $mkt }
    }

    # ── 2026-07-15: PARALLEL GATES (Breadth + Pump + Timing) ────────────────────
    # Gate #1: Breadth Monitor (destranca altcoins em BTC chop)
    # Gate #3: Pump-Dump Classifier (bloqueia pump near peak, permite SHORT)
    # Gate #2: Entry Timing 15M (timing via RSI em daily confirmado)
    $direction = if ($Gem.direction) { [string]$Gem.direction.ToUpper() } else { "LONG" }

    # Get BTC scenario
    $btcScenario = Get-MarketScenario

    # Gate #1: Breadth check
    # 2026-07-16: passa Market+Change24h pra Test-ParallelBreadthGate poder
    # liberar por sinal individual forte (confirmado em 1h+4h) quando o
    # mercado geral esta neutro -- ver lib_breadth_monitor.ps1 pra contexto
    # completo (achado real via gate_replay_study: ARGUSDT +51%/24h
    # bloqueado so pq breadth do mercado geral estava ~50%).
    $gemChange24h = if ($null -ne $Gem.change_24h) { [double]$Gem.change_24h } else { 0 }
    $breadthGate = if (Get-Command Test-ParallelBreadthGate -ErrorAction SilentlyContinue) {
        try {
            Test-ParallelBreadthGate -BtcScenario $btcScenario.scenario -BtcAllowLong $btcScenario.allow_long -BtcAllowShort $btcScenario.allow_short -Market $mkt -Change24h $gemChange24h
        } catch {
            @{ allow_long = $btcScenario.allow_long; allow_short = $btcScenario.allow_short; breadth_trend = "error" }
        }
    } else {
        @{ allow_long = $btcScenario.allow_long; allow_short = $btcScenario.allow_short; breadth_trend = "unknown" }
    }

    # Gate #3: Pump-Dump classifier
    $metadata = @{ mcap = if ($Gem.mcap) { [double]$Gem.mcap } else { 50000000 }; listing_date_days = if ($Gem.days_listed) { [int]$Gem.days_listed } else { 100 } }
    $pumpGate = if (Get-Command Test-PumpDumpGate -ErrorAction SilentlyContinue) {
        try {
            Test-PumpDumpGate -Market $mkt -Metadata $metadata
        } catch {
            @{ allow_long = $true; allow_short = $false; pump_class = "error"; reason = "pump_classifier_error" }
        }
    } else {
        @{ allow_long = $true; allow_short = $false; pump_class = "unknown"; reason = "pump_classifier_missing" }
    }

    # 2026-07-16 FIX: classificador de pump foi calibrado so pra gemas
    # pump-and-dump (mcap<$100M, preco<$0.01, queda>30%) -- majors/blue-chips
    # (ARBUSDT, AVAXUSDT) raramente pontuam essas features mesmo em reversao
    # tecnica real, caindo em "natural_uptrend" por eliminacao (bloqueia SHORT
    # sempre). O sweep TORI_SHORT ja carrega o confluence real em $Gem.score.
    #
    # 2026-07-16 REFINAMENTO (pos-validacao com gate_replay_study, ~9h/17
    # pares unicos): confluence alto sozinho NAO basta -- caso real ARBUSDT
    # (confluence=100 persistente por horas: RSI_EXTREME 71-78 overbought +
    # FRACTAL_BEARISH + CHOCH + VOLUME_PROFILE) teve preco LATERAL de fato
    # (0.088-0.090 por 10h), SHORT teria dado leve prejuizo (-1.3% medido).
    # Investigado a fundo: ARB tinha retracement real (-13% em 7d, ja
    # comecado ha DIAS), mas nas ultimas horas o momentum tinha revertido
    # pra CIMA (mom1h=+0.46%, mom4h=-0.60% -- nao confirmava queda ativa) --
    # o sinal tecnico era real mas o movimento ja tinha "gasto" a maior
    # parte do trajeto antes do confluence aparecer. dist_from_peak sozinho
    # (retracement HISTORICO) nao capturava isso -- so olha se JA caiu, nao
    # se AINDA esta caindo. Fix: reusa Test-RecentMomentumConfirmed (mesma
    # funcao criada hoje pro breadth gate) -- exige momentum de 1h E 4h
    # confirmando queda ATIVA agora, nao so historico de dias.
    $toriConfluenceExtreme = ($Gem.mode -match "TORI_SHORT") -and ($null -ne $Gem.score) -and ([int]$Gem.score -ge 90)
    $toriConfluenceStrong = ($Gem.mode -match "TORI_SHORT") -and ($null -ne $Gem.score) -and ([int]$Gem.score -ge 85)
    $hasActiveMomentum = $false
    if ($toriConfluenceStrong -and (Get-Command Test-RecentMomentumConfirmed -ErrorAction SilentlyContinue)) {
        try { $hasActiveMomentum = Test-RecentMomentumConfirmed -Market $mkt -Direction "lt" } catch { $hasActiveMomentum = $false }
    }
    if (-not $pumpGate.allow_short -and $toriConfluenceExtreme -and $hasActiveMomentum) {
        $origReason = $pumpGate.reason
        $pumpGate = [PSCustomObject]@{
            allow_long          = $pumpGate.allow_long
            allow_short         = $true
            pump_class          = $pumpGate.pump_class
            pump_score          = $pumpGate.pump_score
            pump_confidence     = $pumpGate.pump_confidence
            dist_from_peak_pct  = $pumpGate.dist_from_peak_pct
            vol_ratio           = $pumpGate.vol_ratio
            reason              = "tori_confluence_override_$($Gem.score)_momentum_ativo (era: $origReason)"
            source              = $pumpGate.source
        }
        Write-Host "  [PUMP GATE OVERRIDE] ${mkt}: Tori confluence=$($Gem.score) >=90 + momentum 1h/4h confirmando queda ativa -> libera SHORT apesar de pump_class=$($pumpGate.pump_class)" -ForegroundColor DarkYellow
    }

    # 2026-08-20: BREADTH GATE OVERRIDE (SHORT FORTE EM BULL)
    # Achado: breadth gate bloqueia SHORT 100% em regime BULL/NEUTRO mesmo
    # quando candidato tem sinal TORI muito forte (>=85) + momentum ativo
    # confirmado. Padrao ja existe pro pump gate (acima, tori>=90), estendendo
    # pra breadth gate com limiar ligeiramente menor (>=85, vs 90) porque
    # breadth e mais conservadora que pump. Mesmo raciocinio: sinais TORI forte
    # em SHORT justificam override de mercado macro. Regra: breadth nega SHORT
    # se scenario=BULL (allow_short=false) e breadth nao esta bearish.
    if (-not $breadthGate.allow_short -and $toriConfluenceStrong -and $hasActiveMomentum) {
        $origReason = $breadthGate.reason
        $breadthGate = [PSCustomObject]@{
            allow_long = $breadthGate.allow_long
            allow_short = $true
            breadth_trend = $breadthGate.breadth_trend
            breadth_pct = $breadthGate.breadth_pct
            breadth_confidence = $breadthGate.breadth_confidence
            breadth_vol_ratio = $breadthGate.breadth_vol_ratio
            breadth_green = $breadthGate.breadth_green
            breadth_total = $breadthGate.breadth_total
            btc_scenario = $breadthGate.btc_scenario
            btc_allow_long = $breadthGate.btc_allow_long
            btc_allow_short = $breadthGate.btc_allow_short
            strong_individual_move = $breadthGate.strong_individual_move
            change_24h = $breadthGate.change_24h
            source = "breadth_gate_override"
            reason = "tori_confluence_override_$($Gem.score)_momentum_ativo (era: $origReason)"
        }
        Write-Host "  [BREADTH GATE OVERRIDE] ${mkt}: Tori confluence=$($Gem.score) >=85 + momentum 1h/4h confirmando queda ativa -> libera SHORT apesar de breadth=neutral" -ForegroundColor DarkYellow
    }

    # Gate #2: Entry timing (RSI 15M)
    # 2026-07-15 FIX (achado P6, auditoria agent a8499866): condicao original
    # misturava -ErrorAction (parametro nomeado de Get-Command) com -and na
    # mesma expressao sem parenteses -- funcionava "por acidente" no parser
    # PS mas era fragil/dificil de auditar. Parenteses explicitos agora.
    $hasEntryTimingFn = [bool](Get-Command Test-EntryTimingGate -ErrorAction SilentlyContinue)
    $hasTrendlineScore = ($null -ne $Gem.trendline_score) -and ([double]$Gem.trendline_score -ge 70)

    $entryTiming = if ($hasEntryTimingFn -and $hasTrendlineScore) {
        try {
            Test-EntryTimingGate -Market $mkt -DailyTrendlineScore ([double]$Gem.trendline_score) -ToriScore ([int]$Gem.score)
        } catch {
            # 2026-07-15 FIX (achado P7): excecao era descartada sem log --
            # impossivel diagnosticar de fora por que o gate falhava.
            Write-Host "  [ENTRY TIMING ERROR] ${mkt}: $($_.Exception.Message)" -ForegroundColor Red
            @{ signal = "error"; confidence = 0; effective_tori_score = [int]$Gem.score; passes_gate = $true; reason = "entry_timing_error: $($_.Exception.Message)" }
        }
    } else {
        $skipReason = if (-not $hasEntryTimingFn) { "function_not_loaded" } else { "trendline_weak_or_missing" }
        @{ signal = "unknown"; confidence = 0; effective_tori_score = [int]$Gem.score; passes_gate = $true; reason = $skipReason }
    }

    # Aplicar gates conforme direcao
    $gatesBlocked = @()
    if ($direction -eq "LONG") {
        if (-not $breadthGate.allow_long) { $gatesBlocked += "breadth_long_blocked" }
        if (-not $pumpGate.allow_long) { $gatesBlocked += "pump_long_blocked" }
        if ($entryTiming.signal -eq "skip") { $gatesBlocked += "entry_timing_skip" }
    } elseif ($direction -eq "SHORT") {
        if (-not $breadthGate.allow_short) { $gatesBlocked += "breadth_short_blocked" }
        if (-not $pumpGate.allow_short) { $gatesBlocked += "pump_short_blocked" }
    }

    if ($gatesBlocked.Count -gt 0) {
        Write-Host "BLOQUEADO GATES: $($gatesBlocked -join ', ') | Breadth=$($breadthGate.breadth_trend) Pump=$($pumpGate.pump_class) Entry=$($entryTiming.signal)" -ForegroundColor Yellow

        # 2026-07-16: registra skip pra counterfactual (Write-SignalSkip ja
        # tenta Supabase trade_rejections primeiro, fallback local so se
        # Supabase falhar -- usuario perguntou se vale estudar sinais
        # pulados, mas o gate de breadth/pump (que mais bloqueia hoje) nunca
        # registrava nada aqui, so score/tori/quality_gate registravam.
        # Preco buscado de forma leve/tolerante -- nao trava o fluxo se falhar.
        if (Get-Command Write-SignalSkip -ErrorAction SilentlyContinue) {
            try {
                $skipPrice = 0.0
                try {
                    $skipTicker = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/spot/ticker?market=$mkt" -Method GET -TimeoutSec 5
                    if ($skipTicker.code -eq 0 -and $skipTicker.data) { $skipPrice = [double]$skipTicker.data[0].last }
                } catch { }
                $skipRegime = if ($global:MARKET_REGIME) { "$($global:MARKET_REGIME)" } else { "$($btcScenario.scenario)" }
                Write-SignalSkip -Market $mkt -Direction $direction -Gate ($gatesBlocked -join "+") -EntryPrice $skipPrice -Regime $skipRegime -Source "parallel_gates" | Out-Null
            } catch { }
        }

        # 2026-07-24: gate com maior volume de edge medido no blueprint audit
        # (BEAR|LONG|breadth_long_blocked: n=62, hit_rate 67.7%) -- elegivel
        # pra override do mentor LLM. Ver docs/DESIGN_MENTOR_LLM_OVERRIDE_2026_07_24.md.
        # 2026-07-26 FIX: sem parenteses, "-and $skipPrice -gt 0" era absorvido
        # como parametros extras de Get-Command (nao existem, PowerShell os
        # ignora silenciosamente sem erro) -- o if avaliava SO a existencia da
        # funcao, nunca checava skipPrice>0 de fato. Confirmado com repro
        # isolado: skipPrice=0 + funcao existente entrava no if mesmo assim.
        if ((Get-Command Test-MentorOverride -ErrorAction SilentlyContinue) -and ($skipPrice -gt 0)) {
            $__origDirection = $direction
            $override = Test-MentorOverride -Market $mkt -GateTag ($gatesBlocked -join "+") `
                -GateReason "$($gatesBlocked -join ', ')" -Direction $direction -Price $skipPrice `
                -Change24h $gemChange24h -Regime "$($btcScenario.scenario)"
            if ($override.approved) {
                # 2026-07-28 FIX (achado real: SKYUSDT bloqueado no gate de
                # qualidade por "direction_contradiction_tech_SHORT_vs_trade_
                # LONG" mesmo apos o Mentor aprovar SHORT aqui): Test-MentorOverride
                # roda a cascade completa internamente (Invoke-V6Cascade), e a
                # Mesa dentro dela pode mudar a direcao (breadth_long_blocked
                # so existe p/ LONG -- a UNICA razao do Mentor aprovar esse gate
                # especifico e a Mesa ter achado edge no lado OPOSTO, SHORT).
                #
                # 2026-07-28 FIX ADICIONAL (achado: doc de design 2026-07-24
                # NUNCA disse que aprovar este gate implica converter pra
                # SHORT -- so "destravar" o gate. Assumir cegamente SHORT
                # descartaria o caso legitimo do Mentor aprovar mantendo
                # LONG original -- exatamente o que o dado historico
                # hit_rate=67.7% mede: as vezes o setup individual da moeda
                # justifica LONG mesmo com breadth fraco. Fix real: usa
                # $override.effective_direction (agora exposta por
                # Test-MentorOverride via a Mesa/Mentor da cascade -- fonte
                # estruturada, nao parsing de texto livre do LLM) pra saber
                # se inverte pra SHORT ou mantem LONG.
                if ($__origDirection -eq "LONG" -and ($gatesBlocked -contains "breadth_long_blocked") `
                    -and $override.PSObject.Properties['effective_direction'] -and $override.effective_direction -eq "SHORT") {
                    $direction = "SHORT"
                    Write-Host "  [MENTOR OVERRIDE] $mkt -- $($override.motivo) -- direction=$__origDirection->$direction" -ForegroundColor Magenta
                } else {
                    Write-Host "  [MENTOR OVERRIDE] $mkt -- $($override.motivo)" -ForegroundColor Magenta
                }
            } else {
                return [PSCustomObject]@{ blocked = $true; blocked_by = $gatesBlocked; market = $mkt; gates_info = @{ breadth = $breadthGate; pump = $pumpGate; entry = $entryTiming } }
            }
        } else {
            return [PSCustomObject]@{ blocked = $true; blocked_by = $gatesBlocked; market = $mkt; gates_info = @{ breadth = $breadthGate; pump = $pumpGate; entry = $entryTiming } }
        }
    }

    # Log gates aprovado
    $gatesLog = "GATES APROVADO | Breadth=$($breadthGate.breadth_trend) ($($breadthGate.breadth_pct)%) Pump=$($pumpGate.pump_class) ($($pumpGate.pump_score)) Entry=$($entryTiming.signal) (eff_tori=$($entryTiming.effective_tori_score))"
    Write-Host $gatesLog -ForegroundColor Green

    # ── 2026-06-30: PUMP SCALP EARLY DETECTION ────────────────────────────────────
    # Executa LIVE se pump detectado (confidence >=70). Sem shadow, sempre live.
    if (Get-Command Detect-EarlyPump -ErrorAction SilentlyContinue) {
        if (Get-Command Invoke-PumpScalp -ErrorAction SilentlyContinue) {
            try {
                # 2026-07-02 FIX: operador ?? e PS7-only; em PS 5.1 quebra o PARSE do
                # arquivo INTEIRO -> Invoke-GemExecute nunca existia -> nada entrava.
                # 2026-07-16 FIX: $Gem.vol_data.volume_ratio NUNCA existiu -- o campo
                # real que Get-CoinExVolSpike retorna e "spike_ratio" (confirmado em
                # gem_agent.ps1). Fallback silencioso pra 1.0 travava o confidence de
                # Detect-EarlyPump no teto de 45 (sinais 1+4 nunca somavam, so 2+3),
                # nunca alcancando o >=70 necessario pra disparar -- pump scalp
                # tecnicamente "ligado" (funcao existe, e chamada) mas estruturalmente
                # nunca executava nenhum trade, mesmo com pump real acontecendo.
                $pdChange = if ($null -ne $Gem.change_24h) { $Gem.change_24h } else { 0 }
                $pdVolR   = if ($null -ne $Gem.vol_data.spike_ratio) { $Gem.vol_data.spike_ratio } else { 1.0 }
                $pdRsi    = if ($null -ne $Gem.rsi_14) { $Gem.rsi_14 } else { 50 }
                $pdPrice  = if ($null -ne $Gem.current_price) { $Gem.current_price } else { 0 }
                $pumpDetect = Detect-EarlyPump -Market $mkt -ChangePercent24h $pdChange -VolumeRatio $pdVolR -RSI $pdRsi -CurrentPrice $pdPrice
                if ($pumpDetect.is_pump -and $pumpDetect.confidence -ge 70) {
                    Write-Host "🚀 PUMP SCALP [$mkt] $($pumpDetect.pump_stage) conf=$($pumpDetect.confidence)% | Entry: $($pumpDetect.entry_price) | Target: +5% @ $($pumpDetect.target_price) | Stop: -3% @ $($pumpDetect.stop_price)" -ForegroundColor Yellow
                    $pdCapital = if ($null -ne $global:CAPITAL_TOTAL) { $global:CAPITAL_TOTAL } else { 5500 }
                    $pumpRes = Invoke-PumpScalp -Market $mkt -EntryPrice $pumpDetect.entry_price -TargetPrice $pumpDetect.target_price -StopPrice $pumpDetect.stop_price -RiskUsd ([math]::Min(55, $pdCapital * 0.01)) -TimeoutMinutes 120
                    if ($pumpRes.executed) {
                        Write-Host "  ✓ EXECUTADO: order $($pumpRes.order_id) @ size `$$($pumpRes.size_usd)" -ForegroundColor Green
                    }
                    return [PSCustomObject]@{ blocked = $false; pump_executed = $pumpRes.executed; pump_order_id = $pumpRes.order_id; market = $mkt }
                }
            } catch {
                # Silent fail - continue to normal flow
            }
        }
    }

    if (-not $sizing_pct -or $sizing_pct -le 0) {
        Write-Host "BLOQUEADO: sizing invalido (sizing_pct=$sizing_pct)" -ForegroundColor Red
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("sizing_invalido"); market = $mkt }
    }
    if ($vd.spike_type -eq "BEARISH") {
        Write-Host "BLOQUEADO: spike BEARISH detectado (G1B)" -ForegroundColor Red
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("spike_BEARISH_G1B"); market = $mkt }
    }

    # ── 2026-07-08: REMOVED HUMAN APPROVAL GATE ───────────────────────────────────
    # User requirement: "human approval não deve existir"
    # All trades execute autonomously if score >= threshold, NO Telegram gate
    # (capital sizing validation still applies via risk limits)

    # ── Detectar tipo de mercado ──────────────────────────────────────────────
    # 2026-05-19 PM: usa Get-GemRouteForMarket (consolidado via lib_market_router_wire)
    # GEM prefere spot (sem leverage; risco controlado). Fallback ao pattern antigo.
    # 2026-07-16 FIX (achado real via forced-test-trade ETHUSDT SHORT, run
    # 29444619342): $hasFutures aqui SEMPRE significou "rota ATUAL escolhida
    # e futures" (market_type -eq "FUTURES"), NAO "mercado TEM futures
    # disponivel". Modo GEM prefere spot por padrao mesmo quando ambos
    # existem (Get-RouteForMode, intencional) -- entao pra um par com
    # spot+futures, $hasFutures ficava $false aqui, mesmo com futures real
    # disponivel. Meu guard SHORT-em-SPOT (linha ~1329, commit 8d4566f)
    # herdou esse significado errado e bloqueava SHORT com a mensagem "so
    # tem SPOT disponivel" mesmo quando futures existia de verdade. Fix:
    # variavel separada $futuresAvailable com o significado correto
    # (mercado tem futures, independente da rota escolhida), $hasFutures
    # continua significando "rota atual e futures" (uso extensivo abaixo,
    # nao renomeado pra minimizar blast radius).
    if (Get-Command Get-GemRouteForMarket -ErrorAction SilentlyContinue) {
        $routeInfo = Get-GemRouteForMarket -Market $mkt
        $hasFutures = ($routeInfo.market_type -eq "FUTURES")
        $futuresAvailable = [bool]$routeInfo.futures_available
        $marketType = $routeInfo.market_type
        if ($marketType -eq "NONE") {
            Write-Host "  [Route] $mkt sem rota disponivel (delisted?) -- abortar" -ForegroundColor Red
            return [PSCustomObject]@{ blocked = $true; blocked_by = @("route_NONE_delisted"); market = $mkt }
        }
        Write-Host "  [Route] $mkt -> $($routeInfo.route) (spot=$($routeInfo.spot_available) fut=$($routeInfo.futures_available))" -ForegroundColor DarkCyan
    } else {
        $hasFutures  = CoinEx-HasFuturesMarket $mkt
        $futuresAvailable = $hasFutures
        $marketType  = if ($hasFutures) { "FUTURES" } else { "SPOT" }
    }
    # 2026-05-19 PM: sizing usa TOTAL CoinEx (spot+futures) -- representa portfolio real.
    # Execucao em FUTURES exige margem em futures wallet; gate adicional logo abaixo
    # checa se usd_size <= futures_balance pra evitar margin call.
    # 2026-07-09 FIX cap_exposure: resolver capital via Get-ExecutableCapitalUSDT
    # (lib_capital_context) -- cadeia API fresh -> Supabase/journal cache REAL -> bootstrap.
    # Local sem credenciais passa a usar o capital REAL que a nuvem grava no Supabase,
    # em vez do bootstrap 100+100 que bloqueava tudo com cap_exposure falso.
    # Cross margin: conta inteira e colateral; isolated: so futures wallet.
    # Default isolated (header: "Padrao: FUTURES (isolated margin)"). Cross via $global:GEM_MARGIN_MODE.
    $__marginMode = if ($global:GEM_MARGIN_MODE) { "$global:GEM_MARGIN_MODE" } else { "isolated" }
    if (Get-Command Get-ExecutableCapitalUSDT -ErrorAction SilentlyContinue) {
        $__mt = if ($hasFutures) { "FUTURES" } else { "SPOT" }
        $__cap = Get-ExecutableCapitalUSDT -MarketType $__mt -MarginMode $__marginMode
        $capital = $__cap.capital
        $executionWalletCap = $__cap.wallet_cap
        if ($__cap.source -match "fallback") {
            Write-Host "  [Capital] WARN: bootstrap fallback em uso (sem API nem cache real) -- capital=$capital" -ForegroundColor Yellow
        } else {
            Write-Host "  [Capital] $($__cap.source): total=$capital wallet=$executionWalletCap mode=$__marginMode" -ForegroundColor DarkCyan
        }
    } else {
        $capital     = if (Get-Command CoinEx-GetTotalCapitalUSDT -ErrorAction SilentlyContinue) {
            CoinEx-GetTotalCapitalUSDT
        } elseif ($hasFutures) {
            CoinEx-GetFuturesCapitalUSDT
        } else {
            CoinEx-GetSpotCapitalUSDT
        }
        $executionWalletCap = if ($hasFutures) { CoinEx-GetFuturesCapitalUSDT } else { CoinEx-GetSpotCapitalUSDT }
    }

    # ── Preco atual ───────────────────────────────────────────────────────────
    $tickerEndpoint = if ($hasFutures) { "/v2/futures/ticker?market=$mkt" } else { "/v2/spot/ticker?market=$mkt" }
    $ticker = Invoke-RestMethod -Uri "$COINEX_BASE_URL$tickerEndpoint" -Method GET
    if ($ticker.code -ne 0 -or -not $ticker.data) { throw "Ticker indisponivel para $mkt" }
    $price = [double]$ticker.data[0].last

    # ── Sizing (calculo de usd_size, qty -- precede gates) ───────────────────
    # 2026-06-17: Dynamic sizing via feedback loop (regime-aware allocation + capital-based)
    $usd_size = $null
    $sizingMethod = "legacy"

    # 2026-07-17 FIX (achado #2 do audit, continuacao): dynamic_feedback e o
    # metodo PRIMARIO (roda antes de kelly_adaptive/legacy_pct) mas usava
    # StopLossPct=0.02 CRAVADO em Get-SizePerTrade, ignorando se o trade e
    # DISCOVERY (-50%) ou MOMENTUM (-30%) -- mesma classe de bug do achado #1,
    # so que no caminho que tem prioridade de execucao. Resolve aqui (precisa
    # so de $Gem, nao depende de price/gates) pra reusar no calc abaixo.
    $__stpEarly = if (Get-Command Resolve-StopTargetPct -ErrorAction SilentlyContinue) {
        $__sizingSrcEarly = if ($Gem.PSObject.Properties['sizing'] -and $Gem.sizing) { $Gem.sizing } else { $Gem }
        Resolve-StopTargetPct -Sizing $__sizingSrcEarly
    } else { @{ stop_pct = 0.02 } }

    try {
        if (Get-Command Get-DynamicCapitalAllocation -ErrorAction SilentlyContinue) {
            $regime = if ($null -ne $global:MARKET_REGIME) { $global:MARKET_REGIME } else { "BEAR_WEAK" }

            # 2026-07-07: detecta scalp pra aplicar 3% em vez de 1%
            $isScalp = if (Get-Command Test-IsScalp -ErrorAction SilentlyContinue) {
                Test-IsScalp -Strategy $Signal.strategy -PlannedDurationMinutes $PlannedDurationMin
            } else { $false }

            $spotCap = CoinEx-GetSpotCapitalUSDT
            $futuresCap = CoinEx-GetFuturesCapitalUSDT
            $alloc = Get-DynamicCapitalAllocation -SpotUsdt $spotCap -FuturesUsdt $futuresCap -Regime $regime

            if ($alloc) {
                $allocForTrade = if ($hasFutures) { $alloc.short_alloc } else { $alloc.long_alloc }

                # 2026-07-22: risco/trade evoluido de 1% (Regra de Ouro #2 original)
                # para 3% flat, e MaxConcurrentTrades de 5 para 10 -- decisao explicita
                # do owner apos ver sizing de trades antigos (~$30, calculado com
                # capital menor de entao) parecer baixo frente ao capital atual
                # ($5042). Simulado antes de aplicar: perda maxima do portfolio se
                # as 10 posicoes baterem stop ao mesmo tempo = ~$76 (1.5% do capital
                # total), exposicao maxima ~30% do capital -- documentado como novo
                # baseline, nao mais 1%/5.
                # 2026-07-25: MaxConcurrentTrades 10 -> 15, coerente com
                # gem_max_exposure_pct (Test-GemSafetyGuards, lib_gem_safety.ps1)
                # subido de 15% para 25% no mesmo commit (canal real: tabela
                # Supabase evolution_params, via apply_evolution_gem_max_exposure).
                # Com risco 3%/trade, 25% de exposicao cabe ~8 posicoes simultaneas
                # de fato (o gate real que limita concorrencia); 15 aqui so ajusta
                # o tamanho da fatia por trade nesta funcao de sizing, com folga
                # sobre o gate real. Simulado: perda maxima teorica se 8-9 posicoes
                # baterem stop ao mesmo tempo = ~25% do capital (~$1259 em $5037.6).
                # 2026-08-04 FIX: este valor estava HARDCODED como 0.03, ignorando
                # $global:RISK_MAX_PCT_PER_TRADE por completo (a variavel de
                # config.ps1 -- 2026-07-22 dizia "1%", nunca foi atualizada quando
                # o hardcode virou 3% no mesmo commit, ficando morta/desincronizada
                # ha dias). Owner decidiu subir pra 7% -- agora le a variavel real
                # em vez de hardcode duplicado, config.ps1 e a UNICA fonte.
                $riskPct = if ($global:RISK_MAX_PCT_PER_TRADE) { [double]$global:RISK_MAX_PCT_PER_TRADE } else { 0.07 }
                $allocForTrade = $allocForTrade * $riskPct / 0.01  # normalize para o calc

                # 2026-08-04: owner pediu pesar o sizing pela FORCA do sinal --
                # ate aqui todo trade recebia a mesma fatia (dividida por
                # MaxConcurrentTrades=15 fixo, mesmo com poucas posicoes reais
                # abertas de fato). Get-SignalStrengthWeight (lib_sizing_dynamics.ps1)
                # usa $Gem.score (0-100, ja disponivel neste ponto -- passou no
                # gate scoreMin mais acima) pra dar fatia maior a sinais fortes
                # (score>=90 -> 1.5x) e menor a sinais no piso do gate (score<75
                # -> 0.6x), sem mudar o teto de risco de 3%/trade nem o divisor
                # de concorrencia -- so redistribui a fatia entre trades da
                # mesma janela conforme conviccao.
                $__signalWeight = if (Get-Command Get-SignalStrengthWeight -ErrorAction SilentlyContinue) {
                    Get-SignalStrengthWeight -Score ([double]$Gem.score)
                } else { 1.0 }

                $dynamicSize = Get-SizePerTrade -AllocatedCapital $allocForTrade -MaxConcurrentTrades 15 `
                    -StopLossPct ([double]$__stpEarly.stop_pct) -SignalWeight $__signalWeight

                if ($dynamicSize -gt 0) {
                    $usd_size = $dynamicSize
                    $sizingMethod = "dynamic_feedback_${regime}_3pct_weight${__signalWeight}"
                }
            }
        }
    } catch {
        Write-Host "  [SIZING] Dynamic falhou: $_ -- fallback" -ForegroundColor Yellow
    }

    # Fallback: Kelly ou legacy
    if (-not $usd_size -or $usd_size -le 0) {
        if (Get-Command Get-ExecutorSize -ErrorAction SilentlyContinue) {
            $szResolved = Get-ExecutorSize -Market $mkt -Mode "GEM" -Capital $capital -BasePct $sizing_pct
            $usd_size = [double]$szResolved.size_usd
            $sizingMethod = if ($null -ne $szResolved.method) { $szResolved.method } else { "kelly_adaptive" }
            if ($szResolved.method -eq "kelly_adaptive") {
                Write-Host "  [SIZING] Kelly adaptive: f_used=$($szResolved.f_used) win_prob=$($szResolved.win_prob) (n=$($szResolved.n_trades))" -ForegroundColor DarkCyan
            }
        } else {
            $usd_size = [math]::Round($capital * $sizing_pct, 2)
            $sizingMethod = "legacy_pct"
        }
    }
    # 2026-08-07 FIX CRITICO: clamp da Regra de Ouro (RISK_MAX_PCT_PER_TRADE,
    # config.ps1 -- 7% desde commit 4060d4e/2026-08-04) precisa rodar AQUI,
    # logo apos usd_size ser calculado por QUALQUER caminho (dynamic_feedback/
    # kelly/legacy_pct acima) -- antes de qualquer gate posterior que possa
    # BLOQUEAR o trade inteiro usando o valor cru.
    # Achado real: SOLUSDT recebeu usd_size ~$237 (10.11% de capital=$2345.92,
    # acima mesmo dos 7% da Regra de Ouro) e foi descartado por inteiro
    # pelo Test-CoinExposureCap (gate "cap_por_moeda", ~130 linhas abaixo)
    # sempre que o Mentor aprovava o setup -- o mesmo usd_size nao-clampado
    # tambem e o que o "HARD CAP DE RISCO" (mais abaixo no arquivo, apos
    # o exposure cap) corrigiria, mas so DEPOIS do bloqueio ja ter descartado
    # o trade. Aplicar o clamp aqui, antes de QUALQUER gate de bloqueio,
    # fecha a mesma classe de bug ja corrigida hoje no guard de sizing fixo
    # (Resolve-EffectiveSizingCap/lib_live_guards.ps1).
    # 2026-08-08 FIX: 1a versao deste clamp (RiskPct=0.03 hardcoded) reintroduziu
    # por engano o mesmo bug que o commit 4060d4e ja tinha corrigido -- $riskPct
    # do caminho primario (linha ~837) ja lia $global:RISK_MAX_PCT_PER_TRADE (7%),
    # mas este clamp (adicionado 1 dia depois, sem eu saber da mudanca de 3%->7%)
    # usava 3% hardcoded, apertando de volta pro valor antigo sempre que este
    # gate clampava. Owner notou o valor errado no monitoramento ao vivo.
    if (Get-Command Resolve-GoldenRuleSizeClamp -ErrorAction SilentlyContinue) {
        $__riskPctEarly = if ($global:RISK_MAX_PCT_PER_TRADE) { [double]$global:RISK_MAX_PCT_PER_TRADE } else { 0.07 }
        $__earlyClamp = Resolve-GoldenRuleSizeClamp -ProposedUsd $usd_size -Capital $capital -RiskPct $__riskPctEarly
        if ($__earlyClamp.clamped) {
            Write-Host "  [SIZING] $mkt usd_size=$usd_size excede $($__riskPctEarly*100)% do capital ($($__earlyClamp.usd_size)) -- clampado antes dos gates de bloqueio" -ForegroundColor Cyan
            $usd_size = [double]$__earlyClamp.usd_size
        }
    }

    $qty         = [math]::Round($usd_size / $price, 6)
    $spike_pct   = $vd.pct_change_today

    Write-Host "  Mercado    : $mkt [$($Gem.mode)] score=$($Gem.score) tipo=$marketType" -ForegroundColor White
    Write-Host "  Capital    : $capital USDT ($marketType real)" -ForegroundColor Gray
    # 2026-07-22 FIX: log mostrava $sizing_pct (2%/3% legado, so usado no
    # fallback) mesmo quando dynamic_feedback/kelly_adaptive (o caminho
    # PRIMARIO, roda primeiro) calculava $usd_size por uma formula totalmente
    # diferente -- % exibido nunca batia com o valor em USD ao lado,
    # confundindo qualquer analise manual do risco real por trade.
    $realPct = if ($capital -gt 0) { [math]::Round(($usd_size / $capital) * 100, 3) } else { 0 }
    Write-Host "  Sizing     : $realPct% = $usd_size USDT ($sizingMethod)" -ForegroundColor Yellow
    Write-Host "  Preco      : $price  Qtd: $qty" -ForegroundColor White
    Write-Host "  Vol spike  : $($vd.spike_ratio)x $($vd.spike_type) (+${spike_pct}%)" -ForegroundColor Gray
    Write-Host "  Max dias   : $($Gem.max_days)d" -ForegroundColor Gray

    if ($marketType -eq "FUTURES") {
        Write-Host "  LEMBRETE: margem isolated deve estar configurada para $mkt" -ForegroundColor DarkYellow
    }

    # ── 0. MARKET SAFETY (aviso "nao atacar" da CoinEx) ──────────────────────
    # 2026-06-08: respeita delisting/suspend/swap/maintenance que a CoinEx sinaliza.
    # CoinEx-GetMarketInfo ja expoe isSafe + notices; antes nao era consumido.
    # Gate mais cedo possivel (antes de qualquer custo LLM). Fail-safe: so bloqueia
    # quando explicitamente unsafe (info disponivel e isSafe=false).
    if ($marketType -eq "FUTURES" -and (Get-Command CoinEx-GetMarketInfo -ErrorAction SilentlyContinue)) {
        try {
            $mktInfo = CoinEx-GetMarketInfo $mkt
            if ($mktInfo -and ($mktInfo.isSafe -eq $false)) {
                $noticeTxt = if ($mktInfo.notices -and @($mktInfo.notices).Count -gt 0) { ($mktInfo.notices -join "; ") } else { "status=$($mktInfo.status)" }
                Write-Host "  [GEM BLOQUEADO] MARKET UNSAFE (CoinEx aviso): $mkt -- $noticeTxt" -ForegroundColor Red
                try { Send-TelegramAlert -Message "*GEM BLOQUEADO* -- $mkt`nMotivo: CoinEx sinaliza 'nao atacar'`n$noticeTxt" | Out-Null } catch {}
                if (Get-Command Add-GemRejection -ErrorAction SilentlyContinue) {
                    try { Add-GemRejection -Path (Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json") -Market $mkt -Reason "market_unsafe:$noticeTxt" } catch {}
                }
                return [PSCustomObject]@{ blocked = $true; blocked_by = @("market_unsafe_coinex:$noticeTxt"); market = $mkt }
            }
        } catch { }  # API falha -> nao bloqueia (degradacao graciosa; outros gates seguem)
    }

    # ── FIX 2026-07-07: CASCADING ADD POSITION PREVENTION ────────────────────
    # BUG RAIZ: gem_executor abria 15+ Add Positions em cascata sem validação
    # Causa: sem check de posição existente, leverage acumulado, ou limite Add Positions
    # Solução: validar ANTES de executar qualquer ordem

    # Check posições existentes no mercado
    $existingPosition = $null
    try {
        $allPositions = CoinEx-GetPendingPositions -ErrorAction Stop
        $existingPosition = @($allPositions | Where-Object market -eq $mkt) | Select-Object -First 1
    } catch {
        Write-Host "  [WARN] Falha ao verificar posições existentes: $_" -ForegroundColor Yellow
    }

    if ($existingPosition) {
        # Posição JÁ EXISTE neste mercado
        $currentLeverage = [double]$existingPosition.leverage
        $currentMargin = [double]$existingPosition.cml_position_value
        $currentQty = [double]$existingPosition.open_interest
        $maxLeveragePerPair = 10  # HARD LIMIT: nunca mais de 10X por par
        $maxAddPositionsAllowed = 3

        # Contar quantos Add Positions já temos registrados para este market
        #
        # 2026-07-29 FIX CRITICO (achado real em producao: DOGEUSDT SHORT
        # recebeu 12 Add Positions em 17h, sem o guard bloquear NENHUMA):
        # journal/trade_outcomes.jsonl e um arquivo LOCAL -- o runner do
        # GitHub Actions e efemero (clona limpo a cada job), esse arquivo
        # NUNCA sobrevive entre execucoes. $addPositionCount sempre lia 0,
        # o limite "maximo 3 Add Positions/6h" nunca bloqueava de verdade.
        # Alem disso, os campos usados (.market/.entry_date/status="open")
        # nunca existiram no schema real de trade_outcomes (colunas reais:
        # symbol/entry_ts/status com valores 'pending'|'closed', nunca
        # 'open') -- o guard nao teria funcionado nem lendo do Supabase
        # real com esse schema. Fix: fonte dedicada e real
        # (lib_gem_position_events.ps1, tabela gem_position_events),
        # registrada no momento exato de cada execucao real de ordem.
        $addPositionCount = if (Get-Command Get-RecentGemAddPositionCount -ErrorAction SilentlyContinue) {
            Get-RecentGemAddPositionCount -Market $mkt -HoursBack 6
        } else { 0 }

        # Validações de limite
        if ($currentLeverage -ge $maxLeveragePerPair) {
            Write-Host "  [CASCADE BLOCK] ${mkt}: Já tem leverage=$currentLeverage >= limite=$maxLeveragePerPair. NÃO fazer Add Position." -ForegroundColor Red
            try { Send-TelegramAlert -Message "🚫 GEM bloqueado (cascata): $mkt leverage=$currentLeverage >= $maxLeveragePerPair`nPosição: $currentQty @ $($existingPosition.avg_entry_price)`nCapital: $currentMargin USDT" | Out-Null } catch {}
            if (Get-Command Add-GemRejection -ErrorAction SilentlyContinue) {
                try { Add-GemRejection -Path (Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json") -Market $mkt -Reason "cascade_leverage_max:$currentLeverage" } catch {}
            }
            return [PSCustomObject]@{ blocked = $true; blocked_by = @("cascade_leverage_max_$currentLeverage"); market = $mkt }
        }

        if ($addPositionCount -ge $maxAddPositionsAllowed) {
            Write-Host "  [CASCADE BLOCK] ${mkt}: Já tem $addPositionCount Add Positions >= limite=$maxAddPositionsAllowed. Posição FECHADA para reforço." -ForegroundColor Red
            try { Send-TelegramAlert -Message "🚫 GEM bloqueado (cascata): $mkt tem $addPositionCount Add Positions, limite atingido`nPosição travada" | Out-Null } catch {}
            if (Get-Command Add-GemRejection -ErrorAction SilentlyContinue) {
                try { Add-GemRejection -Path (Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json") -Market $mkt -Reason "cascade_add_position_max:$addPositionCount" } catch {}
            }
            return [PSCustomObject]@{ blocked = $true; blocked_by = @("cascade_add_position_max_$addPositionCount"); market = $mkt }
        }

        # OK fazer Add Position (mas com limite de tamanho)
        $maxAddAmount = $capital * 0.05  # Máximo 5% do capital por Add
        if ($usd_size -gt $maxAddAmount) {
            $usd_size = $maxAddAmount
            Write-Host "  [CASCADE LIMIT] Reducido tamanho de Add: $($Gem.sizing_pct * 100)% → 5% capital (~$maxAddAmount USDT)" -ForegroundColor Yellow
        }
    }

    # ── 1. GEM SAFETY GUARDS (block runaway exposure) ────────────────────────
    # Aplica em DryRun tambem para sinalizar bloqueios em paper trade.
    $safetyStatePath = Join-Path $global:JOURNAL_DIR "gem_safety_state.json"
    $safety = Test-GemSafetyGuards -TradeSizeUsdt $usd_size -TotalCapitalUsdt $capital -Market $mkt -StateFilePath $safetyStatePath
    if (-not $safety.allowed) {
        Write-Host "  [GEM SAFETY BLOCK] ${mkt}: $($safety.reason)" -ForegroundColor Red
        try { Send-TelegramAlert -Message "GEM bloqueado: $($safety.reason)`n$($safety.telegram_message)" | Out-Null } catch {}
        # C fix: TTL cache pra evitar loop re-aprovacao
        if (Get-Command Add-GemRejection -ErrorAction SilentlyContinue) {
            try { Add-GemRejection -Path (Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json") -Market $mkt -Reason "gem_safety:$($safety.reason)" } catch {}
        }
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("gem_safety:$($safety.reason)"); market = $mkt }
    }
    if ($safety.requires_confirmation) {
        Write-Host "  [GEM SAFETY] confirmacao dupla exigida (projetado $($safety.projected_exposure_pct)%)." -ForegroundColor Yellow
        try { Send-TelegramAlert -Message "GEM aviso: $($safety.telegram_message)" | Out-Null } catch {}
        # 2026-05-20: confirmation policy = warning-only (segue trade). Wait-TelegramApproval
        # existe em lib_telegram.ps1:153 mas decisao explicita: GEM mantem aviso unico
        # (sizing 0.2% ja eh tao pequeno que double-confirm seria overkill).
    }

    # ── 1b. COIN EXPOSURE CAP (2026-06-24: anti trade-gigante por SALDO REAL) ──
    # Causa raiz: dedup olhava ledger local (desviava) -> PAXG re-comprado ate 45%.
    # Agora checa o SALDO REAL da corretora: bloqueia re-entrada + cap % por moeda.
    if (Get-Command Test-CoinExposureCap -ErrorAction SilentlyContinue) {
        try {
            $baseCcy = if ($mkt -match "USDT$") { $mkt.Substring(0, $mkt.Length - 4) } else { $mkt }
            $heldUsd = 0.0
            $balR = CoinEx-Get "/v2/assets/spot/balance"
            if ($balR.code -eq 0) {
                $coin = $balR.data | Where-Object { "$($_.ccy)".ToUpper() -eq $baseCcy.ToUpper() } | Select-Object -First 1
                if ($coin) {
                    $heldQty = ([double]$coin.available) + ([double]$coin.frozen)
                    $px = 0.0
                    try { $tk = Invoke-RestMethod "https://api.coinex.com/v2/spot/ticker?market=$mkt" -TimeoutSec 6 -EA Stop; if ($tk.data) { $px = [double]$tk.data[0].last } } catch {}
                    $heldUsd = $heldQty * $px
                }
            }
            # 2026-07-30 FIX: cap so olhava saldo SPOT -- CEGO pra posicoes FUTURES.
            # Achado real: DOGEUSDT SHORT (futures) acumulou $1097 -> $1165 de margem
            # ao longo do dia via re-entradas repetidas do scanner (cada ciclo achava
            # "sinal valido" de novo no mesmo mercado onde ja havia posicao aberta),
            # sem NENHUM guard de teto absoluto barrar -- o cascade guard (gem_executor
            # linha ~893) so limita 3 Add Position por janela de 6h e depois RESETA,
            # nao e um teto. Soma a margem FUTURES real (existingPosition, ja resolvida
            # mais acima nesta funcao) ao heldUsd antes de checar o cap -- agora reflete
            # exposicao total (spot+futures) na moeda, nao so metade do quadro.
            if ($existingPosition) {
                $heldUsd += [double]$existingPosition.cml_position_value
            }
            $cap = Test-CoinExposureCap -HeldUsd $heldUsd -TradeUsd $usd_size -PortfolioUsd $capital
            if (-not $cap.allowed) {
                Write-Host "  [EXPOSURE CAP BLOCK] ${mkt}: $($cap.reason) (held=`$$([math]::Round($heldUsd,2)) proj=$($cap.projected_pct)%)" -ForegroundColor Red
                # 2026-08-15: achado real (owner, 22+ posicoes SHORT abertas) --
                # scanner varre a cada 5min, entao a MESMA moeda ja posicionada
                # ("anti trade-gigante", bloqueio correto) gerava dezenas de
                # Telegrams/hora sem nenhuma acao necessaria. Max 1 alerta por
                # moeda por janela do dia (manha/tarde/noite BRT), sem alerta
                # na madrugada -- ver Test-DailyMarketAlertThrottle.
                $__shouldAlertExposure = if (Get-Command Test-DailyMarketAlertThrottle -ErrorAction SilentlyContinue) {
                    Test-DailyMarketAlertThrottle -Market $mkt -Reason "exposure_cap"
                } else { $true }
                if ($__shouldAlertExposure) {
                    try { Send-TelegramAlert -Message "GEM bloqueado ${mkt}: $($cap.reason) - ja segura `$$([math]::Round($heldUsd,2)) (anti trade-gigante)" | Out-Null } catch {}
                }
                if (Get-Command Add-GemRejection -ErrorAction SilentlyContinue) {
                    try { Add-GemRejection -Path (Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json") -Market $mkt -Reason "exposure_cap:$($cap.reason)" } catch {}
                }
                return [PSCustomObject]@{ blocked = $true; blocked_by = @("exposure_cap:$($cap.reason)"); market = $mkt }
            }
        } catch { Write-Host "  [EXPOSURE CAP] ${mkt}: check falhou (fallback allow): $_" -ForegroundColor Yellow }
    }

    # ── 1c. CENARIO BTC-CORE GATE (2026-06-24: identifica cenario -> estrategia com edge) ──
    # Causa real das perdas: comprou alt LONG com BTC -20%/mes (alt sangra 2-4x em bear).
    # CAPITULACAO -> libera LONG (compra fundo) | BEAR -> bloqueia LONG, libera SHORT
    # BULL -> libera LONG | NEUTRO -> espera. Substitui o gate simples.
    if (Get-Command Get-MarketScenario -ErrorAction SilentlyContinue) {
        # 2026-07-08 CRITICAL FIX: BUG RAIZ do LDOUSDT flip SHORT->LONG->SHORT.
        # Problema: $dirForGate era hardcoded LONG (linha 673 original), mas $direction
        # so resolve MUITO depois em linha ~1011 via conviction score. Gate BTC-core
        # avaliava TUDO como LONG -> bloqueava SHORTs validos em BEAR regime -> proxima
        # iteracao recalculava SHORT -> proximo gate bloqueava de novo como LONG.
        # Solucao: usar MESMO calculo de conviction ANTES do gate BTC-core, nao depois.
        # Isto garante $dirForGate eh consistente com a direcao que SERA executada.

        # Pre-calcular convictions AGORA (replicated from section 3 mais abaixo)
        # para que gate BTC-core tome decisao com direção CORRETA.
        $dirForGate = "LONG"  # default se nao conseguir calcular

        # 2026-07-28 FIX (achado real: SUIUSDT com direction=LONG->SHORT no gate
        # breadth_long_blocked, mas [CENARIO BLOCK] logo depois ainda dizia
        # "bloqueia LONG"): quando o gate breadth_long_blocked (linha ~611-635)
        # ja resolveu $direction via override do Mentor, essa e a fonte de
        # verdade mais recente -- $dirForGate NAO deve recalcular do zero e
        # contradize-la. So aplica quando $direction ja saiu do estado inicial
        # "LONG" default (Gem.direction), preservando o pre-calculo original
        # (comentario 2026-07-08 acima) pra todos os outros casos sem override.
        if ($direction -eq "SHORT") {
            $dirForGate = "SHORT"
        }

        # 2026-07-09 FIX: gems chegam como HASHTABLE (triggers, TORI_SHORT sweep) e
        # PSObject.Properties['direction'] NAO enxerga chaves de hashtable -> direction
        # SHORT era ignorada e o gate avaliava LONG. Check por VALOR funciona p/ ambos.
        $gemDirRaw = "$($Gem.direction)".ToUpper()
        if ($dirForGate -eq "SHORT") {
            # ja resolvido acima via override do Mentor -- nao sobrescrever.
        } elseif ($gemDirRaw -in @("LONG","SHORT")) {
            # Direcao explicita no GEM - use ela
            $dirForGate = $gemDirRaw
        } else {
            # Calcular conviction SHORT vs LONG AGORA (pre-cálculo)
            # Este é exatamente o mesmo código que aparecerá em section 3 (linhas ~938-1011)
            $convShortPre = 50
            $convLongPre = 50

            # Pump-fade detection (ativo blocker para LONG)
            if (Get-Command Detect-EarlyPump -ErrorAction SilentlyContinue) {
                try {
                    $pdChangePre = if ($null -ne $Gem.change_24h) { [double]$Gem.change_24h } else { 0 }
                    # 2026-07-16 FIX: campo real e "spike_ratio", nao "volume_ratio" (ver
                    # fix acima na 1a ocorrencia deste padrao)
                    $pdVolRPre = if ($null -ne $Gem.vol_data.spike_ratio) { [double]$Gem.vol_data.spike_ratio } else { 1.0 }
                    $pdRsiPre = if ($null -ne $Gem.rsi_14) { [double]$Gem.rsi_14 } else { 50 }
                    $pumpDetectPre = Detect-EarlyPump -Market $mkt -ChangePercent24h $pdChangePre -VolumeRatio $pdVolRPre -RSI $pdRsiPre -CurrentPrice $price
                    if ($pumpDetectPre.is_pump -and # 2026-07-16 FIX: Detect-EarlyPump NUNCA retorna "FADE"/"TOP" -- so
                    # "early"|"mid"|"late"|"none" (ver lib_pump_scalper.ps1). "late"
                    # (movimento >=50% acumulado) e o equivalente semantico do estagio
                    # de exaustao que esta condicao pretendia capturar -- alinhado pra
                    # a logica de dump/SHORT-em-topo-de-pump disparar de verdade.
                    $pumpDetectPre.pump_stage -match "late") {
                        $convShortPre = [math]::Min(100, [int]$pumpDetectPre.confidence + 20)
                        $convLongPre = [math]::Max(0, 50 - [int]$pumpDetectPre.confidence)
                    }
                } catch { }
            }

            # Regime bias (BEAR favorece SHORT, BULL favorece LONG)
            if ($global:CURRENT_REGIME -match "BEAR") {
                $convShortPre += 10
                $convLongPre = [math]::Max($convLongPre - 5, 40)
            } elseif ($global:CURRENT_REGIME -match "BULL") {
                $convLongPre += 10
                $convShortPre = [math]::Max($convShortPre - 5, 40)
            }

            # Decidir direcao PRE com base em conviction gap
            $convShortPre = [math]::Min([math]::Max([int]$convShortPre, 0), 100)
            $convLongPre = [math]::Min([math]::Max([int]$convLongPre, 0), 100)

            if ([math]::Abs($convShortPre - $convLongPre) -ge 20) {
                $dirForGate = if ($convShortPre -gt $convLongPre) { "SHORT" } else { "LONG" }
            } else {
                # Convictions proximais - nao decide aqui, deixa section 3 resolver
                # (pode virar SKIP)
                $dirForGate = "LONG"  # default (sera reverificado em section 3)
            }
        }
        try {
            $scen = Get-MarketScenario
            $blockLong  = ($dirForGate -eq "LONG")  -and (-not $scen.allow_long)
            $blockShort = ($dirForGate -eq "SHORT") -and (-not $scen.allow_short)

            # 2026-07-03 DIVERGENCIA REGIME x CENARIO: cenario mede SO o BTC (EMA20/50 +
            # momentum 30d). NEUTRO = BTC em chop -> bloqueava AMBAS as direcoes. Mas em
            # chop com momentum de 30d negativo = "moagem" — exatamente o bolso onde o
            # counterfactual mostrou SHORT de alt funcionando (56% win, mediana +4.9%,
            # docs/ESTUDO_GATES_SHORT). Fisica: microcap deriva -41%/ano independente do
            # chop do BTC (lei 4). Regra: NEUTRO + momentum BTC negativo -> libera SHORT
            # (LONG continua bloqueado).
            #
            # 2026-07-14 fix: condicao original checava $global:CURRENT_REGIME -match
            # "BEAR", mas essa variavel NUNCA e atribuida em codigo de producao (so em
            # teste) -- gate morto desde a criacao, nunca disparou em live trading.
            # Substituido por $scen.momentum_30d (ja calculado ao vivo por Get-MarketScenario
            # nesta mesma chamada, sem depender de infra externa quebrada -- ver rodada 1
            # revertida acima, journal/regime_state.json e gitignored/inacessivel na nuvem).
            if ($blockShort -and $scen.scenario -eq "NEUTRO" -and $scen.momentum_30d -lt 0) {
                $blockShort = $false
                Write-Host "  [CENARIO NEUTRO->SHORT OK] ${mkt}: BTC chop mas momentum_30d=$($scen.momentum_30d)% negativo (moagem favorece short de alt)" -ForegroundColor DarkYellow
            }
            # 2026-06-30 SURF: em vez de so bloquear LONG no bear, SURFA o bear (SHORT).
            # Shadow-first: sem journal/REGIME_SURF_SHORT_LIVE.flag -> so loga; com flag -> ordem real.
            # Se executou SHORT real, retorna (nao bloqueia mais). allow_short ja confirma downtrend.
            if ($blockLong -and $scen.allow_short -and (Get-Command Invoke-RegimeSurfShort -ErrorAction SilentlyContinue)) {
                try {
                    $shortConv = if ($Gem.PSObject.Properties['conviction'] -and $Gem.conviction) { [double]$Gem.conviction } else { [double]$Gem.score }
                    $surf = Invoke-RegimeSurfShort -Market $mkt -Price $price -Scenario $scen `
                        -Momentum30dPct -1 -ShortConviction $shortConv -Capital $capital
                    if ($surf.executed) {
                        Write-Host "  [SURF LIVE] ${mkt}: SHORT executado order=$($surf.order_id) entry=$($surf.decision.entry) stop=$($surf.decision.stop)" -ForegroundColor Green
                        return [PSCustomObject]@{ blocked = $false; executed = $true; direction = "SHORT"; market = $mkt; order_id = $surf.order_id; decision = $surf.decision }
                    } elseif ($surf.dry_run) {
                        Write-Host "  [SURF SHADOW] ${mkt}: SHORT shadow logado ($($surf.decision.reason))" -ForegroundColor Magenta
                    } else {
                        Write-Host "  [SURF SKIP] ${mkt}: $($surf.reason)" -ForegroundColor DarkGray
                    }
                } catch { Write-Host "  [SURF] ${mkt}: tentativa SHORT falhou ($_)" -ForegroundColor Yellow }
            }
            # 2026-07-02: Allow 20% LONG allocation in BEAR_WEAK (per backtest calibration)
            # 2026-07-03 FIX: a condicao antiga comparava o CENARIO com o nome do REGIME —
            # cenario so vale UNKNOWN/CAPITULACAO/BEAR/BULL/NEUTRO, entao era IMPOSSIVEL
            # e a flag nasceu morta (LONG 100% bloqueado em BEAR/NEUTRO desde a criacao).
            # 2026-07-14 FIX 2: a correcao anterior apontou pro lugar certo
            # ($global:CURRENT_REGIME -eq "BEAR_WEAK") mas essa variavel tambem
            # nunca e atribuida em producao (mesmo bug do gate SHORT acima) --
            # gate continuou morto. Substituido por $scen.bear_severity (WEAK/
            # STRONG/NONE), calculado ao vivo dentro de Get-MarketScenario com
            # a mesma formula de backtest/regime_change_monitor.py (dist SMA200
            # + momentum 20d) -- so libera 20% LONG em bear FRACO, nunca em
            # bear forte (mantém a intenção original da flag).
            $allowLongInBearFlag = Join-Path $global:JOURNAL_DIR "ALLOW_LONG_IN_BEAR_WEAK.flag"
            $allowLongInBear = Test-Path $allowLongInBearFlag
            $effectiveBlockLong = $blockLong -and -not ($allowLongInBear -and $scen.bear_severity -eq "WEAK" -and $dirForGate -eq "LONG")
            if ($blockLong -and -not $effectiveBlockLong) {
                Write-Host "  [CENARIO LONG-EXCECAO] ${mkt}: flag ALLOW_LONG_IN_BEAR_WEAK + bear_severity=WEAK libera LONG (cenario=$($scen.scenario))" -ForegroundColor DarkYellow
            }

            # 2026-07-16 PUMP EXTREMO: cenario mede SO o BTC (EMA20/50 + momentum
            # 30d) -- irrelevante pra um evento isolado tipo AKEUSDT +300%/24h, que
            # nao tem nada a ver com o regime macro. Achado real: AKE/ARG foram
            # descobertos e simulados pelo gate_replay_study, mas ficaram sempre
            # bloqueados por "cenario=NEUTRO" mesmo com sinal extremo. Exigir
            # momentum recente confirmado (1h+4h na MESMA direcao do pump, reusa
            # Test-RecentMomentumConfirmed do breadth gate) evita comprar o topo
            # de um pump ja exaurido -- so libera se o movimento ainda esta "vivo"
            # agora, nao so historico das ultimas 24h.
            $pumpExtremeThresholdPct = 100.0
            if ($effectiveBlockLong -and $dirForGate -eq "LONG" -and $gemChange24h -ge $pumpExtremeThresholdPct -and
                (Get-Command Test-RecentMomentumConfirmed -ErrorAction SilentlyContinue)) {
                $pumpMomentumOk = $false
                try { $pumpMomentumOk = Test-RecentMomentumConfirmed -Market $mkt -Direction "gt" } catch {}
                if ($pumpMomentumOk) {
                    $effectiveBlockLong = $false
                    Write-Host "  [CENARIO PUMP-EXCECAO] ${mkt}: change24h=+$([math]::Round($gemChange24h,1))% >= $pumpExtremeThresholdPct% + momentum 1h/4h confirmado -> libera LONG apesar de cenario=$($scen.scenario)" -ForegroundColor DarkYellow
                }
            }

            if ($effectiveBlockLong -or $blockShort) {
                $reason = if ($effectiveBlockLong -and $blockShort) { "ambas" } elseif ($effectiveBlockLong) { "LONG" } else { "SHORT" }
                Write-Host "  [CENARIO BLOCK] ${mkt}: cenario=$($scen.scenario) bloqueia $reason ($($scen.reason))" -ForegroundColor Red
                try { Send-TelegramAlert -Message "GEM bloqueado ${mkt}: cenario BTC=$($scen.scenario), estrategia=$($scen.strategy) -> $reason sem edge" | Out-Null } catch {}
                if (Get-Command Add-GemRejection -ErrorAction SilentlyContinue) {
                    try { Add-GemRejection -Path (Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json") -Market $mkt -Reason "cenario:$($scen.scenario)" } catch {}
                }
                $__override = $null
                if (Get-Command Test-MentorOverride -ErrorAction SilentlyContinue) {
                    $__override = Test-MentorOverride -Market $mkt -GateTag "cenario" -GateReason "cenario=$($scen.scenario) bloqueia $reason ($($scen.reason))" `
                        -Direction $direction -Price $price -Change24h $gemChange24h -Regime "$($scen.scenario)"
                }
                if ($__override -and $__override.approved) {
                    Write-Host "  [MENTOR OVERRIDE] $mkt -- $($__override.motivo)" -ForegroundColor Magenta
                } else {
                    return [PSCustomObject]@{ blocked = $true; blocked_by = @("cenario:$($scen.scenario)"); market = $mkt }
                }
            }
            Write-Host "  [CENARIO OK] ${mkt}: $($scen.scenario) -> $($scen.strategy) (libera $dirForGate)" -ForegroundColor DarkGray
        } catch { Write-Host "  [CENARIO] ${mkt}: check falhou (fallback allow): $_" -ForegroundColor Yellow }
    }

    # ── 1d. CROWDING GATE (2026-07-15: shadow -> ativo) ──
    # Evidencia n=5133 (ESTUDO 2026-07-04, lib_crowding_signal.ps1): funding
    # extremo+ -> fwd24h -0.73% e LONG vira edge negativo (43-46% win). Caso
    # real: WAVESUSDT logada CROWDED_LONGS (funding 0.43%) dias antes de -18%
    # -- o shadow previu, nada agiu. v1: LONG+long_caution = BLOCK;
    # SHORT+short_boost = so log (boost de conviction fica pro v2, apos
    # observar telemetria). Fail-open: sem funding/futures -> no-op.
    if (-not (Get-Command Get-CrowdingSignal -ErrorAction SilentlyContinue)) {
        $crowdLibPath = Join-Path $PSScriptRoot "lib_crowding_signal.ps1"
        if (Test-Path $crowdLibPath) { . $crowdLibPath }
    }
    if (Get-Command Get-CrowdingSignal -ErrorAction SilentlyContinue) {
        try {
            $crowd = Get-CrowdingSignal -Market $mkt
            if ($crowd -and $crowd.available) {
                # 2026-07-28 FIX (achado real: mesma classe de bug de direction=
                # LONG->SHORT dessincronizada, ver 8ba227a/dfc518c/edd4789): esta
                # secao lia $Gem.direction cru, o valor ORIGINAL do scanner, que
                # nunca muda quando o Mentor aprova SHORT via override no gate
                # breadth_long_blocked. Se $direction ja foi resolvida como SHORT,
                # ela e a fonte de verdade mais recente -- prioriza sobre Gem.direction.
                $dirCrowd = if ($direction -eq "SHORT") { "SHORT" } else { "$($Gem.direction)".ToUpper() }
                if ($dirCrowd -notin @("LONG","SHORT")) { $dirCrowd = "LONG" }
                if ($dirCrowd -eq "LONG" -and $crowd.long_caution) {
                    Write-Host "  [CROWDING BLOCK] ${mkt}: $($crowd.crowding) funding=$($crowd.funding_pct)% -- LONG edge negativo (hist 43-46% win)" -ForegroundColor Red
                    try { Send-TelegramAlert -Message "GEM bloqueado ${mkt}: crowding $($crowd.crowding) (funding $($crowd.funding_pct)%) -> LONG sem edge" | Out-Null } catch {}
                    if (Get-Command Add-GemRejection -ErrorAction SilentlyContinue) {
                        try { Add-GemRejection -Path (Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json") -Market $mkt -Reason "crowding:$($crowd.crowding)" } catch {}
                    }
                    $__override = $null
                    if (Get-Command Test-MentorOverride -ErrorAction SilentlyContinue) {
                        $__override = Test-MentorOverride -Market $mkt -GateTag "crowding" -GateReason "$($crowd.crowding) funding=$($crowd.funding_pct)%" `
                            -Direction $dirCrowd -Price $price -Change24h $gemChange24h -Regime "$($btcScenario.scenario)"
                    }
                    if ($__override -and $__override.approved) {
                        Write-Host "  [MENTOR OVERRIDE] $mkt -- $($__override.motivo)" -ForegroundColor Magenta
                    } else {
                        return [PSCustomObject]@{ blocked = $true; blocked_by = @("crowding:$($crowd.crowding)"); market = $mkt }
                    }
                }
                if ($dirCrowd -eq "SHORT" -and $crowd.short_boost) {
                    Write-Host "  [CROWDING] ${mkt}: short_boost ativo ($($crowd.crowding) funding=$($crowd.funding_pct)%) -- telemetria v1, sem alterar conviction" -ForegroundColor DarkYellow
                }
            }
        } catch { }
    }

    # ── 2. CHART PATTERN GATE (2026-06-18: bloqueador ativo) ──
    # Rejeita pump-chase, topping patterns, fake breakouts ANTES de qualquer outra gate
    # Economia: evita -11% (COAIUSDT tipo) com zero LLM
    if (Get-Command Test-ChartPatternGate -ErrorAction SilentlyContinue) {
        try {
            $chart = Test-ChartPatternGate -Market $mkt -HistoricalPrice $prices -Volume $volumes
            if (-not $chart.pass) {
                Write-Host "  [CHART PATTERN BLOCKED] ${mkt}: $($chart.reason) (confidence $($chart.confidence)%)" -ForegroundColor Red
                if (Get-Command Add-GemRejection -ErrorAction SilentlyContinue) {
                    try { Add-GemRejection -Path (Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json") -Market $mkt -Reason "chart_pattern:$($chart.reason)" } catch {}
                }
                $__override = $null
                if (Get-Command Test-MentorOverride -ErrorAction SilentlyContinue) {
                    $__override = Test-MentorOverride -Market $mkt -GateTag "chart_pattern" -GateReason "$($chart.reason) (confidence $($chart.confidence)%)" `
                        -Direction $direction -Price $price -Change24h $gemChange24h -Regime "$($btcScenario.scenario)"
                }
                if ($__override -and $__override.approved) {
                    Write-Host "  [MENTOR OVERRIDE] $mkt -- $($__override.motivo)" -ForegroundColor Magenta
                } else {
                    return [PSCustomObject]@{ blocked = $true; blocked_by = @("chart_pattern_$($chart.reason)"); market = $mkt }
                }
            } else {
                Write-Host "  [CHART OK] ${mkt}: $($chart.reason)" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "  [CHART PATTERN ERROR] ${mkt}: $_ (fallback: allow)" -ForegroundColor Yellow
        }
    }

    # ── 2-TORI: TORI CONFLUENCE GATE (2026-07-08: core technical validation layer) ──
    # NEW: Confluence score MUST be >= 80 (strict gate). Replaces old Tori signal logic.
    # 5 signals: Volume Climax, RSI Extreme, Fractal Pattern, CHoCH, Volume Profile
    # Fail-closed: insufficient data or error = BLOCK entry
    # Wire into: early gate, before conviction/mesa score (technical first)
    if (Get-Command Test-ToriConfluence -ErrorAction SilentlyContinue) {
        try {
            $dirForConfluence = "LONG"  # determine direction first
            # 2026-07-09 FIX: check por VALOR (hashtable-safe) — PSObject.Properties
            # nao enxerga chaves de hashtable; TORI_SHORT/TRIGGER gems sao hashtables.
            $gemDirConf = "$($Gem.direction)".ToUpper()
            # 2026-07-28 FIX (achado real: DOGEUSDT com direction=LONG->SHORT
            # resolvida e CENARIO ja liberando SHORT, mas [TORI Gate] START
            # test-confluence ainda avaliou dir=LONG): $gemDirConf (Gem.direction
            # cru) tinha precedencia sobre $dirForGate (que ja herda a decisao
            # do Mentor desde dfc518c) -- o elseif abaixo nunca era alcancado
            # quando Gem.direction ja era um valor valido (caso comum). Se
            # $direction ja foi resolvida como SHORT via override, ela e a
            # fonte de verdade mais recente.
            if ($direction -eq "SHORT") {
                $dirForConfluence = "SHORT"
            } elseif ($gemDirConf -in @("LONG","SHORT")) {
                $dirForConfluence = $gemDirConf
            } elseif ($dirForGate -in @("LONG","SHORT")) {
                # coerencia com o pre-calc da section 1c (LDOUSDT flip fix)
                $dirForConfluence = $dirForGate
            }

            $toriConfluence = Test-ToriConfluence -Market $mkt -SetupType $dirForConfluence -TimeframeMinutes 60 -Price $price -TimeoutSeconds 6

            # Log detailed analysis
            Write-Host "  [TORI CONFLUENCE] ${mkt}: score=$($toriConfluence.confluence_score)/100 status=$(if ($toriConfluence.allows) { 'PASS' } else { 'BLOCK' })" -ForegroundColor $(if ($toriConfluence.allows) { 'Green' } else { 'Yellow' })

            if ($toriConfluence.signals_fired -and $toriConfluence.signals_fired.Count -gt 0) {
                Write-Host "  [TORI SIGNALS] ${mkt}: $($toriConfluence.signals_fired -join ' + ')" -ForegroundColor DarkGray
            }

            # Fail-closed: if confluence score too low, BLOCK
            if (-not $toriConfluence.allows) {
                Write-Host "  [TORI CONFLUENCE BLOCK] ${mkt}: score=$($toriConfluence.confluence_score) < threshold=80 (reason: $($toriConfluence.reason))" -ForegroundColor Red
                try { Send-TelegramAlert -Message "GEM bloqueado ${mkt}: Tori confluence baixa ($($toriConfluence.confluence_score)/100) - sem edge tecnica`n$($toriConfluence.reason)" | Out-Null } catch {}

                # Cache rejection with Tori score
                if (Get-Command Add-GemRejection -ErrorAction SilentlyContinue) {
                    try {
                        Add-GemRejection -Path (Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json") -Market $mkt `
                            -Reason "tori_confluence:$($toriConfluence.confluence_score)" `
                            -ToriConfluenceScore $toriConfluence.confluence_score
                    } catch {}
                }

                # Write audit log
                if ($toriConfluence.audit_log) {
                    Write-Host "  [TORI AUDIT]`n$($toriConfluence.audit_log)" -ForegroundColor DarkGray
                }

                $__override = $null
                if (Get-Command Test-MentorOverride -ErrorAction SilentlyContinue) {
                    $__override = Test-MentorOverride -Market $mkt -GateTag "tori_confluence" -GateReason "confluence=$($toriConfluence.confluence_score) < 80" `
                        -Direction $direction -Price $price -Change24h $gemChange24h -Regime "$($btcScenario.scenario)"
                }
                if ($__override -and $__override.approved) {
                    Write-Host "  [MENTOR OVERRIDE] $mkt -- $($__override.motivo)" -ForegroundColor Magenta
                } else {
                    return [PSCustomObject]@{ blocked = $true; blocked_by = @("tori_confluence_$($toriConfluence.confluence_score)_lt_80"); market = $mkt }
                }
            }

            Write-Host "  [TORI CONFLUENCE OK] ${mkt}: technical entry validated (confluence=$($toriConfluence.confluence_score))" -ForegroundColor Green
        } catch {
            Write-Host "  [TORI CONFLUENCE ERROR] ${mkt}: $_ (fallback: allow)" -ForegroundColor Yellow
            # Fail-gracious: if Tori gate fails, allow (other gates still active)
        }
    }

    # ── 2a. CONVICTION GATE (2026-06-18: entrada dinamica, mesa score override) ──
    # Checkpoint NOVO: conviction check ANTES de Tori (filtra low-conviction trades)
    # Mesa score 75+ = bypass conviction entirely (elite confluence)
    # Mesa score 60-75 = use conviction threshold 40 (strong signal)
    # Mesa score <60 = use conviction threshold 50 (standard)
    #
    # 2026-07-23 FIX (auditoria "100% integro"): $Gem.conviction NUNCA e
    # populado por nenhum gerador de candidato real (gem_agent.ps1,
    # gem_scanner_executor_live.ps1, gem_loop.ps1 -- confirmado por grep,
    # zero matches). $Gem.mesa_score idem. Consequencia: a Regra 3 de
    # Test-ConvictionGate (ambos<=0 -> allow, "conviction calc deferred")
    # era SEMPRE o caminho tomado -- o gate nunca bloqueou nada em producao,
    # apesar do log [CONVICTION PASS] sugerir avaliacao real.
    # $conviction_ensemble ja e calculado mais abaixo (secao 2026-06-17
    # CONVICTION OVERRIDE, usa Get-MarketConviction) mas só DEPOIS deste
    # gate e só para vencer um SKIP do Tori -- nunca alimentava esta
    # checagem. Fix: computa o ensemble AQUI (mesmo custo de API que ja
    # era pago mais abaixo -- reutilizado la, sem chamada duplicada) e usa
    # o valor real em vez do sempre-zero.
    $__mesaGemPreCalc = if ($Gem.PSObject.Properties['mesa_score']) { [int]$Gem.mesa_score } else { 0 }
    $convictionEnsembleResult = $null
    if ((Get-Command Get-MarketConviction -ErrorAction SilentlyContinue) -and -not $isDataAbsent) {
        try {
            $convictionEnsembleResult = Get-MarketConviction -Market $mkt -Direction $direction -IsFutures $hasFutures
        } catch { }
    }
    if (Get-Command Test-ConvictionGate -ErrorAction SilentlyContinue) {
        try {
            $mesa_score = $__mesaGemPreCalc
            $conviction = if ($convictionEnsembleResult -and $convictionEnsembleResult.PSObject.Properties['conviction']) {
                [int]$convictionEnsembleResult.conviction
            } elseif ($Gem.PSObject.Properties['conviction']) {
                [int]$Gem.conviction
            } else {
                0
            }

            if (-not (Test-ConvictionGate -conviction $conviction -mesa_score $mesa_score)) {
                Write-Host "  [CONVICTION BLOCKED] ${mkt}: conviction=$conviction mesa=$mesa_score (fails dynamic threshold)" -ForegroundColor Yellow
                $__override = $null
                if (Get-Command Test-MentorOverride -ErrorAction SilentlyContinue) {
                    $__override = Test-MentorOverride -Market $mkt -GateTag "conviction_gate_failed" -GateReason "conviction=$conviction mesa=$mesa_score" `
                        -Direction $direction -Price $price -Change24h $gemChange24h -Regime "$($btcScenario.scenario)"
                }
                if ($__override -and $__override.approved) {
                    Write-Host "  [MENTOR OVERRIDE] $mkt -- $($__override.motivo)" -ForegroundColor Magenta
                } else {
                    return [PSCustomObject]@{ blocked = $true; blocked_by = @("conviction_gate_failed_$conviction`_mesa_$mesa_score"); market = $mkt }
                }
            } else {
                Write-Host "  [CONVICTION PASS] ${mkt}: conviction=$conviction mesa=$mesa_score" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "  [CONVICTION CHECK ERROR] ${mkt}: $_ (fallback: allow)" -ForegroundColor Yellow
            # Fallback: if conviction check fails, allow trade (fail-open for robustness)
        }
    } else {
        Write-Host "  [CONVICTION WARN] Test-ConvictionGate not available (lib_gates_drift_wire not loaded)" -ForegroundColor Yellow
    }

    # ── 2. TORI GATE (qualidade tecnica de trendline; ENTER|SKIP|WAIT) ───────
    # Bloqueia GEMs sem ancora tecnica antes de comprometer capital. Defensivo:
    # qualquer falha upstream (Claude indisponivel, exception) aborta o trade.
    # 2026-06-03: Validacao da funcao antes de chamar.
    if (-not (Get-Command Get-ToriTrendlineSignal -ErrorAction SilentlyContinue)) {
        Write-Host "  [GEM BLOQUEADO] ${mkt}: Get-ToriTrendlineSignal nao disponivel (carregamento falhou)" -ForegroundColor Red
        try { Send-TelegramAlert -Message "GEM bloqueado: $mkt -- Get-ToriTrendlineSignal nao carregou. Restart necessario." | Out-Null } catch {}
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("tori_unavailable"); market = $mkt }
    }

    $tori_signal = "ENTER"
    $tori_conviction = 0
    $tori_reason = ""
    $tori_tech_sinal = ""
    $tori_llm_fallback = $false
    try {
        $tori = Get-ToriTrendlineSignal -Market $mkt
        $tori_conviction = if ($tori.PSObject.Properties['conviction']) { [int]$tori.conviction } else { 0 }
        # 2026-06-12: respeita o signal do Tori (SKIP explicito bloqueia de novo).
        # Bypass "sempre ENTER" de 2026-06-11 custou TRUMPUSDT -4.4% (Tori dizia SKIP).
        $tori_signal = if ($tori.PSObject.Properties['signal']) { "$($tori.signal)".ToUpper() } else { "ENTER" }
        $tori_reason = "$($tori.reason)"
        # 2026-06-21: direcao tecnica + flag de fallback p/ o gate de qualidade fail-closed
        $tori_tech_sinal = if ($tori.PSObject.Properties['tech_sinal']) { "$($tori.tech_sinal)" } else { "" }
        $tori_llm_fallback = [bool]($tori.PSObject.Properties['llm_fallback'] -and $tori.llm_fallback)
    } catch {
        Write-Host "  [GEM TORI ERROR] ${mkt}: $_" -ForegroundColor Red
        try { Send-TelegramAlert -Message "GEM bloqueado por Tori (error): $mkt -- $_" | Out-Null } catch {}
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("tori_error:$($_.Exception.Message)"); market = $mkt }
    }
    if ($tori_signal -in @("SKIP","WAIT")) {
        $tag = "tori:" + $tori_signal.ToLower() + ":" + $tori_reason
        Write-Host "  [GEM TORI BLOCK] ${mkt}: $tag" -ForegroundColor Red

        # 2026-05-18 Opcao C: SKIP por DADOS AUSENTES vira log silencioso (nao spam TG).
        # 2026-05-21 fix: ainda retorna PSCustomObject blocked pra caller saber motivo.
        $reasonLower = "$tori_reason".ToLower()
        $isDataAbsent = ($reasonLower -match "n/a|no_trendline_data|no_verdict|tech_agent_null|impossivel identificar|impossível identificar|sem dados|sem pontos de ancoragem|retornaram n/a")

        # 2026-06-09: Captura skip pra counterfactual learning (se tem entry_price)
        if (-not $isDataAbsent -and (Get-Command Write-SignalSkip -ErrorAction SilentlyContinue)) {
            $regime = if ($global:MARKET_REGIME) { "$($global:MARKET_REGIME)" } else { "UNKNOWN" }
            try { Write-SignalSkip -Market $mkt -Direction "LONG" -Gate "tori_$($tori_signal.ToLower())" -EntryPrice $price -Regime $regime -Source "tori" | Out-Null } catch {}
        }

        # A. MISSED log enriquecido 2026-05-22: quando Tori SKIP por timing missed,
        # cruza com snapshot tori_proximity pra capturar setup_ripening pre-spike.
        # Zero LLM, zero risco LIVE -- so observa SKIP que ja aconteceu pra dataset
        # decidir "afrouxar 16% threshold" data-driven em 7 dias.
        $isTimingMissed = ($reasonLower -match "missed|ja se distanciou|ja rompeu|distancia significativa|overbought extremo|chase|distanciou.*line")
        if ($isTimingMissed -and (Get-Command Get-ToriProximityForMarket -ErrorAction SilentlyContinue)) {
            try {
                $statePath = Join-Path $global:JOURNAL_DIR "tori_proximity_state.json"
                $missedPath = Join-Path $global:JOURNAL_DIR "missed_setups.jsonl"
                $tp = Get-ToriProximityForMarket -Market $mkt -StatePath $statePath -MaxAgeMinutes 60
                $entry = [ordered]@{
                    ts_skip          = (Get-Date).ToUniversalTime().ToString("o")
                    market           = $mkt
                    tori_reason      = "$tori_reason".Substring(0, [Math]::Min(200, "$tori_reason".Length))
                    proximity_snap   = if ($tp) { [ordered]@{
                        ts_snap        = if ($tp.PSObject.Properties['ts_utc']) { "$($tp.ts_utc)" } else { $null }
                        side           = "$($tp.side)"
                        proximity_pct  = $tp.proximity_pct
                        action_line    = $tp.action_line
                        slope_deg      = $tp.slope_deg
                        rsi            = $tp.rsi
                        vol_drying     = $tp.vol_drying
                        setup_ripening = [bool]$tp.setup_ripening
                    } } else { $null }
                    snapshot_present = ($null -ne $tp)
                }
                $dir = Split-Path -Parent $missedPath
                if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                Add-Content -Path $missedPath -Value ($entry | ConvertTo-Json -Compress -Depth 4) -Encoding UTF8
            } catch {}
        }

        # ── 2026-06-17: CONVICTION OVERRIDE (destrava Tori veta-tudo) ───────────
        # Se o ensemble (multi-TF gradiente + BTC relative strength) der conviccao
        # alta, o SKIP do Tori e vencido. FAIL-SAFE: so com CONVICTION_GATE.flag;
        # nunca overrida dados-ausentes; loga a decisao. Default OFF.
        $toriOverridden = $false
        $convictionEvaluated = $false
        $__gateFlag = Join-Path $PSScriptRoot "..\journal\CONVICTION_GATE.flag"
        if ((Test-Path $__gateFlag) -and -not $isDataAbsent -and (Get-Command Resolve-ConvictionOverride -ErrorAction SilentlyContinue)) {
            try {
                # 2026-07-23: reusa o ensemble ja calculado no Conviction Gate (secao
                # 2a acima) -- evita 4 chamadas de API duplicadas pro mesmo market/direcao.
                $convM = if ($convictionEnsembleResult) { $convictionEnsembleResult } else { Get-MarketConviction -Market $mkt -Direction $direction -IsFutures $hasFutures }
                if ($convM) {
                    $convictionEvaluated = $true
                    # 2026-07-26: threshold dinamico por momentum (pedido do owner).
                    # A MEDIA ponderada (conviction) pode diluir um sinal forte quando
                    # so 1-2 dos 6-7 eixos tem peso alto -- caso real SOLUSDT:
                    # conviction=60.7 (bloqueado em 75) mas multitf/btc_rs ja fortes
                    # individualmente. Conta quantos eixos PRESENTES bateram >=80
                    # (confirmacao em multiplas dimensoes ortogonais independentes,
                    # nao so a media unica) -- com 2+, threshold cai 75->60.
                    $__strongAxes = 0
                    if ($convM.axes_detail) {
                        foreach ($__axKey in $convM.axes_detail.Keys) {
                            if ([double]$convM.axes_detail[$__axKey] -ge 80) { $__strongAxes++ }
                        }
                    }
                    $ovr = Resolve-ConvictionOverride -ToriSignal $tori_signal -Conviction $convM.conviction -DataAbsent $false -FlagOn $true -Threshold 75 -StrongAxesCount $__strongAxes
                    if ($ovr.allow) {
                        $toriOverridden = $true
                        Write-Host "  [CONVICTION OVERRIDE] ${mkt}: $($ovr.reason) (eixos: $($convM.axes_detail.Keys -join ','))" -ForegroundColor Green
                        try { Send-TelegramAlert -Message "CONVICCAO venceu Tori: $mkt $direction conv=$($convM.conviction)/100 (Tori dizia $tori_signal)" | Out-Null } catch {}
                    } else {
                        Write-Host "  [CONVICTION] ${mkt}: nao override ($($ovr.reason)) -- axes_detail: $($convM.axes_detail | ConvertTo-Json -Compress)" -ForegroundColor DarkGray
                    }
                }
            } catch { Write-Host "  [CONVICTION ERROR] ${mkt}: $_" -ForegroundColor DarkGray }
        }

        if (-not $toriOverridden) {
            if ($isDataAbsent) {
                Write-Host "  [GEM TORI SKIP-SILENT] ${mkt}: dados ausentes -- nao spam TG" -ForegroundColor DarkYellow
            } else {
                try { Send-TelegramAlert -Message "GEM bloqueado por Tori ($tori_signal): $mkt -- $tori_reason" | Out-Null } catch {}
            }
            # C fix 2026-05-21: TTL cache pra prevenir loop re-aprovacao em market sem dados.
            # 2026-06-17: se o gate de conviction RODOU e nao aprovou, cacheia
            # "conviction_low" (NAO bypassed) -> nao re-avalia todo ciclo (evita loop).
            # Senao mantem tori_skip (que e bypassed quando gate on -> re-avalia).
            if (Get-Command Add-GemRejection -ErrorAction SilentlyContinue) {
                $cacheReason = if ($isDataAbsent) { "tori_data_absent" }
                               elseif ($convictionEvaluated) { "conviction_low_$($tori_signal.ToLower())" }
                               else { "tori_$($tori_signal.ToLower())" }
                try { Add-GemRejection -Path (Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json") -Market $mkt -Reason $cacheReason } catch {}
            }
            return [PSCustomObject]@{ blocked = $true; blocked_by = @("tori_$($tori_signal.ToLower())_$tori_reason"); market = $mkt; tori_data_absent = $isDataAbsent }
        }
    }

    # ── 3. CALCULATE STOP/TARGET (precision math, fix sub-dollar 2026-05-14) ──
    # Decimal-based; serializa InvariantCulture. So acontece se safety + tori passaram.
    # Consulta precision de mercado ANTES (cache 1h) -- garante que sub-dollar tokens
    # arredondem na precisao correta (AIUSDT spot: quote_ccy_precision=6+).
    $precType   = if ($hasFutures) { "futures" } else { "spot" }
    $precision  = $null
    try {
        $precision = Get-MarketPrecision -Market $mkt -MarketType $precType
    } catch {
        Write-Host "  [PRECISION WARN] ${mkt}: Get-MarketPrecision falhou ($_); usando fallback 8 casas" -ForegroundColor Yellow
    }
    $pricePrec = if ($precision -and $precision.quote_ccy_precision) {
        [int]$precision.quote_ccy_precision
    } else {
        Write-Host "  [PRECISION WARN] ${mkt}: precision indisponivel; fallback quote=8" -ForegroundColor Yellow
        8
    }
    $basePrec  = if ($precision -and $precision.base_ccy_precision) { [int]$precision.base_ccy_precision } else { 6 }
    $cachedTag = if ($precision) { "true" } else { "false" }
    Write-Host "  [PRECISION] $mkt $precType quote=$pricePrec base=$basePrec cached=$cachedTag" -ForegroundColor DarkGray

    # 2026-07-08 FIX: Remove viés LONG automático. Decide direção via conviction multi-TF.
    # Bug: entrada sem direction property default LONG, perdendo SHORTs óbvios (CRCLX case).
    # Solução: se direction explícita, use. Senão, decide via convictions + pump-fade detector.
    #
    # 2026-07-28 FIX (achado real: SUIUSDT com direction=LONG->SHORT resolvida
    # via MENTOR OVERRIDE no gate breadth_long_blocked -- 3 gates ja aprovaram
    # SHORT -- mas esta secao SEMPRE resetava $direction="SKIP" e recalculava
    # do zero via conviction multi-TF, DESCARTANDO a decisao do Mentor. O
    # recalculo local (pump-fade/RSI/regime bias, sem LLM) reavaliou o
    # candidato como LONG de novo, e o gate seguinte (multi_tf_misalignment)
    # bloqueou por STRONG_DOWN nos 3 timeframes -- que so faz sentido pra
    # LONG, nao pro SHORT que o Mentor ja tinha aprovado com contexto pleno.
    # Fix: se $direction ja foi resolvida como SHORT (override anterior ja
    # rodou e passou), pula o recalculo -- a decisao do Mentor (LLM com mais
    # contexto que este calculo local) e a fonte de verdade mais recente.
    if ($direction -eq "SHORT") {
        Write-Host "  [DIRECTION] Preservada (ja resolvida via override anterior): $direction" -ForegroundColor DarkYellow
    } elseif ($Gem.PSObject.Properties['direction'] -and "$($Gem.direction)" -in @("LONG","SHORT")) {
        $direction = "$($Gem.direction)".ToUpper()
        Write-Host "  [DIRECTION] Explícita no GEM: $direction" -ForegroundColor DarkYellow
    } else {
        # Sem direção explícita: calcular convictions LONG e SHORT
        $longConv = 50
        $shortConv = 50

        # Detect pump-fade pattern (ativo blocker para LONG)
        $isPumpFade = $false
        $pumpDetectScore = 0
        if (Get-Command Detect-EarlyPump -ErrorAction SilentlyContinue) {
            try {
                $pdChange = if ($null -ne $Gem.change_24h) { [double]$Gem.change_24h } else { 0 }
                # 2026-07-16 FIX: campo real e "spike_ratio", nao "volume_ratio"
                $pdVolR   = if ($null -ne $Gem.vol_data.spike_ratio) { [double]$Gem.vol_data.spike_ratio } else { 1.0 }
                $pdRsi    = if ($null -ne $Gem.rsi_14) { [double]$Gem.rsi_14 } else { 50 }
                $pumpDetect = Detect-EarlyPump -Market $mkt -ChangePercent24h $pdChange -VolumeRatio $pdVolR -RSI $pdRsi -CurrentPrice $price
                # 2026-07-16 FIX: "late" e o equivalente real de "FADE|TOP" (ver fix
                # acima na 1a ocorrencia deste padrao)
                if ($pumpDetect.is_pump -and $pumpDetect.pump_stage -match "late") {
                    $isPumpFade = $true
                    $pumpDetectScore = [int]$pumpDetect.confidence
                    $shortConv = [math]::Min(100, $pumpDetectScore + 20)  # pump-fade = SHORT favorecido
                    $longConv = [math]::Max(0, 50 - $pumpDetectScore)    # LONG desfavorecido
                }
            } catch { }
        }

        # Overextension + RSI check (mean-reversion SHORT favorecido)
        if (-not $isPumpFade -and $prices.Count -ge 20) {
            try {
                $rsi = if ($null -ne $Gem.rsi_14) { [double]$Gem.rsi_14 } else { 50 }
                if ($rsi -gt 65) {
                    # Overbought: SHORT melhor
                    $shortConv += 15
                    $longConv = [math]::Max($longConv - 10, 30)
                    Write-Host "  [OVEREXTENSION] RSI=$rsi (overbought) -> SHORT favorecido" -ForegroundColor DarkYellow
                } elseif ($rsi -lt 35) {
                    # Oversold: LONG melhor
                    $longConv += 15
                    $shortConv = [math]::Max($shortConv - 10, 30)
                    Write-Host "  [OVERSOLD] RSI=$rsi (oversold) -> LONG favorecido" -ForegroundColor DarkYellow
                }
            } catch { }
        }

        # Apply regime bias
        if ($global:CURRENT_REGIME -match "BEAR") {
            # BEAR: SHORT mais favorecido
            $shortConv += 10
            $longConv = [math]::Max($longConv - 5, 40)
        } elseif ($global:CURRENT_REGIME -match "BULL") {
            # BULL: LONG mais favorecido
            $longConv += 10
            $shortConv = [math]::Max($shortConv - 5, 40)
        }

        # Clamp to 0-100
        $longConv = [math]::Min([math]::Max([int]$longConv, 0), 100)
        $shortConv = [math]::Min([math]::Max([int]$shortConv, 0), 100)

        # Usar Resolve-EntryDirection (fail-closed)
        if (Get-Command Resolve-EntryDirection -ErrorAction SilentlyContinue) {
            try {
                $dirDecision = Resolve-EntryDirection -AllowLong $btcScenario.allow_long -AllowShort $btcScenario.allow_short `
                    -LongConviction $longConv -ShortConviction $shortConv -MinConviction 45
                if ($dirDecision.act) {
                    $direction = $dirDecision.direction
                    Write-Host "  [DIRECTION] Resolvida via conviction: $direction (Long=$longConv Short=$shortConv, motivo: $($dirDecision.reason))" -ForegroundColor DarkYellow
                } else {
                    Write-Host "  [DIRECTION] SKIP — nenhum lado com conviction suficiente (L=$longConv S=$shortConv < 45 minimo)" -ForegroundColor DarkGray
                    $direction = "SKIP"
                }
            } catch {
                Write-Host "  [DIRECTION] Resolve-EntryDirection falhou ($_); fallback conservador: SKIP" -ForegroundColor Yellow
                $direction = "SKIP"
            }
        } else {
            # Fallback: se uma conviction é significativamente maior, usa
            if ([math]::Abs($shortConv - $longConv) -ge 20) {
                $direction = if ($shortConv -gt $longConv) { "SHORT" } else { "LONG" }
                Write-Host "  [DIRECTION] Fallback (Resolve-EntryDirection NA): $direction (conviction gap=$([math]::Abs($shortConv - $longConv)))" -ForegroundColor Yellow
            } else {
                $direction = "SKIP"
                Write-Host "  [DIRECTION] Fallback SKIP — convictions próximas (L=$longConv S=$shortConv)" -ForegroundColor DarkGray
            }
        }
    }

    # Block se SKIP (falha-fechado: sem direção clara = não entra)
    if ($direction -eq "SKIP") {
        Write-Host "  BLOQUEADO: Nenhuma direção com confidence suficiente" -ForegroundColor Red
        $__override = $null
        if (Get-Command Test-MentorOverride -ErrorAction SilentlyContinue) {
            # Sem direcao clara pra passar ao mentor -- usa a de maior conviction
            # entre LONG/SHORT so pra montar o Setup da consulta (nao afeta o
            # resultado real, so o mentor decide se aprova ou nao).
            $__dirCandidate = if ($shortConv -gt $longConv) { "SHORT" } else { "LONG" }
            $__override = Test-MentorOverride -Market $mkt -GateTag "no_direction_confidence" -GateReason "L=$longConv S=$shortConv, nenhuma com confidence suficiente" `
                -Direction $__dirCandidate -Price $price -Change24h $gemChange24h -Regime "$($btcScenario.scenario)"
        }
        if ($__override -and $__override.approved) {
            $direction = $__dirCandidate
            Write-Host "  [MENTOR OVERRIDE] $mkt -- $($__override.motivo) -- direction=$direction" -ForegroundColor Magenta
        } else {
            return [PSCustomObject]@{ blocked = $true; blocked_by = @("no_direction_confidence"); market = $mkt }
        }
    }
    $direction = if ($direction -in @("LONG","SHORT")) { $direction } else { "LONG" }  # safety check

    # 2026-07-16 FIX (auditoria agent a395f05e): SHORT so existe via FUTURES
    # (venda a descoberto nao existe em SPOT sem margem). A rota (linha ~558,
    # Get-GemRouteForMarket) e decidida ANTES da direcao final ser conhecida
    # aqui -- modo GEM prefere SPOT por padrao (Get-RouteForMode, intencional
    # p/ LONG pequeno sem leverage), entao se a direcao resolvida via
    # conviction ensemble for SHORT mas a rota ja escolheu spot, o codigo
    # tentaria Invoke-OrderRouted -Route spot -Side sell -- venda a descoberto
    # invalida (a CoinEx rejeitaria por saldo insuficiente, mas nao e um
    # bloqueio limpo/intencional, so falha externa). Fix: reforcar rota pra
    # futures se SHORT e futures disponivel; bloquear explicitamente (fail
    # -closed) se SHORT e SOMENTE spot disponivel.
    if ($direction -eq "SHORT" -and $marketType -ne "FUTURES") {
        # 2026-07-16 FIX rodada 2 (achado real via forced-test-trade ETHUSDT
        # SHORT, run 29444619342): checava $hasFutures ("rota atual e
        # futures", sempre $false aqui pq acabamos de confirmar
        # marketType != FUTURES) em vez de $futuresAvailable ("mercado TEM
        # futures", o dado que realmente importa). Bloqueava SHORT com a
        # mensagem enganosa "so tem SPOT disponivel" mesmo com futures
        # disponivel de verdade -- confirmado no log real: "[Route] ETHUSDT
        # -> spot (spot=True fut=True)" seguido de bloqueio incorreto.
        if ($futuresAvailable) {
            Write-Host "  [ROUTE OVERRIDE] ${mkt}: SHORT exige futures -- corrigindo rota de spot para futures" -ForegroundColor DarkYellow
            $marketType = "FUTURES"
            $hasFutures = $true
        } else {
            Write-Host "  BLOQUEADO: SHORT requer futures, mas $mkt so tem SPOT disponivel" -ForegroundColor Red
            return [PSCustomObject]@{ blocked = $true; blocked_by = @("short_requires_futures_spot_only"); market = $mkt }
        }
    }

    # 2026-08-02: LONG-FUTURES "serio" (owner pediu: percebeu que LONG nunca
    # abre em futures, so SHORT -- Get-RouteForMode com modo GEM sempre
    # prefere spot por design, "sizing pequeno sem leverage = risco
    # controlado"). Diferente do override SHORT acima (OBRIGATORIO -- SHORT
    # so existe via futures), este e OPCIONAL: so promove LONG pra futures
    # se o ativo tiver qualidade fundamentalista suficiente (FQS BLUE_CHIP
    # ou QUALITY -- mesmo criterio ja usado pro gate TIER_A_LIVE/
    # TIER_B_PAPER, nunca conectado ao roteamento em si ate agora). Decisao
    # extraida pra Test-LongFuturesRouteEligible (lib_long_futures_route.ps1,
    # logica pura testavel) -- sem FQS suficiente, mantem SPOT (comportamento
    # atual preservado, zero regressao pro caminho GEM pequeno). Fail-closed:
    # qualquer erro ao consultar FQS mantem SPOT (categoria fica $null).
    $__longFqsCategory = $null
    if (Get-Command Get-FundamentalScore -ErrorAction SilentlyContinue) {
        try { $__longFqsCategory = (Get-FundamentalScore -Market $mkt).category } catch {}
    }
    if (Get-Command Test-LongFuturesRouteEligible -ErrorAction SilentlyContinue) {
        $__promoteLongFutures = Test-LongFuturesRouteEligible -Direction $direction -MarketType $marketType `
            -FuturesAvailable $futuresAvailable -FqsCategory $__longFqsCategory
        if ($__promoteLongFutures) {
            Write-Host "  [ROUTE OVERRIDE] ${mkt}: LONG com FQS=$__longFqsCategory -- promovendo rota de spot para futures" -ForegroundColor DarkYellow
            $marketType = "FUTURES"
            $hasFutures = $true
        }
    }

    # 2026-06-17 fix: gems TRIGGER tem sizing sem stop_pct/target_pct -> StopPct=0 lancava.
    # Resolve-StopTargetPct devolve fracoes validas (default R:R 1:5) se ausentes/invalidas.
    #
    # 2026-07-17 FIX (achado #1 do audit de R:R): passava -Sizing $Gem (objeto TOPO),
    # mas stop_pct/target_pct SEMPRE vivem em $Gem.sizing.stop_pct (Get-GemSizing em
    # gem_agent.ps1 linha ~1055: Add-Member -NotePropertyName sizing -NotePropertyValue $sz).
    # $Gem.stop_pct no nivel raiz nunca existiu -- nem em TRIGGER (scripts/gem_loop.ps1
    # linha 315: sizing=@{sizing_pct=0.02}, tambem aninhado). Resultado real: TODO trade
    # DISCOVERY/MOMENTUM caia no default (stop=2%, target=10%) e IGNORAVA silenciosamente
    # os -50%/+200% e -30%/+90% configurados em config.ps1 GEM_STOP_*/GEM_TARGET_*.
    # Reproduzido localmente: Resolve-StopTargetPct -Sizing $gem (com .sizing.stop_pct=0.50)
    # devolvia stop_pct=0.02 antes deste fix. Fix: ler $Gem.sizing (fallback pro proprio
    # $Gem se .sizing nao existir, cobre formatos antigos/desconhecidos).
    $__sizingSrc = if ($Gem.PSObject.Properties['sizing'] -and $Gem.sizing) { $Gem.sizing } else { $Gem }
    $__stp = if (Get-Command Resolve-StopTargetPct -ErrorAction SilentlyContinue) {
        Resolve-StopTargetPct -Sizing $__sizingSrc
    } else {
        @{ stop_pct = (&{ if ([double]$__sizingSrc.stop_pct -gt 0 -and [double]$__sizingSrc.stop_pct -lt 1) { [double]$__sizingSrc.stop_pct } else { 0.02 } });
           target_pct = (&{ if ([double]$__sizingSrc.target_pct -gt 0) { [double]$__sizingSrc.target_pct } else { 0.10 } }) }
    }

    # 2026-07-29: calibragem autonoma de R:R por regime+direcao (owner pediu
    # "calibrar conforme regime autonomo" -- refinar dependendo do movimento/
    # tendencia real do preco, nao um numero fixo pra todo mundo). Mantem
    # stop_pct INTACTO (reflete volatilidade natural da categoria DISCOVERY/
    # MOMENTUM + risco por trade ja calculado via GEM_CAPITAL_*) -- so
    # recalibra target_pct, trocando o multiplicador fixo GEM_MIN_RR (1:5
    # sempre) pelo R:R real medido em mce_counterfactual_agg pra este par
    # regime+direction especifico (edge forte hit_rate>=85% -> 1:3, edge
    # moderado 60-85% -> 1:4, sem edge medido confiavel -> mantem 1:5 --
    # Regra de Ouro #3 nunca fica MAIS frouxa que o piso quando falta dado).
    # Fail-soft: Get-Command guard + Resolve-RegimeRRCalibration nunca lanca
    # (cai no default se Supabase/mce_counterfactual_agg indisponivel).
    if (Get-Command Resolve-RegimeRRCalibration -ErrorAction SilentlyContinue) {
        try {
            $__regimeForRR = if ($btcScenario -and $btcScenario.scenario) { [string]$btcScenario.scenario } else { "UNKNOWN" }
            $__rrCalib = Resolve-RegimeRRCalibration -Regime $__regimeForRR -Direction $direction -DefaultRR $global:GEM_MIN_RR
            if ($__rrCalib -and $__rrCalib.rr_min -gt 0) {
                $__stp = @{ stop_pct = [double]$__stp.stop_pct; target_pct = [double]$__stp.stop_pct * [double]$__rrCalib.rr_min }
                if ($__rrCalib.tier -ne "SEM_EDGE_MEDIDO") {
                    Write-Host "  [RR CALIBRATION] $mkt regime=$__regimeForRR dir=$direction tier=$($__rrCalib.tier) -> R:R=1:$($__rrCalib.rr_min) ($($__rrCalib.reason))" -ForegroundColor Cyan
                }
            }
        } catch {
            Write-Host "  [RR CALIBRATION] falhou p/ $mkt (mantem default): $_" -ForegroundColor DarkYellow
        }
    }

    try {
        $st = Calculate-StopTarget `
            -Entry     ([double]$price) `
            -StopPct   ([double]$__stp.stop_pct) `
            -TargetPct ([double]$__stp.target_pct) `
            -Direction $direction `
            -Precision $pricePrec
    } catch {
        Write-Host "BLOQUEADO: Calculate-StopTarget falhou para ${mkt}: $_" -ForegroundColor Red
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("calculate_stoptarget_error:$($_.Exception.Message)"); market = $mkt }
    }
    $stop_price  = $st.stop_price
    $tgt_price   = $st.target_price
    $stop_pct_display   = [math]::Round($__stp.stop_pct * 100, 0)
    $target_pct_display = [math]::Round($__stp.target_pct * 100, 0)

    Write-Host "  Stop       : $stop_price  (-${stop_pct_display}%)" -ForegroundColor Red
    Write-Host "  Target     : $tgt_price   (+${target_pct_display}%)" -ForegroundColor Green
    Write-Host "  Tori       : $tori_signal ($tori_reason)" -ForegroundColor DarkGreen

    # ── 3.5 ENTRY QUALITY GATE (2026-06-21: FAIL-CLOSED, Regra de Ouro #5) ───────
    # Fecha as brechas vistas no run #677: comprar contra o sinal tecnico (SHORT-FORTE
    # em LONG) e entrada cega (LLM caido + conviction 0 + chart sem dados).
    # Desligavel via ENTRY_QUALITY_GATE_OFF.flag (default ON = protege capital real).
    if ((Get-Command Test-EntryQualityGate -ErrorAction SilentlyContinue) -and
        -not (Test-Path (Join-Path $global:JOURNAL_DIR "ENTRY_QUALITY_GATE_OFF.flag"))) {
        $gConv  = if ($Gem.PSObject.Properties['conviction']) { [int]$Gem.conviction } else { [int]$tori_conviction }
        $gMesa  = if ($Gem.PSObject.Properties['mesa_score'])  { [int]$Gem.mesa_score }  else { 0 }
        $gChart = if ($chart -and $chart.PSObject.Properties['reason']) { "$($chart.reason)" } else { "" }
        $qg = Test-EntryQualityGate -TradeDirection $direction -TechConsensus $tori_tech_sinal `
                -LlmFallback $tori_llm_fallback -Conviction $gConv -MesaScore $gMesa -ChartStatus $gChart
        if ($qg.blocked) {
            $qreason = ($qg.reasons -join ",")
            Write-Host "  [QUALITY GATE BLOCK] ${mkt}: $qreason (dir=$direction tech=$tori_tech_sinal llm_fallback=$tori_llm_fallback conv=$gConv mesa=$gMesa)" -ForegroundColor Red
            if (Get-Command Write-SignalSkip -ErrorAction SilentlyContinue) {
                $regimeQ = if ($global:MARKET_REGIME) { "$($global:MARKET_REGIME)" } else { "UNKNOWN" }
                try { Write-SignalSkip -Market $mkt -Direction $direction -Gate "quality_gate" -EntryPrice $price -Regime $regimeQ -Source "entry_quality_gate" | Out-Null } catch {}
            }
            $__override = $null
            if (Get-Command Test-MentorOverride -ErrorAction SilentlyContinue) {
                $__override = Test-MentorOverride -Market $mkt -GateTag "quality_gate" -GateReason $qreason `
                    -Direction $direction -Price $price -Change24h $gemChange24h -Regime "$($btcScenario.scenario)"
            }
            if ($__override -and $__override.approved) {
                Write-Host "  [MENTOR OVERRIDE] $mkt -- $($__override.motivo)" -ForegroundColor Magenta
            } else {
                return [PSCustomObject]@{ blocked = $true; blocked_by = @("quality_gate:$qreason"); market = $mkt }
            }
        }
        Write-Host "  [QUALITY GATE PASS] ${mkt}: dir=$direction tech=$tori_tech_sinal conv=$gConv mesa=$gMesa" -ForegroundColor DarkGray
    }

    # ── 4. EXIT LADDER (multi TP/SL knowledge-driven) ───────────────────────────
    # Decide template baseado em context (GEM/STANDARD/regime/spike) e instancia.
    # Defensive: se Get-ExitLadder nao estiver carregado, segue trade legacy (1 TP).
    $ladder      = $null
    $ladderTplId = $null
    if (Get-Command Get-ExitLadder -ErrorAction SilentlyContinue) {
        $setupForLadder = [PSCustomObject]@{
            score       = $Gem.score
            market_type = $marketType
            vol_data    = $vd
        }
        try {
            $ladderTplId = Get-LadderTemplateForSetup -Setup $setupForLadder -Regime "" -GemMode $true
            $ladder      = Get-ExitLadder -TemplateId $ladderTplId -Entry ([decimal]$price) -AtrValue ([decimal]0)
            $tpsCount    = if ($ladder -and $ladder.tp_levels) { @($ladder.tp_levels).Count } else { 0 }
            $slsCount    = if ($ladder -and $ladder.sl_levels) { @($ladder.sl_levels).Count } else { 0 }
            $beAfter     = if ($ladder.PSObject.Properties['breakeven_after_tp']) { $ladder.breakeven_after_tp } else { 0 }
            Write-Host "  [LADDER] $mkt template=$ladderTplId tps=$tpsCount sls=$slsCount breakeven_after=$beAfter" -ForegroundColor Cyan
        } catch {
            Write-Host "  [LADDER WARN] Get-ExitLadder falhou para ${mkt}: $_ (segue legacy single TP)" -ForegroundColor Yellow
            $ladder = $null
        }
    }

    if ($DryRun) {
        Write-Host "  [DRY RUN] Ordem NAO enviada." -ForegroundColor DarkYellow
        Write-GemTradeJournal -Market $mkt -Price $price -Qty $qty -StopPrice $stop_price `
            -TargetPrice $tgt_price -SizingUsd $usd_size -GemScore $Gem.score `
            -Mode $Gem.mode -MarketType $marketType -DryRun $true -ToriSignal $tori_signal
        if ($ladder -and (Get-Command Add-LadderEntryRecord -ErrorAction SilentlyContinue)) {
            try {
                Add-LadderEntryRecord -Market $mkt -TemplateId $ladderTplId -Regime "GEM" `
                    -Entry $price -AtrValue 0 `
                    -TpsCount (@($ladder.tp_levels).Count) -SlsCount (@($ladder.sl_levels).Count) `
                    -Notes "dry_run" | Out-Null
            } catch {}
        }
        return [PSCustomObject]@{
            market              = $mkt
            market_type         = $marketType
            price               = $price
            qty                 = $qty
            stop                = $stop_price
            target              = $tgt_price
            sizing_usd          = $usd_size
            dry_run             = $true
            ladder_template_id  = $ladderTplId
            ladder              = $ladder
        }
    }

    # ── GUARD: Promotion Ladder sizing (Phase 2 2026-05-18) ───────────────────
    # Se market esta na ladder, aplica multiplier por tier_state (25/50/100%).
    # State 0/1 (DESCOBERTA/OBSERVATION) bloqueia trade. Markets fora da ladder
    # caem pra guards antigos abaixo (compat).
    if (Get-Command Resolve-PromotionSizing -ErrorAction SilentlyContinue) {
        $pipelinePath = Join-Path (Split-Path $PSScriptRoot -Parent) "journal\promotion_pipeline.jsonl"
        if (Test-Path $pipelinePath) {
            $ladderSize = Resolve-PromotionSizing -PipelinePath $pipelinePath -Market $mkt -BaseSize $usd_size
            if ($ladderSize.source -eq "ladder") {
                if (-not $ladderSize.allowed) {
                    Write-Host "  [LADDER] $mkt em $($ladderSize.tier_label) -- trade NAO permitido (size=0)" -ForegroundColor DarkYellow
                    return [PSCustomObject]@{
                        market = $mkt; market_type = $marketType
                        price = $price; qty = 0
                        stop = $stop_price; target = $tgt_price
                        sizing_usd = 0; dry_run = $false
                        blocked = $true; blocked_by = @("ladder_tier_$($ladderSize.tier_label)")
                    }
                }
                if ($ladderSize.size_usd -lt $usd_size) {
                    Write-Host "  [LADDER] $mkt sizing $usd_size -> $($ladderSize.size_usd) ($($ladderSize.tier_label))" -ForegroundColor Cyan
                    $usd_size = [double]$ladderSize.size_usd
                    $qty = [Math]::Round($usd_size / $price, 8)
                }
            }
        }
    }

    # ── GUARD: tier whitelist + 4 live guards (2026-05-18) ────────────────────
    # GemAgent agora respeita Mode 2 LIVE guards. Bloqueia GEMs fora Tier A/B em LIVE.
    # 2026-06-03: DISCOVERY mode exempto de tier whitelist (são pares novos por definição)
    if (Get-Command Test-LiveTradeGuards -ErrorAction SilentlyContinue) {
        $tierMode = if ($gem.mode -eq "DISCOVERY") { "ANY" } else {
            if ($global:LIVE_TIER_FILTER) { $global:LIVE_TIER_FILTER } else { "PAPER" }
        }
        $maxSize  = if ($global:LIVE_MAX_SIZE_USD) { [double]$global:LIVE_MAX_SIZE_USD } else { 100.0 }
        $maxFreq  = if ($global:LIVE_MAX_TRADES_PER_WEEK) { [int]$global:LIVE_MAX_TRADES_PER_WEEK } else { 5 }
        $maxCust  = if ($global:LIVE_MAX_CUSTODIAL_RATIO) { [double]$global:LIVE_MAX_CUSTODIAL_RATIO } else { 0.30 }
        $totCap   = if ($global:TOTAL_CAPITAL_USD) { [double]$global:TOTAL_CAPITAL_USD } else { 0 }
        $exchBal  = 0.0
        try { $exchBal = [double](CoinEx-GetTotalCapitalUSDT) } catch {}

        # 2026-08-07 FIX CRITICO: $maxSize acima e um cap fixo em dolar
        # historico (desde o commit inicial do projeto, quando nao havia
        # % dinamico de capital ainda) -- sem este fix, ele bloqueava o
        # trade INTEIRO (via Test-SizingCap, return mais abaixo) antes do
        # "HARD CAP DE RISCO" (mais novo, a Regra de Ouro real, so
        # clampa) rodar mais adiante no arquivo.
        # 2026-08-08 FIX: RiskPct=0.03 hardcoded reintroduzia por engano o
        # valor antigo (owner subiu RISK_MAX_PCT_PER_TRADE de 3% pra 7% no
        # commit 4060d4e/2026-08-04, 3 dias antes deste fix ser escrito sem
        # essa mudanca em vista) -- le a variavel global agora, mesmo padrao
        # ja usado no caminho primario de sizing (linha ~837).
        # 2026-08-14 FIX: Resolve-EffectiveSizingCap deixou de usar "o menor
        # entre cap fixo e risk_pct" -- caso real LINKUSDT (TORI 100/100 +
        # quality gate PASS, tudo aprovado) bloqueado no fim por "$171.14 >
        # cap $100" com capital=$2444.81 (7% real=$171.14, MAIOR que o cap
        # fixo nunca configurado/esquecido desde antes da Regra de Ouro subir
        # pra 7%). Decisao explicita do owner: risk_pct do capital atual E a
        # trava, sem teto fixo em dolar por cima (nem pra capital pequeno nem
        # grande) -- ver Resolve-EffectiveSizingCap pro detalhe completo.
        if (Get-Command Resolve-EffectiveSizingCap -ErrorAction SilentlyContinue) {
            $__riskPctGuard = if ($global:RISK_MAX_PCT_PER_TRADE) { [double]$global:RISK_MAX_PCT_PER_TRADE } else { 0.07 }
            $effCap = Resolve-EffectiveSizingCap -FixedCapUsd $maxSize -Capital $capital -RiskPct $__riskPctGuard
            if ($effCap.cap_usd -ne $maxSize) {
                Write-Host "  [GEM GUARD] $mkt cap efetivo: `$$maxSize (fixo) -> `$$($effCap.cap_usd) ($($__riskPctGuard*100)% capital, Regra de Ouro)" -ForegroundColor Cyan
            }
            $maxSize = [double]$effCap.cap_usd
        }

        # 2026-07-08: overage pequeno (<=10%) clampa pro cap em vez de bloquear.
        # Proposta $102.75 > cap $100 matava o trade inteiro (8 blocks 07-07/08).
        # Overage >10% continua bloqueando via Test-SizingCap (fail-closed).
        if (Get-Command Resolve-SizingClamp -ErrorAction SilentlyContinue) {
            $sizingClamp = Resolve-SizingClamp -ProposedSizeUsd $usd_size -MaxSizeUsd $maxSize
            if ($sizingClamp.clamped) {
                Write-Host "  [GEM GUARD] $mkt sizing clamp: $usd_size -> $($sizingClamp.size_usd) (cap)" -ForegroundColor Cyan
                $usd_size = [double]$sizingClamp.size_usd
                $qty = [Math]::Round($usd_size / $price, 8)
            }
        }

        $guards = Test-LiveTradeGuards `
            -Market $mkt -ProposedSizeUsd $usd_size `
            -ExchangeBalanceUsd $exchBal -TotalCapitalUsd $totCap `
            -MaxSizeUsd $maxSize -MaxTradesPerWeek $maxFreq `
            -AllowedTierMode $tierMode -MaxCustodialRatio $maxCust
        if (-not $guards.pass) {
            $reasons = ($guards.blocked_by -join " | ")
            Write-Host "  [GEM GUARD BLOCKED] $mkt -- $reasons" -ForegroundColor Red
            $tsBlock = (Get-Date).ToString("HH:mm dd/MM/yy")
            $blockMsg = "*GEM BLOQUEADO* -- $mkt`nMotivo: $reasons`n_$tsBlock_"
            try { Send-TelegramAlert -Message $blockMsg | Out-Null } catch {}
            return [PSCustomObject]@{
                market = $mkt; market_type = $marketType
                price = $price; qty = $qty
                stop = $stop_price; target = $tgt_price
                sizing_usd = $usd_size; dry_run = $false
                blocked = $true; blocked_by = $guards.blocked_by
            }
        }
    }

    # ── 2026-06-03: VALIDAÇÃO OBRIGATÓRIA DE TP ANTES DE ABRIR ──────────────────
    # BUG: CoinEx API está rejeitando TP alto (0.334+) e colocando TP mínimo (0.111).
    # SOLUÇÃO: Validar que TP é razoável ANTES de abrir.
    # 2026-07-16 FIX (achado real via forced-test-trade ARBUSDT SHORT, runs
    # 29445042483 e 29445171696): checagem original "TP < entry*1.01 ->
    # bloqueia" so faz sentido pra LONG (TP acima do entry = lucro). Pra
    # SHORT, TP correto e ABAIXO do entry (lucro quando preco cai) --
    # tp_vs_entry sempre < 1 num SHORT valido, entao essa checagem
    # bloqueava 100% dos SHORT em futures, sempre, independente de
    # preco/timing (confirmado: 2 tentativas identicas, mesmo bloqueio).
    # Nunca foi pego antes porque nenhum SHORT tinha chegado ate essa
    # validacao em producao real ate hoje. Fix: direcao-aware.
    if ($hasFutures) {
        $tp_vs_entry = $tgt_price / $price
        $tp_min_acceptable_pct = 0.01  # TP deve estar pelo menos 1% distante do entry
        $tpInvalid = if ($direction -eq "SHORT") {
            $tp_vs_entry -gt (1 - $tp_min_acceptable_pct)  # SHORT: TP deve ficar >=1% ABAIXO
        } else {
            $tp_vs_entry -lt (1 + $tp_min_acceptable_pct)  # LONG: TP deve ficar >=1% ACIMA
        }
        if ($tpInvalid) {
            Write-Host "  [GEM BLOQUEADO] TP INVALIDO: TP=$tgt_price vs Entry=$price dir=$direction (ratio=$([Math]::Round($tp_vs_entry, 4)))" -ForegroundColor Red
            $blockMsg = "*GEM BLOQUEADO* -- $mkt`nMotivo: TP invalido (rejeitado por API?)`nTP: $tgt_price vs Entry: $price (dir=$direction)`nAcao: Revisar CoinEx API limits"
            try { Send-TelegramAlert -Message $blockMsg | Out-Null } catch {}
            return [PSCustomObject]@{ blocked = $true; blocked_by = @("tp_validation_failed:tp_too_close_to_entry"); market = $mkt }
        }
    }

    # ── Alerta PRE-ordem ─────────────────────────────────────────────────────
    $mktType = if ($hasFutures) { "FUTURES" } else { "SPOT" }
    $directionLabel = if ($direction -eq "SHORT") { "SHORT 📉" } else { "LONG 📈" }
    $preMsg = "*EXECUTANDO GEM* -- $mkt [$mktType] $directionLabel`nEntrada: $price | Stop: $stop_price | Alvo: $tgt_price`nSizing: $usd_size USDT"
    Send-TelegramAlert -Message $preMsg | Out-Null

    # ── 2026-06-08: VALIDAÇÃO MULTI-TIMEFRAME (Phase 2 integration) ────────────
    # Enforça LONG/SHORT em seu próprio contexto de sinal: LONG requer HTF uptrend,
    # SHORT requer HTF downtrend (ou neutral). Cada direção tem suas próprias regras.
    if (Get-Command Get-TrendDirection -ErrorAction SilentlyContinue) {
        try {
            Write-Host "  [MULTI-TF] Fetching candles para $mkt (1D, 4H, 1H)..." -ForegroundColor Cyan

            # Fetch candles for all timeframes
            $candles1D = Get-CoinExCandles -Market $mkt -Period "1day" -Limit 50 -IsFutures $hasFutures
            $candles4H = Get-CoinExCandles -Market $mkt -Period "4hour" -Limit 50 -IsFutures $hasFutures
            $candles1H = Get-CoinExCandles -Market $mkt -Period "1hour" -Limit 50 -IsFutures $hasFutures

            if ($candles1D.Count -lt 20 -or $candles4H.Count -lt 20 -or $candles1H.Count -lt 5) {
                Write-Host "  [MULTI-TF WARN] Insuficientes candles: 1D=$($candles1D.Count) 4H=$($candles4H.Count) 1H=$($candles1H.Count) — pulando validacao" -ForegroundColor Yellow
            } else {
                # Analyze trends
                $trend1D = Get-TrendDirection -Candles $candles1D -Timeframe "1D"
                $trend4H = Get-TrendDirection -Candles $candles4H -Timeframe "4H"
                $trend1H = Get-TrendDirection -Candles $candles1H -Timeframe "1H"

                # Test alignment
                $aligned = Test-MultiTimeframeAlignment -Trend1D $trend1D -Trend4H $trend4H -Trend1H $trend1H -Direction $direction

                if (-not $aligned) {
                    Write-Host "  [GEM BLOQUEADO] Multi-TF misalignment: 1D=$trend1D | 4H=$trend4H | 1H=$trend1H | Dir=$direction | Aligned=$aligned" -ForegroundColor Red
                    $blockMsg = "*GEM BLOQUEADO* -- $mkt`nMotivo: Multi-TF misalignment`nTrend 1D: $trend1D | 4H: $trend4H | 1H: $trend1H`nDirection: $direction"
                    try { Send-TelegramAlert -Message $blockMsg | Out-Null } catch {}
                    $__override = $null
                    if (Get-Command Test-MentorOverride -ErrorAction SilentlyContinue) {
                        $__override = Test-MentorOverride -Market $mkt -GateTag "multi_tf_misalignment" -GateReason "1D=$trend1D 4H=$trend4H 1H=$trend1H dir=$direction" `
                            -Direction $direction -Price $price -Change24h $gemChange24h -Regime "$($btcScenario.scenario)"
                    }
                    if ($__override -and $__override.approved) {
                        Write-Host "  [MENTOR OVERRIDE] $mkt -- $($__override.motivo)" -ForegroundColor Magenta
                    } else {
                        return [PSCustomObject]@{ blocked = $true; blocked_by = @("multi_tf_misalignment:$direction-$trend1D-$trend4H"); market = $mkt }
                    }
                }

                Write-Host "  [MULTI-TF OK] $mkt aligned: 1D=$trend1D | 4H=$trend4H | 1H=$trend1H | Dir=$direction" -ForegroundColor Green

                # ── CONVICTION ENSEMBLE (modo observacao; NUNCA bloqueia) ─────────
                # 2026-06-17: registra conviccao 0-100 combinando eixos ortogonais
                # (BTC relative strength + multi-TF gradiente). So roda com a flag
                # CONVICTION_OBSERVE.flag presente. Falha sempre silenciosa.
                $__convFlag = Join-Path $PSScriptRoot "..\journal\CONVICTION_OBSERVE.flag"
                if ((Test-Path $__convFlag) -and (Get-Command Get-EntryConviction -ErrorAction SilentlyContinue)) {
                    try {
                        $axes = @{}

                        # Eixo multi-TF (reusa trends ja calculados acima -- custo zero)
                        if (Get-Command Get-MultiTimeframeConviction -ErrorAction SilentlyContinue) {
                            $axes.multitf = Get-MultiTimeframeConviction -Trend1D $trend1D -Trend4H $trend4H -Trend1H $trend1H -Direction $direction
                        }

                        # Eixo BTC relative strength (1 fetch extra de BTC 1H, so com flag)
                        if (Get-Command Get-BtcRelativeStrength -ErrorAction SilentlyContinue) {
                            $btcCandles1H = Get-CoinExCandles -Market "BTCUSDT" -Period "1hour" -Limit 50 -IsFutures $true
                            if ($btcCandles1H -and $btcCandles1H.Count -ge 2) {
                                $altCloses = @($candles1H | ForEach-Object { [double]$_.close })
                                $btcCloses = @($btcCandles1H | ForEach-Object { [double]$_.close })
                                $rsInfo = Get-BtcRelativeStrength -AltCloses $altCloses -BtcCloses $btcCloses -Beta 1.0
                                if ($rsInfo) {
                                    $axes.btc_rs = Get-RsConvictionScore -Rs $rsInfo.rs -BtcReturn $rsInfo.btc_return -Direction $direction
                                }
                            }
                        }

                        if ($axes.Count -gt 0) {
                            $conv = Get-EntryConviction -Axes $axes -Direction $direction
                            $obsPath = Join-Path $PSScriptRoot "..\journal\conviction_observations.jsonl"
                            Write-ConvictionObservation -Market $mkt -Direction $direction -Conviction $conv.conviction -Axes $axes -Path $obsPath
                            Write-Host "  [CONVICTION] $mkt $direction = $($conv.conviction)/100 (eixos: $($axes.Keys -join ',')) ready=$($conv.ready)" -ForegroundColor Magenta
                        }
                    } catch {
                        # observacao nunca afeta execucao
                    }
                }
            }
        } catch {
            Write-Host "  [MULTI-TF ERROR] $_" -ForegroundColor Yellow
        }
    }

    # ── ENRIQUECIMENTO SUPABASE PRE-EXECUCAO (2026-07-09) ──────────────────
    # Aplica decision grade inversion + counterfactual boost ANTES de executar
    # Impacto esperado: +8-15% win rate via mentoria mais informada
    $enrichment = $null
    $regime = if ($global:MARKET_REGIME) { "$($global:MARKET_REGIME)" } else { "UNKNOWN" }
    if (Get-Command Get-DecisionGradeEnrichment -ErrorAction SilentlyContinue) {
        try {
            $enrichment = Get-DecisionGradeEnrichment -Direction $direction -Regime $regime
            if ($enrichment -and $enrichment.should_invert -eq $true) {
                $oldDir = $direction
                $direction = if ($direction -eq "LONG") { "SHORT" } else { "LONG" }
                Write-Host "  [ENRICHMENT] Decision Grade Inversion: $oldDir → $direction (accuracy=$($enrichment.accuracy)% n=$($enrichment.n))" -ForegroundColor Magenta
            }
        } catch {
            Write-Host "  [ENRICHMENT WARN] Get-DecisionGradeEnrichment falhou: $_" -ForegroundColor Yellow
        }
    }

    # ── Gate de qualidade ESTRUTURAL do token (2026-07-20) ────────────────
    # Achado: BABYDOGEUSDT comprado autonomo ($100 real, -33.8% hoje) --
    # pipeline tinha gates de momentum/tecnico (breadth/pump-dump/entry
    # timing acima) mas NENHUM de qualidade estrutural do token em si. FQS
    # (lib_fundamental_quality.ps1) existe mas exige coin_registry.json
    # curado (55 mercados) -- aplicar aqui mataria a estrategia GEM inteira
    # (qualquer coisa nova = AVOID). Gate novo (lib_token_structural_quality.ps1)
    # e' so-CoinEx (liquidez rasa vs tamanho da posicao + preco unitario
    # extremo), NAO exige registry -- pesquisado 2026-07-20 (paper arXiv
    # 2507.01963v2: liquidez rasa e' o sinal mais forte de manipulacao/
    # memecoin-lixo, 88.1% de cobertura). BLOCK so com 2+ flags simultaneos
    # (padrao real de lixo estrutural); 1 flag isolado (ex: moeda legitima
    # barata) so ganha CAUTION, sizing reduzido -- nao mata a descoberta.
    $__intendedSizeUsd = if ($usd_size -gt 0) { [double]$usd_size } else { [double]$qty * $price }
    if (Get-Command Test-TokenStructuralQuality -ErrorAction SilentlyContinue) {
        try {
            $structQuality = Test-TokenStructuralQuality -Market $mkt -CurrentPrice $price -IntendedSizeUsd $__intendedSizeUsd
            if ($structQuality.verdict -eq "BLOCK") {
                Write-Host "  BLOQUEADO: qualidade estrutural do token $mkt -- $($structQuality.reason) (liquidez=`$$($structQuality.liquidity_usd) preco=$($structQuality.unit_price))" -ForegroundColor Red
                if (Get-Command Write-SignalSkip -ErrorAction SilentlyContinue) {
                    try { Write-SignalSkip -Market $mkt -Direction $direction -Gate "token_structural_quality_block" -EntryPrice $price -Regime "$($btcScenario.scenario)" -Source "structural_gate" | Out-Null } catch {}
                }
                $__override = $null
                if (Get-Command Test-MentorOverride -ErrorAction SilentlyContinue) {
                    $__override = Test-MentorOverride -Market $mkt -GateTag "token_structural_quality" -GateReason "$($structQuality.reason) (liquidez=$($structQuality.liquidity_usd) preco=$($structQuality.unit_price))" `
                        -Direction $direction -Price $price -Change24h $gemChange24h -Regime "$($btcScenario.scenario)"
                }
                if ($__override -and $__override.approved) {
                    Write-Host "  [MENTOR OVERRIDE] $mkt -- $($__override.motivo)" -ForegroundColor Magenta
                } else {
                    return [PSCustomObject]@{ blocked = $true; blocked_by = @("token_structural_quality:$($structQuality.reason)"); market = $mkt; gates_info = @{ structural = $structQuality } }
                }
            } elseif ($structQuality.verdict -eq "CAUTION") {
                $usd_size = [math]::Round($usd_size * 0.5, 2)
                Write-Host "  [STRUCTURAL CAUTION] $mkt -- $($structQuality.reason) -- sizing reduzido pela metade (`$$usd_size)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [STRUCTURAL GATE WARN] Test-TokenStructuralQuality falhou (nao bloqueante): $_" -ForegroundColor Yellow
        }
    }

    # ── HARD CAP DE RISCO/TRADE (2026-07-24, blueprint audit) ────────────
    # Achado: o teto (Regra de Ouro #2) so e' aplicado no caminho
    # primario de sizing (dynamic_feedback) via normalizacao interna -- os
    # fallbacks (Kelly/legacy, Add Position cascata 5%, ladder, sizing clamp)
    # nao reafirmam esse teto de forma centralizada. Este gate roda por
    # ULTIMO, depois de QUALQUER caminho de sizing ja ter decidido $usd_size,
    # e clampa (nunca bloqueia o trade -- so reduz o tamanho) se o valor
    # final exceder o teto do capital atual. Fail-safe: se $capital nao
    # estiver disponivel aqui por algum motivo, nao clampa (evita
    # falso-positivo por dado ausente bloquear trade legitimo -- o caminho
    # primario ja aplicou o teto corretamente na maioria dos casos).
    # 2026-08-08 FIX: hardcode 0.03 nunca foi atualizado quando o owner
    # subiu RISK_MAX_PCT_PER_TRADE de 3% pra 7% (commit 4060d4e/2026-08-04,
    # 11 dias depois deste gate ter sido escrito) -- esse mesmo hardcode
    # tambem foi copiado sem querer pros 2 fixes novos de 2026-08-07/08
    # (Resolve-GoldenRuleSizeClamp, Resolve-EffectiveSizingCap), fazendo o
    # sistema clampar trades de volta pro valor antigo (3%) mesmo apos o
    # owner ja ter decidido 7% ha dias -- os 3 pontos agora leem a mesma
    # fonte real (config.ps1).
    if ($capital -gt 0 -and $usd_size -gt 0) {
        $__hardCapRiskPct = if ($global:RISK_MAX_PCT_PER_TRADE) { [double]$global:RISK_MAX_PCT_PER_TRADE } else { 0.07 }
        $__hardCapUsd = [math]::Round($capital * $__hardCapRiskPct, 2)
        if ($usd_size -gt $__hardCapUsd) {
            Write-Host "  [RISK HARD CAP] $mkt usd_size=$usd_size excede $($__hardCapRiskPct*100)% do capital ($__hardCapUsd) -- clampado" -ForegroundColor Yellow
            $usd_size = $__hardCapUsd
            # $qty precisa refletir o clamp -- e' o que Invoke-OrderRouted usa
            # de fato pra FUTURES (SPOT usa $usd_size via QuoteAmountUsd direto).
            if ($price -gt 0) { $qty = [math]::Round($usd_size / $price, 6) }
        }
    }

    # ── MENTOR SHADOW OBSERVATION (2026-07-24, Fase 0 do plano) ─────────────
    # Roda a cascade Triagem->Mesa->Mentor (LLM real) so pra LOGAR a opiniao
    # dele vs a decisao real ja tomada acima -- nunca influencia $usd_size,
    # $direction ou bloqueio. No-op total se journal/MENTOR_SHADOW_ENABLED.flag
    # nao existir. Ver agents/lib_mentor_shadow.ps1.
    if (Get-Command Invoke-MentorShadowObservation -ErrorAction SilentlyContinue) {
        try {
            Invoke-MentorShadowObservation -Market $mkt -RealDirection $direction `
                -RealPrice $price -RealUsdSize $usd_size -Change24h $gemChange24h `
                -Regime "$($btcScenario.scenario)"
        } catch {
            # observacao nunca afeta execucao
        }
    }

    # ── ENTRY LOCK (2026-07-23, auditoria "100% integro") ───────────────────
    # 3 motores de execucao real (gem_scanner_executor_live/gem_loop, ambos via
    # esta funcao, + faro_v3_entry.ps1 separado) rodam em paralelo (jobs GH
    # Actions distintos). Cada um ja checa CoinEx-GetPendingPositions antes de
    # chegar aqui, mas ha uma janela real entre esse check e o envio da ordem
    # -- 2 motores podem ambos ver "sem posicao" e tentar abrir ao mesmo tempo.
    # Lock distribuido via Supabase (INSERT puro, PK=market, TTL 30s -- exclusao
    # mutua real garantida pelo Postgres, nao um check-then-write no cliente).
    # Fail-open se a infra de lock nao estiver disponivel (nao adiciona um
    # ponto de falha novo pro fluxo de trade real).
    $__entryLockAcquired = $false
    if (Get-Command Lock-EntryMarket -ErrorAction SilentlyContinue) {
        if (-not (Lock-EntryMarket -Market $mkt -LockedBy "gem_executor")) {
            return [PSCustomObject]@{ blocked = $true; blocked_by = @("entry_lock_held_by_other_engine"); market = $mkt }
        }
        $__entryLockAcquired = $true
    }

    # ── Execucao via Invoke-OrderRouted (2026-05-20 wire) ──────────────────
    # 2026-06-08: Suporta SHORT em adicao a LONG
    $side = if ($direction -eq "SHORT") { "sell" } else { "buy" }
    $orderTypeLabel = if ($hasFutures) { "FUTURES" } else { "SPOT (fallback)" }
    Write-Host "  Enviando ordem $orderTypeLabel [$direction]..." -ForegroundColor Cyan
    if ($hasFutures) {
        # 2026-07-17 FIX (achado real: SUIUSDT abriu a 50x, fechou madrugada
        # de 17/07): POST /futures/order (place order) NAO carrega leverage no
        # payload -- a corretora usa o que ja estiver configurado NA CONTA pro
        # par, herdado de qualquer config manual anterior (nunca decidido pelo
        # sistema). O UNICO jeito de fixar leverage e' POST /futures/adjust-
        # position-leverage ANTES da ordem (knowledge/COINEX_REFERENCE.md
        # secao 4.4, [confirmado]). CoinEx-AdjustPositionLeverage ja existia
        # (lib_coinex_position_management.ps1) e Get-SafeLeverage ja existia
        # com hard cap 5x (lib_leverage_cap.ps1, criada 2026-06-18 pro MESMO
        # bug -- "Found 50x BNB, 20x XMR") -- nenhuma das duas era chamada
        # aqui, unico lugar onde FUTURES real abre. Fail-closed: se o ajuste
        # falhar, bloqueia a ordem em vez de abrir com leverage desconhecida.
        $__convictionForLev = if ($Gem.PSObject.Properties['conviction'] -and $null -ne $Gem.conviction) { [int]$Gem.conviction } else { 0 }
        $__leverageMode = if ($Gem.mode -match "TORI_SHORT|PUMP") { "PUMP_RIDE" } elseif ($Gem.mode -eq "MOMENTUM") { "SCALP" } else { "STANDARD" }
        $__safeLeverage = if (Get-Command Get-SafeLeverage -ErrorAction SilentlyContinue) {
            [int](Get-SafeLeverage -ConvictionPercent $__convictionForLev -Mode $__leverageMode)
        } else { 2 }
        $__levResult = if (Get-Command CoinEx-AdjustPositionLeverage -ErrorAction SilentlyContinue) {
            CoinEx-AdjustPositionLeverage -Market $mkt -Leverage $__safeLeverage -MarginMode "isolated"
        } else { [PSCustomObject]@{ success = $false; error_msg = "CoinEx-AdjustPositionLeverage indisponivel" } }
        if (-not $__levResult.success) {
            Write-Host "  BLOQUEADO: falha ao fixar leverage segura em $mkt (${__safeLeverage}x) -- $($__levResult.error_msg)" -ForegroundColor Red
            if ($__entryLockAcquired -and (Get-Command Unlock-EntryMarket -ErrorAction SilentlyContinue)) { Unlock-EntryMarket -Market $mkt }
            return [PSCustomObject]@{ blocked = $true; blocked_by = @("leverage_adjust_failed:$($__levResult.error_msg)"); market = $mkt }
        }
        Write-Host "  [LEVERAGE] $mkt fixado em ${__safeLeverage}x isolated (mode=$__leverageMode conviction=$__convictionForLev)" -ForegroundColor DarkCyan
        $order = Invoke-OrderRouted -Route "futures" -Market $mkt -Side $side -Type "market" `
                                     -Amount $qty -StopLoss $stop_price
    } else {
        $order = Invoke-OrderRouted -Route "spot" -Market $mkt -Side $side -Type "market" `
                                     -Amount $qty -QuoteAmountUsd $usd_size
    }
    Write-Host "  Ordem: id=$($order.order_id)" -ForegroundColor Green
    # Ordem ja confirmada na exchange -- posicao real existe, libera o lock
    # (o proposito dele era so evitar 2 motores enviando ordem simultaneamente).
    if ($__entryLockAcquired -and (Get-Command Unlock-EntryMarket -ErrorAction SilentlyContinue)) { Unlock-EntryMarket -Market $mkt }

    # 2026-07-29: registra o evento real (OPEN vs ADD) na fonte que o guard
    # de cascata (secao 891+) de fato consulta -- $existingPosition ja foi
    # calculado antes deste ponto do fluxo (verifica posicao pre-existente).
    if (Get-Command Add-GemPositionEvent -ErrorAction SilentlyContinue) {
        try {
            $__eventType = if ($existingPosition) { "ADD" } else { "OPEN" }
            Add-GemPositionEvent -Market $mkt -Side $direction -UsdSize $usd_size -EventType $__eventType
        } catch {}
    }
    $filled_qty = if ($order.filled_amount) { [double]$order.filled_amount } else { $qty }
    $avg_price  = if ($order.avg_deal_price -and [double]$order.avg_deal_price -gt 0) { [double]$order.avg_deal_price } else { $price }

    if (-not $hasFutures) {

        # 2026-07-16 FIX (auditoria agent a395f05e): stop condicional SPOT era
        # fire-and-forget puro -- try/catch so logava em Write-Host (console
        # do runner efemero, ninguem ve), sem retry, sem alerta Telegram, sem
        # bloqueio/reversao. Se falhasse (rate limit, erro de precisao, rede),
        # a posicao ficava aberta SEM protecao e ninguem sabia. Diferente do
        # caminho FUTURES (Set-PositionProtection: retry 3x + valida via API
        # + alerta Telegram explicito se falhar apos retries). Fix: mesmo
        # padrao de retry+alerta pro SPOT, adaptado (CoinEx-PlaceSpotStopOrder
        # nao tem MaxRetries embutido como Set-PositionProtection).
        $spotStopOk = $false
        $spotStopLastErr = ""
        for ($__i = 1; $__i -le 3; $__i++) {
            try {
                CoinEx-PlaceSpotStopOrder -Market $mkt -Side "sell" -TriggerPrice $stop_price -Amount $filled_qty | Out-Null
                Write-Host "  Stop condicional colocado em $stop_price (tentativa $__i)" -ForegroundColor Yellow
                $spotStopOk = $true
                break
            } catch {
                $spotStopLastErr = $_.Exception.Message
                Write-Host "  AVISO: stop order falhou (tentativa $__i/3): $spotStopLastErr" -ForegroundColor Red
                if ($__i -lt 3) { Start-Sleep -Seconds 2 }
            }
        }
        if (-not $spotStopOk) {
            # 2026-07-24 FIX (blueprint audit): antes so alertava e deixava a
            # posicao aberta SEM PROTECAO ate intervencao manual -- viola
            # Regra de Ouro #1 (stop antes de qualquer entrada) na pratica.
            # Fail-safe real: sem stop condicional confirmado, vende a
            # posicao a mercado AGORA (nao espera humano ver o Telegram).
            $__critMsg = "CRITICO: SPOT SL FALHOU apos 3 tentativas -- ${mkt}. Ultimo erro: $spotStopLastErr"
            Write-Host "  $__critMsg -- fechando posicao a mercado (fail-safe)" -ForegroundColor Red
            $__emergencyCloseOk = $false
            $__emergencyCloseErr = ""
            try {
                CoinEx-PlaceSpotOrder -Market $mkt -Side "sell" -Type "market" -Amount $filled_qty | Out-Null
                $__emergencyCloseOk = $true
            } catch {
                $__emergencyCloseErr = $_.Exception.Message
            }
            if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
                $__alertMsg = if ($__emergencyCloseOk) {
                    "🚨 $__critMsg`nPosicao fechada a mercado (fail-safe) -- sem protecao nao ficou aberta."
                } else {
                    "🚨🚨 $__critMsg`nFECHAMENTO DE EMERGENCIA TAMBEM FALHOU: $__emergencyCloseErr`nPOSICAO ABERTA SEM PROTECAO -- AGIR MANUALMENTE AGORA."
                }
                try { Send-TelegramAlert -Message $__alertMsg | Out-Null } catch {}
            }
        }
    }

    Write-GemTradeJournal -Market $mkt -Price $avg_price -Qty $filled_qty -StopPrice $stop_price `
        -TargetPrice $tgt_price -SizingUsd $usd_size -GemScore $Gem.score `
        -Mode $Gem.mode -MarketType $marketType -DryRun $false -OrderId $order.order_id `
        -ToriSignal $tori_signal

    # Registra exposure para guard cumulativo
    try { Add-OpenGemPosition -Market $mkt -SizeUsdt $usd_size -StateFilePath $safetyStatePath } catch {}

    # ── PROTECAO OBRIGATORIA: SL + TP REAIS na corretora (2026-05-29) ───────────
    # CRITICO: 2026-07-02 — BUG REPETITIVO: lib_position_protection.ps1 nao carregada!
    # Resultado: SL/TP NUNCA eram colocados → posicoes abertas sem protecao
    # Fix: dot-source carregado no topo; agora SEMPRE tenta proteger.
    if ($hasFutures) {
        if (Get-Command Set-PositionProtection -ErrorAction SilentlyContinue) {
            Start-Sleep -Seconds 2  # aguarda posicao materializar na API
            $protect = Set-PositionProtection -Market $mkt -StopLoss $stop_price -TakeProfit $tgt_price -MaxRetries 3 -AlertOnFailure $true
            if ($protect.success) {
                Write-Host "  [PROTECAO OK] $mkt SL=$($protect.sl_price) TP=$($protect.tp_price) (validado na corretora)" -ForegroundColor Green
                try { Send-TelegramAlert -Message "✅ PROTEÇÃO ATIVA: $mkt SL=$($protect.sl_price) TP=$($protect.tp_price)" | Out-Null } catch {}
            } else {
                # 2026-07-24 FIX (blueprint audit): antes so alertava e deixava
                # a posicao FUTURES aberta SEM PROTECAO (alavancada = risco
                # maior que SPOT) ate intervencao manual. Fail-safe real:
                # sem SL/TP confirmado na corretora, fecha a posicao AGORA.
                Write-Host "  [PROTECAO FALHOU] $mkt sl_set=$($protect.sl_set) tp_set=$($protect.tp_set) -- fechando posicao (fail-safe)" -ForegroundColor Red
                $__futEmergencyOk = $false
                $__futEmergencyErr = ""
                try {
                    CoinEx-ClosePosition $mkt | Out-Null
                    $__futEmergencyOk = $true
                } catch {
                    $__futEmergencyErr = $_.Exception.Message
                }
                $__futAlertMsg = if ($__futEmergencyOk) {
                    "🚨 CRÍTICO: SL/TP FALHOU em $mkt — posicao FECHADA a mercado (fail-safe, alavancada demais pra ficar sem protecao). Entry=$avg_price Stop=$stop_price Target=$tgt_price"
                } else {
                    "🚨🚨 CRÍTICO: SL/TP FALHOU em $mkt E fechamento de emergencia TAMBEM FALHOU ($__futEmergencyErr) — POSICAO ALAVANCADA ABERTA SEM PROTECAO, AGIR MANUALMENTE AGORA! Entry=$avg_price Stop=$stop_price Target=$tgt_price"
                }
                try { Send-TelegramAlert -Message $__futAlertMsg | Out-Null } catch {}
            }
        } else {
            Write-Host "  [CRITICO] Set-PositionProtection NAO CARREGADA! Fechando posicao (fail-safe)!" -ForegroundColor Red
            $__futEmergencyOk2 = $false
            $__futEmergencyErr2 = ""
            try {
                CoinEx-ClosePosition $mkt | Out-Null
                $__futEmergencyOk2 = $true
            } catch {
                $__futEmergencyErr2 = $_.Exception.Message
            }
            $__futAlertMsg2 = if ($__futEmergencyOk2) {
                "🚨 CRÍTICO: $mkt lib_position_protection não carregada — posicao FECHADA a mercado (fail-safe)."
            } else {
                "🚨🚨 CRÍTICO: $mkt lib_position_protection não carregada E fechamento de emergencia FALHOU ($__futEmergencyErr2) — AGIR MANUALMENTE AGORA!"
            }
            try { Send-TelegramAlert -Message $__futAlertMsg2 | Out-Null } catch {}
        }
    }

    # ── Multi TP/SL nativo CoinEx (apenas FUTURES; spot usa stop ja colocado) ───
    if ($ladder -and $hasFutures -and (Get-Command CoinEx-PlaceMultiExitLadder -ErrorAction SilentlyContinue)) {
        try {
            $multi = CoinEx-PlaceMultiExitLadder -Market $mkt -PositionSide "long" `
                -TotalAmount ([decimal]$filled_qty) -Entry ([decimal]$avg_price) `
                -Ladder $ladder -AtrValue ([decimal]0) -PricePrecision $pricePrec -AmountPrecision $basePrec
            Write-Host "  [LADDER PLACED] tps=$(@($multi.tp_orders).Count) sls=$(@($multi.sl_orders).Count)" -ForegroundColor Cyan
        } catch {
            Write-Host "  [LADDER WARN] CoinEx-PlaceMultiExitLadder falhou: $_" -ForegroundColor Yellow
        }
    }

    if ($ladder -and (Get-Command Add-LadderEntryRecord -ErrorAction SilentlyContinue)) {
        try {
            Add-LadderEntryRecord -Market $mkt -TemplateId $ladderTplId -Regime "GEM" `
                -Entry $avg_price -AtrValue 0 `
                -TpsCount (@($ladder.tp_levels).Count) -SlsCount (@($ladder.sl_levels).Count) `
                -TradeId $order.order_id -Notes "live" | Out-Null
        } catch {}
    }

    # ── Confirmacao POS-ordem ─────────────────────────────────────────────────
    $execObj = [PSCustomObject]@{ market=$mkt; market_type=$mktType; order_id=$order.order_id; price=$avg_price; qty=$filled_qty; stop=$stop_price; target=$tgt_price }
    Send-TelegramAlert -Message (Format-TgGemExecuted -ExecResult $execObj -Gem $Gem) | Out-Null

    # ── 2026-05-29: ALERTA DE TRADE ABERTO EM DESTAQUE ────────────────────────
    # Antes: abertura passava sem destaque (so a linha generica acima). Agora envia
    # mensagem em destaque com entry/stop/TP/size para nao passar despercebida.
    if (Get-Command Format-TgTradeOpenedHighlight -ErrorAction SilentlyContinue) {
        try {
            $stopPctCalc   = if ($avg_price -gt 0) { [math]::Round([math]::Abs(($avg_price - $stop_price) / $avg_price) * 100, 1) } else { 0 }
            $targetPctCalc = if ($avg_price -gt 0) { [math]::Round([math]::Abs(($tgt_price - $avg_price) / $avg_price) * 100, 1) } else { 0 }
            $sideForMsg = if ($hasFutures) { "long" } else { "long" }  # GEM long-only
            $tradeHl = @{
                market      = $mkt
                side        = $sideForMsg
                entry_price = $avg_price
                size        = $filled_qty
                stop_loss   = $stop_price
                take_profit = $tgt_price
                stop_pct    = $stopPctCalc
                target_pct  = $targetPctCalc
                capital     = $usd_size
            }
            Send-TelegramAlert -Message (Format-TgTradeOpenedHighlight -Trade $tradeHl) | Out-Null
        } catch {
            Write-Host "  [TG HIGHLIGHT WARN] Falha ao enviar destaque: $_" -ForegroundColor Yellow
        }
    }

    # ── 2026-05-29: ANALISE DE MERCADO AUTOMATICA (multi-timeframe) ───────────
    # Nossa "AI Analysis" interna: contexto 1h/4h/1d (RSI/MACD/Bollinger/niveis)
    # enviado junto da abertura para dar visao de mercado no momento da entrada.
    if ($hasFutures -and (Get-Command Get-AutoMarketAnalysis -ErrorAction SilentlyContinue)) {
        try {
            $autoAnalysis = Get-AutoMarketAnalysis -Market $mkt
            if ($autoAnalysis.success -and (Get-Command Format-TgAutoAnalysis -ErrorAction SilentlyContinue)) {
                Send-TelegramAlert -Message (Format-TgAutoAnalysis -Analysis $autoAnalysis) | Out-Null
            }
        } catch {
            Write-Host "  [AUTO ANALYSIS WARN] Falha ao gerar analise: $_" -ForegroundColor Yellow
        }
    }

    # ── 2026-06-17: REGISTRO OBRIGATORIO em trailing_positions.json ──────────────
    # BUG-A: guard "$hasFutures -and" excluia SPOT (SPCXX, BASED nunca registrados).
    # BUG-B: Add-TrailingPosition nunca era chamada — só Update-TrailingStop (ATR job),
    #        que é diferente: um registra a posição, o outro ajusta o stop depois.
    # Fix: registrar SEMPRE após EXEC, independente de SPOT vs FUTURES.
    # 2026-06-28 CAUSA RAIZ original: Add-TrailingPosition caia no default "public"
    # (schema compartilhado com outro app). STATE_STORE_SCHEMA agora e forcado no
    # TOPO do arquivo (2026-08-15 fix, cobre Write-SignalSkip tambem) -- linha
    # abaixo mantida como reforco redundante no mesmo processo, sem custo real.
    if (Get-Command Add-TrailingPosition -ErrorAction SilentlyContinue) {
        try {
            $env:STATE_STORE_SCHEMA = "manuheadfund"  # reforco (fonte real: topo do arquivo)
            $__orderId = if ($order -and $order.order_id) { [string]$order.order_id } else { "" }
            # 2026-07-18: origem explicita p/ lib_trailing_unified.ps1 (motor
            # unico de trailing). $hasFutures ja esta no escopo (usado 3 linhas
            # abaixo); recalcula isScalp aqui (nao reusa $isScalp de linha ~716
            # -- fica dentro de um try/if condicional, pode nao ter sido
            # atribuida neste ciclo, e mais seguro recalcular local que confiar
            # em variavel de escopo distante).
            $__isScalpAtReg = if (Get-Command Test-IsScalp -ErrorAction SilentlyContinue) {
                Test-IsScalp -Strategy $Signal.strategy -PlannedDurationMinutes $PlannedDurationMin
            } else { $false }
            $__origin = @{
                asset_class = if ($hasFutures) { "FUTURES" } else { "SPOT" }
                trade_style = if ($__isScalpAtReg) { "SCALP" } else { "SWING" }
            }
            # 2026-07-27: "score de nascimento" -- owner pediu que cada trade
            # seja acompanhado conforme como nasceu, nao com regra fixa igual
            # p/ todos. Combina os sinais REAIS que decidiram esta entrada
            # (nao o Mentor LLM -- esse roda so em shadow, nunca decide o
            # real, ver lib_mentor_shadow.ps1). Usa os campos opt-in que
            # Add-TrailingPosition ja tinha (MentorConfidence/Tier/MesaSinal),
            # nunca preenchidos por nenhum dos 3 motores de execucao ate hoje.
            # Score 0-100: conviction ensemble (peso maior) + bonus por eixo
            # forte confirmado (>=80 em axes_detail, mesmo criterio do
            # threshold dinamico de 2026-07-26) + bonus/penalidade por FQS.
            $__birthConviction = if ($convictionEnsembleResult -and $null -ne $convictionEnsembleResult.conviction) {
                [double]$convictionEnsembleResult.conviction
            } else { 50.0 }
            $__birthStrongAxes = if (Get-Variable -Name __strongAxes -ErrorAction SilentlyContinue) { [int]$__strongAxes } else { 0 }
            $__birthFqsCategory = if ($fqsResult -and $fqsResult.success -and $fqsResult.new_fqs_category) {
                [string]$fqsResult.new_fqs_category
            } else { "UNKNOWN" }
            $__fqsBonus = switch ($__birthFqsCategory) {
                "GEM"  { 10 }
                "SOLID" { 5 }
                "RISKY" { -10 }
                default { 0 }
            }
            $__birthScore = [math]::Round(
                [math]::Max(0, [math]::Min(100, $__birthConviction + ($__birthStrongAxes * 5) + $__fqsBonus)), 1
            )
            $__birthRegime = if ($btcScenario -and $btcScenario.scenario) { [string]$btcScenario.scenario } else { "UNKNOWN" }
            $__birthMesaSinal = "regime=$__birthRegime|strong_axes=$__birthStrongAxes|fqs=$__birthFqsCategory"
            # 2026-07-28 FIX (achado real critico: SUIUSDT SHORT real executado
            # e registrado no trailing como "LONG" -- Side estava HARDCODED
            # aqui, ignorando $direction ja resolvida corretamente por toda a
            # cadeia de fixes anteriores 8ba227a/dfc518c/edd4789/26e8254).
            # Motor de saida (Resolve-ExitAutoDecision, lib_trailing_policy*)
            # calcula ganho/stop de forma INVERTIDA conforme o lado -- um
            # SHORT real monitorado como LONG pode nunca fechar corretamente
            # (ganho e perda trocados). $direction ja e "LONG"|"SHORT" valido
            # neste ponto (safety check linha ~1647), cobre SPOT (sempre LONG
            # na pratica, short_requires_futures_spot_only bloqueia SHORT+spot
            # antes daqui) e FUTURES (LONG ou SHORT).
            Add-TrailingPosition `
                -Market  $mkt `
                -Side    $direction `
                -Entry   $avg_price `
                -Stop    $stop_price `
                -Target  $tgt_price `
                -OrderId $__orderId `
                -Source  "gem" `
                -Mode    "GEM" `
                -Origin  $__origin `
                -BirthScore $__birthScore `
                -BirthFqsCategory $__birthFqsCategory `
                -BirthMesaSinal $__birthMesaSinal `
                -SlSource "fixed_pct" `
                -TpSource "fixed_pct" `
                -StopPctUsed ([double]$__stp.stop_pct)
            Write-Host "  [TRAILING] Registrado: $mkt entry=$avg_price stop=$stop_price target=$tgt_price origin=$($__origin.asset_class)/$($__origin.trade_style) birth_score=$__birthScore ($__birthMesaSinal)" -ForegroundColor Green
        } catch {
            Write-Host "  [TRAILING WARN] Falha ao registrar trailing: $_" -ForegroundColor Yellow
        }
    }

    # ── 2026-05-23: TRAILING STOP ATR (Position Management, FUTURES only) ────────
    # Ajusta stop dinamicamente via ATR apos 2% de lucro. Complementar ao registro acima.
    if ($hasFutures -and (Get-Command Update-TrailingStop -ErrorAction SilentlyContinue)) {
        try {
            Write-Host "  [TRAILING STOP] Agendando ativacao automatica em 60s..." -ForegroundColor DarkCyan
            # Agendar trailing stop para 60s depois (tempo para posicao aparecer na API)
            $trailingJob = Start-Job -ScriptBlock {
                param($Market, $ScriptRoot, $AccessId, $SecretKey, $BaseUrl)
                Start-Sleep -Seconds 60
                # Carregar credenciais no job (nao herdam do processo pai)
                $env:COINEX_ACCESS_ID  = $AccessId
                $env:COINEX_SECRET_KEY = $SecretKey
                if ($BaseUrl) { $global:COINEX_BASE_URL = $BaseUrl }
                . "$ScriptRoot\config.ps1"
                . "$ScriptRoot\lib_coinex.ps1"
                . "$ScriptRoot\lib_coinex_position_management.ps1"
                . "$ScriptRoot\lib_position_risk_manager.ps1"
                $result = Update-TrailingStop -Market $Market -AtrMultiplier 2.0 -MinProfitPct 2.0
                return $result
            } -ArgumentList $mkt, $PSScriptRoot, $env:COINEX_ACCESS_ID, $env:COINEX_SECRET_KEY, $COINEX_BASE_URL
            
            Write-Host "  [TRAILING STOP] Job ID: $($trailingJob.Id) (rodando em background)" -ForegroundColor DarkGray
        } catch {
            Write-Host "  [TRAILING STOP WARN] Falha ao agendar: $_" -ForegroundColor Yellow
        }
    }

    Write-Host "=== ENTRADA REGISTRADA ($direction) ===" -ForegroundColor Cyan
    return [PSCustomObject]@{
        market      = $mkt
        market_type = $marketType
        order_id    = $order.order_id
        price       = $avg_price
        qty         = $filled_qty
        stop        = $stop_price
        target      = $tgt_price
        sizing_usd  = $usd_size
        dry_run     = $false
        direction   = $direction
        trailing_stop_job_id = if ($trailingJob) { $trailingJob.Id } else { $null }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Write-GemTradeJournal
# ─────────────────────────────────────────────────────────────────────────────
# BUG FIX 2026-05-29: Adicionar escape de aspas e formatação correta de números
# Problema: valores numéricos estavam sendo truncados/corrompidos no CSV
# Solução: usar InvariantCulture para serialização e escape de aspas
function Write-GemTradeJournal {
    param(
        [string] $Market,
        [double] $Price,
        [double] $Qty,
        [double] $StopPrice,
        [double] $TargetPrice,
        [double] $SizingUsd,
        [int]    $GemScore,
        [string] $Mode,
        [string] $MarketType = "FUTURES",
        [bool]   $DryRun,
        [string] $OrderId = "",
        [string] $ToriSignal = ""
    )

    $tradeFile = Join-Path $global:JOURNAL_DIR "gem_trades.csv"
    if (-not (Test-Path $tradeFile)) {
        "timestamp,market,mode,market_type,score,price_entry,qty,stop_price,target_price,sizing_usd,order_id,dry_run,status,price_exit,pnl_pct,tori_signal,notes" |
            Out-File -FilePath $tradeFile -Encoding utf8 -Force
    }

    # BUG FIX: Usar InvariantCulture para evitar corrupção de números (vírgula PT-BR)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $priceStr = $Price.ToString($inv)
    $qtyStr = $Qty.ToString($inv)
    $stopStr = $StopPrice.ToString($inv)
    $targetStr = $TargetPrice.ToString($inv)
    $sizingStr = $SizingUsd.ToString($inv)
    
    # Escape de aspas em campos de texto
    $marketEsc = $Market -replace '"', '""'
    $modeEsc = $Mode -replace '"', '""'
    $marketTypeEsc = $MarketType -replace '"', '""'
    $orderIdEsc = $OrderId -replace '"', '""'
    $toriSignalEsc = $ToriSignal -replace '"', '""'

    $row = @(
        (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),
        $marketEsc, $modeEsc, $marketTypeEsc, $GemScore,
        $priceStr, $qtyStr, $stopStr, $targetStr, $sizingStr,
        $orderIdEsc,
        $(if ($DryRun) { "true" } else { "false" }),
        "OPEN", "", "", $toriSignalEsc, ""
    ) -join ","

    Add-Content -Path $tradeFile -Value $row -Encoding utf8
}

