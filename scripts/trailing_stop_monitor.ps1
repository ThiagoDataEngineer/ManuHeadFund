# scripts\trailing_stop_monitor.ps1
# Monitor de Trailing Stop - CROSS-PLATFORM (Windows/Linux)
# Funciona tanto localmente quanto no GitHub Actions
# 2026-05-24

$ErrorActionPreference = "Stop"

# ============================================================================
# Setup Cross-Platform
# ============================================================================

# Detectar raiz do projeto
$projectRoot = Split-Path -Parent $PSScriptRoot

# Carregar lib cross-platform primeiro
$agentsDir = Join-Path $projectRoot "agents"
$crossPlatformLib = Join-Path $agentsDir "lib_cross_platform.ps1"
. $crossPlatformLib

# Carregar config.local.ps1 se existir (para credenciais)
$configLocal = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocal) {
    . $configLocal
}

# Inicializar ambiente
$cpEnv = Initialize-CrossPlatformEnvironment
$journalDir = Join-Path $projectRoot "journal"
$logsDir = Join-Path $projectRoot "logs"

Write-CrossPlatformLog "=== TRAILING STOP MONITOR START ===" -LogFile "trailing_stop_monitor.log"
Write-CrossPlatformLog "OS: $(if ($cpEnv.IsLinux) { 'Linux' } else { 'Windows' })" -LogFile "trailing_stop_monitor.log"
Write-CrossPlatformLog "Project Root: $($cpEnv.ProjectRoot)" -LogFile "trailing_stop_monitor.log"

# ============================================================================
# Validar Credenciais
# ============================================================================

if (-not (Test-CrossPlatformCredentials)) {
    Write-CrossPlatformLog "ERROR: Credentials not configured" -Level ERROR -LogFile "trailing_stop_monitor.log"
    exit 1
}

# ============================================================================
# Carregar Bibliotecas
# ============================================================================

try {
    Write-CrossPlatformLog "Loading libraries..." -LogFile "trailing_stop_monitor.log"
    
    # Carregar libs diretamente com Join-Path (cross-platform)
    . (Join-Path $agentsDir "config.ps1")
    . (Join-Path $agentsDir "lib_coinex.ps1")
    . (Join-Path $agentsDir "lib_candle_fetcher.ps1")
    . (Join-Path $agentsDir "lib_telegram.ps1")
    . (Join-Path $agentsDir "lib_trailing.ps1")
    # 2026-06-20: registra trade_outcome ao fechar (JSONL local + espelho Supabase).
    # Sem este load, Add-TradeOutcome nao existe e a chamada gated em lib_trailing
    # eh pulada -> nenhum outcome registrado (causa de 0 rows no Supabase).
    . (Join-Path $agentsDir "lib_feedback_loop.ps1")
    . (Join-Path $agentsDir "lib_trailing_stop_intelligent.ps1")
    . (Join-Path $agentsDir "lib_trailing_orphan_detection.ps1")
    # 2026-07-18: motor unico de trailing. PROMOVIDO pra ATIVO em 2026-07-29
    # (owner aprovado apos 1000 observacoes reais de shadow desde 2026-07-19
    # mostrarem 73.7% would_have_differed=true, sempre na direcao de proteger
    # o lucro MAIS CEDO/MAIS FORTE que os motores fragmentados -- nunca o
    # contrario). Ver "2.55b TRAILING UNIFIED (ATIVO)" abaixo. lib_tori_proximity
    # e nova (2026-07-29): trendline real de suporte/resistencia, 3o fator do
    # motor unificado (Get-TrendlineTighteningFactor).
    . (Join-Path $agentsDir "lib_trailing_exhaustion.ps1")
    . (Join-Path $agentsDir "lib_multiframe_analysis.ps1")
    . (Join-Path $agentsDir "lib_tori_proximity.ps1")
    . (Join-Path $agentsDir "lib_trailing_unified.ps1")
    # 2026-08-22: detectores de reversao (rejeicao estrutural + candlestick)
    # pra alimentar -ReversalSignals do Resolve-TrailingDecision -- o ladder
    # de reversao (tighten=2 sinais, exit=3) existia desde 2026-07-29 mas o
    # caller nunca passava sinal nenhum (default 0 = ladder morto). As duas
    # funcoes existem/testadas desde 2026-08-14 (caso ACEUSDT) mas so eram
    # usadas na ENTRADA, nunca pra proteger posicao aberta.
    . (Join-Path $agentsDir "lib_chart_patterns.ps1")
    # 2026-08-06: reconcilia journal.stopCurrent com SL real na corretora
    # antes do motor decidir (ver comentario no bloco TRAILING UNIFIED).
    . (Join-Path $agentsDir "lib_trailing_stop_reconcile.ps1")
    # 2026-05-29: auto-reparo de protecao (SL+TP reais na corretora)
    . (Join-Path $agentsDir "lib_coinex_position_management.ps1")
    . (Join-Path $agentsDir "lib_order_validation.ps1")
    . (Join-Path $agentsDir "lib_position_protection.ps1")
    # 2026-06-18 Fase 1 online: peak update fino (+2.5% breakeven) + executor de SL
    . (Join-Path $agentsDir "lib_trailing_peak_update.ps1")
    . (Join-Path $agentsDir "lib_trailing_sync.ps1")
    # 2026-06-19 Fase 2: Exit Intelligence (saídas automáticas em lucro)
    . (Join-Path $agentsDir "lib_exit_intelligence.ps1")
    . (Join-Path $agentsDir "lib_exit_intelligence_auto.ps1")
    . (Join-Path $agentsDir "lib_spot_stop_guard.ps1")  # 2026-06-24: cobertura spot por saldo (nuvem)
    # 2026-06-21: motor de politica de saida gated (runner em uptrend, validado walk-forward)
    . (Join-Path $agentsDir "lib_trailing_baseline.ps1")
    . (Join-Path $agentsDir "lib_trailing_policy.ps1")
    . (Join-Path $agentsDir "lib_trailing_policy_live.ps1")
    # 2026-07-31: execucao REAL de PARTIAL/EXIT (ladder de saida parcial
    # nativo na corretora) -- ate agora so era logado. Ver "PARTIAL EXIT
    # EXECUTION" abaixo. Gated por journal/PARTIAL_EXIT_EXECUTION_ENABLED.flag
    # (ausencia = so log, comportamento identico a antes).
    . (Join-Path $agentsDir "lib_trailing_partial_exit.ps1")

    # ═══════════════════════════════════════════════════════════════════════════════
    # 2026-07-07 WIRED: LOAD SUPABASE INTEGRATION LIBS
    # ═══════════════════════════════════════════════════════════════════════════════
    . (Join-Path $agentsDir "lib_state_store.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_position_sync_live.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_trade_journal_supabase.ps1") -ErrorAction SilentlyContinue

    Write-CrossPlatformLog "Libraries loaded successfully" -LogFile "trailing_stop_monitor.log"
} catch {
    Write-CrossPlatformLog "ERROR loading libraries: $_" -Level ERROR -LogFile "trailing_stop_monitor.log"
    exit 1
}

# ============================================================================
# Executar Monitor
# ============================================================================

try {
    # 1. ORPHAN DETECTION
    Write-CrossPlatformLog "--- ORPHAN DETECTION ---" -LogFile "trailing_stop_monitor.log"
    
    $orphanSync = Sync-OrphanPositions
    
    if ($orphanSync.success) {
        Write-CrossPlatformLog "Exchange positions: $($orphanSync.total_exchange)" -LogFile "trailing_stop_monitor.log"
        Write-CrossPlatformLog "Orphans detected: $($orphanSync.orphans_detected)" -LogFile "trailing_stop_monitor.log"
        
        if ($orphanSync.orphans_detected -gt 0) {
            Write-CrossPlatformLog "  Registered: $($orphanSync.registered)" -LogFile "trailing_stop_monitor.log"
            Write-CrossPlatformLog "  Skipped (duplicates): $($orphanSync.skipped)" -LogFile "trailing_stop_monitor.log"
            Write-CrossPlatformLog "  Errors: $($orphanSync.errors)" -LogFile "trailing_stop_monitor.log"
            
            foreach ($detail in $orphanSync.details) {
                if ($detail.registered) {
                    $stopType = if ($detail.stop_calculated) { "calculated" } else { "from exchange" }
                    Write-CrossPlatformLog "  ORPHAN REGISTERED: $($detail.market) | Entry: $($detail.entry) | Stop: $($detail.stop) ($stopType)" -LogFile "trailing_stop_monitor.log"
                }
                elseif ($detail.error) {
                    Write-CrossPlatformLog "  ORPHAN ERROR: $($detail.error)" -Level WARN -LogFile "trailing_stop_monitor.log"
                }
            }
        }
        else {
            Write-CrossPlatformLog "No orphans detected - all positions registered locally" -LogFile "trailing_stop_monitor.log"
        }
    }

    # 1.5 PHANTOM RECONCILIATION (2026-05-26 A.0): fecha posicoes locais active=true
    # que nao existem na exchange (oposto de orphan - position fechada externamente).
    if (Get-Command Reconcile-PhantomPositions -ErrorAction SilentlyContinue) {
        Write-CrossPlatformLog "--- PHANTOM RECONCILIATION ---" -LogFile "trailing_stop_monitor.log"
        $safetyPath = Join-Path $journalDir "gem_safety_state.json"
        $phantomSync = Reconcile-PhantomPositions -GemSafetyStatePath $safetyPath
        Write-CrossPlatformLog "Phantoms detected: $($phantomSync.phantoms_detected) closed: $($phantomSync.closed) errors: $($phantomSync.errors)" -LogFile "trailing_stop_monitor.log"
        foreach ($d in $phantomSync.details) {
            $level = if ($d.closed) { "INFO" } else { "WARN" }
            Write-CrossPlatformLog "  PHANTOM: $($d.market) closed=$($d.closed) exit=$($d.exitPrice)" -Level $level -LogFile "trailing_stop_monitor.log"
        }
    }
    else {
        Write-CrossPlatformLog "ORPHAN DETECTION ERROR: $($orphanSync.error)" -Level ERROR -LogFile "trailing_stop_monitor.log"
    }
    
    # 2. TRAILING STOP UPDATE (DESATIVADO 2026-07-29 -- substituido por TRAILING
    # UNIFIED mais abaixo, ver "2.55c TRAILING UNIFIED (ATIVO)". Update-AllTrailingStops
    # (ATR+suporte, gatilho fixo 3% lucro) e Invoke-TrailingPolicyLive (chandelier
    # ATR) eram 2 motores fragmentados calculando o stop de forma independente e
    # as vezes conflitante -- causa raiz confirmada do "seta apaga seta apaga"
    # reportado pelo owner ao vivo. Guard $false abaixo desliga sem apagar o
    # codigo (rollback rapido: trocar $false por $true reativa este motor).
    Write-CrossPlatformLog "--- TRAILING STOP UPDATE (legado, desativado -- ver TRAILING UNIFIED) ---" -LogFile "trailing_stop_monitor.log"

    if ($false -and (Get-Command Update-AllTrailingStops -ErrorAction SilentlyContinue)) {
        $result = Update-AllTrailingStops -DryRun $false
        
        if ($result.success) {
            Write-CrossPlatformLog "Total positions: $($result.total_positions)" -LogFile "trailing_stop_monitor.log"
            Write-CrossPlatformLog "Updated: $($result.updated)" -LogFile "trailing_stop_monitor.log"
            Write-CrossPlatformLog "No update needed: $($result.no_update)" -LogFile "trailing_stop_monitor.log"
            Write-CrossPlatformLog "Errors: $($result.errors)" -LogFile "trailing_stop_monitor.log"
            
            # Log detalhado
            foreach ($posResult in $result.results) {
                if ($posResult.success) {
                    if ($posResult.action -eq "updated") {
                        Write-CrossPlatformLog "  $($posResult.market): UPDATED stop from $($posResult.old_stop) to $($posResult.new_stop)" -LogFile "trailing_stop_monitor.log"
                    }
                    elseif ($posResult.action -eq "no_update") {
                        Write-CrossPlatformLog "  $($posResult.market): NO UPDATE - $($posResult.reason)" -LogFile "trailing_stop_monitor.log"
                    }
                }
                else {
                    Write-CrossPlatformLog "  $($posResult.market): ERROR - $($posResult.error)" -Level WARN -LogFile "trailing_stop_monitor.log"
                }
            }
        }
        else {
            Write-CrossPlatformLog "ERROR: $($result.error)" -Level ERROR -LogFile "trailing_stop_monitor.log"
        }
    }
    else {
        Write-CrossPlatformLog "Update-AllTrailingStops not available (simplified mode)" -Level WARN -LogFile "trailing_stop_monitor.log"
        
        # Modo simplificado: apenas listar posições
        $localPositions = @(Get-TrailingPositions | Where-Object { $_.active })
        Write-CrossPlatformLog "Local active positions: $($localPositions.Count)" -LogFile "trailing_stop_monitor.log"
        
        foreach ($pos in $localPositions) {
            Write-CrossPlatformLog "  $($pos.market): Entry $($pos.entry) | Stop $($pos.stopCurrent)" -LogFile "trailing_stop_monitor.log"
        }
    }
    
    # 2.55c TRAILING UNIFIED -- ATIVO (2026-07-18 desenhado, PROMOVIDO 2026-07-29)
    # Resolve-TrailingDecision (lib_trailing_unified.ps1, ATR + exhaustion +
    # trendline real Tori) agora EMPURRA o stop de verdade na corretora,
    # substituindo Update-AllTrailingStops (lib_trailing_stop_intelligent.ps1)
    # e Invoke-TrailingPolicyLive (lib_trailing_policy_live.ps1) -- os 2 motores
    # fragmentados que calculavam stop de forma independente e as vezes
    # conflitante ("seta apaga seta apaga" reportado pelo owner ao vivo, 2026-07-29).
    # Owner aprovado apos 1000 observacoes reais de shadow desde 2026-07-19
    # mostrarem 73.7% would_have_differed=true, SEMPRE na direcao de proteger
    # o lucro mais cedo/mais forte (nunca o contrario nos casos observados).
    # Guard monotonico "nunca afrouxa" ja embutido em Resolve-TrailingDecision
    # (linha ~254 de lib_trailing_unified.ps1) -- e' o que garante seguranca
    # aqui, mesmo com o motor decidindo ao vivo. Posicao sem origin gravado
    # (registros antigos, pre-2026-07-18) usa fallback UNKNOWN -- Resolve-
    # TrailingDecision lanca excecao nesse caso, capturada e logada como skip
    # (fail-safe, nao quebra o ciclo, nao mexe no stop dessa posicao).
    #
    # Kill-switch: journal/TRAILING_UNIFIED_SHADOW.flag agora e o gate de
    # ATIVACAO (nome preservado por continuidade historica -- inverte o
    # sentido: presente = motor unificado ATIVO e escreve; ausente = motor
    # unificado desligado, cai de volta pro Update-AllTrailingStops/
    # Invoke-TrailingPolicyLive antigos).
    if (Get-Command Resolve-TrailingDecision -ErrorAction SilentlyContinue) {
        $tuJournalDir = Join-Path (Split-Path $agentsDir -Parent) "journal"
        $tuFlag = Join-Path $tuJournalDir "TRAILING_UNIFIED_SHADOW.flag"
        $tuActive = Test-Path $tuFlag
        Write-CrossPlatformLog "--- TRAILING UNIFIED ($(if ($tuActive) { 'ATIVO' } else { 'desligado, flag ausente' })) ---" -LogFile "trailing_stop_monitor.log"
        try {
            $tuPositions = @(Get-TrailingPositions | Where-Object { $_.active })
            foreach ($tuPos in $tuPositions) {
                $tuMarket = [string]$tuPos.market
                try {
                    $tuTicker = CoinEx-GetTicker -Market $tuMarket -ErrorAction SilentlyContinue
                    $tuPrice = if ($tuTicker) { [double]$tuTicker.last } else { 0 }
                    if ($tuPrice -le 0) { continue }

                    $tuIsFutures = ($tuPos.origin -and "$($tuPos.origin.asset_class)".ToUpper() -eq "FUTURES")

                    # 2026-08-06 FIX: reconcilia $tuPos.stopCurrent (journal) com o
                    # SL REAL na corretora antes de decidir -- achado real em
                    # producao: ARBUSDT/NEARUSDT/OPUSDT tiveram origin corrigido
                    # (backfill, ver lib_trailing_origin_backfill.ps1) DEPOIS de
                    # varios ciclos com origin=UNKNOWN, onde o motor ja calculava
                    # e gravava stopCurrent no journal MAS nunca empurrava pra
                    # CoinEx (tuIsFutures era false, pulava o push). Resultado: o
                    # journal "achava" que o stop ja tinha avancado, entao o
                    # proximo ciclo (com origin ja correto) comparava contra esse
                    # valor adiantado e decidia "stop_calculado_nao_melhora" --
                    # nunca reenviava, corretora ficava presa no valor antigo pra
                    # sempre. So reconcilia quando o real esta MAIS FOLGADO que o
                    # journal (protege contra o caso real -- nunca afrouxa o que
                    # ja esta certo na corretora, so corrige atraso).
                    if ($tuIsFutures -and (Get-Command CoinEx-GetPendingPositions -ErrorAction SilentlyContinue)) {
                        try {
                            $tuRealPosCheck = @(CoinEx-GetPendingPositions -Market $tuMarket) | Select-Object -First 1
                            if ($tuRealPosCheck -and [double]$tuRealPosCheck.stop_loss_price -gt 0 -and (Get-Command Test-JournalStopAheadOfExchange -ErrorAction SilentlyContinue)) {
                                $tuRealSl = [double]$tuRealPosCheck.stop_loss_price
                                $tuJournalSl = [double]$tuPos.stopCurrent
                                $tuJournalAhead = Test-JournalStopAheadOfExchange -Side "$($tuPos.side)" -JournalStop $tuJournalSl -RealStop $tuRealSl
                                if ($tuJournalAhead) {
                                    Write-CrossPlatformLog "  UNIFIED ${tuMarket}: journal.stopCurrent ($tuJournalSl) esta a frente do SL real na corretora ($tuRealSl) -- reconciliando pro valor real antes de decidir (evita HOLD permanente por 'ja melhorou' quando na verdade nunca foi enviado)" -Level WARN -LogFile "trailing_stop_monitor.log"
                                    $tuPos.stopCurrent = $tuRealSl
                                    # 2026-08-06: persiste a reconciliacao de volta no journal
                                    # (nao so usa em memoria pra decidir este ciclo) -- evita
                                    # journal.stopCurrent != corretora aparecer em diagnosticos
                                    # futuros mesmo depois da protecao real ja estar correta.
                                    try { Save-TrailingPositions -Positions @($tuPositions) | Out-Null } catch {
                                        Write-CrossPlatformLog "  UNIFIED ${tuMarket}: falha ao persistir reconciliacao no journal: $_" -Level WARN -LogFile "trailing_stop_monitor.log"
                                    }
                                }
                            }
                        } catch {
                            Write-CrossPlatformLog "  UNIFIED ${tuMarket}: reconciliacao stopCurrent falhou (segue com valor do journal): $_" -Level WARN -LogFile "trailing_stop_monitor.log"
                        }
                    }

                    $tuCandles = @(Get-CoinExCandles -Market $tuMarket -Period "4hour" -Limit 30 -IsFutures $tuIsFutures)

                    # 2026-07-29 (parte 2): enriquecimento opcional -- multi-TF
                    # (1D/4H/1H) pra ativar o perfil runner-vs-atual validado, e
                    # bars_held/regime pro time-stop/ladder de reversao real
                    # (portado de Invoke-TrailingPolicyLive/Get-PositionExitDecision,
                    # o 2o motor fragmentado desligado nesta promocao). Fail-soft:
                    # candles multi-TF insuficientes -> $tuHtfTrend fica $null,
                    # Resolve-TrailingDecision cai no comportamento base (ATR+
                    # exhaustion+trendline+support), sem enriquecimento.
                    $tuHtfTrend = $null
                    if ($tuIsFutures -and (Get-Command Get-TrendDirection -ErrorAction SilentlyContinue)) {
                        try {
                            $tuC1D = @(Get-CoinExCandles -Market $tuMarket -Period "1day" -Limit 60 -IsFutures $true)
                            $tuC4H = @(Get-CoinExCandles -Market $tuMarket -Period "4hour" -Limit 60 -IsFutures $true)
                            $tuC1H = @(Get-CoinExCandles -Market $tuMarket -Period "1hour" -Limit 60 -IsFutures $true)
                            if ($tuC1D.Count -ge 20 -and $tuC4H.Count -ge 20 -and $tuC1H.Count -ge 20) {
                                $tuHtfTrend = [PSCustomObject]@{
                                    t1D = (Get-TrendDirection -Candles $tuC1D -Timeframe "1D")
                                    t4H = (Get-TrendDirection -Candles $tuC4H -Timeframe "4H")
                                    t1H = (Get-TrendDirection -Candles $tuC1H -Timeframe "1H")
                                }
                            }
                        } catch { $tuHtfTrend = $null }
                    }
                    $tuRegime = if (Get-Command Get-RegimeFromState -ErrorAction SilentlyContinue) { Get-RegimeFromState } else { "" }
                    $tuBarsHeld = $null
                    if ($tuPos.PSObject.Properties['openedAt'] -and $tuPos.openedAt) {
                        try { $tuBarsHeld = [Math]::Max(0, [int][Math]::Floor(((Get-Date) - [datetime]$tuPos.openedAt).TotalDays)) } catch { $tuBarsHeld = $null }
                    }

                    # 2026-08-22: conta sinais de reversao REAIS contra a posicao e
                    # alimenta o ladder do Resolve-TrailingDecision (tighten com 2,
                    # exit com 3 -- lib_trailing_policy.ps1). Antes: -ReversalSignals
                    # nunca era passado (default 0), ladder morto desde a criacao.
                    # Sinal 1 = rejeicao estrutural no nivel CONTRA a posicao: pra
                    # LONG, resistencia ACIMA testada e rejeitada (caso do video do
                    # owner: BTC batendo 80-82k pela 4a vez); pra SHORT, suporte
                    # abaixo rejeitando. O motor unificado interno so olha o nivel A
                    # FAVOR (suporte pra LONG) como fator de aperto -- o lado CONTRA
                    # nunca era avaliado em posicao aberta.
                    # Sinal 2 = candlestick reversal na direcao contraria (evening
                    # star/shooting star/etc pra LONG; espelho pra SHORT).
                    # Exhaustion NAO conta aqui: ja age como fator continuo interno
                    # do motor -- contar de novo dobraria o efeito.
                    # Fail-soft total: qualquer erro -> 0 sinais (comportamento iden-
                    # tico ao anterior).
                    $tuReversalSignals = 0
                    $tuRevDetails = @()
                    try {
                        $tuSide = "$($tuPos.side)".ToUpper()
                        $tuOpens  = @($tuCandles | ForEach-Object { [double]$_.open })
                        $tuHighs  = @($tuCandles | ForEach-Object { [double]$_.high })
                        $tuLows   = @($tuCandles | ForEach-Object { [double]$_.low })
                        $tuCloses = @($tuCandles | ForEach-Object { [double]$_.close })
                        # lado CONTRA a posicao: LONG teme reversao SHORT e vice-versa
                        $tuAgainst = if ($tuSide -eq "LONG") { "SHORT" } else { "LONG" }

                        if ((Get-Command Detect-StructuralRejection -ErrorAction SilentlyContinue) -and (Get-Command Find-SupportLevels -ErrorAction SilentlyContinue)) {
                            $tuLevels = @()
                            if ($tuAgainst -eq "SHORT") {
                                # resistencias ACIMA: espelha candles pra reusar Find-SupportLevels
                                # (mesmo padrao ja usado dentro de lib_trailing_unified.ps1)
                                $tuMirror = @($tuCandles | ForEach-Object { [PSCustomObject]@{ open=$_.open; high=(2*$tuPrice - $_.low); low=(2*$tuPrice - $_.high); close=(2*$tuPrice - $_.close); volume=$_.volume } })
                                $tuMirrored = @(Find-SupportLevels -Candles $tuMirror -LookbackPeriod 20)
                                $tuLevels = @($tuMirrored | ForEach-Object { 2*$tuPrice - [double]$_ })
                            } else {
                                $tuLevels = @(Find-SupportLevels -Candles $tuCandles -LookbackPeriod 20)
                            }
                            if ($tuLevels.Count -gt 0) {
                                $tuRej = Detect-StructuralRejection -Closes $tuCloses -Levels $tuLevels -Side $tuAgainst
                                if ($tuRej.detected) {
                                    $tuReversalSignals++
                                    $tuRevDetails += "structural_rejection(nivel=$([math]::Round([double]$tuRej.level,6)) forca=$($tuRej.strength))"
                                }
                            }
                        }
                        if (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue) {
                            $tuCdl = Detect-CandlestickReversal -Opens $tuOpens -Highs $tuHighs -Lows $tuLows -Closes $tuCloses -Side $tuAgainst
                            if ($tuCdl.detected) {
                                $tuReversalSignals++
                                $tuRevDetails += "candlestick($($tuCdl.pattern_name) forca=$($tuCdl.strength))"
                            }
                        }
                        if ($tuReversalSignals -gt 0) {
                            Write-CrossPlatformLog "  UNIFIED ${tuMarket}: $tuReversalSignals sinal(is) de reversao contra $tuSide -- $($tuRevDetails -join ' + ')" -Level WARN -LogFile "trailing_stop_monitor.log"
                        }
                    } catch {
                        $tuReversalSignals = 0
                        Write-CrossPlatformLog "  UNIFIED ${tuMarket}: deteccao de reversao falhou (segue sem sinais): $_" -Level WARN -LogFile "trailing_stop_monitor.log"
                    }

                    # Ladder de reversao (Get-ExitDecision) so ativa com BarsHeld nao-nulo
                    # (lib_trailing_unified.ps1 linha ~475). Posicao sem openedAt perderia
                    # os sinais detectados -- fallback: BarsHeld=0 ativa o ladder sem
                    # acionar o time-stop (que so age com barras acumuladas).
                    if ($null -eq $tuBarsHeld -and $tuReversalSignals -gt 0) { $tuBarsHeld = 0 }

                    $tuDecision = Resolve-TrailingDecision -Position $tuPos -CurrentPrice $tuPrice -Candles $tuCandles -HtfTrend $tuHtfTrend -Regime $tuRegime -BarsHeld $tuBarsHeld -ReversalSignals $tuReversalSignals
                    $tuPushed = $false
                    $tuPushErr = $null

                    if ($tuDecision.action -eq "UPDATE") {
                        Write-CrossPlatformLog "  UNIFIED $tuMarket [$($tuPos.side)]: real_stop=$($tuPos.stopCurrent) unified_sugere=$($tuDecision.new_stop) (exhaustion=$($tuDecision.exhaustion_score) trendline_factor=$($tuDecision.trendline_factor) reason=$($tuDecision.reason))" -LogFile "trailing_stop_monitor.log"

                        if ($tuActive -and $tuIsFutures -and (Get-Command CoinEx-ModifyPositionStopLoss -ErrorAction SilentlyContinue)) {
                            try {
                                $tuResp = CoinEx-ModifyPositionStopLoss -Market $tuMarket -Price ([decimal]$tuDecision.new_stop)
                                $tuPushed = ($tuResp -and $tuResp.success -eq $true)
                                if (-not $tuPushed) { $tuPushErr = "api_falhou" }
                            } catch { $tuPushErr = $_.Exception.Message }

                            if (-not $tuPushed) {
                                Write-CrossPlatformLog "  UNIFIED ${tuMarket}: push FUTURES falhou ($tuPushErr) -- journal NAO atualizado (evita dessincronia journal-vs-corretora)" -Level WARN -LogFile "trailing_stop_monitor.log"
                            }
                        }

                        # 2026-07-29: atualiza o journal (trailing_state) sempre que a
                        # decisao e' UPDATE e (FUTURES com push confirmado) OU (SPOT --
                        # sem push direto aqui, mesma inteligencia de saida do FUTURES
                        # via ATR/exhaustion/trendline, execucao real fica por conta de
                        # Sync-SpotStopsToExchange mais abaixo, que ja le stopCurrent
                        # daqui via Get-SpotHoldingsForStop -- owner pediu explicitamente
                        # que SPOT tenha a MESMA logica de saida, so o TIPO de ordem
                        # (spot stop-order vs futures modify-position) e diferente).
                        # Sem isso pro FUTURES com push falho, o proximo ciclo comparia
                        # contra um valor que a corretora nunca recebeu -> dessincronia.
                        if ((-not $tuIsFutures) -or $tuPushed) {
                            $tuPos.stopCurrent = $tuDecision.new_stop
                            $tuPos.updatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                            try { Save-TrailingPositions -Positions @($tuPositions) | Out-Null } catch {}
                            $tuDest = if ($tuIsFutures) { "corretora (FUTURES, push direto)" } else { "journal (SPOT, Sync-SpotStopsToExchange executa a seguir)" }
                            Write-CrossPlatformLog "  UNIFIED ${tuMarket}: stop $($tuPos.stopCurrent) -> $($tuDecision.new_stop) atualizado em $tuDest" -LogFile "trailing_stop_monitor.log"
                        }
                    } elseif ($tuDecision.action -in @("PARTIAL","EXIT")) {
                        # 2026-07-29: PARTIAL/EXIT sao NOVAS acoes possiveis (portadas
                        # de Get-ExitDecision -- saida parcial real em R-multiple,
                        # time-stop, ladder de reversao).
                        Write-CrossPlatformLog "  UNIFIED $tuMarket [$($tuPos.side)]: $($tuDecision.action) recomendado (size_pct=$($tuDecision.size_pct) profile=$($tuDecision.profile_selected) reason=$($tuDecision.reason))" -Level WARN -LogFile "trailing_stop_monitor.log"

                        # 2026-07-31: execucao REAL -- registra ladder de saida
                        # parcial NATIVO na corretora (nao executa venda a
                        # mercado repetida: Get-ExitDecision e stateless, entao
                        # "vender agora" a cada ciclo esvaziaria a posicao sem
                        # controle -- achado real com DOGEUSDT recomendando o
                        # mesmo size_pct=0.75 por >1h sem mudar). Gated por
                        # journal/PARTIAL_EXIT_EXECUTION_ENABLED.flag -- ausencia
                        # = comportamento identico a antes (so log). So FUTURES
                        # por enquanto (SPOT fica pra fase seguinte, escopo
                        # menor e mais simples de validar primeiro em producao).
                        $tuPartialFlag = Join-Path $tuJournalDir "PARTIAL_EXIT_EXECUTION_ENABLED.flag"
                        if ($tuIsFutures -and (Test-Path $tuPartialFlag)) {
                            try {
                                if ($tuDecision.action -eq "EXIT") {
                                    # 2026-07-31 FIX: EXIT = tese do trade acabou (reversao
                                    # confirmada ou time-stop) -- fecha a posicao INTEIRA,
                                    # nao registra ladder parcial (nao faz sentido "sair aos
                                    # poucos" quando o motor ja decidiu sair de tudo). Reusa
                                    # CoinEx-ClosePosition, ja em producao/testado.
                                    if (Get-Command CoinEx-ClosePosition -ErrorAction SilentlyContinue) {
                                        $tuCloseResp = CoinEx-ClosePosition $tuMarket
                                        $tuCloseOk = ($tuCloseResp -and $tuCloseResp.code -eq 0)
                                        Write-CrossPlatformLog "  UNIFIED ${tuMarket}: EXIT total -> success=$tuCloseOk" -LogFile "trailing_stop_monitor.log"
                                    }
                                } elseif ($tuDecision.action -eq "PARTIAL" -and (Get-Command Register-PartialExitLadder -ErrorAction SilentlyContinue)) {
                                    # Perfil "runner" nunca gera PARTIAL de proposito (ver
                                    # lib_trailing_policy.ps1: partials=@() -- "dinheiro da
                                    # casa", so sai em reversao/time-stop = EXIT acima). So
                                    # "atual"/"scalp"/"swing" chegam aqui de fato.
                                    $tuPartials = if (Get-Command Get-CurrentTrailingPolicy -ErrorAction SilentlyContinue) {
                                        @((Get-CurrentTrailingPolicy).partials)
                                    } else { @() }

                                    # quantidade real (open_interest) NAO existe no journal
                                    # trailing_state -- so na posicao real da corretora.
                                    $tuRealPos = $null
                                    if (Get-Command CoinEx-GetPendingPositions -ErrorAction SilentlyContinue) {
                                        $tuRealPos = @(CoinEx-GetPendingPositions -Market $tuMarket) | Select-Object -First 1
                                    }
                                    if ($tuRealPos -and [double]$tuRealPos.open_interest -gt 0) {
                                        $tuRisk = [Math]::Abs([double]$tuPos.entry - [double]$tuPos.stop)
                                        $tuLadderPos = [PSCustomObject]@{
                                            market = $tuMarket; side = "$($tuPos.side)"
                                            entry = [double]$tuPos.entry; open_interest = [double]$tuRealPos.open_interest
                                            take_profit_price = "$($tuRealPos.take_profit_price)"
                                        }
                                        $tuLadderResult = Register-PartialExitLadder -Position $tuLadderPos -Partials $tuPartials -StopDistance $tuRisk
                                        Write-CrossPlatformLog "  UNIFIED ${tuMarket}: partial exit ladder -> success=$($tuLadderResult.success) reason=$($tuLadderResult.reason)" -LogFile "trailing_stop_monitor.log"
                                    } else {
                                        Write-CrossPlatformLog "  UNIFIED ${tuMarket}: partial exit ladder SKIP -- posicao real nao encontrada/sem quantidade" -Level WARN -LogFile "trailing_stop_monitor.log"
                                    }
                                }
                            } catch {
                                Write-CrossPlatformLog "  UNIFIED ${tuMarket}: partial/exit execution EXCECAO: $_" -Level WARN -LogFile "trailing_stop_monitor.log"
                            }
                        }
                    } else {
                        Write-CrossPlatformLog "  UNIFIED $tuMarket [$($tuPos.side)]: HOLD ($($tuDecision.reason))" -LogFile "trailing_stop_monitor.log"
                    }
                    # 2026-07-19: persiste no Supabase (nao so log local, que o runner
                    # efemero do GH Actions descarta a cada ciclo) -- mantido apos a
                    # promocao pra ativo tambem, agora incluindo se o push realmente
                    # aconteceu (nao so o que o motor decidiu).
                    if (Get-Command Save-StateRecords -ErrorAction SilentlyContinue) {
                        try {
                            Save-StateRecords -Table "trailing_unified_shadow" -Records @([PSCustomObject]@{
                                market              = $tuMarket
                                side                = "$($tuPos.side)"
                                ts                  = (Get-Date -Format "o")
                                real_stop           = [double]$tuPos.stopCurrent
                                unified_action      = $tuDecision.action
                                unified_new_stop    = if ($tuDecision.action -eq "UPDATE") { $tuDecision.new_stop } else { $null }
                                exhaustion_score    = $tuDecision.exhaustion_score
                                atr_pct             = $tuDecision.atr_pct
                                trailing_pct        = $tuDecision.trailing_pct
                                trendline_factor    = $tuDecision.trendline_factor
                                reason              = $tuDecision.reason
                                would_have_differed = ($tuDecision.action -eq "UPDATE") -and ($tuDecision.new_stop -ne [double]$tuPos.stopCurrent)
                                pushed_live         = $tuPushed
                            })
                        } catch {
                            Write-CrossPlatformLog "  UNIFIED ${tuMarket}: persist falhou ($_)" -Level WARN -LogFile "trailing_stop_monitor.log"
                        }
                    }
                } catch {
                    Write-CrossPlatformLog "  UNIFIED ${tuMarket}: skip ($_)" -Level WARN -LogFile "trailing_stop_monitor.log"
                }
            }
        } catch { Write-CrossPlatformLog "TRAILING UNIFIED erro: $_" -Level WARN -LogFile "trailing_stop_monitor.log" }
    }

    # 2.5 PEAK UPDATE FINO + EXECUTOR DE SL (2026-06-18 Fase 1 online)
    # Atualiza peak/phase com lock fino (+2.5% breakeven) e EMPURRA a SL pra corretora.
    # Sync-TrailingToExchange tem trava propria: nunca empurra SL que ja dispararia.
    # Aditivo e idempotente -- nao conflita com Update-AllTrailingStops acima.
    # 2026-06-20 FIX: Usar CoinEx-GetOpenOrders (que tem as posições reais) em vez de GetPendingPositions (não retorna nada)
    Write-CrossPlatformLog "--- PEAK UPDATE + SL SYNC ---" -LogFile "trailing_stop_monitor.log"
    if ((Get-Command Update-TrailingPeakLive -ErrorAction SilentlyContinue) -and (Get-Command CoinEx-GetOpenOrders -ErrorAction SilentlyContinue)) {
        try {
            $allPositions = CoinEx-GetOpenOrders -ErrorAction SilentlyContinue
            foreach ($p in @($allPositions)) {
                $mk = "$($p.market)"
                # Buscar preço atual via API
                try {
                    $ticker = CoinEx-GetTicker -Market $mk -ErrorAction SilentlyContinue
                    $mark = if ($ticker) { [double]$ticker.last } else { 0 }
                } catch {
                    $mark = 0
                }

                # Se preço encontrado, atualiza trailing peak
                if ($mark -gt 0) {
                    Write-CrossPlatformLog "  Updating peak: $mk @ $mark" -LogFile "trailing_stop_monitor.log"
                    Update-TrailingPeakLive -Market $mk -CurrentPrice $mark | Out-Null
                }
            }
        } catch { Write-CrossPlatformLog "peak update: $_" -Level WARN -LogFile "trailing_stop_monitor.log" }
    }

    # 2.55 TRAILING POLICY GATED (DESATIVADO 2026-07-29 -- substituido por
    # TRAILING UNIFIED, ver "2.55c" abaixo). Era o 2o dos 2 motores fragmentados
    # (chandelier ATR multi-timeframe) que, junto com Update-AllTrailingStops,
    # causava o "seta apaga" -- cada um calculava o stop com logica propria,
    # sem coordenacao. Guard $false abaixo desliga sem apagar o codigo
    # (rollback rapido: trocar $false por $true reativa este motor).
    # Ratchet-only no stopCurrent (nunca afrouxa); Sync abaixo empurra (push UNICO -> sem duplicata).
    # NAO executa parciais/saidas (dono = exit_intelligence_auto -> sem double-sell).
    # Gate defere ao trailing ATUAL no regime bear corrente. Kill-switch: remover TRAILING_POLICY_ENABLED.flag
    $tpJournalDir = Join-Path (Split-Path $agentsDir -Parent) "journal"
    $tpFlag = Join-Path $tpJournalDir "TRAILING_POLICY_ENABLED.flag"
    if ($false -and (Test-Path $tpFlag) -and (Get-Command Invoke-TrailingPolicyLive -ErrorAction SilentlyContinue)) {
        Write-CrossPlatformLog "--- TRAILING POLICY (gated, ATIVO) ---" -LogFile "trailing_stop_monitor.log"
        try {
            $tpRegime = Get-RegimeFromState
            $tpPos = @(Get-TrailingPositions | Where-Object { $_.active })
            if ($tpPos.Count -gt 0) {
                $tpMap = @{}       # market -> candles 1D (ATR/SMA do Get-TrailingCandleMetrics)
                $tpHtf = @{}       # market -> {t1D;t4H;t1H} (confluencia multi-TF)
                $useCandleFn = (Get-Command Get-CoinExCandles -ErrorAction SilentlyContinue) -and (Get-Command Get-TrendDirection -ErrorAction SilentlyContinue)
                foreach ($pp in $tpPos) {
                    $mk = [string]$pp.market
                    # 2026-07-07: candle FUTURES (nao spot). Get-CoinExCandles exige -IsFutures
                    # explicito pq futures da CoinEx terminam em USDT e o auto-detect falha.
                    if ($useCandleFn) {
                        try {
                            $c1D = @(Get-CoinExCandles -Market $mk -Period "1day"  -Limit 60 -IsFutures $true)
                            $c4H = @(Get-CoinExCandles -Market $mk -Period "4hour" -Limit 60 -IsFutures $true)
                            $c1H = @(Get-CoinExCandles -Market $mk -Period "1hour" -Limit 60 -IsFutures $true)
                            if ($c1D.Count -ge 2) { $tpMap[$mk] = $c1D }
                            if ($c1D.Count -ge 20 -and $c4H.Count -ge 20 -and $c1H.Count -ge 20) {
                                $tpHtf[$mk] = @{
                                    t1D = (Get-TrendDirection -Candles $c1D -Timeframe "1D")
                                    t4H = (Get-TrendDirection -Candles $c4H -Timeframe "4H")
                                    t1H = (Get-TrendDirection -Candles $c1H -Timeframe "1H")
                                }
                            }
                        } catch { }
                    } else {
                        # Fallback legado (sem lib de candles): 1D spot kline direto.
                        try {
                            $kr = Invoke-RestMethod "https://api.coinex.com/v2/futures/kline?market=$mk&period=1day&limit=60" -TimeoutSec 10 -EA Stop
                            if ($kr.data) {
                                $tpMap[$mk] = @($kr.data | ForEach-Object { [PSCustomObject]@{ open=[double]$_.open; high=[double]$_.high; low=[double]$_.low; close=[double]$_.close; volume=[double]$_.volume } })
                            }
                        } catch { }
                    }
                }
                $tpRes = Invoke-TrailingPolicyLive -Positions $tpPos -CandleMap $tpMap -Regime $tpRegime -HtfTrendMap $tpHtf
                if (@($tpRes.changes).Count -gt 0) {
                    Save-TrailingPositions -Positions $tpRes.positions | Out-Null
                    Write-TrailingPolicyAudit -Changes $tpRes.changes | Out-Null
                    foreach ($c in $tpRes.changes) {
                        Write-CrossPlatformLog "  TP_RATCHET $($c.market) [$($c.selected)]: $($c.old_stop) -> $($c.new_stop) (r=$($c.r_now) regime=$($c.regime))" -Level INFO -LogFile "trailing_stop_monitor.log"
                    }
                } else {
                    Write-CrossPlatformLog "  Nenhum ratchet (regime=$tpRegime defere ao atual / stop ja otimo)" -LogFile "trailing_stop_monitor.log"
                }
            }
        } catch { Write-CrossPlatformLog "TRAILING POLICY erro: $_" -Level WARN -LogFile "trailing_stop_monitor.log" }
    }

    # 2026-07-30 DESATIVADO -- 3o motor fragmentado empurrando stop na mesma
    # execucao do TRAILING UNIFIED. Sync-TrailingToExchange nasceu (2026-06-17)
    # de quando o motor de trailing so escrevia journal sem empurrar pra
    # corretora -- hoje o bloco UNIFIED acima ja chama CoinEx-ModifyPositionStopLoss
    # direto e atualiza o journal no mesmo passo. Sync-TrailingToExchange rodava
    # LOGO DEPOIS, lia o journal que o UNIFIED tinha acabado de atualizar,
    # comparava com o stop_loss_price que a API ainda reportava (nao propagou
    # ainda) e empurrava de NOVO -- confirmado em producao (run 30517140015,
    # 30514386549, 30511299233): SL_PUSH SOLUSDT/SUIUSDT com melhora de
    # 0.09%-4% minutos apos o UNIFIED ja ter processado a mesma posicao. Cada
    # push extra = 1 cancelamento/recriacao de ordem a mais na CoinEx,
    # dobrando a chance do padrao "seta apaga" (TP/SL some da UI por
    # segundos) que o owner reportou ao vivo -- mesma classe de bug da
    # promocao de ontem (2 motores concorrentes = colisao by design da API),
    # so que esse 3o caminho sobreviveu a promocao por engano. Guard $false
    # abaixo desliga sem apagar (rollback rapido: trocar $false por $true).
    if ($false -and (Get-Command Sync-TrailingToExchange -ErrorAction SilentlyContinue)) {
        try {
            $sync = Sync-TrailingToExchange
            foreach ($s in @($sync)) {
                if ($s.pushed) { Write-CrossPlatformLog "  SL_PUSH $($s.market) [$($s.side)]: $($s.exch_sl) -> $($s.journal_sl)" -LogFile "trailing_stop_monitor.log" }
                elseif ($s.should_push -and $s.error) { Write-CrossPlatformLog "  SL_PUSH FALHOU $($s.market): $($s.error)" -Level WARN -LogFile "trailing_stop_monitor.log" }
            }
        } catch { Write-CrossPlatformLog "sync SL: $_" -Level WARN -LogFile "trailing_stop_monitor.log" }
    }

    # 2.7 EXIT INTELLIGENCE (2026-06-19: sai de trades em lucro automaticamente)
    Write-CrossPlatformLog "--- EXIT INTELLIGENCE (4-LAYER) ---" -LogFile "trailing_stop_monitor.log"
    if (Get-Command Invoke-ExitIntelligence -ErrorAction SilentlyContinue) {
        try {
            $allPos = @(CoinEx-GetPendingPositions | Where-Object { $_.active -eq $true })
            if ($allPos.Count -gt 0) {
                # Build price cache (current prices)
                $priceCache = @{}
                $candleCache = @{}

                foreach ($p in $allPos) {
                    $mk = $p.market
                    $priceCache[$mk] = [double]$p.mark_price

                    # Fetch 1H candles (last 24)
                    try {
                        $kr = Invoke-RestMethod "https://api.coinex.com/v2/spot/kline?market=$mk&period=1hour&limit=24" -TimeoutSec 10 -EA Stop
                        if ($kr.data) {
                            $candleCache[$mk] = @($kr.data | ForEach-Object {
                                [PSCustomObject]@{
                                    open = [double]$_.open
                                    high = [double]$_.high
                                    low = [double]$_.low
                                    close = [double]$_.close
                                    volume = [double]$_.volume
                                }
                            })
                        }
                    } catch { }
                }

                # Invoke exit intelligence
                $exitSignals = Invoke-ExitIntelligence -AllPositions $allPos -PriceCache $priceCache -CandleCache $candleCache

                if ($exitSignals.Count -gt 0) {
                    Write-CrossPlatformLog "EXIT SIGNALS DETECTED: $($exitSignals.Count)" -LogFile "trailing_stop_monitor.log"
                    foreach ($exit in $exitSignals) {
                        Write-CrossPlatformLog "  [$($exit.layer)] $($exit.market): SELL $($exit.qty_to_sell) @ `$$($exit.usd_value) PnL=$('{0:+0.00%}' -f $exit.pnl_pct)" -Level INFO -LogFile "trailing_stop_monitor.log"
                        Write-CrossPlatformLog "    Reason: $($exit.reason)" -LogFile "trailing_stop_monitor.log"

                        # TODO: Wire to gem_executor para executar SELL real
                        # Por agora, apenas log (requer aprovação manual ou automated execution)
                    }
                } else {
                    Write-CrossPlatformLog "No exit signals" -LogFile "trailing_stop_monitor.log"
                }
            }
        } catch {
            Write-CrossPlatformLog "EXIT INTELLIGENCE ERROR: $_" -Level WARN -LogFile "trailing_stop_monitor.log"
        }
    } else {
        Write-CrossPlatformLog "Exit Intelligence not available" -Level WARN -LogFile "trailing_stop_monitor.log"
    }

    # 2.8 EXIT INTELLIGENCE AUTO (2026-06-19: Execution automática Layer 2-4)
    Write-CrossPlatformLog "--- EXIT INTELLIGENCE AUTO (Layer 2-4 execution) ---" -LogFile "trailing_stop_monitor.log"
    if (Get-Command Invoke-ExitIntelligenceAuto -ErrorAction SilentlyContinue) {
        try {
            $autoExecResults = Invoke-ExitIntelligenceAuto -Debug:$false
            if ($autoExecResults -and $autoExecResults.Count -gt 0) {
                Write-CrossPlatformLog "EXIT AUTO: $($autoExecResults.Count) positions executed" -LogFile "trailing_stop_monitor.log"
                foreach ($exec in $autoExecResults) {
                    Write-CrossPlatformLog "  [Layer $($exec.layer)] $($exec.market): SOLD $($exec.pct)% ($($exec.qty)) - $($exec.reason)" -Level INFO -LogFile "trailing_stop_monitor.log"
                }

                # ═════════════════════════════════════════════════════════════════
                # 2026-07-07 WIRED: RECONCILE CLOSED POSITIONS (quando fecha)
                # ═════════════════════════════════════════════════════════════════
                if (Get-Command "Reconcile-AppToJournal" -EA SilentlyContinue) {
                    try {
                        $reconResults = Reconcile-AppToJournal -Limit 10
                        Write-CrossPlatformLog "  RECONCILE-OK: $($reconResults.Count) closed positions registered in Supabase" -Level INFO -LogFile "trailing_stop_monitor.log"
                    } catch {
                        Write-CrossPlatformLog "  RECONCILE-WARN: $_" -Level WARN -LogFile "trailing_stop_monitor.log"
                    }
                }
            } else {
                Write-CrossPlatformLog "EXIT AUTO: No layers triggered" -LogFile "trailing_stop_monitor.log"
            }
        } catch {
            Write-CrossPlatformLog "EXIT AUTO ERROR: $_" -Level WARN -LogFile "trailing_stop_monitor.log"
        }
    }

    # 2.9 SPOT STOP FAIL-CLOSED por SALDO REAL (2026-06-24: substitui sync_and_fix_tp)
    # Causa raiz: nuvem comprava spot e ficava NUA (sem stop). sync_and_fix_tp foi
    # desabilitado por criar 178 dups. Agora Sync-SpotStopsToExchange e IDEMPOTENTE
    # (Resolve-SpotStopActions: nao duplica) + cobre TODA holding do saldo (nao so CSV).
    Write-CrossPlatformLog "--- SPOT STOP FAIL-CLOSED (por saldo) ---" -LogFile "trailing_stop_monitor.log"
    if ((Get-Command Get-SpotHoldingsForStop -ErrorAction SilentlyContinue) -and (Get-Command Sync-SpotStopsToExchange -ErrorAction SilentlyContinue)) {
        try {
            $spotTargets = Get-SpotHoldingsForStop -MinUsd 5
            $spotStopRes = Sync-SpotStopsToExchange -Positions $spotTargets
            $placed = @($spotStopRes | Where-Object { $_.action -in @("PLACE","UPDATE","FALLBACK_SELL") -and $_.ok }).Count
            Write-CrossPlatformLog "SPOT STOPS: $(@($spotTargets).Count) holdings cobertas, $placed acao(oes)" -LogFile "trailing_stop_monitor.log"
            foreach ($ss in @($spotStopRes | Where-Object { $_.action -in @("PLACE","FALLBACK_SELL") -and $_.ok })) {
                Write-CrossPlatformLog "  [$($ss.action)] $($ss.market): $($ss.detail)" -Level INFO -LogFile "trailing_stop_monitor.log"
            }
        } catch {
            Write-CrossPlatformLog "SPOT STOP FAIL-CLOSED erro: $_" -Level WARN -LogFile "trailing_stop_monitor.log"
        }
    } else {
        Write-CrossPlatformLog "SPOT STOP guard indisponivel (lib nao carregada)" -Level WARN -LogFile "trailing_stop_monitor.log"
    }

    # 3. VALIDATION
    Write-CrossPlatformLog "--- VALIDATION ---" -LogFile "trailing_stop_monitor.log"

    $allPositions = @(CoinEx-GetPendingPositions)
    $positionsWithoutStop = @()
    $positionsWithoutTP = @()

    foreach ($pos in $allPositions) {
        $hasSl = ($pos.stop_loss_price -and [double]$pos.stop_loss_price -gt 0)
        $hasTp = ($pos.take_profit_price -and [double]$pos.take_profit_price -gt 0)

        if (-not $hasSl) {
            $positionsWithoutStop += $pos
            Write-CrossPlatformLog "  ALERT: $($pos.market) WITHOUT STOP LOSS!" -Level WARN -LogFile "trailing_stop_monitor.log"
        }
        if (-not $hasTp) {
            $positionsWithoutTP += $pos
            Write-CrossPlatformLog "  ALERT: $($pos.market) WITHOUT TAKE PROFIT!" -Level WARN -LogFile "trailing_stop_monitor.log"
        }

        # 2026-05-29: AUTO-REPARO. Reaplica SL/TP reais na corretora (calculados do entry
        # se ausentes). Causa raiz: SL/TP embutido em ordem MARKET nao aplica confiavel.
        if ((-not $hasSl -or -not $hasTp) -and (Get-Command Repair-PositionProtection -ErrorAction SilentlyContinue)) {
            try {
                $rep = Repair-PositionProtection -Market $pos.market -EnableTrailing $true
                if ($rep.success) {
                    Write-CrossPlatformLog "  AUTO-REPAIR OK: $($pos.market) SL=$($rep.stop_loss) TP=$($rep.take_profit)" -LogFile "trailing_stop_monitor.log"
                } else {
                    Write-CrossPlatformLog "  AUTO-REPAIR FAILED: $($pos.market) reason=$($rep.reason)" -Level ERROR -LogFile "trailing_stop_monitor.log"
                }
            } catch {
                Write-CrossPlatformLog "  AUTO-REPAIR EXCEPTION: $($pos.market) $_" -Level ERROR -LogFile "trailing_stop_monitor.log"
            }
        }
    }

    if ($positionsWithoutStop.Count -gt 0) {
        Write-CrossPlatformLog "CRITICAL: $($positionsWithoutStop.Count) position(s) WITHOUT STOP LOSS (auto-repair attempted)!" -Level ERROR -LogFile "trailing_stop_monitor.log"
    } else {
        Write-CrossPlatformLog "All positions have stop loss configured." -LogFile "trailing_stop_monitor.log"
    }
    if ($positionsWithoutTP.Count -gt 0) {
        Write-CrossPlatformLog "WARN: $($positionsWithoutTP.Count) position(s) WITHOUT TAKE PROFIT (auto-repair attempted)." -Level WARN -LogFile "trailing_stop_monitor.log"
    } else {
        Write-CrossPlatformLog "All positions have take profit configured." -LogFile "trailing_stop_monitor.log"
    }
    
    Write-CrossPlatformLog "=== TRAILING STOP MONITOR END ===" -LogFile "trailing_stop_monitor.log"
    
    exit 0
    
} catch {
    Write-CrossPlatformLog "CRITICAL ERROR: $_" -Level ERROR -LogFile "trailing_stop_monitor.log"
    Write-CrossPlatformLog $_.ScriptStackTrace -Level ERROR -LogFile "trailing_stop_monitor.log"
    exit 1
}
