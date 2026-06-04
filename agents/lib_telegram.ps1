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
        # 2026-06-03: SEMPRE usar env vars first (config.local.ps1)
        if (-not $BotToken) { $BotToken = $env:TELEGRAM_BOT_TOKEN }
        if (-not $ChatId) { $ChatId = $env:TELEGRAM_CHAT_ID }

        # Fallback: telegram.json so se env vars nao definidas
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

        # parse_mode HTML: faz <b>/<code> renderizarem (antes apareciam crus).
        # UTF-8 explicito nos bytes: evita acentos/emojis quebrados (mojibake).
        $payload = @{
            chat_id    = $ChatId
            text       = $Message
            parse_mode = "HTML"
        }
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json))

        try {
            $response = Invoke-RestMethod -Uri $url -Method Post -Body $bodyBytes -ContentType "application/json; charset=utf-8"
        }
        catch {
            # Fallback: HTML invalido (ex: < ou & cru vindo de texto dinamico) faz a
            # API rejeitar com 400. Reenvia como texto puro para a msg nao se perder.
            Write-Host "[TELEGRAM] HTML rejeitado, reenviando texto puro" -ForegroundColor Yellow
            $plain = @{ chat_id = $ChatId; text = $Message }
            $plainBytes = [System.Text.Encoding]::UTF8.GetBytes(($plain | ConvertTo-Json))
            $response = Invoke-RestMethod -Uri $url -Method Post -Body $plainBytes -ContentType "application/json; charset=utf-8"
        }
        
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
        [Alias("BotToken")]
        [string]$Token = $env:TELEGRAM_BOT_TOKEN,

        [Parameter(Mandatory=$false)]
        [string]$ChatId = $env:TELEGRAM_CHAT_ID,

        [Parameter(Mandatory=$false)]
        [int]$DedupSeconds = 0,

        [Parameter(Mandatory=$false)]
        [string]$DedupStorePath = "",

        [Parameter(Mandatory=$false)]
        [string]$Enabled = "true"
    )

    if ($Enabled -ne "true")  { return $false }
    if (-not $Token)          { return $false }
    if (-not $ChatId)         { return $false }

    # Deduplicacao opcional
    if ($DedupSeconds -gt 0) {
        if ($DedupStorePath) {
            $store = Import-TgDedupStore -Path $DedupStorePath
            $isDup = Test-TelegramDuplicate -Message $Message -Store $store -TtlSeconds $DedupSeconds
            Export-TgDedupStore -Store $store -Path $DedupStorePath | Out-Null
            if ($isDup) { return $true }
        }
        else {
            if ($null -eq $global:TG_DEDUP_STORE) { $global:TG_DEDUP_STORE = @{} }
            if (Test-TelegramDuplicate -Message $Message -Store $global:TG_DEDUP_STORE -TtlSeconds $DedupSeconds) {
                return $true
            }
        }
    }

    try {
        $r = Telegram-SendMessage -Message $Message -BotToken $Token -ChatId $ChatId
        return ($r -and $r.success -eq $true)
    } catch {
        return $false
    }
}


# ============================================================================
# TG_EMOJI -- Hashtable global de emojis para mensagens Telegram
# ============================================================================
if (-not $global:TG_EMOJI) {
    $global:TG_EMOJI = @{
        alert  = "⚠️"
        check  = "✅"
        cross  = "❌"
        clock  = "⏰"
        chart  = "📈"
        money  = "💰"
        target = "🎯"
        stop   = "🛑"
        gem    = "💎"
        fire   = "🔥"
    }
}

# ============================================================================
# Format-TelegramMessage -- Formata gem para mensagem Telegram compacta
# ============================================================================
function Format-TelegramMessage {
    param(
        [Parameter(Mandatory=$true)] $Gem,
        [string]$MarketType = "FUTURES"
    )
    $market  = if ($Gem.market) { $Gem.market } else { "?" }
    $score   = if ($Gem.score)  { $Gem.score }  else { 0 }
    $mode    = if ($Gem.mode)   { $Gem.mode }   else { "DISCOVERY" }
    $spike   = if ($Gem.vol_data -and $Gem.vol_data.spike_ratio)      { "$([math]::Round($Gem.vol_data.spike_ratio,1))x" }      else { "N/A" }
    $chg     = if ($Gem.vol_data -and $Gem.vol_data.pct_change_today) { "$([math]::Round($Gem.vol_data.pct_change_today,1))%" } else { "N/A" }
    $sizeUsd = if ($Gem.sizing  -and $Gem.sizing.sizing_usd)          { "`$$([math]::Round($Gem.sizing.sizing_usd,2))" }         else { "N/A" }
    return "<b>$market</b> [$MarketType] Score:$score | $mode | Vol:$spike $chg | Size:$sizeUsd"
}

# ============================================================================
# Send-GemAlertWithLogo -- Envia alerta de gem com foto (logo) ou texto
# ============================================================================
function Send-GemAlertWithLogo {
    param(
        [Parameter(Mandatory=$true)] $Gem,
        [string]$Token   = $env:TELEGRAM_BOT_TOKEN,
        [string]$ChatId  = $env:TELEGRAM_CHAT_ID,
        [string]$Enabled = "true"
    )
    if ($Enabled -ne "true" -or -not $Token -or -not $ChatId) { return $false }
    $msg     = Format-TelegramMessage -Gem $Gem
    $logoUrl = if ($Gem.PSObject.Properties["logo_url"]) { $Gem.logo_url } else { $null }
    $baseUrl = "https://api.telegram.org/bot$Token"
    try {
        if ($logoUrl) {
            $body = @{ chat_id=$ChatId; photo=$logoUrl; caption=$msg } | ConvertTo-Json -Compress
            $r = Invoke-RestMethod -Uri "$baseUrl/sendPhoto" -Method POST -Body $body -ContentType "application/json" -ErrorAction Stop
        } else {
            $body = @{ chat_id=$ChatId; text=$msg } | ConvertTo-Json -Compress
            $r = Invoke-RestMethod -Uri "$baseUrl/sendMessage" -Method POST -Body $body -ContentType "application/json" -ErrorAction Stop
        }
        return ($r.ok -eq $true)
    } catch {
        if ($logoUrl) {
            try {
                $body2 = @{ chat_id=$ChatId; text=$msg } | ConvertTo-Json -Compress
                $r2 = Invoke-RestMethod -Uri "$baseUrl/sendMessage" -Method POST -Body $body2 -ContentType "application/json" -ErrorAction Stop
                return ($r2.ok -eq $true)
            } catch {}
        }
        return $false
    }
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

    # mcap formatado (ex: 1200000 → "1.2M")
    $mcapStr = ""
    if ($Gem.PSObject.Properties["mcap_usd"] -and $Gem.mcap_usd -gt 0) {
        $mcapStr = " | MCap: $([math]::Round($Gem.mcap_usd/1000000,2))M"
    }

    # gates_passed como "G1 G2 G3"
    $gatesStr = ""
    if ($Gem.PSObject.Properties["gates_passed"] -and $Gem.gates_passed) {
        $gatesStr = "`nGates: $($Gem.gates_passed -join ' ')"
    }

    $msg = "$modeEmoji <b>APROVAR$dryTag — $($Gem.market)</b> | Score: $($Gem.score)$mcapStr | Vol: $volSpike ↑$change24h`n💰 $sizeUsd | Stop: $stopPct | Target: $targetPct$gatesStr`n✅ Confirmar?"

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
        [Parameter(Mandatory=$true)]  $Gem,
        [Parameter(Mandatory=$true)]  [string]$GemId,
        [Parameter(Mandatory=$false)] [int]$TimeoutSeconds = 300,
        [Parameter(Mandatory=$false)] [int]$PollSeconds    = 5,
        [Parameter(Mandatory=$false)] [string]$Token       = $env:TELEGRAM_BOT_TOKEN,
        [Parameter(Mandatory=$false)] [string]$ChatId      = $env:TELEGRAM_CHAT_ID,
        [Parameter(Mandatory=$false)] [string]$Enabled     = "true",
        # Compat retroativa: aceita GemMarket (alias para GemId)
        [Parameter(Mandatory=$false)] [string]$GemMarket   = "",
        [Parameter(Mandatory=$false)] [string]$BotToken    = ""
    )
    if ($GemMarket -and -not $GemId) { $GemId = $GemMarket }
    if ($BotToken  -and -not $Token) { $Token  = $BotToken  }

    # Envia mensagem de aprovacao com inline keyboard
    $sent = Send-TgApprovalRequest -Gem $Gem -GemId $GemId -Token $Token -ChatId $ChatId -Enabled $Enabled
    if (-not $sent.ok) {
        return @{ decision="error"; from=$null; message_id=$null }
    }
    $msgId    = $sent.message_id
    $wasPhoto = $sent.was_photo
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastOffset = 0

    while ((Get-Date) -lt $deadline) {
        $updates = Receive-TelegramUpdates -Offset $lastOffset -Token $Token -Timeout ([math]::Min($PollSeconds, 5))
        foreach ($upd in @($updates)) {
            if ($upd.update_id -gt $lastOffset) { $lastOffset = $upd.update_id }
            $cb = $upd.callback_query
            if (-not $cb) { continue }
            $data = [string]$cb.data
            $from = if ($cb.from -and $cb.from.first_name) { $cb.from.first_name } else { "user" }
            if ($data -eq "approve:$GemId") {
                if (Get-Command Confirm-TgCallback -EA SilentlyContinue) { Confirm-TgCallback -CallbackId $cb.id -Text "Executando..." -Token $Token | Out-Null }
                if ($msgId -and (Get-Command Update-TgCaption -EA SilentlyContinue)) { Update-TgCaption -MessageId $msgId -Caption "APROVADO por $from" -WasPhoto:$wasPhoto -Token $Token -ChatId $ChatId | Out-Null }
                return @{ decision="approve"; from=$from; message_id=$msgId }
            }
            if ($data -eq "reject:$GemId") {
                if (Get-Command Confirm-TgCallback -EA SilentlyContinue) { Confirm-TgCallback -CallbackId $cb.id -Text "Cancelado." -Token $Token | Out-Null }
                if ($msgId -and (Get-Command Update-TgCaption -EA SilentlyContinue)) { Update-TgCaption -MessageId $msgId -Caption "CANCELADO por $from" -WasPhoto:$wasPhoto -Token $Token -ChatId $ChatId | Out-Null }
                return @{ decision="reject"; from=$from; message_id=$msgId }
            }
        }
        if ((Get-Date) -lt $deadline) { Start-Sleep -Seconds $PollSeconds }
    }
    return @{ decision="timeout"; from=$null; message_id=$msgId }
}

# ==============================================================================
# VISUAL HELPERS — badges, bars, emojis
# Implementado 2026-05-27: funções exigidas pelos testes tg_visual.Tests.ps1
# e chamadas por Format-TgEsquadraoResult / Format-TgCycleSummary / etc.
# ==============================================================================

function Get-TierBadge {
    param([string]$Tier)
    $t = $Tier.ToUpper()
    switch ($t) {
        "A"   { return "[A]" }
        "B"   { return "[B]" }
        "C"   { return "[C]" }
        "D"   { return "[D]" }
        "GEM" { return "[G]" }
        default { return $t }
    }
}

function Get-DirectionEmoji {
    param([string]$Direction)
    switch ($Direction.ToUpper()) {
        "LONG"  { return "^" }
        "SHORT" { return "v" }
        default { return "" }
    }
}

function Get-ConfidenceBar {
    param(
        [int]$Pct,
        [int]$Width = 10
    )
    $filled = [math]::Round($Pct / 100.0 * $Width)
    $empty  = $Width - $filled
    return ("#" * $filled) + ("." * $empty)
}

function Get-RegimeLabel {
    param([string]$Regime)
    switch ($Regime) {
        "BULL_STRONG"    { return "BULL+" }
        "BULL_WEAK"      { return "BULL~" }
        "BEAR_STRONG"    { return "BEAR+" }
        "BEAR_WEAK"      { return "BEAR~" }
        "TRANSITION_UP"  { return "TRANS^" }
        "TRANSITION_DOWN"{ return "TRANSv" }
        "SIDEWAYS"       { return "SIDE" }
        "CAPITULATION"   { return "CAPIT" }
        default          { return $Regime }
    }
}

# ==============================================================================
# Format-TgSystemStart — mensagem de boot do sistema
# ==============================================================================
function Format-TgSystemStart {
    param([switch]$DryRun)
    $mode = if ($DryRun) { "DRY RUN" } else { "LIVE" }
    $ts   = (Get-Date).ToString("dd/MM HH:mm")
    return "[SISTEMA LIGADO] $mode | $ts"
}

# ==============================================================================
# Format-HeartbeatMessage — heartbeat horario (ciclos sem novidade)
# ==============================================================================
function Format-HeartbeatMessage {
    param(
        [string]$Window      = "NEUTRAL",
        [int]   $NextMin     = 60,
        [string]$NextTime    = "",
        [int]   $WatchCount  = 0,
        [int]   $CyclesQuiet = 0,
        [switch]$DryRun
    )
    $modeTag = if ($DryRun) { " [DRY]" } else { "" }
    $quietStr = if ($CyclesQuiet -eq 1) { "1 ciclo sem novidade" } else { "$CyclesQuiet ciclos sem novidade" }
    return "[HEARTBEAT]$modeTag $Window | $WatchCount pares | $quietStr | prox ${NextMin}min ($NextTime)"
}

# ==============================================================================
# Format-TgEsquadraoResult — resultado de um par no orchestrator V6
# Chamado em orchestrator_v6.ps1 quando cascade.telegramFire = true
# ==============================================================================
function Format-TgEsquadraoResult {
    param(
        [string]       $Market,
        [PSCustomObject]$Triagem  = $null,
        [PSCustomObject]$Mesa     = $null,
        [PSCustomObject]$Mentor   = $null,
        [string]       $Decisao  = "ABORTAR",
        [string]       $Regime   = "",
        [double]       $Score    = 0,
        [string]       $Direction = ""
    )

    $isExec    = $Decisao -in @("EXECUTAR","STRONG_EXECUTAR","DRY_RUN_EXECUTAR")
    $isDry     = $Decisao -eq "DRY_RUN_EXECUTAR"
    $isStrong  = $Decisao -eq "STRONG_EXECUTAR"

    # Linha de decisão
    $decLabel = switch ($Decisao) {
        "EXECUTAR"         { "EXECUTAR" }
        "STRONG_EXECUTAR"  { "STRONG EXECUTAR" }
        "DRY_RUN_EXECUTAR" { "EXECUTAR (simulado)" }
        "REVISAR"          { "REVISAR" }
        "ABORTAR"          { "ABORTAR" }
        "HARD_VETO"        { "HARD VETO" }
        default            { $Decisao }
    }

    $decIcon = if ($isExec) { "[OK]" } elseif ($Decisao -eq "REVISAR") { "[?]" } else { "[X]" }
    $strongTag = if ($isStrong) { " 1.5x" } else { "" }
    $dryTag    = if ($isDry)    { " [SIM]" } else { "" }

    # Tier badge
    $tierStr = if ($Triagem -and $Triagem.tier) { Get-TierBadge -Tier $Triagem.tier } else { "" }
    $scoreStr = if ($Triagem -and $Triagem.score_predicted) { "score=$($Triagem.score_predicted)" } else { "" }

    # Mesa consensus
    $mesaStr = ""
    if ($Mesa -and $Mesa.consensus) {
        $mesaStr = "Mesa:$($Mesa.consensus)"
        if ($Mesa.sinal_consenso) { $mesaStr += "/$($Mesa.sinal_consenso)" }
    }

    # Mentor
    $mentorStr = ""
    $mentorBar = ""
    if ($Mentor) {
        $conf = if ($Mentor.PSObject.Properties['confianca']) { [int]$Mentor.confianca }
                elseif ($Mentor.PSObject.Properties['confianca_mentor']) { [int]$Mentor.confianca_mentor }
                else { 0 }
        $mentorBar = Get-ConfidenceBar -Pct $conf -Width 8
        $mentorMsg = if ($Mentor.PSObject.Properties['mentor_mensagem'] -and $Mentor.mentor_mensagem) {
            $raw = [string]$Mentor.mentor_mensagem
            $maxLen = if ($global:TG_FORMAT_MODE -eq "compact") { 90 } else { 240 }
            if ($raw.Length -gt $maxLen) { $raw.Substring(0, $maxLen) + "..." } else { $raw }
        } else { "" }
        $mentorStr = "Mentor($conf%) [$mentorBar] $mentorMsg"
    }

    # Regime
    $regStr = if ($Regime) { Get-RegimeLabel -Regime $Regime } else { "" }
    $dirEmoji = Get-DirectionEmoji -Direction $Direction

    # Monta mensagem
    $lines = @()
    $header = "$decIcon $Market $tierStr $scoreStr$strongTag$dryTag"
    if ($regStr)   { $header += " | $regStr" }
    if ($dirEmoji) { $header += " $dirEmoji" }
    $lines += $header
    $lines += "$decLabel"
    if ($mesaStr)  { $lines += $mesaStr }
    if ($mentorStr){ $lines += $mentorStr }

    return $lines -join "`n"
}

# ==============================================================================
# Format-TgCycleSummary — resumo de ciclo enviado ao Telegram
# Chamado no final de Invoke-MasterCycle
# ==============================================================================
function Format-TgCycleSummary {
    param(
        [string]$Window       = "NEUTRAL",
        [int]   $MomentScore  = 50,
        [string]$TrailSummary = "nenhuma posicao ativa",
        [string]$GemSummary   = "nenhum",
        [string]$ScanSummary  = "",
        [string]$OrchSummary  = "",
        [int]   $NextMin      = 60,
        [string]$NextTime     = "",
        [int]   $ElapsedSec   = 0,
        [switch]$DryRun
    )

    $ts      = (Get-Date).ToString("HH:mm")
    $dryTag  = if ($DryRun) { " [DRY]" } else { "" }
    $bar     = Get-ConfidenceBar -Pct $MomentScore -Width 10

    # Conta exec vs abort no OrchSummary
    $nExec  = ([regex]::Matches($OrchSummary, "EXECUTAR\(\)")).Count
    $nAbort = ([regex]::Matches($OrchSummary, "ABORTAR\(\)")).Count

    $compact = ($global:TG_FORMAT_MODE -eq "compact")

    $lines = @()
    $lines += "CICLO$dryTag | janela=$Window | $ts"
    $lines += "momento: [$bar] $MomentScore/100"

    if (-not $compact) {
        if ($GemSummary -and $GemSummary -ne "nenhum") {
            $lines += "gems: $GemSummary"
        }
        if ($ScanSummary) {
            $lines += "scan: $ScanSummary"
        }
        if ($OrchSummary) {
            # Contador sempre visível mesmo no verbose
            $lines += "$nExec exec | $nAbort abort"
            # Mostra linha por par
            $orchLines = $OrchSummary -split "\s*\|\s*" | Where-Object { $_.Trim() }
            foreach ($ol in $orchLines) { $lines += "  $($ol.Trim())" }
        }
    } else {
        # Compact: só contadores
        $lines += "$nExec exec | $nAbort abort"
        if ($GemSummary -and $GemSummary -ne "nenhum") { $lines += "gems: $GemSummary" }
    }

    $lines += "trail: $TrailSummary"
    $lines += "Proximo: ${NextMin}min ($NextTime)"

    return $lines -join "`n"
}

# ==============================================================================
# Send-TelegramAlertFiltered — Envia com filtro por tier de importância
# 2026-06-01: Reduzir ruído filtrando mensagens por tier
# ==============================================================================
function Send-TelegramAlertFiltered {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("CRITICAL", "IMPORTANT", "INFORMATIVE", "DEBUG")]
        [string]$Tier = "CRITICAL",
        
        [Parameter(Mandatory=$false)]
        [int]$DedupSeconds = 0,
        
        [Parameter(Mandatory=$false)]
        [string]$DedupStorePath = ""
    )
    
    # Verificar se deve enviar baseado no tier
    $shouldSend = switch ($Tier) {
        "CRITICAL"     { $global:TELEGRAM_SEND_CRITICAL }
        "IMPORTANT"    { $global:TELEGRAM_SEND_IMPORTANT }
        "INFORMATIVE"  { $global:TELEGRAM_SEND_INFORMATIVE }
        "DEBUG"        { $global:TELEGRAM_SEND_DEBUG }
        default        { $true }
    }
    
    if (-not $shouldSend) {
        Write-Verbose "[TELEGRAM] Mensagem $Tier filtrada (modo=$global:TELEGRAM_FILTER_MODE)"
        return [PSCustomObject]@{
            success = $true
            skipped = $true
            reason = "filtered_by_tier_$Tier"
        }
    }
    
    # Enviar com dedup se configurado
    if ($DedupSeconds -gt 0) {
        return Send-TelegramAlert -Message $Message -DedupSeconds $DedupSeconds -DedupStorePath $DedupStorePath
    } else {
        return Send-TelegramAlert -Message $Message
    }
}

# ==============================================================================
# Send-HeartbeatIfDue — envia heartbeat se passou o intervalo configurado
# Chamado em scan_master quando ciclo nao tem novidades
# ==============================================================================
function Send-HeartbeatIfDue {
    param(
        [string]$LastHeartbeatFile = "",
        [int]   $IntervalMinutes   = 60,
        [string]$Window            = "NEUTRAL",
        [int]   $NextMin           = 60,
        [string]$NextTime          = "",
        [int]   $WatchCount        = 0,
        [int]   $CyclesQuiet       = 0,
        [switch]$DryRun,
        [bool]  $Enabled           = $true
    )

    if (-not $Enabled) { return $false }

    # 2026-06-01: Usar intervalo da configuração (default 360 min = 6h)
    $interval = if ($global:TELEGRAM_HEARTBEAT_INTERVAL_MIN) {
        $global:TELEGRAM_HEARTBEAT_INTERVAL_MIN
    } else {
        $IntervalMinutes
    }

    # Verifica se passou o intervalo desde o ultimo heartbeat
    if ($LastHeartbeatFile -and (Test-Path $LastHeartbeatFile)) {
        $lastAge = ((Get-Date) - (Get-Item $LastHeartbeatFile).LastWriteTime).TotalMinutes
        if ($lastAge -lt $interval) { return $false }
    }

    # Monta e envia
    $msg = Format-HeartbeatMessage `
        -Window $Window -NextMin $NextMin -NextTime $NextTime `
        -WatchCount $WatchCount -CyclesQuiet $CyclesQuiet -DryRun:$DryRun

    # Dedup persistente: heartbeats identicos nao sao reenviados mesmo apos restart
    # do daemon. Store em journal/tg_dedup_heartbeat.json.
    $hbDedupPath = Join-Path $PSScriptRoot "..\journal\tg_dedup_heartbeat.json"
    $result = Send-TelegramAlert -Message $msg -DedupSeconds 3600 -DedupStorePath $hbDedupPath
    if ($result -and $LastHeartbeatFile) {
        # Atualiza timestamp do ultimo heartbeat
        $dir = Split-Path $LastHeartbeatFile
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        (Get-Date).ToString("o") | Set-Content $LastHeartbeatFile -Encoding UTF8
    }
    return $true
}

# ==============================================================================
# Format-TgStatusSnapshot — versão melhorada do STATUS SNAPSHOT
# Substitui o texto plano do watch_status.ps1 por mensagem estruturada
# ==============================================================================
function Format-TgStatusSnapshot {
    param(
        [array] $Drawdowns    = @(),
        [int]   $NDecisions   = 0,
        [int]   $NAprovar     = 0,
        [int]   $NVetar       = 0,
        [int]   $NHalluc      = 0,
        [hashtable]$Daemons   = @{},
        [string]$Mode         = "PAPER",
        [int]   $NOutcomes    = 0,
        [bool]  $KellyActive  = $false,
        [hashtable]$LlmStatus = @{},
        [string]$BtcDD        = "",
        [array] $ToriRipening = @()
    )

    $ts = (Get-Date).ToString("dd/MM HH:mm")
    $lines = @()
    $lines += "[STATUS $ts]"

    # BTC
    if ($BtcDD) { $lines += "BTC DD: $BtcDD%" }

    # Drawdown
    if ($Drawdowns.Count -gt 0) {
        $lines += "--- Posicoes ---"
        foreach ($d in $Drawdowns) {
            $icon = switch ($d.status) { "CRITICAL" { "[!!]" } "FLAGGED" { "[!]" } default { "[OK]" } }
            $lines += "$icon $($d.market) $($d.vs_peak_pct)%"
        }
    }

    # Decisoes
    $aprovRate = if ($NDecisions -gt 0) { [math]::Round($NAprovar / $NDecisions * 100) } else { 0 }
    $bar = Get-ConfidenceBar -Pct $aprovRate -Width 8
    $lines += "--- Decisoes 24h ---"
    $lines += "Total: $NDecisions | APROV: $NAprovar | VETO: $NVetar"
    $lines += "Taxa: [$bar] $aprovRate%"
    if ($NHalluc -gt 0) { $lines += "WARN hallucinations: $NHalluc" }

    # LLM
    if ($LlmStatus.Count -gt 0) {
        $llmLine = "LLM: "
        $llmLine += "Haiku=$(if ($LlmStatus['haiku']) { $LlmStatus['haiku'] } else { '?' }) "
        $llmLine += "Groq=$(if ($LlmStatus['groq']) { $LlmStatus['groq'] } else { '?' }) "
        $llmLine += "Gemini=$(if ($LlmStatus['gemini']) { $LlmStatus['gemini'] } else { '?' })"
        $lines += $llmLine
    }

    # Daemons
    if ($Daemons.Count -gt 0) {
        $lines += "--- Daemons ---"
        foreach ($k in @("scan_master","gem_loop","tg_listener","watchdog_paper")) {
            if ($Daemons.ContainsKey($k)) {
                $s = $Daemons[$k]
                $icon = if ($s.alive) { "[ON]" } else { "[OFF]" }
                $lines += "$icon $k"
            }
        }
    }

    # TORI
    if ($ToriRipening.Count -gt 0) {
        $lines += "--- TORI Ripening ---"
        foreach ($t in $ToriRipening) { $lines += ">> $t" }
    }

    # Kelly
    $kellyBar = Get-ConfidenceBar -Pct ([math]::Min(100, $NOutcomes * 10)) -Width 10
    $lines += "--- Kelly ---"
    $lines += "[$kellyBar] $NOutcomes/10 trades"
    if ($KellyActive) { $lines += "Kelly ATIVO" }

    # Modo
    $lines += "Modo: $Mode"

    return $lines -join "`n"
}

# ==============================================================================
# QUALIDADE DE MENSAGENS (2026-05-29)
# Resolve 3 problemas observados em producao:
#   1. Tags HTML cruas / caracteres especiais quebrados (faltava parse_mode+escape)
#   2. Mensagens repetidas reenviadas sem acao (faltava deduplicacao)
#   3. Trade aberto sem destaque (mensagem generica)
# ==============================================================================

# ------------------------------------------------------------------------------
# Format-TelegramText -- escapa caracteres reservados de HTML para uso seguro
# com parse_mode="HTML". Deve ser aplicado em VALORES dinamicos (nao na msg toda,
# senao escaparia as proprias tags <b>). Ordem importa: & primeiro.
# ------------------------------------------------------------------------------
function Format-TelegramText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$Text
    )
    if ($null -eq $Text) { return "" }
    $t = $Text -replace '&', '&amp;'
    $t = $t -replace '<', '&lt;'
    $t = $t -replace '>', '&gt;'
    return $t
}

# ------------------------------------------------------------------------------
# Import-TgDedupStore / Export-TgDedupStore -- persistencia do store de dedup em
# JSON. Permite que a deduplicacao sobreviva a restart do daemon (antes era
# apenas in-memory por processo). Formato: { hash: "ISO8601 datetime", ... }.
# Falhas de IO sao tolerantes (fail-open): retorna store vazio / nao quebra envio.
# ------------------------------------------------------------------------------
function Import-TgDedupStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    $store = @{}
    if (-not (Test-Path $Path)) { return $store }
    try {
        $raw = Get-Content $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $store }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        foreach ($prop in $obj.PSObject.Properties) {
            [datetime]$dt = [datetime]::MinValue
            if ([datetime]::TryParse([string]$prop.Value, [ref]$dt)) {
                $store[$prop.Name] = $dt
            }
        }
    }
    catch {
        Write-Verbose "[TG DEDUP] Falha ao ler store ($Path): $_"
    }
    return $store
}

function Export-TgDedupStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Store,

        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    try {
        $dir = Split-Path $Path -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $obj = [ordered]@{}
        foreach ($k in $Store.Keys) {
            $v = $Store[$k]
            $obj[$k] = if ($v -is [datetime]) { $v.ToString("o") } else { [string]$v }
        }
        ($obj | ConvertTo-Json) | Set-Content -Path $Path -Encoding UTF8 -ErrorAction Stop
        return $true
    }
    catch {
        Write-Verbose "[TG DEDUP] Falha ao gravar store ($Path): $_"
        return $false
    }
}

# ------------------------------------------------------------------------------
# Test-TelegramDuplicate -- retorna $true se a mensagem (por hash) ja foi enviada
# dentro do TTL. Caso contrario registra no store e retorna $false.
# $Store: hashtable [hash -> datetime do ultimo envio]. Mantida pelo caller
# (in-memory por processo) ou persistida em JSON pelo daemon.
# ------------------------------------------------------------------------------
function Test-TelegramDuplicate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$true)]
        [hashtable]$Store,

        [Parameter(Mandatory=$false)]
        [int]$TtlSeconds = 300
    )

    # Hash estavel da mensagem (MD5 do texto normalizado)
    $normalized = ($Message -replace '\s+', ' ').Trim()
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $hash = [System.BitConverter]::ToString($md5.ComputeHash($bytes)) -replace '-', ''
    $md5.Dispose()

    $now = Get-Date

    # Limpa entradas expiradas (mantem store pequeno)
    $expiredKeys = @()
    foreach ($k in $Store.Keys) {
        if (($now - $Store[$k]).TotalSeconds -gt $TtlSeconds) { $expiredKeys += $k }
    }
    foreach ($k in $expiredKeys) { $Store.Remove($k) }

    if ($Store.ContainsKey($hash)) {
        $age = ($now - $Store[$hash]).TotalSeconds
        if ($age -le $TtlSeconds) {
            return $true   # duplicada dentro do TTL
        }
    }

    $Store[$hash] = $now
    return $false
}

# ------------------------------------------------------------------------------
# Format-TgTradeOpenedHighlight -- mensagem de ABERTURA DE TRADE em destaque.
# HTML parse_mode; valores dinamicos escapados. Pensada para ser impossivel de
# passar despercebida (cabecalho forte + dados-chave).
# ------------------------------------------------------------------------------
function Format-TgTradeOpenedHighlight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Trade
    )

    $sideRaw  = "$($Trade.side)"
    $isLong   = $sideRaw -match '(?i)long'
    $sideIcon = if ($isLong) { "[LONG]" } else { "[SHORT]" }
    $arrow    = if ($isLong) { "+" } else { "-" }

    $mkt   = Format-TelegramText -Text "$($Trade.market)"
    $entry = Format-TelegramText -Text "$($Trade.entry_price)"
    $sl    = Format-TelegramText -Text "$($Trade.stop_loss)"
    $tp    = Format-TelegramText -Text "$($Trade.take_profit)"
    $size  = Format-TelegramText -Text "$($Trade.size)"

    $lev   = if ($Trade.leverage)  { " | " + (Format-TelegramText -Text "$($Trade.leverage)x") } else { "" }
    $cap   = if ($Trade.capital)   { Format-TelegramText -Text "$($Trade.capital)" } else { "" }
    $stopPct   = if ($null -ne $Trade.stop_pct)   { Format-TelegramText -Text "$($Trade.stop_pct)" }   else { "" }
    $targetPct = if ($null -ne $Trade.target_pct) { Format-TelegramText -Text "$($Trade.target_pct)" } else { "" }

    $lines = @()
    $lines += "🟢🟢🟢 <b>TRADE ABERTO</b> 🟢🟢🟢"
    $lines += "$sideIcon <b>$mkt</b>$lev"
    $lines += "Entry: <code>$entry</code> | Size: <code>$size</code>"
    $slLine = "🛑 Stop: <code>$sl</code>"
    if ($stopPct)   { $slLine += " (-$stopPct%)" }
    $lines += $slLine
    $tpLine = "🎯 Target: <code>$tp</code>"
    if ($targetPct) { $tpLine += " ($arrow$targetPct%)" }
    $lines += $tpLine
    if ($cap) { $lines += "💰 Capital: <code>`$$cap</code>" }

    return ($lines -join "`n")
}

# ============================================================================
# New-TgApprovalKeyboard - Inline keyboard para aprovacao de GEM
# ============================================================================
function New-TgApprovalKeyboard {
    param([Parameter(Mandatory=$true)][string]$GemId)
    # Unary comma (,) preserva o array nested — sem isso PS5.1 unwraps e vira flat
    $row = @(
        @{ text = "EXECUTAR"; callback_data = "approve:$GemId" },
        @{ text = "CANCELAR"; callback_data = "reject:$GemId"  }
    )
    return @{ inline_keyboard = @(,$row) }
}

# ============================================================================
# Send-TgApprovalRequest - Envia mensagem de aprovacao com inline keyboard
# ============================================================================
function Send-TgApprovalRequest {
    param(
        [Parameter(Mandatory=$true)]  $Gem,
        [Parameter(Mandatory=$true)]  [string]$GemId,
        [Parameter(Mandatory=$true)]  [string]$Token,
        [Parameter(Mandatory=$true)]  [string]$ChatId,
        [Parameter(Mandatory=$false)] [string]$Enabled = "true"
    )
    if ($Enabled -ne "true") {
        return @{ ok=$false; message_id=$null; was_photo=$false }
    }
    $kb = New-TgApprovalKeyboard -GemId $GemId
    $replyMarkup = $kb | ConvertTo-Json -Depth 5 -Compress
    $logoUrl = if ($Gem.PSObject.Properties["logo_url"]) { $Gem.logo_url } else { $null }
    $baseUrl = "https://api.telegram.org/bot$Token"
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $score = if ($Gem.score) { $Gem.score } else { 0 }
    $mode  = if ($Gem.mode)  { $Gem.mode }  else { "DISCOVERY" }
    $caption = "GEM: $($Gem.market) | Score: $score | Modo: $mode`nAprovar execucao?"
    $bodyMsg = @{ chat_id=$ChatId; text=$caption; reply_markup=$replyMarkup } | ConvertTo-Json -Compress
    try {
        if ($logoUrl) {
            $bodyPhoto = @{ chat_id=$ChatId; photo=$logoUrl; caption=$caption; reply_markup=$replyMarkup } | ConvertTo-Json -Compress
            $r = Invoke-RestMethod -Uri "$baseUrl/sendPhoto" -Method POST -Body $bodyPhoto -ContentType "application/json; charset=utf-8" -ErrorAction Stop
            if ($r.ok) { return @{ ok=$true; message_id=$r.result.message_id; was_photo=$true } }
            # sendPhoto retornou ok=false — fallback para sendMessage
            $r2 = Invoke-RestMethod -Uri "$baseUrl/sendMessage" -Method POST -Body $bodyMsg -ContentType "application/json; charset=utf-8" -ErrorAction Stop
            if ($r2.ok) { return @{ ok=$true; message_id=$r2.result.message_id; was_photo=$false } }
            return @{ ok=$false; message_id=$null; was_photo=$false }
        } else {
            $r = Invoke-RestMethod -Uri "$baseUrl/sendMessage" -Method POST -Body $bodyMsg -ContentType "application/json; charset=utf-8" -ErrorAction Stop
            if ($r.ok) { return @{ ok=$true; message_id=$r.result.message_id; was_photo=$false } }
            return @{ ok=$false; message_id=$null; was_photo=$false }
        }
    } catch {
        # sendPhoto threw — fallback para sendMessage
        if ($logoUrl) {
            try {
                $r2 = Invoke-RestMethod -Uri "$baseUrl/sendMessage" -Method POST -Body $bodyMsg -ContentType "application/json; charset=utf-8" -ErrorAction Stop
                if ($r2.ok) { return @{ ok=$true; message_id=$r2.result.message_id; was_photo=$false } }
            } catch {}
        }
        return @{ ok=$false; message_id=$null; was_photo=$false }
    }
}

# ============================================================================
# Confirm-TgCallback - Confirma callback_query (evita loading spinner no bot)
# ============================================================================
function Confirm-TgCallback {
    param(
        [Parameter(Mandatory=$true)]  [string]$CallbackId,
        [Parameter(Mandatory=$false)] [string]$Text  = "",
        [Parameter(Mandatory=$false)] [string]$Token = $env:TELEGRAM_BOT_TOKEN
    )
    if (-not $Token) { return $false }
    try {
        $body = @{ callback_query_id=$CallbackId; text=$Text } | ConvertTo-Json -Compress
        $r = Invoke-RestMethod -Uri "https://api.telegram.org/bot$Token/answerCallbackQuery" -Method POST -Body $body -ContentType "application/json" -ErrorAction Stop
        return ($r.ok -eq $true)
    } catch { return $false }
}

# ============================================================================
# Update-TgCaption - Edita caption/texto de mensagem existente
# ============================================================================
function Update-TgCaption {
    param(
        [Parameter(Mandatory=$true)]  [long]$MessageId,
        [Parameter(Mandatory=$true)]  [string]$Caption,
        [switch]$WasPhoto,
        [Parameter(Mandatory=$false)] [string]$Token  = $env:TELEGRAM_BOT_TOKEN,
        [Parameter(Mandatory=$false)] [string]$ChatId = $env:TELEGRAM_CHAT_ID
    )
    if (-not $Token -or -not $ChatId) { return $false }
    $endpoint = if ($WasPhoto) { "editMessageCaption" } else { "editMessageText" }
    $bodyKey  = if ($WasPhoto) { "caption" } else { "text" }
    try {
        $body = @{ chat_id=$ChatId; message_id=$MessageId; $bodyKey=$Caption } | ConvertTo-Json -Compress
        $r = Invoke-RestMethod -Uri "https://api.telegram.org/bot$Token/$endpoint" -Method POST -Body $body -ContentType "application/json" -ErrorAction Stop
        return ($r.ok -eq $true)
    } catch { return $false }
}

# ============================================================================
# Receive-TelegramUpdates - Polling de updates (wrapper testavel)
# ============================================================================
function Receive-TelegramUpdates {
    param(
        [long]  $Offset  = 0,
        [string]$Token   = $env:TELEGRAM_BOT_TOKEN,
        [int]   $Timeout = 5
    )
    try {
        $r = Invoke-RestMethod -Uri "https://api.telegram.org/bot$Token/getUpdates?offset=$($Offset+1)&timeout=$Timeout" -Method GET -ErrorAction Stop
        if ($r.ok) { return $r.result } else { return @() }
    } catch { return @() }
}
