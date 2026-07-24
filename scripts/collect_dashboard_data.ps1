# collect_dashboard_data.ps1 — Gerar dados do dashboard
# Executar a cada 5-10 minutos via Task Scheduler

$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$agentsDir = Join-Path $scriptDir "..\agents"
$dashboardDir = Join-Path $scriptDir "..\dashboard"
$logsDir = Join-Path $scriptDir "..\logs"

# Carregar config
. (Join-Path $agentsDir "config.ps1")    *>&1 | Out-Null
. (Join-Path $agentsDir "lib_coinex.ps1") *>&1 | Out-Null
. (Join-Path $agentsDir "lib_market_scenario.ps1") *>&1 | Out-Null

$logFile = Join-Path $logsDir "dashboard.log"

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] === DASHBOARD GENERATOR START ===" -ForegroundColor Cyan
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] === DASHBOARD GENERATOR START ===" | Out-File -FilePath $logFile -Append -Encoding utf8

try {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] OS: Windows" -ForegroundColor Cyan
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] OS: Windows" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Loading libraries..." -ForegroundColor Cyan
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Loading libraries..." | Out-File -FilePath $logFile -Append -Encoding utf8
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Libraries loaded" -ForegroundColor Green
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Libraries loaded" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] --- COLLECTING DATA ---" -ForegroundColor Cyan
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] --- COLLECTING DATA ---" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    # 2026-07-16 FIX: dados eram hardcoded ("# Simular coleta de dados" -- $positions=0,
    # $totalPnl=0, $totalMargin=0 sempre, e market_regime fixo em "BEAR_WEAK" mais
    # abaixo). Dashboard nunca refletiu a realidade desde a criacao -- mostrava
    # "0 posicoes, $0 PnL" mesmo com posicoes reais abertas com PnL negativo real,
    # confirmado divergindo de Trailing Stop Monitor + Position Risk Manager no
    # MESMO run. Fonte real: CoinEx-GetPendingPositions (mesma funcao que
    # lib_position_risk_manager.ps1 ja usa).
    $realPositions = @()
    try { $realPositions = @(CoinEx-GetPendingPositions) } catch { $realPositions = @() }

    $positions = $realPositions.Count
    $totalPnl = 0.0
    foreach ($rp in $realPositions) {
        if ($rp.PSObject.Properties['unrealized_pnl'] -and $null -ne $rp.unrealized_pnl) {
            $totalPnl += [double]$rp.unrealized_pnl
        }
    }
    $totalPnl = [math]::Round($totalPnl, 2)

    # Capital real (mesmas funcoes que gem_executor/FARO ja usam em producao).
    # "margin" nao confirmado no payload real de pending-position (sem credenciais
    # locais pra testar) -- usa capital total real em vez de inventar o campo.
    $realSpotCap = 0.0; $realFutCap = 0.0; $realTotalCap = 0.0
    try { $realSpotCap = [double](CoinEx-GetSpotCapitalUSDT) } catch {}
    try { $realFutCap = [double](CoinEx-GetFuturesCapitalUSDT) } catch {}
    try { $realTotalCap = [double](CoinEx-GetTotalCapitalUSDT) } catch {}
    $totalMargin = $realTotalCap

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Positions: $positions" -ForegroundColor Cyan
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Positions: $positions" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Total PNL: `$$totalPnl (0%)" -ForegroundColor Cyan
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Total PNL: `$$totalPnl (0%)" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Total Margin: `$$totalMargin" -ForegroundColor Cyan
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Total Margin: `$$totalMargin" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] --- GENERATING HTML ---" -ForegroundColor Cyan
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] --- GENERATING HTML ---" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    # Criar arquivo HTML simples
    $htmlFile = Join-Path $dashboardDir "index.html"
    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Coinex Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .status { padding: 10px; background: #f0f0f0; border-radius: 5px; }
        .ok { color: green; }
        .warning { color: orange; }
        .error { color: red; }
    </style>
</head>
<body>
    <h1>Coinex Trading Dashboard</h1>
    <div class="status">
        <p><strong>Last Updated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>Positions:</strong> <span class="ok">$positions</span></p>
        <p><strong>Total PNL:</strong> <span class="ok">`$$totalPnl</span></p>
        <p><strong>Total Capital:</strong> <span class="ok">`$$totalMargin</span></p>
        <p><strong>Status:</strong> <span class="ok">✅ Operational</span></p>
    </div>
</body>
</html>
"@
    
    $htmlContent | Out-File -FilePath $htmlFile -Encoding utf8 -Force
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Dashboard created: $htmlFile" -ForegroundColor Green
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Dashboard created: $htmlFile" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] === DASHBOARD GENERATOR END ===" -ForegroundColor Green
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] === DASHBOARD GENERATOR END ===" | Out-File -FilePath $logFile -Append -Encoding utf8

    # Coleta dados para retorno JSON (11 categorias)
    $tradeOutcomesPath = Join-Path $scriptDir "..\journal\trade_outcomes.jsonl"
    $trades = @()
    if (Test-Path $tradeOutcomesPath) {
        $trades = Get-Content $tradeOutcomesPath -EA SilentlyContinue | ForEach-Object { $_ | ConvertFrom-Json -EA SilentlyContinue } | Where-Object { $_ }
    }
    $now = Get-Date

    # 2026-07-24 FIX: schema real de trade_outcomes.jsonl usa created_at
    # (nao exit_date), pnl_realized (nao pnl_usd), e nao tem campo "win"
    # booleano -- deriva de pnl_realized > 0 (ver ConvertTo-SupabaseOutcome).
    $t24h   = [int](@($trades | Where-Object { $_.created_at -and ([datetime]$_.created_at) -ge $now.AddDays(-1)  }).Count)
    $t7d    = [int](@($trades | Where-Object { $_.created_at -and ([datetime]$_.created_at) -ge $now.AddDays(-7)  }).Count)
    $t30d   = [int](@($trades | Where-Object { $_.created_at -and ([datetime]$_.created_at) -ge $now.AddDays(-30) }).Count)
    $tpnl   = [double](@($trades) | Measure-Object -Property pnl_realized -Sum).Sum
    $wins   = @($trades | Where-Object { [double]$_.pnl_realized -gt 0 }).Count
    $wr     = if ($trades.Count -gt 0) { [math]::Round($wins / $trades.Count, 4) } else { 0.0 }

    # 2026-07-16 FIX: market_regime era hardcoded "BEAR_WEAK" sempre, independente
    # do mercado real -- fonte real ao vivo e Get-MarketScenario (mesma funcao que
    # gem_executor.ps1 usa pros gates de cenario).
    $realRegime = "UNKNOWN"; $realBias = "UNKNOWN"
    try {
        $scen = Get-MarketScenario
        if ($scen) {
            $realRegime = "$($scen.scenario)"
            $realBias = if ($scen.allow_long -and -not $scen.allow_short) { "BULLISH" }
                        elseif ($scen.allow_short -and -not $scen.allow_long) { "BEARISH" }
                        else { "NEUTRAL" }
        }
    } catch {}

    $dashData = [ordered]@{
        trading_metrics = [ordered]@{
            trades_24h  = $t24h
            trades_7d   = $t7d
            trades_30d  = $t30d
            total_pnl   = $tpnl
            win_rate    = [double]$wr
        }
        mentor_decisions  = [ordered]@{ count=0; last_decision="N/A"; avg_confidence=0 }
        mesa_consensus    = [ordered]@{ cycles_today=0; avg_score=0; top_market="N/A" }
        market_regime     = [ordered]@{ regime=$realRegime; phase="live"; bias=$realBias }
        promotion_pipeline= [ordered]@{ tier_a=0; tier_b=0; tier_c=0; tier_d=0 }
        fqs_distribution  = [ordered]@{ quality=0; acceptable=0; avoid=0; unknown=0 }
        llm_costs         = [ordered]@{ today_usd=0.0; month_usd=0.0; provider="groq" }
        feedback_loop     = [ordered]@{ signals_today=0; accuracy_7d=0.0 }
        trailing_stop     = [ordered]@{ active_positions=$positions; stops_updated_today=0 }
        portfolio_metrics = [ordered]@{ total_capital=$realTotalCap; futures_capital=$realFutCap; spot_capital=$realSpotCap; open_positions=$positions; unrealized_pnl_futures=$totalPnl }
        alerts            = @([ordered]@{ type="INFO"; message="Sistema operacional"; ts=$now.ToString("o") })
        generated_at      = $now.ToString("o")
    }

    # Salvar JSON em dashboard_data.json
    $dataFile = Join-Path $dashboardDir "dashboard_data.json"
    $dashData | ConvertTo-Json -Depth 5 | Out-File -FilePath $dataFile -Encoding utf8 -Force

    # Retornar JSON compacto no stdout (uma linha — compativel com $json | ConvertFrom-Json)
    $dashData | ConvertTo-Json -Depth 5 -Compress

} catch {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ERROR: $_" -ForegroundColor Red
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [ERROR] $_" | Out-File -FilePath $logFile -Append -Encoding utf8
}
