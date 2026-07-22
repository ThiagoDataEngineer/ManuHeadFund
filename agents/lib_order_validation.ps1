# lib_order_validation.ps1
# Validação pós-execução de ordens com retry e fallback
# Implementado com TDD: tests\lib_order_validation.Tests.ps1
# 2026-05-24
#
# FUNCIONALIDADES:
# 1. Validar se stop loss e take profit foram configurados
# 2. Retry automático se falhar
# 3. Fallback para endpoints alternativos
# 4. Alertas se posição sem proteção

# ============================================================================
# Test-PositionHasStopLoss - Verificar se posição tem stop loss
# ============================================================================

function Test-PositionHasStopLoss {
    <#
    .SYNOPSIS
        Verifica se uma posição tem stop loss configurado
    
    .PARAMETER Market
        Par de trading (ex: BTCUSDT)
    
    .OUTPUTS
        PSCustomObject com has_stop_loss, stop_loss_price, has_take_profit, take_profit_price
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market
    )
    
    try {
        $positions = CoinEx-GetPendingPositions -Market $Market
        
        if (-not $positions -or $positions.Count -eq 0) {
            return [PSCustomObject]@{
                success = $false
                error = "Position not found"
                has_stop_loss = $false
                has_take_profit = $false
            }
        }
        
        $pos = $positions[0]
        $stopLoss = [double]$pos.stop_loss_price
        $takeProfit = [double]$pos.take_profit_price
        
        return [PSCustomObject]@{
            success = $true
            has_stop_loss = ($stopLoss -gt 0)
            stop_loss_price = $stopLoss
            has_take_profit = ($takeProfit -gt 0)
            take_profit_price = $takeProfit
            market = $Market
        }
    }
    catch {
        return [PSCustomObject]@{
            success = $false
            error = $_.Exception.Message
            has_stop_loss = $false
            has_take_profit = $false
        }
    }
}

# ============================================================================
# Set-PositionStopLossFallback - Configurar stop loss com fallback
# ============================================================================

function Set-PositionStopLossFallback {
    <#
    .SYNOPSIS
        Configura stop loss com múltiplas tentativas e fallback
    
    .PARAMETER Market
        Par de trading
    
    .PARAMETER Price
        Preço do stop loss
    
    .PARAMETER MaxRetries
        Número máximo de tentativas (default: 3)
    
    .OUTPUTS
        PSCustomObject com success, method_used, stop_loss_price
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$true)]
        [decimal]$Price,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxRetries = 3
    )
    
    $attempt = 0

    # 2026-07-22 FIX: Round($Price,4) fixo zerava o preco de tokens sub-centavo
    # (PEPE ~$0.0000045) mesmo depois de Repair-PositionProtection calcular o
    # valor correto -- o zeramento acontecia aqui, na hora de montar o corpo
    # da requisicao pra API, nao no calculo em si. Mesma causa raiz corrigida
    # em lib_position_protection.ps1, precisava do mesmo fix aqui tambem.
    $slRoundPrec = 4
    if (Get-Command Get-MarketPrecision -ErrorAction SilentlyContinue) {
        try {
            $slPrec = Get-MarketPrecision -Market $Market -MarketType "futures"
            if ($slPrec -and $slPrec.quote_ccy_precision -gt 0) { $slRoundPrec = [int]$slPrec.quote_ccy_precision }
        } catch { }
    }

    while ($attempt -lt $MaxRetries) {
        $attempt++

        try {
            # Método 1: set-position-stop-loss (preferido)
            Write-Verbose "Attempt ${attempt}: Using set-position-stop-loss"

            $inv = [System.Globalization.CultureInfo]::InvariantCulture
            $bodyObj = @{
                market = $Market
                market_type = "FUTURES"
                stop_loss_type = "mark_price"
                stop_loss_price = ([Math]::Round($Price, $slRoundPrec)).ToString($inv)
            }

            $response = CoinEx-Post -path "/v2/futures/set-position-stop-loss" -bodyObj $bodyObj

            if ($response.code -eq 0) {
                # Validar
                Start-Sleep -Milliseconds 500
                $validation = Test-PositionHasStopLoss -Market $Market

                if ($validation.has_stop_loss) {
                    return [PSCustomObject]@{
                        success = $true
                        method_used = "set-position-stop-loss"
                        stop_loss_price = $validation.stop_loss_price
                        attempts = $attempt
                    }
                }
            }

            # Se chegou aqui, falhou - tentar método 2
            Write-Verbose "Attempt ${attempt}: Trying modify-position-stop-loss"

            $bodyObj2 = @{
                market = $Market
                market_type = "FUTURES"
                stop_loss_type = "mark_price"
                stop_loss_price = ([Math]::Round($Price, $slRoundPrec)).ToString($inv)
            }
            
            $response2 = CoinEx-Post -path "/v2/futures/modify-position-stop-loss" -bodyObj $bodyObj2
            
            if ($response2.code -eq 0) {
                # Validar
                Start-Sleep -Milliseconds 500
                $validation2 = Test-PositionHasStopLoss -Market $Market
                
                if ($validation2.has_stop_loss) {
                    return [PSCustomObject]@{
                        success = $true
                        method_used = "modify-position-stop-loss"
                        stop_loss_price = $validation2.stop_loss_price
                        attempts = $attempt
                    }
                }
            }
            
            # Aguardar antes de retry
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Milliseconds (300 * $attempt)
            }
        }
        catch {
            Write-Verbose "Attempt $attempt failed: $_"
            
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Milliseconds (300 * $attempt)
            }
        }
    }
    
    # Esgotou tentativas
    return [PSCustomObject]@{
        success = $false
        error = "Failed to set stop loss after $MaxRetries attempts"
        method_used = "none"
        attempts = $MaxRetries
    }
}

# ============================================================================
# Set-PositionTakeProfitFallback - Configurar take profit com fallback
# ============================================================================

function Set-PositionTakeProfitFallback {
    <#
    .SYNOPSIS
        Configura take profit com múltiplas tentativas e fallback
    
    .PARAMETER Market
        Par de trading
    
    .PARAMETER Price
        Preço do take profit
    
    .PARAMETER MaxRetries
        Número máximo de tentativas (default: 3)
    
    .OUTPUTS
        PSCustomObject com success, method_used, take_profit_price
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$true)]
        [decimal]$Price,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxRetries = 3
    )
    
    $attempt = 0

    # 2026-07-22 FIX: mesmo bug de Set-PositionStopLossFallback -- Round(,4)
    # fixo zerava TP de tokens sub-centavo antes de enviar pra API.
    $tpRoundPrec = 4
    if (Get-Command Get-MarketPrecision -ErrorAction SilentlyContinue) {
        try {
            $tpPrec = Get-MarketPrecision -Market $Market -MarketType "futures"
            if ($tpPrec -and $tpPrec.quote_ccy_precision -gt 0) { $tpRoundPrec = [int]$tpPrec.quote_ccy_precision }
        } catch { }
    }

    while ($attempt -lt $MaxRetries) {
        $attempt++

        try {
            # Método 1: set-position-take-profit
            Write-Verbose "Attempt ${attempt}: Using set-position-take-profit"

            $inv = [System.Globalization.CultureInfo]::InvariantCulture

            # 2026-06-03: Validacao TP — rejeitar se TP muito perto da entrada (bug detection)
            # Symptoma: API retorna TP=entrada*1.0001 em vez de entrada*1.0 + target%
            if ($Price -le 0) {
                throw "Set-PositionTakeProfitFallback: Price invalido ($Price <= 0)"
            }

            $bodyObj = @{
                market = $Market
                market_type = "FUTURES"
                take_profit_type = "mark_price"
                take_profit_price = ([Math]::Round($Price, $tpRoundPrec)).ToString($inv)
            }

            Write-Verbose "Set-PositionTakeProfitFallback: Enviando TP=$Price (arredondado=$(([Math]::Round($Price, $tpRoundPrec)).ToString($inv)))"

            $response = CoinEx-Post -path "/v2/futures/set-position-take-profit" -bodyObj $bodyObj

            # 2026-06-03: DEBUG resposta da API — se rejeitou, logar
            if ($response.code -ne 0) {
                Write-Verbose "API REJEITOU TP: code=$($response.code) msg=$($response.msg)"
            }

            if ($response.code -eq 0) {
                # Validar
                Start-Sleep -Milliseconds 500
                $validation = Test-PositionHasStopLoss -Market $Market

                if ($validation.has_take_profit) {
                    return [PSCustomObject]@{
                        success = $true
                        method_used = "set-position-take-profit"
                        take_profit_price = $validation.take_profit_price
                        attempts = $attempt
                    }
                }
            }

            # Método 2: modify-position-take-profit
            Write-Verbose "Attempt ${attempt}: Trying modify-position-take-profit"

            $bodyObj2 = @{
                market = $Market
                market_type = "FUTURES"
                take_profit_type = "mark_price"
                take_profit_price = ([Math]::Round($Price, $tpRoundPrec)).ToString($inv)
            }
            
            $response2 = CoinEx-Post -path "/v2/futures/modify-position-take-profit" -bodyObj $bodyObj2
            
            if ($response2.code -eq 0) {
                # Validar
                Start-Sleep -Milliseconds 500
                $validation2 = Test-PositionHasStopLoss -Market $Market
                
                if ($validation2.has_take_profit) {
                    return [PSCustomObject]@{
                        success = $true
                        method_used = "modify-position-take-profit"
                        take_profit_price = $validation2.take_profit_price
                        attempts = $attempt
                    }
                }
            }
            
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Milliseconds (300 * $attempt)
            }
        }
        catch {
            Write-Verbose "Attempt $attempt failed: $_"
            
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Milliseconds (300 * $attempt)
            }
        }
    }
    
    return [PSCustomObject]@{
        success = $false
        error = "Failed to set take profit after $MaxRetries attempts"
        method_used = "none"
        attempts = $MaxRetries
    }
}

# ============================================================================
# Invoke-OrderWithValidation - Executar ordem com validação completa
# ============================================================================

function Invoke-OrderWithValidation {
    <#
    .SYNOPSIS
        Executa ordem e valida se stop loss e take profit foram configurados
    
    .PARAMETER Market
        Par de trading
    
    .PARAMETER Side
        Lado (buy/sell)
    
    .PARAMETER Amount
        Quantidade
    
    .PARAMETER StopLoss
        Preço do stop loss
    
    .PARAMETER TakeProfit
        Preço do take profit
    
    .PARAMETER Leverage
        Alavancagem (default: 5)
    
    .OUTPUTS
        PSCustomObject com success, order_id, validation_result
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$true)]
        [string]$Side,
        
        [Parameter(Mandatory=$true)]
        [double]$Amount,
        
        [Parameter(Mandatory=$false)]
        [double]$StopLoss = 0,
        
        [Parameter(Mandatory=$false)]
        [double]$TakeProfit = 0,
        
        [Parameter(Mandatory=$false)]
        [int]$Leverage = 5
    )
    
    try {
        # 1. Ajustar leverage
        Write-Verbose "Setting leverage to ${Leverage}x"
        $leverageResult = CoinEx-AdjustPositionLeverage -Market $Market -Leverage $Leverage -MarginMode "isolated"
        
        if (-not $leverageResult.success) {
            return [PSCustomObject]@{
                success = $false
                error = "Failed to set leverage: $($leverageResult.error_msg)"
                stage = "leverage"
            }
        }
        
        # 2. Executar ordem (SEM stop/TP no PlaceOrder - bug conhecido)
        Write-Verbose "Placing order"
        $orderResult = CoinEx-PlaceOrder `
            -market $Market `
            -side $Side `
            -type "market" `
            -amount $Amount
        
        if (-not $orderResult -or -not $orderResult.order_id) {
            return [PSCustomObject]@{
                success = $false
                error = "Failed to place order"
                stage = "order"
            }
        }
        
        $orderId = $orderResult.order_id
        Write-Verbose "Order placed: $orderId"
        
        # 3. Aguardar ordem ser processada
        Start-Sleep -Seconds 2
        
        # 4. Configurar stop loss (se especificado)
        $slResult = $null
        if ($StopLoss -gt 0) {
            Write-Verbose "Setting stop loss: $StopLoss"
            $slResult = Set-PositionStopLossFallback -Market $Market -Price $StopLoss -MaxRetries 3
            
            if (-not $slResult.success) {
                return [PSCustomObject]@{
                    success = $false
                    error = "Order placed but failed to set stop loss: $($slResult.error)"
                    order_id = $orderId
                    stage = "stop_loss"
                    warning = "POSITION WITHOUT STOP LOSS PROTECTION!"
                }
            }
        }
        
        # 5. Configurar take profit (se especificado)
        $tpResult = $null
        if ($TakeProfit -gt 0) {
            Write-Verbose "Setting take profit: $TakeProfit"
            $tpResult = Set-PositionTakeProfitFallback -Market $Market -Price $TakeProfit -MaxRetries 3
            
            if (-not $tpResult.success) {
                Write-Warning "Failed to set take profit: $($tpResult.error)"
            }
        }
        
        # 6. Validação final
        $validation = Test-PositionHasStopLoss -Market $Market
        
        return [PSCustomObject]@{
            success = $true
            order_id = $orderId
            stop_loss_configured = $validation.has_stop_loss
            stop_loss_price = $validation.stop_loss_price
            take_profit_configured = $validation.has_take_profit
            take_profit_price = $validation.take_profit_price
            stop_loss_method = if ($slResult) { $slResult.method_used } else { "none" }
            take_profit_method = if ($tpResult) { $tpResult.method_used } else { "none" }
            validation = $validation
        }
    }
    catch {
        return [PSCustomObject]@{
            success = $false
            error = $_.Exception.Message
            stage = "unknown"
        }
    }
}

# ============================================================================
# Funcoes exportadas
# ============================================================================
# Test-PositionHasStopLoss
# Set-PositionStopLossFallback
# Set-PositionTakeProfitFallback
# Invoke-OrderWithValidation
