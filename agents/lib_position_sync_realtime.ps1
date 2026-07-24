# lib_position_sync_realtime.ps1 — ROOT CAUSE FIX
#
# PROBLEMA RAIZ (2026-07-07 discovery):
#   Posições abertas pelo sistema (7 no total) NÃO estavam sincronizadas com journal
#   - open_positions_tracking.jsonl estava VAZIO
#   - trade_outcomes.jsonl tinha registros FAKE (2 contraditórios)
#   - position_watcher.ps1 tentava ler gem_trades.csv (desatualizado)
#   - Nenhum sync automático rodando de posições REAIS
#
# SOLUÇÃO:
#   1. Fetch posições REAIS via CoinEx API (Get-CoinexFuturesPositions)
#   2. Sync com open_positions_tracking.jsonl (JSONL de auditoria)
#   3. Sync com trade_outcomes.jsonl (reconciliação)
#   4. Publicar em Supabase (cloud backup)
#   5. Chamar automaticamente a cada 15min (ou via scan_master)
#
# PS 5.1. UTF-8 BOM.

if (-not (Get-Command Save-StateRecords -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "lib_state_store.ps1")
}

function Sync-PositionsFromCoinEx {
    <#
    .SYNOPSIS
    Fetch posições REAIS da exchange e sincroniza com journal.
    Chamado por: position_watcher.ps1, scan_master.ps1, trailing_stop_monitor.ps1

    .PARAMETER PublishToSupabase
    Se $true, publica em Supabase open_positions table

    .OUTPUTS
    @{ synced_count, positions, timestamp }
    #>
    [CmdletBinding()]
    param(
        [bool] $PublishToSupabase = $false,
        [string] $JournalDir = $null
    )

    if (-not $JournalDir) {
        $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
    }

    $trackingFile = Join-Path $JournalDir "open_positions_tracking.jsonl"
    $outcomesFile = Join-Path $JournalDir "trade_outcomes.jsonl"
    $syncLogFile  = Join-Path $JournalDir "position_sync.log"

    function Write-SyncLog {
        param([string]$Msg)
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content $syncLogFile -Value "[$ts] $Msg" -Encoding UTF8
    }

    try {
        Write-SyncLog "SYNC START: Fetching posições from CoinEx API (Futures + Spot)"

        # 1. FETCH posições reais da exchange
        $positions = @()

        # 1A. FUTURES posições
        if (Get-Command CoinEx-GetPendingPositions -ErrorAction SilentlyContinue) {
            try {
                $futuresPos = @(CoinEx-GetPendingPositions -ErrorAction Stop)
                $positions += $futuresPos
                Write-SyncLog "FETCHED: $($futuresPos.Count) posições FUTURES"
            } catch {
                Write-SyncLog "WARNING: Erro ao fetch Futures: $_"
            }
        } else {
            Write-SyncLog "WARNING: CoinEx-GetPendingPositions não disponível"
        }

        # 1B. SPOT holdings (assets com saldo > 0)
        if (Get-Command CoinEx-Get -ErrorAction SilentlyContinue) {
            try {
                $spotBalance = CoinEx-Get "/v2/assets/spot/balance" -ErrorAction Stop
                if ($spotBalance -and $spotBalance.data) {
                    $spotHoldings = @($spotBalance.data | Where-Object { [double]$_.available -gt 0 -or [double]$_.frozen -gt 0 })
                    Write-SyncLog "FETCHED: $($spotHoldings.Count) ativos SPOT com saldo"

                    # Converter holdings Spot para formato compatível com Futures
                    foreach ($holding in $spotHoldings) {
                        $positions += [PSCustomObject]@{
                            ccy = $holding.ccy
                            available = [double]$holding.available
                            frozen = [double]$holding.frozen
                            market_type = "SPOT"
                            _spot_indicator = $true  # Flag interno para identificar Spot
                        }
                    }
                }
            } catch {
                Write-SyncLog "WARNING: Erro ao fetch Spot: $_"
            }
        }

        if ($positions.Count -eq 0) {
            Write-SyncLog "INFO: Nenhuma posição/holding aberta encontrada"
            # Limpar tracking file se não há posições
            @{ positions = @(); timestamp = Get-Date } | ConvertTo-Json | Set-Content $trackingFile -Encoding UTF8
            return @{ synced_count = 0; positions = @(); timestamp = Get-Date }
        }

        # 2. SYNC com open_positions_tracking.jsonl
        Write-SyncLog "SYNCING: $($positions.Count) posições → open_positions_tracking.jsonl"

        $trackingData = @{
            positions = @()
            timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            synced_at = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
            note = "Real-time sync from CoinEx API"
        }

        foreach ($pos in $positions) {
            # Detectar se é Spot (holding) ou Futures (position)
            if ($pos._spot_indicator -eq $true) {
                # ── SPOT HOLDING ──
                $entry = [PSCustomObject]@{
                    market_type       = "SPOT"
                    market            = $pos.ccy
                    direction         = "HOLDING"  # Spot não tem direction (long/short)
                    available         = [double]$pos.available
                    frozen            = [double]$pos.frozen
                    total_quantity    = ([double]$pos.available + [double]$pos.frozen)
                    leverage          = 1  # Spot nunca usa leverage
                    pnl_usd           = $null  # Spot não rastreia PnL per-holding neste formato
                    pnl_pct           = $null
                    stop_loss         = $null
                    take_profit       = $null
                    liquidation_price = $null
                    margin_rate       = 0
                    liq_risk_pct      = 0
                    opened_at         = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"  # Assume hoje (holdings não têm opened_at)
                    margin_mode       = "SPOT"
                    position_id       = "SPOT-$($pos.ccy)-HOLDING"
                }
            } else {
                # ── FUTURES POSITION ──
                $pnlUsd = [double]$pos.unrealized_pnl
                $entryPrice = [double]$pos.avg_entry_price
                $settlePrice = [double]$pos.settle_price
                $positionValue = [double]$pos.cml_position_value
                $leverage = [double]$pos.leverage

                # Calcular PnL %: unrealized_pnl / (settlement_value / leverage)
                $pnlPct = if ($positionValue -gt 0) { ($pnlUsd / $positionValue) * 100 } else { 0 }

                # Liq risk: margin_rate * 100 (quanto % da margin foi usado)
                $liqRiskPct = if ([double]$pos.position_margin_rate -gt 0) { [double]$pos.position_margin_rate * 100 } else { 0 }

                # Timestamp: created_at vem em milliseconds Unix
                $openedAtMs = [long]$pos.created_at
                $openedAtDate = [datetime]::UnixEpoch.AddMilliseconds($openedAtMs).ToString("yyyy-MM-ddTHH:mm:ssZ")

                $entry = [PSCustomObject]@{
                    market_type       = "FUTURES"
                    market            = $pos.market
                    direction         = $pos.side.ToUpper()  # API usa "long"/"short", converter para "LONG"/"SHORT"
                    entry_price       = $entryPrice
                    current_price     = $settlePrice  # settle_price é o preço atual
                    quantity          = [double]$pos.open_interest
                    leverage          = $leverage
                    pnl_usd           = $pnlUsd
                    pnl_pct           = $pnlPct
                    stop_loss         = if ($pos.stop_loss_price -and $pos.stop_loss_price -ne "0") { [double]$pos.stop_loss_price } else { $null }
                    take_profit       = if ($pos.take_profit_price -and $pos.take_profit_price -ne "0") { [double]$pos.take_profit_price } else { $null }
                    liquidation_price = if ($pos.liq_price -and $pos.liq_price -ne "0") { [double]$pos.liq_price } else { $null }
                    margin_rate       = [double]$pos.position_margin_rate
                    liq_risk_pct      = $liqRiskPct
                    opened_at         = $openedAtDate
                    margin_mode       = $pos.margin_mode
                    position_id       = $pos.position_id
                }
            }

            $trackingData.positions += $entry
        }

        $trackingData | ConvertTo-Json | Set-Content $trackingFile -Encoding UTF8
        Write-SyncLog "SYNCED: $($trackingData.positions.Count) posições em tracking file"

        # 3. RECONCILE com trade_outcomes.jsonl
        Write-SyncLog "RECONCILE: Validar trade_outcomes.jsonl vs posições reais"

        # Carregar trade_outcomes existentes
        $outcomes = @()
        if (Test-Path $outcomesFile) {
            try {
                $outcomes = @(Get-Content $outcomesFile -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue)
            } catch {
                Write-SyncLog "WARNING: Não conseguiu parsear trade_outcomes.jsonl"
                $outcomes = @()
            }
        }

        # Atualizar trade_outcomes com posições abertas reais
        $updatedOutcomes = @()
        # Spot usa "ccy", Futures usa "market"
        $realMarkets = @($positions | ForEach-Object { if ($_.market) { $_.market } else { $_.ccy } })

        foreach ($outcome in $outcomes) {
            # Se está em outcomes mas NÃO está em posições reais, marcar como closed (se status era open)
            if ($outcome.status -eq "open" -and $outcome.market -notin $realMarkets) {
                $outcome.status = "closed"
                $outcome.exit_date = Get-Date -Format "yyyy-MM-dd"
                $outcome.notes = "Auto-closed via sync: não encontrada em posições reais API"
                Write-SyncLog "UPDATE: $($outcome.market) status open→closed (não na API)"
            }

            $updatedOutcomes += $outcome
        }

        # Adicionar novas posições abertas em trade_outcomes (se não existem)
        foreach ($pos in $positions) {
            $mkt = if ($pos.market) { $pos.market } else { $pos.ccy }  # Spot usa ccy, Futures usa market
            # Para Spot, não rastrear em trade_outcomes (holdings não são "trades")
            if ($pos._spot_indicator -eq $true) {
                Write-SyncLog "SKIP: $mkt é SPOT holding (não adicionar em trade_outcomes)"
                continue
            }

            $existingOutcome = $outcomes | Where-Object { $_.market -eq $mkt -and $_.status -eq "open" } | Select-Object -First 1

            if (-not $existingOutcome) {
                # Novo trade aberto, não registrado em outcomes
                $openedAtMs = [long]$pos.created_at
                $openedAtDate = [datetime]::UnixEpoch.AddMilliseconds($openedAtMs).ToString("yyyy-MM-ddTHH:mm:ssZ")
                $openedDate = [datetime]::UnixEpoch.AddMilliseconds($openedAtMs).ToString("yyyy-MM-dd")

                $pnlUsd = [double]$pos.unrealized_pnl
                $positionValue = [double]$pos.cml_position_value
                $pnlPct = if ($positionValue -gt 0) { ($pnlUsd / $positionValue) * 100 } else { 0 }

                $newOutcome = [PSCustomObject]@{
                    trade_id        = "$mkt-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                    market          = $mkt
                    direction       = $pos.side.ToUpper()
                    entry_price     = [double]$pos.avg_entry_price
                    entry_time      = $openedAtDate
                    entry_date      = $openedDate
                    status          = "open"
                    pnl_usd         = $pnlUsd
                    pnl_pct         = $pnlPct
                    size_usd        = $positionValue
                    leverage        = [double]$pos.leverage
                    source          = "position_sync_realtime"
                    registered_at   = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
                    notes           = "Auto-registered via CoinEx position sync"
                }

                $updatedOutcomes += $newOutcome
                Write-SyncLog "NEW: $mkt adicionado em trade_outcomes (aberto na API)"
            }
        }

        # Salvar trade_outcomes atualizado
        if ($updatedOutcomes.Count -gt 0) {
            # 2026-07-24 FIX: "-AsArray" nao existe no PowerShell 5.1 --
            # lancava erro real, Set-Content nunca rodava. trade_outcomes.jsonl
            # e JSONL real (1 objeto por linha, nao array formatado) --
            # grava linha por linha, cada uma comprimida.
            $lines = @($updatedOutcomes | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 5 })
            Set-Content -Path $outcomesFile -Value $lines -Encoding UTF8
            Write-SyncLog "UPDATED: trade_outcomes.jsonl ($($updatedOutcomes.Count) entradas)"
        }

        # 4. PUBLISH em Supabase (se habilitado) — Futures apenas (Spot holdings não são trades)
        if ($PublishToSupabase -and (Get-Command Save-StateRecords -ErrorAction SilentlyContinue)) {
            Write-SyncLog "PUBLISH: Enviando posições para Supabase..."
            $futuresPositions = @($positions | Where-Object { $_._spot_indicator -ne $true })
            foreach ($pos in $futuresPositions) {
                try {
                    $openedAtMs = [long]$pos.created_at
                    $openedAtDate = [datetime]::UnixEpoch.AddMilliseconds($openedAtMs).ToString("yyyy-MM-ddTHH:mm:ssZ")

                    $pnlUsd = [double]$pos.unrealized_pnl
                    $positionValue = [double]$pos.cml_position_value
                    $pnlPct = if ($positionValue -gt 0) { ($pnlUsd / $positionValue) * 100 } else { 0 }

                    Save-StateRecords -Table "open_positions" -Records @(@{
                        market              = $pos.market
                        direction           = $pos.side.ToUpper()
                        entry_price         = [double]$pos.avg_entry_price
                        current_price       = [double]$pos.settle_price
                        pnl_usd             = $pnlUsd
                        pnl_pct             = $pnlPct
                        leverage            = [double]$pos.leverage
                        opened_at           = $openedAtDate
                        synced_at           = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
                    }) -ErrorAction Stop
                } catch {
                    Write-SyncLog "WARNING: Falha ao publicar $($pos.market) em Supabase: $_"
                }
            }
            Write-SyncLog "PUBLISHED: $($futuresPositions.Count) futures em Supabase (Spot holdings não são trades)"
        }

        Write-SyncLog "SYNC COMPLETE: $($trackingData.positions.Count) posições sincronizadas"

        return @{
            synced_count = $trackingData.positions.Count
            positions    = $trackingData.positions  # Retorna posições mapeadas (não raw API)
            timestamp    = Get-Date
        }
    } catch {
        Write-SyncLog "ERROR: $_"
        return @{ synced_count = 0; positions = @(); timestamp = Get-Date; error = $_ }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# WIRE-UP: Chamar automaticamente
# ─────────────────────────────────────────────────────────────────────────────
# Em scan_master.ps1 (após orchestrator):
#   . agents/lib_position_sync_realtime.ps1
#   Sync-PositionsFromCoinEx -PublishToSupabase $true
#
# Em trailing_stop_monitor.ps1 (a cada 15min):
#   . agents/lib_position_sync_realtime.ps1
#   Sync-PositionsFromCoinEx -PublishToSupabase $false
#
# Em position_watcher.ps1 (ao iniciar):
#   . agents/lib_position_sync_realtime.ps1
#   Sync-PositionsFromCoinEx -PublishToSupabase $true
# ─────────────────────────────────────────────────────────────────────────────
