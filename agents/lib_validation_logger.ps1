# lib_validation_logger.ps1 - Validacao Layer 1+2+4 (Opcao 2)
# 2026-05-25: Snapshot logger leve para validar interacoes entre layers
# em modo ADVISORY puro, ate a primeira posicao fechar.
#
# Janela: ate primeira posicao (UNI, LINK, BNB, SOL) fechar.
# Estado: registrado em journal/validation_run.json + JSONL stream.
# Criterio "1a pos fechou" = active==false ou some do trailing_positions.json
#
# NAO interfere no fluxo principal. Side effect: 2 arquivos por ciclo.

$VALIDATION_DIR        = Join-Path (Join-Path $PSScriptRoot "..") "journal"
$VALIDATION_STATE_FILE = Join-Path $VALIDATION_DIR "validation_run.json"
$VALIDATION_STREAM     = Join-Path $VALIDATION_DIR "validation_snapshots.jsonl"
$VALIDATION_REPORT     = Join-Path $VALIDATION_DIR "validation_report.md"

# ---------------------------------------------------------------------
# Start-ValidationRun - Inicializa baseline (idempotente)
# ---------------------------------------------------------------------
function Start-ValidationRun {
    [CmdletBinding()]
    param(
        [string]$Note = ""
    )

    if (-not (Test-Path $VALIDATION_DIR)) {
        New-Item -ItemType Directory -Path $VALIDATION_DIR -Force | Out-Null
    }

    # Idempotencia: se ja existe e nao fechou, retorna o existente
    if (Test-Path $VALIDATION_STATE_FILE) {
        try {
            $existing = Get-Content $VALIDATION_STATE_FILE -Raw | ConvertFrom-Json
            if ($existing -and -not $existing.closed) {
                Write-Host "[Validation] Run ja ativa desde $($existing.startedAt)" -ForegroundColor DarkGray
                return $existing
            }
        } catch { }
    }

    # Capturar baseline
    $positions = @(Get-TrailingPositions) | Where-Object { $_.active }
    $baseline  = @{
        startedAt          = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        note               = $Note
        closed             = $false
        firstClosedMarket  = $null
        firstClosedAt      = $null
        cycleCount         = 0
        baselinePositions  = @($positions | ForEach-Object {
            @{
                market      = $_.market
                side        = $_.side
                entry       = $_.entry
                stop        = $_.stopCurrent
                target      = $_.target
                phase       = $_.phase
                peak        = $_.peak
                price       = $_.currentPrice
            }
        })
    }

    $baseline | ConvertTo-Json -Depth 6 | Set-Content $VALIDATION_STATE_FILE -Encoding utf8

    # Stream header
    $hdr = @{
        type       = "RUN_START"
        timestamp  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        note       = $Note
        positions  = $baseline.baselinePositions
    } | ConvertTo-Json -Depth 6 -Compress
    Add-Content -Path $VALIDATION_STREAM -Value $hdr -Encoding utf8

    Write-Host "[Validation] Run iniciada - $($baseline.baselinePositions.Count) posicoes baseline" -ForegroundColor Cyan
    return $baseline
}

# ---------------------------------------------------------------------
# Write-ValidationSnapshot - Chamado por ciclo do scan_master
# ---------------------------------------------------------------------
function Write-ValidationSnapshot {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $VALIDATION_STATE_FILE)) { return }

    try {
        $state = Get-Content $VALIDATION_STATE_FILE -Raw | ConvertFrom-Json
    } catch { return }

    if ($state.closed) { return }  # Run finalizada, nao snapshotar mais

    $state.cycleCount = [int]$state.cycleCount + 1

    # Snapshot atual de todas as posicoes
    $current = @(Get-TrailingPositions)
    $activeMarkets = @($current | Where-Object { $_.active } | ForEach-Object { $_.market })

    # Detectar fechamento (qualquer baseline market que nao esta mais ativo)
    $baselineMarkets = @($state.baselinePositions | ForEach-Object { $_.market })
    $closedMarket = $null
    foreach ($m in $baselineMarkets) {
        if ($m -notin $activeMarkets) {
            $closedMarket = $m
            break
        }
    }

    # Macro regime (se disponivel)
    $regime = "UNKNOWN"
    if (Get-Command Get-MacroContext -ErrorAction SilentlyContinue) {
        try {
            $macro = Get-MacroContext
            if ($macro -and $macro.regime) { $regime = [string]$macro.regime }
        } catch { }
    } elseif (Get-Command Get-MacroRegime -ErrorAction SilentlyContinue) {
        try { $regime = (Get-MacroRegime).regime } catch { }
    }

    # Snapshot por posicao
    $snapshotPositions = @()
    foreach ($bm in $state.baselinePositions) {
        $cur = $current | Where-Object { $_.market -eq $bm.market } | Select-Object -First 1
        if ($null -eq $cur) {
            # Posicao fechou
            $snapshotPositions += @{
                market    = $bm.market
                status    = "CLOSED"
                phase     = $null
                peak      = $null
                stop      = $null
                price     = $null
                pnlPct    = $null
                layer4    = $null
                layer4Tier = $null
                hoursOpen = $null
            }
        } else {
            $hoursOpen = 0
            try {
                $opened = [datetime]::ParseExact($cur.openedAt, "yyyy-MM-dd HH:mm:ss", $null)
                $hoursOpen = [math]::Round(((Get-Date) - $opened).TotalHours, 2)
            } catch { }

            $pnlPct = if ($bm.entry -gt 0 -and $cur.currentPrice) {
                if ($bm.side -eq "LONG") {
                    [math]::Round((([double]$cur.currentPrice - [double]$bm.entry) / [double]$bm.entry) * 100, 2)
                } else {
                    [math]::Round((([double]$bm.entry - [double]$cur.currentPrice) / [double]$bm.entry) * 100, 2)
                }
            } else { $null }

            $l4Action = if ($cur.PSObject.Properties['layer4Advisory']) { $cur.layer4Advisory } else { "HOLD" }
            $l4Tier   = if ($cur.PSObject.Properties['layer4AdvisoryTier']) { $cur.layer4AdvisoryTier } else { "NONE" }
            $l4Reason = if ($cur.PSObject.Properties['layer4AdvisoryReason']) { $cur.layer4AdvisoryReason } else { "" }

            $snapshotPositions += @{
                market      = $cur.market
                status      = "ACTIVE"
                phase       = $cur.phase
                peak        = $cur.peak
                stop        = $cur.stopCurrent
                price       = $cur.currentPrice
                pnlPct      = $pnlPct
                hoursOpen   = $hoursOpen
                layer4      = $l4Action
                layer4Tier  = $l4Tier
                layer4Reason = $l4Reason
            }
        }
    }

    # JSONL stream
    $entry = @{
        type       = "SNAPSHOT"
        timestamp  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        cycle      = $state.cycleCount
        regime     = $regime
        positions  = $snapshotPositions
    } | ConvertTo-Json -Depth 6 -Compress
    Add-Content -Path $VALIDATION_STREAM -Value $entry -Encoding utf8

    # Detectar fechamento e finalizar run
    if ($closedMarket -and -not $state.closed) {
        $state | Add-Member -NotePropertyName "closed" -NotePropertyValue $true -Force
        $state | Add-Member -NotePropertyName "firstClosedMarket" -NotePropertyValue $closedMarket -Force
        $state | Add-Member -NotePropertyName "firstClosedAt" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force

        $closeEvent = @{
            type       = "RUN_END"
            timestamp  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            firstClosed = $closedMarket
            cycleCount = $state.cycleCount
        } | ConvertTo-Json -Depth 4 -Compress
        Add-Content -Path $VALIDATION_STREAM -Value $closeEvent -Encoding utf8

        Write-Host "[Validation] PRIMEIRA POSICAO FECHOU: $closedMarket - gerando relatorio..." -ForegroundColor Magenta
        try { New-ValidationReport } catch { Write-Host "[Validation] erro ao gerar relatorio: $_" -ForegroundColor Red }
    }

    # Persistir state
    $state | ConvertTo-Json -Depth 6 | Set-Content $VALIDATION_STATE_FILE -Encoding utf8
}

# ---------------------------------------------------------------------
# New-ValidationReport - Relatorio markdown ao fim da janela
# ---------------------------------------------------------------------
function New-ValidationReport {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $VALIDATION_STATE_FILE)) {
        Write-Host "[Validation] Sem state, nada a reportar" -ForegroundColor Yellow
        return
    }

    $state = Get-Content $VALIDATION_STATE_FILE -Raw | ConvertFrom-Json

    # Ler todos os snapshots
    $snapshots = @()
    if (Test-Path $VALIDATION_STREAM) {
        Get-Content $VALIDATION_STREAM | ForEach-Object {
            try { $snapshots += ($_ | ConvertFrom-Json) } catch { }
        }
    }
    $snaps = @($snapshots | Where-Object { $_.type -eq "SNAPSHOT" })

    # Metricas por mercado
    $metrics = @{}
    foreach ($bm in $state.baselinePositions) {
        $market = $bm.market
        $marketSnaps = @($snaps | ForEach-Object { $_.positions | Where-Object { $_.market -eq $market } })

        # Tier journey (NONE -> SOFT -> MEDIUM -> HARD)
        $tiers = @($marketSnaps | ForEach-Object { $_.layer4Tier } | Where-Object { $_ -and $_ -ne "" } | Select-Object -Unique)

        # Phase journey (0 -> 1 -> 2 -> 3)
        $phases = @($marketSnaps | ForEach-Object { $_.phase } | Where-Object { $null -ne $_ } | Select-Object -Unique | Sort-Object)

        # PNL extremos
        $pnls = @($marketSnaps | ForEach-Object { $_.pnlPct } | Where-Object { $null -ne $_ })
        $minPnl = if ($pnls.Count -gt 0) { ($pnls | Measure-Object -Minimum).Minimum } else { $null }
        $maxPnl = if ($pnls.Count -gt 0) { ($pnls | Measure-Object -Maximum).Maximum } else { $null }
        $finalPnl = if ($pnls.Count -gt 0) { $pnls[-1] } else { $null }

        # Peak vs final
        $peaks = @($marketSnaps | ForEach-Object { $_.peak } | Where-Object { $null -ne $_ })
        $maxPeak = if ($peaks.Count -gt 0) { ($peaks | Measure-Object -Maximum).Maximum } else { $null }

        # Layer4 actions unicas
        $l4Actions = @($marketSnaps | ForEach-Object { $_.layer4 } | Where-Object { $_ } | Select-Object -Unique)

        $metrics[$market] = @{
            entry      = $bm.entry
            tiers      = $tiers
            phases     = $phases
            minPnlPct  = $minPnl
            maxPnlPct  = $maxPnl
            finalPnlPct = $finalPnl
            maxPeak    = $maxPeak
            l4Actions  = $l4Actions
            samples    = $marketSnaps.Count
        }
    }

    # Montar markdown (ASCII puro - PS5.1 compat)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Relatorio de Validacao - Layer 1+2+4")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- Iniciada: $($state.startedAt)")
    [void]$sb.AppendLine("- Encerrada: $($state.firstClosedAt)")
    [void]$sb.AppendLine("- Primeira posicao fechada: $($state.firstClosedMarket)")
    [void]$sb.AppendLine("- Ciclos observados: $($state.cycleCount)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Criterio de sucesso (b/c/d)")
    [void]$sb.AppendLine("- (b) Trades ruins fechados antes do worst-case?")
    [void]$sb.AppendLine("- (c) Peaks capturados ao menos parcialmente?")
    [void]$sb.AppendLine("- (d) Sem regressao vs comportamento anterior?")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Metricas por posicao")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Market | Entry | Min PNL% | Max PNL% | Final PNL% | Peak | Phases | L4 Tiers | L4 Actions |")
    [void]$sb.AppendLine("|--------|-------|----------|----------|------------|------|--------|----------|------------|")
    foreach ($m in $metrics.Keys) {
        $x = $metrics[$m]
        $tiersStr = ($x.tiers -join " -> ")
        $phasesStr = ($x.phases -join " -> ")
        $actionsStr = ($x.l4Actions -join ", ")
        [void]$sb.AppendLine("| $m | $($x.entry) | $($x.minPnlPct) | $($x.maxPnlPct) | $($x.finalPnlPct) | $($x.maxPeak) | $phasesStr | $tiersStr | $actionsStr |")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Analise")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("(Avaliar manualmente apos leitura - comparar minPnl com stop, maxPnl vs final, e se Layer4 escalou tiers conforme esperado.)")

    $sb.ToString() | Set-Content $VALIDATION_REPORT -Encoding utf8
    Write-Host "[Validation] Relatorio gerado: $VALIDATION_REPORT" -ForegroundColor Green
}

# ---------------------------------------------------------------------
# Stop-ValidationRun - Encerrar manualmente (para testes)
# ---------------------------------------------------------------------
function Stop-ValidationRun {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $VALIDATION_STATE_FILE)) { return }
    $state = Get-Content $VALIDATION_STATE_FILE -Raw | ConvertFrom-Json
    $state | Add-Member -NotePropertyName "closed" -NotePropertyValue $true -Force
    $state | Add-Member -NotePropertyName "firstClosedAt" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
    $state | ConvertTo-Json -Depth 6 | Set-Content $VALIDATION_STATE_FILE -Encoding utf8
    New-ValidationReport
    Write-Host "[Validation] Run encerrada manualmente" -ForegroundColor Yellow
}
