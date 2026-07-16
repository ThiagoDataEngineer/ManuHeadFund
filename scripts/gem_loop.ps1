# gem_loop.ps1 -- Loop dedicado GemAgent (paralelo ao scan_master daily).
#
# Por que existe (2026-05-18):
# - scan_master roda DAILY (1x/dia) -- ideal para orchestrator V6 + trailing
# - GemAgent precisa de ritmo INTRA-DAY (micro-cap pumps tempo-sensiveis)
# - Loop separado: cycle 10min (LIVE trading, não 1h!)
#
# Mesmos guards do gem_executor (tier filter + sizing + freq + custodial removido).
# Idempotent: nao spawna se ja tem gem_loop rodando.
#
# Uso:
#   pwsh -File scripts\gem_loop.ps1                       # cycle default 10min LIVE
#   pwsh -File scripts\gem_loop.ps1 -CheckInterval 5      # 5min cycle (aggressive)
#   pwsh -File scripts\gem_loop.ps1 -Force                # bypassa idempotent
#
# PS 5.1. UTF-8 BOM.

param(
    [int]$CheckInterval = 10,   # minutos entre cycles GemScan (LIVE: 10min não 60!)
    [switch]$Once,              # roda 1 cycle e sai (teste / cloud)
    [switch]$Force,             # ignora idempotent
    [switch]$DryRun             # nao executa ordens reais (passa -DryRun ao executor)
)

$scriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot  = Split-Path -Parent $scriptRoot
$agentsDir    = Join-Path $projectRoot "agents"
$journalDir   = Join-Path $projectRoot "journal"
$gemLog       = Join-Path $journalDir "gem_loop.log"

# 2026-06-18 Fase 3 cloud: prova o stack na nuvem SEM disparar ordem real.
# Enquanto CLOUD_DRY_RUN.flag existir, todo execute vira DryRun. Remover o flag = LIVE.
# Join-Path aninhado (cross-platform: backslash literal quebrava no ubuntu).
if (Test-Path (Join-Path $journalDir "CLOUD_DRY_RUN.flag")) { $DryRun = $true }

# 2026-06-18 CUTOVER: trading e online (nuvem). Daemon LOOP local nao roda (evita
# double-trade). A nuvem chama com -Once, que BYPASSA este gate. Reversivel: rm o flag.
if ((Test-Path (Join-Path $journalDir "LOCAL_TRADING_DISABLED.flag")) -and -not $Once) {
    Write-Host "[CUTOVER] gem_loop LOOP local desativado (trading online na nuvem). -Once bypassa."
    exit 0
}

function Write-GemLog {
    param([string]$Level, [string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $gemLog -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Host $line
}

# IDEMPOTENT ROBUSTO via lib_daemon_singleton (lockfile PID+start_ticks).
# Antes: CommandLine -like "*gem_loop*" falhava com processos elevados (CommandLine
# NULL) -> DUPLICATAS. -Force NAO bypassa mais o guard (nunca queremos duplicata;
# o singleton ja toma lock stale automaticamente, entao -Force virou no-op aqui).
$myPid = $PID
$__singletonLib = Join-Path $agentsDir "lib_daemon_singleton.ps1"
$__lockDir      = Join-Path $journalDir "daemon_locks"
if (Test-Path $__singletonLib) {
    . $__singletonLib
    if (-not (Enter-DaemonSingleton -Name "gem_loop" -LockDir $__lockDir)) {
        Write-GemLog "SKIP" "Outro gem_loop VIVO ja detem o singleton lock; este PID=$myPid exit."
        exit 0
    }
}

# Verifica LIVE mode flag (mesmo flag do scan_master)
$liveFlag = Join-Path $journalDir "LIVE_MODE_ENABLED.flag"
$isLive = Test-Path $liveFlag
$modeLabel = if ($isLive) { "LIVE" } else { "DRY" }

# Carrega config + libs
Set-Location $projectRoot

# Config
try {
    . (Join-Path $agentsDir "config.local.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "config.ps1") -ErrorAction Stop
} catch {
    Write-GemLog "ERROR" "Falha ao carregar config: $($_.Exception.Message)"
    exit 1
}

# 2026-06-21 DIAGNOSTICO: presenca das keys de LLM (SO comprimento, nunca o valor).
# Causa de "Todas cascadas falharam" e [TechAgent] FALLBACK em producao -> confirmar
# se os secrets chegam ao processo (len>0) ou estao vazios.
try {
    $__keyDiag = @("ANTHROPIC_API_KEY","GROQ_API_KEY","GROQ_API_KEY_2","MISTRAL_API_KEY","CEREBRAS_API_KEY","FRED_API_KEY") |
        ForEach-Object { $v = [Environment]::GetEnvironmentVariable($_); "$_=$(if ($v) { "len$($v.Length)" } else { 'EMPTY' })" }
    Write-GemLog "DEBUG" "LLM keys (env): $($__keyDiag -join ' | ')"
} catch {}

# Core libs (ordem importa)
try {
    . (Join-Path $agentsDir "lib_coinex_positions_fetch.ps1") -ErrorAction SilentlyContinue  # Load FIRST: provides CoinEx-GetPendingPositions with -IsFutures
    . (Join-Path $agentsDir "lib_coinex.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_capital_context.ps1") -ErrorAction Stop  # 2026-07-09 FIX: Get-ExecutableCapitalUSDT critico pra sizing + gem_safety
    . (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_idempotency.ps1") -ErrorAction SilentlyContinue  # B14 callback idempotency
    . (Join-Path $agentsDir "lib_retry.ps1") -ErrorAction SilentlyContinue  # B19 retry transient
    . (Join-Path $agentsDir "lib_order_idempotency.ps1") -ErrorAction SilentlyContinue  # B19b PlaceOrder client_id
    . (Join-Path $agentsDir "lib_price_freshness.ps1") -ErrorAction SilentlyContinue  # B18 stale price
    . (Join-Path $agentsDir "lib_mentor_hallucination_detector.ps1") -ErrorAction SilentlyContinue  # P0b FQS hallucination
    . (Join-Path $agentsDir "lib_journal.ps1") -ErrorAction Stop
} catch {
    Write-GemLog "ERROR" "Falha ao carregar core libs: $($_.Exception.Message)"
    exit 1
}

# Guards + safety
try {
    . (Join-Path $agentsDir "lib_live_guards.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_quant_whitelist.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_gem_safety.ps1") -ErrorAction SilentlyContinue
    # B9 fix: TTL cache pra GEM re-veto loop
    . (Join-Path $agentsDir "lib_gem_decision_cache.ps1") -ErrorAction SilentlyContinue
    # 2026-06-17: SHORT gates (Resolve-BidirectionalDirection precisa delas)
    . (Join-Path $agentsDir "lib_bidirectional_gates.ps1") -ErrorAction SilentlyContinue
} catch {
    Write-GemLog "WARN" "Falha ao carregar guards: $($_.Exception.Message)"
}

# Market movers (universo dinamico 2026-06-09)
try {
    . (Join-Path $agentsDir "lib_market_movers.ps1") -ErrorAction SilentlyContinue
    if (Get-Command Get-PrioritizedMarkets -ErrorAction SilentlyContinue) {
        Write-GemLog "DEBUG" "Market movers lib carregado (universo dinamico ativo)"
    }
} catch { }

# Trailing stop (deixa ganho rodar 2026-06-09)
try {
    . (Join-Path $agentsDir "lib_trailing.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "trailing_stop_manager.ps1") -ErrorAction SilentlyContinue
    Write-GemLog "DEBUG" "Trailing stop ativado"
} catch { }

# Governance: Circuit breaker ONLY (no human approval — see TRADING_AUTONOMY.md)
# 2026-07-16 FIX (auditoria agent a395f05e): lib_state_store precisa carregar
# ANTES do circuit breaker -- Get-DailyPnL agora consulta Supabase via
# Get-StateRecords (fix de fail-open, arquivo local nao sobrevive entre jobs
# efemeros). Antes lib_state_store so carregava na linha ~196 (depois de
# gem_executor.ps1 ja ter rodado o circuit breaker check), entao o fix
# silenciosamente caia no fallback local mesmo assim. Dot-source adiantado
# aqui, idempotente (mesmo arquivo recarregado depois nao quebra nada).
try {
    . (Join-Path $agentsDir "lib_state_store.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_circuit_breaker_simple.ps1") -ErrorAction SilentlyContinue
    Write-GemLog "DEBUG" "Governance libs carregadas (circuit breaker c/ Supabase, no human approval)"
} catch { }

# Macro + Halving aware (2026-06-09 — WIRE halving cycle + DCA strategy)
try {
    . (Join-Path $agentsDir "lib_macro.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_market_context_engine.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_halving_phase_alert.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_trailing_peak_update.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_dca_accumulator.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_pyramid_exit.ps1") -ErrorAction SilentlyContinue
    if (Get-Command Get-MacroContext -ErrorAction SilentlyContinue) {
        $ctx = Get-MacroContext
        $phase = if ($ctx.halving_phase) { $ctx.halving_phase } else { "unknown" }
        Write-GemLog "DEBUG" "Macro context ativo (macro_bias=$($ctx.macro_bias), halving_phase=$phase)"
    }
} catch {
    Write-GemLog "WARN" "Macro libs carregamento falhou (non-critical): $($_.Exception.Message)"
}

# Vol Climax integration (2026-06-09 — TDD phase 1)
try {
    . (Join-Path $agentsDir "lib_vol_climax_integration.ps1") -ErrorAction SilentlyContinue
    if (Get-Command Test-VolClimaxSignal -ErrorAction SilentlyContinue) {
        Write-GemLog "DEBUG" "Vol Climax integration loaded (TDD phase 1)"
    }
} catch {
    Write-GemLog "WARN" "Vol Climax integration load failed (non-critical): $($_.Exception.Message)"
}

# Tech agent (precisa estar disponivel para gem_executor)
# Carrega com erro visivel (Stop) — catch loga + continua (fallback no gem_executor)
try {
    . (Join-Path $agentsDir "tech_agent_ai.ps1") -ErrorAction Stop
    if (Get-Command Get-ToriTrendlineSignal -ErrorAction SilentlyContinue) {
        Write-GemLog "DEBUG" "Tech agent carregado com sucesso"
    } else {
        Write-GemLog "WARN" "tech_agent_ai carregou mas Get-ToriTrendlineSignal nao disponivel"
    }
} catch {
    Write-GemLog "WARN" "Falha ao carregar tech_agent_ai (fallback gem_executor): $($_.Exception.Message)"
}

# Gem agents (GemAgent DEVE vir antes de gem_executor)
try {
    . (Join-Path $agentsDir "gem_agent.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "gem_executor.ps1") -ErrorAction Stop
} catch {
    Write-GemLog "ERROR" "Falha ao carregar gem agents: $($_.Exception.Message)"
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# 2026-07-07 WIRED: LOAD SUPABASE INTEGRATION LIBS
# ═══════════════════════════════════════════════════════════════════════════════
try {
    . (Join-Path $agentsDir "lib_state_store.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_position_sync_live.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_trade_journal_supabase.ps1") -ErrorAction SilentlyContinue
    Write-GemLog "INFO" "Supabase integration libs loaded (state_store, position_sync, trade_journal)"
} catch {
    Write-GemLog "WARN" "Supabase integration libs load failed (non-critical): $($_.Exception.Message)"
}

# Validar que Invoke-GemScan está disponível
if (-not (Get-Command "Invoke-GemScan" -ErrorAction SilentlyContinue)) {
    Write-GemLog "ERROR" "Invoke-GemScan nao esta disponivel apos sourcing"
    exit 1
}

# 2026-07-09 BOOT INTEGRITY GUARD (fail-closed, regra 5): parse error em lib =
# funcoes somem em silencio (caso lib_position_sync_live: sync morto por `??`).
. (Join-Path $agentsDir "lib_boot_integrity.ps1")
$__boot = Assert-BootIntegrity -DaemonName "gem_loop" -AgentsDir $agentsDir -CriticalFunctions @(
    "Invoke-GemExecute", "Test-GemSafetyGuards", "Get-ExecutableCapitalUSDT",
    "Get-TrailingNewStop", "Send-TelegramAlert"
)
if (-not $__boot.ok) {
    Write-GemLog "ERROR" "gem_loop abortado por boot integrity: $($__boot.message)"
    exit 1
}

Write-GemLog "INFO" "GemLoop iniciado. Interval=${CheckInterval}min | Mode=$modeLabel | PID=$myPid"

# Validar carregamentos
Write-GemLog "DEBUG" "Libs loaded: Invoke-GemScan=$(Get-Command 'Invoke-GemScan' -ErrorAction SilentlyContinue | % {$_.Name})"

function Invoke-GemCycle-Once {
    param([bool]$DryRun)
    try {
        # Trailing peak update (MONUSDT — via Invoke-RestMethod diretamente)
        if (Get-Command Update-TrailingPeakLive -ErrorAction SilentlyContinue) {
            try {
                $trailingFile = Join-Path $global:JOURNAL_DIR "trailing_positions.json"
                if (Test-Path $trailingFile) {
                    # Get current MONUSDT price via Invoke-RestMethod (como gem_executor faz) — ADD TIMEOUT
                    $ticker = Invoke-RestMethod -Uri "$global:COINEX_BASE_URL/v2/futures/ticker?market=MONUSDT" -Method GET -TimeoutSec 5 -ErrorAction SilentlyContinue
                    if ($ticker -and $ticker.code -eq 0 -and $ticker.data) {
                        $currentPrice = [double]$ticker.data[0].last
                        $trailingResult = Update-TrailingPeakLive -Market "MONUSDT" -CurrentPrice $currentPrice -TrailingFile $trailingFile
                        if ($trailingResult.updated) {
                            Write-GemLog "DEBUG" "Trailing peak MONUSDT: price=$currentPrice peak=$($trailingResult.new_peak)"
                        }
                    }
                }
            } catch {
                Write-GemLog "DEBUG" "Trailing peak: skipped (non-critical)"
            }
        }

        # DCA daily check (once per day, ~1-3% of capital)
        if (Get-Command Invoke-DcaBuy -ErrorAction SilentlyContinue) {
            try {
                $dcaState = Get-DcaState
                $lastBuyDate = if ($dcaState.last_buy -is [string]) {
                    [datetime]$dcaState.last_buy
                } else { $dcaState.last_buy }
                $today = (Get-Date).Date

                if ($lastBuyDate.Date -lt $today) {
                    # Get BTC price via Invoke-RestMethod — ADD TIMEOUT
                    $btcTicker = Invoke-RestMethod -Uri "$global:COINEX_BASE_URL/v2/futures/ticker?market=BTCUSDT" -Method GET -TimeoutSec 5 -ErrorAction SilentlyContinue
                    if ($btcTicker -and $btcTicker.code -eq 0 -and $btcTicker.data) {
                        $btcPrice = [double]$btcTicker.data[0].last
                        $shouldBuy = Test-DcaShouldBuy -BtcPrice $btcPrice
                        if ($shouldBuy -and -not $DryRun) {
                            $dcaResult = Invoke-DcaBuy -JournalDir $global:JOURNAL_DIR
                            Write-GemLog "DCA" "Compra executada: symbol=$($dcaResult.symbol) qty=$($dcaResult.qty) usd=$($dcaResult.usd)"
                        } elseif ($shouldBuy) {
                            Write-GemLog "DCA" "DRY: simulado DCA compra (não executado em modo DRY)"
                        } else {
                            Write-GemLog "DEBUG" "DCA: sinal não acionado (BTC=$btcPrice)"
                        }
                    }
                }
            } catch {
                Write-GemLog "DEBUG" "DCA check: skipped (non-critical)"
            }
        }

        Write-GemLog "CYCLE" "Iniciando GemScan (mode=$(if ($DryRun) {'DRY'} else {'LIVE'}))"

        # 2026-06-15: Read signal_triggers from scan_master + append to gem_loop results
        $triggerGems = @()
        $triggerFile = Join-Path $global:JOURNAL_DIR "signal_triggers.jsonl"
        if (Test-Path $triggerFile) {
            try {
                $now = Get-Date
                $lines = @(Get-Content $triggerFile -ErrorAction SilentlyContinue)
                foreach ($line in $lines) {
                    if (-not $line) { continue }
                    $sig = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if (-not $sig) { continue }

                    # Filtro: pending + nao expirado
                    if ($sig.status -ne "pending") { continue }
                    $expTime = if ($sig.expires_at) { [datetime]$sig.expires_at } else { $now }
                    if ($now -gt $expTime) { continue }

                    # Converter em gem compatível
                    $gem = @{
                        trigger_id = $sig.id
                        market = $sig.market
                        score = [int]($(if ($null -ne $sig.conviction) { $sig.conviction } else { 50 }))
                        mode = "TRIGGER"
                        signal = $sig.signal
                        direction = $sig.direction
                        sizing = @{sizing_pct = 0.02}  # 2% default para triggers
                    }
                    $triggerGems += $gem
                    Write-GemLog "TRIGGER" "$($sig.market) signal=$($sig.signal) conviction=$($sig.conviction)"
                }
            } catch {
                Write-GemLog "WARN" "signal_triggers read failed (non-critical): $($_.Exception.Message)"
            }
        }

        # Append Invoke-GemScan results
        $gemsFromScan = @(Invoke-GemScan -TopN 5)

        # ── TORI SHORT SWEEP (2026-07-09): 3a fonte de candidatos ──────────────
        # RAIZ "0 trades": DISCOVERY so gera candidatos LONG-momentum; o padrao
        # Wyckoff diario do short_scanner disparou 0x em 30 dias neste regime
        # (medido em 22 mercados). Enquanto isso o PROPRIO gate Tori marca SHORTs
        # 90-100/100 diariamente (ARB/TIA/INJ em 2026-07-09). Sweep: avalia o
        # tier_a_live com o MESMO detector do gate; score>=80 vira candidato
        # direction=SHORT na MESMA esteira — executor re-roda TODOS os gates
        # (cenario, chart pattern, Tori re-valida, Mesa, Mentor, sizing, circuit
        # breaker). Cap 3/ciclo. Reversivel: live_enabled=false no universo.
        $toriShortGems = @()
        if (-not (Get-Command Test-ToriConfluence -ErrorAction SilentlyContinue)) {
            $projRoot = Split-Path $global:JOURNAL_DIR -Parent
            foreach ($tl in @("lib_tori_confluence_detector.ps1","lib_tori_gate_wrapper.ps1")) {
                $tlp = Join-Path (Join-Path $projRoot "agents") $tl
                if (Test-Path $tlp) { . $tlp }
            }
        }
        if (Get-Command Test-ToriConfluence -ErrorAction SilentlyContinue) {
            try {
                $suPath = Join-Path (Split-Path $global:JOURNAL_DIR -Parent) "config/short_universe.json"
                if (Test-Path $suPath) {
                    $su = Get-Content $suPath -Raw | ConvertFrom-Json
                    if ($su.live_enabled -and $su.tier_a_live) {
                        foreach ($m in @($su.tier_a_live)) {
                            $tc = $null
                            try { $tc = Test-ToriConfluence -Market $m -SetupType "SHORT" -TimeframeMinutes 60 -TimeoutSeconds 6 } catch {}
                            if ($tc -and $tc.allows) {
                                # PSCustomObject (nao hashtable): executor le .direction
                                # via PSObject em alguns pontos legados
                                $toriShortGems += [PSCustomObject]@{
                                    market     = $m
                                    score      = [int]$tc.confluence_score
                                    mode       = "TORI_SHORT"
                                    direction  = "SHORT"
                                    conviction = [int]$tc.confluence_score
                                    signal     = ("tori:" + (@($tc.signals_fired) -join '+'))
                                    sizing     = [PSCustomObject]@{ sizing_pct = 0.02 }
                                }
                                Write-GemLog "TORI_SHORT" "$m confluence=$($tc.confluence_score) signals=$(@($tc.signals_fired) -join '+')"
                            }
                        }
                        if ($toriShortGems.Count -gt 3) {
                            $toriShortGems = @($toriShortGems | Sort-Object { [int]$_.score } -Descending | Select-Object -First 3)
                        }
                        if ($toriShortGems.Count -gt 0) {
                            Write-GemLog "INFO" "Tori SHORT sweep: $($toriShortGems.Count) candidato(s) >=80 no tier_a_live"
                        }
                    }
                }
            } catch {
                Write-GemLog "WARN" "tori short sweep failed (non-critical): $($_.Exception.Message)"
            }
        }

        # ── TORI LONG SWEEP (2026-07-15): 4a fonte de candidatos ───────────────
        # Espelho do SHORT sweep acima, para o lado LONG. Regime-aware: so roda
        # quando Get-MarketScenario permite LONG (allow_long=true: BULL/
        # CAPITULACAO/UNKNOWN) -- mesmo criterio do gate 1c do executor, entao
        # nenhum candidato e gerado apenas para ser bloqueado no cenario.
        # Universo: config/long_universe.json (git-tracked, acessivel na nuvem),
        # tier A_LIVE. Cap 3/ciclo. Executor re-roda TODOS os gates.
        $toriLongGems = @()
        if (-not (Get-Command Get-MarketScenario -ErrorAction SilentlyContinue)) {
            $projRoot2 = Split-Path $global:JOURNAL_DIR -Parent
            $msPath = Join-Path (Join-Path $projRoot2 "agents") "lib_market_scenario.ps1"
            if (Test-Path $msPath) { . $msPath }
        }
        if ((Get-Command Test-ToriConfluence -ErrorAction SilentlyContinue) -and
            (Get-Command Get-MarketScenario -ErrorAction SilentlyContinue)) {
            try {
                $scenSweep = Get-MarketScenario
                if ($scenSweep -and $scenSweep.allow_long) {
                    $luPath = Join-Path (Split-Path $global:JOURNAL_DIR -Parent) "config/long_universe.json"
                    if (Test-Path $luPath) {
                        $lu = Get-Content $luPath -Raw | ConvertFrom-Json
                        $luMarkets = @($lu.markets | Where-Object { $_.tier -eq "A_LIVE" } | ForEach-Object { $_.market })
                        foreach ($m in $luMarkets) {
                            $tc = $null
                            try { $tc = Test-ToriConfluence -Market $m -SetupType "LONG" -TimeframeMinutes 60 -TimeoutSeconds 6 } catch {}
                            if ($tc -and $tc.allows) {
                                $toriLongGems += [PSCustomObject]@{
                                    market     = $m
                                    score      = [int]$tc.confluence_score
                                    mode       = "TORI_LONG"
                                    direction  = "LONG"
                                    conviction = [int]$tc.confluence_score
                                    signal     = ("tori:" + (@($tc.signals_fired) -join '+'))
                                    sizing     = [PSCustomObject]@{ sizing_pct = 0.02 }
                                }
                                Write-GemLog "TORI_LONG" "$m confluence=$($tc.confluence_score) signals=$(@($tc.signals_fired) -join '+')"
                            }
                        }
                        if ($toriLongGems.Count -gt 3) {
                            $toriLongGems = @($toriLongGems | Sort-Object { [int]$_.score } -Descending | Select-Object -First 3)
                        }
                        if ($toriLongGems.Count -gt 0) {
                            Write-GemLog "INFO" "Tori LONG sweep: $($toriLongGems.Count) candidato(s) >=80 no A_LIVE (cenario=$($scenSweep.scenario))"
                        }
                    }
                } else {
                    Write-GemLog "INFO" "Tori LONG sweep: skip (cenario=$($scenSweep.scenario) allow_long=false)"
                }
            } catch {
                Write-GemLog "WARN" "tori long sweep failed (non-critical): $($_.Exception.Message)"
            }
        }

        # ── BTC MULTI-TIMEFRAME (2026-07-16): scalp em 15m alem do 1h ───────────
        # BTC e a referencia de regime (Get-MarketScenario) e passa pelos sweeps
        # acima como qualquer outro par do tier_a_live/A_LIVE -- so que so no 1h,
        # onde a menor volatilidade relativa de BTC faz sinais de fractal/volume
        # climax (calibrados pra altcoin) dispararem raramente (confirmado:
        # DOGE/ADA/OP/INJ/TIA/UNI batem confluence>=80 quase todo ciclo, BTC
        # nunca aparece nos logs TORI_SHORT/TORI_LONG). Nao e caso especial de
        # regra -- mesmo threshold 80, mesmos gates depois -- so mais uma chance
        # de timeframe pra capturar scalp que o 1h nao ve. A partir de 15m (nao
        # 5m, pra nao acrescentar ruido sobre o que ja funciona). SHORT sempre
        # tentado (BTC tem futures); LONG so quando cenario permite (mesmo criterio
        # do sweep LONG acima).
        try {
            if (Get-Command Test-ToriConfluence -ErrorAction SilentlyContinue) {
                $btcTc15Short = $null
                try { $btcTc15Short = Test-ToriConfluence -Market "BTCUSDT" -SetupType "SHORT" -TimeframeMinutes 15 -TimeoutSeconds 6 } catch {}
                if ($btcTc15Short -and $btcTc15Short.allows) {
                    $toriShortGems += [PSCustomObject]@{
                        market     = "BTCUSDT"
                        score      = [int]$btcTc15Short.confluence_score
                        mode       = "TORI_SHORT_15M"
                        direction  = "SHORT"
                        conviction = [int]$btcTc15Short.confluence_score
                        signal     = ("tori15m:" + (@($btcTc15Short.signals_fired) -join '+'))
                        sizing     = [PSCustomObject]@{ sizing_pct = 0.02 }
                    }
                    Write-GemLog "TORI_SHORT_15M" "BTCUSDT confluence=$($btcTc15Short.confluence_score) signals=$(@($btcTc15Short.signals_fired) -join '+')"
                }

                $btcScenForLong = if ($scenSweep) { $scenSweep } else { Get-MarketScenario }
                if ($btcScenForLong -and $btcScenForLong.allow_long) {
                    $btcTc15Long = $null
                    try { $btcTc15Long = Test-ToriConfluence -Market "BTCUSDT" -SetupType "LONG" -TimeframeMinutes 15 -TimeoutSeconds 6 } catch {}
                    if ($btcTc15Long -and $btcTc15Long.allows) {
                        $toriLongGems += [PSCustomObject]@{
                            market     = "BTCUSDT"
                            score      = [int]$btcTc15Long.confluence_score
                            mode       = "TORI_LONG_15M"
                            direction  = "LONG"
                            conviction = [int]$btcTc15Long.confluence_score
                            signal     = ("tori15m:" + (@($btcTc15Long.signals_fired) -join '+'))
                            sizing     = [PSCustomObject]@{ sizing_pct = 0.02 }
                        }
                        Write-GemLog "TORI_LONG_15M" "BTCUSDT confluence=$($btcTc15Long.confluence_score) signals=$(@($btcTc15Long.signals_fired) -join '+')"
                    }
                }
            }
        } catch {
            Write-GemLog "WARN" "btc multi-tf sweep failed (non-critical): $($_.Exception.Message)"
        }

        $gems = @($triggerGems) + @($gemsFromScan) + @($toriShortGems) + @($toriLongGems)
        # R4 fix 2026-05-21: cache check ANTES do log "encontrados" + Invoke-GemExecute.
        # Resolve PEAQ/PROVE re-detection spam.
        if (Get-Command Test-GemRecentlyRejected -ErrorAction SilentlyContinue -and $gems.Count -gt 0) {
            $cachePath = Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json"
            # 2026-06-17: com CONVICTION_GATE on, tori_skip/wait nao bloqueiam (re-avalia
            # via ensemble no executor). conviction_low/sizing/etc continuam bloqueando.
            $bypass = @()
            if (Test-Path (Join-Path $global:JOURNAL_DIR "CONVICTION_GATE.flag")) { $bypass = @("tori_skip","tori_wait") }
            $filtered = @(); $skipped = @()
            foreach ($g in $gems) {
                # 2026-07-09 FIX: cache de rejeicao e por MARKET (sem direcao). O ARB
                # SHORT (Tori 100, melhor candidato) morria ETERNAMENTE no cache gravado
                # pela rejeicao do ARB LONG (65<80) segundos antes no MESMO ciclo.
                # Gems com direcao explicita (TORI_SHORT/TRIGGER) pulam o cache de
                # market — os guards reais (exposure_cap, cascade, cenario, dedup de
                # posicao, Tori/Mesa/Mentor) continuam TODOS no executor.
                $gDirCache = "$($g.direction)".ToUpper()
                if ($gDirCache -in @("LONG","SHORT")) { $filtered += $g; continue }
                # 2026-06-03: Reduzido TTL de 60 para 5 minutos
                # Tori agora FORÇA ENTRY, então gems rejeitados devem ser re-tentados rapidamente
                if (Test-GemRecentlyRejected -Path $cachePath -Market $g.market -TtlMinutes 5 -BypassReasons $bypass) {
                    $skipped += $g.market
                } else { $filtered += $g }
            }
            if ($skipped.Count -gt 0) {
                Write-GemLog "INFO" "Cache hit: $($skipped.Count) gem(s) skip -- $($skipped -join ',')"
            }
            $gems = $filtered
        }
        Write-GemLog "INFO" "GemScan: $($gems.Count) gem(s) encontrados"

        foreach ($g in $gems) {
            $mkt = if ($g.market) { $g.market } else { "?" }
            $score = if ($g.score) { $g.score } else { 0 }
            Write-GemLog "GEM" "$mkt score=$score mode=$($g.mode)"
            # gem_executor ja tem guards (tier + sizing + freq)
            try {
                $r = Invoke-GemExecute -Gem $g -DryRun:$DryRun
                if ($r.blocked) {
                    Write-GemLog "BLOCKED" "$mkt -- $($r.blocked_by -join '; ')"
                    # Mark trigger as skipped if from signal_triggers
                    # 2026-07-08: gravar razao REAL (blocked_by) em vez do catch-all
                    # "gem_safety_blocked" que escondeu 2327 skips; e marcar so o
                    # trigger deste gem (id match), nao todos do market.
                    if ($g.mode -eq "TRIGGER") {
                        try {
                            $reasonNote = "blocked: " + (@($r.blocked_by) -join '; ')
                            if ($reasonNote.Length -gt 180) { $reasonNote = $reasonNote.Substring(0, 180) }
                            $triggerFile = Join-Path $global:JOURNAL_DIR "signal_triggers.jsonl"
                            if (Test-Path $triggerFile) {
                                $lines = @(Get-Content $triggerFile -ErrorAction SilentlyContinue)
                                $updated = @()
                                foreach ($line in $lines) {
                                    if (-not $line) { continue }
                                    $sig = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                                    $isMatch = if ($g.trigger_id) { $sig.id -eq $g.trigger_id }
                                               else { $sig.market -eq $mkt -and $sig.status -eq "pending" }
                                    if ($isMatch) {
                                        $sig.status = "skipped"
                                        $sig.notes = $reasonNote
                                    }
                                    $updated += ($sig | ConvertTo-Json -Compress)
                                }
                                $updated | Set-Content $triggerFile -Encoding UTF8 -ErrorAction SilentlyContinue
                            }
                        } catch { }
                    }
                } elseif ($r.order_id) {
                    Write-GemLog "EXEC" "$mkt order=$($r.order_id) qty=$($r.qty)"
                    # Mark trigger as executed
                    if ($g.mode -eq "TRIGGER") {
                        try {
                            $triggerFile = Join-Path $global:JOURNAL_DIR "signal_triggers.jsonl"
                            if (Test-Path $triggerFile) {
                                $lines = @(Get-Content $triggerFile -ErrorAction SilentlyContinue)
                                $updated = @()
                                foreach ($line in $lines) {
                                    if (-not $line) { continue }
                                    $sig = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                                    $isMatch = if ($g.trigger_id) { $sig.id -eq $g.trigger_id }
                                               else { $sig.market -eq $mkt -and $sig.status -eq "pending" }
                                    if ($isMatch) {
                                        $sig.status = "processed"
                                        $sig.notes = "gem_executor_executed"
                                    }
                                    $updated += ($sig | ConvertTo-Json -Compress)
                                }
                                $updated | Set-Content $triggerFile -Encoding UTF8 -ErrorAction SilentlyContinue
                            }
                        } catch { }
                    }
                    # Pyramid exit mock: register intention if score >= 80 (high conviction)
                    if ($score -ge 80 -and (Get-Command Invoke-PyramidExit -ErrorAction SilentlyContinue)) {
                        try {
                            $pyramidResult = Invoke-PyramidExit -Market $mkt -EntryPrice $r.entry_price -JournalDir $global:JOURNAL_DIR -DryRun $DryRun
                            if ($pyramidResult.registered) {
                                Write-GemLog "PYRAMID" "$mkt registered for pyramid exit (score=$score)"
                            }
                        } catch {
                            Write-GemLog "DEBUG" "Pyramid exit mock: $mkt score=$score (no-op yet)"
                        }
                    }
                } elseif ($r.dry_run) {
                    Write-GemLog "DRY" "$mkt simulado (sizing=$($r.sizing_usd))"
                }
            } catch {
                Write-GemLog "ERROR" "Invoke-GemExecute $mkt -- $($_.Exception.Message)"
            }
        }
    } catch {
        Write-GemLog "ERROR" "GemCycle: $($_.Exception.Message)"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# 2026-07-08: STARTUP — Auto-aprendizado daemon (grade_llm_decisions 1h interval)
# ═══════════════════════════════════════════════════════════════════════════════
$gradeDaemonPath = Join-Path $scriptRoot "grade_llm_daemon.ps1"
if (Test-Path $gradeDaemonPath) {
    try {
        # Start grade daemon in background (independent process)
        $gradePid = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$gradeDaemonPath`"" -PassThru -WindowStyle Hidden
        Write-GemLog "INFO" "Grade daemon started (PID=$($gradePid.Id), interval=1h, auto-learning ATIVO)"
    } catch {
        Write-GemLog "WARN" "Failed to start grade daemon: $_"
    }
}

# Main loop
if ($Once) {
    Invoke-GemCycle-Once -DryRun (-not $isLive)
    Write-GemLog "INFO" "Once mode -- exit"
    exit 0
}

while ($true) {
    # ═══════════════════════════════════════════════════════════════════
    # 2026-07-08: POSITION SYNC DISABLED TEMPORARILY
    # Reason: IsFutures parameter conflict resolved offline
    # Positions tracked via Trailing system in parallel
    # ═══════════════════════════════════════════════════════════════════
    # Sync-ExchangePositionsLive disabled to unblock gem_loop

    Invoke-GemCycle-Once -DryRun (-not $isLive)
    $sleepSec = $CheckInterval * 60
    Write-GemLog "INFO" "Dormindo ${CheckInterval}min ate proximo cycle"
    Start-Sleep -Seconds $sleepSec
}
