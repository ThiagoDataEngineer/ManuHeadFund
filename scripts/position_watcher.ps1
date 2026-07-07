# position_watcher.ps1 — Monitora posições COM DADOS REAIS (não API bugada)
# Usa CoinEx websocket ou polling com fallback local

param(
    [int]$CheckInterval = 15  # segundos entre checks
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"

function Write-WatchLog {
    param([string]$Level, [string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path (Join-Path $journalDir "position_watcher.log") -Value $line -Encoding UTF8
    Write-Host $line
}

Set-Location $projectRoot

try {
    . (Join-Path $agentsDir "config.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "config.local.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_coinex.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_position_price.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_daemon_singleton.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_trailing.ps1") -ErrorAction SilentlyContinue  # 2026-06-25: Get-TrailingPositions (Supabase-aware) p/ spot/futures stop sync abaixo
    . (Join-Path $agentsDir "lib_trailing_peak_update.ps1") -ErrorAction SilentlyContinue  # 2026-06-17: trailing cego fix
    . (Join-Path $agentsDir "lib_coinex_position_management.ps1") -ErrorAction SilentlyContinue  # CoinEx-ModifyPositionStopLoss
    . (Join-Path $agentsDir "lib_trailing_sync.ps1") -ErrorAction SilentlyContinue  # 2026-06-17: empurra SL journal->corretora
    . (Join-Path $agentsDir "lib_spot_stop_guard.ps1") -ErrorAction SilentlyContinue  # 2026-06-23: SPOT stop fail-closed (OPN -69% fix)
    . (Join-Path $agentsDir "lib_asymmetric_trail.ps1") -ErrorAction SilentlyContinue  # 2026-06-23: trail assimetrico opt-in (Evolucao B)
    . (Join-Path $agentsDir "lib_futures_stop_guard.ps1") -ErrorAction SilentlyContinue  # 2026-06-23: futures fail-closed
} catch {
    Write-WatchLog "ERROR" "Falha ao carregar libs: $_"
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# 2026-07-07 WIRED: LOAD SUPABASE INTEGRATION LIBS
# ═══════════════════════════════════════════════════════════════════════════════
try {
    . (Join-Path $agentsDir "lib_state_store.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_position_sync_live.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_trade_journal_supabase.ps1") -ErrorAction SilentlyContinue
    Write-WatchLog "INFO" "Supabase integration libs loaded"
} catch {
    Write-WatchLog "WARN" "Supabase integration libs load failed: $_"
}

# Anti-duplicata: position_watcher tambem e singleton (estava duplicando).
if (Get-Command Enter-DaemonSingleton -ErrorAction SilentlyContinue) {
    $__lockDir = Join-Path $journalDir "daemon_locks"
    if (-not (Enter-DaemonSingleton -Name "position_watcher" -LockDir $__lockDir)) {
        Write-WatchLog "SKIP" "Outro position_watcher ja detem o singleton lock; PID=$PID exit."
        exit 0
    }
}

Write-WatchLog "INFO" "Position Watcher iniciado | Check=${CheckInterval}s | FOCO: DADOS REAIS"

# Estado persistido
$positionState = @{}  # mkt -> {entry, qty, highest_price, ...}
$lastAlert = @{}      # mkt -> timestamp da última alerta

$gemTradesPath = Join-Path $journalDir "gem_trades.csv"

function Get-OpenSpotPositions {
    # Lê gem_trades.csv, filtra SPOT OPEN, verifica balance na exchange
    if (-not (Test-Path $gemTradesPath)) { return @() }
    $trades = Import-Csv $gemTradesPath -EA SilentlyContinue
    $openSpot = @($trades | Where-Object { $_.market_type -eq "SPOT" -and $_.status -eq "OPEN" })
    $result = @()
    foreach ($t in $openSpot) {
        $base = $t.market -replace "USDT$",""
        try {
            $bal = CoinEx-Get "/v2/assets/spot/balance" -EA SilentlyContinue
            $coin = if ($bal.code -eq 0) { $bal.data | Where-Object { $_.ccy -eq $base } | Select-Object -First 1 } else { $null }
            $qty = if ($coin) { [double]$coin.available + [double]$coin.frozen } else { [double]$t.qty }
            if ($qty -lt 0.0001) { continue }  # posição já fechada
            $result += [PSCustomObject]@{
                market      = $t.market
                entry_price = [double]$t.price_entry
                stop_price  = [double]$t.stop_price
                target_price= [double]$t.target_price
                qty         = $qty
                side        = "LONG"
            }
        } catch {}
    }
    return $result
}

while ($true) {
    try {
        # ═════════════════════════════════════════════════════════════════
        # 2026-07-07 WIRED: SYNC POSITIONS PERIODICALLY
        # ═════════════════════════════════════════════════════════════════
        if (Get-Command "Sync-PositionsPeriodic" -EA SilentlyContinue) {
            try {
                $syncResult = Sync-PositionsPeriodic
                Write-WatchLog "DEBUG" "Position sync periodic: Futures=$($syncResult.futures_synced) Spot=$($syncResult.spot_synced) Orphans=$($syncResult.orphans_count)"
            } catch {
                Write-WatchLog "WARN" "Periodic sync failed: $_"
            }
        }

        # 1a. Posições FUTURES
        $positions = CoinEx-GetPendingPositions -ErrorAction SilentlyContinue

        if ($positions -and @($positions).Count -gt 0) {
            foreach ($pos in @($positions)) {
                $mkt = $pos.market
                $entry = [double]$pos.avg_entry_price
                $mark = [double]$pos.mark_price
                $pnl_usd = [double]$pos.pnl_usd
                $pnl_pct = [double]$pos.pnl_pct
                $qty = [double]$pos.qty
                $tp = [double]$pos.take_profit_price
                $sl = [double]$pos.stop_loss_price

                # 2. Se mark=0 (API bug comum em micro-caps), busca o ticker 'last'
                #    como fallback em vez de pular. Pular deixava a posicao SEM gestao
                #    de stop (capital cego). Ver lib_position_price + lib_position_price.Tests.
                if ($mark -le 0) {
                    $tickerLast = 0
                    try {
                        $ft = Invoke-RestMethod "https://api.coinex.com/v2/futures/ticker?market=$mkt" -TimeoutSec 8 -EA Stop
                        if ($ft.data) { $tickerLast = [double]$ft.data[0].last }
                    } catch { }
                    $mark = Resolve-MarkPrice -Mark $mark -TickerLast $tickerLast
                    if (-not (Test-PriceUsable -Price $mark)) {
                        Write-WatchLog "SKIP" "${mkt}: mark=0 E ticker last=0 (sem preco valido), aguardando proximo ciclo"
                        continue
                    }
                    # Recomputa pnl% price-based a partir do last real (pos.pnl_pct vinha 0/furado)
                    $pnl_pct = Get-PositionPnlPct -Price $mark -Entry $entry -Side $pos.side
                    Write-WatchLog "FALLBACK" "${mkt}: mark=0 -> ticker last=$mark | pnl(price)=$([math]::Round($pnl_pct,2))%"
                }

                $price_to_use = $mark
                if ($mark -le $entry * 0.9) {
                    # Mark price anormalmente baixo (>10% down) — verificar se é SL real
                    Write-WatchLog "WARN" "${mkt}: mark suspeito ($mark vs entry $entry), verificando SL"
                }

                # 3. Atualiza estado local
                if (-not $positionState[$mkt]) {
                    $positionState[$mkt] = @{
                        entry = $entry
                        qty = $qty
                        highest_price = $price_to_use
                        highest_pnl = $pnl_pct
                        opened_at = Get-Date
                    }
                    Write-WatchLog "OPEN" "${mkt}: POSIÇÃO ABERTA | Entry=$entry | Qty=$qty"
                }

                # 4. Rastreia melhor preço (para trailing stop)
                if ($price_to_use -gt $positionState[$mkt].highest_price) {
                    $positionState[$mkt].highest_price = $price_to_use
                    $positionState[$mkt].highest_pnl = $pnl_pct
                    Write-WatchLog "HIGH" "${mkt}: NOVO MÁXIMO | Price=$price_to_use | PnL=$([math]::Round($pnl_pct,2))%"
                }

                # 4b. 2026-06-17 FIX trailing cego: ATUALIZA peak/SL no journal a cada ciclo
                # (antes so vivia na memoria -> trailing_positions.json congelava -> SL nunca subia).
                # Side-aware (LONG/SHORT) + lock fino +2.5% breakeven. Fail-soft.
                if (Get-Command Update-TrailingPeakLive -ErrorAction SilentlyContinue) {
                    try {
                        $tu = Update-TrailingPeakLive -Market $mkt -CurrentPrice $price_to_use
                        if ($tu.updated) { Write-WatchLog "TRAIL" "${mkt}: peak/SL atualizado (price=$([math]::Round($price_to_use,6)))" }
                    } catch { Write-WatchLog "WARN" "${mkt}: trailing update falhou: $_" }
                }

                # 5. Alerta se chegou perto do TP
                $tp_distance = (($tp - $price_to_use) / $price_to_use) * 100
                if ($tp_distance -lt 2 -and -not $lastAlert["${mkt}_TP"]) {
                    $tp_dist_str = "$([math]::Round($tp_distance,2))pct"
                    Write-WatchLog "ALERT" "${mkt}: PROXIMO DO TP! Distance=$tp_dist_str"
                    Send-TelegramAlert -Message "ATENCAO: $mkt perto do TP ($tp_dist_str restante)" | Out-Null
                    $lastAlert["${mkt}_TP"] = Get-Date
                }

                # 6. Alerta se atingiu SL (esperado que fecha automaticamente)
                if ($price_to_use -le $sl) {
                    Write-WatchLog "SL_HIT" "${mkt}: SL ATIVADO! Price=$price_to_use vs SL=$sl"
                    Send-TelegramAlert -Message "SL ATIVADO $mkt | Perda: $([math]::Round($pnl_pct,2))% ($pnl_usd USD)" | Out-Null
                    $positionState.Remove($mkt)
                }

                # 6b. 2026-06-23 FUTURES FAIL-CLOSED: garante que toda posicao tem SL na corretora.
                # Furo: posicao nua (sl=0) nao rastreada no journal ficava sem protecao.
                # PlannedStop = SL ja setado, senao journal stopCurrent, senao default 15% do entry.
                if (Get-Command Resolve-FuturesStopGuard -ErrorAction SilentlyContinue) {
                    $sideF = "$($pos.side)".ToUpper(); if (-not $sideF) { $sideF = "LONG" }
                    $planned = if ($sl -gt 0) { $sl } else {
                        if ($sideF -eq "SHORT") { [math]::Round($entry * 1.15, 8) } else { [math]::Round($entry * 0.85, 8) }
                    }
                    $g = Resolve-FuturesStopGuard -Side $sideF -MarkPrice $price_to_use -ExchangeStop $sl -PlannedStop $planned -HasPosition $true
                    try {
                        if ($g.action -eq "SET" -and (Get-Command CoinEx-ModifyPositionStopLoss -ErrorAction SilentlyContinue)) {
                            $resp = CoinEx-ModifyPositionStopLoss -Market $mkt -Price ([decimal]$g.stop)
                            if ($resp.success) {
                                Write-WatchLog "FUT_STOP" "${mkt}: SL fail-closed setado na corretora ($($g.stop))"
                                Send-TelegramAlert -Message "FUTURES ${mkt}: SL fail-closed setado ($($g.stop))" | Out-Null
                            } else { Write-WatchLog "WARN" "${mkt}: set SL futures falhou" }
                        } elseif ($g.action -eq "CLOSE_FALLBACK" -and (Get-Command CoinEx-ClosePosition -ErrorAction SilentlyContinue)) {
                            CoinEx-ClosePosition $mkt | Out-Null
                            Write-WatchLog "SL_HIT" "${mkt}: FUTURES fallback fecha a mercado ($($g.reason))"
                            Send-TelegramAlert -Message "FUTURES ${mkt}: fechado a mercado (fallback nua+furou)" | Out-Null
                            $positionState.Remove($mkt)
                        }
                    } catch { Write-WatchLog "WARN" "${mkt}: futures stop guard falhou: $_" }
                }

                # 7. Log contínuo conciso
                $pnl_dir = if ($pnl_pct -gt 0) { "UP" } elseif ($pnl_pct -lt 0) { "DOWN" } else { "FLAT" }
                $pnl_str = "$([math]::Round($pnl_pct,2))pct"
                Write-WatchLog "WATCH" "[$pnl_dir] ${mkt}: Price=$([math]::Round($price_to_use,6)) | PnL=$pnl_str ($pnl_usd USD) | TP=$tp | SL=$sl"
            }
        }

        # 1b. Posições SPOT (via gem_trades.csv)
        $spotPositions = Get-OpenSpotPositions
        foreach ($spos in $spotPositions) {
            $mkt = $spos.market
            try {
                $ticker = Invoke-RestMethod "https://api.coinex.com/v2/spot/ticker?market=$mkt" -EA Stop
                $currentPrice = [double]$ticker.data.last
            } catch { continue }

            if ($currentPrice -le 0) { continue }

            $entry  = $spos.entry_price
            $sl     = $spos.stop_price
            $tp     = $spos.target_price
            $qty    = $spos.qty
            $pnl_pct = if ($entry -gt 0) { [math]::Round(($currentPrice - $entry) / $entry * 100, 2) } else { 0 }
            $pnl_usd = [math]::Round(($currentPrice - $entry) * $qty, 2)

            if (-not $positionState["SPOT_$mkt"]) {
                $positionState["SPOT_$mkt"] = @{ entry=$entry; qty=$qty; highest_price=$currentPrice; opened_at=Get-Date }
                Write-WatchLog "OPEN" "SPOT ${mkt}: Entry=$entry | Qty=$qty | SL=$sl | TP=$tp"
            }
            if ($currentPrice -gt $positionState["SPOT_$mkt"].highest_price) {
                $positionState["SPOT_$mkt"].highest_price = $currentPrice
            }

            # 2026-06-17 FIX trailing cego (SPOT): atualiza peak/SL no journal a cada ciclo
            if (Get-Command Update-TrailingPeakLive -ErrorAction SilentlyContinue) {
                try {
                    $tu = Update-TrailingPeakLive -Market $mkt -CurrentPrice $currentPrice
                    if ($tu.updated) { Write-WatchLog "TRAIL" "SPOT ${mkt}: peak/SL atualizado (price=$currentPrice)" }
                } catch { Write-WatchLog "WARN" "SPOT ${mkt}: trailing update falhou: $_" }
            }

            $pnl_emoji = if ($pnl_pct -gt 0) { "GANHO" } elseif ($pnl_pct -lt 0) { "PERDA" } else { "FLAT" }
            Write-WatchLog "SPOT" "[$pnl_emoji] ${mkt}: Price=$currentPrice | PnL=$pnl_pct% ($pnl_usd USD) | SL=$sl | TP=$tp"

            # Alerta se próximo do SL
            if ($sl -gt 0 -and $currentPrice -le ($sl * 1.05) -and -not $lastAlert["${mkt}_SL_WARN"]) {
                Send-TelegramAlert -Message "SPOT $mkt PROXIMO DO SL! Price=$currentPrice SL=$sl PnL=$pnl_pct%" | Out-Null
                $lastAlert["${mkt}_SL_WARN"] = Get-Date
                Write-WatchLog "WARN" "SPOT ${mkt}: Proximo do SL ($currentPrice vs $sl)"
            }
        }

        # 7b. 2026-06-23 FIX OPN -69%: SPOT stop FAIL-CLOSED na corretora.
        # Antes o loop SPOT acima SO alertava no SL (nunca vendia) -> daemon morto = capital nu.
        # Agora coloca stop-order real na CoinEx (sobrevive daemon caido), idempotente
        # (Resolve-SpotStopActions nao duplica -> sem repetir bug das 178 stops).
        if (Get-Command Sync-SpotStopsToExchange -ErrorAction SilentlyContinue) {
            try {
                # 2026-06-24 CAUSA RAIZ: cobre TODA holding do saldo real (nao so o CSV).
                # Compras da nuvem/manual nao registradas tambem ganham stop fail-closed.
                $stopTargets = if (Get-Command Get-SpotHoldingsForStop -ErrorAction SilentlyContinue) {
                    Get-SpotHoldingsForStop -MinUsd 5
                } else { $spotPositions }
                $spotStops = Sync-SpotStopsToExchange -Positions $stopTargets
                foreach ($ss in @($spotStops)) {
                    if ($ss.action -eq "PLACE" -and $ss.ok) {
                        Write-WatchLog "SPOT_STOP" "$($ss.market): stop FAIL-CLOSED colocado na corretora ($($ss.detail))"
                        Send-TelegramAlert -Message "SPOT $($ss.market): stop protegido na corretora ($($ss.detail))" | Out-Null
                    } elseif ($ss.action -eq "UPDATE" -and $ss.ok) {
                        Write-WatchLog "SPOT_STOP" "$($ss.market): trailing $($ss.detail)"
                        Send-TelegramAlert -Message "SPOT $($ss.market): trailing $($ss.detail)" | Out-Null
                    } elseif ($ss.action -eq "FALLBACK_SELL" -and $ss.ok) {
                        Write-WatchLog "SL_HIT" "$($ss.market): FALLBACK venda a mercado ($($ss.detail))"
                        Send-TelegramAlert -Message "SPOT $($ss.market): SL FALLBACK - vendido a mercado ($($ss.detail))" | Out-Null
                    } elseif ($ss.action -eq "CANCEL" -and $ss.ok) {
                        Write-WatchLog "SPOT_STOP" "$($ss.market): stop redundante cancelado ($($ss.detail))"
                    } elseif ($ss.action -eq "SKIP_DUST") {
                        # silencioso (poeira/sub-nano/simbolo) — nao polui o log
                    } elseif (-not $ss.ok) {
                        Write-WatchLog "WARN" "SPOT $($ss.market): stop $($ss.action) falhou ($($ss.detail))"
                    }
                }
            } catch { Write-WatchLog "WARN" "sync spot stops falhou: $_" }
        }

        # 8. 2026-06-17: SYNC journal->corretora (empurra SL real, com trava de seguranca)
        # Elo que faltava: trailing executa de verdade. Nunca empurra SL que dispararia.
        if (Get-Command Sync-TrailingToExchange -ErrorAction SilentlyContinue) {
            try {
                $sync = Sync-TrailingToExchange
                foreach ($s in @($sync)) {
                    if ($s.pushed) {
                        Write-WatchLog "SL_PUSH" "$($s.market) [$($s.side)]: SL $($s.exch_sl) -> $($s.journal_sl) na corretora"
                        Send-TelegramAlert -Message "Trailing: SL $($s.market) movido p/ $($s.journal_sl) (protege lucro)" | Out-Null
                    } elseif ($s.should_push -and $s.error) {
                        Write-WatchLog "WARN" "$($s.market): push SL falhou: $($s.error)"
                    }
                }
            } catch { Write-WatchLog "WARN" "sync trailing falhou: $_" }
        }

        Start-Sleep -Seconds $CheckInterval
    } catch {
        Write-WatchLog "ERROR" "Ciclo falhou: $_"
        Start-Sleep -Seconds $CheckInterval
    }
}
