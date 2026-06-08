# scan_master.ps1 — Loop mestre: GemScan + Orchestrator + Trailing stops
# Auto-pacing via lib_seasonality (15min PRIME / 30min GOOD / 1h NEUTRAL / 2h SLOW)
# Comandos Telegram: /status /scan [PAR] /gem /pausar /retomar /fechar PAR /ajuda
#
# Uso:
#   .\scripts\scan_master.ps1                      # loop continuo
#   .\scripts\scan_master.ps1 -Pairs BTCUSDT,ETHUSDT -Once
#   .\scripts\scan_master.ps1 -SkipGem -SkipOrchestrator   # so trailing

param(
    [string[]]$Pairs             = @(),       # pares para Orchestrator; vazio = watchlist padrao
    [switch]  $Once,                          # roda uma vez e sai
    [switch]  $DryRun,                        # passa DryRun para Orchestrator
    [switch]  $SkipGem,                       # pula GemScan
    [switch]  $SkipOrchestrator,              # pula Orchestrator
    [switch]  $SkipTrailing,                  # pula atualizacao de trailing stops
    [int]     $ForceIntervalMin  = 0,         # forcas intervalo fixo (0 = usa sazonalidade)
    [int]     $GemTopN           = 5,
    [int]     $OrchestratorTopN  = 20,        # quantos pares ORGANICOS do scanner enviar ao Orchestrator (Item 1 2026-05-29: era 3)
    [switch]  $Parallel,                      # roda candidates do orchestrator em paralelo (RunspacePool)
    # B28b fix 2026-05-21: MaxConcurrency 3 -> 2.
    # Diagnostico mesa_drones.jsonl pos B27 mostrou burst inter-market (3 markets
    # simultaneos = 9 drones LLM em paralelo) estourando Groq rate limit. Stagger
    # 750ms intra-drone nao ajuda se 3 markets disparam ao mesmo tempo.
    # 2 concurrent = max 6 drones simultaneos, sustentavel.
    [int]     $ParallelMaxConcurrency = 2
)

$ErrorActionPreference = "Continue"

# Anti-duplicata ROBUSTO via lib_daemon_singleton (lockfile PID+start_ticks).
# Substitui o check antigo por CommandLine -like "*scan_master*", que falhava com
# processos ELEVADOS (CommandLine=NULL pra shell normal -> nao casava -> DUPLICATAS).
# O lockfile e imune a esse blindspot: qualquer duplicata se auto-mata no startup.
$myPid = $PID
$__singletonLib = Join-Path (Split-Path $PSScriptRoot -Parent) "agents\lib_daemon_singleton.ps1"
$__lockDir      = Join-Path (Split-Path $PSScriptRoot -Parent) "journal\daemon_locks"
if (Test-Path $__singletonLib) {
    . $__singletonLib
    if (-not (Enter-DaemonSingleton -Name "scan_master" -LockDir $__lockDir)) {
        Write-Host "[SKIP] Outro scan_master VIVO ja detem o singleton lock; este PID=$myPid exit." -ForegroundColor Yellow
        exit 0
    }
}

"[DBG1 line22] DryRun=$DryRun PSBound=$($PSBoundParameters.Keys -join ',')" | Out-File -FilePath "$env:TEMP\dryrun_trace.log" -Append -Encoding utf8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$null = cmd /c chcp 65001 2`>nul

$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$agentsDir = Join-Path $scriptDir "..\agents"
$logDir    = Join-Path $scriptDir "..\logs"

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# Dot-source de tudo numa vez — evita re-importar no loop
. (Join-Path $agentsDir "constants_loader.ps1")    # 2026-05-16: single source of truth
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_cost_tracker.ps1")
. (Join-Path $agentsDir "lib_claude.ps1")
. (Join-Path $agentsDir "lib_macro.ps1")
. (Join-Path $agentsDir "lib_indicators.ps1")
. (Join-Path $agentsDir "lib_seasonality.ps1")
. (Join-Path $agentsDir "lib_telegram.ps1")
. (Join-Path $agentsDir "lib_idempotency.ps1")  # B14 callback idempotency
. (Join-Path $agentsDir "lib_retry.ps1")  # B19 retry transient
. (Join-Path $agentsDir "lib_order_idempotency.ps1")  # B19b PlaceOrder client_id
. (Join-Path $agentsDir "lib_price_freshness.ps1")  # B18 stale price gate
. (Join-Path $agentsDir "lib_mentor_hallucination_detector.ps1")  # P0b FQS hallucination detector
. (Join-Path $agentsDir "lib_fqs_enrichment_queue.ps1")  # 2026-05-21: auto-enqueue early (pre-Mentor)
. (Join-Path $agentsDir "lib_fundamental_quality.ps1")  # 2026-06-03 fix: Get-FundamentalScore (FQS JSON fallback) ausente do runspace -> FQS ABSENT -> 100% abort
. (Join-Path $agentsDir "lib_signal_trigger_bus.ps1")   # 2026-06-03 fast-path: consome triggers event-driven de sinais-lider
. (Join-Path $agentsDir "lib_entry_score_boost.ps1")    # 2026-06-03 fix: runspace audit missing (Get-EntryScoreBoost)
. (Join-Path $agentsDir "lib_order_routed.ps1")         # 2026-06-03 fix: runspace audit missing (Invoke-OrderRouted)
. (Join-Path $agentsDir "lib_market_router_wire.ps1")   # 2026-06-03 fix: runspace audit missing (Resolve-MarketRouteLive)
. (Join-Path $agentsDir "lib_tori_proximity.ps1")  # 2026-05-21 PM7: snapshot reader consumido por Mentor FullContext
. (Join-Path $agentsDir "lib_trailing.ps1")
. (Join-Path $agentsDir "lib_trailing_adaptive.ps1")  # Layer 1 TDD: Adaptive buffers + regime-aware stops
. (Join-Path $agentsDir "lib_mentor_reflection.ps1")  # Layer 2 TDD: 6h checkpoint reviews + early warnings
. (Join-Path $agentsDir "lib_layer4_tori_timestop.ps1")  # Layer 4 TDD: Tori proximity + time-based stops
. (Join-Path $agentsDir "lib_moon_bag.ps1")  # Layer 5 TDD: Moon Bag (50/50 harvest + upside)
. (Join-Path $agentsDir "lib_position_register.ps1")  # Layer 5 wire: wrapper opt-in via MOON_BAG_ENABLED.flag
. (Join-Path $agentsDir "lib_validation_logger.ps1")  # 2026-05-25: Validação Opção 2 (até 1ª pos fechar)
. (Join-Path $agentsDir "lib_trade_logger.ps1")
. (Join-Path $agentsDir "lib_trade_reason_archive.ps1")  # 2026-05-29: Arquivo de razoes completas
# Universe Sweep + Hit-Rate -- ZERO API extra; reusa cache da chamada CoinEx
# que Get-ScannerCandidates ja faz ($global:LAST_UNIVERSE_SNAPSHOT).
. (Join-Path $agentsDir "lib_universe_sweep.ps1")
. (Join-Path $agentsDir "lib_hit_rate.ps1")
. (Join-Path $agentsDir "lib_observation_logger.ps1")
. (Join-Path $agentsDir "lib_mentor_invariants.ps1")  # B4 prevention
. (Join-Path $agentsDir "lib_gem_safety.ps1")
. (Join-Path $agentsDir "lib_gem_auto_approve.ps1")
. (Join-Path $agentsDir "gem_agent.ps1")
. (Join-Path $agentsDir "gem_executor.ps1")

# V6.5 Cycle Indicators (Pi Cycle / 200WMA / ATH-DD / NUPL proxy)
# Reais ANTES do orchestrator_v6.ps1 (que importa chain_agent.ps1 -> mocks idempotentes).
. (Join-Path $agentsDir "lib_cycle_indicators.ps1")          # Parte A
. (Join-Path $agentsDir "lib_cycle_indicators_advanced.ps1") # Parte B

# 2026-06-01: Remover orchestrator.ps1 antigo (usar apenas orchestrator_v6.ps1)
# . (Join-Path $agentsDir "orchestrator.ps1") -DryRun:$DryRun
. (Join-Path $agentsDir "scanner.ps1")

# ── V6 Esquadrao: Triagem + Mesa + Mentor Debate ─────────────────────────────
# Ordem importa: reais primeiro (definem Invoke-Triagem/Invoke-Mesa), mocks
# depois (idempotentes via if-not-exists, so preenchem se reais falharem).
. (Join-Path $agentsDir "knowledge_retriever.ps1")
. (Join-Path $agentsDir "triagem_agent.ps1")
. (Join-Path $agentsDir "mesa_agent.ps1")
. (Join-Path $agentsDir "mentor_agent.ps1")  # 2026-06-01: Mentor Debate para validação final
. (Join-Path $agentsDir "lib_esquadrao_mocks.ps1")
"[DBG2 after-dot-source] DryRun=$DryRun" | Out-File -FilePath "$env:TEMP\dryrun_trace.log" -Append -Encoding utf8
. (Join-Path $agentsDir "orchestrator_v6.ps1")
. (Join-Path $agentsDir "lib_operational_whitelist.ps1")  # 2026-06-01: Whitelist SHORT bypass para Tier D
. (Join-Path $agentsDir "lib_enhanced_short_entry.ps1")   # 2026-06-01: Enhanced SHORT entry filter + regime trailing
. (Join-Path $agentsDir "lib_mesa_consensus_relaxed.ps1") # 2026-06-01: Relaxar Mesa Consensus + Permitir Tier C com FORTE_3
. (Join-Path $agentsDir "lib_quant_whitelist.ps1")
. (Join-Path $agentsDir "lib_top_candidates.ps1")  # Item 1 fix 2026-05-29: Select-TopCandidates (BTC anchor + top-N organicos)
. (Join-Path $agentsDir "lib_fqs_drain.ps1")       # Item 2 fix 2026-05-29: drain FQS inline antes do orchestrator
. (Join-Path $agentsDir "lib_market_context.ps1")
. (Join-Path $agentsDir "lib_market_context_engine.ps1")
. (Join-Path $agentsDir "lib_live_guards.ps1")
. (Join-Path $agentsDir "lib_promotion_gates.ps1")
. (Join-Path $agentsDir "lib_orchestrator_parallel.ps1")
. (Join-Path $agentsDir "lib_llm_quota_optimizer.ps1")  # 2026-05-26: Rate limiting + quota tracking
. (Join-Path $agentsDir "lib_short_execution.ps1")      # 2026-05-28: SHORT Block 2 -- wiring scanner -> orchestrator
# NOTE: lib_trailing_adaptive.ps1 and lib_layer4_tori_timestop.ps1 already loaded above (line 77-78)
# Removing duplicate loads to prevent function shadowing issues

# 2026-05-19 PM: Kelly sizing flag (auto-activated via cron quando 10+ outcomes graduate criteria)
# Le journal/USE_KELLY_SIZING.flag se presente -> seta $global:USE_KELLY_SIZING=$true
$_kellyFlag = Join-Path $scriptDir "..\journal\USE_KELLY_SIZING.flag"
if (Test-Path $_kellyFlag) {
    $global:USE_KELLY_SIZING = $true
    Write-Host "[Kelly] Flag detectada em $_kellyFlag -- USE_KELLY_SIZING=ON" -ForegroundColor Green
}

# ── Watchlist padrao para Orchestrator ───────────────────────────────────────
$DEFAULT_WATCHLIST = @(
    "BTCUSDT","ETHUSDT","SOLUSDT","BNBUSDT",
    "XRPUSDT","DOGEUSDT","ADAUSDT","AVAXUSDT"
)

# ── Estado global do loop ─────────────────────────────────────────────────────
$global:MASTER_PAUSED    = $false
$global:MASTER_LAST_SEASONAL = $null

# ── Resolve regime canonico para o TRADE log ─────────────────────────────────
# Wave 2.5 bugfix: o regime exibido no log do paper trade DEVE vir do
# triagem.regime (canonico: BULL_STRONG, BULL_WEAK, SIDEWAYS, TRANSITION_UP,
# TRANSITION_DOWN, BEAR_WEAK, BEAR_STRONG, CAPITULATION) -- e NUNCA do
# macro.macro_bias (que vale BULLISH/NEUTRAL/BEARISH e nao e canonico).
#
# Precedencia:
#   1. $Result.triagem.regime  (canonico, vindo de _Compute-RegimeFromContext)
#   2. $Result.regime          (caso algum caller legado ja resolva)
#   3. "UNKNOWN"               (fallback explicito -- NUNCA "NEUTRAL")
$script:VALID_TRADE_REGIMES = @(
    "BULL_STRONG","BULL_WEAK","SIDEWAYS","TRANSITION_UP",
    "TRANSITION_DOWN","BEAR_WEAK","BEAR_STRONG","CAPITULATION"
)

# ── Bug A fix: Pre-screen RSI trend-aware ────────────────────────────────────
# Regra antiga (estatica) rejeitava breakouts saudaveis:
#   passes_rsi = ($rsi -ge 28 -and $rsi -le 78)
# Caso HYPE 14/05: vol 4.46x + ADX 29 + RSI 80 era cortado antes do orchestrator.
# KB-fix RSI trend-aware ja em backtest/signal_generator.py — agora replicado aqui.
#
# Bug C fix (2026-05-15): desacopla vol/ADX do RSI gate em faixa saudavel.
# Anteriormente faixa 28-78 exigia ADX>=20 AND vol>=1.0x DENTRO do gate de RSI;
# isso duplicava o gate vol>=0.5x do array passes e bloqueava 100% dos candidatos
# em janela SLOW (madrugada) onde vol relativo cai universalmente. Snapshot
# 04:06 BRT 15/05: 14/14 blocks falharam por RSI gate com missing=vol<1.0x.
# RSI gate agora julga APENAS RSI; ADX e vol tem gates separados no array passes.
# Confluencia vol/ADX so se aplica em faixa de breakout (78-88), onde a
# confluencia E o sinal (sem ela, RSI alto vira sinal falso).
#
# Faixas:
#   RSI < 28               -> rejeita (oversold sem trigger)
#   RSI 28-78              -> passa SEMPRE (faixa saudavel; vol/ADX nos outros gates)
#   RSI 78-88              -> passa SE vol >= 1.5x AND ADX >= 25 (breakout confirmado)
#   RSI > 88               -> rejeita (overextended)
function Test-ScanPreScreen {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][double]$Rsi,
        [Parameter(Mandatory=$true)][double]$Adx,
        [Parameter(Mandatory=$true)][double]$Vol
    )
    if ($Rsi -lt 28) { return $false }
    if ($Rsi -gt 88) { return $false }
    if ($Rsi -le 78) {
        # Faixa saudavel — RSI sozinho ja qualifica. Gates de vol e ADX
        # (array passes em Invoke-MasterCycle) decidem confluencia separadamente.
        return $true
    }
    # Faixa 78-88: breakout. Exige confirmacao de volume E forca de tendencia.
    return ($Vol -ge 1.5 -and $Adx -ge 25)
}

# ── B.0 fix 2026-05-15: Inferencia de direction-bias para destravar SHORTs ──
# Problema diagnosticado: regra 5 da whitelist (SHORT em paper -> observe) nunca
# executou porque nenhum candidato chegava com direction=SHORT. Scanner top-20
# eh dominado por LONG movers, e pre-screen nao infere direcao. Esta funcao
# pura recebe RSI + EMA9/21 + momentum e devolve LONG/SHORT/NEUTRAL.
# Atta-se ao candidato em $candidates += ... para que orchestrator/triagem
# possa usar como hint quando macroBias eh NEUTRAL.
#
# Heuristica (calibrada pra capturar exhaustion + breakdown sem virar oscillator):
#   LONG    : (EMA9 > EMA21) E momentum >= +2%
#             OU oversold rebound (RSI < 30 E momentum >= +1.5%)
#   SHORT   : RSI >= 80 (parabolic) E momentum < 0  (exhaustion clean)
#             OU (EMA9 < EMA21) E momentum <= -3%  (breakdown trend)
#   NEUTRAL : todo o resto
#
# Tests: tests/scan_direction_bias.Tests.ps1 (10 tests TDD).
function Get-DirectionBias {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][double]$Rsi,
        [Parameter(Mandatory=$true)][double]$Ema9,
        [Parameter(Mandatory=$true)][double]$Ema21,
        [Parameter(Mandatory=$true)][double]$MomentumPct
    )
    if ($Ema21 -le 0) { return "NEUTRAL" }
    $emaUp   = ($Ema9 -gt $Ema21)
    $emaDown = ($Ema9 -lt $Ema21)

    # SHORT priority: parabolic exhaustion (RSI>=80 + momentum negativo) wins over EMA hint
    if ($Rsi -ge 80 -and $MomentumPct -lt 0) { return "SHORT" }
    # SHORT trend: EMA cross down + momentum claramente negativo
    if ($emaDown -and $MomentumPct -le -3) { return "SHORT" }

    # LONG continuation: EMA up + momentum positivo (>= +2)
    if ($emaUp -and $MomentumPct -ge 2) { return "LONG" }
    # LONG oversold rebound: RSI < 30 + momentum virando positivo
    if ($Rsi -lt 30 -and $MomentumPct -ge 1.5) { return "LONG" }

    return "NEUTRAL"
}


# ── Bug B fix: Score composto para ranking top-N ─────────────────────────────
# Ordenacao antiga: Sort-Object adx -Descending puro -> selecionava ADX 88-100
# (saturado/exausto, reversao iminente) em vez de 19-50 (breakout fresco).
# Caso HYPE 14/05 com ADX 29 nunca chegava ao top-3.
#
# Formula:
#   score = vol_spike * 0.4 + momentum_pct * 0.3 + adx_healthy_factor * 0.3
# onde adx_healthy_factor:
#   adx <= 60               -> adx/60        (ramp-up linear)
#   60 < adx <= 80          -> 1.0           (sweet spot)
#   adx > 80                -> max(0, 1 - (adx-80)/20)  (penaliza saturacao)
# Pesos calibrados: volume e o sinal mais ruidoso-resistente (40%); ADX-em-faixa
# desempata entre candidatos com mesmo vol/momentum.
function Get-ScannerCompositeScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][double]$VolSpike,
        [Parameter(Mandatory=$true)][double]$MomentumPct,
        [Parameter(Mandatory=$true)][double]$Adx
    )
    $adxHealthy = if ($Adx -le 60) {
        $Adx / 60.0
    } elseif ($Adx -le 80) {
        1.0
    } else {
        [math]::Max(0.0, 1.0 - ($Adx - 80.0) / 20.0)
    }
    $score = ($VolSpike * 0.4) + ([math]::Abs($MomentumPct) * 0.3) + ($adxHealthy * 0.3)
    return [math]::Round($score, 4)
}

function Get-OrchestratorTopN {
    # Calibracao cascade V6 (2026-05-15): override OPT-IN via $global:ORCHESTRATOR_TOPN_OVERRIDE
    # em config.local.ps1. Default 3 (comportamento anterior). Override valido = 1..20 (limite
    # do scanner top-20). Qualquer outro valor (nao numerico, <=0, >20) cai pro default 3.
    [CmdletBinding()]
    param(
        [int]$Default = 3,
        [int]$Max     = 20
    )
    $override = $null
    if (Test-Path variable:global:ORCHESTRATOR_TOPN_OVERRIDE) {
        $override = $global:ORCHESTRATOR_TOPN_OVERRIDE
    }
    if ($null -eq $override) { return $Default }
    $parsed = 0
    if (-not [int]::TryParse([string]$override, [ref]$parsed)) { return $Default }
    if ($parsed -lt 1 -or $parsed -gt $Max) { return $Default }
    return $parsed
}

function Resolve-RegimeForLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] $Result
    )
    $candidate = $null
    if ($Result -and $Result.triagem -and $Result.triagem.regime) {
        $candidate = [string]$Result.triagem.regime
    } elseif ($Result -and $Result.regime) {
        $candidate = [string]$Result.regime
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) { return "UNKNOWN" }
    if ($script:VALID_TRADE_REGIMES -notcontains $candidate) { return "UNKNOWN" }
    return $candidate
}

# ── Scanner dinamico: varredura UNIVERSAL spot + futures USDT ────────────────
# Custo: 2 chamadas API CoinEx (sem Claude). Retorna top N pares ranked por
# (|change_24h| x log10(volume_usd)). Cobre ~1.250 pares.
# Cada candidato carrega marketType (FUTURES | SPOT) para roteamento posterior.

function Get-ScannerCandidates {
    param(
        [int]   $TopN          = 15,      # quantos pares retornar para pre-screen
        [double]$MinVolUsd     = 500000,  # volume minimo 24h em USDT
        [switch]$IncludeSpot   = $true,   # incluir spot tickers no scan
        [switch]$FuturesOnly              # se setado, ignora spot mesmo com IncludeSpot
    )

    function Score-Ticker {
        param($t, [string]$Type)
        if (-not $t.market -or -not ($t.market -like "*USDT")) { return $null }
        $vol = [double]$t.value
        if ($vol -lt $MinVolUsd) { return $null }
        $open  = [double]$t.open; $close = [double]$t.close
        if ($open -le 0) { return $null }
        $change = (($close - $open) / $open) * 100
        $score  = [math]::Abs($change) * [math]::Log10([math]::Max($vol, 1000) / 1000)
        return [PSCustomObject]@{
            market     = $t.market
            marketType = $Type
            change     = [math]::Round($change, 2)
            volume     = [math]::Round($vol, 0)
            score      = [math]::Round($score, 2)
        }
    }

    # Universe Sweep cache: normaliza ticker bruto -> schema lib_universe_sweep.
    # Reusa o mesmo fetch (ZERO chamada CoinEx extra). Campos ausentes da CoinEx
    # ($t nao tem market_cap nem genesis_date) ficam $null sem quebrar.
    function _ToUniverseRow {
        param($t, [string]$Type)
        if (-not $t.market) { return $null }
        $open  = if ($null -ne $t.open)  { [double]$t.open }  else { 0 }
        $close = if ($null -ne $t.close) { [double]$t.close } else { 0 }
        $change = if ($open -gt 0) { (($close - $open) / $open) * 100 } else { $null }
        $vol   = if ($null -ne $t.value) { [double]$t.value } else { $null }
        # Spread: ask/bid se disponiveis no ticker; senao $null.
        $spread = $null
        if ($t.PSObject.Properties.Name -contains 'ask' -and $t.PSObject.Properties.Name -contains 'bid') {
            $ask = [double]$t.ask; $bid = [double]$t.bid
            if ($bid -gt 0) { $spread = (($ask - $bid) / $bid) * 100 }
        }
        return [PSCustomObject]@{
            symbol      = [string]$t.market
            marketType  = $Type
            vol_24h     = $vol
            change_24h  = $change
            market_cap  = $null   # CoinEx nao expoe; pre-screen continua usando CoinGecko
            age_days    = $null   # idem
            spread_pct  = $spread
        }
    }

    try {
        $scored      = @()
        $universe    = @()
        $futCount    = 0
        $spotCount   = 0
        $futMarkets  = @{}

        # 1) Futuros (prioritarios — orchestrator opera aqui)
        $futTickers = @(CoinEx-GetAllFuturesTickers)
        $futCount   = $futTickers.Count
        foreach ($t in $futTickers) {
            $u = _ToUniverseRow $t "FUTURES"
            if ($u) { $universe += $u }
            $r = Score-Ticker $t "FUTURES"
            if ($r) { $scored += $r; $futMarkets[$r.market] = $true }
        }

        # 2) Spot (somente se par NAO existir em futuros — evita duplicata)
        if ($IncludeSpot -and -not $FuturesOnly) {
            $spotTickers = @(CoinEx-GetAllSpotTickers)
            $spotCount   = $spotTickers.Count
            foreach ($t in $spotTickers) {
                $u = _ToUniverseRow $t "SPOT"
                if ($u) { $universe += $u }
                if ($futMarkets.ContainsKey($t.market)) { continue }
                $r = Score-Ticker $t "SPOT"
                if ($r) { $scored += $r }
            }
        }

        # Universe Sweep: cache universal antes do filtro top-N. Sentinela @()
        # (NUNCA $null) para downstream Get-UniverseSnapshot operar com seguranca.
        $global:LAST_UNIVERSE_SNAPSHOT = @($universe)
        $global:LAST_UNIVERSE_TS       = Get-Date

        $top = @($scored | Sort-Object score -Descending | Select-Object -First $TopN)
        Write-Host ("  [Scanner] {0} futuros + {1} spot ({2} passaram vol >= {3:N0} USDT) -> top {4}" -f $futCount, $spotCount, $scored.Count, $MinVolUsd, $top.Count) -ForegroundColor DarkCyan
        return $top
    } catch {
        # Falha catastrofica: garante snapshot vazio (nao $null) para callers degradarem
        $global:LAST_UNIVERSE_SNAPSHOT = @()
        $global:LAST_UNIVERSE_TS       = Get-Date
        Write-Host "  [Scanner] Erro: $_" -ForegroundColor DarkYellow
        return @()
    }
}

function Write-MasterLog {
    param([string]$Msg, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Msg"
    $logFile = Join-Path $logDir "master_$(Get-Date -Format 'yyyyMMdd').log"
    Add-Content -Path $logFile -Value $line -Encoding utf8
    $color = switch ($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "GEM" { "Magenta" } "TRADE" { "Green" } default { "DarkGray" } }
    Write-Host $line -ForegroundColor $color
}

# ── GemScan inline (compartilhado entre ciclo e comando /gem) ─────────────────

function Invoke-GemCycle {
    param([switch]$DryRun)
    $gems = @()
    Write-Host "`n[GEM] Iniciando GemScan (TopN=$GemTopN)..." -ForegroundColor Magenta
    try {
        $gems = @(Invoke-GemScan -TopN $GemTopN)
        # R4 fix 2026-05-21: filtrar gems com cache hit ANTES de emitir log/alert.
        # Pre-fix: PEAQ/PROVE re-detected cycle apos cycle. Cache hit acontecia
        # so dentro de Invoke-GemExecute (apos log GemScan), gerando spam.
        if (Get-Command Test-GemRecentlyRejected -ErrorAction SilentlyContinue -and $gems.Count -gt 0) {
            $cachePath = Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json"
            $filtered = @()
            $skipCached = @()
            foreach ($g in $gems) {
                if (Test-GemRecentlyRejected -Path $cachePath -Market $g.market -TtlMinutes 60) {
                    $skipCached += $g.market
                } else {
                    $filtered += $g
                }
            }
            if ($skipCached.Count -gt 0) {
                Write-MasterLog "GemScan: $($skipCached.Count) gem(s) skip cache (recently rejected) -- $($skipCached -join ',')" "GEM"
            }
            $gems = $filtered
        }
        if ($gems.Count -gt 0) {
            $gemList = ($gems | ForEach-Object { "$($_.market)($($_.score))" }) -join ", "
            Write-MasterLog "GemScan: $($gems.Count) gem(s) -- $gemList" "GEM"
            foreach ($g in $gems) {
                # 2026-06-08: PRE-CHECK TORI ANTES DE PEDIR APROVACAO
                # Se Tori vai bloquear de qualquer forma, não pede aprovação (evita confusão user)
                $toriPreCheck = $null
                $toriBlocksThis = $false
                if (Get-Command Get-ToriTrendlineSignal -ErrorAction SilentlyContinue) {
                    try {
                        $toriPre = Get-ToriTrendlineSignal -Market $g.market
                        $toriConviction = if ($toriPre.PSObject.Properties['conviction']) { [int]$toriPre.conviction } else { 0 }
                        $toriSig = if ($toriConviction -eq 0) { "SKIP" } elseif ($toriConviction -le 40) { "WAIT" } else { "ENTER" }
                        if ($toriSig -in @("SKIP","WAIT")) {
                            $toriBlocksThis = $true
                            $toriPreCheck = $toriSig
                            Write-MasterLog "GEM pre-check BLOCKED: $($g.market) -- Tori $toriSig ($($toriPre.reason))" "GEM"
                        }
                    } catch { }  # Falha silenciosa, continua normal
                }

                # Se Tori bloqueou no pre-check, pula pedido de aprovação
                if ($toriBlocksThis) {
                    Write-MasterLog "GEM skipped approval request: $($g.market) (Tori $toriPreCheck bloqueou)" "GEM"
                    continue
                }

                $approvalMsg = Format-TgGemApproval -Gem $g -DryRun:$DryRun
                if ($DryRun) {
                    Send-TelegramAlert -Message $approvalMsg | Out-Null
                    Write-MasterLog "GEM DryRun: $($g.market) score=$($g.score)" "GEM"
                } else {
                    # 2026-05-20 PM4: auto-approve strict (opt-in via GEM_AUTO_APPROVE.flag).
                    # Criterios: score>=90 + FQS BLUE_CHIP/QUALITY + registry + sizing<=1% + daily cap 3
                    # Captura GEMs quando user dorme; ainda dispara TG alert (audit + visibility).
                    $autoApprove = $false
                    $autoApprovalResult = $null
                    if (Get-Command Test-GemAutoApprove -ErrorAction SilentlyContinue) {
                        try {
                            $gemForAuto = [PSCustomObject]@{
                                market = $g.market
                                score  = if ($g.PSObject.Properties['score']) { [double]$g.score } else { 0 }
                                mode   = if ($g.PSObject.Properties['mode']) { [string]$g.mode } else { "DISCOVERY" }
                                sizing_pct = 0.5   # default DISCOVERY pos-PM4
                            }
                            $autoApprovalResult = Test-GemAutoApprove -Gem $gemForAuto
                            $autoApprove = $autoApprovalResult.approved
                            if ($autoApprove) {
                                Write-MasterLog "GEM auto-approved: $($g.market) score=$($g.score) reasons=$($autoApprovalResult.reasons -join ',')" "GEM"
                                Send-TelegramAlert -Message "*GEM AUTO-APPROVED* -- $($g.market) score=$($g.score)`nFQS:$($autoApprovalResult.fqs) daily=$($autoApprovalResult.daily_used)/$($autoApprovalResult.daily_cap)" | Out-Null
                            }
                        } catch { Write-MasterLog "auto-approve fail: $_" "WARN" }
                    }
                    $tgResult = if ($autoApprove) {
                        [PSCustomObject]@{ decision = 'approve'; source = 'auto' }
                    } else {
                        Wait-TgCallbackApproval -Gem $g -GemId $g.market -TimeoutSeconds 300
                    }
                    if ($tgResult.decision -eq 'approve') {
                        try {
                            $execResult = Invoke-GemExecute -Gem $g
                            # 2026-05-18 fix: $execResult pode ser $null (Tori SKIP, gem_safety block,
                            # guards block). NAO criar ghost position nem mandar "GEM EXECUTADA" sem
                            # order valida.
                            if (-not $execResult) {
                                # 2026-05-21 fix: legado fallback se gem_executor retornar null
                                # (apos B fix, todos paths retornam PSCustomObject — mas defensive)
                                Write-MasterLog "GEM nao executou (legacy null return, sem reason explicito): $($g.market)" "GEM"
                                try { Send-TelegramAlert -Message "[X] GEM nao executou: $($g.market) - sistema bloqueou pos-aprovacao (motivo: indefinido, ver log)" | Out-Null } catch {}
                            } elseif ($execResult.blocked) {
                                $reasons = ($execResult.blocked_by -join ' | ')
                                Write-MasterLog "GEM bloqueada por guards: $($g.market) -- $reasons" "GEM"
                                # A fix 2026-05-21: TG verbose pos-aprovacao bloqueada (user precisa saber!)
                                $isAutoApproved = ($tgResult.source -eq 'auto')
                                $approvalNote = if ($isAutoApproved) { "auto-approved" } else { "VOCE aprovou via TG" }
                                $tgVerbose = "[X] GEM bloqueado pos-aprovacao`nMarket: $($g.market) score=$($g.score)`nAprovacao: $approvalNote`nGuard: $reasons`n`nDefesa final estrutural funcionou — aprovacao manual respeita guards."
                                try { Send-TelegramAlert -Message $tgVerbose | Out-Null } catch {}
                            } elseif (-not $execResult.order_id) {
                                Write-MasterLog "GEM sem order_id (provavel dry_run ou erro silencioso): $($g.market)" "GEM"
                            } else {
                                Write-MasterLog "GEM EXECUTADA: $($g.market) ordem=$($execResult.order_id)" "GEM"
                                Send-TelegramAlert -Message (Format-TgGemExecuted -ExecResult $execResult -Gem $g) | Out-Null
                                # Layer 5 wire (opt-in via journal/MOON_BAG_ENABLED.flag)
                                # Quando flag OFF: trailing classico (back-compat).
                                # Quando flag ON e Size>0: Moon Bag split harvest+moon.
                                $gemSize = if ($execResult.sizing_usd) { [double]$execResult.sizing_usd } else { 0 }
                                Register-PositionTrailing -Market $g.market -Side "LONG" -Entry $execResult.price -Stop $execResult.stop -Target $execResult.target -OrderId $execResult.order_id -Source "gem" -Size $gemSize
                                # Auto-approve audit log (se foi auto)
                                if ($autoApprove -and (Get-Command Add-GemAutoApproveLog -ErrorAction SilentlyContinue)) {
                                    try { Add-GemAutoApproveLog -Gem $gemForAuto -ApprovalResult $autoApprovalResult -OrderId $execResult.order_id } catch {}
                                }
                            }
                        } catch {
                            Write-MasterLog "GEM execucao falhou: $($g.market) -- $_" "ERROR"
                        }
                    } else {
                        Write-MasterLog "GEM rejeitada: $($g.market)" "GEM"
                        Send-TelegramAlert -Message "❌ GEM rejeitada: $($g.market) (timeout ou usuario cancelou)" | Out-Null
                    }
                }
            }
        } else {
            Write-MasterLog "GemScan: nenhum gem encontrado" "GEM"
        }
    } catch {
        Write-MasterLog "GemScan falhou: $_" "ERROR"
    }
    return $gems
}

# ── Um ciclo completo ─────────────────────────────────────────────────────────

function Invoke-MasterCycle {
    param([PSCustomObject]$Seasonal, [string]$ForcePair = "")

    $cycleStart  = Get-Date
    $cycleTs     = $cycleStart.ToString("HH:mm dd/MM")
    $orchResults = @()
    $trailLines  = @()
    $gems        = @()
    $candidates  = @()
    $topCandidates = @()

    Write-Host ""
    Write-Host "-------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host "  MASTER CYCLE  $cycleTs  $($Seasonal.window)  momento=$($Seasonal.momentScore)/100" -ForegroundColor DarkCyan
    Write-Host "-------------------------------------------------" -ForegroundColor DarkCyan

    # ── 1. Trailing stops (ADAPTIVE — Layer 1 TDD) ──────────────────────────────
    if (-not $SkipTrailing) {
        Write-Host "`n[TRAIL] Atualizando posicoes abertas (modo adaptativo)..." -ForegroundColor DarkGreen
        
        # 2026-06-01: Sincronizar posições com exchange ANTES de atualizar
        # Detecta mudanças manuais feitas na ferramenta
        try { Sync-TrailingPositionsWithExchange } catch { Write-MasterLog "Sync trailing erro: $_" "WARN" }
        
        try { Update-TrailingStopsAdaptive } catch { Write-MasterLog "Trailing adaptativo erro: $_" "WARN" }
        Show-TrailingStatus
        
        # ── Layer 2: Mentor Reflection (6h checkpoint reviews) ──────────────────
        try { Update-MentorReview } catch { Write-MasterLog "Mentor review erro: $_" "WARN" }
        
        # ── Layer 4: Tori Proximity + Time-Based Stops ──────────────────────────
        try { Update-Layer4Review } catch { Write-MasterLog "Layer4 review erro: $_" "WARN" }

        # ── Layer 5: Moon Bag review (advisory por padrão) ──────────────────────
        try { Update-MoonBagReview } catch { Write-MasterLog "Layer5 MoonBag review erro: $_" "WARN" }

        # ── Validation Snapshot (Opção 2) — registrar estado a cada ciclo ───────
        try { Write-ValidationSnapshot } catch { Write-MasterLog "Validation snapshot erro: $_" "WARN" }
        
        $trailActive = @(Get-TrailingPositions) | Where-Object { $_.active }
        $trailLines  = if ($trailActive -and @($trailActive).Count -gt 0) {
            $trailActive | ForEach-Object { "$($_.market) $($_.side) fase=$($_.phase) stop=$($_.stopCurrent)" }
        } else { @("nenhuma") }
    }

    # ── 2. GemScan ───────────────────────────────────────────────────────────
    if (-not $SkipGem) {
        $gems = @(Invoke-GemCycle -DryRun:$DryRun)
    }

    # ── 2.5 Daily Loss Circuit Breaker (pre-trade) ───────────────────────────
    # Bloqueia execucao do orchestrator se equity caiu > threshold no dia.
    # Threshold default -5% (configurable via $global:DAILY_LOSS_THRESHOLD_PCT).
    # Em DryRun, registra mas nao bloqueia (paper continua coletando dados).
    $dailyLossBlocked = $false
    if (-not $SkipOrchestrator -and (Get-Command Test-DailyLossCircuit -ErrorAction SilentlyContinue)) {
        try {
            # 2026-05-19 PM: rastreia TOTAL CoinEx (spot + futures) em vez de so futures.
            # User confirmou pool de teste ~$2200 distribuido entre wallets; spot e capital
            # disponivel pra rebalance/oportunidade, nao reserva morta. Daily CB monitora
            # equity consolidada.
            $currentCap = 0.0
            if (Get-Command CoinEx-GetTotalCapitalUSDT -ErrorAction SilentlyContinue) {
                $currentCap = [double](CoinEx-GetTotalCapitalUSDT)
            } elseif (Get-Command CoinEx-GetFuturesCapitalUSDT -ErrorAction SilentlyContinue) {
                $currentCap = [double](CoinEx-GetFuturesCapitalUSDT)
            }
            if ($currentCap -gt 0) {
                $eq = Get-DailyEquityDelta -CurrentEquityUsd $currentCap
                # 2026-05-19 PM (vuln #7): threshold escala com capital se Get-CapitalScaledDailyLossThreshold disponivel.
                # Capital pequeno ($2.7K) = -2% cap (vs -5% legacy). Protege fase fragil.
                # Override via $global:DAILY_LOSS_THRESHOLD_PCT mantido (legacy).
                $threshold = if ($null -ne $global:DAILY_LOSS_THRESHOLD_PCT) {
                    [double]$global:DAILY_LOSS_THRESHOLD_PCT
                } elseif (Get-Command Get-CapitalScaledDailyLossThreshold -ErrorAction SilentlyContinue) {
                    Get-CapitalScaledDailyLossThreshold -CapitalUsd $currentCap
                } else {
                    -5.0
                }
                # B17 fix 2026-05-20 PM6+: fail-closed quando state corrupt (era silent fail-open)
                $cb = if ($eq.corrupt) {
                    Test-DailyLossCircuit -EquityTodayPct $eq.delta_pct -ThresholdPct $threshold -StateCorrupt
                } else {
                    Test-DailyLossCircuit -EquityTodayPct $eq.delta_pct -ThresholdPct $threshold
                }
                if (-not $cb.passes) {
                    $dailyLossBlocked = $true
                    $cbMsg = "DAILY LOSS CB DISPAROU: equity ${eq.delta_pct}% (threshold ${threshold}%) -- start=$($eq.start_equity) cur=$($eq.current_equity)"
                    Write-MasterLog $cbMsg "ERROR"
                    if (-not $DryRun) {
                        try { Send-TelegramAlert -Message "<b>DAILY LOSS CIRCUIT</b>`n$cbMsg`n`nOrchestrator pulado neste ciclo." | Out-Null } catch {}
                    }
                } elseif ($eq.first_call) {
                    Write-MasterLog "DailyLoss baseline registrado: start=$($eq.start_equity) USD" "INFO"
                }
            }
        } catch {
            Write-MasterLog "DailyLoss check erro: $_" "WARN"
        }
    }

    # ── 3. Pre-screen + Orchestrator ─────────────────────────────────────────
    if (-not $SkipOrchestrator -and -not $dailyLossBlocked) {
        $watchlist = if ($ForcePair) {
            @($ForcePair)
        } elseif ($Pairs -and $Pairs.Count -gt 0) {
            $Pairs
        } else {
            # Scanner UNIVERSAL: spot + futures USDT (~1.250 pares CoinEx)
            Write-Host "`n[SCANNER] Varrendo universo CoinEx (spot + futures)..." -ForegroundColor Cyan
            $scannerResults = @(Get-ScannerCandidates -TopN 20 -MinVolUsd 500000 -IncludeSpot)

            # Tier 2 (2026-05-17): forca inclusao de Tier A LIVE/PAPER da per_asset_whitelist
            $quantMode = if ($global:QUANT_WHITELIST_MODE) { $global:QUANT_WHITELIST_MODE } else { "LIVE" }
            try {
                # Item 1 (2026-05-28): regime-aware tier_level -- ativos BEAR rebaixados para tier 3
                # liberando slots para candidatos organicos quando whitelist inteira esta em BEAR.
                $regimeProviderBlock = $null
                if (Get-Command Get-MarketRegimeFromCache -ErrorAction SilentlyContinue) {
                    $regimeProviderBlock = { param($m) Get-MarketRegimeFromCache -Market $m }
                }
                $mergeArgs = @{ Candidates = $scannerResults; Mode = $quantMode }
                if ($regimeProviderBlock) { $mergeArgs.RegimeProvider = $regimeProviderBlock }

                # Item 1 fix 2026-05-29: AnchorMarkets restringe forcados a apenas BTC.
                # Antes: 11 markets da whitelist forcavam o top-10 inteiro -> INJ aparecia
                # em todos os ciclos monopolizando slot. Agora: apenas BTC e anchor
                # (always-on); os demais (INJ/RENDER/CFG/ZEC/PENDLE/SUI/SKY/XRP/BCH/XMR)
                # competem como organicos pelo compScore real do scanner.
                # Override via $global:ANCHOR_MARKETS em config.local.ps1 (opt-in).
                $anchorList = if ($global:ANCHOR_MARKETS) { @($global:ANCHOR_MARKETS) } else { @("BTCUSDT") }
                $mergeArgs.AnchorMarkets = $anchorList

                $scannerResults = @(Merge-QuantWhitelistIntoCandidates @mergeArgs)
            } catch {
                Write-MasterLog "WARN: Merge-QuantWhitelistIntoCandidates falhou -- $($_.Exception.Message)"
            }

            # Wave 2.5: indexa scannerResults por market para que o orchestrator
            # possa receber -ScannerInfo (score/change/volume) no Context.
            $global:SCANNER_INDEX = @{}
            foreach ($sr in $scannerResults) { $global:SCANNER_INDEX[$sr.market] = $sr }

            # 2026-05-21: auto-enqueue FQS para markets discovered sem registry entry.
            # Antes: so Mentor enqueava, mas markets blocked antes (Tier D / gem track) escapavam.
            try {
                $enqStats = @{ enqueued = 0; skipped = 0 }
                foreach ($sr in $scannerResults) {
                    $r = Add-FqsEnrichmentRequest -Market $sr.market -Source "scan_master_discovery"
                    if ($r.action -eq 'enqueued') { $enqStats.enqueued++ } else { $enqStats.skipped++ }
                }
                if ($enqStats.enqueued -gt 0) {
                    Write-MasterLog "INFO: FQS auto-enqueue -- $($enqStats.enqueued) novo(s), $($enqStats.skipped) skip"
                }
            } catch {
                Write-MasterLog "WARN: FQS auto-enqueue falhou -- $($_.Exception.Message)"
            }

            # Item 2 fix 2026-05-29: drain FQS inline ANTES do orchestrator V6.
            # Antes: enqueue acima marca markets na fila, mas processamento (python
            # coingecko_enrichment) so rodava no cron separado -- markets novos
            # chegavam ao orchestrator com "FQS indisponivel" e eram vetados.
            # Agora: enriquecimento sincrono dos faltantes (max 10 por ciclo, 30s
            # timeout). Fail-soft: se python ausente ou timeout, segue sem bloquear.
            # Toggle off via $global:FQS_DRAIN_DISABLED = $true em config.local.ps1.
            if (-not $global:FQS_DRAIN_DISABLED -and (Get-Command Invoke-FqsEnrichmentDrain -ErrorAction SilentlyContinue)) {
                try {
                    $invoker = $null
                    if (Get-Command New-CoingeckoFqsInvoker -ErrorAction SilentlyContinue) {
                        $invoker = New-CoingeckoFqsInvoker
                    }
                    $marketsList = @($scannerResults | ForEach-Object { $_.market } | Where-Object { $_ })
                    $drainStats = Invoke-FqsEnrichmentDrain `
                        -Markets $marketsList `
                        -Invoker $invoker `
                        -MaxMarkets 10 `
                        -TimeoutSec 30
                    if ($drainStats.enriched -gt 0) {
                        Write-MasterLog ("INFO: FQS drain -- enriched={0} skipped_registered={1} overflow={2}" -f $drainStats.enriched, $drainStats.skipped_registered, $drainStats.skipped_overflow)
                    }
                    if ($drainStats.failed) {
                        Write-MasterLog ("WARN: FQS drain falhou -- {0}" -f $drainStats.error)
                    }
                } catch {
                    Write-MasterLog "WARN: FQS drain exception -- $($_.Exception.Message)"
                }
            }

            # ── Universe Sweep + Hit-Rate (zero API extra; usa $global:LAST_UNIVERSE_SNAPSHOT) ──
            # N dinamico do GEM_SAFETY.MaxGemsPerDay (fallback 10). Circuit breaker:
            # se safety pausado, N=0 -> nao computa top movers (so universe + gate stats).
            try {
                if ($global:LAST_UNIVERSE_SNAPSHOT -and (Get-Command Get-UniverseSnapshot -ErrorAction SilentlyContinue)) {
                    $usN = 10
                    $usPaused = $false
                    if ($global:GEM_SAFETY -and $global:GEM_SAFETY.MaxGemsPerDay) {
                        $usN = [int]$global:GEM_SAFETY.MaxGemsPerDay
                    }
                    # Reconcilia circuit-breaker do gem_safety se existir
                    if (Get-Command Test-GemSafety -ErrorAction SilentlyContinue) {
                        try {
                            $safetyState = Test-GemSafety
                            if ($safetyState -and $safetyState.paused) { $usPaused = $true }
                        } catch {}
                    }
                    if ($usPaused) { $usN = 0 }

                    $usSnap = Get-UniverseSnapshot -Pairs $global:LAST_UNIVERSE_SNAPSHOT -TopN $usN
                    Write-MasterLog (Format-UniverseLogEntry -Snapshot $usSnap)
                    Write-MasterLog (Format-GateQualityEntry -GateStats $usSnap.gate_stats)

                    if ($usN -gt 0) {
                        $scannerSymbols = @($scannerResults | ForEach-Object { $_.market })
                        $longSyms  = @($usSnap.top_long_movers  | ForEach-Object { $_.symbol })
                        $shortSyms = @($usSnap.top_short_movers | ForEach-Object { $_.symbol })
                        $longCmp  = Compare-ScannerVsUniverse -ScannerTopN $scannerSymbols -UniverseMovers $longSyms  -Direction "LONG"
                        $shortCmp = Compare-ScannerVsUniverse -ScannerTopN $scannerSymbols -UniverseMovers $shortSyms -Direction "SHORT"
                        Write-MasterLog (Format-HitRateEntry -Comparison $longCmp)
                        Write-MasterLog (Format-HitRateEntry -Comparison $shortCmp)
                    }
                }
            } catch {
                Write-MasterLog "Universe Sweep falhou: $_" "WARN"
            }
            # ── /Universe Sweep ───────────────────────────────────────────────
            if ($scannerResults.Count -gt 0) {
                # Mostra todos os top, marcando SPOT-only (monitorados mas nao roteados ao orchestrator)
                Write-Host "  Top 20 pares por momentum x volume:" -ForegroundColor DarkCyan
                $scannerResults | Select-Object -First 15 | ForEach-Object {
                    $sign = if ($_.change -ge 0) { "+" } else { "" }
                    $tag  = if ($_.marketType -eq "SPOT") { "[SPOT]" } else { "[FUT] " }
                    Write-Host ("    {0} {1,-12} change={2}{3,7:F2}% vol={4,6:F1}M score={5}" -f $tag, $_.market, $sign, $_.change, ($_.volume/1000000), $_.score) -ForegroundColor DarkCyan
                }
                # Orchestrator opera apenas em pares FUTURES (margem isolada, stop nativo)
                $futureCandidates = @($scannerResults | Where-Object { $_.marketType -eq "FUTURES" })
                if ($futureCandidates.Count -eq 0) {
                    Write-Host "  [Aviso] Nenhum candidato com futuros - usando watchlist default" -ForegroundColor DarkYellow
                    $DEFAULT_WATCHLIST
                } else {
                    Write-Host ("  {0} pares com futuros vao ao pre-screen (spot monitorado mas nao operado pelo orchestrator)" -f $futureCandidates.Count) -ForegroundColor Cyan
                    @($futureCandidates | ForEach-Object { $_.market })
                }
            } else {
                Write-Host "  Scanner falhou - usando watchlist default" -ForegroundColor DarkYellow
                $DEFAULT_WATCHLIST
            }
        }

        Write-Host "`n[SCAN] Pre-filtrando $($watchlist.Count) pares..." -ForegroundColor Cyan
        $candidates = @()

        # FASE 4 part 2 fix 2026-05-21: Tier A LIVE markets (BTC/RENDER/INJ/XMR)
        # passam por pre-screen mas perdem o forced-priority quando $candidates eh
        # reconstruido. Sort por compScore enterra estaveis low-momentum. Construir
        # set de markets forcados PRE-screen, propagar flag, e usar como sort primario.
        # FASE 4 p4 (2026-05-21 sessao extra): tambem propagar tier_level pra ordenar
        # Tier A LIVE > Tier B PAPER > scanner. Antes com Mode=PAPER 11 forced disputavam
        # top-7, RENDER/XMR (Tier A, low compScore) eram bumped por BCH/SKY (Tier B).
        $forcedSet = @{}
        $tierLevelSet = @{}
        if ($scannerResults) {
            foreach ($sr in $scannerResults) {
                if ($sr.PSObject.Properties['source'] -and $sr.source -like 'quant_whitelist_*') {
                    $forcedSet[$sr.market] = $true
                    if ($sr.PSObject.Properties['tier_level']) {
                        $tierLevelSet[$sr.market] = [int]$sr.tier_level
                    } else {
                        $tierLevelSet[$sr.market] = 2  # fallback: trata como Tier B
                    }
                }
            }
        }

        foreach ($mkt in $watchlist) {
            try {
                $td = Get-TechData -Market $mkt
                if (-not $td -or -not $td.tf1h) { continue }

                $tf1h = $td.tf1h
                $tf1d = $td.tf1d
                $adx  = if ($tf1d) { [double]$tf1d.adx.adx } else { [double]$tf1h.adx.adx }
                $rsi  = [double]$tf1h.rsi
                $ema9 = [double]$tf1h.ema9; $ema21 = [double]$tf1h.ema21
                $vol  = [double]$tf1h.vol.ratio

                # Bug A fix: RSI trend-aware via Test-ScanPreScreen substitui regra
                # estatica antiga ($rsi -ge 28 -and $rsi -le 78). RSI 78-88 agora passa
                # SE vol >= 1.5x AND ADX >= 25 (breakout confirmado). Acima de 88 ou
                # abaixo de 28 -> rejeita. Caso HYPE 14/05 (RSI 80, vol 4.46x, ADX 29)
                # agora entra na pre-selecao.
                $rsiOk = Test-ScanPreScreen -Rsi $rsi -Adx $adx -Vol $vol
                $passes = @(
                    ($adx -ge 18),
                    $rsiOk,
                    (($ema9 -gt 0 -and $ema21 -gt 0) -and ([math]::Abs($ema9-$ema21)/$ema21 -ge 0.0002)),
                    ($vol -ge 0.5)
                ) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count

                # FASE 4 part 3 fix 2026-05-21: bypass pre-screen passes>=3 para markets
                # whitelist-forced. Tier A LIVE eh curado (Bailey-Lopez/Simons gates ja validados),
                # pre-screen tecnico nao deve filtrar mais. BTC/RENDER/XMR podem ter RSI/ADX/vol
                # fora dos thresholds em fases de consolidacao mas ainda merecem orchestrator.
                $isForced = [bool]$forcedSet[$mkt]
                if ($passes -ge 3 -or $isForced) {
                    # Momentum 24h vem do scanner index (campo change% absoluto).
                    # Fallback: usa 0 quando candidato veio de watchlist default (sem scanner).
                    $momentumPct = 0.0
                    if ($global:SCANNER_INDEX -and $global:SCANNER_INDEX.ContainsKey($mkt)) {
                        $momentumPct = [math]::Abs([double]$global:SCANNER_INDEX[$mkt].change)
                    }
                    # Bug B fix: armazena score composto para ranking top-N.
                    $compScore = Get-ScannerCompositeScore -VolSpike $vol -MomentumPct $momentumPct -Adx $adx
                    # B. Tori PROXIMITY boost 2026-05-22: opt-in flag pra priorizar markets
                    # com setup_ripening no sort top-N. +1000 bump => ripening sobe a topo
                    # independente do compScore base. Zero risco LIVE (flag ausente = no-op).
                    $ripeningBoost = 0; $ripeningTag = ''
                    $boostFlag = Join-Path (Split-Path $PSScriptRoot -Parent) "journal\TORI_PROXIMITY_BOOST.flag"
                    if ((Test-Path $boostFlag) -and (Get-Command Get-ToriProximityForMarket -ErrorAction SilentlyContinue)) {
                        try {
                            $statePath = Join-Path (Split-Path $PSScriptRoot -Parent) "journal\tori_proximity_state.json"
                            $tp = Get-ToriProximityForMarket -Market $mkt -StatePath $statePath -MaxAgeMinutes 30
                            if ($tp -and [bool]$tp.setup_ripening) {
                                $ripeningBoost = 1000
                                $ripeningTag   = " [TORI-RIPE-$($tp.side)]"
                            }
                        } catch {}
                    }
                    $compScoreBoosted = $compScore + $ripeningBoost
                    # FASE 4 p4: tier_level 1=A_LIVE, 2=B_PAPER, 99=scanner natural.
                    $tierLevel = if ($tierLevelSet.ContainsKey($mkt)) { [int]$tierLevelSet[$mkt] } else { 99 }
                    $candidates += [PSCustomObject]@{ market=$mkt; adx=$adx; rsi=$rsi; vol=$vol; momentum=$momentumPct; compScore=$compScoreBoosted; compScoreBase=$compScore; ripeningBoost=$ripeningBoost; passes=$passes; isWhitelistForced=$isForced; tierLevel=$tierLevel }
                    $forcedTag = if ($isForced) { " [WL-T$tierLevel]" } else { '' }
                    Write-Host "  + $mkt (adx=$([math]::Round($adx,1)) rsi=$([math]::Round($rsi,1)) vol=$([math]::Round($vol,2))x mom=$([math]::Round($momentumPct,2))% comp=$compScoreBoosted passes=$passes/4)$forcedTag$ripeningTag" -ForegroundColor DarkCyan
                } else {
                    Write-Host "  - $mkt bloqueado ($passes/4 passes)" -ForegroundColor DarkGray
                }
            } catch { Write-Host "  ? $mkt erro: $_" -ForegroundColor DarkGray }
        }

        # Calibracao cascade V6 (2026-05-15): respeita $global:ORCHESTRATOR_TOPN_OVERRIDE
        # quando setado em config.local.ps1; caso contrario usa o parametro -OrchestratorTopN
        # (default 3). Override valido = 1..20; valor invalido -> fallback para 3.
        $effectiveTopN = Get-OrchestratorTopN -Default $OrchestratorTopN
        $topN = if ($ForcePair) { 1 } else { $effectiveTopN }
        # Item 1 fix 2026-05-29: Select-TopCandidates (lib_top_candidates.ps1)
        # substitui Sort-Object | Select -First N puro. Por que:
        # - Antes: 11 forcados monopolizavam top-10 -> 0 organicos competiam.
        # - Agora: forcados (apenas BTC anchor) ficam SEMPRE vivos, FORA da contagem
        #   do TopN. TopN e preenchido por candidatos organicos reais ranqueados
        #   por compScore. Resultado: BTC + top-N organicos competindo.
        # ForcePair (1 candidato manual): -OrganicTopN 1 mantem comportamento legacy.
        $topCandidates = @(Select-TopCandidates -Candidates $candidates -OrganicTopN $topN)

        # ── SHORT Block 2 (2026-05-28): injeta candidatos SHORT do short_alerts.jsonl ──
        # short_scanner.ps1 detecta sinais (vol climax + RSI overbought) e escreve
        # short_alerts.jsonl. Aqui lemos e injetamos no pipeline do orchestrator.
        # Regimes com edge comprovado: BEAR_STRONG/BEAR_WEAK (+0.56R), SIDEWAYS (+0.34R),
        # TRANSITION_UP bounce failure (+0.81R). Whitelist ja atualizada para execute/observe.
        if (-not $SkipOrchestrator -and (Get-Command Get-ShortCandidatesFromAlerts -ErrorAction SilentlyContinue)) {
            try {
                $shortAlertsPath = Join-Path $scriptDir "..\journal\short_alerts.jsonl"
                $shortCandidates = @(Get-ShortCandidatesFromAlerts `
                    -AlertsPath $shortAlertsPath `
                    -MaxAgeHours 2 `
                    -ExcludeMarkets $topCandidates)
                if ($shortCandidates.Count -gt 0) {
                    $topCandidates = @(Merge-ShortCandidatesIntoScan `
                        -LongCandidates $topCandidates `
                        -ShortAlerts $shortCandidates)
                    Write-MasterLog "SHORT Block2: $($shortCandidates.Count) candidato(s) SHORT injetado(s) -- $($shortCandidates.market -join ',')"
                }
            } catch {
                Write-MasterLog "SHORT Block2 inject falhou (nao critico): $_" "WARN"
            }
        }

        if ($topCandidates.Count -eq 0) {
            Write-MasterLog "Nenhum par passou o pre-screen - Orchestrator pulado" "WARN"
        } else {
            Write-Host "`n[ORCH] $($topCandidates.Count) candidatos para analise completa..." -ForegroundColor Cyan

            # ── Pre-fetch paralelo opt-in: roda Invoke-OrchestratorV6 em RunspacePool ──
            # Speedup esperado: ~2.5x para 5+ candidatos. Default OFF (preserva path serial estavel).
            # 3 vias pra ativar paralelo (qualquer uma vence):
            #   1. flag -Parallel na linha de comando
            #   2. $global:ORCHESTRATOR_PARALLEL = $true em config.local.ps1
            #   3. arquivo journal/PARALLEL_DEFAULT_ENABLED.flag (rollout gradual)
            $parallelFlagFile = Join-Path $scriptDir "..\journal\PARALLEL_DEFAULT_ENABLED.flag"
            $useParallel = $Parallel.IsPresent `
                -or ($global:ORCHESTRATOR_PARALLEL -eq $true) `
                -or (Test-Path $parallelFlagFile)
            $preFetched  = @{}
            if ($useParallel -and $topCandidates.Count -ge 2 -and (Get-Command Invoke-OrchestratorCandidatesParallel -ErrorAction SilentlyContinue)) {
                Write-Host ("  [PARALLEL] Pre-fetching {0} candidatos via RunspacePool (concurrency={1})..." -f $topCandidates.Count, $ParallelMaxConcurrency) -ForegroundColor DarkCyan
                $parInputs = @()
                foreach ($c in $topCandidates) {
                    $si = $null
                    if ($global:SCANNER_INDEX -and $global:SCANNER_INDEX.ContainsKey($c.market)) {
                        $sr = $global:SCANNER_INDEX[$c.market]
                        $si = [PSCustomObject]@{ score = $sr.score; change = $sr.change; volume = $sr.volume }
                    }
                    $parInputs += [PSCustomObject]@{
                        market   = $c.market
                        scanInfo = $si
                        mode     = if ($DryRun) { "paper" } else { "live" }
                        dryRun   = $DryRun.IsPresent
                    }
                }
                $parStart = Get-Date
                try {
                    $parResults = Invoke-OrchestratorCandidatesParallel `
                        -Candidates $parInputs `
                        -MaxConcurrency $ParallelMaxConcurrency `
                        -AgentsDir $agentsDir
                    foreach ($pr in $parResults) {
                        if ($pr.ok) { $preFetched[$pr.market] = $pr.result }
                        else { Write-MasterLog "Parallel orch $($pr.market) falhou: $($pr.error)" "WARN" }
                    }
                    $parElapsed = [math]::Round(((Get-Date) - $parStart).TotalSeconds, 1)
                    Write-MasterLog ("Parallel orchestrator: {0}/{1} resultados em {2}s" -f $preFetched.Count, $topCandidates.Count, $parElapsed)
                } catch {
                    Write-MasterLog "Parallel orchestrator falhou (fallback serial): $_" "WARN"
                    $preFetched = @{}
                }
            }

            foreach ($c in $topCandidates) {
                Write-Host "`n  === $($c.market) ===" -ForegroundColor Yellow
                try {
                    $orchArgs = @{ Market = $c.market }
                    if ($DryRun) { $orchArgs.DryRun = $true }
                    # Wave 2.5: propaga scanner info + mode para Invoke-OrchestratorV6
                    # (alimenta whitelist gate via Context.scanner_score + Context.mode).
                    $scanInfo = $null
                    if ($global:SCANNER_INDEX -and $global:SCANNER_INDEX.ContainsKey($c.market)) {
                        $sr = $global:SCANNER_INDEX[$c.market]
                        $scanInfo = [PSCustomObject]@{
                            score  = $sr.score
                            change = $sr.change
                            volume = $sr.volume
                        }
                    }
                    $orchArgs.ScannerInfo = $scanInfo
                    $orchArgs.Mode        = if ($DryRun) { "paper" } else { "live" }
                    # Usa pre-fetch paralelo quando disponivel; senao chamada serial padrao.
                    $result = if ($preFetched.ContainsKey($c.market)) { $preFetched[$c.market] } else { Invoke-OrchestratorV6 @orchArgs }

                    # Estrutura V6: triagem.tier, triagem.score_predicted, mesa.consensus,
                    # mesa.sinal_consenso, cascade.motivo. Fallback p/ campos legados
                    # (scorePonderado/sinalTech) quando V6 retorna pipeline antigo.
                    $tier      = if ($result.triagem)             { $result.triagem.tier }            else { $null }
                    # 2026-05-15 EUREKA A fix: emitir AMBOS scanner_score (deterministico,
                    # input do tier) e score_predicted (LLM-gerado, cosmetico).
                    # Diagnose journal: log antigo "score=X" era ambiguo (X mudava de fonte
                    # conforme cascade abortava ou nao).
                    $scannerScore = $null
                    if ($scanInfo -and $null -ne $scanInfo.score) {
                        $scannerScore = $scanInfo.score
                    } elseif ($null -ne $result.scorePonderado) {
                        $scannerScore = $result.scorePonderado
                    } elseif ($result.mesa)                       {
                        $scannerScore = $result.mesa.score_avg
                    }
                    $scorePredicted = if ($result.triagem) { $result.triagem.score_predicted } else { $null }

                    $direction = if ($result.mesa -and $result.mesa.sinal_consenso) { $result.mesa.sinal_consenso }
                                 elseif ($result.sinalTech)       { $result.sinalTech }
                                 else { $null }
                    $consensus = if ($result.mesa)                { $result.mesa.consensus }          else { $null }
                    # Wave 2.5 bugfix: regime do log vem do triagem.regime (canonico),
                    # NUNCA do macro.macro_bias (BULLISH/NEUTRAL/BEARISH e nao canonico).
                    $regimeCtx = Resolve-RegimeForLog -Result $result
                    $razao     = if ($result.motivo)              { $result.motivo }                  else { $null }

                    $tradeLine = Format-TradeLogEntry `
                        -Timestamp      (Get-Date -Format 'HH:mm:ss') `
                        -Market         $c.market `
                        -Decision       $result.decisao `
                        -Regime         $regimeCtx `
                        -Direction      $direction `
                        -ScannerScore   $scannerScore `
                        -ScorePredicted $scorePredicted `
                        -Razao          $razao `
                        -Tier           $tier `
                        -ConsensusMesa  $consensus
                    # Write-MasterLog ja prefixa [HH:mm:ss] [LEVEL]; passamos somente o payload
                    # apos o prefixo "[TRADE] " para evitar duplicacao.
                    $payload = $tradeLine -replace '^\[\d{2}:\d{2}:\d{2}\]\s+\[TRADE\]\s+', ''
                    Write-MasterLog $payload "TRADE"
                    
                    # 2026-05-29: Arquivar razao completa em JSONL para auditoria
                    # (razao foi truncada no log master para evitar inflacao de contexto)
                    if ($razao -and (Get-Command Add-TradeReasonArchive -ErrorAction SilentlyContinue)) {
                        try {
                            Add-TradeReasonArchive -Market $c.market -Decision $result.decisao -FullReason $razao
                        } catch {
                            Write-Warning "Falha ao arquivar razao de trade: $_"
                        }
                    }
                    
                    $orchResults += $result
                    if ($result.decisao -eq "EXECUTAR" -and $result.ordemId) {
                        # Layer 5 wire (opt-in via journal/MOON_BAG_ENABLED.flag)
                        # Orchestrator nao retorna sizing_usd direto - inferimos
                        # de capital * sizing_pct se disponivel, senao usa 0
                        # (fallback trailing classico).
                        $orchSize = 0.0
                        if ($result.PSObject.Properties['sizing_usd'] -and $result.sizing_usd) {
                            $orchSize = [double]$result.sizing_usd
                        } elseif ($result.capital -and $result.capital -gt 0) {
                            # 1% default sizing, conservador pra Moon Bag opt-in
                            $orchSize = [double]$result.capital * 0.01
                        }
                        Register-PositionTrailing `
                            -Market  $result.market `
                            -Side    $result.sinalTech `
                            -Entry   $result.entryPrice `
                            -Stop    $result.stopLoss `
                            -Target  $result.alvo1 `
                            -OrderId $result.ordemId `
                            -Source  "orchestrator" `
                            -Size    $orchSize
                    }
                } catch {
                    $errMsg = "$_"
                    $stackTop = ""
                    if ($_.ScriptStackTrace) {
                        $stackTop = ($_.ScriptStackTrace -split "`n" | Select-Object -First 3) -join " | "
                    } elseif ($_.InvocationInfo) {
                        $stackTop = "at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)"
                    }
                    Write-MasterLog "Orchestrator $($c.market) erro: $errMsg :: $stackTop" "ERROR"
                }
            }
        }
    }

    $elapsed = [math]::Round(((Get-Date) - $cycleStart).TotalSeconds, 1)
    $candidateCount = $candidates.Count
    $topCount = $topCandidates.Count
    Write-MasterLog "Ciclo concluido em ${elapsed}s | gems=$($gems.Count) candidates=$candidateCount top=$topCount"

    # ── Resumo Telegram ───────────────────────────────────────────────────────
    try {
        $nextTs  = (Get-Date).AddMinutes($Seasonal.scanIntervalMin).ToString("HH:mm")

        $trailSummary = if ($trailLines -and @($trailLines)[0] -ne "nenhuma") {
            ($trailLines -join " | ")
        } else { "nenhuma posicao ativa" }

        $gemSummary = if ($gems.Count -gt 0) {
            ($gems | ForEach-Object { "$($_.market) score=$($_.score) $($_.mode)" }) -join " | "
        } else { "nenhum encontrado" }

        $passedMkts = if ($candidates -and @($candidates).Count -gt 0) {
            ($candidates | ForEach-Object { $_.market }) -join " "
        } else { "nenhum" }
        $watchCount = if ($SkipOrchestrator) { 0 } else { if ($Pairs -and $Pairs.Count -gt 0) { $Pairs.Count } else { $DEFAULT_WATCHLIST.Count } }
        $scanSummary = "$watchCount pares | passou: $passedMkts"

        $orchSummary = if ($orchResults -and @($orchResults).Count -gt 0) {
            ($orchResults | ForEach-Object {
                $dec = $_.decisao -replace "DRY_RUN_",""
                "$($_.market) $dec($($_.scorePonderado)) $($_.sinalTech)"
            }) -join " | "
        } else { "nenhum par analisado" }

        # Cycle filter V6: so dispara cycle summary se houve "news"
        $mesaPassed = if ($orchResults) {
            @($orchResults | Where-Object { $_.decisao -match "EXECUTAR" }).Count
        } else { 0 }
        $execCount = if ($orchResults) {
            @($orchResults | Where-Object { $_.decisao -eq "EXECUTAR" -and $_.ordemId }).Count
        } else { 0 }
        $trailChg = if ($global:TRAIL_PHASE_CHANGES_THIS_CYCLE) { [int]$global:TRAIL_PHASE_CHANGES_THIS_CYCLE } else { 0 }

        $hasNews = if (Get-Command Test-CycleHasNews -ErrorAction SilentlyContinue) {
            Test-CycleHasNews -GemCount $gems.Count -MesaPassed $mesaPassed -TrailPhaseChg $trailChg -Executions $execCount
        } else { $true }

        if ($hasNews) {
            # Format-TgCycleSummary: mensagem estruturada com contadores e detalhes
            $orchForFmt = if ($orchResults -and @($orchResults).Count -gt 0) {
                ($orchResults | ForEach-Object {
                    $dec = $_.decisao -replace "DRY_RUN_",""
                    "$($_.market) $dec()"
                }) -join " | "
            } else { "" }
            $msg = if (Get-Command Format-TgCycleSummary -ErrorAction SilentlyContinue) {
                Format-TgCycleSummary `
                    -Window $Seasonal.window `
                    -MomentScore $Seasonal.momentScore `
                    -TrailSummary $trailSummary `
                    -GemSummary $gemSummary `
                    -ScanSummary $scanSummary `
                    -OrchSummary $orchForFmt `
                    -NextMin $Seasonal.scanIntervalMin `
                    -NextTime $nextTs `
                    -ElapsedSec ([int]$elapsed) `
                    -DryRun:$DryRun
            } else {
                $dryTag = if ($DryRun) { " [DRYRUN]" } else { "" }
                "CICLO$dryTag | janela=$($Seasonal.window) | $nextTs`ngems=$($gems.Count) scan=$scanSummary orch=$orchForFmt trail=$trailSummary`nProximo: ${($Seasonal.scanIntervalMin)}min"
            }
            Send-TelegramAlert -Message $msg | Out-Null
        } else {
            Write-MasterLog "Cycle filter: nenhuma news (gems=0 mesa=0 trail=0 exec=0) -- TG silencioso"
            # Heartbeat opt-in: 1x/hora confirma "vivo, sem noticias" (default ON apos 2026-05-17)
            $hbEnabled = if ($null -ne $global:HEARTBEAT_ENABLED) { [bool]$global:HEARTBEAT_ENABLED } else { $true }
            $hbInterval = if ($global:HEARTBEAT_INTERVAL_MIN) { [int]$global:HEARTBEAT_INTERVAL_MIN } else { 60 }
            $hbFile = Join-Path $PSScriptRoot "..\journal\heartbeat_last.txt"
            if (Get-Command Send-HeartbeatIfDue -ErrorAction SilentlyContinue) {
                $sent = Send-HeartbeatIfDue `
                    -LastHeartbeatFile $hbFile `
                    -IntervalMinutes $hbInterval `
                    -Window $Seasonal.window `
                    -NextMin $Seasonal.scanIntervalMin `
                    -NextTime $nextTs `
                    -WatchCount $watchCount `
                    -DryRun:$DryRun `
                    -Enabled:$hbEnabled
                if ($sent) { Write-MasterLog "Heartbeat enviado ao Telegram (interval=${hbInterval}min)" }
            }
        }
        # reset contador entre ciclos
        $global:TRAIL_PHASE_CHANGES_THIS_CYCLE = 0
    } catch {}
}

# ── Handler de comandos Telegram ──────────────────────────────────────────────
# Processa um comando recebido e retorna acao solicitada (scan/gem/cycle/$null).

function Invoke-TelegramCommand {
    param([PSCustomObject]$Cmd, [PSCustomObject]$Seasonal, [int]$RemainingMin, [string]$NextTime)

    Write-Host "  [CMD] /$($Cmd.command) $($Cmd.arg) (de: $($Cmd.from))" -ForegroundColor DarkMagenta

    switch ($Cmd.command) {

        { $_ -in "ajuda","help" } {
            Send-TelegramAlert -Message "Comandos: /status /scan /gem /pausar /retomar /fechar PAR /ajuda" | Out-Null
        }

        { $_ -in "custos","cost" } {
            try {
                Send-TelegramAlert -Message (Format-TgCostReport) | Out-Null
                Write-MasterLog "Relatorio de custos enviado por $($Cmd.from)"
            } catch {
                Send-TelegramAlert -Message "<b>Erro ao gerar relatorio:</b> $_" | Out-Null
            }
        }

        "status" {
            $positions = @(Get-TrailingPositions) | Where-Object { $_.active }
            $posStr = if ($positions.Count -gt 0) { ($positions | ForEach-Object { "$($_.market) $($_.side)" }) -join ", " } else { "nenhuma" }
            $msg = "📊 STATUS | janela=$($Seasonal.window) | proximo=${RemainingMin}min ($NextTime)`nPosicoes: $posStr`nPausado: $global:MASTER_PAUSED"
            Send-TelegramAlert -Message $msg | Out-Null
        }

        "pausar" {
            $global:MASTER_PAUSED = $true
            Send-TelegramAlert -Message "<b>LOOP PAUSADO</b>`nEnvie /retomar para continuar." | Out-Null
            Write-Host "  [CMD] Loop pausado." -ForegroundColor Yellow
            Write-MasterLog "Loop pausado por comando Telegram ($($Cmd.from))" "WARN"
        }

        "retomar" {
            $global:MASTER_PAUSED = $false
            Send-TelegramAlert -Message "<b>LOOP RETOMADO</b>`nProximo ciclo em instantes." | Out-Null
            Write-Host "  [CMD] Loop retomado." -ForegroundColor Green
            Write-MasterLog "Loop retomado por comando Telegram ($($Cmd.from))"
            return "cycle"   # forca ciclo imediato
        }

        "fechar" {
            if ($Cmd.arg) {
                Close-TrailingPosition -Market $Cmd.arg -Reason "comando_telegram"
                Send-TelegramAlert -Message "<b>POSICAO FECHADA</b> -- $($Cmd.arg)`n<i>Comando manual de $($Cmd.from)</i>" | Out-Null
                Write-MasterLog "Trailing $($Cmd.arg) fechado manualmente por $($Cmd.from)" "WARN"
            } else {
                Send-TelegramAlert -Message "Uso: /fechar BTCUSDT" | Out-Null
            }
        }

        "scan" {
            if ($Cmd.arg) {
                # Analisa par especifico inline (continua aguardando depois)
                Send-TelegramAlert -Message "<b>SCAN MANUAL</b> -- $($Cmd.arg)`n<i>Iniciando analise...</i>" | Out-Null
                Write-MasterLog "Scan manual: $($Cmd.arg) por $($Cmd.from)"
                try { Invoke-MasterCycle -Seasonal $Seasonal -ForcePair $Cmd.arg } catch {
                    Send-TelegramAlert -Message "<b>Erro</b> ao analisar $($Cmd.arg): $_" | Out-Null
                }
                # Retorna $null para continuar aguardando o intervalo normal
            } else {
                # Forca ciclo completo imediato (interrompe o wait)
                Send-TelegramAlert -Message "<b>CICLO FORCADO</b>`n<i>Iniciando agora...</i>" | Out-Null
                Write-MasterLog "Ciclo forcado por comando Telegram ($($Cmd.from))"
                return "cycle"
            }
        }

        "gem" {
            # GemScan inline (continua aguardando depois)
            Send-TelegramAlert -Message "<b>GEMSCAN MANUAL</b>`n<i>Iniciando scan...</i>" | Out-Null
            Write-MasterLog "GemScan manual por $($Cmd.from)"
            try { Invoke-GemCycle -DryRun:$DryRun } catch {
                Send-TelegramAlert -Message "<b>Erro</b> no GemScan manual: $_" | Out-Null
            }
            # Retorna $null para continuar aguardando o intervalo normal
        }
    }

    return $null
}

# ── Espera com polling de comandos ────────────────────────────────────────────
# Substitui Start-Sleep no loop principal.
# Retorna: $null (tempo esgotado) | "cycle" | "gem" | "scan:BTCUSDT"

function Wait-WithCommands {
    param([int]$TotalMinutes, [PSCustomObject]$Seasonal)

    if ($TotalMinutes -le 0) { return $null }

    $endTime   = (Get-Date).AddMinutes($TotalMinutes)
    $chunkSec  = 15   # frequencia de polling de comandos

    while ($global:MASTER_PAUSED -or (Get-Date) -lt $endTime) {
        Start-Sleep -Seconds $chunkSec

        $cmds = @()
        # Ler comandos do arquivo de fila (escrito pelo telegram_listener.ps1)
        $cmdQueueFile = Join-Path $PSScriptRoot "..\journal\scan_master_cmd_queue.jsonl"
        if (Test-Path $cmdQueueFile) {
            try {
                $lines = Get-Content $cmdQueueFile -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($lines) {
                    $cmds = @($lines | ForEach-Object { $_ | ConvertFrom-Json -ErrorAction SilentlyContinue } | Where-Object { $_ })
                    Remove-Item $cmdQueueFile -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }
        foreach ($cmd in $cmds) {
            $remaining = [int](($endTime - (Get-Date)).TotalMinutes)
            if ($remaining -lt 0) { $remaining = 0 }
            $nextTime  = $endTime.ToString("HH:mm")
            $action = Invoke-TelegramCommand -Cmd $cmd -Seasonal $Seasonal -RemainingMin $remaining -NextTime $nextTime
            if ($action) { return $action }
        }

        # ── Fast-path event-driven: consome trigger de sinal-lider ───────────────
        # Sinais-lider (whale/faro/vol_climax/...) enfileiram triggers conviction-
        # gated no signal_triggers.jsonl. Aqui (polling 15s) disparamos analise full
        # (Mesa+Mentor) imediata e direcionada no mercado -- sem esperar o ciclo de
        # 30min. Inline + continua aguardando (mesmo padrao do comando /scan PAR).
        if (Get-Command Get-NextTriggerScan -ErrorAction SilentlyContinue) {
            try {
                $trg = Get-NextTriggerScan
                if ($trg -and $trg.market) {
                    if ($trg.mode -eq "observe") {
                        # Observe: so audit/alerta, NAO dispara analise/entrada.
                        Write-MasterLog "TRIGGER(observe) $($trg.signal) conv=$($trg.conviction) market=$($trg.market)"
                        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
                            try { Send-TelegramAlert -Message "<b>TRIGGER (obs)</b> $($trg.signal) conv $($trg.conviction)`n$($trg.market)" | Out-Null } catch {}
                        }
                    } else {
                        Write-MasterLog "TRIGGER $($trg.signal) conv=$($trg.conviction) -> scan direcionado $($trg.market)"
                        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
                            try { Send-TelegramAlert -Message "<b>TRIGGER</b> $($trg.signal) (conv $($trg.conviction))`nScan imediato: $($trg.market)" | Out-Null } catch {}
                        }
                        try { Invoke-MasterCycle -Seasonal $Seasonal -ForcePair $trg.market } catch {
                            Write-MasterLog "Erro no scan triggered $($trg.market): $_" "ERROR"
                        }
                    }
                }
            } catch {}
        }

        # Log de keepalive a cada 10 min para confirmar que o loop esta vivo
        $sinceStart = [int](($endTime - (Get-Date)).TotalSeconds)
        if ($sinceStart % 600 -lt $chunkSec) {
            Write-MasterLog "Aguardando... $([int](($endTime - (Get-Date)).TotalMinutes))min restantes janela=$($Seasonal.window)"
        }
    }

    return $null
}

# ── GEM STRATEGIES INTEGRATION (2026-06-09) ────────────────────────────────────

function Invoke-GemStrategies {
    <#
    .SYNOPSIS
        Run GEM discovery + execution (PULL_BACK_RECOVERY + DISTRIBUTION_SHORT)
    #>
    param([PSCustomObject] $Seasonal)

    # Load GEM libraries
    . (Join-Path (Split-Path $PSScriptRoot -Parent) "agents\lib_gem_discovery.ps1") 2>$null
    . (Join-Path (Split-Path $PSScriptRoot -Parent) "agents\lib_gem_router.ps1") 2>$null

    # Discover patterns
    $discoveries = Start-GemDiscoveryScanner -MaxResults 5

    if ($discoveries -and $discoveries.Count -gt 0) {
        Write-Host "`n📊 GEM STRATEGIES: $($discoveries.Count) discovery(ies) encontrada(s)" -ForegroundColor Green

        # Route each to execution
        foreach ($signal in $discoveries) {
            try {
                $result = Invoke-GemRouter -Signal $signal
                if ($result.executed) {
                    Write-Host "   ✅ Executado: $($signal.market) $($signal.strategy)" -ForegroundColor Green
                } else {
                    Write-Host "   ⚠️ Skipped: $($signal.market) - $($result.reason)" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "   ❌ Error: $($signal.market) - $_" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "`n⭕ GEM STRATEGIES: Nenhum padrão detectado neste ciclo" -ForegroundColor Gray
    }
}

# ── Loop principal ────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  SCAN MASTER -- Loop Mestre" -ForegroundColor Cyan
Write-Host "  GemScan + Orchestrator + Trailing + Comandos TG" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
# Initialize-TelegramOffset (skipped if not found)
"[DBG3 line852] DryRun=$DryRun" | Out-File -FilePath "$env:TEMP\dryrun_trace.log" -Append -Encoding utf8
# System start message
if (Get-Command Format-TgSystemStart -ErrorAction SilentlyContinue) {
    $_startMsg = if ($DryRun) { Format-TgSystemStart -DryRun } else { Format-TgSystemStart }
    Send-TelegramAlert -Message $_startMsg | Out-Null
}

$iteration = 0
do {
    $iteration++
    $seasonal = Get-SeasonalityContext
    $global:MASTER_LAST_SEASONAL = $seasonal

    if (-not $global:MASTER_PAUSED) {
        try {
            Invoke-MasterCycle -Seasonal $seasonal

            # GEM STRATEGIES: PULL_BACK_RECOVERY + DISTRIBUTION_SHORT (2026-06-09)
            try {
                Invoke-GemStrategies -Seasonal $seasonal
            } catch {
                Write-MasterLog "Erro em GEM STRATEGIES: $_" "WARN"
            }
        } catch {
            Write-MasterLog "Erro no ciclo $iteration`: $_" "ERROR"
            Send-TelegramAlert -Message "<b>ERRO</b> ScanMaster ciclo $iteration`n<i>$_</i>" | Out-Null
        }
    } else {
        Write-MasterLog "Ciclo $iteration pulado (loop pausado)" "WARN"
    }

    if ($Once) { break }

    # Intervalo: forcado ou sazonalidade
    $intervalMin = if ($ForceIntervalMin -gt 0) { $ForceIntervalMin } else { $seasonal.scanIntervalMin }
    $nextRun     = (Get-Date).AddMinutes($intervalMin)
    $nextRunStr  = $nextRun.ToString("HH:mm")

    Write-Host ""
    Write-Host "  Proximo ciclo em ${intervalMin}min ($nextRunStr) janela=$($seasonal.window)" -ForegroundColor DarkGray
    Write-MasterLog "Dormindo ${intervalMin}min janela=$($seasonal.window) proximo=$nextRunStr"

    $action = Wait-WithCommands -TotalMinutes $intervalMin -Seasonal $seasonal

    if ($action -eq "cycle") {
        Write-MasterLog "Ciclo forcado por comando"
        continue   # pula o sleep restante, roda o ciclo completo agora
    }
    # $null = tempo esgotado normalmente, continua para o proximo ciclo

} while ($true)

Write-Host "ScanMaster encerrado." -ForegroundColor Yellow
Send-TelegramAlert -Message "🛑 ScanMaster encerrado." | Out-Null
