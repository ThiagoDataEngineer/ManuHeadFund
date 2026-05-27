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
# Telegram-SendPositionOpened (COMPACTO)
# ============================================================================

function Telegram-SendPositionOpened {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Position
    )
    
    $sideIcon = if ($Position.side -eq "long") { "📈" } else { "📉" }
    $message = "$sideIcon <b>$($Position.market)</b> | Entry: `$$($Position.entry_price) | Size: $($Position.size)`nStop: `$$($Position.stop_loss) | TP: `$$($Position.take_profit)"
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# Telegram-SendPositionClosed (COMPACTO)
# ============================================================================

function Telegram-SendPositionClosed {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Position
    )
    
    $result = if ($Position.pnl -gt 0) { "✅ WIN" } else { "❌ LOSS" }
    $pnlSign = if ($Position.pnl -gt 0) { "+" } else { "" }
    
    $message = "$result | <b>$($Position.market)</b> | $pnlSign`$$($Position.pnl) ($pnlSign$($Position.pnl_pct)%)`nDuration: $($Position.duration) | Reason: $($Position.close_reason)"
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# Telegram-SendTrailingActivated (COMPACTO)
# ============================================================================

function Telegram-SendTrailingActivated {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Position
    )
    
    $message = "🎯 <b>TRAILING ACTIVE</b> | $($Position.market)`nEntry: `$$($Position.entry_price) → Current: `$$($Position.current_price) (+$($Position.profit_pct)%)`nNew Stop: `$$($Position.new_stop)"
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# Telegram-SendRiskAlert (COMPACTO)
# ============================================================================

function Telegram-SendRiskAlert {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Alert
    )
    
    $severity = switch ($Alert.severity) {
        "HIGH" { "🔴" }
        "MEDIUM" { "🟠" }
        default { "🟡" }
    }
    
    $message = "$severity <b>RISK ALERT</b> | $($Alert.market)`nCurrent: `$$($Alert.current_price) | Liq: `$$($Alert.liq_price) | Distance: $($Alert.distance_pct)%`nAction: $($Alert.action)"
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# Telegram-SendDailySummary (COMPACTO)
# ============================================================================

function Telegram-SendDailySummary {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Summary
    )
    
    $trend = if ($Summary.daily_pnl -gt 0) { "📈" } else { "📉" }
    $pnlSign = if ($Summary.daily_pnl -gt 0) { "+" } else { "" }
    
    $message = "$trend <b>DAILY SUMMARY</b> | Trades: $($Summary.trades_count) | W/L: $($Summary.wins)/$($Summary.losses) | WR: $($Summary.win_rate)%`nDaily: $pnlSign`$$($Summary.daily_pnl) | Total: $pnlSign`$$($Summary.total_pnl) | Open: $($Summary.open_positions)"
    
    Telegram-SendMessage -Message $message
}

# ============================================================================
# Telegram-SendDashboardSnapshot (COMPACTO)
# ============================================================================

function Telegram-SendDashboardSnapshot {
    param(
        [Parameter(Mandatory=$true)]
        $Metrics
    )

    $pnlTrend = if ($Metrics.total_pnl -gt 0) { "📈" } else { "📉" }
    $pnlSign = if ($Metrics.total_pnl -gt 0) { "+" } else { "" }

    $message = "$pnlTrend <b>DASHBOARD</b> | P&L: $pnlSign`$$($Metrics.total_pnl) | WR: $($Metrics.win_rate)% | Open: $($Metrics.open_positions)`nCapital: `$$($Metrics.capital) | Sharpe: $($Metrics.sharpe_ratio) | DD: $($Metrics.max_drawdown)%"

    if ($Metrics.open_positions -gt 0) {
        $posArray = if ($Metrics.open_positions_detail -is [array]) {
            $Metrics.open_positions_detail
        } else {
            @($Metrics.open_positions_detail)
        }

        $posStr = ""
        foreach ($pos in $posArray) {
            $sideLabel = if ($pos.side -eq "long") { "L" } else { "S" }
            $pnlPct = [math]::Round($pos.unrealized_pnl_pct, 1)
            $pnlPctSign = if ($pnlPct -gt 0) { "+" } else { "" }
            $posStr += "`n[$sideLabel] $($pos.market): $pnlPctSign$pnlPct%"
        }
        $message += $posStr
    }

    Telegram-SendMessage -Message $message
}


# ============================================================================
# Send-TelegramAlert - Alias para Telegram-SendMessage (compat retroativa)
# Usado por: tori_proximity_scanner, lib_trailing, daily_summary_digest, etc
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


# ==============================================================================
# Send-GemAlert — Formata e envia alerta Telegram para gem encontrado (COMPACTO)
# ==============================================================================
function Send-GemAlert {
    [CmdletBinding()]
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

    if (-not $BotToken -or -not $ChatId) { return $null }

    $modeEmoji = switch ($Gem.mode) {
        "DISCOVERY" { "🔬" }
        "MOMENTUM"  { "🚀" }
        default     { "💎" }
    }

    $scoreColor = if ($Gem.score -ge 80) { "🟢" } elseif ($Gem.score -ge 65) { "🟡" } else { "🟠" }

    $volSpike   = if ($Gem.vol_data -and $Gem.vol_data.spike_ratio) { "$([math]::Round($Gem.vol_data.spike_ratio, 1))x" } else { "N/A" }
    $change24h  = if ($Gem.vol_data -and $Gem.vol_data.pct_change_today) { "$([math]::Round($Gem.vol_data.pct_change_today, 1))%" } else { "N/A" }
    $sizeUsd    = if ($Gem.sizing) { "`$$([math]::Round($Gem.sizing.size_usd, 2))" } else { "N/A" }

    $msg = "$modeEmoji <b>$($Gem.market)</b> | Score: $scoreColor$($Gem.score) | Vol: $volSpike ↑$change24h`n💰 Size: $sizeUsd | Mode: $($Gem.mode)"

    return Telegram-SendMessage -Message $msg -BotToken $BotToken -ChatId $ChatId
}


# ==============================================================================
# Format-TgGemApproval — Formata mensagem de aprovação de gem (COMPACTO)
# ==============================================================================
function Format-TgGemApproval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Gem,

        [Parameter(Mandatory=$false)]
        [switch]$DryRun
    )

    $modeEmoji = switch ($Gem.mode) {
        "DISCOVERY" { "🔬" }
        "MOMENTUM"  { "🚀" }
        default     { "💎" }
    }
    $dryTag = if ($DryRun) { " [DRYRUN]" } else { "" }

    $volSpike  = if ($Gem.vol_data -and $Gem.vol_data.spike_ratio)      { "$([math]::Round($Gem.vol_data.spike_ratio,1))x" }      else { "N/A" }
    $change24h = if ($Gem.vol_data -and $Gem.vol_data.pct_change_today) { "$([math]::Round($Gem.vol_data.pct_change_today,1))%" } else { "N/A" }
    $sizeUsd   = if ($Gem.sizing -and $Gem.sizing.sizing_usd)           { "`$$([math]::Round($Gem.sizing.sizing_usd,2))" }         else { "N/A" }
    $stopPct   = if ($Gem.sizing -and $Gem.sizing.stop_pct)             { "$([math]::Round($Gem.sizing.stop_pct*100,0))%" }        else { "N/A" }
    $targetPct = if ($Gem.sizing -and $Gem.sizing.target_pct)           { "+$([math]::Round($Gem.sizing.target_pct*100,0))%" }     else { "N/A" }

    $msg = "$modeEmoji <b>APPROVE$dryTag — $($Gem.market)</b> | Score: $($Gem.score) | Vol: $volSpike ↑$change24h`n💰 $sizeUsd | Stop: $stopPct | Target: $targetPct`n✅ Approve?"

    return $msg
}

# ==============================================================================
# Format-TgGemExecuted — Formata mensagem de execução de gem (COMPACTO)
# ==============================================================================
function Format-TgGemExecuted {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$ExecResult,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Gem
    )

    $status = if ($ExecResult.success) { "✅" } else { "❌" }
    $sizeUsd = if ($Gem.sizing -and $Gem.sizing.sizing_usd) { "`$$([math]::Round($Gem.sizing.sizing_usd,2))" } else { "N/A" }

    $msg = "$status <b>$($Gem.market)</b> [$($Gem.mode)] | Score: $($Gem.score) | Size: $sizeUsd"
    if ($ExecResult.error) { $msg += "`nError: $($ExecResult.error)" }

    return $msg
}

# ==============================================================================
# Format-TgTrailStopHit — Formata mensagem quando trailing stop é atingido
# Adicionado 2026-05-26: função chamada em lib_trailing.ps1 L454 mas nunca definida.
# ==============================================================================
function Format-TgTrailStopHit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Pos,

        [Parameter(Mandatory=$false)]
        [double]$CurrentPrice
    )

    $sideEmoji = if ($Pos.side -eq "LONG") { "📉" } else { "📈" }
    $pnlSign = if ($Pos.pnl -gt 0) { "+" } else { "" }
    $pnlPct = if ($Pos.pnl_pct) { $Pos.pnl_pct } else { 0 }

    $msg = @"
$sideEmoji <b>TRAILING STOP HIT — $($Pos.market)</b>
$pnlSign$pnlPct% | Preço: <code>$CurrentPrice</code>
Stop: <code>$($Pos.stopCurrent)</code> | Lucro: <code>$pnlSign`$$($Pos.pnl)</code>
"@

    return $msg
}

# ==============================================================================
# Format-TgTrailPhase — Formata mensagem quando fase de trailing muda
# Adicionado 2026-05-26: função chamada em lib_trailing.ps1 L483 mas nunca definida.
# ==============================================================================
function Format-TgTrailPhase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Pos,

        [Parameter(Mandatory=$false)]
        [double]$OldStop,

        [Parameter(Mandatory=$false)]
        [int]$OldPhase,

        [Parameter(Mandatory=$false)]
        [double]$CurrentPrice
    )

    $phaseEmoji = switch ($Pos.phase) {
        1 { "🟡" }
        2 { "🟠" }
        3 { "🟢" }
        default { "⚪" }
    }

    $msg = @"
$phaseEmoji <b>TRAILING PHASE $OldPhase → $($Pos.phase) — $($Pos.market)</b>
Preço: <code>$CurrentPrice</code> | Stop: <code>$OldStop</code> → <code>$($Pos.stopCurrent)</code>
"@

    return $msg
}

# ==============================================================================
# Wait-TgCallbackApproval — Aguarda aprovação do usuário via Telegram callback
# Adicionado 2026-05-26: função chamada em gem_agent.ps1 para aprovação de gems.
# ==============================================================================
function Wait-TgCallbackApproval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$GemMarket,

        [Parameter(Mandatory=$false)]
        [int]$TimeoutSeconds = 300,

        [Parameter(Mandatory=$false)]
        [string]$BotToken = $env:TELEGRAM_BOT_TOKEN,

        [Parameter(Mandatory=$false)]
        [string]$ChatId = $env:TELEGRAM_CHAT_ID
    )

    if (-not $BotToken -or -not $ChatId) {
        Write-Host "[CALLBACK] Config Telegram nao encontrado" -ForegroundColor Yellow
        return [PSCustomObject]@{
            approved = $false
            reason = "Config not found"
        }
    }

    # Arquivo de estado para armazenar aprovações
    $stateDir = Join-Path $PSScriptRoot "..\journal"
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    
    $approvalFile = Join-Path $stateDir "gem_approvals.json"
    $startTime = Get-Date

    Write-Host "[CALLBACK] Aguardando aprovação para $GemMarket (timeout: $($TimeoutSeconds)s)..." -ForegroundColor Cyan

    # Loop de polling (a cada 5 segundos)
    while ((Get-Date) -lt $startTime.AddSeconds($TimeoutSeconds)) {
        if (Test-Path $approvalFile) {
            $approvals = Get-Content $approvalFile -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            
            if ($approvals -and $approvals.PSObject.Properties[$GemMarket]) {
                $approval = $approvals.$GemMarket
                
                # Remover após consumir
                $approvals.PSObject.Properties.Remove($GemMarket)
                $approvals | ConvertTo-Json | Set-Content $approvalFile -Encoding UTF8

                Write-Host "[CALLBACK] Aprovação recebida para $GemMarket`: $($approval.approved)" -ForegroundColor Green
                return [PSCustomObject]@{
                    approved = $approval.approved
                    reason = $approval.reason
                    timestamp = $approval.timestamp
                }
            }
        }

        Start-Sleep -Seconds 5
    }

    Write-Host "[CALLBACK] Timeout aguardando aprovação para $GemMarket" -ForegroundColor Yellow
    return [PSCustomObject]@{
        approved = $false
        reason = "Timeout"
    }
}
