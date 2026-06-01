# lib_coinex_position_management.ps1 - Position Management API (TDD-driven)
# Implementado com TDD rigoroso: testes em tests\lib_coinex_position_management.Tests.ps1
#
# FUNCOES CRITICAS:
# 1. CoinEx-AdjustPositionLeverage    - Ajustar leverage + margin mode
# 2. CoinEx-AdjustPositionMargin      - Add/Remove margin (salva de liquidacao)
# 3. CoinEx-ModifyPositionStopLoss    - Modificar SL sem cancelar
# 4. CoinEx-ModifyPositionTakeProfit  - Modificar TP sem cancelar
# 5. CoinEx-CancelPositionStopLoss    - Cancelar SL
# 6. CoinEx-CancelPositionTakeProfit  - Cancelar TP
# 7. CoinEx-GetFinishedPositions      - Historico de posicoes (analytics)

# ============================================================================
# CoinEx-AdjustPositionLeverage - Ajustar leverage + margin mode
# ============================================================================

function CoinEx-AdjustPositionLeverage {
    <#
    .SYNOPSIS
        Ajusta leverage e margin mode de uma posicao
    
    .DESCRIPTION
        Permite ajustar leverage (1-100x) e margin mode (isolated/cross)
        CRITICO para gestao de risco - afeta liquidation price
    
    .PARAMETER Market
        Par de trading (ex: BTCUSDT)
    
    .PARAMETER Leverage
        Leverage desejado (1-100)
    
    .PARAMETER MarginMode
        Modo de margem: "isolated" (default) ou "cross"
    
    .EXAMPLE
        CoinEx-AdjustPositionLeverage -Market "BTCUSDT" -Leverage 10 -MarginMode "isolated"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$true)]
        [int]$Leverage,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("isolated", "cross")]
        [string]$MarginMode = "isolated"
    )
    
    try {
        $bodyObj = @{
            market      = $Market
            market_type = "FUTURES"
            leverage    = $Leverage
            margin_mode = $MarginMode
        }
        
        $response = CoinEx-Post -path "/v2/futures/adjust-position-leverage" -bodyObj $bodyObj
        
        if ($response.code -eq 0) {
            return [PSCustomObject]@{
                success     = $true
                leverage    = $response.data.leverage
                margin_mode = $response.data.margin_mode
                market      = $response.data.market
            }
        } else {
            return [PSCustomObject]@{
                success    = $false
                error_code = $response.code
                error_msg  = $response.message
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            success   = $false
            error_msg = $_.Exception.Message
        }
    }
}

# ============================================================================
# CoinEx-AdjustPositionMargin - Add/Remove margin
# ============================================================================

function CoinEx-AdjustPositionMargin {
    <#
    .SYNOPSIS
        Adiciona ou remove margin de uma posicao
    
    .DESCRIPTION
        Permite ajustar margin para evitar liquidacao ou liberar capital
        CRITICO para gestao de risco - afeta liquidation price
    
    .PARAMETER Market
        Par de trading (ex: BTCUSDT)
    
    .PARAMETER Amount
        Quantidade de margin a adicionar/remover
    
    .PARAMETER Type
        Tipo de operacao: "add" ou "remove"
    
    .EXAMPLE
        CoinEx-AdjustPositionMargin -Market "BTCUSDT" -Amount 100 -Type "add"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$true)]
        [decimal]$Amount,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("add", "remove")]
        [string]$Type
    )
    
    try {
        $bodyObj = @{
            market      = $Market
            market_type = "FUTURES"
            amount      = $Amount.ToString()
            type        = $Type
        }
        
        $response = CoinEx-Post -path "/v2/futures/adjust-position-margin" -bodyObj $bodyObj
        
        if ($response.code -eq 0) {
            return [PSCustomObject]@{
                success = $true
                amount  = $response.data.amount
                type    = $response.data.type
                market  = $response.data.market
            }
        } else {
            return [PSCustomObject]@{
                success    = $false
                error_code = $response.code
                error_msg  = $response.message
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            success   = $false
            error_msg = $_.Exception.Message
        }
    }
}

# ============================================================================
# CoinEx-ModifyPositionStopLoss - Modificar SL sem cancelar
# ============================================================================

function CoinEx-ModifyPositionStopLoss {
    <#
    .SYNOPSIS
        Modifica stop loss de uma posicao sem cancelar
    
    .DESCRIPTION
        Permite ajustar SL sem pagar fees de cancelamento + nova ordem
        CRITICO para trailing stops e ajustes dinamicos
    
    .PARAMETER Market
        Par de trading (ex: BTCUSDT)
    
    .PARAMETER Price
        Novo preco de stop loss
    
    .PARAMETER TriggerType
        Tipo de trigger: "mark_price" (default) ou "latest_price"
    
    .EXAMPLE
        CoinEx-ModifyPositionStopLoss -Market "BTCUSDT" -Price 95000
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$true)]
        [decimal]$Price,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("mark_price", "latest_price")]
        [string]$TriggerType = "mark_price"
    )
    
    try {
        $bodyObj = @{
            market          = $Market
            market_type     = "FUTURES"
            stop_loss_price = $Price.ToString()
            stop_loss_type  = $TriggerType
        }
        
        $response = CoinEx-Post -path "/v2/futures/modify-position-stop-loss" -bodyObj $bodyObj
        
        if ($response.code -eq 0) {
            return [PSCustomObject]@{
                success         = $true
                stop_loss_price = $response.data.stop_loss_price
                market          = $response.data.market
            }
        } else {
            return [PSCustomObject]@{
                success    = $false
                error_code = $response.code
                error_msg  = $response.message
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            success   = $false
            error_msg = $_.Exception.Message
        }
    }
}

# ============================================================================
# CoinEx-ModifyPositionTakeProfit - Modificar TP sem cancelar
# ============================================================================

function CoinEx-ModifyPositionTakeProfit {
    <#
    .SYNOPSIS
        Modifica take profit de uma posicao sem cancelar
    
    .DESCRIPTION
        Permite ajustar TP sem pagar fees de cancelamento + nova ordem
        CRITICO para ajustes dinamicos de target
    
    .PARAMETER Market
        Par de trading (ex: BTCUSDT)
    
    .PARAMETER Price
        Novo preco de take profit
    
    .PARAMETER TriggerType
        Tipo de trigger: "mark_price" (default) ou "latest_price"
    
    .EXAMPLE
        CoinEx-ModifyPositionTakeProfit -Market "BTCUSDT" -Price 105000
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$true)]
        [decimal]$Price,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("mark_price", "latest_price")]
        [string]$TriggerType = "mark_price"
    )
    
    try {
        $bodyObj = @{
            market            = $Market
            market_type       = "FUTURES"
            take_profit_price = $Price.ToString()
            take_profit_type  = $TriggerType
        }
        
        $response = CoinEx-Post -path "/v2/futures/modify-position-take-profit" -bodyObj $bodyObj
        
        if ($response.code -eq 0) {
            return [PSCustomObject]@{
                success           = $true
                take_profit_price = $response.data.take_profit_price
                market            = $response.data.market
            }
        } else {
            return [PSCustomObject]@{
                success    = $false
                error_code = $response.code
                error_msg  = $response.message
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            success   = $false
            error_msg = $_.Exception.Message
        }
    }
}

# ============================================================================
# CoinEx-CancelPositionStopLoss - Cancelar SL
# ============================================================================

function CoinEx-CancelPositionStopLoss {
    <#
    .SYNOPSIS
        Cancela stop loss de uma posicao
    
    .DESCRIPTION
        Remove SL da posicao (use com cuidado!)
    
    .PARAMETER Market
        Par de trading (ex: BTCUSDT)
    
    .EXAMPLE
        CoinEx-CancelPositionStopLoss -Market "BTCUSDT"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market
    )
    
    try {
        $bodyObj = @{
            market      = $Market
            market_type = "FUTURES"
        }
        
        $response = CoinEx-Post -path "/v2/futures/cancel-position-stop-loss" -bodyObj $bodyObj
        
        if ($response.code -eq 0) {
            return [PSCustomObject]@{
                success = $true
                status  = $response.data.status
                market  = $response.data.market
            }
        } else {
            return [PSCustomObject]@{
                success    = $false
                error_code = $response.code
                error_msg  = $response.message
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            success   = $false
            error_msg = $_.Exception.Message
        }
    }
}

# ============================================================================
# CoinEx-CancelPositionTakeProfit - Cancelar TP
# ============================================================================

function CoinEx-CancelPositionTakeProfit {
    <#
    .SYNOPSIS
        Cancela take profit de uma posicao
    
    .DESCRIPTION
        Remove TP da posicao
    
    .PARAMETER Market
        Par de trading (ex: BTCUSDT)
    
    .EXAMPLE
        CoinEx-CancelPositionTakeProfit -Market "BTCUSDT"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market
    )
    
    try {
        $bodyObj = @{
            market      = $Market
            market_type = "FUTURES"
        }
        
        $response = CoinEx-Post -path "/v2/futures/cancel-position-take-profit" -bodyObj $bodyObj
        
        if ($response.code -eq 0) {
            return [PSCustomObject]@{
                success = $true
                status  = $response.data.status
                market  = $response.data.market
            }
        } else {
            return [PSCustomObject]@{
                success    = $false
                error_code = $response.code
                error_msg  = $response.message
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            success   = $false
            error_msg = $_.Exception.Message
        }
    }
}

# ============================================================================
# CoinEx-GetFinishedPositions - Historico de posicoes
# ============================================================================

function CoinEx-GetFinishedPositions {
    <#
    .SYNOPSIS
        Retorna historico de posicoes finalizadas
    
    .DESCRIPTION
        Busca posicoes fechadas para analytics e performance tracking
        Dados historicos sao limitados pela API
    
    .PARAMETER Market
        Par de trading (opcional - filtra por market)
    
    .PARAMETER Limit
        Limite de resultados (default: 100)
    
    .EXAMPLE
        CoinEx-GetFinishedPositions -Market "BTCUSDT" -Limit 50
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Market,
        
        [Parameter(Mandatory=$false)]
        [int]$Limit = 100
    )
    
    try {
        $queryParams = @(
            "market_type=FUTURES"
            "limit=$Limit"
        )
        
        if ($Market) {
            $queryParams += "market=$Market"
        }
        
        $queryString = $queryParams -join "&"
        $path = "/v2/futures/finished-position?$queryString"
        
        $response = CoinEx-Get -path $path
        
        if ($response.code -eq 0) {
            return [PSCustomObject]@{
                success   = $true
                positions = $response.data
            }
        } else {
            return [PSCustomObject]@{
                success    = $false
                error_code = $response.code
                error_msg  = $response.message
                positions  = @()
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            success   = $false
            error_msg = $_.Exception.Message
            positions = @()
        }
    }
}

# ============================================================================
# Funcoes exportadas (disponiveis via dot-sourcing)
# ============================================================================
# CoinEx-AdjustPositionLeverage
# CoinEx-AdjustPositionMargin
# CoinEx-ModifyPositionStopLoss
# CoinEx-ModifyPositionTakeProfit
# CoinEx-CancelPositionStopLoss
# CoinEx-CancelPositionTakeProfit
# CoinEx-GetFinishedPositions
