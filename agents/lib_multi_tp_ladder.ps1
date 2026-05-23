# lib_multi_tp_ladder.ps1 - Multi-TP Escalonado (Ladder Exits)
# Implementa saídas escalonadas para maximizar lucros
#
# ESTRATEGIA:
# - TP1 (25%): Recupera capital + pequeno lucro
# - TP2 (35%): Lucro moderado
# - TP3 (25%): Lucro alto
# - TP4 (15%): Runner (deixa correr)
#
# STOP LOSS DINAMICO:
# - Após TP1: Move SL para breakeven
# - Após TP2: Move SL para TP1
# - Após TP3: Move SL para TP2

. "$PSScriptRoot\lib_coinex.ps1"
. "$PSScriptRoot\lib_coinex_position_management.ps1"

# ============================================================================
# Get-LadderExitLevels - Calcula níveis de TP escalonados
# ============================================================================

function Get-LadderExitLevels {
    <#
    .SYNOPSIS
        Calcula níveis de TP escalonados baseados em ATR
    
    .DESCRIPTION
        Cria 4 níveis de TP com distribuição otimizada:
        - TP1: 2x ATR (25% da posição)
        - TP2: 4x ATR (35% da posição)
        - TP3: 6x ATR (25% da posição)
        - TP4: 10x ATR (15% runner)
    
    .PARAMETER EntryPrice
        Preço de entrada
    
    .PARAMETER Side
        Lado da posição (long/short)
    
    .PARAMETER AtrValue
        Valor do ATR
    
    .PARAMETER TotalQty
        Quantidade total da posição
    
    .EXAMPLE
        Get-LadderExitLevels -EntryPrice 100000 -Side "long" -AtrValue 800 -TotalQty 0.01
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [double]$EntryPrice,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("long", "short")]
        [string]$Side,
        
        [Parameter(Mandatory=$true)]
        [double]$AtrValue,
        
        [Parameter(Mandatory=$true)]
        [double]$TotalQty
    )
    
    # Multiplicadores ATR para cada TP
    $tp1Mult = 2.0
    $tp2Mult = 4.0
    $tp3Mult = 6.0
    $tp4Mult = 10.0
    
    # Distribuição de quantidade (%)
    $tp1Pct = 0.25  # 25%
    $tp2Pct = 0.35  # 35%
    $tp3Pct = 0.25  # 25%
    $tp4Pct = 0.15  # 15% runner
    
    # Calcular preços
    if ($Side -eq "long") {
        $tp1Price = $EntryPrice + ($AtrValue * $tp1Mult)
        $tp2Price = $EntryPrice + ($AtrValue * $tp2Mult)
        $tp3Price = $EntryPrice + ($AtrValue * $tp3Mult)
        $tp4Price = $EntryPrice + ($AtrValue * $tp4Mult)
    } else {
        $tp1Price = $EntryPrice - ($AtrValue * $tp1Mult)
        $tp2Price = $EntryPrice - ($AtrValue * $tp2Mult)
        $tp3Price = $EntryPrice - ($AtrValue * $tp3Mult)
        $tp4Price = $EntryPrice - ($AtrValue * $tp4Mult)
    }
    
    # Calcular quantidades
    $tp1Qty = [math]::Round($TotalQty * $tp1Pct, 8)
    $tp2Qty = [math]::Round($TotalQty * $tp2Pct, 8)
    $tp3Qty = [math]::Round($TotalQty * $tp3Pct, 8)
    $tp4Qty = [math]::Round($TotalQty - $tp1Qty - $tp2Qty - $tp3Qty, 8)  # Resto
    
    return [PSCustomObject]@{
        tp1 = [PSCustomObject]@{
            price = [math]::Round($tp1Price, 2)
            qty = $tp1Qty
            pct = $tp1Pct
            atr_mult = $tp1Mult
        }
        tp2 = [PSCustomObject]@{
            price = [math]::Round($tp2Price, 2)
            qty = $tp2Qty
            pct = $tp2Pct
            atr_mult = $tp2Mult
        }
        tp3 = [PSCustomObject]@{
            price = [math]::Round($tp3Price, 2)
            qty = $tp3Qty
            pct = $tp3Pct
            atr_mult = $tp3Mult
        }
        tp4 = [PSCustomObject]@{
            price = [math]::Round($tp4Price, 2)
            qty = $tp4Qty
            pct = $tp4Pct
            atr_mult = $tp4Mult
        }
    }
}

# ============================================================================
# Place-LadderExitOrders - Coloca ordens de TP escalonadas
# ============================================================================

function Place-LadderExitOrders {
    <#
    .SYNOPSIS
        Coloca ordens de TP escalonadas na CoinEx
    
    .DESCRIPTION
        Cria 4 ordens de take profit com quantidades distribuídas
        Usa limit orders para garantir preços exatos
    
    .PARAMETER Market
        Par de trading (ex: BTCUSDT)
    
    .PARAMETER Side
        Lado da posição (long/short)
    
    .PARAMETER Ladder
        Objeto com níveis de TP (de Get-LadderExitLevels)
    
    .PARAMETER DryRun
        Simular sem executar
    
    .EXAMPLE
        Place-LadderExitOrders -Market "BTCUSDT" -Side "long" -Ladder $ladder
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("long", "short")]
        [string]$Side,
        
        [Parameter(Mandatory=$true)]
        [object]$Ladder,
        
        [Parameter(Mandatory=$false)]
        [switch]$DryRun
    )
    
    try {
        $orderSide = if ($Side -eq "long") { "sell" } else { "buy" }
        $orders = @()
        
        Write-Host "  [LADDER] Colocando 4 TPs escalonados..." -ForegroundColor Cyan
        
        # TP1 (25%)
        Write-Host "    TP1: $($Ladder.tp1.price) ($($Ladder.tp1.qty) = $([math]::Round($Ladder.tp1.pct*100))%)" -ForegroundColor Green
        if (-not $DryRun) {
            $order1 = CoinEx-PlaceFuturesOrder -Market $Market -Side $orderSide `
                -Type "limit" -Amount $Ladder.tp1.qty -Price $Ladder.tp1.price
            $orders += [PSCustomObject]@{ level = "TP1"; order = $order1 }
        }
        
        # TP2 (35%)
        Write-Host "    TP2: $($Ladder.tp2.price) ($($Ladder.tp2.qty) = $([math]::Round($Ladder.tp2.pct*100))%)" -ForegroundColor Green
        if (-not $DryRun) {
            $order2 = CoinEx-PlaceFuturesOrder -Market $Market -Side $orderSide `
                -Type "limit" -Amount $Ladder.tp2.qty -Price $Ladder.tp2.price
            $orders += [PSCustomObject]@{ level = "TP2"; order = $order2 }
        }
        
        # TP3 (25%)
        Write-Host "    TP3: $($Ladder.tp3.price) ($($Ladder.tp3.qty) = $([math]::Round($Ladder.tp3.pct*100))%)" -ForegroundColor Green
        if (-not $DryRun) {
            $order3 = CoinEx-PlaceFuturesOrder -Market $Market -Side $orderSide `
                -Type "limit" -Amount $Ladder.tp3.qty -Price $Ladder.tp3.price
            $orders += [PSCustomObject]@{ level = "TP3"; order = $order3 }
        }
        
        # TP4 (15% runner)
        Write-Host "    TP4: $($Ladder.tp4.price) ($($Ladder.tp4.qty) = $([math]::Round($Ladder.tp4.pct*100))% runner)" -ForegroundColor Green
        if (-not $DryRun) {
            $order4 = CoinEx-PlaceFuturesOrder -Market $Market -Side $orderSide `
                -Type "limit" -Amount $Ladder.tp4.qty -Price $Ladder.tp4.price
            $orders += [PSCustomObject]@{ level = "TP4"; order = $order4 }
        }
        
        return [PSCustomObject]@{
            success = $true
            orders = $orders
            dry_run = $DryRun.IsPresent
        }
    }
    catch {
        Write-Host "  [LADDER ERROR] $_" -ForegroundColor Red
        return [PSCustomObject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

# ============================================================================
# Monitor-LadderExecution - Monitora execução e ajusta SL
# ============================================================================

function Monitor-LadderExecution {
    <#
    .SYNOPSIS
        Monitora execução de TPs e ajusta SL dinamicamente
    
    .DESCRIPTION
        Verifica quais TPs foram executados e move SL:
        - TP1 hit → SL para breakeven
        - TP2 hit → SL para TP1
        - TP3 hit → SL para TP2
    
    .PARAMETER Market
        Par de trading (ex: BTCUSDT)
    
    .PARAMETER EntryPrice
        Preço de entrada
    
    .PARAMETER Ladder
        Objeto com níveis de TP
    
    .PARAMETER Side
        Lado da posição (long/short)
    
    .EXAMPLE
        Monitor-LadderExecution -Market "BTCUSDT" -EntryPrice 100000 -Ladder $ladder -Side "long"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$true)]
        [double]$EntryPrice,
        
        [Parameter(Mandatory=$true)]
        [object]$Ladder,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("long", "short")]
        [string]$Side
    )
    
    try {
        # Buscar posição atual
        $positions = CoinEx-GetPendingPositions -Market $Market
        if (-not $positions -or $positions.Count -eq 0) {
            Write-Host "  [LADDER] Posição fechada" -ForegroundColor DarkGray
            return [PSCustomObject]@{ success = $false; reason = "position_closed" }
        }
        
        $pos = $positions[0]
        $currentPrice = [double]$pos.latest_price
        $currentQty = [double]$pos.amount
        $currentSL = if ($pos.stop_loss_price) { [double]$pos.stop_loss_price } else { 0 }
        
        # Verificar quais TPs foram atingidos
        $tp1Hit = if ($Side -eq "long") {
            $currentPrice -ge $Ladder.tp1.price
        } else {
            $currentPrice -le $Ladder.tp1.price
        }
        
        $tp2Hit = if ($Side -eq "long") {
            $currentPrice -ge $Ladder.tp2.price
        } else {
            $currentPrice -le $Ladder.tp2.price
        }
        
        $tp3Hit = if ($Side -eq "long") {
            $currentPrice -ge $Ladder.tp3.price
        } else {
            $currentPrice -le $Ladder.tp3.price
        }
        
        # Determinar novo SL
        $newSL = $currentSL
        $slReason = ""
        
        if ($tp3Hit) {
            $newSL = $Ladder.tp2.price
            $slReason = "TP3 hit → SL para TP2"
        } elseif ($tp2Hit) {
            $newSL = $Ladder.tp1.price
            $slReason = "TP2 hit → SL para TP1"
        } elseif ($tp1Hit) {
            $newSL = $EntryPrice
            $slReason = "TP1 hit → SL para breakeven"
        }
        
        # Atualizar SL se necessário
        if ($newSL -ne $currentSL -and $newSL -gt 0) {
            Write-Host "  [LADDER] $slReason" -ForegroundColor Yellow
            Write-Host "    SL: $currentSL → $newSL" -ForegroundColor Cyan
            
            $result = CoinEx-ModifyPositionStopLoss -Market $Market -Price $newSL
            
            return [PSCustomObject]@{
                success = $result.success
                tp1_hit = $tp1Hit
                tp2_hit = $tp2Hit
                tp3_hit = $tp3Hit
                old_sl = $currentSL
                new_sl = $newSL
                reason = $slReason
            }
        } else {
            Write-Host "  [LADDER] SL já está otimizado ($currentSL)" -ForegroundColor DarkGray
            return [PSCustomObject]@{
                success = $false
                reason = "sl_already_optimal"
                current_sl = $currentSL
            }
        }
    }
    catch {
        Write-Host "  [LADDER ERROR] $_" -ForegroundColor Red
        return [PSCustomObject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

# ============================================================================
# Invoke-LadderExitStrategy - Estratégia completa de ladder exits
# ============================================================================

function Invoke-LadderExitStrategy {
    <#
    .SYNOPSIS
        Implementa estratégia completa de ladder exits
    
    .DESCRIPTION
        1. Calcula níveis de TP baseados em ATR
        2. Coloca ordens escalonadas
        3. Monitora execução e ajusta SL
    
    .PARAMETER Market
        Par de trading (ex: BTCUSDT)
    
    .PARAMETER EntryPrice
        Preço de entrada
    
    .PARAMETER Side
        Lado da posição (long/short)
    
    .PARAMETER TotalQty
        Quantidade total da posição
    
    .PARAMETER AtrValue
        Valor do ATR (opcional, calcula automaticamente se não fornecido)
    
    .PARAMETER DryRun
        Simular sem executar
    
    .EXAMPLE
        Invoke-LadderExitStrategy -Market "BTCUSDT" -EntryPrice 100000 -Side "long" -TotalQty 0.01
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$true)]
        [double]$EntryPrice,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("long", "short")]
        [string]$Side,
        
        [Parameter(Mandatory=$true)]
        [double]$TotalQty,
        
        [Parameter(Mandatory=$false)]
        [double]$AtrValue = 0,
        
        [Parameter(Mandatory=$false)]
        [switch]$DryRun
    )
    
    try {
        Write-Host "`n=== LADDER EXIT STRATEGY: $Market ===" -ForegroundColor Cyan
        
        # 1. Calcular ATR se não fornecido
        if ($AtrValue -le 0) {
            Write-Host "Calculando ATR..." -ForegroundColor Yellow
            $candles = CoinEx-GetFuturesCandles -Market $Market -Period "1hour" -Limit 15
            
            if (-not $candles -or $candles.Count -lt 14) {
                throw "Dados insuficientes para calcular ATR"
            }
            
            $atrSum = 0
            for ($i = 1; $i -lt 15; $i++) {
                $high = [double]$candles[$i].high
                $low = [double]$candles[$i].low
                $prevClose = [double]$candles[$i-1].close
                
                $tr = [math]::Max(
                    ($high - $low),
                    [math]::Abs($high - $prevClose),
                    [math]::Abs($low - $prevClose)
                )
                $atrSum += $tr
            }
            $AtrValue = $atrSum / 14
            Write-Host "  ATR: $([math]::Round($AtrValue, 2))" -ForegroundColor Gray
        }
        
        # 2. Calcular níveis de TP
        Write-Host "Calculando níveis de TP..." -ForegroundColor Yellow
        $ladder = Get-LadderExitLevels -EntryPrice $EntryPrice -Side $Side `
            -AtrValue $AtrValue -TotalQty $TotalQty
        
        Write-Host "  Entry: $EntryPrice" -ForegroundColor White
        Write-Host "  TP1: $($ladder.tp1.price) (25% @ $($ladder.tp1.atr_mult)x ATR)" -ForegroundColor Green
        Write-Host "  TP2: $($ladder.tp2.price) (35% @ $($ladder.tp2.atr_mult)x ATR)" -ForegroundColor Green
        Write-Host "  TP3: $($ladder.tp3.price) (25% @ $($ladder.tp3.atr_mult)x ATR)" -ForegroundColor Green
        Write-Host "  TP4: $($ladder.tp4.price) (15% @ $($ladder.tp4.atr_mult)x ATR runner)" -ForegroundColor Green
        
        # 3. Colocar ordens
        Write-Host "`nColocando ordens..." -ForegroundColor Yellow
        $orders = Place-LadderExitOrders -Market $Market -Side $Side -Ladder $ladder -DryRun:$DryRun
        
        if ($orders.success) {
            Write-Host "✓ Ordens colocadas com sucesso" -ForegroundColor Green
        } else {
            Write-Host "✗ Falha ao colocar ordens" -ForegroundColor Red
        }
        
        Write-Host "`n=== LADDER CONFIGURADO ===" -ForegroundColor Cyan
        
        return [PSCustomObject]@{
            success = $orders.success
            market = $Market
            entry_price = $EntryPrice
            side = $Side
            total_qty = $TotalQty
            atr_value = $AtrValue
            ladder = $ladder
            orders = $orders.orders
            dry_run = $DryRun.IsPresent
        }
    }
    catch {
        Write-Host "`n✗ ERRO: $_" -ForegroundColor Red
        return [PSCustomObject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}
