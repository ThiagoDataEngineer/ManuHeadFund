# lib_telegram.ps1 - Telegram Bot Integration
# Mensagens limpas e profissionais

# ============================================================================
# Telegram-SendMessage - Envia mensagem para Telegram
# ============================================================================

function Telegram-SendMessage {
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
        if (-not $BotToken -or -not $ChatId) {
            $configPath = Join-Path $PSScriptRoot "..\config\telegram.json"
            
            if (Test-Path $configPath) {
                $config = Get-Content $configPath -Raw | ConvertFrom-Json
                
                if (-not $BotToken) { $BotToken = $config.bot_token }
                if (-not $ChatId) { $ChatId = $config.chat_id }
            }
        }
        
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
# Telegram-SendPositionOpened
# ============================================================================

function Telegram-SendPositionOpened {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Position
    )
    
    $sideEmoji = if ($Position.side -eq "long") { "📈" } else { "📉" }
    
    $message = "━━━━━━━━━━━━━━━━━━━━━━`n"
    $message += "$sideEmoji POSITION OPENED`n"
    $message += "━━━━━━━━━━━━━━━━━━━━━━`n`n"
    $message += "Market: $($Position.market)`n"
    $message += "Side: $($Position.side.ToUpper())`n"
    $message += "Entry: `$$($Position.entry_price)`n"
    $message += "Size: $($Position.size)`n"
    $message += "Leverage: $($Position.leverage)x`n`n"
    $message += "Stop Loss: `$$($Position.stop_loss)`n"
    $message += "Take Profit: `$$($Position.take_profit)`n`n"
    $message += "Capital: `$$($Position.capital) USDT"
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# Telegram-SendPositionClosed
# ============================================================================

function Telegram-SendPositionClosed {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Position
    )
    
    $emoji = if ($Position.pnl -gt 0) { "✅" } else { "❌" }
    $pnlSign = if ($Position.pnl -gt 0) { "+" } else { "" }
    
    $message = "━━━━━━━━━━━━━━━━━━━━━━`n"
    $message += "$emoji POSITION CLOSED`n"
    $message += "━━━━━━━━━━━━━━━━━━━━━━`n`n"
    $message += "Market: $($Position.market)`n"
    $message += "Side: $($Position.side.ToUpper())`n"
    $message += "Entry: `$$($Position.entry_price)`n"
    $message += "Exit: `$$($Position.exit_price)`n`n"
    $message += "PnL: $pnlSign`$$($Position.pnl) ($pnlSign$($Position.pnl_pct)%)`n"
    $message += "Duration: $($Position.duration)`n"
    $message += "Reason: $($Position.close_reason)"
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# Telegram-SendTrailingActivated
# ============================================================================

function Telegram-SendTrailingActivated {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Position
    )
    
    $message = "━━━━━━━━━━━━━━━━━━━━━━`n"
    $message += "🎯 TRAILING STOP ACTIVE`n"
    $message += "━━━━━━━━━━━━━━━━━━━━━━`n`n"
    $message += "Market: $($Position.market)`n"
    $message += "Entry: `$$($Position.entry_price)`n"
    $message += "Current: `$$($Position.current_price)`n"
    $message += "Profit: +$($Position.profit_pct)%`n`n"
    $message += "New Stop: `$$($Position.new_stop)`n"
    $message += "Locked: +$($Position.locked_profit_pct)%"
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# Telegram-SendRiskAlert
# ============================================================================

function Telegram-SendRiskAlert {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Alert
    )
    
    $message = "━━━━━━━━━━━━━━━━━━━━━━`n"
    $message += "⚠️ RISK ALERT`n"
    $message += "━━━━━━━━━━━━━━━━━━━━━━`n`n"
    $message += "Market: $($Alert.market)`n"
    $message += "Type: $($Alert.type)`n"
    $message += "Severity: $($Alert.severity)`n`n"
    $message += "Current: `$$($Alert.current_price)`n"
    $message += "Liquidation: `$$($Alert.liq_price)`n"
    $message += "Distance: $($Alert.distance_pct)%`n`n"
    $message += "Action: $($Alert.action)"
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# Telegram-SendDailySummary
# ============================================================================

function Telegram-SendDailySummary {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Summary
    )
    
    $emoji = if ($Summary.daily_pnl -gt 0) { "📈" } else { "📉" }
    $pnlSign = if ($Summary.daily_pnl -gt 0) { "+" } else { "" }
    
    $message = "━━━━━━━━━━━━━━━━━━━━━━`n"
    $message += "$emoji DAILY SUMMARY`n"
    $message += "━━━━━━━━━━━━━━━━━━━━━━`n`n"
    $message += "Date: $(Get-Date -Format 'yyyy-MM-dd')`n`n"
    $message += "Trades: $($Summary.trades_count)`n"
    $message += "Wins: $($Summary.wins) | Losses: $($Summary.losses)`n"
    $message += "Win Rate: $($Summary.win_rate)%`n`n"
    $message += "Daily PnL: $pnlSign`$$($Summary.daily_pnl)`n"
    $message += "Total PnL: $pnlSign`$$($Summary.total_pnl)`n`n"
    $message += "Open: $($Summary.open_positions)`n"
    $message += "Capital: `$$($Summary.capital) USDT"
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# Telegram-SendDashboardSnapshot
# ============================================================================

function Telegram-SendDashboardSnapshot {
    param(
        [Parameter(Mandatory=$true)]
        $Metrics
    )

    $pnlEmoji = if ($Metrics.total_pnl -gt 0) { "📈" } else { "📉" }
    $pnlSign = if ($Metrics.total_pnl -gt 0) { "+" } else { "" }
    $wrEmoji = if ($Metrics.win_rate -ge 50) { "✅" } else { "⚠️" }

    $message = "━━━━━━━━━━━━━━━━━━━━━━`n"
    $message += "📊 DASHBOARD`n"
    $message += "━━━━━━━━━━━━━━━━━━━━━━`n`n"
    $message += "Positions: $($Metrics.open_positions)`n"
    $message += "P&L: $pnlSign`$$($Metrics.total_pnl) $pnlEmoji`n"
    $message += "Win Rate: $($Metrics.win_rate)% $wrEmoji`n"
    $message += "Capital: `$$($Metrics.capital)`n`n"
    $message += "Sharpe: $($Metrics.sharpe_ratio)`n"
    $message += "Max DD: $($Metrics.max_drawdown)%`n"
    $message += "Profit Factor: $($Metrics.profit_factor)"

    if ($Metrics.open_positions -gt 0) {
        $message += "`n`n--- Open Positions ---"

        $posArray = if ($Metrics.open_positions_detail -is [array]) {
            $Metrics.open_positions_detail
        } else {
            @($Metrics.open_positions_detail)
        }

        foreach ($pos in $posArray) {
            $sideEmoji = if ($pos.side -eq "long") { "📈" } else { "📉" }
            $pnlPct = [math]::Round($pos.unrealized_pnl_pct, 2)
            $pnlPctSign = if ($pnlPct -gt 0) { "+" } else { "" }

            $message += "`n$sideEmoji $($pos.market): $pnlPctSign$pnlPct%"
        }
    }

    Telegram-SendMessage -Message $message
}
