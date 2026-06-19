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
    . (Join-Path $agentsDir "lib_telegram.ps1")
    . (Join-Path $agentsDir "lib_trailing.ps1")
    . (Join-Path $agentsDir "lib_trailing_stop_intelligent.ps1")
    . (Join-Path $agentsDir "lib_trailing_orphan_detection.ps1")
    # 2026-05-29: auto-reparo de protecao (SL+TP reais na corretora)
    . (Join-Path $agentsDir "lib_coinex_position_management.ps1")
    . (Join-Path $agentsDir "lib_order_validation.ps1")
    . (Join-Path $agentsDir "lib_position_protection.ps1")
    # 2026-06-18 Fase 1 online: peak update fino (+2.5% breakeven) + executor de SL
    . (Join-Path $agentsDir "lib_trailing_peak_update.ps1")
    . (Join-Path $agentsDir "lib_trailing_sync.ps1")
    # 2026-06-19 Fase 2: Exit Intelligence (saídas automáticas em lucro)
    . (Join-Path $agentsDir "lib_exit_intelligence.ps1")

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
    
    # 2. TRAILING STOP UPDATE (se lib disponível)
    Write-CrossPlatformLog "--- TRAILING STOP UPDATE ---" -LogFile "trailing_stop_monitor.log"
    
    if (Get-Command Update-AllTrailingStops -ErrorAction SilentlyContinue) {
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
    
    # 2.5 PEAK UPDATE FINO + EXECUTOR DE SL (2026-06-18 Fase 1 online)
    # Atualiza peak/phase com lock fino (+2.5% breakeven) e EMPURRA a SL pra corretora.
    # Sync-TrailingToExchange tem trava propria: nunca empurra SL que ja dispararia.
    # Aditivo e idempotente -- nao conflita com Update-AllTrailingStops acima.
    Write-CrossPlatformLog "--- PEAK UPDATE + SL SYNC ---" -LogFile "trailing_stop_monitor.log"
    if ((Get-Command Update-TrailingPeakLive -ErrorAction SilentlyContinue) -and (Get-Command CoinEx-GetPendingPositions -ErrorAction SilentlyContinue)) {
        try {
            foreach ($p in @(CoinEx-GetPendingPositions)) {
                $mk = "$($p.market)"; $mark = [double]$p.mark_price
                if ($mark -le 0) {
                    try { $ft = Invoke-RestMethod "https://api.coinex.com/v2/futures/ticker?market=$mk" -TimeoutSec 8 -EA Stop; if ($ft.data) { $mark = [double]$ft.data[0].last } } catch {}
                }
                if ($mark -gt 0) { Update-TrailingPeakLive -Market $mk -CurrentPrice $mark | Out-Null }
            }
        } catch { Write-CrossPlatformLog "peak update: $_" -Level WARN -LogFile "trailing_stop_monitor.log" }
    }
    if (Get-Command Sync-TrailingToExchange -ErrorAction SilentlyContinue) {
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
