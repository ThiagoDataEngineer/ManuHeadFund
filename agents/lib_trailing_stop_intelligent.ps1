# lib_trailing_stop_intelligent.ps1
# Trailing Stop Inteligente baseado em conhecimento
# Implementado com TDD: tests\lib_trailing_stop_intelligent.Tests.ps1
# 2026-05-24
#
# FUNCIONALIDADES:
# 1. Calcular ATR (Average True Range) para volatilidade
# 2. Detectar suportes/resistências em candles
# 3. Ajustar trailing % baseado em contexto:
#    - ATR × multiplicador
#    - Distância de suporte
#    - Alavancagem (50x = 1-2%, 5x = 3-5%)
#    - Tempo desde entrada
# 4. Ativar trailing após +3% de lucro
# 5. Nunca mover stop para baixo (apenas para cima)

# ============================================================================
# Calculate-ATR - Average True Range
# ============================================================================

function Calculate-ATR {
    <#
    .SYNOPSIS
        Calcula ATR (Average True Range) para medir volatilidade
    
    .PARAMETER Candles
        Array de candles (PSCustomObject com high, low, close)
    
    .PARAMETER Period
        Periodo do ATR (default: 14)
    
    .OUTPUTS
        Double - ATR value
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Candles,
        
        [Parameter(Mandatory=$false)]
        [int]$Period = 14
    )
    
    if ($Candles.Count -lt $Period + 1) {
        throw "Insufficient candles for ATR calculation (need at least $($Period + 1))"
    }
    
    # Calcular True Range para cada candle
    $trueRanges = @()
    
    for ($i = 1; $i -lt $Candles.Count; $i++) {
        $current = $Candles[$i]
        $previous = $Candles[$i - 1]
        
        $highLow = $current.high - $current.low
        $highClose = [Math]::Abs($current.high - $previous.close)
        $lowClose = [Math]::Abs($current.low - $previous.close)
        
        $tr = [Math]::Max($highLow, [Math]::Max($highClose, $lowClose))
        $trueRanges += $tr
    }
    
    # ATR = média dos últimos N true ranges
    $atr = ($trueRanges | Select-Object -Last $Period | Measure-Object -Average).Average
    
    return [Math]::Round($atr, 8)
}

# ============================================================================
# Find-SupportLevels - Detectar suportes em candles
# ============================================================================

function Find-SupportLevels {
    <#
    .SYNOPSIS
        Detecta níveis de suporte baseado em mínimas locais
    
    .PARAMETER Candles
        Array de candles
    
    .PARAMETER LookbackPeriod
        Período de lookback (default: 20)
    
    .PARAMETER Tolerance
        Tolerância para agrupar suportes próximos (default: 0.5%)
    
    .OUTPUTS
        Array de níveis de suporte (ordenados do mais próximo ao preço atual)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Candles,
        
        [Parameter(Mandatory=$false)]
        [int]$LookbackPeriod = 20,
        
        [Parameter(Mandatory=$false)]
        [double]$Tolerance = 0.005
    )
    
    if ($Candles.Count -lt $LookbackPeriod) {
        return @()
    }
    
    $recentCandles = $Candles | Select-Object -Last $LookbackPeriod
    $currentPrice = $Candles[-1].close
    
    # Encontrar mínimas locais (candle com low menor que vizinhos)
    $supports = @()
    
    for ($i = 1; $i -lt ($recentCandles.Count - 1); $i++) {
        $current = $recentCandles[$i]
        $prev = $recentCandles[$i - 1]
        $next = $recentCandles[$i + 1]
        
        if ($current.low -lt $prev.low -and $current.low -lt $next.low) {
            $supports += $current.low
        }
    }
    
    # Agrupar suportes próximos (dentro da tolerância)
    $groupedSupports = @()
    $supports = $supports | Sort-Object
    
    foreach ($support in $supports) {
        $found = $false
        
        for ($i = 0; $i -lt $groupedSupports.Count; $i++) {
            $diff = [Math]::Abs($support - $groupedSupports[$i]) / $groupedSupports[$i]
            
            if ($diff -le $Tolerance) {
                # Atualizar com média
                $groupedSupports[$i] = ($groupedSupports[$i] + $support) / 2
                $found = $true
                break
            }
        }
        
        if (-not $found) {
            $groupedSupports += $support
        }
    }
    
    # Retornar apenas suportes abaixo do preço atual, ordenados (mais próximo primeiro)
    return $groupedSupports | Where-Object { $_ -lt $currentPrice } | Sort-Object -Descending
}

# ============================================================================
# Calculate-TrailingStopPrice - Calcular novo stop inteligente
# ============================================================================

function Calculate-TrailingStopPrice {
    <#
    .SYNOPSIS
        Calcula novo preço de stop loss baseado em contexto inteligente
    
    .PARAMETER Position
        Objeto de posição (com side, open_price, latest_price, leverage, etc.)
    
    .PARAMETER Candles
        Array de candles recentes
    
    .PARAMETER CurrentStopLoss
        Stop loss atual
    
    .PARAMETER MinProfitPctToActivate
        Lucro mínimo % para ativar trailing (default: 3%)
    
    .OUTPUTS
        PSCustomObject com new_stop_price, reason, should_update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Position,
        
        [Parameter(Mandatory=$true)]
        [array]$Candles,
        
        [Parameter(Mandatory=$true)]
        [double]$CurrentStopLoss,
        
        [Parameter(Mandatory=$false)]
        [double]$MinProfitPctToActivate = 3.0
    )
    
    # Campos corretos da API CoinEx v2
    $entryPrice = [double]$Position.avg_entry_price
    $leverage = [int]$Position.leverage
    $side = $Position.side
    
    # Buscar preço atual do ticker (latest_price não está na posição)
    $ticker = CoinEx-GetTicker -market $Position.market
    $currentPrice = [double]$ticker.last
    
    # Calcular PNL %
    $pnlPct = if ($side -eq "long") {
        (($currentPrice - $entryPrice) / $entryPrice) * 100
    } else {
        (($entryPrice - $currentPrice) / $entryPrice) * 100
    }
    
    # Verificar se atingiu lucro mínimo para ativar trailing
    if ($pnlPct -lt $MinProfitPctToActivate) {
        return [PSCustomObject]@{
            new_stop_price = $CurrentStopLoss
            reason = "Profit $([Math]::Round($pnlPct, 2))% below activation threshold ($MinProfitPctToActivate%)"
            should_update = $false
            pnl_pct = $pnlPct
        }
    }
    
    # Calcular ATR
    $atr = Calculate-ATR -Candles $Candles -Period 14
    $atrPct = ($atr / $currentPrice) * 100
    
    # Encontrar suportes (para LONG) ou resistências (para SHORT)
    $supports = Find-SupportLevels -Candles $Candles -LookbackPeriod 20
    
    # Determinar trailing % baseado em contexto
    $trailingPct = 0
    $reason = ""
    
    # Fator 1: Alavancagem (maior leverage = trailing mais apertado)
    if ($leverage -ge 50) {
        $trailingPct = 1.5  # 1.5% para 50x
        $reason = "High leverage (${leverage}x)"
    } elseif ($leverage -ge 20) {
        $trailingPct = 2.5  # 2.5% para 20x+
        $reason = "Medium-high leverage (${leverage}x)"
    } elseif ($leverage -ge 10) {
        $trailingPct = 3.5  # 3.5% para 10x+
        $reason = "Medium leverage (${leverage}x)"
    } else {
        $trailingPct = 4.5  # 4.5% para 5x ou menos
        $reason = "Low leverage (${leverage}x)"
    }
    
    # Fator 2: ATR (alta volatilidade = trailing mais largo)
    if ($atrPct -gt 3.0) {
        $trailingPct += 1.0
        $reason += ", high volatility (ATR $([Math]::Round($atrPct, 2))%)"
    } elseif ($atrPct -lt 1.0) {
        $trailingPct -= 0.5
        $reason += ", low volatility (ATR $([Math]::Round($atrPct, 2))%)"
    }
    
    # Fator 3: Suporte próximo (ajustar stop para logo acima do suporte)
    $nearestSupport = $null
    if ($supports.Count -gt 0) {
        $nearestSupport = $supports[0]
        $distanceToSupport = (($currentPrice - $nearestSupport) / $currentPrice) * 100
        
        # Se suporte está muito próximo (< 2%), usar suporte + 0.5%
        if ($distanceToSupport -lt 2.0) {
            $trailingPct = [Math]::Min($trailingPct, $distanceToSupport + 0.5)
            $reason += ", near support at `$$([Math]::Round($nearestSupport, 4))"
        }
    }
    
    # Calcular novo stop
    $newStopPrice = if ($side -eq "long") {
        $currentPrice * (1 - ($trailingPct / 100))
    } else {
        $currentPrice * (1 + ($trailingPct / 100))
    }
    
    # REGRA CRÍTICA: Nunca mover stop para baixo (LONG) ou para cima (SHORT)
    $shouldUpdate = $false
    
    if ($side -eq "long") {
        if ($newStopPrice -gt $CurrentStopLoss) {
            $shouldUpdate = $true
        } else {
            $newStopPrice = $CurrentStopLoss
            $reason = "Stop not moved (would move down)"
        }
    } else {
        if ($newStopPrice -lt $CurrentStopLoss) {
            $shouldUpdate = $true
        } else {
            $newStopPrice = $CurrentStopLoss
            $reason = "Stop not moved (would move up)"
        }
    }
    
    return [PSCustomObject]@{
        new_stop_price = [Math]::Round($newStopPrice, 4)
        trailing_pct = [Math]::Round($trailingPct, 2)
        reason = $reason
        should_update = $shouldUpdate
        pnl_pct = [Math]::Round($pnlPct, 2)
        atr = [Math]::Round($atr, 8)
        atr_pct = [Math]::Round($atrPct, 2)
        nearest_support = if ($nearestSupport) { [Math]::Round($nearestSupport, 4) } else { $null }
    }
}

# ============================================================================
# Update-PositionTrailingStop - Atualizar stop de uma posição
# ============================================================================

function Update-PositionTrailingStop {
    <#
    .SYNOPSIS
        Atualiza trailing stop de uma posição se necessário
    
    .PARAMETER Market
        Par de trading (ex: BTCUSDT)
    
    .PARAMETER DryRun
        Se true, apenas simula (não executa)
    
    .OUTPUTS
        PSCustomObject com resultado da operação
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$false)]
        [bool]$DryRun = $false
    )
    
    try {
        # Buscar posição
        $positions = CoinEx-GetPendingPositions -Market $Market
        
        if ($positions.Count -eq 0) {
            return [PSCustomObject]@{
                success = $false
                market = $Market
                error = "Position not found"
            }
        }
        
        $position = $positions[0]
        $currentStopLoss = [double]$position.stop_loss_price
        
        if ($currentStopLoss -eq 0) {
            return [PSCustomObject]@{
                success = $false
                market = $Market
                error = "No stop loss configured"
            }
        }
        
        # Buscar candles
        $candles = CoinEx-GetFuturesCandles -market $Market -period "15min" -limit 50
        
        if ($candles.Count -lt 20) {
            return [PSCustomObject]@{
                success = $false
                market = $Market
                error = "Insufficient candle data"
            }
        }
        
        # Calcular novo stop
        $calculation = Calculate-TrailingStopPrice `
            -Position $position `
            -Candles $candles `
            -CurrentStopLoss $currentStopLoss
        
        if (-not $calculation.should_update) {
            return [PSCustomObject]@{
                success = $true
                market = $Market
                action = "no_update"
                reason = $calculation.reason
                current_stop = $currentStopLoss
                pnl_pct = $calculation.pnl_pct
            }
        }
        
        # Executar update (se não for dry run)
        if (-not $DryRun) {
            $result = CoinEx-ModifyPositionStopLoss `
                -Market $Market `
                -Price $calculation.new_stop_price
            
            if (-not $result.success) {
                return [PSCustomObject]@{
                    success = $false
                    market = $Market
                    error = "API error: $($result.error_msg)"
                }
            }
        }
        
        return [PSCustomObject]@{
            success = $true
            market = $Market
            action = if ($DryRun) { "simulated" } else { "updated" }
            old_stop = $currentStopLoss
            new_stop = $calculation.new_stop_price
            trailing_pct = $calculation.trailing_pct
            reason = $calculation.reason
            pnl_pct = $calculation.pnl_pct
            atr_pct = $calculation.atr_pct
            nearest_support = $calculation.nearest_support
        }
    }
    catch {
        return [PSCustomObject]@{
            success = $false
            market = $Market
            error = $_.Exception.Message
        }
    }
}

# ============================================================================
# Update-AllTrailingStops - Atualizar todas as posições
# ============================================================================

function Update-AllTrailingStops {
    <#
    .SYNOPSIS
        Atualiza trailing stops de todas as posições abertas
    
    .PARAMETER DryRun
        Se true, apenas simula (não executa)
    
    .OUTPUTS
        Array de resultados por posição
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [bool]$DryRun = $false
    )
    
    try {
        # Buscar todas as posições
        $positions = CoinEx-GetPendingPositions
        
        if ($positions.Count -eq 0) {
            return @([PSCustomObject]@{
                success = $true
                message = "No open positions"
                results = @()
            })
        }
        
        $results = @()
        
        foreach ($pos in $positions) {
            $market = $pos.market
            
            Write-Verbose "Processing $market..."
            
            $result = Update-PositionTrailingStop -Market $market -DryRun $DryRun
            $results += $result
            
            # Rate limiting: aguardar 200ms entre chamadas
            Start-Sleep -Milliseconds 200
        }
        
        return [PSCustomObject]@{
            success = $true
            total_positions = $positions.Count
            updated = ($results | Where-Object { $_.action -eq "updated" }).Count
            simulated = ($results | Where-Object { $_.action -eq "simulated" }).Count
            no_update = ($results | Where-Object { $_.action -eq "no_update" }).Count
            errors = ($results | Where-Object { -not $_.success }).Count
            results = $results
        }
    }
    catch {
        return [PSCustomObject]@{
            success = $false
            error = $_.Exception.Message
            results = @()
        }
    }
}

# ============================================================================
# Funcoes exportadas
# ============================================================================
# Calculate-ATR
# Find-SupportLevels
# Calculate-TrailingStopPrice
# Update-PositionTrailingStop
# Update-AllTrailingStops
