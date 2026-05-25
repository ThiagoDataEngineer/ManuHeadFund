# journal.ps1 — Journal de trades: registro, revisao e estatisticas
# Filosofia: Mark Douglas (Trading in the Zone) + Van Tharp (Trade Your Way to Financial Freedom)
# Dot-source: . (Join-Path $PSScriptRoot "journal.ps1")

. (Join-Path $PSScriptRoot "config.ps1")

$JOURNAL_HEADERS = "id,timestamp,market,sinal,entry_price,stop_loss,alvo1,alvo2," +
                   "quantidade,risco_usd,rr_planejado,score_ponderado,qualidade_setup," +
                   "mentor_veredicto,status,exit_price,exit_timestamp,pnl_usd,pnl_pct," +
                   "resultado,motivo_saida,erros_execucao,notas,ordem_id"

function Initialize-Journal {
    if (-not (Test-Path $JOURNAL_DIR)) {
        New-Item -ItemType Directory -Path $JOURNAL_DIR -Force | Out-Null
    }
    if (-not (Test-Path $JOURNAL_FILE)) {
        $JOURNAL_HEADERS | Out-File -FilePath $JOURNAL_FILE -Encoding UTF8
        Write-Host "Journal criado: $JOURNAL_FILE" -ForegroundColor Green
    }
}

function New-TradeEntry {
    param(
        [string]$Market,
        [string]$Sinal,          # LONG | SHORT
        [double]$EntryPrice,
        [double]$StopLoss,
        [double]$Alvo1,
        [double]$Alvo2       = 0,
        [double]$Quantidade,
        [double]$RiscoUSD,
        [double]$RRPlanejado = 0,
        [double]$ScorePonderado = 0,
        [string]$QualidadeSetup = "",
        [string]$MentorVeredicto = "",
        [string]$OrdemId     = "",
        [string]$Notas       = ""
    )

    Initialize-Journal

    $id        = [System.Guid]::NewGuid().ToString("N").Substring(0, 8)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $rr = if ($RRPlanejado -gt 0) { $RRPlanejado }
          elseif ($StopLoss -gt 0 -and $Alvo1 -gt 0) {
              $stopDist = [math]::Abs($EntryPrice - $StopLoss)
              $targetDist = [math]::Abs($Alvo1 - $EntryPrice)
              if ($stopDist -gt 0) { [math]::Round($targetDist / $stopDist, 2) } else { 0 }
          } else { 0 }

    $line = "$id,$timestamp,$Market,$Sinal,$EntryPrice,$StopLoss,$Alvo1,$Alvo2," +
            "$Quantidade,$RiscoUSD,$rr,$ScorePonderado,$QualidadeSetup," +
            "$MentorVeredicto,ABERTO,,,,,,,,$Notas,$OrdemId"

    $line | Out-File -FilePath $JOURNAL_FILE -Append -Encoding UTF8
    Write-Host "  [Journal] Trade registrado: $id | $Market $Sinal @ $EntryPrice" -ForegroundColor Green
    return $id
}

# Registra trade a partir do resultado do orchestrator
function Add-OrchestratorTrade {
    param([object]$OrchestratorResult, [string]$Notas = "")

    if (-not $OrchestratorResult) { return $null }
    if ($OrchestratorResult.decisao -notmatch "EXECUTAR") { return $null }

    return New-TradeEntry `
        -Market          $OrchestratorResult.market `
        -Sinal           $OrchestratorResult.sinalTech `
        -EntryPrice      $OrchestratorResult.entryPrice `
        -StopLoss        $OrchestratorResult.stopLoss `
        -Alvo1           $OrchestratorResult.alvo1 `
        -Quantidade      $OrchestratorResult.quantidadeUnits `
        -RiscoUSD        $OrchestratorResult.riscoUSD `
        -RRPlanejado     $OrchestratorResult.rrFinal `
        -ScorePonderado  $OrchestratorResult.scorePonderado `
        -QualidadeSetup  $OrchestratorResult.qualidadeSetup `
        -MentorVeredicto $OrchestratorResult.mentorVeredicto `
        -OrdemId         $OrchestratorResult.ordemId `
        -Notas           $Notas
}

# Fecha um trade existente com resultado
function Close-Trade {
    param(
        [string]$TradeId,
        [double]$ExitPrice,
        [string]$MotivoSaida,    # STOP_LOSS | ALVO1 | ALVO2 | MANUAL | TRAILING
        [string]$ErrosExecucao = "",
        [string]$Notas         = ""
    )

    Initialize-Journal
    $content = Get-Content $JOURNAL_FILE -Encoding UTF8
    $header  = $content[0]
    $rows    = $content | Select-Object -Skip 1

    $updated = $false
    $newRows = $rows | ForEach-Object {
        $cols = $_ -split ","
        if ($cols[0] -eq $TradeId -and $cols[14] -eq "ABERTO") {
            $sinal      = $cols[3]
            $entryPrice = [double]$cols[4]
            $quantidade = [double]$cols[8]
            $riscoUSD   = [double]$cols[9]

            $pnlUSD = if ($sinal -eq "LONG") {
                [math]::Round(($ExitPrice - $entryPrice) * $quantidade, 2)
            } else {
                [math]::Round(($entryPrice - $ExitPrice) * $quantidade, 2)
            }

            $pnlPct     = if ($entryPrice -gt 0) { [math]::Round($pnlUSD / ($entryPrice * $quantidade) * 100, 2) } else { 0 }
            $resultado  = if ($pnlUSD -gt 0) { "WIN" } elseif ($pnlUSD -lt 0) { "LOSS" } else { "BREAK_EVEN" }
            $exitTS     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

            # Reconstruir linha com saida preenchida
            $cols[14] = "FECHADO"
            $cols[15] = $ExitPrice
            $cols[16] = $exitTS
            $cols[17] = $pnlUSD
            $cols[18] = $pnlPct
            $cols[19] = $resultado
            $cols[20] = $MotivoSaida
            $cols[21] = $ErrosExecucao
            if ($Notas) { $cols[22] = $Notas }

            $updated = $true
            Write-Host "  [Journal] Trade $TradeId fechado: $resultado PnL=$pnlUSD USD ($pnlPct%)" -ForegroundColor $(if($pnlUSD -gt 0){"Green"}else{"Red"})
        }
        $_ = $cols -join ","
        $_
    }

    if ($updated) {
        @($header) + $newRows | Out-File -FilePath $JOURNAL_FILE -Encoding UTF8

        # E4 wire (2026-05-23): compute + persist alpha_vs_btc se libs disponiveis.
        # Fail-soft: erro nao bloqueia close. Schema migration deve ter rodado antes
        # (scripts/migrate_alpha_column.ps1 idempotent).
        try {
            $alphaWirePath = Join-Path $PSScriptRoot "lib_alpha_wire.ps1"
            $alphaLibPath = Join-Path $PSScriptRoot "lib_alpha_vs_btc.ps1"
            if ((Test-Path $alphaWirePath) -and (Test-Path $alphaLibPath)) {
                . $alphaWirePath
                . $alphaLibPath
                if (Test-AlphaColumnExists -CsvPath $JOURNAL_FILE) {
                    # Re-parse closed row pra computar alpha (precisamos entryDate + exitDate + pnlPct + market)
                    $rows = Get-Content $JOURNAL_FILE -Encoding UTF8 | Select-Object -Skip 1
                    foreach ($r in $rows) {
                        if ([string]::IsNullOrWhiteSpace($r)) { continue }
                        $rc = $r -split ","
                        if ($rc[0] -eq $TradeId -and $rc[14] -eq "FECHADO") {
                            $market = $rc[2]
                            $entryTs = $rc[1]
                            $exitTs = $rc[16]
                            $pnlPctVal = 0.0
                            try { $pnlPctVal = [double]$rc[18] } catch {}
                            # Parse dates (YYYY-MM-DD)
                            $entryDate = if ($entryTs) { try { ([datetime]$entryTs).ToString("yyyy-MM-dd") } catch { "" } } else { "" }
                            $exitDate  = if ($exitTs)  { try { ([datetime]$exitTs).ToString("yyyy-MM-dd") }  catch { "" } } else { "" }
                            if ($entryDate -and $exitDate -and $market) {
                                $a = Compute-AlphaVsBtc -Market $market -EntryDateUtc $entryDate -ExitDateUtc $exitDate -TradeReturnPct $pnlPctVal
                                $alphaToWrite = if ($a.valid) { $a.alpha_vs_btc } else { $null }
                                $u = Update-TradeWithAlpha -CsvPath $JOURNAL_FILE -TradeId $TradeId -AlphaVsBtc $alphaToWrite
                                if ($u.updated) {
                                    $alphaStr = if ($null -ne $alphaToWrite) { "$([math]::Round($alphaToWrite,2))pp vs BTC" } else { "n/a (BTC cache miss)" }
                                    Write-Host "  [Journal] alpha_vs_btc=$alphaStr" -ForegroundColor DarkCyan
                                }
                            }
                            break
                        }
                    }
                }
            }
        } catch {
            # Fail-soft: nao bloqueia close
            Write-Host "  [Journal] alpha_vs_btc compute skipped: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))" -ForegroundColor DarkGray
        }
    } else {
        Write-Warning "  [Journal] Trade $TradeId nao encontrado ou ja fechado"
    }
}

# Estatisticas do journal
function Get-JournalStats {
    param([int]$UltimosDias = 30)

    Initialize-Journal
    $content = Get-Content $JOURNAL_FILE -Encoding UTF8
    if ($content.Count -le 1) {
        Write-Host "Journal vazio." -ForegroundColor Yellow
        return
    }

    $cutoff = (Get-Date).AddDays(-$UltimosDias)
    $trades = $content | Select-Object -Skip 1 | ForEach-Object {
        $cols = $_ -split ","
        if ($cols.Count -ge 20 -and $cols[14] -eq "FECHADO") {
            $ts = try { [DateTime]::Parse($cols[1]) } catch { $null }
            if ($ts -and $ts -ge $cutoff) {
                $entryPrice = try { [double]$cols[4] } catch { 0 }
                $stopLoss   = try { [double]$cols[5] } catch { 0 }
                $exitPrice  = try { [double]$cols[15] } catch { 0 }
                $sinal      = $cols[3]
                $stopDist   = [math]::Abs($entryPrice - $stopLoss)
                $exitDist   = if ($sinal -eq "LONG") { $exitPrice - $entryPrice } else { $entryPrice - $exitPrice }
                $rrReal     = if ($stopDist -gt 0 -and $exitPrice -gt 0) { [math]::Round($exitDist / $stopDist, 2) } else { $null }

                $pnlUSD_v  = try { [double]$cols[17] } catch { 0 }
                $pnlPct_v  = try { [double]$cols[18] } catch { 0 }
                $rr_v      = try { [double]$cols[10] } catch { 0 }
                $score_v   = try { [double]$cols[11] } catch { 0 }
                [PSCustomObject]@{
                    id        = $cols[0]
                    ts        = $ts
                    market    = $cols[2]
                    sinal     = $sinal
                    pnlUSD    = $pnlUSD_v
                    pnlPct    = $pnlPct_v
                    resultado = $cols[19]
                    motivo    = $cols[20]
                    rr        = $rr_v
                    rrReal    = $rrReal
                    score     = $score_v
                    qualidade = $cols[12]
                }
            }
        }
    } | Where-Object { $_ -ne $null }

    if (-not $trades) {
        Write-Host "Nenhum trade fechado nos ultimos $UltimosDias dias." -ForegroundColor Yellow
        return
    }

    $total    = $trades.Count
    $wins     = ($trades | Where-Object { $_.resultado -eq "WIN" }).Count
    $losses   = ($trades | Where-Object { $_.resultado -eq "LOSS" }).Count
    $winRate  = if ($total -gt 0) { [math]::Round($wins / $total * 100, 1) } else { 0 }
    $totalPnl = [math]::Round(($trades | Measure-Object -Property pnlUSD -Sum).Sum, 2)

    $avgWin  = if ($wins -gt 0) {
        [math]::Round(($trades | Where-Object { $_.resultado -eq "WIN" } | Measure-Object -Property pnlUSD -Average).Average, 2)
    } else { 0 }
    $avgLoss = if ($losses -gt 0) {
        [math]::Round(($trades | Where-Object { $_.resultado -eq "LOSS" } | Measure-Object -Property pnlUSD -Average).Average, 2)
    } else { 0 }

    $expectancy = if ($total -gt 0) {
        [math]::Round(($winRate/100 * $avgWin) + ((1 - $winRate/100) * $avgLoss), 2)
    } else { 0 }

    # Profit factor
    $grossProfit  = ($trades | Where-Object { $_.pnlUSD -gt 0 } | Measure-Object -Property pnlUSD -Sum).Sum
    $grossLoss    = [math]::Abs(($trades | Where-Object { $_.pnlUSD -lt 0 } | Measure-Object -Property pnlUSD -Sum).Sum)
    $profitFactor = if ($grossLoss -gt 0) { [math]::Round($grossProfit / $grossLoss, 2) } else { "INF" }

    # RR realizado medio
    $rrReaisList = $trades | Where-Object { $null -ne $_.rrReal }
    $avgRrReal   = if ($rrReaisList) {
        [math]::Round(($rrReaisList | Measure-Object -Property rrReal -Average).Average, 2)
    } else { $null }
    $avgRrPlan   = if ($total -gt 0) {
        [math]::Round(($trades | Measure-Object -Property rr -Average).Average, 2)
    } else { 0 }

    # Drawdown
    $runningPnl = 0; $peak = 0; $maxDD = 0
    $trades | Sort-Object ts | ForEach-Object {
        $runningPnl += $_.pnlUSD
        if ($runningPnl -gt $peak) { $peak = $runningPnl }
        $dd = $peak - $runningPnl
        if ($dd -gt $maxDD) { $maxDD = $dd }
    }

    # Maior sequencia de perdas consecutivas
    $curStreak = 0; $maxStreak = 0
    $trades | Sort-Object ts | ForEach-Object {
        if ($_.resultado -eq "LOSS") {
            $curStreak++
            if ($curStreak -gt $maxStreak) { $maxStreak = $curStreak }
        } else { $curStreak = 0 }
    }

    # Breakdown por qualidade de setup
    $qualGroups = $trades | Group-Object qualidade | Sort-Object Name

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  JOURNAL STATS — Ultimos $UltimosDias dias       ║" -ForegroundColor Cyan
    Write-Host "╠══════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  Total trades:    $total" -ForegroundColor White
    Write-Host "║  Win Rate:        $winRate% ($wins/$total)" -ForegroundColor $(if($winRate -ge 50){"Green"}else{"Red"})
    Write-Host "║  PnL Total:       $totalPnl USD" -ForegroundColor $(if($totalPnl -ge 0){"Green"}else{"Red"})
    Write-Host "║  Avg Win:         $avgWin USD" -ForegroundColor Green
    Write-Host "║  Avg Loss:        $avgLoss USD" -ForegroundColor Red
    Write-Host "║  Expectancy:      $expectancy USD/trade" -ForegroundColor $(if($expectancy -ge 0){"Green"}else{"Red"})
    Write-Host "║  Profit Factor:   $profitFactor  (>=1.5 saudavel)" -ForegroundColor $(if($profitFactor -eq "INF" -or [double]$profitFactor -ge 1.5){"Green"}elseif([double]$profitFactor -ge 1.0){"Yellow"}else{"Red"})
    Write-Host "║  RR Planejado:    1:$avgRrPlan (media)" -ForegroundColor White
    Write-Host "║  RR Realizado:    1:$(if($null -ne $avgRrReal){$avgRrReal}else{'N/A'}) (media)" -ForegroundColor $(if($null -ne $avgRrReal -and $avgRrReal -ge $avgRrPlan * 0.8){"Green"}else{"Yellow"})
    Write-Host "║  Max Drawdown:    $([math]::Round($maxDD, 2)) USD" -ForegroundColor Yellow
    Write-Host "║  Max Loss Streak: $maxStreak" -ForegroundColor $(if($maxStreak -ge 3){"Red"}else{"White"})
    Write-Host "╠══════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  Por qualidade de setup:" -ForegroundColor Cyan
    foreach ($g in $qualGroups) {
        $gWins  = ($g.Group | Where-Object { $_.resultado -eq "WIN" }).Count
        $gTotal = $g.Group.Count
        $gWR    = if ($gTotal -gt 0) { [math]::Round($gWins / $gTotal * 100, 0) } else { 0 }
        $gPnl   = [math]::Round(($g.Group | Measure-Object -Property pnlUSD -Sum).Sum, 2)
        $label  = if ($g.Name) { $g.Name } else { "?" }
        Write-Host "║    Setup $($label): $gWR% WR ($gWins/$gTotal) | PnL $gPnl USD" -ForegroundColor $(if($gWR -ge 50){"Green"}else{"Yellow"})
    }
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Alerta Mark Douglas: perdas consecutivas
    if ($maxStreak -ge 3) {
        $ultimosN = $trades | Sort-Object ts | Select-Object -Last $maxStreak
        $recentLossStreak = 0
        $trades | Sort-Object ts | Select-Object -Last 3 | ForEach-Object {
            if ($_.resultado -eq "LOSS") { $recentLossStreak++ }
        }
        if ($recentLossStreak -eq 3) {
            Write-Host "ALERTA MARK DOUGLAS: 3 perdas consecutivas recentes!" -ForegroundColor Red
            Write-Host "Regra Tudor Jones: PARE de operar hoje. Revise seu estado mental." -ForegroundColor Red
            Write-Host ""
        }
    }

    return [PSCustomObject]@{
        total=$total; wins=$wins; losses=$losses; winRate=$winRate
        totalPnl=$totalPnl; avgWin=$avgWin; avgLoss=$avgLoss
        expectancy=$expectancy; profitFactor=$profitFactor
        avgRrPlanejado=$avgRrPlan; avgRrRealizado=$avgRrReal
        maxDrawdown=[math]::Round($maxDD,2); maxLossStreak=$maxStreak
    }
}

# Lista trades abertos
function Get-OpenTrades {
    Initialize-Journal
    $content = Get-Content $JOURNAL_FILE -Encoding UTF8
    $open = $content | Select-Object -Skip 1 | ForEach-Object {
        $cols = $_ -split ","
        if ($cols.Count -ge 15 -and $cols[14] -eq "ABERTO") {
            [PSCustomObject]@{
                id      = $cols[0]; timestamp = $cols[1]; market = $cols[2]
                sinal   = $cols[3]; entry = $cols[4]; stop = $cols[5]
                alvo1   = $cols[6]; qtd = $cols[8]; risco = $cols[9]
                ordemId = if ($cols.Count -gt 23) { $cols[23] } else { "" }
            }
        }
    } | Where-Object { $_ -ne $null }

    if ($open) {
        Write-Host "Trades abertos:" -ForegroundColor Yellow
        $open | ForEach-Object {
            Write-Host "  $($_.id) | $($_.market) $($_.sinal) @ $($_.entry) | Stop: $($_.stop) | Alvo: $($_.alvo1)" -ForegroundColor White
        }
    } else {
        Write-Host "Nenhum trade aberto." -ForegroundColor Gray
    }
    return $open
}
