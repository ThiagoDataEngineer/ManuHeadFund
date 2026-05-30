# orchestrator_v6.ps1 -- Esquadrao V6: Triagem (Parte A) -> Mesa (Parte B) -> Mentor Debate
# Cascade pura (Invoke-V6Cascade) + wrapper IO (Invoke-OrchestratorV6).
#
# Cascata:
#   Triagem  : tier A/B/C/D. Tier D = ABORTAR sem custo. Tier A = pula Mesa.
#   Whitelist (Wave 2): regime+direction+DoW BRT+mode  -> execute/observe/skip.
#                       skip       = ABORTAR antes da Mesa.
#                       observe    = roda cascade mas telegramFire=false (paper-only).
#                       execute    = fluxo normal (Mesa/Mentor).
#   Mesa     : termal+radar+lidar, consensus FORTE_3/MEDIO_2/MEDIO_1/CAOS.
#              CAOS = ABORTAR sem chamar Mentor.
#   Mentor   : modo DEBATE com knowledge cited. APROVAR/VETAR.
#
# Funcoes consumidas (Parte A/B reais ou mocks):
#   Invoke-Triagem               (Parte A)
#   Invoke-Mesa                  (Parte B)
#   Invoke-MentorDebate          (Parte C -- mentor_agent.ps1)
#   Test-RegimeDirectionAllowed  (Wave 2 -- lib_operational_whitelist.ps1)
#   Get-RelevantKnowledge        (Parte A, opcional, usado pelo Mentor via RAG)
#
# 2026-05-29: Integração de TP/SL Automático + Trailing Stop + CoinEx AI
#   Initialize-AutomaticTPSL    (lib_trailing_stop_intelligent.ps1)
#   Update-TrailingStopContinuous (lib_trailing_stop_intelligent.ps1)
#   Integrate-CoinExAIAnalysis   (lib_coinex_ai_integration.ps1)


# ─────────────────────────────────────────────────────────────────────────────
# Carregar dependências de Trailing Stop e CoinEx AI (2026-05-29)
# ─────────────────────────────────────────────────────────────────────────────

$trailingStopPath = Join-Path $PSScriptRoot "lib_trailing_stop_intelligent.ps1"
$coinexAIPath = Join-Path $PSScriptRoot "lib_coinex_ai_integration.ps1"

if (Test-Path $trailingStopPath) {
    . $trailingStopPath
    Write-Verbose "[orchestrator_v6] Loaded: lib_trailing_stop_intelligent.ps1"
}

if (Test-Path $coinexAIPath) {
    . $coinexAIPath
    Write-Verbose "[orchestrator_v6] Loaded: lib_coinex_ai_integration.ps1"
}

# Inicializar dicionário global para jobs de trailing stop
if (-not $global:TRAILING_STOP_JOBS) {
    $global:TRAILING_STOP_JOBS = @{}
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-DayOfWeekBRT -- converte DateTime UTC para dia da semana em BRT (UTC-3).
# Retorno: 0=Sunday, 1=Monday, ..., 6=Saturday (alinhado com lib_operational_whitelist).
# ─────────────────────────────────────────────────────────────────────────────
function Get-SetupForCascade {
    # 2026-05-16 03:00 BRT: calcula entry/stop/target reais ANTES da cascade.
    # Bug residual era: setup placeholder zerado fazia Mentor vetar 100% por "stop=0".
    # Formula barata: ATR-proxy via change_24h (sem fetch candles extra).
    # stop_pct = clamp(|change|*0.5, min=2%, max=8%) | RR fixo 5 (config.ps1 $RR_PREFERIDO)
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Market,
        [Parameter(Mandatory=$true)][string]$Direction,
        [Parameter(Mandatory=$true)][double]$Price,
        [Parameter(Mandatory=$true)][double]$Change24h
    )

    if ($Price -le 0) {
        return [PSCustomObject]@{ entry=0; stop=0; target=0; rr=0 }
    }
    if ($Direction -ne "LONG" -and $Direction -ne "SHORT") {
        return [PSCustomObject]@{ entry=0; stop=0; target=0; rr=0 }
    }

    # ATR-proxy: stop_pct entre 2% e 8% baseado em volatilidade observada (change 24h)
    $stopPct = [math]::Abs($Change24h) * 0.5
    if ($stopPct -lt 2.0) { $stopPct = 2.0 }
    if ($stopPct -gt 8.0) { $stopPct = 8.0 }
    $rr = 5.0
    $targetPct = $stopPct * $rr

    if ($Direction -eq "LONG") {
        $stop   = [math]::Round($Price * (1 - $stopPct / 100), 6)
        $target = [math]::Round($Price * (1 + $targetPct / 100), 6)
    } else {  # SHORT
        $stop   = [math]::Round($Price * (1 + $stopPct / 100), 6)
        $target = [math]::Round($Price * (1 - $targetPct / 100), 6)
    }

    return [PSCustomObject]@{
        entry  = $Price
        stop   = $stop
        target = $target
        rr     = $rr
    }
}


function Get-DayOfWeekBRT {
    param(
        [Parameter()] [DateTime]$Utc = (Get-Date).ToUniversalTime()
    )
    # Se vier sem Kind=Utc, assume UTC literal
    if ($Utc.Kind -ne [DateTimeKind]::Utc) {
        $Utc = [DateTime]::SpecifyKind($Utc, [DateTimeKind]::Utc)
    }
    $brt = $Utc.AddHours(-3)
    return [int]$brt.DayOfWeek
}

# ─────────────────────────────────────────────────────────────────────────────
# Invoke-V6Cascade -- PURA: nao toca CoinEx/Macro/Capital, so cascateia agentes.
# Permite testes unitarios isolados com stubs simples.
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-V6Cascade {
    param(
        [string]         $Market,
        [PSCustomObject] $Context,    # macro/feeCtx/capital/seasonal pre-computados
        [PSCustomObject] $Setup       # entry/stop/target/rr -- pode vir de triagem ou mesa
    )

    # === Triagem (Parte A) ===
    $triagem = Invoke-Triagem -Market $Market -Context $Context

    if ($triagem.tier -eq "D") {
        return [PSCustomObject]@{
            decisao      = "ABORTAR"
            motivo       = $triagem.razao
            triagem      = $triagem
            mesa         = $null
            mentor       = $null
            telegramFire = $false
        }
    }

    # === Whitelist gate (Wave 2): regime+direction+DoW+mode ============================
    # Curto-circuito antes da Mesa quando whitelist diz skip.
    # observe -> roda cascade mas marca paperOnly=$true (telegramFire=false no final).
    $paperOnly = $false
    $wlRegime    = $null; if ($triagem.regime)    { $wlRegime    = [string]$triagem.regime }
    $wlDirection = $null; if ($triagem.direction) { $wlDirection = [string]$triagem.direction }
    $wlMode      = "paper"; if ($Context.mode)    { $wlMode      = [string]$Context.mode }
    $wlDow       = $null
    if ($null -ne $Context.day_of_week_brt) { $wlDow = [int]$Context.day_of_week_brt }
    else { $wlDow = Get-DayOfWeekBRT }

    if ($wlRegime -and $wlDirection -and (Get-Command Test-RegimeDirectionAllowed -ErrorAction SilentlyContinue)) {
        try {
            $wl = Test-RegimeDirectionAllowed `
                -Regime    $wlRegime `
                -Direction $wlDirection `
                -DayOfWeekBRT $wlDow `
                -Mode      $wlMode
            if ($wl.tier -eq 'skip') {
                $skipMotivo = ("whitelist:skip:{0}+{1} [{2}]" -f $wlRegime, $wlDirection, $wl.reason)
                if (Get-Command Add-Decision -ErrorAction SilentlyContinue) {
                    try {
                        Add-Decision -Market $Market -Decision "SKIP" -Reason $skipMotivo `
                                     -AbortStage "whitelist" -Regime $wlRegime -Direction $wlDirection `
                                     -ScannerScore ([double]$Context.scanner_score) `
                                     -WhitelistTier "skip" -PaperOnly $false
                    } catch {}
                }
                return [PSCustomObject]@{
                    decisao      = "ABORTAR"
                    motivo       = $skipMotivo
                    triagem      = $triagem
                    mesa         = $null
                    mentor       = $null
                    telegramFire = $false
                }
            }
            if ($wl.tier -eq 'observe') {
                $paperOnly = $true
            }
        } catch {
            # Falha defensiva: nao bloqueia cascade se whitelist quebrar
        }
    }

    # === Mesa (Parte B) -- pula se Tier A ===
    $mesa = $null
    if ($triagem.tier -ne "A") {
        # B29 fix 2026-05-28: enriquecer Context com regime da triagem antes de chamar Mesa.
        # Antes: Context nao tinha .regime -> mesa_drones.jsonl ficava com regime="" em 99% das entradas.
        # Agora: injeta triagem.regime no Context para que Invoke-Mesa possa logar corretamente.
        $contextForMesa = $Context
        if ($triagem.regime -and -not ($Context.PSObject.Properties["regime"] -and $Context.regime)) {
            $contextForMesa = $Context | Select-Object *
            $contextForMesa | Add-Member -NotePropertyName "regime" -NotePropertyValue ([string]$triagem.regime) -Force
        }
        $mesa = Invoke-Mesa -Market $Market -Context $contextForMesa -Setup $Setup
        if ($mesa.consensus -eq "CAOS") {
            # B.1 fix 2026-05-15: registrar observation MESMO em CAOS quando paperOnly.
            # CAOS continua sendo dado valioso para criterio anti-padrao #3 (Mesa
            # consensus em <30% dos casos = whitelist mal-alinhada com drones).
            if ($paperOnly -and (Get-Command Add-Observation -ErrorAction SilentlyContinue)) {
                try {
                    # B1 fix 2026-05-20 PM6: usar $Setup param (entry/stop/target reais do scanner)
                    $caosEntry  = if ($Setup -and $Setup.entry  -gt 0) { [double]$Setup.entry  } else { 0 }
                    $caosStop   = if ($Setup -and $Setup.stop   -gt 0) { [double]$Setup.stop   } else { 0 }
                    $caosTarget = if ($Setup -and $Setup.target -gt 0) { [double]$Setup.target } else { 0 }
                    $caosAtr    = if ($Context.atr_pct) { [double]$Context.atr_pct }
                                   elseif ($caosEntry -gt 0) { [math]::Abs($caosStop - $caosEntry) / $caosEntry * 100 }
                                   else { 0 }
                    Add-Observation `
                        -Market           $Market `
                        -Regime           ([string]$wlRegime) `
                        -Direction        ([string]$wlDirection) `
                        -DowBrt           ([int]$wlDow) `
                        -WhitelistTier    'observe' `
                        -WhitelistReason  ([string]$wl.reason) `
                        -ScannerScore     ([double]$Context.scanner_score) `
                        -MesaConsensus    'CAOS' `
                        -MesaSinal        $null `
                        -MentorDecision   $null `
                        -MentorConfidence 0 `
                        -EntryPrice       $caosEntry `
                        -StopPrice        $caosStop `
                        -TargetPrice      $caosTarget `
                        -AtrProxyPct      $caosAtr `
                        -Mode             ([string]$wlMode)
                } catch { Write-Warning "Add-Observation (CAOS path) falhou: $_" }
            }
            # B25 fix 2026-05-21: distinguir MESA_DEGRADED (cascade LLM caiu) de CAOS genuino.
            # Antes: "Mesa dividida (CAOS)" mascarava 50% de falhas de infra como desacordo de personas.
            $caosMotivo = if ($mesa.degraded) {
                $nullDrones = @()
                if ($null -eq $mesa.termal) { $nullDrones += "termal" }
                if ($null -eq $mesa.radar)  { $nullDrones += "radar" }
                if ($null -eq $mesa.lidar)  { $nullDrones += "lidar" }
                "MESA_DEGRADED: {0}/3 drones null ({1}) -- cascade LLM falhou, nao eh desacordo de personas" -f $nullDrones.Count, ($nullDrones -join ',')
            } else {
                "Mesa dividida (CAOS) -- desacordo genuino entre personas (1/1/1 vote split)"
            }
            return [PSCustomObject]@{
                decisao      = "ABORTAR"
                motivo       = $caosMotivo
                triagem      = $triagem
                mesa         = $mesa
                mentor       = $null
                telegramFire = $false
                paperOnly    = $paperOnly
            }
        }
    }

    # 2026-05-16 12:00: RECALCULAR setup com direction da Mesa antes de chamar Mentor.
    # Bug raiz: setup pre-cascade usa direction macro (regime->LONG/SHORT), mas Mesa
    # decide direction por análise técnica. Mismatch causava "stop ABAIXO do entry
    # em SHORT" -> Mentor vetava por incoerencia matematica. Fix: re-calc post-Mesa.
    $setupForMentor = $Setup
    if ($mesa -and $mesa.sinal_consenso -and $mesa.sinal_consenso -ne "NEUTRO" -and
        (Get-Command Get-SetupForCascade -ErrorAction SilentlyContinue) -and
        $Setup.entry -gt 0) {
        # ATR proxy reconstruído via diferença stop/entry original
        $atrPct = if ($Setup.entry -gt 0) { [math]::Abs($Setup.stop - $Setup.entry) / $Setup.entry * 100 * 2 } else { 5 }
        $setupForMentor = Get-SetupForCascade -Market $Market -Direction $mesa.sinal_consenso `
                                              -Price $Setup.entry -Change24h $atrPct
    }

    # === Mentor Debate (Parte C) ===
    # Fase 1A 2026-05-20: monta FullContext (FQS/beta/dsr/regime/dd) pro Mentor.
    # PM6 fix bug semantico: triagem.tier (A/B/C/D = score quality) e wl.tier (live/observe/skip
    # = autorizacao regime) sao ORTOGONAIS. Mode combina ambos:
    #   triagem=A + wl=live    -> TIER_A_LIVE  (high quality, regime OK)
    #   triagem=A + wl=observe -> TIER_A_PAPER (high quality MAS regime limita pra paper)
    #   triagem=B + wl=observe -> TIER_B_PAPER (paper validation antes promote)
    #   GEM source             -> GEM
    $triagemTier = if ($triagem -and $triagem.tier) { [string]$triagem.tier } else { "" }
    $wlTierStr   = if ($wl -and $wl.tier) { [string]$wl.tier } else { "" }
    $mentorMode = "STANDARD"
    if ($triagemTier -eq "A" -and $wlTierStr -eq "live")    { $mentorMode = "TIER_A_LIVE" }
    elseif ($triagemTier -eq "A" -and $wlTierStr -eq "observe") { $mentorMode = "TIER_A_PAPER" }
    elseif ($wlTierStr -eq "observe")                       { $mentorMode = "TIER_B_PAPER" }
    elseif ($wlTierStr -eq "live")                          { $mentorMode = "TIER_A_LIVE" }   # fallback compat
    if ($Context.source -eq "GEM" -or $Context.mode -eq "GEM") { $mentorMode = "GEM" }

    $fullCtx = $null
    if (Get-Command Build-MentorFullContext -ErrorAction SilentlyContinue) {
        try {
            $fullCtx = Build-MentorFullContext -Market $Market -Mode $mentorMode -RegimeBias ([string]$wlRegime)
        } catch { $fullCtx = $null }
    }

    # B4 prevention 2026-05-20 PM6+260min: invariante pre-LLM.
    # Defesa em profundidade — se algum payload chegar corrompido (tier=A + mode=TIER_B_PAPER
    # impossivel apos 4-mode mapping, mas defensivo p/ replay/recovery futuro), falha fast
    # SEM queimar 1 LLM call (~$0.006).
    if (Get-Command Test-MentorPayloadInvariant -ErrorAction SilentlyContinue) {
        $inv = Test-MentorPayloadInvariant -TriagemTier $triagemTier -MentorMode $mentorMode
        if (-not $inv.valid) {
            Write-Warning "[orchestrator_v6] PAYLOAD INVARIANT VIOLATION: tier=$triagemTier mode=$mentorMode reason=$($inv.reason); SKIP mentor (poupanca LLM)"
            return [PSCustomObject]@{
                decisao      = "ABORTAR"
                motivo       = "INVARIANT_VIOLATION: $($inv.reason)"
                triagem      = $triagem
                mesa         = $mesa
                mentor       = $null
                telegramFire = $false
                paperOnly    = $paperOnly
            }
        }
    }

    # R5 fix 2026-05-21: skip Mentor para casos onde Mentor VAI VETAR com certeza.
    # User audit: 35 Mentor calls/dia, 0 trades. Mentor era chamado em candidates ja
    # condenados a falhar gates downstream. Pre-skip economiza $0.30+/dia.
    # Casos: Triagem tier=D (scanner score floor, ruido puro) OR
    #        Triagem tier=C + wlTier=skip (combinacao impossivel exec real) OR
    #        Triagem tier=C + wlTier=observe (paper-only nao precisa Mentor).
    # FIX 2026-05-23: adicionar tier=C+observe (economiza ~$0.15/dia adicional).
    $preMentorSkip = $false
    $preMentorReason = ""
    if ($triagemTier -eq "D") {
        $preMentorSkip = $true
        $preMentorReason = "PRE_MENTOR_SKIP: Triagem tier=D (ScannerScore floor, ruido puro)"
    }
    if ($triagemTier -eq "C" -and $wlTierStr -eq "observe") {
        $preMentorSkip = $true
        $preMentorReason = "PRE_MENTOR_SKIP: tier=C + observe (paper-only, Mentor desnecessario)"
    }
    if ($triagemTier -eq "C" -and $wlTierStr -eq "skip") {
        $preMentorSkip = $true
        $preMentorReason = "PRE_MENTOR_SKIP: tier=C + skip (combinacao impossivel)"
    }
    if ($preMentorSkip) {
        Write-Warning "[orchestrator_v6] $preMentorReason; SKIP mentor (poupanca LLM ~$0.006/call)"
        return [PSCustomObject]@{
            decisao      = "ABORTAR"
            motivo       = $preMentorReason
            triagem      = $triagem
            mesa         = $mesa
            mentor       = $null
            telegramFire = $false
            paperOnly    = $paperOnly
        }
    }

    $mentor = Invoke-MentorDebate -Market $Market -TriagemResult $triagem `
                                  -MesaResult $mesa -Setup $setupForMentor -FullContext $fullCtx

    $decisao = if ($mentor.decision -eq "APROVAR") { "EXECUTAR" } else { "ABORTAR" }
    $motivo  = if ($mentor.decision -eq "VETAR") { $mentor.mentor_mensagem } else { "" }

    # === MCE gate (Market Context Engine 2026-05-19) ===
    # Aplica filtro contextual APOS Mentor: se contexto BLOCK, sobrepoe APROVAR.
    # Se contexto LIVE_REDUCED, propaga size_multiplier pro sizing downstream.
    # Refs: knowledge/MARKET_TIMING_BRT.md
    $mceResult = $null
    $sizeMultiplier = 1.0
    if ((Get-Command Test-ContextAllowsTrade -ErrorAction SilentlyContinue) -and $mentor.decision -eq "APROVAR") {
        try {
            $regimeForMce = if ($wlRegime) { [string]$wlRegime } else { "SIDEWAYS" }

            # Fatores dinamicos: Fear&Greed, FundingRate, ETF Flow, DXY
            # Cache por ciclo em journal/mce_dynamic_cache.json (evita chamadas repetidas)
            $dynData = $null
            if (Get-Command Get-DynamicContextData -ErrorAction SilentlyContinue) {
                try {
                    $cacheFile = Join-Path $global:JOURNAL_DIR "mce_dynamic_cache.json"
                    $cacheValid = $false
                    if (Test-Path $cacheFile) {
                        $cached = Get-Content $cacheFile -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($cached -and $cached.fetched_at) {
                            $age = ((Get-Date).ToUniversalTime() - [datetime]$cached.fetched_at).TotalMinutes
                            if ($age -lt 30) { $dynData = $cached; $cacheValid = $true }
                        }
                    }
                    if (-not $cacheValid) {
                        $dynData = Get-DynamicContextData -CacheFile $cacheFile
                    }
                } catch { $dynData = $null }
            }

            $mceResult = Test-ContextAllowsTrade -DateBrt (Get-Date) -Regime $regimeForMce -DynamicData $dynData
            if ($mceResult.action -eq "BLOCK") {
                $decisao = "ABORTAR"
                $motivo = "MCE_BLOCK score=$($mceResult.score) static=$($mceResult.static_score) dynamic=$($mceResult.dynamic_score) (contexto desfavoravel)"
                $mentor.decision = "VETAR_MCE"
            } elseif ($mceResult.action -eq "PAPER_ONLY") {
                $paperOnly = $true
                $sizeMultiplier = 0.0
                $motivo = "MCE_PAPER score=$($mceResult.score)"
            } elseif ($mceResult.action -eq "LIVE_REDUCED") {
                $sizeMultiplier = [double]$mceResult.size_multiplier
            } else {
                # LIVE_FULL
                $sizeMultiplier = [Math]::Min(2.0, [double]$mceResult.size_multiplier)
            }
        } catch {
            Write-Warning "MCE check falhou (passa adiante): $_"
        }
    }

    # 2026-05-19 PM: Entry score boost via trend_persistence cache.
    # Apos Mentor APROVAR + MCE OK, ajusta score final baseado em trend persistence.
    # STRONG_TREND +10 / MODERATE +5 / NOISE/MEAN_REV -5. Apenas tracking (nao bloqueia).
    $trendBoost = $null
    if ($decisao -eq "EXECUTAR" -and (Get-Command Get-EntryScoreBoost -ErrorAction SilentlyContinue)) {
        try {
            $baseScoreForBoost = if ($triagem.score_predicted) { [double]$triagem.score_predicted } else { 65.0 }
            $trendBoost = Get-EntryScoreBoost -Market $Market -BaseScore $baseScoreForBoost
            if ($trendBoost.boost -ne 0) {
                Write-Host "  [TREND] $Market $($trendBoost.trend_label) -> score $baseScoreForBoost +$($trendBoost.boost) = $($trendBoost.adjusted_score)" -ForegroundColor DarkCyan
            }
        } catch {}
    }

    # paperOnly (observe) suprime disparo telegram mesmo com Mentor APROVAR.
    $tgFire = ($decisao -eq "EXECUTAR") -and (-not $paperOnly)

    # 2026-05-19: Log UNIVERSAL de toda decisao em journal/decisions.csv.
    # Resolve bug "observations.csv vazia": Add-Observation so loga paperOnly,
    # Add-Decision loga TUDO (EXECUTAR/ABORTAR/SKIP/PAPER) com stage do abort.
    if (Get-Command Add-Decision -ErrorAction SilentlyContinue) {
        try {
            $decFinal = if ($decisao -eq "EXECUTAR" -and $paperOnly) { "PAPER" } else { $decisao }
            $abortStage = ""
            if ($decisao -eq "ABORTAR") {
                if ($motivo -match "triagem|tier=D|score baixo|BATEDOR") { $abortStage = "triagem" }
                elseif ($motivo -match "whitelist|skip") { $abortStage = "whitelist" }
                elseif ($motivo -match "mesa|CAOS|consensus") { $abortStage = "mesa" }
                elseif ($motivo -match "mentor|VETAR") { $abortStage = "mentor" }
                elseif ($motivo -match "MCE|BLOCK|context") { $abortStage = "mce" }
                else { $abortStage = "other" }
            }
            Add-Decision `
                -Market         $Market `
                -Decision       $decFinal `
                -Reason         ([string]$motivo) `
                -AbortStage     $abortStage `
                -Regime         ([string]$wlRegime) `
                -Direction      ([string]$wlDirection) `
                -ScannerScore   ([double]$Context.scanner_score) `
                -WhitelistTier  $(if ($wl) { [string]$wl.tier } else { "" }) `
                -MesaConsensus  $(if ($mesa) { [string]$mesa.consensus } else { $null }) `
                -MentorDecision $(if ($mentor) { [string]$mentor.decision } else { $null }) `
                -PaperOnly      $paperOnly `
                -ProviderUsed   $(if ($mentor -and $mentor.PSObject.Properties['provider_used']) { [string]$mentor.provider_used } else { "none" })
        } catch {
            Write-Warning "Add-Decision falhou: $_"
        }
    }

    # B.1 fix 2026-05-15: registrar observation no CSV para audit pos-14d.
    # journal/short_promotion_criteria_2026_05_15.md define schema + criterio.
    if ($paperOnly -and (Get-Command Add-Observation -ErrorAction SilentlyContinue)) {
        try {
            # B1 fix 2026-05-20 PM6: $Setup param tem entry/stop/target reais; fallback hierarchy.
            # Antes do fix: Tier A skipava mesa -> setup ficava @{entry=0;...} -> observations.csv shell-only.
            $setup = if ($Setup -and $Setup.entry -gt 0) { $Setup }
                     elseif ($mesa -and $mesa.setup -and $mesa.setup.entry -gt 0) { $mesa.setup }
                     elseif ($triagem.setup -and $triagem.setup.entry -gt 0) { $triagem.setup }
                     else { @{entry=0;stop=0;target=0} }
            $atrPct = if ($Context.atr_pct) { [double]$Context.atr_pct }
                      elseif ($Setup -and $Setup.entry -gt 0) { [math]::Abs([double]$Setup.stop - [double]$Setup.entry) / [double]$Setup.entry * 100 }
                      else { 0 }
            Add-Observation `
                -Market           $Market `
                -Regime           ([string]$wlRegime) `
                -Direction        ([string]$wlDirection) `
                -DowBrt           ([int]$wlDow) `
                -WhitelistTier    'observe' `
                -WhitelistReason  ([string]$wl.reason) `
                -ScannerScore     ([double]$Context.scanner_score) `
                -MesaConsensus    $(if ($mesa) { [string]$mesa.consensus } else { $null }) `
                -MesaSinal        $(if ($mesa) { [string]$mesa.sinal_consenso } else { $null }) `
                -MentorDecision   ([string]$mentor.decision) `
                -MentorConfidence ([double]$mentor.confidence) `
                -EntryPrice       ([double]$setup.entry) `
                -StopPrice        ([double]$setup.stop) `
                -TargetPrice      ([double]$setup.target) `
                -AtrProxyPct      $atrPct `
                -Mode             ([string]$wlMode)
        } catch {
            Write-Warning "Add-Observation falhou: $_"
        }
    }

    return [PSCustomObject]@{
        decisao         = $decisao
        motivo          = $motivo
        triagem         = $triagem
        mesa            = $mesa
        mentor          = $mentor
        telegramFire    = $tgFire
        paperOnly       = $paperOnly
        mce             = $mceResult
        size_multiplier = $sizeMultiplier
        trend_boost     = $trendBoost
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Invoke-OrchestratorV6 -- wrapper completo
# Reusa fase 0 (market safety, fees, capital, macro, seasonal, prescreen) do
# orchestrator legado, depois delega a cascata para Invoke-V6Cascade.
#
# Dependencias dot-sourced fora deste arquivo:
#   config.ps1, lib_coinex.ps1, lib_macro.ps1, lib_indicators.ps1,
#   lib_seasonality.ps1, lib_telegram.ps1, mentor_agent.ps1,
#   lib_esquadrao_mocks.ps1 (ou triagem_agent.ps1/mesa_agent.ps1 reais)
# ─────────────────────────────────────────────────────────────────────────────
# =============================================================================
# Invoke-V6PostMentorExecution -- A+B path (2026-05-20)
#
# B (default): V6 cascade = paper-only mesmo com LIVE_MODE_ENABLED.flag.
# A (opt-in):  Quando AMBOS LIVE_MODE_ENABLED.flag E V6_LIVE_ENABLED.flag presentes,
#              + decisao=EXECUTAR + Wait-TelegramApproval OK -> CoinEx-PlaceOrder real.
#
# Por que 2 flags: LIVE_MODE_ENABLED ja autoriza GEM live; V6_LIVE_ENABLED eh opt-in
# adicional pra V6 cascade (recem-corrigida, ainda nao validada em paper full cycle).
# =============================================================================
function Invoke-V6PostMentorExecution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Decisao,           # "EXECUTAR" | "ABORTAR"
        [PSCustomObject] $Mentor = $null,
        [PSCustomObject] $Setup = $null,
        [string] $Side = "buy",
        [double] $Amount = 0,
        [string] $JournalDir = "",
        [switch] $DryRun
    )
    # Default result (paper-only)
    $result = [PSCustomObject]@{
        ordemId       = $null
        ordemExecutada = $null
        paperOnly     = $true
        decisaoFinal  = $Decisao
        reason        = "paper_default"
    }

    # Guards de seguranca em cadeia (fail closed)
    if ($Decisao -ne "EXECUTAR") { $result.reason = "not_execute"; return $result }
    if ($DryRun) { $result.reason = "dry_run"; return $result }
    if ($Amount -le 0) { $result.reason = "invalid_amount"; return $result }

    if (-not $JournalDir) {
        $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Split-Path $PSScriptRoot -Parent) "journal" }
    }
    $liveFlag = Join-Path $JournalDir "LIVE_MODE_ENABLED.flag"
    $v6Flag   = Join-Path $JournalDir "V6_LIVE_ENABLED.flag"
    if (-not (Test-Path $liveFlag)) { $result.reason = "no_live_mode_flag"; return $result }
    if (-not (Test-Path $v6Flag))   { $result.reason = "no_v6_live_flag";   return $result }

    # Aprovacao manual via Telegram (timeout 5min)
    $approvalMsg = "V6 EXEC $Market $Side $Amount entry=$($Setup.entry) stop=$($Setup.stop) target=$($Setup.target) mentor=$($Mentor.confianca)"
    $approved = $false
    if (Get-Command Wait-TgCallbackApproval -ErrorAction SilentlyContinue) {
        try {
            $tgResult = Wait-TgCallbackApproval -GemMarket $Market -TimeoutSeconds 300
            $approved = ($tgResult.decision -eq "approve")
        } catch {
            $result.decisaoFinal = "ERRO_APPROVAL"
            $result.reason = "approval_threw"
            return $result
        }
    }
    if (-not $approved) {
        $result.decisaoFinal = "CANCELADO_THIAGO"
        $result.reason = "user_rejected_or_timeout"
        return $result
    }

    # PlaceOrder real -- 2026-05-20 PM: usa Invoke-OrderRouted (arquitetura unificada)
    # Antes chamava CoinEx-PlaceOrder direto. Agora roteado via lib_order_routed.ps1
    # que dispatcha futures/spot conforme MarketRoute upstream. Mesmo comportamento
    # com routing-awareness.
    try {
        $sl = if ($Setup -and $Setup.stop -gt 0)  { $Setup.stop }   else { 0 }
        $tp = if ($Setup -and $Setup.target -gt 0) { $Setup.target } else { 0 }
        if (Get-Command Invoke-OrderRouted -ErrorAction SilentlyContinue) {
            $order = Invoke-OrderRouted -Route "futures" -Market $Market -Side $Side `
                -Type "market" -Amount $Amount -StopLoss $sl -Target $tp
        } else {
            # Fallback se lib_order_routed nao carregada (defensive)
            $slArg = if ($sl -gt 0) { $sl } else { $null }
            $tpArg = if ($tp -gt 0) { $tp } else { $null }
            $order = CoinEx-PlaceOrder $Market $Side "market" $Amount $null $slArg $tpArg "ct"
        }
        if ($order -and $order.order_id) {
            $result.ordemId = $order.order_id
            $result.ordemExecutada = $order
            $result.paperOnly = $false
            $result.reason = "executed"
        } else {
            $result.decisaoFinal = "ERRO_EXECUCAO"
            $result.reason = "no_order_id_returned"
        }
    } catch {
        $result.decisaoFinal = "ERRO_EXECUCAO"
        $result.reason = "placeorder_threw:$($_.Exception.Message)"
    }
    return $result
}


function Invoke-OrchestratorV6 {
    param(
        [string]$Market = "BTCUSDT",
        [switch]$DryRun,
        [PSCustomObject]$ScannerInfo = $null,   # Wave 2: propaga scanner.score
        [string]$Mode = "paper"                 # paper|live -- gate da whitelist
    )

    $startTime = Get-Date
    Write-Host ""
    Write-Host "=== ORCHESTRATOR V6 (Esquadrao) === $Market $(Get-Date -Format 'HH:mm')" -ForegroundColor Cyan

    # Fase 0: Market safety + fees (se lib_coinex disponivel)
    $mktInfo = $null; $feeCtx = $null; $capitalReal = 0
    if (Get-Command CoinEx-GetMarketInfo -ErrorAction SilentlyContinue) {
        $mktInfo = CoinEx-GetMarketInfo $Market
        if ($mktInfo -and -not $mktInfo.isSafe) {
            return [PSCustomObject]@{
                market=$Market; decisao="ABORTAR"
                motivo="Mercado nao seguro: $($mktInfo.notices -join '|')"
                triagem=$null; mesa=$null; mentor=$null
                timestamp=(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
        }
        $feeCtx = CoinEx-GetFeeContext $Market
        $capitalReal = CoinEx-GetFuturesCapitalUSDT
    }

    # Macro
    $macro = if (Get-Command Get-MacroContext -ErrorAction SilentlyContinue) {
        Get-MacroContext
    } else { [PSCustomObject]@{ macro_bias="NEUTRO"; score=50; resumo="" } }

    # Seasonal
    $seasonal = if (Get-Command Get-SeasonalityContext -ErrorAction SilentlyContinue) {
        $tier = if (Get-Command Get-MarketTier -ErrorAction SilentlyContinue) { Get-MarketTier -Market $Market } else { "MAJOR" }
        Get-SeasonalityContext -MarketTier $tier
    } else { $null }

    # Wave 2: propaga scanner.score e mode no Context para Triagem + whitelist gate.
    $scannerScore = $null
    if ($ScannerInfo) {
        if ($null -ne $ScannerInfo.score) { $scannerScore = [int]$ScannerInfo.score }
    }
    $scannerSub = [PSCustomObject]@{
        score  = $scannerScore
        change = if ($ScannerInfo) { $ScannerInfo.change } else { $null }
        volume = if ($ScannerInfo) { $ScannerInfo.volume } else { $null }
    }

    $context = [PSCustomObject]@{
        market           = $Market
        macro            = $macro
        feeCtx           = $feeCtx
        capital          = $capitalReal
        seasonal         = $seasonal
        mktInfo          = $mktInfo
        mode             = $Mode
        scanner          = $scannerSub
        scanner_score    = $scannerScore
        day_of_week_brt  = (Get-DayOfWeekBRT)
    }

    # 2026-05-19 PM: Wire market_router (fase 0). Decisao spot vs futures fica em
    # context.market_route pra downstream consumir. Execucao em si fica futures
    # por enquanto (rollout cauteloso); decisao apenas habilita visibility + futuro hook.
    if (Get-Command Add-MarketRouteToContext -ErrorAction SilentlyContinue) {
        try {
            $routingMode = if ($Mode -eq "paper") { "TIER_A" } else { "TIER_A" }   # default TIER_A; GEM tem flow proprio
            $context = Add-MarketRouteToContext -Context $context -Mode $routingMode
        } catch {
            Write-Warning "Add-MarketRouteToContext fail: $_"
        }
    }

    # Setup REAL calculado ANTES da cascade (fix 2026-05-16 03:00 BRT).
    # Bug residual era: placeholder zerado fazia Mentor VETAR 100% ("stop=0 viola regra inviolavel").
    # Get-SetupForCascade usa current price (mktInfo ou ticker live) + change24h como ATR-proxy.
    $priceForSetup = 0.0
    $changeForSetup = 0.0
    # B18-wire 2026-05-20 PM6+460min: stale price gate fail-closed pre-setup.
    # Decisao de stop/sizing usa preco fresh; preço >60s velho -> ABORTAR
    # (defense em profundidade: ScannerInfo.price pode estar stale entre cycle e setup).
    $priceStale = $false
    try {
        if ($ScannerInfo -and $null -ne $ScannerInfo.price) { $priceForSetup = [double]$ScannerInfo.price }
        elseif (Get-Command CoinEx-GetTickerFresh -ErrorAction SilentlyContinue) {
            $tkFresh = CoinEx-GetTickerFresh $Market
            if (Get-Command Test-PriceFresh -ErrorAction SilentlyContinue) {
                $fr = Test-PriceFresh -FetchedAt $tkFresh.fetched_at -MaxAgeSeconds 60
                if (-not $fr.is_fresh) { $priceStale = $true }
            }
            if ($tkFresh.ticker -and $tkFresh.ticker.last) { $priceForSetup = [double]$tkFresh.ticker.last }
        }
        elseif (Get-Command CoinEx-GetTicker -ErrorAction SilentlyContinue) {
            $tk = CoinEx-GetTicker $Market
            if ($tk -and $tk.last) { $priceForSetup = [double]$tk.last }
        }
        if ($ScannerInfo -and $null -ne $ScannerInfo.change) { $changeForSetup = [double]$ScannerInfo.change }
    } catch { }
    if ($priceStale) {
        Write-Warning "[orchestrator_v6] STALE PRICE detectado para $Market -- ABORTAR (fail-closed B18-wire)"
        return [PSCustomObject]@{
            decisao = "ABORTAR"
            motivo  = "STALE_PRICE: ticker fetched_at >60s, refusing to compute stop/sizing"
            triagem = $null
            mesa    = $null
            mentor  = $null
            telegramFire = $false
            paperOnly = $paperOnly
        }
    }
    # direction derivada de Triagem ainda nao rodou -- usa regime->direction proxy
    $dirForSetup = "LONG"
    if ($context.regime -like "BEAR*" -or $context.regime -eq "CAPITULATION" -or $context.regime -eq "TRANSITION_DOWN") {
        $dirForSetup = "SHORT"
    }
    $setupReal = Get-SetupForCascade -Market $Market -Direction $dirForSetup -Price $priceForSetup -Change24h $changeForSetup

    # Cascata
    $cascade = Invoke-V6Cascade -Market $Market -Context $context -Setup $setupReal

    # Atualiza setup com o que triagem/mesa entregaram (se entregaram); fallback = setupReal
    $finalSetup = $setupReal
    if ($cascade.triagem -and $cascade.triagem.setup) { $finalSetup = $cascade.triagem.setup }
    if ($cascade.mesa    -and $cascade.mesa.setup)    { $finalSetup = $cascade.mesa.setup }

    # Telegram: SO dispara se cascade.telegramFire = true
    if ($cascade.telegramFire -and (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue)) {
        try {
            $decisaoTg = if ($DryRun) { "DRY_RUN_EXECUTAR" } else { $cascade.decisao }
            $msg = Format-TgEsquadraoResult -Market $Market -Triagem $cascade.triagem `
                -Mesa $cascade.mesa -Mentor $cascade.mentor -Decisao $decisaoTg
            Send-TelegramAlert -Message $msg | Out-Null
        } catch { Write-Host "  [TG] Falha envio: $_" -ForegroundColor DarkYellow }
    }

    # === V6 Live Execution (A+B path, 2026-05-20) ===
    # B (default): V6_LIVE_ENABLED.flag ausente -> paper-only (skip PlaceOrder)
    # A (opt-in):  Ambos LIVE_MODE_ENABLED + V6_LIVE_ENABLED -> Wait-TelegramApproval + PlaceOrder
    # Amount: sizing 1% capital nocional (placeholder; sizing_engine integration futura)
    $execResult = $null
    try {
        # Sizing simples: 1% capital / preco (placeholder; sizing_engine wired futuro)
        $amountForExec = 0
        if ($capitalReal -gt 0 -and $finalSetup -and $finalSetup.entry -gt 0) {
            $amountForExec = [math]::Round(($capitalReal * 0.01) / $finalSetup.entry, 6)
        }
        $sideForExec = if ($cascade.mesa -and $cascade.mesa.sinal_consenso -eq "SHORT") { "sell" } else { "buy" }
        $execResult = Invoke-V6PostMentorExecution `
            -Market $Market -Decisao $cascade.decisao `
            -Mentor $cascade.mentor -Setup $finalSetup `
            -Side $sideForExec -Amount $amountForExec `
            -DryRun:$DryRun
    } catch {
        Write-Warning "Invoke-V6PostMentorExecution falhou: $_"
        $execResult = [PSCustomObject]@{ ordemId=$null; paperOnly=$true; decisaoFinal=$cascade.decisao; reason="exec_exception" }
    }

    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    Write-Host "  [V6] Decisao: $($cascade.decisao) | exec=$($execResult.reason) | ${elapsed}s" -ForegroundColor Cyan

    return [PSCustomObject]@{
        market       = $Market
        decisao      = if ($execResult.decisaoFinal -ne $cascade.decisao) { $execResult.decisaoFinal } `
                       elseif ($DryRun -and $cascade.decisao -eq "EXECUTAR") { "DRY_RUN_EXECUTAR" } `
                       else { $cascade.decisao }
        motivo       = $cascade.motivo
        triagem      = $cascade.triagem
        mesa         = $cascade.mesa
        mentor       = $cascade.mentor
        setup        = $finalSetup
        macro        = $macro
        feeContext   = $feeCtx
        capital      = $capitalReal
        elapsed      = $elapsed
        timestamp    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        # A+B fields: ordemId null em paper, populated em live
        ordemId      = $execResult.ordemId
        ordemExecutada = $execResult.ordemExecutada
        paperOnly    = $execResult.paperOnly
        execReason   = $execResult.reason
    }
}


# ─────────────────────────────────────────────────────────────────────────────
# Initialize-TrailingStopForPosition (2026-05-29)
# Inicializa TP/SL automático e inicia job de trailing stop contínuo
# ─────────────────────────────────────────────────────────────────────────────

function Initialize-TrailingStopForPosition {
    <#
    .SYNOPSIS
        Inicializa TP/SL automático e inicia trailing stop contínuo para uma posição
    
    .PARAMETER Market
        Par de trading (ex: INJUSDT)
    
    .PARAMETER Mode
        Modo (GEM ou STANDARD)
    
    .PARAMETER JournalDir
        Diretório do journal
    
    .OUTPUTS
        PSCustomObject com resultado da inicialização
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$false)]
        [string]$Mode = "STANDARD",
        
        [Parameter(Mandatory=$false)]
        [string]$JournalDir = ""
    )
    
    if (-not $JournalDir) {
        $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Split-Path $PSScriptRoot -Parent) "journal" }
    }
    
    try {
        # 1. Buscar posição aberta
        $position = CoinEx-GetPendingPositions -Market $Market | Select-Object -First 1
        
        if (-not $position) {
            Write-Host "❌ Nenhuma posição aberta para $Market" -ForegroundColor Red
            return [PSCustomObject]@{
                success = $false
                market = $Market
                error = "Position not found"
            }
        }
        
        $entryPrice = [double]$position.avg_entry_price
        $qty = [double]$position.quantity
        
        # 2. Buscar dados de mercado
        $ticker = CoinEx-GetTicker -market $Market
        $currentPrice = [double]$ticker.last
        $high24h = [double]$ticker.high_24h
        
        # 3. Inicializar TP/SL automático
        $tpsl = Initialize-AutomaticTPSL `
            -Entry $entryPrice `
            -CurrentPrice $currentPrice `
            -Peak24h $high24h `
            -Qty $qty `
            -Mode $Mode
        
        Write-Host "✅ TP/SL Automático Inicializado para $Market" -ForegroundColor Green
        Write-Host "   Entry: $entryPrice | TP: $($tpsl.TPBase) | SL: $($tpsl.SLBase)" -ForegroundColor Cyan
        Write-Host "   Trailing Stop: $($tpsl.TrailingStop) | Saídas Parciais: $($tpsl.PartialExits.Count)" -ForegroundColor Cyan
        
        # 4. Salvar TP/SL no journal
        $tpslConfigPath = Join-Path $JournalDir "tpsl_config_$Market.json"
        $tpslConfig = @{
            Market = $Market
            Mode = $Mode
            Entry = $entryPrice
            TPBase = $tpsl.TPBase
            SLBase = $tpsl.SLBase
            TrailingStop = $tpsl.TrailingStop
            PartialExits = $tpsl.PartialExits
            InitializedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        
        $tpslConfig | ConvertTo-Json -Depth 10 | Set-Content $tpslConfigPath
        Write-Host "   Config salvo em: $tpslConfigPath" -ForegroundColor DarkCyan
        
        # 5. Iniciar trailing stop contínuo como background job
        $trailingStopJob = Start-Job -ScriptBlock {
            param($Market, $Entry, $Peak, $SLBase, $ScriptRoot)
            
            # Carregar dependências no job
            . (Join-Path $ScriptRoot "lib_trailing_stop_intelligent.ps1")
            . (Join-Path $ScriptRoot "lib_coinex.ps1")
            
            # Executar trailing stop contínuo
            Update-TrailingStopContinuous `
                -Market $Market `
                -Entry $Entry `
                -Peak $Peak `
                -SLBase $SLBase `
                -TrailingPercent 14.5 `
                -UpdateIntervalSeconds 60
        } -ArgumentList $Market, $entryPrice, $high24h, $tpsl.SLBase, $PSScriptRoot
        
        # 6. Armazenar job ID para monitoramento
        $global:TRAILING_STOP_JOBS[$Market] = @{
            JobId = $trailingStopJob.Id
            Market = $Market
            StartedAt = Get-Date
            Status = "RUNNING"
            EntryPrice = $entryPrice
            TPBase = $tpsl.TPBase
            SLBase = $tpsl.SLBase
        }
        
        Write-Host "✅ Trailing Stop Job iniciado (ID: $($trailingStopJob.Id))" -ForegroundColor Green
        
        return [PSCustomObject]@{
            success = $true
            market = $Market
            jobId = $trailingStopJob.Id
            tpsl = $tpsl
            position = $position
        }
    }
    catch {
        Write-Host "❌ Erro ao inicializar trailing stop: $_" -ForegroundColor Red
        return [PSCustomObject]@{
            success = $false
            market = $Market
            error = $_.Exception.Message
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Monitor-TrailingStopJobs (2026-05-29)
# Monitora status dos jobs de trailing stop
# ─────────────────────────────────────────────────────────────────────────────

function Monitor-TrailingStopJobs {
    <#
    .SYNOPSIS
        Monitora status dos jobs de trailing stop
    
    .OUTPUTS
        Array com status de cada job
    #>
    [CmdletBinding()]
    param()
    
    $results = @()
    
    foreach ($market in $global:TRAILING_STOP_JOBS.Keys) {
        $jobInfo = $global:TRAILING_STOP_JOBS[$market]
        $job = Get-Job -Id $jobInfo.JobId -ErrorAction SilentlyContinue
        
        if ($job) {
            $status = $job.State
            $output = $job | Receive-Job -Keep -ErrorAction SilentlyContinue
            
            $results += [PSCustomObject]@{
                Market = $market
                JobId = $jobInfo.JobId
                Status = $status
                StartedAt = $jobInfo.StartedAt
                Duration = (Get-Date) - $jobInfo.StartedAt
                EntryPrice = $jobInfo.EntryPrice
                TPBase = $jobInfo.TPBase
                SLBase = $jobInfo.SLBase
                LastOutput = if ($output) { $output[-1] } else { "No output yet" }
            }
        } else {
            # Job completou ou foi removido
            $results += [PSCustomObject]@{
                Market = $market
                JobId = $jobInfo.JobId
                Status = "COMPLETED"
                StartedAt = $jobInfo.StartedAt
                Duration = (Get-Date) - $jobInfo.StartedAt
                EntryPrice = $jobInfo.EntryPrice
                TPBase = $jobInfo.TPBase
                SLBase = $jobInfo.SLBase
                LastOutput = "Job completed"
            }
            
            # Remover do dicionário
            $global:TRAILING_STOP_JOBS.Remove($market)
        }
    }
    
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# Stop-TrailingStopJob (2026-05-29)
# Para job de trailing stop para um mercado
# ─────────────────────────────────────────────────────────────────────────────

function Stop-TrailingStopJob {
    <#
    .SYNOPSIS
        Para job de trailing stop para um mercado
    
    .PARAMETER Market
        Par de trading
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market
    )
    
    if ($global:TRAILING_STOP_JOBS.ContainsKey($Market)) {
        $jobInfo = $global:TRAILING_STOP_JOBS[$Market]
        
        try {
            Stop-Job -Id $jobInfo.JobId -ErrorAction SilentlyContinue
            Remove-Job -Id $jobInfo.JobId -ErrorAction SilentlyContinue
            $global:TRAILING_STOP_JOBS.Remove($Market)
            
            Write-Host "✅ Trailing stop job parado para $Market" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "❌ Erro ao parar job: $_" -ForegroundColor Red
            return $false
        }
    }
    
    return $false
}

# ─────────────────────────────────────────────────────────────────────────────
# Validate-WithCoinExAI (2026-05-29)
# Valida decisão com análise IA da CoinEx
# ─────────────────────────────────────────────────────────────────────────────

function Validate-WithCoinExAI {
    <#
    .SYNOPSIS
        Valida decisão com análise IA da CoinEx
    
    .PARAMETER Market
        Par de trading
    
    .PARAMETER OurAnalysis
        Nossa análise técnica
    
    .OUTPUTS
        PSCustomObject com resultado da validação
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$false)]
        [PSCustomObject]$OurAnalysis = $null
    )
    
    try {
        # Consumir análise CoinEx
        $coinexAnalysis = Get-CoinExAIAnalysis -Symbol $Market
        
        if (-not $coinexAnalysis.Success) {
            return [PSCustomObject]@{
                success = $false
                market = $Market
                error = "Failed to fetch CoinEx analysis"
            }
        }
        
        # Se não temos nossa análise, usar padrão
        if (-not $OurAnalysis) {
            $OurAnalysis = @{
                RSI = 50
                MACD = 0
                Resistance = 0
                Support = 0
                Volume = 0
            }
        }
        
        # Integrar análise CoinEx
        $integration = Integrate-CoinExAIAnalysis `
            -Symbol $Market `
            -OurAnalysis $OurAnalysis `
            -MinAlignmentScore 0.8
        
        Write-Host "[VALIDACAO] CoinEx AI para $($Market):" -ForegroundColor Cyan
        Write-Host "   Alinhamento: $([Math]::Round($integration.OverallAlignment * 100, 1))%" -ForegroundColor Cyan
        Write-Host "   Tecnico: $([Math]::Round($integration.TechnicalAlignment * 100, 1))%" -ForegroundColor Cyan
        Write-Host "   Sentimento: $([Math]::Round($integration.SentimentAlignment * 100, 1))%" -ForegroundColor Cyan
        
        if ($integration.UseCoinExAnalysis) {
            Write-Host "   [OK] CoinEx AI ALINHADA - usando como validacao" -ForegroundColor Green
        } else {
            Write-Host "   [WARN] CoinEx AI DESALINHADA - ignorando" -ForegroundColor Yellow
        }
        
        return [PSCustomObject]@{
            success = $true
            market = $Market
            useCoinExAnalysis = $integration.UseCoinExAnalysis
            overallAlignment = $integration.OverallAlignment
            technicalAlignment = $integration.TechnicalAlignment
            sentimentAlignment = $integration.SentimentAlignment
            coinexAnalysis = $integration.CoinExAnalysis
            details = $integration.TechnicalDetails + $integration.SentimentDetails
        }
    }
    catch {
        Write-Host "[ERROR] Erro ao validar com CoinEx AI: $_" -ForegroundColor Red
        return [PSCustomObject]@{
            success = $false
            market = $Market
            error = $_.Exception.Message
        }
    }
}

# Fim do arquivo orchestrator_v6.ps1
