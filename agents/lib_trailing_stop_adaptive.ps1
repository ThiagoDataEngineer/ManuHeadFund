# lib_trailing_stop_adaptive.ps1
# Trailing Stop Adaptativo baseado em volatilidade e momentum
# 2026-05-24

. (Join-Path $PSScriptRoot "lib_coinex.ps1")

function Calculate-ATR {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array] $Candles,
        [int] $Period = 14
    )
    
    if ($Candles.Count -lt $Period) {
        return 0
    }
    
    # Calcular True Range para cada vela
    $trueRanges = @()
    for ($i = 1; $i -lt $Candles.Count; $i++) {
        $high = [double]$Candles[$i].high
        $low = [double]$Candles[$i].low
        $prevClose = [double]$Candles[$i-1].close
        
        $tr1 = $high - $low
        $tr2 = [Math]::Abs($high - $prevClose)
        $tr3 = [Math]::Abs($low - $prevClose)
        
        $trueRanges += [Math]::Max($tr1, [Math]::Max($tr2, $tr3))
    }
    
    # Calcular ATR (media dos ultimos N true ranges)
    $recentTR = $trueRanges | Select-Object -Last $Period
    $atr = ($recentTR | Measure-Object -Average).Average
    
    return $atr
}

function Get-VolatilityClass {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $ATRPercent
    )
    
    if ($ATRPercent -lt 2.0) { return "LOW_VOL" }
    if ($ATRPercent -lt 4.0) { return "MEDIUM_VOL" }
    if ($ATRPercent -lt 6.0) { return "HIGH_VOL" }
    return "EXTREME_VOL"
}

function Get-AdaptiveTrailingThreshold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $CurrentPrice
    )
    
    try {
        # Buscar candles de 1h (ultimas 50 velas = ~2 dias)
        $candles = CoinEx-GetFuturesCandles -market $Market -period "1hour" -limit 50
        
        if (-not $candles -or $candles.Count -lt 20) {
            # Fallback: usar threshold padrao
            return @{
                threshold_pct = 3.0
                atr_pct = 0
                volatility_class = "UNKNOWN"
                reasoning = "Insufficient data, using default threshold"
                fallback = $true
            }
        }
        
        # Calcular ATR(14)
        $atr = Calculate-ATR -Candles $candles -Period 14
        $atrPct = ($atr / $CurrentPrice) * 100
        
        # Determinar threshold baseado em volatilidade
        $threshold = switch ($atrPct) {
            { $_ -lt 2.0 }  { 2.0 }   # LOW_VOL
            { $_ -lt 4.0 }  { 3.0 }   # MEDIUM_VOL (padrao)
            { $_ -lt 6.0 }  { 5.0 }   # HIGH_VOL
            default         { 8.0 }   # EXTREME_VOL
        }
        
        $volClass = Get-VolatilityClass -ATRPercent $atrPct
        
        return @{
            threshold_pct = $threshold
            atr_pct = [Math]::Round($atrPct, 2)
            volatility_class = $volClass
            reasoning = "ATR=$([Math]::Round($atrPct,2))% â†’ $volClass â†’ threshold=$threshold%"
            fallback = $false
        }
    }
    catch {
        Write-Warning "Error calculating adaptive threshold for $Market : $_"
        return @{
            threshold_pct = 3.0
            atr_pct = 0
            volatility_class = "ERROR"
            reasoning = "Error: $($_.Exception.Message)"
            fallback = $true
        }
    }
}


function Get-MomentumScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market
    )
    
    try {
        # Buscar candles recentes
        $candles = CoinEx-GetFuturesCandles -market $Market -period "1hour" -limit 30
        
        if (-not $candles -or $candles.Count -lt 14) {
            return @{
                strength = "MODERATE"
                score = 50
                reasoning = "Insufficient data"
            }
        }
        
        # Calcular RSI simples (14 periodos)
        $gains = @()
        $losses = @()
        
        for ($i = 1; $i -lt [Math]::Min(15, $candles.Count); $i++) {
            $change = [double]$candles[$i].close - [double]$candles[$i-1].close
            if ($change -gt 0) {
                $gains += $change
                $losses += 0
            } else {
                $gains += 0
                $losses += [Math]::Abs($change)
            }
        }
        
        $avgGain = ($gains | Measure-Object -Average).Average
        $avgLoss = ($losses | Measure-Object -Average).Average
        
        if ($avgLoss -eq 0) {
            $rsi = 100
        } else {
            $rs = $avgGain / $avgLoss
            $rsi = 100 - (100 / (1 + $rs))
        }
        
        # Classificar momentum
        $strength = if ($rsi -gt 65) { "STRONG" }
                    elseif ($rsi -gt 45) { "MODERATE" }
                    else { "WEAK" }
        
        return @{
            strength = $strength
            score = [Math]::Round($rsi, 1)
            reasoning = "RSI=$([Math]::Round($rsi,1)) â†’ $strength"
        }
    }
    catch {
        return @{
            strength = "MODERATE"
            score = 50
            reasoning = "Error: $($_.Exception.Message)"
        }
    }
}

function Get-NearestSupport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $Price
    )
    
    try {
        # Buscar minimas das ultimas 20 velas de 1h
        $candles = CoinEx-GetFuturesCandles -market $Market -period "1hour" -limit 20
        
        if (-not $candles -or $candles.Count -lt 10) {
            # Fallback: 2% abaixo do preco atual
            return $Price * 0.98
        }
        
        $lows = $candles | ForEach-Object { [double]$_.low }
        $minLow = ($lows | Measure-Object -Minimum).Minimum
        
        # Suporte = minima das ultimas 20 velas
        return $minLow
    }
    catch {
        return $Price * 0.98
    }
}

function Get-AdaptiveTrailingDistance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $CurrentPrice,
        [Parameter(Mandatory)] [double] $EntryPrice,
        [Parameter(Mandatory)] [double] $CurrentPNL
    )
    
    try {
        # Buscar momentum
        $momentum = Get-MomentumScore -Market $Market
        
        # Buscar suporte tecnico
        $support = Get-NearestSupport -Market $Market -Price $CurrentPrice
        
        # Calcular distancia base por momentum
        $baseDistance = switch ($momentum.strength) {
            "STRONG"    { 1.5 }  # 1.5% abaixo (mais agressivo)
            "MODERATE"  { 2.0 }  # 2.0% (padrao)
            "WEAK"      { 2.5 }  # 2.5% (mais conservador)
            default     { 2.0 }
        }
        
        # Calcular distancia ate suporte
        $supportDistance = (($CurrentPrice - $support) / $CurrentPrice) * 100
        
        # Usar o menor (mais conservador)
        $finalDistance = [Math]::Min($baseDistance, [Math]::Max($supportDistance, 1.0))
        
        return @{
            distance_pct = [Math]::Round($finalDistance, 2)
            base_distance = $baseDistance
            support_distance = [Math]::Round($supportDistance, 2)
            support_price = [Math]::Round($support, 4)
            momentum = $momentum.strength
            momentum_score = $momentum.score
            reasoning = "Momentum=$($momentum.strength) (RSI=$($momentum.score)), Support=$([Math]::Round($supportDistance,2))%"
        }
    }
    catch {
        Write-Warning "Error calculating adaptive distance for $Market : $_"
        return @{
            distance_pct = 2.0
            base_distance = 2.0
            support_distance = 2.0
            support_price = $CurrentPrice * 0.98
            momentum = "MODERATE"
            momentum_score = 50
            reasoning = "Error: $($_.Exception.Message)"
        }
    }
}

# Export functions (comentado - nao e um modulo formal)
# Export-ModuleMember -Function @(
#     'Calculate-ATR',
#     'Get-VolatilityClass',
#     'Get-AdaptiveTrailingThreshold',
#     'Get-MomentumScore',
#     'Get-NearestSupport',
#     'Get-AdaptiveTrailingDistance'
# )
