# promotion_weekly_cron.ps1 -- Cron runner promotion ladder
#
# Roda semanalmente (Domingo 03:00 BRT recomendado via Task Scheduler).
# Para cada market no pipeline:
#   1. Fetch candles via CoinEx API (asset + BTC)
#   2. Compute metrics (regime, mom_20d, trade stats de observations.csv)
#   3. Invoke-PromotionCycle (logica testada em lib_promotion_cycle)
#   4. Para cada action retornada, Send-TgPromotionPropose
#
# Modos:
#   -DryRun     simula sem chamar Telegram (usa Write-Host)
#   -Once       1 cycle e exit (default)
#   -Loop       fica rodando, sleep 7 dias entre cycles
#
# Logs: journal/promotion_cron.log

param(
    [switch]$DryRun,
    [switch]$Once = $true,
    [switch]$Loop
)

$scriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot  = Split-Path -Parent $scriptRoot
$agentsDir    = Join-Path $projectRoot "agents"
$journalDir   = Join-Path $projectRoot "journal"
$pipelinePath = Join-Path $journalDir "promotion_pipeline.jsonl"
$dsrPath      = Join-Path $journalDir "dsr_trials.jsonl"  # B15 race-safe append-only
$obsPath      = Join-Path $journalDir "observations.csv"
$cronLog      = Join-Path $journalDir "promotion_cron.log"

function Write-CronLog {
    param([string]$Level, [string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $cronLog -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Host $line
}

# Load libs (ordem importa)
Set-Location $projectRoot
try {
    . (Join-Path $agentsDir "config.local.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "config.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_promotion_ladder.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_dsr_global.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_promotion_cycle.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_promotion_telegram.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_promotion_paper_engine.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_coinex_news.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_living_whitelist.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction Stop
} catch {
    Write-CronLog "ERROR" "Falha load libs: $($_.Exception.Message)"
    exit 1
}


function Get-CoinexDailyCloses {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Market, [int]$Limit = 250)
    try {
        $url = "https://api.coinex.com/v2/spot/kline?market=$Market&period=1day&limit=$Limit"
        $r = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 15
        if (-not $r.data) { return @() }
        return [double[]]@($r.data | ForEach-Object { [double]$_.close })
    } catch {
        Write-CronLog "WARN" "Get-CoinexDailyCloses $Market falhou: $($_.Exception.Message)"
        return @()
    }
}


function Get-CoinexDailyCandles {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Market, [int]$Limit = 250)
    return (Get-CoinexCandles -Market $Market -Period "1day" -Limit $Limit)
}


function Get-CoinexCandles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string]$Period = "1day",      # 1day, 4hour, 1hour, 15min, etc
        [int]$Limit = 500
    )
    try {
        $url = "https://api.coinex.com/v2/spot/kline?market=$Market&period=$Period&limit=$Limit"
        $r = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 15
        if (-not $r.data) { return @() }
        return @($r.data | ForEach-Object {
            [PSCustomObject]@{
                close = [double]$_.close
                high  = [double]$_.high
                low   = [double]$_.low
            }
        })
    } catch {
        Write-CronLog "WARN" "Get-CoinexCandles $Market $Period falhou: $($_.Exception.Message)"
        return @()
    }
}


function Build-MetricsProvider {
    # Captura closes_btc uma vez por cycle (cache) -- regime macro usa daily
    $btcCloses = Get-CoinexDailyCloses -Market "BTCUSDT"
    # Captura referencias de funcao no closure (scope nao herda funcoes aninhadas em PS)
    $fnFetchClosesDaily   = Get-Command Get-CoinexDailyCloses
    $fnFetchCandles       = Get-Command Get-CoinexCandles
    $fnMetric             = Get-Command Get-PromotionMetrics
    $fnBacktest           = Get-Command Compute-PaperBacktest
    return {
        param([string]$Market)
        # Daily candles pra regime macro (asset)
        $dailyCandles = & $fnFetchCandles -Market $Market -Period "1day" -Limit 250
        if ($dailyCandles.Count -lt 50) {
            return $null   # historico insuficiente
        }
        $assetCloses = [double[]]@($dailyCandles | ForEach-Object { $_.close })

        # Phase 3.1: paper backtest em 4h (6x mais entries que daily)
        # Captura proxy de frequencia 50-100/ano por asset
        $h4Candles = & $fnFetchCandles -Market $Market -Period "4hour" -Limit 500
        $btSource = if ($h4Candles.Count -ge 250) { $h4Candles } else { $dailyCandles }

        $bt = & $fnBacktest -Candles $btSource
        $external = @{
            sharpe_30d = $bt.sharpe_30d
            n_trades   = $bt.n_trades
            max_dd     = $bt.max_dd
        }
        $m = & $fnMetric -Market $Market -AssetCloses $assetCloses -BtcCloses $btcCloses -External $external
        return $m
    }.GetNewClosure()
}


function Invoke-CronCycle {
    Write-CronLog "INFO" "Cycle iniciado (DryRun=$DryRun)"

    if (-not (Test-Path $pipelinePath)) {
        Write-CronLog "INFO" "Pipeline vazio (nenhum candidato registrado) -- exit"
        return
    }

    $provider = Build-MetricsProvider
    # 2026-05-20 PM: -EnforceGates opt-in via flag pra cobrir 13 gates antes do promote.
    # Resolve gap descoberto: Invoke-AllGates era orfa em prod (so chamada por Propose).
    # Wire so dispara se journal/ENFORCE_GATES_ENABLED.flag presente (opt-in conservador).
    $enforceFlag = Join-Path $journalDir "ENFORCE_GATES_ENABLED.flag"
    $tierAMarkets = @()
    try {
        $wlFiles = Get-ChildItem -Path $journalDir -Filter "per_asset_whitelist_*.json" -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($wlFiles) {
            $wl = Get-Content $wlFiles.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $tierAMarkets = @($wl.TIER_A_LIVE | ForEach-Object { $_.market })
        }
    } catch {}
    $cycleArgs = @{
        PipelinePath    = $pipelinePath
        DsrPath         = $dsrPath
        MetricsProvider = $provider
    }
    if (Test-Path $enforceFlag) {
        $cycleArgs.EnforceGates = $true
        $cycleArgs.CurrentTierAMarkets = $tierAMarkets
        $cycleArgs.VolumeUsd = 1000000   # placeholder; per-market via metricsProvider futuro
        Write-CronLog "INFO" "EnforceGates ATIVO (13 gates pre-promote) | TierA=$($tierAMarkets.Count)"
    }
    $result = Invoke-PromotionCycle @cycleArgs

    Write-CronLog "INFO" "Evaluated $($result.evaluated.Count) markets | Actions: $($result.actions.Count)"

    foreach ($action in $result.actions) {
        $msg = Format-TgPromotionPropose -Market $action.market -Proposal $action
        if ($DryRun) {
            Write-CronLog "DRY" "Would send TG: $($action.action) $($action.market)"
            Write-Host $msg -ForegroundColor Cyan
        } else {
            try {
                $sent = Send-TelegramAlert -Message $msg
                Write-CronLog "TG" "Sent $($action.action) $($action.market) -> ok=$sent"
            } catch {
                Write-CronLog "ERROR" "TG send failed: $($_.Exception.Message)"
            }
        }
    }

    $dsrTotal = Get-DsrTrials -Path $dsrPath
    Write-CronLog "INFO" "Cycle complete | DSR global trials=$dsrTotal"

    # Manual scan summary: se /scan disparou via Telegram, manda heartbeat resumido
    # mesmo sem actions (user fica no escuro se 0 events). Flag criada por Cmd-Scan.
    $manualFlag = Join-Path $journalDir "MANUAL_SCAN_REQUEST.flag"
    if (Test-Path $manualFlag) {
        try {
            $summary = @(
                "[OK] Scan manual completo",
                "Evaluated: $($result.evaluated.Count) | Actions: $($result.actions.Count)",
                "DSR trials: $dsrTotal"
            ) -join "`n"
            if (-not $DryRun) { Send-TelegramAlert -Message $summary | Out-Null }
            Remove-Item $manualFlag -Force -ErrorAction SilentlyContinue
        } catch {
            Write-CronLog "WARN" "Manual scan summary falhou: $($_.Exception.Message)"
        }
    }

    # ── Weekly Cost Report (NEW 2026-05-19, Domingo apenas) ─────────────────
    # Alerta Telegram com custo LLM semanal + projecao mensal.
    if ((Get-Date).DayOfWeek -eq 'Sunday') {
        Write-CronLog "INFO" "Weekly Cost Report (Domingo)..."
        try {
            . (Join-Path (Join-Path $projectRoot "agents") "lib_cost_tracker.ps1")
            $costMsg = Format-TgCostReport
            if (-not $DryRun) { Send-TelegramAlert -Message $costMsg | Out-Null }
            $s = Get-CostSummary
            Write-CronLog "INFO" "Cost semanal: `$$($s.week) ($($s.weekCalls) calls) projecao `$$($s.projectedMonthly)/mes"
        } catch {
            Write-CronLog "WARN" "Cost report fail: $_"
        }
    }

    # ── Halving Phase Change Alert (NEW 2026-05-19 v2) ──────────────────────
    # Detecta transicao de halving_phase + alerta Telegram + persiste estado.
    # Validado backtest 14y: strict_v3 phase-aware +18% total R vs strict_v2.
    Write-CronLog "INFO" "Halving Phase Check..."
    try {
        . (Join-Path (Join-Path $projectRoot "agents") "lib_market_context_engine.ps1")
        . (Join-Path (Join-Path $projectRoot "agents") "lib_halving_phase_alert.ps1")
        $sendBlock = $null
        if (-not $DryRun) {
            $sendBlock = { param($m) Send-TelegramAlert -Message $m }
        }
        $phaseResult = Invoke-HalvingPhaseCheck -SendTelegram $sendBlock
        if ($phaseResult.changed) {
            Write-CronLog "INFO" "Phase mudou: $($phaseResult.previous) -> $($phaseResult.current)"
        } else {
            Write-CronLog "INFO" "Phase estavel: $($phaseResult.current)"
        }
    } catch {
        Write-CronLog "WARN" "Halving phase check fail: $_"
    }

    # ── Tier A Drawdown Monitor (NEW 2026-05-19) ────────────────────────────
    # Detecta drawdowns >15% nos Tier A LIVE, se >25% (CRITICAL) re-valida automatico.
    Write-CronLog "INFO" "Tier A Drawdown Monitor..."
    try {
        $env:PYTHONIOENCODING = "utf-8"
        & python "backtest/tier_a_drawdown_monitor.py" 2>&1 | Out-Null
        $ddPath = Join-Path $journalDir ("tier_a_drawdown_" + (Get-Date -Format "yyyy_MM_dd") + ".json")
        if (Test-Path $ddPath) {
            $dd = Get-Content $ddPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Write-CronLog "INFO" "Drawdown: flagged=$($dd.flagged.Count) critical=$($dd.critical.Count)"
            if ($dd.flagged.Count -gt 0 -or $dd.critical.Count -gt 0) {
                $lines = @("📉 <b>Pullback Tier A LIVE</b>", "")
                $fallList = @()
                foreach ($d in $dd.drawdowns) {
                    if ($d.status -ne "OK") {
                        $tag = if ($d.status -eq "CRITICAL") { "🔴" } else { "🟡" }
                        $fallList += "$tag $($d.market) $($d.vs_peak_pct)% (vs peak 7d)"
                    }
                }
                $lines += $fallList
                if ($dd.critical.Count -gt 0) {
                    $lines += ""
                    $lines += "Critical re-validados: $($dd.critical -join ', ')"
                }
                if ($dd.replacement_candidates -and @($dd.replacement_candidates).Count -gt 0) {
                    $lines += ""
                    $lines += "<b>Subindo nao-testados:</b>"
                    foreach ($r in $dd.replacement_candidates | Select-Object -First 4) {
                        $voK = [math]::Round($r.vol/1e3, 0)
                        $lines += "$($r.market) +$($r.pct24)% (vol `$$voK"+"K, $($r.category))"
                    }
                    $lines += ""
                    $lines += "📌 Cron 02h amanha testa os melhores."
                }
                # NEW 2026-05-19: auto-demote proposal se 3+ dias consecutivos FLAG
                if ($dd.demote_candidates -and @($dd.demote_candidates).Count -gt 0) {
                    $lines += ""
                    $lines += "⚠️ <b>Demote proposto</b> (3+ dias FLAG):"
                    foreach ($m in $dd.demote_candidates) { $lines += "  - $m" }
                    $lines += "Responda: /demote MARKET ou /keep MARKET"
                }
                $msg = $lines -join "`n"
                if (-not $DryRun) { Send-TelegramAlert -Message $msg | Out-Null }
                Write-CronLog "TG" "Drawdown alert enviado"
            }
        }
    } catch {
        Write-CronLog "WARN" "Drawdown monitor falhou: $($_.Exception.Message)"
    }

    # ── Regime Change Monitor (BTC) -- antes de tudo, se mudou regime forca acoes ──
    Write-CronLog "INFO" "Regime Change Monitor BTC..."
    try {
        $env:PYTHONIOENCODING = "utf-8"
        & python "backtest/regime_change_monitor.py" 2>&1 | Out-Null
        $regimePath = Join-Path $journalDir "regime_state.json"
        if (Test-Path $regimePath) {
            $regState = Get-Content $regimePath -Raw -Encoding UTF8 | ConvertFrom-Json
            Write-CronLog "INFO" "Regime: $($regState.prev_regime) -> $($regState.current_regime) changed=$($regState.changed)"
            if ($regState.changed) {
                $msg = "🌊 <b>Regime BTC mudou</b>`n`n$($regState.prev_regime) → <b>$($regState.current_regime)</b>`n`n📌 Re-validation + discovery disparados automatico."
                if (-not $DryRun) { Send-TelegramAlert -Message $msg | Out-Null }
                Write-CronLog "TG" "Regime change alert enviado"
            }
        }
    } catch {
        Write-CronLog "WARN" "Regime monitor falhou: $($_.Exception.Message)"
    }

    # ── Weekly Revalidation: re-roda matrix em markets whitelist ────────────
    # 2026-05-19: cron passou pra DAILY mas revalidation eh pesado (3-5min/asset)
    # e markets nao degradam em 24h. Roda APENAS domingo.
    $isSunday = ((Get-Date).DayOfWeek -eq "Sunday")
    if (-not $isSunday) {
        Write-CronLog "INFO" "Weekly Revalidation SKIP (so domingo, hoje eh $((Get-Date).DayOfWeek))"
    } else {
    Write-CronLog "INFO" "Weekly Revalidation iniciando (domingo)..."
    try {
        $env:PYTHONIOENCODING = "utf-8"
        & python "backtest/weekly_revalidation.py" 2>&1 | Out-Null
        $rvPath = Join-Path $journalDir ("weekly_revalidation_" + (Get-Date -Format "yyyy_MM_dd") + ".json")
        if (Test-Path $rvPath) {
            $rv = Get-Content $rvPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Write-CronLog "INFO" "Revalidation: stable=$($rv.stable.Count) degraded=$($rv.degraded.Count) failing=$($rv.failing_gate.Count)"
            if ($rv.degraded.Count -gt 0 -or $rv.failing_gate.Count -gt 0) {
                $lines = @("⚠️ <b>Whitelist degradacao</b>", "")
                if ($rv.degraded.Count -gt 0) { $lines += "🟡 Sharpe >30% pior: $($rv.degraded -join ', ')" }
                if ($rv.failing_gate.Count -gt 0) { $lines += "🔴 Falha gate: $($rv.failing_gate -join ', ')" }
                $lines += ""
                $lines += "📌 Revisao manual -- decidir manter/demote."
                $msg = $lines -join "`n"
                if (-not $DryRun) { Send-TelegramAlert -Message $msg | Out-Null }
                Write-CronLog "TG" "Revalidation alert enviado"
            }
        }
    } catch {
        Write-CronLog "WARN" "Revalidation falhou: $($_.Exception.Message)"
    }
    }   # close if-Sunday else block

    # ── Weekly Discovery: goldilocks + cross_asset_matrix automatic ─────────
    Write-CronLog "INFO" "Weekly Discovery (goldilocks + matrix) iniciando..."
    try {
        $env:PYTHONIOENCODING = "utf-8"
        $pyOut = & python "backtest/weekly_discovery.py" 2>&1 | Out-String
        # Parsa output -- procura "VEREDICTO" section
        $tierA = @()
        $tierB = @()
        $jsonPath = Join-Path $journalDir ("weekly_discovery_" + (Get-Date -Format "yyyy_MM_dd") + ".json")
        if (Test-Path $jsonPath) {
            try {
                $disc = Get-Content $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $tierA = @($disc.tier_a_new)
                $tierB = @($disc.tier_b_new)
                Write-CronLog "INFO" "Discovery: TierA=$($tierA.Count) TierB=$($tierB.Count) TierC=$(@($disc.tier_c_new).Count)"
            } catch {
                Write-CronLog "WARN" "Falha parse weekly_discovery JSON: $($_.Exception.Message)"
            }
        }
        if ($tierA.Count -gt 0) {
            $msg = "🎯 <b>$($tierA -join ', ') entrou(aram) Tier A</b>`n`nValidado via backtest matrix (strict gate).`n`n📌 Update whitelist + observa. Setup formando = alerta separado."
            if (-not $DryRun) {
                Send-TelegramAlert -Message $msg | Out-Null
            }
            Write-CronLog "TG" "Tier A descobertos: $($tierA -join ', ')"
        }
    } catch {
        Write-CronLog "WARN" "Weekly Discovery falhou: $($_.Exception.Message)"
    }

    # ── Living Whitelist scan (auto-add BULL_STRONG + regime viz) ──────────
    if (Get-Command Invoke-LivingWhitelistScan -ErrorAction SilentlyContinue) {
        Write-CronLog "INFO" "Living Whitelist scan iniciando (BullStrongAutoAdd)..."
        try {
            $tickers = Get-CoinexAllTickers
            if ($tickers.Count -gt 0) {
                $lwProvider = Build-MetricsProvider
                $lw = Invoke-LivingWhitelistScan -Tickers $tickers -PipelinePath $pipelinePath `
                    -MetricsProvider $lwProvider -MinVolumeUsd 1000000 -TopN 30 -BullStrongAutoAdd

                Write-CronLog "INFO" "LW: scanned=$($lw.scanned_count) auto_added=$($lw.auto_added.Count) tracked=$($lw.already_tracked.Count) filtered=$($lw.filtered_out.Count)"

                # Visualizacao distribuicao regime
                $vizText = Format-RegimeDistribution -Counts $lw.regime_counts
                foreach ($line in ($vizText -split "`r?`n")) {
                    if ($line.Trim()) { Write-CronLog "VIZ" $line.TrimEnd() }
                }

                # Telegram com auto-added + regime viz
                # Envio APENAS se houve auto-added (silencia scans 0-novos pra reduzir ruido)
                if ($lw.auto_added.Count -gt 0) {
                    $lines = @("🆕 <b>$($lw.auto_added.Count) BULL_STRONG novo(s) em OBSERVATION:</b>")
                    $lines += $lw.auto_added -join ', '
                    $lines += ""
                    $lines += "<pre>$vizText</pre>"
                    $msg = $lines -join "`n"
                    if ($DryRun) { Write-CronLog "DRY" "Would send TG LW alert" }
                    else { Send-TelegramAlert -Message $msg | Out-Null }
                }
            }
        } catch {
            Write-CronLog "WARN" "Living Whitelist falhou: $($_.Exception.Message)"
        }
    }
}


function Get-CoinexAllTickers {
    try {
        $url = "https://api.coinex.com/v2/spot/ticker"
        $r = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 20
        if (-not $r.data) { return @() }
        return @($r.data | ForEach-Object {
            [PSCustomObject]@{
                market = $_.market
                value  = [double]$_.value
            }
        })
    } catch {
        Write-CronLog "WARN" "Get-CoinexAllTickers falhou: $($_.Exception.Message)"
        return @()
    }
}


# Main
if ($Loop) {
    while ($true) {
        Invoke-CronCycle
        Write-CronLog "INFO" "Sleep 7 dias ate proximo cycle"
        Start-Sleep -Seconds (7 * 24 * 3600)
    }
} else {
    Invoke-CronCycle
}
