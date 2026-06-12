# lib_telegram_v2.ps1 - Telegram Bot Integration v2
# ✨ Mensagens LIMPAS, CONCISAS e HIERÁRQUICAS
# Implementado: 2026-05-26
# Objetivo: Substituir verbosidade por clareza

# ============================================================================
# CORE: Telegram-SendMessage - Base para todas as mensagens
# ============================================================================

function Telegram-SendMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$BotToken,
        
        [Parameter(Mandatory=$false)]
        [string]$ChatId,
        
        [Parameter(Mandatory=$false)]
        [switch]$ParseMarkdown
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
            Write-Host "[TELEGRAM] Config não encontrado, pulando envio" -ForegroundColor Yellow
            return [PSCustomObject]@{
                success = $false
                error = "Config not found"
            }
        }
        
        if ($BotToken -eq "YOUR_BOT_TOKEN" -or $ChatId -eq "YOUR_CHAT_ID") {
            Write-Host "[TELEGRAM] Config não configurado, pulando envio" -ForegroundColor Yellow
            return [PSCustomObject]@{
                success = $false
                error = "Config not configured"
            }
        }
        
        $url = "https://api.telegram.org/bot$BotToken/sendMessage"
        
        $body = @{
            chat_id = $ChatId
            text = $Message
        }
        
        if ($ParseMarkdown) {
            $body.parse_mode = "Markdown"
        }
        
        $response = Invoke-RestMethod -Uri $url -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json"
        
        if ($response.ok) {
            Write-Host "[TELEGRAM] ✅ Mensagem enviada" -ForegroundColor Green
            return [PSCustomObject]@{
                success = $true
                message_id = $response.result.message_id
            }
        } else {
            Write-Host "[TELEGRAM] ❌ Erro: $($response.description)" -ForegroundColor Red
            return [PSCustomObject]@{
                success = $false
                error = $response.description
            }
        }
    }
    catch {
        Write-Host "[TELEGRAM] ❌ Exceção: $_" -ForegroundColor Red
        return [PSCustomObject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

# ============================================================================
# TRADE OPENED - Conciso e acionável
# ============================================================================

function Telegram-SendTradeOpened {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Trade
    )
    
    $side = if ($Trade.side -eq "long") { "🟢 LONG" } else { "🔴 SHORT" }
    $leverage = if ($Trade.leverage) { " | $($Trade.leverage)x" } else { "" }
    
    $message = @"
$side | $($Trade.market)$leverage
Entry: `$$($Trade.entry_price) | Size: $($Trade.size)
Stop: -$($Trade.stop_pct)% | Target: +$($Trade.target_pct)%
Capital: `$$($Trade.capital)
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# TRADE CLOSED - Resultado claro
# ============================================================================

function Telegram-SendTradeClosed {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Trade
    )
    
    $result = if ($Trade.pnl -gt 0) { "✅ WIN" } else { "❌ LOSS" }
    $pnlSign = if ($Trade.pnl -gt 0) { "+" } else { "" }
    $side = if ($Trade.side -eq "long") { "LONG" } else { "SHORT" }
    
    $message = @"
$result | $($Trade.market) [$side]
Entry: `$$($Trade.entry_price) → Exit: `$$($Trade.exit_price)
P&L: $pnlSign`$$($Trade.pnl) ($pnlSign$($Trade.pnl_pct)%)
Duration: $($Trade.duration) | Reason: $($Trade.close_reason)
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# TRAILING STOP ACTIVATED - Proteção de lucro
# ============================================================================

function Telegram-SendTrailingActivated {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Position
    )
    
    $message = @"
🛡️ TRAILING ATIVO | $($Position.market)
Lucro: +$($Position.profit_pct)% | Novo Stop: `$$($Position.new_stop)
Lucro Travado: +$($Position.locked_profit_pct)%
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# RISK ALERT - Atenção imediata
# ============================================================================

function Telegram-SendRiskAlert {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Alert
    )
    
    $severity = switch ($Alert.severity) {
        "CRITICAL" { "🚨" }
        "HIGH" { "⚠️" }
        "MEDIUM" { "⚡" }
        default { "ℹ️" }
    }
    
    $message = @"
$severity ALERTA | $($Alert.market)
Tipo: $($Alert.type) | Severidade: $($Alert.severity)
Preço: `$$($Alert.current_price) | Liquidação: `$$($Alert.liq_price)
Distância: $($Alert.distance_pct)% | Ação: $($Alert.action)
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# DAILY SUMMARY - Resumo do dia
# ============================================================================

function Telegram-SendDailySummary {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Summary
    )
    
    $trend = if ($Summary.daily_pnl -gt 0) { "📈" } else { "📉" }
    $pnlSign = if ($Summary.daily_pnl -gt 0) { "+" } else { "" }
    $wrStatus = if ($Summary.win_rate -ge 50) { "✅" } else { "⚠️" }
    
    $message = @"
$trend RESUMO DIÁRIO | $(Get-Date -Format 'dd/MM/yyyy')
Trades: $($Summary.trades_count) | Wins: $($Summary.wins) | Losses: $($Summary.losses)
Win Rate: $wrStatus $($Summary.win_rate)%
P&L Diário: $pnlSign`$$($Summary.daily_pnl) | Total: $pnlSign`$$($Summary.total_pnl)
Posições Abertas: $($Summary.open_positions) | Capital: `$$($Summary.capital)
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# GEM FOUND - Descoberta de gem
# ============================================================================

function Telegram-SendGemFound {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Gem
    )
    
    $modeEmoji = switch ($Gem.mode) {
        "DISCOVERY" { "🔬" }
        "MOMENTUM" { "🚀" }
        default { "💎" }
    }
    
    $scoreEmoji = if ($Gem.score -ge 80) { "🟢" } elseif ($Gem.score -ge 65) { "🟡" } else { "🟠" }
    
    $volSpike = if ($Gem.vol_data -and $Gem.vol_data.spike_ratio) { 
        "$([math]::Round($Gem.vol_data.spike_ratio, 1))x" 
    } else { 
        "N/A" 
    }
    
    $change24h = if ($Gem.vol_data -and $Gem.vol_data.pct_change_today) { 
        "$([math]::Round($Gem.vol_data.pct_change_today, 1))%" 
    } else { 
        "N/A" 
    }
    
    $sizeUsd = if ($Gem.sizing -and $Gem.sizing.sizing_usd) { 
        "`$$([math]::Round($Gem.sizing.sizing_usd, 2))" 
    } else { 
        "N/A" 
    }
    
    $message = @"
$modeEmoji GEM | $($Gem.market) | $scoreEmoji Score: $($Gem.score)/100
Vol: $volSpike ↑$change24h | Tamanho: $sizeUsd
Stop: -$($Gem.sizing.stop_pct)% | Target: +$($Gem.sizing.target_pct)%
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# GEM APPROVAL REQUEST - Pedindo aprovação
# ============================================================================

function Telegram-SendGemApprovalRequest {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Gem
    )
    
    $modeEmoji = switch ($Gem.mode) {
        "DISCOVERY" { "🔬" }
        "MOMENTUM" { "🚀" }
        default { "💎" }
    }
    
    $scoreEmoji = if ($Gem.score -ge 80) { "🟢" } elseif ($Gem.score -ge 65) { "🟡" } else { "🟠" }
    
    $volSpike = if ($Gem.vol_data -and $Gem.vol_data.spike_ratio) { 
        "$([math]::Round($Gem.vol_data.spike_ratio, 1))x" 
    } else { 
        "N/A" 
    }
    
    $change24h = if ($Gem.vol_data -and $Gem.vol_data.pct_change_today) { 
        "$([math]::Round($Gem.vol_data.pct_change_today, 1))%" 
    } else { 
        "N/A" 
    }
    
    $sizeUsd = if ($Gem.sizing -and $Gem.sizing.sizing_usd) { 
        "`$$([math]::Round($Gem.sizing.sizing_usd, 2))" 
    } else { 
        "N/A" 
    }
    
    $message = @"
$modeEmoji APROVAR? | $($Gem.market) | $scoreEmoji $($Gem.score)/100
Vol: $volSpike ↑$change24h | Tamanho: $sizeUsd
Stop: -$($Gem.sizing.stop_pct)% | Target: +$($Gem.sizing.target_pct)%
✅ Sim | ❌ Não
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# GEM EXECUTED - Gem foi executado
# ============================================================================

function Telegram-SendGemExecuted {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Gem,
        
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$ExecResult
    )
    
    $status = if ($ExecResult.success) { "✅ EXECUTADO" } else { "❌ FALHOU" }
    $sizeUsd = if ($Gem.sizing -and $Gem.sizing.sizing_usd) { 
        "`$$([math]::Round($Gem.sizing.sizing_usd, 2))" 
    } else { 
        "N/A" 
    }
    
    $message = @"
$status | $($Gem.market) | Score: $($Gem.score)/100
Tamanho: $sizeUsd | Modo: $($Gem.mode)
$(if ($ExecResult.error) { "Erro: $($ExecResult.error)" })
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# DASHBOARD SNAPSHOT - Status rápido do sistema
# ============================================================================

function Telegram-SendDashboardSnapshot {
    param(
        [Parameter(Mandatory=$true)]
        $Metrics
    )
    
    $pnlTrend = if ($Metrics.total_pnl -gt 0) { "📈" } else { "📉" }
    $pnlSign = if ($Metrics.total_pnl -gt 0) { "+" } else { "" }
    $wrStatus = if ($Metrics.win_rate -ge 50) { "✅" } else { "⚠️" }
    
    $message = @"
📊 DASHBOARD | $(Get-Date -Format 'HH:mm:ss')
Posições: $($Metrics.open_positions) | P&L: $pnlSign`$$($Metrics.total_pnl) [$pnlTrend]
Win Rate: $wrStatus $($Metrics.win_rate)% | Capital: `$$($Metrics.capital)
Sharpe: $($Metrics.sharpe_ratio) | Drawdown: $($Metrics.max_drawdown)%
"@
    
    if ($Metrics.open_positions -gt 0 -and $Metrics.open_positions_detail) {
        $message += "`n`n--- Posições Abertas ---"
        
        $posArray = if ($Metrics.open_positions_detail -is [array]) {
            $Metrics.open_positions_detail
        } else {
            @($Metrics.open_positions_detail)
        }
        
        foreach ($pos in $posArray) {
            $sideLabel = if ($pos.side -eq "long") { "🟢" } else { "🔴" }
            $pnlPct = [math]::Round($pos.unrealized_pnl_pct, 2)
            $pnlPctSign = if ($pnlPct -gt 0) { "+" } else { "" }
            
            $message += "`n$sideLabel $($pos.market): $pnlPctSign$pnlPct%"
        }
    }
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# SYSTEM STATUS - Status do sistema
# ============================================================================

function Telegram-SendSystemStatus {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Status
    )
    
    $statusEmoji = if ($Status.is_running) { "✅" } else { "❌" }
    $uptime = $Status.uptime_hours
    
    $message = @"
$statusEmoji SISTEMA | $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
Status: $($Status.status) | Uptime: $uptime h
Memória: $($Status.memory_usage)% | CPU: $($Status.cpu_usage)%
Última Atividade: $($Status.last_activity)
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# CALIBRATION PROGRESS - Progresso da calibração
# ============================================================================

function Telegram-SendCalibrationProgress {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Progress
    )
    
    $progressBar = ""
    $filled = [math]::Round($Progress.progress_pct / 10)
    $empty = 10 - $filled
    
    $progressBar = "█" * $filled + "░" * $empty
    
    $message = @"
📈 CALIBRAÇÃO | $($Progress.day)/$($Progress.total_days) dias
Progresso: [$progressBar] $($Progress.progress_pct)%
Trades: $($Progress.trades_count) | Win Rate: $($Progress.win_rate)%
P&L: +$($Progress.pnl_pct)% | ETA: $($Progress.eta_days) dias
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# QUOTA WARNING - Aviso de quota
# ============================================================================

function Telegram-SendQuotaWarning {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Quota
    )
    
    $severity = if ($Quota.usage_pct -ge 90) { "🚨" } else { "⚠️" }
    
    $message = @"
$severity QUOTA LLM | $(Get-Date -Format 'dd/MM/yyyy')
Uso: $($Quota.usage_pct)% | Chamadas: $($Quota.calls_used)/$($Quota.calls_limit)
Dias Restantes: $($Quota.days_remaining) | Ação: $($Quota.action)
"@
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# BACKWARD COMPATIBILITY - Aliases para funções antigas
# ============================================================================

function Send-TelegramAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$BotToken = $env:TELEGRAM_BOT_TOKEN,
        
        [Parameter(Mandatory=$false)]
        [string]$ChatId = $env:TELEGRAM_CHAT_ID
    )
    
    return Telegram-SendMessage -Message $Message -BotToken $BotToken -ChatId $ChatId
}

# Alias para compatibilidade com código antigo
function Send-GemAlert {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Gem,
        
        [Parameter(Mandatory=$false)]
        [string]$MarketType = "SPOT",
        
        [Parameter(Mandatory=$false)]
        [string]$BotToken = $env:TELEGRAM_BOT_TOKEN,
        
        [Parameter(Mandatory=$false)]
        [string]$ChatId = $env:TELEGRAM_CHAT_ID
    )
    
    return Telegram-SendGemFound -Gem $Gem
}

function Format-TgGemApproval {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Gem,
        
        [Parameter(Mandatory=$false)]
        [switch]$DryRun
    )
    
    # Retorna apenas a mensagem formatada (sem enviar)
    $modeEmoji = switch ($Gem.mode) {
        "DISCOVERY" { "🔬" }
        "MOMENTUM" { "🚀" }
        default { "💎" }
    }
    
    $scoreEmoji = if ($Gem.score -ge 80) { "🟢" } elseif ($Gem.score -ge 65) { "🟡" } else { "🟠" }
    
    $volSpike = if ($Gem.vol_data -and $Gem.vol_data.spike_ratio) { 
        "$([math]::Round($Gem.vol_data.spike_ratio, 1))x" 
    } else { 
        "N/A" 
    }
    
    $change24h = if ($Gem.vol_data -and $Gem.vol_data.pct_change_today) { 
        "$([math]::Round($Gem.vol_data.pct_change_today, 1))%" 
    } else { 
        "N/A" 
    }
    
    $sizeUsd = if ($Gem.sizing -and $Gem.sizing.sizing_usd) { 
        "`$$([math]::Round($Gem.sizing.sizing_usd, 2))" 
    } else { 
        "N/A" 
    }
    
    $dryTag = if ($DryRun) { " [DRYRUN]" } else { "" }
    
    $msg = @"
$modeEmoji APROVAR$dryTag | $($Gem.market) | $scoreEmoji $($Gem.score)/100
Vol: $volSpike ↑$change24h | Tamanho: $sizeUsd
Stop: -$($Gem.sizing.stop_pct)% | Target: +$($Gem.sizing.target_pct)%
✅ Sim | ❌ Não
"@
    
    return $msg
}

function Format-TgGemExecuted {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$ExecResult,
        
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Gem
    )
    
    $status = if ($ExecResult.success) { "✅ EXECUTADO" } else { "❌ FALHOU" }
    $sizeUsd = if ($Gem.sizing -and $Gem.sizing.sizing_usd) { 
        "`$$([math]::Round($Gem.sizing.sizing_usd, 2))" 
    } else { 
        "N/A" 
    }
    
    $msg = @"
$status | $($Gem.market) | Score: $($Gem.score)/100
Tamanho: $sizeUsd | Modo: $($Gem.mode)
$(if ($ExecResult.error) { "Erro: $($ExecResult.error)" })
"@
    
    return $msg
}

# ============================================================================
# EXPORT - Funções públicas
# ============================================================================

Export-ModuleMember -Function @(
    'Telegram-SendMessage',
    'Telegram-SendTradeOpened',
    'Telegram-SendTradeClosed',
    'Telegram-SendTrailingActivated',
    'Telegram-SendRiskAlert',
    'Telegram-SendDailySummary',
    'Telegram-SendGemFound',
    'Telegram-SendGemApprovalRequest',
    'Telegram-SendGemExecuted',
    'Telegram-SendDashboardSnapshot',
    'Telegram-SendSystemStatus',
    'Telegram-SendCalibrationProgress',
    'Telegram-SendQuotaWarning',
    'Send-TelegramAlert',
    'Send-GemAlert',
    'Format-TgGemApproval',
    'Format-TgGemExecuted'
)
