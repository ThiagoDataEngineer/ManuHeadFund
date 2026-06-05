# lib_performance_analyzer.ps1 - Analise Avancada de Performance de Trading
# Metricas: Sharpe Ratio, Max Drawdown, Win Streaks, Performance por Market/Horario
# TDD: Testes em tests/lib_performance_analyzer.Tests.ps1

. (Join-Path $PSScriptRoot "lib_coinex.ps1")
. (Join-Path $PSScriptRoot "lib_coinex_position_management.ps1")

# ============================================================================
# Calculate-SharpeRatio - Calcula Sharpe Ratio dos trades
# ============================================================================

function Calculate-SharpeRatio {
    <#
    .SYNOPSIS
        Calcula Sharpe Ratio (retorno ajustado por risco)
    
    .DESCRIPTION
        Sharpe Ratio = (Retorno Medio - Risk Free Rate) / Desvio Padrao
        Risk Free Rate default: 0.04 (4% anual = ~0.01% diario)
    
    .PARAMETER Trades
        Array de trades com campo 'realized_pnl'
    
    .PARAMETER RiskFreeRate
        Taxa livre de risco (default: 0.0001 = 0.01% diario)
    
    .EXAMPLE
        Calculate-SharpeRatio -Trades $trades
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [array]$Trades,
        
        [Parameter(Mandatory=$false)]
        [double]$RiskFreeRate = 0.0001
    )
    
    if ($Trades.Count -eq 0) {
        return [PSCustomObject]@{
            sharpe_ratio = 0
            avg_return = 0
            std_dev = 0
            trades_count = 0
        }
    }
    
    # Calcular retornos
    $returns = $Trades | ForEach-Object { [double]$_.realized_pnl }
    
    # Media e desvio padrao
    $avgReturn = ($returns | Measure-Object -Average).Average
    
    if ($returns.Count -lt 2) {
        return [PSCustomObject]@{
            sharpe_ratio = 0
            avg_return = $avgReturn
            std_dev = 0
            trades_count = $returns.Count
        }
    }
    
    # Calcular desvio padrao manualmente
    $variance = 0
    foreach ($r in $returns) {
        $variance += [math]::Pow($r - $avgReturn, 2)
    }
    $variance = $variance / ($returns.Count - 1)
    $stdDev = [math]::Sqrt($variance)
    
    # Sharpe Ratio
    $sharpeRatio = if ($stdDev -gt 0) {
        ($avgReturn - $RiskFreeRate) / $stdDev
    } else { 0 }
    
    return [PSCustomObject]@{
        sharpe_ratio = [math]::Round($sharpeRatio, 3)
        avg_return = [math]::Round($avgReturn, 2)
        std_dev = [math]::Round($stdDev, 2)
        trades_count = $returns.Count
    }
}

# ============================================================================
# Calculate-MaxDrawdown - Calcula Max Drawdown (maior queda do pico)
# ============================================================================

function Calculate-MaxDrawdown {
    <#
    .SYNOPSIS
        Calcula Max Drawdown (maior perda do pico ate o vale)
    
    .DESCRIPTION
        Max Drawdown = (Vale - Pico) / Pico
        Mede a maior queda percentual do capital
    
    .PARAMETER Trades
        Array de trades ordenados por data
    
    .EXAMPLE
        Calculate-MaxDrawdown -Trades $trades
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [array]$Trades
    )
    
    if ($Trades.Count -eq 0) {
        return [PSCustomObject]@{
            max_drawdown_pct = 0
            max_drawdown_usd = 0
            peak_equity = 0
            valley_equity = 0
        }
    }
    
    # Construir equity curve
    $equity = 0
    $peak = 0
    $maxDrawdown = 0
    $maxDrawdownUsd = 0
    $peakEquity = 0
    $valleyEquity = 0
    
    foreach ($trade in $Trades) {
        $equity += [double]$trade.realized_pnl
        
        # Atualizar pico
        if ($equity -gt $peak) {
            $peak = $equity
        }
        
        # Calcular drawdown atual
        $drawdown = $peak - $equity
        
        if ($drawdown -gt $maxDrawdownUsd) {
            $maxDrawdownUsd = $drawdown
            $peakEquity = $peak
            $valleyEquity = $equity
        }
    }
    
    # Calcular drawdown percentual
    $maxDrawdownPct = if ($peakEquity -gt 0) {
        ($maxDrawdownUsd / $peakEquity) * 100
    } else { 0 }
    
    return [PSCustomObject]@{
        max_drawdown_pct = [math]::Round($maxDrawdownPct, 2)
        max_drawdown_usd = [math]::Round($maxDrawdownUsd, 2)
        peak_equity = [math]::Round($peakEquity, 2)
        valley_equity = [math]::Round($valleyEquity, 2)
    }
}

# ============================================================================
# Calculate-WinStreaks - Calcula sequencias de wins/losses
# ============================================================================

function Calculate-WinStreaks {
    <#
    .SYNOPSIS
        Calcula maior sequencia de wins e losses consecutivos
    
    .PARAMETER Trades
        Array de trades ordenados por data
    
    .EXAMPLE
        Calculate-WinStreaks -Trades $trades
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [array]$Trades
    )
    
    if ($Trades.Count -eq 0) {
        return [PSCustomObject]@{
            max_win_streak = 0
            max_loss_streak = 0
            current_streak = 0
            current_streak_type = "none"
        }
    }
    
    $maxWinStreak = 0
    $maxLossStreak = 0
    $currentStreak = 0
    $currentType = "none"
    
    foreach ($trade in $Trades) {
        $pnl = [double]$trade.realized_pnl
        $isWin = $pnl -gt 0
        
        if ($currentType -eq "none") {
            $currentType = if ($isWin) { "win" } else { "loss" }
            $currentStreak = 1
        }
        elseif (($currentType -eq "win" -and $isWin) -or ($currentType -eq "loss" -and -not $isWin)) {
            $currentStreak++
        }
        else {
            # Streak quebrou
            if ($currentType -eq "win") {
                $maxWinStreak = [math]::Max($maxWinStreak, $currentStreak)
            } else {
                $maxLossStreak = [math]::Max($maxLossStreak, $currentStreak)
            }
            
            $currentType = if ($isWin) { "win" } else { "loss" }
            $currentStreak = 1
        }
    }
    
    # Atualizar com streak final
    if ($currentType -eq "win") {
        $maxWinStreak = [math]::Max($maxWinStreak, $currentStreak)
    } else {
        $maxLossStreak = [math]::Max($maxLossStreak, $currentStreak)
    }
    
    return [PSCustomObject]@{
        max_win_streak = $maxWinStreak
        max_loss_streak = $maxLossStreak
        current_streak = $currentStreak
        current_streak_type = $currentType
    }
}

# ============================================================================
# Analyze-PerformanceByMarket - Analisa performance por market
# ============================================================================

function Analyze-PerformanceByMarket {
    <#
    .SYNOPSIS
        Analisa performance separada por market
    
    .PARAMETER Trades
        Array de trades
    
    .EXAMPLE
        Analyze-PerformanceByMarket -Trades $trades
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [array]$Trades
    )
    
    $marketStats = @{}
    
    foreach ($trade in $Trades) {
        $market = $trade.market
        $pnl = [double]$trade.realized_pnl
        
        if (-not $marketStats.ContainsKey($market)) {
            $marketStats[$market] = @{
                trades = @()
                total_pnl = 0
                wins = 0
                losses = 0
            }
        }
        
        $marketStats[$market].trades += $trade
        $marketStats[$market].total_pnl += $pnl
        
        if ($pnl -gt 0) {
            $marketStats[$market].wins++
        } else {
            $marketStats[$market].losses++
        }
    }
    
    # Calcular metricas por market
    $results = @()
    foreach ($market in $marketStats.Keys) {
        $stats = $marketStats[$market]
        $totalTrades = $stats.trades.Count
        $winRate = if ($totalTrades -gt 0) {
            ($stats.wins / $totalTrades) * 100
        } else { 0 }
        
        $results += [PSCustomObject]@{
            market = $market
            trades = $totalTrades
            wins = $stats.wins
            losses = $stats.losses
            win_rate = [math]::Round($winRate, 1)
            total_pnl = [math]::Round($stats.total_pnl, 2)
            avg_pnl = [math]::Round($stats.total_pnl / $totalTrades, 2)
        }
    }
    
    return $results | Sort-Object total_pnl -Descending
}

# ============================================================================
# Analyze-PerformanceByHour - Analisa performance por hora do dia
# ============================================================================

function Analyze-PerformanceByHour {
    <#
    .SYNOPSIS
        Analisa performance por hora do dia (0-23)
    
    .PARAMETER Trades
        Array de trades com campo 'created_at' (timestamp)
    
    .EXAMPLE
        Analyze-PerformanceByHour -Trades $trades
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [array]$Trades
    )
    
    $hourStats = @{}
    
    foreach ($trade in $Trades) {
        # Converter timestamp para hora
        $timestamp = [long]$trade.created_at
        $date = [DateTimeOffset]::FromUnixTimeMilliseconds($timestamp).DateTime
        $hour = $date.Hour
        
        $pnl = [double]$trade.realized_pnl
        
        if (-not $hourStats.ContainsKey($hour)) {
            $hourStats[$hour] = @{
                trades = 0
                total_pnl = 0
                wins = 0
            }
        }
        
        $hourStats[$hour].trades++
        $hourStats[$hour].total_pnl += $pnl
        if ($pnl -gt 0) { $hourStats[$hour].wins++ }
    }
    
    # Calcular metricas por hora
    $results = @()
    for ($h = 0; $h -lt 24; $h++) {
        if ($hourStats.ContainsKey($h)) {
            $stats = $hourStats[$h]
            $winRate = if ($stats.trades -gt 0) {
                ($stats.wins / $stats.trades) * 100
            } else { 0 }
            
            $results += [PSCustomObject]@{
                hour = $h
                trades = $stats.trades
                wins = $stats.wins
                win_rate = [math]::Round($winRate, 1)
                total_pnl = [math]::Round($stats.total_pnl, 2)
                avg_pnl = [math]::Round($stats.total_pnl / $stats.trades, 2)
            }
        }
    }
    
    return $results | Sort-Object total_pnl -Descending
}

# ============================================================================
# Get-ComprehensivePerformanceReport - Relatorio completo de performance
# ============================================================================

function Get-ComprehensivePerformanceReport {
    <#
    .SYNOPSIS
        Gera relatorio completo de performance com todas as metricas
    
    .PARAMETER Limit
        Numero de trades a analisar (default: 100)
    
    .EXAMPLE
        Get-ComprehensivePerformanceReport -Limit 200
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [int]$Limit = 100
    )
    
    try {
        # Buscar trades
        $history = CoinEx-GetFinishedPositions -Limit $Limit
        if (-not $history.success) {
            throw "Falha ao buscar historico de trades"
        }
        
        $trades = $history.positions
        
        if ($trades.Count -eq 0) {
            throw "Nenhum trade encontrado"
        }
        
        # Calcular todas as metricas
        $sharpe = Calculate-SharpeRatio -Trades $trades
        $drawdown = Calculate-MaxDrawdown -Trades $trades
        $streaks = Calculate-WinStreaks -Trades $trades
        $byMarket = Analyze-PerformanceByMarket -Trades $trades
        $byHour = Analyze-PerformanceByHour -Trades $trades
        
        # Metricas basicas
        $totalPnl = ($trades | ForEach-Object { [double]$_.realized_pnl } | Measure-Object -Sum).Sum
        $wins = ($trades | Where-Object { [double]$_.realized_pnl -gt 0 }).Count
        $losses = $trades.Count - $wins
        $winRate = if ($trades.Count -gt 0) { ($wins / $trades.Count) * 100 } else { 0 }
        
        return [PSCustomObject]@{
            success = $true
            timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            trades_analyzed = $trades.Count
            
            # Metricas basicas
            total_pnl = [math]::Round($totalPnl, 2)
            wins = $wins
            losses = $losses
            win_rate = [math]::Round($winRate, 1)
            
            # Metricas avancadas
            sharpe_ratio = $sharpe.sharpe_ratio
            avg_return = $sharpe.avg_return
            std_dev = $sharpe.std_dev
            
            max_drawdown_pct = $drawdown.max_drawdown_pct
            max_drawdown_usd = $drawdown.max_drawdown_usd
            
            max_win_streak = $streaks.max_win_streak
            max_loss_streak = $streaks.max_loss_streak
            current_streak = $streaks.current_streak
            current_streak_type = $streaks.current_streak_type
            
            # Analises detalhadas
            by_market = $byMarket
            by_hour = $byHour
        }
    }
    catch {
        return [PSCustomObject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}
