# lib_position_risk_manager.ps1 - Gestao Dinamica de Risco de Posicoes
# Integra Position Management com agents para:
# 1. Trailing stops dinamicos
# 2. Ajuste de leverage por volatilidade
# 3. Add/Remove margin para evitar liquidacao
# 4. Gestao automatica de SL/TP

. (Join-Path $PSScriptRoot "lib_coinex.ps1")
. (Join-Path $PSScriptRoot "lib_coinex_position_management.ps1")

# ============================================================================
# Update-TrailingStop - Trailing stop dinamico baseado em ATR
# ============================================================================

function Update-TrailingStop {
    <#
    .SYNOPSIS
        Atualiza stop loss dinamicamente conforme preco sobe (trailing)
    
    .DESCRIPTION
        Usa ATR para calcular distancia do trailing stop
        Evita fees de cancelar + recriar ordem (usa ModifyPositionStopLoss)
    
    .PARAMETER Market
        Par de trading (ex: BTCUSDT)
    
    .PARAMETER AtrMultiplier
        Multiplicador do ATR para distancia do stop (default: 2.0)
    
    .PARAMETER MinProfitPct
        Lucro minimo antes de ativar trailing (default: 2%)
    
    .EXAMPLE
        Update-TrailingStop -Market "BTCUSDT" -AtrMultiplier 2.5 -MinProfitPct 3
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$false)]
        [double]$AtrMultiplier = 1.5,
        
        [Parameter(Mandatory=$false)]
        [double]$MinProfitPct = 1.0,
        
        [Parameter(Mandatory=$false)]
        [switch]$DryRun
    )
    
    try {
        # 1. Buscar posicao atual
        $allPositions = CoinEx-GetPendingPositions
        $positions = $allPositions | Where-Object { $_.market -eq $Market }
        if (-not $positions -or $positions.Count -eq 0) {
            Write-Host "  [TrailingStop] ${Market}: sem posicao aberta" -ForegroundColor DarkGray
            return [PSCustomObject]@{ success = $false; reason = "no_position" }
        }
        
        $pos = $positions[0]
        $side = $pos.side
        $entryPrice = [double]$pos.avg_entry_price
        
        # Buscar preco atual via ticker
        $ticker = CoinEx-Get "/v2/futures/ticker?market=$Market"
        if ($ticker.code -ne 0 -or -not $ticker.data) {
            Write-Host "  [Function] ${Market}: falha ao buscar ticker" -ForegroundColor Yellow
            return [PSCustomObject]@{ success = $false; reason = "ticker_error" }
        }
        $currentPrice = [double]$ticker.data.last
        $currentSL = if ($pos.stop_loss_price) { [double]$pos.stop_loss_price } else { 0 }
        
        # 2. Calcular lucro atual
        $profitPct = if ($side -eq "long") {
            (($currentPrice - $entryPrice) / $entryPrice) * 100
        } else {
            (($entryPrice - $currentPrice) / $entryPrice) * 100
        }
        
        # 3. Verificar se atingiu lucro minimo
        if ($profitPct -lt $MinProfitPct) {
            Write-Host "  [TrailingStop] ${Market}: lucro $([math]::Round($profitPct,2))% < minimo $MinProfitPct%" -ForegroundColor DarkGray
            return [PSCustomObject]@{ success = $false; reason = "profit_below_min"; profit_pct = $profitPct }
        }
        
        # 4. Calcular ATR (14 periodos, 1h)
        $candles = CoinEx-GetFuturesCandles -Market $Market -Period "1hour" -Limit 15
        if (-not $candles -or $candles.Count -lt 14) {
            Write-Host "  [TrailingStop] ${Market}: dados insuficientes para ATR" -ForegroundColor Yellow
            return [PSCustomObject]@{ success = $false; reason = "insufficient_data" }
        }
        
        $atrSum = 0
        for ($i = 1; $i -lt 15; $i++) {
            $high = [double]$candles[$i].high
            $low = [double]$candles[$i].low
            $prevClose = [double]$candles[$i-1].close
            
            $tr1 = $high - $low
            $tr2 = [math]::Abs($high - $prevClose)
            $tr3 = [math]::Abs($low - $prevClose)
            $tr = [math]::Max([math]::Max($tr1, $tr2), $tr3)
            $atrSum += $tr
        }
        $atr = $atrSum / 14
        
        # 5. Calcular novo stop loss
        $stopDistance = $atr * $AtrMultiplier
        $newSL = if ($side -eq "long") {
            $currentPrice - $stopDistance
        } else {
            $currentPrice + $stopDistance
        }
        
        # 6. Verificar se novo SL e melhor que atual
        $shouldUpdate = $false
        if ($side -eq "long") {
            $shouldUpdate = ($newSL -gt $currentSL) -and ($newSL -gt $entryPrice)
        } else {
            $shouldUpdate = ($newSL -lt $currentSL) -and ($newSL -lt $entryPrice)
        }
        
        if (-not $shouldUpdate) {
            Write-Host "  [TrailingStop] ${Market}: SL atual $currentSL ja e otimo (novo seria $([math]::Round($newSL,2)))" -ForegroundColor DarkGray
            return [PSCustomObject]@{
                success = $false
                reason = "current_sl_better"
                current_sl = $currentSL
                proposed_sl = $newSL
            }
        }
        
        # 7. Atualizar stop loss
        Write-Host "  [TrailingStop] ${Market}: atualizando SL $currentSL -> $([math]::Round($newSL,2)) (ATR=$([math]::Round($atr,2)) profit=$([math]::Round($profitPct,2))%)" -ForegroundColor Cyan
        
        if ($DryRun) {
            return [PSCustomObject]@{
                success = $true
                dry_run = $true
                market = $Market
                old_sl = $currentSL
                new_sl = $newSL
                atr = $atr
                profit_pct = $profitPct
            }
        }
        
        $result = CoinEx-ModifyPositionStopLoss -Market $Market -Price $newSL
        
        return [PSCustomObject]@{
            success = $result.success
            market = $Market
            old_sl = $currentSL
            new_sl = $newSL
            atr = $atr
            profit_pct = $profitPct
            api_response = $result
        }
    }
    catch {
        Write-Host "  [TrailingStop] ERRO ${Market}: $_" -ForegroundColor Red
        return [PSCustomObject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

# ============================================================================
# Adjust-LeverageByVolatility - Ajusta leverage baseado em volatilidade
# ============================================================================

function Adjust-LeverageByVolatility {
    <#
    .SYNOPSIS
        Ajusta leverage automaticamente baseado em volatilidade do mercado
    
    .DESCRIPTION
        Volatilidade alta = leverage baixo (protecao)
        Volatilidade baixa = leverage pode ser maior
        Usa ATR% (ATR / preco) como medida de volatilidade
    
    .PARAMETER Market
        Par de trading (ex: BTCUSDT)
    
    .PARAMETER MaxLeverage
        Leverage maximo permitido (default: 10x)
    
    .PARAMETER MinLeverage
        Leverage minimo (default: 3x)
    
    .EXAMPLE
        Adjust-LeverageByVolatility -Market "BTCUSDT" -MaxLeverage 10 -MinLeverage 3
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxLeverage = 10,
        
        [Parameter(Mandatory=$false)]
        [int]$MinLeverage = 3,
        
        [Parameter(Mandatory=$false)]
        [switch]$DryRun
    )
    
    try {
        # 1. Calcular ATR% (volatilidade normalizada)
        $candles = CoinEx-GetFuturesCandles -Market $Market -Period "1hour" -Limit 15
        if (-not $candles -or $candles.Count -lt 14) {
            Write-Host "  [LeverageAdjust] ${Market}: dados insuficientes" -ForegroundColor Yellow
            return [PSCustomObject]@{ success = $false; reason = "insufficient_data" }
        }
        
        $currentPrice = [double]$candles[-1].close
        
        $atrSum = 0
        for ($i = 1; $i -lt 15; $i++) {
            $high = [double]$candles[$i].high
            $low = [double]$candles[$i].low
            $prevClose = [double]$candles[$i-1].close
            
            $tr1 = $high - $low
            $tr2 = [math]::Abs($high - $prevClose)
            $tr3 = [math]::Abs($low - $prevClose)
            $tr = [math]::Max([math]::Max($tr1, $tr2), $tr3)
            $atrSum += $tr
        }
        $atr = $atrSum / 14
        $atrPct = ($atr / $currentPrice) * 100
        
        # 2. Mapear ATR% para leverage
        # ATR% < 1% = baixa volatilidade = leverage alto
        # ATR% > 5% = alta volatilidade = leverage baixo
        $targetLeverage = if ($atrPct -lt 1.0) {
            $MaxLeverage
        } elseif ($atrPct -gt 5.0) {
            $MinLeverage
        } else {
            # Interpolacao linear entre min e max
            $ratio = ($atrPct - 1.0) / 4.0  # 0 a 1
            [int]($MaxLeverage - ($ratio * ($MaxLeverage - $MinLeverage)))
        }
        
        # 3. Buscar leverage atual
        $allPositions = CoinEx-GetPendingPositions
        $positions = $allPositions | Where-Object { $_.market -eq $Market }
        $currentLeverage = if ($positions -and $positions.Count -gt 0) {
            [int]$positions[0].leverage
        } else {
            Write-Host "  [LeverageAdjust] ${Market}: sem posicao aberta, usando leverage default" -ForegroundColor DarkGray
            return [PSCustomObject]@{ success = $false; reason = "no_position" }
        }
        
        # 4. Verificar se precisa ajustar
        if ($currentLeverage -eq $targetLeverage) {
            Write-Host "  [LeverageAdjust] ${Market}: leverage $currentLeverage ja e otimo (ATR%=$([math]::Round($atrPct,2))%)" -ForegroundColor DarkGray
            return [PSCustomObject]@{
                success = $false
                reason = "leverage_already_optimal"
                current_leverage = $currentLeverage
                atr_pct = $atrPct
            }
        }
        
        Write-Host "  [LeverageAdjust] ${Market}: ajustando leverage $currentLeverage -> $targetLeverage (ATR%=$([math]::Round($atrPct,2))%)" -ForegroundColor Cyan
        
        if ($DryRun) {
            return [PSCustomObject]@{
                success = $true
                dry_run = $true
                market = $Market
                old_leverage = $currentLeverage
                new_leverage = $targetLeverage
                atr_pct = $atrPct
            }
        }
        
        # 5. Ajustar leverage
        $result = CoinEx-AdjustPositionLeverage -Market $Market -Leverage $targetLeverage -MarginMode "isolated"
        
        return [PSCustomObject]@{
            success = $result.success
            market = $Market
            old_leverage = $currentLeverage
            new_leverage = $targetLeverage
            atr_pct = $atrPct
            api_response = $result
        }
    }
    catch {
        Write-Host "  [LeverageAdjust] ERRO ${Market}: $_" -ForegroundColor Red
        return [PSCustomObject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

# ============================================================================
# Protect-FromLiquidation - Adiciona margin quando perto de liquidacao
# ============================================================================

function Protect-FromLiquidation {
    <#
    .SYNOPSIS
        Adiciona margin automaticamente quando posicao se aproxima de liquidacao
    
    .DESCRIPTION
        Monitora distancia ate liquidation price
        Se < threshold, adiciona margin para afastar liquidacao
    
    .PARAMETER Market
        Par de trading (ex: BTCUSDT)
    
    .PARAMETER ThresholdPct
        Distancia minima ate liquidacao antes de agir (default: 10%)
    
    .PARAMETER MarginToAdd
        Quantidade de USDT a adicionar (default: 50)
    
    .EXAMPLE
        Protect-FromLiquidation -Market "BTCUSDT" -ThresholdPct 15 -MarginToAdd 100
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$false)]
        [double]$ThresholdPct = 10.0,
        
        [Parameter(Mandatory=$false)]
        [double]$MarginToAdd = 50.0,
        
        [Parameter(Mandatory=$false)]
        [switch]$DryRun
    )
    
    try {
        # 1. Buscar posicao
        $allPositions = CoinEx-GetPendingPositions
        $positions = $allPositions | Where-Object { $_.market -eq $Market }
        if (-not $positions -or $positions.Count -eq 0) {
            Write-Host "  [LiqProtect] ${Market}: sem posicao aberta" -ForegroundColor DarkGray
            return [PSCustomObject]@{ success = $false; reason = "no_position" }
        }
        
        $pos = $positions[0]
        $side = $pos.side
        
        # Buscar preco atual via ticker
        $ticker = CoinEx-Get "/v2/futures/ticker?market=$Market"
        if ($ticker.code -ne 0 -or -not $ticker.data) {
            Write-Host "  [LiqProtect] ${Market}: falha ao buscar ticker" -ForegroundColor Yellow
            return [PSCustomObject]@{ success = $false; reason = "ticker_error" }
        }
        $currentPrice = [double]$ticker.data.last
        
        $liqPrice = [double]$pos.liq_price
        $margin = if ($pos.margin_avbl) { [double]$pos.margin_avbl } else { 0 }
        
        # Verificar se liq_price esta disponivel
        if ($liqPrice -eq 0 -or [double]::IsNaN($liqPrice)) {
            Write-Host "  [LiqProtect] ${Market}: liq_price nao disponivel (isolated margin ou cross margin)" -ForegroundColor DarkGray
            return [PSCustomObject]@{
                success = $false
                reason = "liq_price_unavailable"
                message = "Liquidation price not available from exchange"
            }
        }
        
        # 2. Calcular distancia ate liquidacao
        $distancePct = if ($side -eq "long") {
            (($currentPrice - $liqPrice) / $currentPrice) * 100
        } else {
            (($liqPrice - $currentPrice) / $currentPrice) * 100
        }
        
        # 3. Verificar se precisa proteger
        if ($distancePct -gt $ThresholdPct) {
            Write-Host "  [LiqProtect] ${Market}: distancia $([math]::Round($distancePct,2))% > threshold $ThresholdPct% (seguro)" -ForegroundColor DarkGray
            return [PSCustomObject]@{
                success = $false
                reason = "safe_distance"
                distance_pct = $distancePct
                liquidation_price = $liqPrice
            }
        }
        
        Write-Host "  [LiqProtect] ${Market}: ALERTA! Distancia $([math]::Round($distancePct,2))% < $ThresholdPct% - adicionando margin" -ForegroundColor Yellow
        
        if ($DryRun) {
            return [PSCustomObject]@{
                success = $true
                dry_run = $true
                market = $Market
                distance_pct = $distancePct
                margin_to_add = $MarginToAdd
                current_margin = $margin
            }
        }
        
        # 4. Adicionar margin
        $result = CoinEx-AdjustPositionMargin -Market $Market -Amount $MarginToAdd -Type "add"
        
        # 5. Enviar alerta
        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
            $msg = "âš ï¸ LIQUIDACAO PROXIMA: $Market`n" +
                   "Distancia: $([math]::Round($distancePct,2))%`n" +
                   "Liq Price: $liqPrice`n" +
                   "Margin adicionado: +$MarginToAdd USDT"
            Send-TelegramAlert -Message $msg | Out-Null
        }
        
        return [PSCustomObject]@{
            success = $result.success
            market = $Market
            distance_pct = $distancePct
            margin_added = $MarginToAdd
            old_margin = $margin
            new_margin = $margin + $MarginToAdd
            api_response = $result
        }
    }
    catch {
        Write-Host "  [LiqProtect] ERRO ${Market}: $_" -ForegroundColor Red
        return [PSCustomObject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

# ============================================================================
# Invoke-PositionRiskScan - Scan completo de todas as posicoes
# ============================================================================

function Invoke-PositionRiskScan {
    <#
    .SYNOPSIS
        Executa scan completo de gestao de risco em todas as posicoes abertas
    
    .DESCRIPTION
        Para cada posicao:
        1. Verifica trailing stop
        2. Ajusta leverage se necessario
        3. Protege de liquidacao
    
    .EXAMPLE
        Invoke-PositionRiskScan -DryRun
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$DryRun
    )
    
    try {
        Write-Host "`n=== POSITION RISK SCAN ===" -ForegroundColor Cyan
        
        # 1. Buscar todas as posicoes
        $allPositions = @(CoinEx-GetPendingPositions)
        if (-not $allPositions -or $allPositions.Count -eq 0) {
            Write-Host "  Nenhuma posicao aberta" -ForegroundColor DarkGray
            return [PSCustomObject]@{ success = $true; positions_scanned = 0 }
        }
        
        $posCount = $allPositions.Count
        Write-Host "  Posicoes abertas: $posCount" -ForegroundColor White
        
        $results = @()
        
        foreach ($pos in $allPositions) {
            $market = $pos.market
            Write-Host "`n  --- $market ---" -ForegroundColor Yellow
            
            # A. Trailing Stop
            $trailingResult = Update-TrailingStop -Market $market -DryRun:$DryRun
            
            # B. Leverage Adjustment
            $leverageResult = Adjust-LeverageByVolatility -Market $market -DryRun:$DryRun
            
            # C. Liquidation Protection
            $liqResult = Protect-FromLiquidation -Market $market -DryRun:$DryRun
            
            $results += [PSCustomObject]@{
                market = $market
                trailing_stop = $trailingResult
                leverage_adjust = $leverageResult
                liq_protection = $liqResult
            }
        }
        
        Write-Host "`n=== SCAN COMPLETO ===" -ForegroundColor Cyan
        return [PSCustomObject]@{
            success = $true
            positions_scanned = $allPositions.Count
            results = $results
        }
    }
    catch {
        Write-Host "  [RiskScan] ERRO: $_" -ForegroundColor Red
        return [PSCustomObject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}
