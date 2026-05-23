# lib_telegram.ps1 - Telegram Bot Integration
# Envia alertas para Telegram quando eventos importantes ocorrem

# ============================================================================
# Telegram-SendMessage - Envia mensagem para Telegram
# ============================================================================

function Telegram-SendMessage {
    <#
    .SYNOPSIS
        Envia mensagem para Telegram via Bot API
    
    .PARAMETER Message
        Mensagem a ser enviada (suporta Markdown)
    
    .PARAMETER BotToken
        Token do bot (opcional, usa config se nao fornecido)
    
    .PARAMETER ChatId
        Chat ID (opcional, usa config se nao fornecido)
    
    .EXAMPLE
        Telegram-SendMessage -Message "Position opened: BNBUSDT LONG"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$BotToken,
        
        [Parameter(Mandatory=$false)]
        [string]$ChatId
    )
    
    try {
        # Carregar config se nao fornecido
        if (-not $BotToken -or -not $ChatId) {
            $configPath = Join-Path $PSScriptRoot "..\config\telegram.json"
            
            if (Test-Path $configPath) {
                $config = Get-Content $configPath -Raw | ConvertFrom-Json
                
                if (-not $BotToken) { $BotToken = $config.bot_token }
                if (-not $ChatId) { $ChatId = $config.chat_id }
            }
        }
        
        # Validar config
        if (-not $BotToken -or -not $ChatId) {
            Write-Host "[TELEGRAM] Config nao encontrado, pulando envio" -ForegroundColor Yellow
            return [PSCustomObject]@{
                success = $false
                error = "Config not found"
            }
        }
        
        if ($BotToken -eq "YOUR_BOT_TOKEN" -or $ChatId -eq "YOUR_CHAT_ID") {
            Write-Host "[TELEGRAM] Config nao configurado, pulando envio" -ForegroundColor Yellow
            return [PSCustomObject]@{
                success = $false
                error = "Config not configured"
            }
        }
        
        # Enviar mensagem
        $url = "https://api.telegram.org/bot$BotToken/sendMessage"
        
        $body = @{
            chat_id = $ChatId
            text = $Message
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json"
        
        if ($response.ok) {
            Write-Host "[TELEGRAM] Mensagem enviada com sucesso" -ForegroundColor Green
            return [PSCustomObject]@{
                success = $true
                message_id = $response.result.message_id
            }
        } else {
            Write-Host "[TELEGRAM] Erro ao enviar: $($response.description)" -ForegroundColor Red
            return [PSCustomObject]@{
                success = $false
                error = $response.description
            }
        }
    }
    catch {
        Write-Host "[TELEGRAM] Excecao: $_" -ForegroundColor Red
        return [PSCustomObject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

# ============================================================================
# Telegram-SendPositionOpened - Alerta de posicao aberta
# ============================================================================

function Telegram-SendPositionOpened {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Position
    )
    
    $sideEmoji = if ($Position.side -eq "long") { "📈" } else { "📉" }
    
    $message = @"
$sideEmoji Position Opened

Market: $($Position.market)
Side: $($Position.side.ToUpper())
Entry: `$$($Position.entry_price)
Size: $($Position.size)
Leverage: $($Position.leverage)x

Stop Loss: `$$($Position.stop_loss) ($($Position.stop_loss_pct)%)
Take Profit: `$$($Position.take_profit) ($($Position.take_profit_pct)%)

Capital: `$$($Position.capital) USDT
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# Telegram-SendPositionClosed - Alerta de posicao fechada
# ============================================================================

function Telegram-SendPositionClosed {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Position
    )
    
    $emoji = if ($Position.pnl -gt 0) { "✅" } else { "❌" }
    $pnlSign = if ($Position.pnl -gt 0) { "+" } else { "" }
    
    $message = @"
$emoji Position Closed

Market: $($Position.market)
Side: $($Position.side.ToUpper())
Entry: `$$($Position.entry_price)
Exit: `$$($Position.exit_price)

PnL: $pnlSign`$$($Position.pnl) ($pnlSign$($Position.pnl_pct)%)
Duration: $($Position.duration)
Reason: $($Position.close_reason)
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# Telegram-SendTrailingActivated - Alerta de trailing stop ativado
# ============================================================================

function Telegram-SendTrailingActivated {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Position
    )
    
    $message = @"
🎯 Trailing Stop Active

Market: $($Position.market)
Entry: `$$($Position.entry_price)
Current: `$$($Position.current_price)
Profit: +$($Position.profit_pct)%

New Stop: `$$($Position.new_stop)
Locked: +$($Position.locked_profit_pct)%
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# Telegram-SendRiskAlert - Alerta de risco
# ============================================================================

function Telegram-SendRiskAlert {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Alert
    )
    
    $message = @"
⚠️ Risk Alert

Market: $($Alert.market)
Alert Type: $($Alert.type)
Severity: $($Alert.severity)

Details: $($Alert.details)

Current Price: `$$($Alert.current_price)
Liquidation: `$$($Alert.liq_price)
Distance: $($Alert.distance_pct)%

Action Required: $($Alert.action)
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# Telegram-SendDailySummary - Resumo diario
# ============================================================================

function Telegram-SendDailySummary {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Summary
    )
    
    $emoji = if ($Summary.daily_pnl -gt 0) { "📈" } else { "📉" }
    $pnlSign = if ($Summary.daily_pnl -gt 0) { "+" } else { "" }
    
    $message = @"
$emoji Daily Summary

Date: $(Get-Date -Format "yyyy-MM-dd")

Trades Today: $($Summary.trades_count)
Wins: $($Summary.wins) | Losses: $($Summary.losses)
Win Rate: $($Summary.win_rate)%

Daily PnL: $pnlSign`$$($Summary.daily_pnl) ($pnlSign$($Summary.daily_pnl_pct)%)
Total PnL: $pnlSign`$$($Summary.total_pnl)

Open Positions: $($Summary.open_positions)
Capital: `$$($Summary.capital) USDT

Best Trade: +`$$($Summary.best_trade)
Worst Trade: -`$$($Summary.worst_trade)
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# Telegram-SendDashboardSnapshot - Envia snapshot do dashboard
# ============================================================================

function Telegram-SendDashboardSnapshot {
    param(
        [Parameter(Mandatory=$true)]
        $Metrics
    )

    $pnlEmoji = if ($Metrics.total_pnl -gt 0) { "📈" } else { "📉" }
    $pnlSign = if ($Metrics.total_pnl -gt 0) { "+" } else { "" }

    $wrEmoji = if ($Metrics.win_rate -ge 50) { "✅" } else { "⚠️" }
    $sharpeEmoji = if ($Metrics.sharpe_ratio -gt 1) { "🎯" } else { "📊" }

    $message = @"
📊 Dashboard Snapshot

Positions: $($Metrics.open_positions)
Total P&L: $pnlSign`$$($Metrics.total_pnl) $pnlEmoji
Win Rate: $($Metrics.win_rate)% $wrEmoji
Capital: `$$($Metrics.capital)

Sharpe Ratio: $($Metrics.sharpe_ratio) $sharpeEmoji
Max Drawdown: $($Metrics.max_drawdown)%
Profit Factor: $($Metrics.profit_factor)
"@

    if ($Metrics.open_positions -gt 0) {
        $message += "`n`nOpen Positions:"

        $posArray = if ($Metrics.open_positions_detail -is [array]) {
            $Metrics.open_positions_detail
        } else {
            @($Metrics.open_positions_detail)
        }

        foreach ($pos in $posArray) {
            $sideEmoji = if ($pos.side -eq "long") { "📈" } else { "📉" }
            $pnlPct = [math]::Round($pos.unrealized_pnl_pct, 2)
            $pnlPctSign = if ($pnlPct -gt 0) { "+" } else { "" }

            $message += "`n  $sideEmoji $($pos.market): $pnlPctSign$pnlPct%"
        }
    }

    Telegram-SendMessage -Message $message
}

# ============================================================================
# Funcoes exportadas
# ============================================================================
# Telegram-SendMessage
# Telegram-SendPositionOpened
# Telegram-SendPositionClosed
# Telegram-SendTrailingActivated
# Telegram-SendRiskAlert
# Telegram-SendDailySummary
# Telegram-SendDashboardSnapshot
