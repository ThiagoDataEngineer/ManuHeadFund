# update_dashboard_json.ps1
# Atualiza dashboard/dashboard_data.json com dados reais do sistema
# Chamado pelo GitHub Actions e pela task local

$ErrorActionPreference = "Continue"
$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir   = Join-Path $projectRoot "agents"
$journalDir  = Join-Path $projectRoot "journal"
$dashDir     = Join-Path $projectRoot "dashboard"

# Carregar libs
. (Join-Path $agentsDir "config.ps1")
$configLocal = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocal) { . $configLocal }
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_dashboard_metrics.ps1")  # 2026-06-12: metricas reais (16 TDD)

$data = [ordered]@{
    timestamp         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    capital           = @{}
    positions         = @()
    trading_metrics   = @{}
    trailing_stop     = @()
    pnl_curve         = @()
    whale_signals     = @()
    market_regime     = @{}
    promotion_pipeline = @{}
    fqs_distribution  = @{}
    llm_costs         = @{}
    mentor_decisions  = @{}
    mesa_consensus    = @{}
    alerts            = @{}
    feedback_loop     = @{}
}

# ── Capital ──────────────────────────────────────────────────────────────────
try {
    $spotCap    = [math]::Round([double](CoinEx-GetSpotCapitalUSDT), 2)
    $futuresCap = [math]::Round([double](CoinEx-GetFuturesCapitalUSDT), 2)
    $data.capital = @{
        spot    = $spotCap
        futures = $futuresCap
        total   = [math]::Round($spotCap + $futuresCap, 2)
    }
} catch { $data.capital = @{ spot=0; futures=0; total=0; error=$_.Exception.Message } }

# ── Posições abertas ─────────────────────────────────────────────────────────
try {
    $positions = @(CoinEx-GetPendingPositions)
    $posData = @()
    foreach ($pos in $positions) {
        $entry  = [double]$pos.open_price
        $current = [double]$pos.mark_price
        $pnlPct = if ($entry -gt 0) { [math]::Round(($current - $entry) / $entry * 100 * [double]$pos.leverage, 2) } else { 0 }
        $posData += @{
            market    = $pos.market
            side      = $pos.side
            entry     = [math]::Round($entry, 6)
            current   = [math]::Round($current, 6)
            pnl_pct   = $pnlPct
            leverage  = $pos.leverage
            margin    = [math]::Round([double]$pos.margin, 2)
            stop_loss = $pos.stop_loss_price
        }
    }
    $data.positions = $posData
} catch { $data.positions = @() }

# ── Trailing stops (do journal) ───────────────────────────────────────────────
try {
    $trailFile = Join-Path $journalDir "trailing_positions.json"
    if (Test-Path $trailFile) {
        $trail = Get-Content $trailFile -Raw | ConvertFrom-Json
        $active = @($trail | Where-Object { $_.active -eq $true })
        $data.trailing_stop = $active | ForEach-Object {
            @{
                market       = $_.market
                side         = $_.side
                entry        = $_.entry
                stop_current = $_.stopCurrent
                peak         = $_.peak
                phase        = $_.phase
            }
        }
    }
} catch {}

# ── Regime de mercado ─────────────────────────────────────────────────────────
try {
    $regimeFile = Get-ChildItem $journalDir -Filter "regime_state*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($regimeFile) {
        $regime = Get-Content $regimeFile.FullName -Raw | ConvertFrom-Json
        $data.market_regime = @{
            regime         = $regime.regime
            bias           = $regime.bias
            phase          = $regime.phase
            updated_at     = $regime.updated_at
        }
    }
} catch {}

# ── Custos LLM (do claude_usage.csv) ─────────────────────────────────────────
try {
    $usageFile = Join-Path $journalDir "claude_usage.csv"
    if (Test-Path $usageFile) {
        $today = Get-Date -Format "yyyy-MM-dd"
        $lines = Get-Content $usageFile | Where-Object { $_ -match $today -and $_ -match "," }
        $total24h = 0.0; $anthropic = 0.0; $groq = 0.0; $calls = 0
        foreach ($line in $lines) {
            $p = $line.Trim() -split ","
            if ($p.Count -lt 6) { continue }
            $costStr = $p[5].Trim()
            if ($costStr -notmatch '^\d') { continue }
            $cost = [double]$costStr
            $total24h += $cost; $calls++
            if ($p[2] -match "anthropic") { $anthropic += $cost }
            elseif ($p[2] -match "groq") { $groq += $cost }
        }
        # 7d e 30d
        $lines7d  = Get-Content $usageFile | Where-Object { $_ -match "," }
        $total7d  = 0.0; $total30d = 0.0
        $cutoff7d  = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd")
        $cutoff30d = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd")
        foreach ($line in $lines7d) {
            $p = $line.Trim() -split ","
            if ($p.Count -lt 6) { continue }
            $ts = $p[0].Trim()
            $costStr = $p[5].Trim()
            if ($costStr -notmatch '^\d') { continue }
            $cost = [double]$costStr
            if ($ts -ge $cutoff30d) { $total30d += $cost }
            if ($ts -ge $cutoff7d)  { $total7d  += $cost }
        }
        $data.llm_costs = @{
            total_24h        = [math]::Round($total24h, 4)
            total_7d         = [math]::Round($total7d, 4)
            total_30d        = [math]::Round($total30d, 4)
            anthropic        = [math]::Round($anthropic, 4)
            groq             = [math]::Round($groq, 4)
            calls_24h        = $calls
            cost_per_decision = if ($calls -gt 0) { [math]::Round($total24h / $calls, 5) } else { 0 }
        }
    }
} catch {}

# ── Decisions (trading metrics) ───────────────────────────────────────────────
try {
    $decFile = Join-Path $journalDir "decisions.csv"
    if (Test-Path $decFile) {
        $today = Get-Date -Format "yyyy-MM-dd"
        $cut7d  = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd")
        $cut30d = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd")
        $allLines = Get-Content $decFile | Where-Object { $_ -match "," }
        $t24h = @($allLines | Where-Object { $_ -match $today -and $_ -match "EXECUTAR" }).Count
        $t7d  = @($allLines | Where-Object { $_ -match "EXECUTAR" } | Where-Object { ($_ -split ",")[0] -ge $cut7d }).Count
        $t30d = @($allLines | Where-Object { $_ -match "EXECUTAR" } | Where-Object { ($_ -split ",")[0] -ge $cut30d }).Count
        $data.trading_metrics = @{
            trades_24h   = $t24h
            trades_7d    = $t7d
            trades_30d   = $t30d
        }
        # Mentor decisions
        $vetoes = @($allLines | Where-Object { $_ -match $today -and $_ -match "ABORTAR" }).Count
        $approvals = $t24h
        $total = $vetoes + $approvals
        $data.mentor_decisions = @{
            total_24h    = $total
            approval_rate = if ($total -gt 0) { [math]::Round($approvals / $total * 100, 1) } else { 0 }
            veto_rate    = if ($total -gt 0) { [math]::Round($vetoes / $total * 100, 1) } else { 0 }
        }
    }
} catch {}

# ── Performance REAL + curva PnL (trade_outcomes.jsonl) ─────────────────────
# 2026-06-12: antes win_rate/profit_factor eram hardcoded 0. Agora lê o journal
# de outcomes (mesma fonte do learning engine / Kelly).
try {
    $outFile2 = Join-Path $journalDir "trade_outcomes.jsonl"
    if (Test-Path $outFile2) {
        $outcomes = @(Get-Content $outFile2 | Where-Object { $_.Trim() } | ForEach-Object {
            try { $_ | ConvertFrom-Json } catch { $null }
        } | Where-Object { $_ })

        $perf = Get-TradePerformanceMetrics -Outcomes $outcomes
        $data.trading_metrics.win_rate      = $perf.win_rate
        $data.trading_metrics.profit_factor = $perf.profit_factor
        $data.trading_metrics.total_pnl_usd = $perf.total_pnl_usd
        $data.trading_metrics.closed_trades = $perf.trades
        $data.trading_metrics.avg_win_usd   = $perf.avg_win_usd
        $data.trading_metrics.avg_loss_usd  = $perf.avg_loss_usd
        $data.trading_metrics.best_usd      = $perf.best_usd
        $data.trading_metrics.worst_usd     = $perf.worst_usd

        $data.pnl_curve = @(Get-PnlCurvePoints -Outcomes $outcomes)
    }
} catch { Write-Warning "trade_outcomes metrics: $_" }

# ── Whale signals (tape reading via deals, free) ─────────────────────────────
# Para cada mercado com posição trailing ativa: últimos 100 deals, trades >= $500
# em micro-caps = whale print. Spot primeiro, fallback futures.
try {
    $whaleMarkets = @($data.trailing_stop | ForEach-Object { "$($_.market)" } | Select-Object -Unique)
    foreach ($mkt in $whaleMarkets) {
        $deals = $null
        try {
            $r = CoinEx-Get "/v2/spot/deals?market=$mkt&limit=100"
            if ($r.code -eq 0 -and @($r.data).Count -gt 0) { $deals = @($r.data) }
        } catch {}
        if (-not $deals) {
            try {
                $r = CoinEx-Get "/v2/futures/deals?market=$mkt&limit=100"
                if ($r.code -eq 0) { $deals = @($r.data) }
            } catch {}
        }
        if (-not $deals) { continue }

        # threshold adaptativo (8x mediana do tape) — escala de BTC a micro-cap
        $w = Get-WhaleActivitySummary -Deals $deals
        $data.whale_signals += @{
            market        = $mkt
            signal        = $w.signal
            whale_buys    = $w.whale_buys
            whale_sells   = $w.whale_sells
            buy_usd       = $w.buy_usd
            sell_usd      = $w.sell_usd
            net_usd       = $w.net_usd
            largest_usd   = $w.largest_usd
            largest_side  = $w.largest_side
            threshold_usd = $w.threshold_usd
        }
    }
} catch { Write-Warning "whale signals: $_" }

# ── Whitelist Tier A/B ────────────────────────────────────────────────────────
try {
    $wlFile = Get-ChildItem $journalDir -Filter "per_asset_whitelist_*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($wlFile) {
        $wl = Get-Content $wlFile.FullName -Raw | ConvertFrom-Json
        $tierA = @($wl.TIER_A_LIVE)
        $tierB = @($wl.TIER_B_PAPER)
        $data.promotion_pipeline = @{
            tier_a            = $tierA.Count
            tier_b            = $tierB.Count
            tier_a_markets    = ($tierA | ForEach-Object { $_.market }) -join ", "
            tier_b_markets    = ($tierB | ForEach-Object { $_.market }) -join ", "
            discovery         = 0
            gem_track         = 0
            recent_promotions = @()
        }
    }
} catch {}

# ── FQS Distribution ─────────────────────────────────────────────────────────
try {
    $fqsFile = Get-ChildItem $journalDir -Filter "fqs_registry*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $fqsFile) { $fqsFile = Get-ChildItem $journalDir -Filter "*fqs*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
    if ($fqsFile) {
        $fqs = Get-Content $fqsFile.FullName -Raw | ConvertFrom-Json
        $dist = @{ blue_chip=0; quality=0; speculative=0; avoid=0; missing=0 }
        $fqs.PSObject.Properties | ForEach-Object {
            $score = $_.Value.score
            if ($null -eq $score) { $dist.missing++ }
            elseif ($score -ge 6) { $dist.blue_chip++ }
            elseif ($score -ge 4) { $dist.quality++ }
            elseif ($score -ge 2) { $dist.speculative++ }
            else { $dist.avoid++ }
        }
        $data.fqs_distribution = $dist
    }
} catch {}

# ── Salvar JSON e data.js (para uso no browser sem CORS) ─────────────────────
$outFile = Join-Path $dashDir "dashboard_data.json"
$jsonStr = $data | ConvertTo-Json -Depth 5
$jsonStr | Out-File $outFile -Encoding UTF8 -Force

# Escrever data.js com os dados reais (carregado pelo manu.html via <script src>)
$dataJs = "const MANU_DATA = $jsonStr;"
$dataJs | Out-File (Join-Path $dashDir "manu_data.js") -Encoding UTF8 -Force

Write-Host "Dashboard data atualizado: $outFile"
Write-Host "Capital: `$$($data.capital.total) | Posicoes: $($data.positions.Count) | Trades 24h: $($data.trading_metrics.trades_24h)"
