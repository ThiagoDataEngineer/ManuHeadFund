# collect_dashboard_data.ps1
# Coleta dados completos para dashboard enterprise
# 2026-05-24

. "$PSScriptRoot\..\agents\config.ps1"
. "$PSScriptRoot\..\agents\lib_coinex.ps1"
. "$PSScriptRoot\..\agents\lib_veto_feedback.ps1"
. "$PSScriptRoot\..\agents\lib_trailing_stop_adaptive.ps1"

function Get-TradingMetrics {
    param(
        [int] $Hours = 24
    )
    
    $tradesFile = "$PSScriptRoot\..\journal\trades.csv"
    if (-not (Test-Path $tradesFile)) {
        return @{
            trades_24h = 0
            trades_7d = 0
            trades_30d = 0
            win_rate = 0
            profit_factor = 0
            sharpe_ratio = 0
            max_drawdown = 0
            best_trade = 0
            worst_trade = 0
        }
    }
    
    $cutoff24h = (Get-Date).AddHours(-24)
    $cutoff7d = (Get-Date).AddDays(-7)
    $cutoff30d = (Get-Date).AddDays(-30)
    
    $allTrades = Import-Csv $tradesFile
    
    $trades24h = $allTrades | Where-Object { 
        $_.timestamp -and [datetime]::Parse($_.timestamp) -gt $cutoff24h 
    }
    $trades7d = $allTrades | Where-Object { 
        $_.timestamp -and [datetime]::Parse($_.timestamp) -gt $cutoff7d 
    }
    $trades30d = $allTrades | Where-Object { 
        $_.timestamp -and [datetime]::Parse($_.timestamp) -gt $cutoff30d 
    }
    
    # Calcular metricas
    $wins = ($trades30d | Where-Object { [double]$_.pnl_usd -gt 0 }).Count
    $total = $trades30d.Count
    $winRate = if ($total -gt 0) { ($wins / $total) * 100 } else { 0 }
    
    $grossProfit = ($trades30d | Where-Object { [double]$_.pnl_usd -gt 0 } | Measure-Object -Property pnl_usd -Sum).Sum
    $grossLoss = [Math]::Abs(($trades30d | Where-Object { [double]$_.pnl_usd -lt 0 } | Measure-Object -Property pnl_usd -Sum).Sum)
    $profitFactor = if ($grossLoss -gt 0) { $grossProfit / $grossLoss } else { 0 }
    
    $bestTrade = ($trades30d | Measure-Object -Property pnl_usd -Maximum).Maximum
    $worstTrade = ($trades30d | Measure-Object -Property pnl_usd -Minimum).Minimum
    
    return @{
        trades_24h = $trades24h.Count
        trades_7d = $trades7d.Count
        trades_30d = $trades30d.Count
        win_rate = [Math]::Round($winRate, 1)
        profit_factor = [Math]::Round($profitFactor, 2)
        sharpe_ratio = 0  # TODO: Implementar calculo Sharpe
        max_drawdown = 0  # TODO: Implementar calculo drawdown
        best_trade = [Math]::Round($bestTrade, 2)
        worst_trade = [Math]::Round($worstTrade, 2)
    }
}

function Get-MentorDecisions {
    $decisionsFile = "$PSScriptRoot\..\journal\decisions.csv"
    if (-not (Test-Path $decisionsFile)) {
        return @{
            total_24h = 0
            approval_rate = 0
            veto_rate = 0
            veto_reasons = @{}
            recent_decisions = @()
        }
    }
    
    $cutoff = (Get-Date).AddHours(-24)
    $decisions = Import-Csv $decisionsFile | Where-Object {
        $_.timestamp -and [datetime]::Parse($_.timestamp) -gt $cutoff
    }
    
    $total = $decisions.Count
    $approved = ($decisions | Where-Object { $_.mentor_decision -eq "APROVAR" }).Count
    $vetoed = ($decisions | Where-Object { $_.mentor_decision -like "VETAR*" }).Count
    
    $approvalRate = if ($total -gt 0) { ($approved / $total) * 100 } else { 0 }
    $vetoRate = if ($total -gt 0) { ($vetoed / $total) * 100 } else { 0 }
    
    # Contar razoes de veto
    $vetoReasons = @{}
    $decisions | Where-Object { $_.reason -match "FQS|beta|consensus|tier|MCE" } | ForEach-Object {
        $reason = switch -Regex ($_.reason) {
            "FQS" { "FQS Missing" }
            "beta" { "Beta Cap" }
            "consensus" { "Consensus Weak" }
            "tier.*C" { "Tier C" }
            "MCE" { "MCE Block" }
            default { "Other" }
        }
        if (-not $vetoReasons.ContainsKey($reason)) {
            $vetoReasons[$reason] = 0
        }
        $vetoReasons[$reason]++
    }
    
    # Ultimas 10 decisoes
    $recent = $decisions | Select-Object -Last 10 | ForEach-Object {
        @{
            market = $_.market
            decision = $_.mentor_decision
            reason = $_.reason.Substring(0, [Math]::Min(80, $_.reason.Length))
        }
    }
    
    return @{
        total_24h = $total
        approval_rate = [Math]::Round($approvalRate, 1)
        veto_rate = [Math]::Round($vetoRate, 1)
        veto_reasons = $vetoReasons
        recent_decisions = $recent
    }
}

function Get-MesaConsensus {
    $mesaFile = "$PSScriptRoot\..\journal\mesa_drones.jsonl"
    if (-not (Test-Path $mesaFile)) {
        return @{
            consensus = "UNKNOWN"
            score_avg = 0
            degraded_count = 0
            recent_analyses = @()
        }
    }
    
    # Ler ultimas 20 linhas
    $recent = Get-Content $mesaFile -Tail 20 | ForEach-Object {
        $_ | ConvertFrom-Json
    }
    
    if ($recent.Count -eq 0) {
        return @{
            consensus = "UNKNOWN"
            score_avg = 0
            degraded_count = 0
            recent_analyses = @()
        }
    }
    
    # Consensus mais recente
    $latest = $recent[-1]
    $consensus = $latest.consensus
    $scoreAvg = $latest.score_avg
    
    # Contar degraded
    $degradedCount = ($recent | Where-Object { $_.degraded -eq $true }).Count
    
    # Ultimas analises
    $analyses = $recent | Select-Object -Last 5 | ForEach-Object {
        @{
            market = $_.market
            consensus = $_.consensus
            score = $_.score_avg
            degraded = $_.degraded
        }
    }
    
    return @{
        consensus = $consensus
        score_avg = $scoreAvg
        degraded_count = $degradedCount
        recent_analyses = $analyses
    }
}

function Get-MarketRegime {
    # TODO: Implementar leitura de regime real
    # Por enquanto, retornar dados mockados baseados em config
    return @{
        regime = "BULL_STRONG"
        cycle = "MID"
        mce_score = 0.68
        tori_proximity = 12.5
    }
}

function Get-PromotionPipeline {
    $pipelineFile = "$PSScriptRoot\..\journal\promotion_pipeline.jsonl"
    if (-not (Test-Path $pipelineFile)) {
        return @{
            discovery = 0
            tier_a = 0
            tier_b = 0
            tier_c = 0
            gem_track = 0
            recent_promotions = @()
        }
    }
    
    $pipeline = Get-Content $pipelineFile | ForEach-Object {
        $_ | ConvertFrom-Json
    }
    
    $discovery = ($pipeline | Where-Object { $_.tier -eq "DISCOVERY" }).Count
    $tierA = ($pipeline | Where-Object { $_.tier -eq "A" }).Count
    $tierB = ($pipeline | Where-Object { $_.tier -eq "B" }).Count
    $tierC = ($pipeline | Where-Object { $_.tier -eq "C" }).Count
    $gemTrack = ($pipeline | Where-Object { $_.mode -like "*GEM*" }).Count
    
    return @{
        discovery = $discovery
        tier_a = $tierA
        tier_b = $tierB
        tier_c = $tierC
        gem_track = $gemTrack
        recent_promotions = @()
    }
}

function Get-FQSDistribution {
    # TODO: Implementar leitura de FQS registry
    return @{
        blue_chip = 5
        quality = 12
        speculative = 8
        avoid = 3
        missing = 15
    }
}

function Get-LLMCosts {
    $costFile = "$PSScriptRoot\..\journal\cost_tracker.jsonl"
    if (-not (Test-Path $costFile)) {
        return @{
            total_24h = 0
            total_7d = 0
            total_30d = 0
            anthropic = 0
            groq = 0
            tokens_24h = 0
            cost_per_decision = 0
        }
    }
    
    # TODO: Implementar leitura real de custos
    return @{
        total_24h = 2.45
        total_7d = 15.80
        total_30d = 63.20
        anthropic = 58.50
        groq = 4.70
        tokens_24h = 125000
        cost_per_decision = 0.08
    }
}

function Get-FeedbackLoopMetrics {
    $feedbacks = Get-PendingVetoFeedbacks -MaxAge 24
    
    $pending = ($feedbacks | Where-Object { $_.status -eq "pending" }).Count
    $completed = ($feedbacks | Where-Object { $_.status -eq "completed" }).Count
    $failed = ($feedbacks | Where-Object { $_.status -eq "failed" }).Count
    
    $resubmissionRate = if (($completed + $failed) -gt 0) {
        ($completed / ($completed + $failed)) * 100
    } else { 0 }
    
    return @{
        pending = $pending
        completed = $completed
        failed = $failed
        resubmission_rate = [Math]::Round($resubmissionRate, 1)
    }
}

function Get-TrailingStopMetrics {
    try {
        $positions = CoinEx-GetPendingPositions
        
        if (-not $positions -or $positions.Count -eq 0) {
            return @()
        }
        
        $metrics = @()
        foreach ($pos in $positions) {
            $market = $pos.market
            $currentPrice = [double]$pos.latest_price
            $entryPrice = [double]$pos.avg_entry_price
            $pnlPct = [double]$pos.unrealized_pnl_rate
            
            # Calcular threshold adaptativo
            $threshold = Get-AdaptiveTrailingThreshold -Market $market -CurrentPrice $currentPrice
            
            # Calcular distancia adaptativa
            $distance = Get-AdaptiveTrailingDistance -Market $market -CurrentPrice $currentPrice -EntryPrice $entryPrice -CurrentPNL $pnlPct
            
            $metrics += @{
                market = $market
                threshold_pct = $threshold.threshold_pct
                atr_pct = $threshold.atr_pct
                volatility_class = $threshold.volatility_class
                distance_pct = $distance.distance_pct
                momentum = $distance.momentum
                momentum_score = $distance.momentum_score
            }
        }
        
        return $metrics
    }
    catch {
        return @()
    }
}

function Get-PortfolioMetrics {
    try {
        $positions = CoinEx-GetPendingPositions
        
        if (-not $positions -or $positions.Count -eq 0) {
            return @{
                beta = 0
                concentration = @{}
                exposure_total = 0
                diversification = 0
            }
        }
        
        # Calcular concentracao por ativo
        $totalMargin = ($positions | Measure-Object -Property margin -Sum).Sum
        $concentration = @{}
        foreach ($pos in $positions) {
            $pct = ([double]$pos.margin / $totalMargin) * 100
            $concentration[$pos.market] = [Math]::Round($pct, 1)
        }
        
        return @{
            beta = 1.05  # TODO: Calcular beta real
            concentration = $concentration
            exposure_total = [Math]::Round($totalMargin, 2)
            diversification = $positions.Count
        }
    }
    catch {
        return @{
            beta = 0
            concentration = @{}
            exposure_total = 0
            diversification = 0
        }
    }
}

function Get-AlertsAndEvents {
    try {
        $positions = CoinEx-GetPendingPositions
        
        $alerts = @()
        
        # Verificar posicoes sem stop
        $noStop = $positions | Where-Object { [double]$_.stop_loss_price -eq 0 }
        if ($noStop) {
            $alerts += @{
                type = "CRITICAL"
                message = "$($noStop.Count) position(s) without stop loss"
                markets = ($noStop | ForEach-Object { $_.market }) -join ", "
            }
        }
        
        # TODO: Adicionar mais alertas (beta cap, concentration, etc)
        
        return $alerts
    }
    catch {
        return @()
    }
}

# Coletar todos os dados
$data = @{
    timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    trading_metrics = Get-TradingMetrics
    mentor_decisions = Get-MentorDecisions
    mesa_consensus = Get-MesaConsensus
    market_regime = Get-MarketRegime
    promotion_pipeline = Get-PromotionPipeline
    fqs_distribution = Get-FQSDistribution
    llm_costs = Get-LLMCosts
    feedback_loop = Get-FeedbackLoopMetrics
    trailing_stop = Get-TrailingStopMetrics
    portfolio_metrics = Get-PortfolioMetrics
    alerts = Get-AlertsAndEvents
}

# Retornar JSON
return ($data | ConvertTo-Json -Depth 10)
