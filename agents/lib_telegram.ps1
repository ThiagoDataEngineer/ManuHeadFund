# lib_telegram.ps1 — Alertas + comandos interativos via Telegram
# Bot: @coinex_gemagent_bot
# Dot-source: . "$PSScriptRoot\lib_telegram.ps1"

$global:TELEGRAM_API_BASE  = "https://api.telegram.org"
$global:TG_UPDATE_OFFSET   = 0   # offset compartilhado entre aprovacao e comandos

# Linha separadora simples (sem Unicode para compatibilidade PS5)
$TG_SEP = "- - - - - - - - - - - - - - - - - -"

# Emojis via Unicode escape — safe para PS5.1 ASCII source files
$global:TG_EMOJI = @{
    alert   = [char]::ConvertFromUtf32(0x1F6A8)   # rotating light
    check   = [char]::ConvertFromUtf32(0x2705)    # green check
    cross   = [char]::ConvertFromUtf32(0x274C)    # red X
    clock   = [char]::ConvertFromUtf32(0x23F1)    # stopwatch
    chart   = [char]::ConvertFromUtf32(0x1F4CA)   # bar chart
    money   = [char]::ConvertFromUtf32(0x1F4B0)   # money bag
    target  = [char]::ConvertFromUtf32(0x1F3AF)   # bullseye
    stop    = [char]::ConvertFromUtf32(0x1F6D1)   # stop sign
    gem     = [char]::ConvertFromUtf32(0x1F48E)   # gem
    fire    = [char]::ConvertFromUtf32(0x1F525)   # fire
    heart   = [char]::ConvertFromUtf32(0x1F49A)   # green heart
    rocket  = [char]::ConvertFromUtf32(0x1F680)   # rocket
    chartUp = [char]::ConvertFromUtf32(0x1F4C8)   # chart up
    chartDn = [char]::ConvertFromUtf32(0x1F4C9)   # chart down
    up      = [char]::ConvertFromUtf32(0x2197)    # arrow up
    down    = [char]::ConvertFromUtf32(0x2198)    # arrow down
    robot   = [char]::ConvertFromUtf32(0x1F916)   # robot (sistema trabalhando)
    search  = [char]::ConvertFromUtf32(0x1F50D)   # magnifying glass (scan)
    gear    = [char]::ConvertFromUtf32(0x2699)    # gear (orchestrator/processing)
    brain   = [char]::ConvertFromUtf32(0x1F9E0)   # brain (mentor)
    bulb    = [char]::ConvertFromUtf32(0x1F4A1)   # bulb (insight)
    sun     = [char]::ConvertFromUtf32(0x2600)    # sun (BULL)
    moon    = [char]::ConvertFromUtf32(0x1F319)   # moon (NEUTRAL/sideways)
    snow    = [char]::ConvertFromUtf32(0x2744)    # snowflake (BEAR/cold)
    light   = [char]::ConvertFromUtf32(0x1F50B)   # battery (vivo)
    pulse   = [char]::ConvertFromUtf32(0x1F4E1)   # satellite (monitoring)
    # 2026-05-23 Tier 2 Block 1: SHORT direction emojis
    longArrow  = [char]::ConvertFromUtf32(0x1F535)   # blue circle (LONG)
    shortArrow = [char]::ConvertFromUtf32(0x1F534)   # red circle (SHORT)
    bear       = [char]::ConvertFromUtf32(0x1F43B)   # bear face (SHORT semantic)
}

# Tier badges (visual identification)
$global:TG_TIER_EMOJI = @{
    "A" = [char]::ConvertFromUtf32(0x1F7E2)   # green circle
    "B" = [char]::ConvertFromUtf32(0x1F7E1)   # yellow circle
    "C" = [char]::ConvertFromUtf32(0x1F7E0)   # orange circle
    "D" = [char]::ConvertFromUtf32(0x1F534)   # red circle
}

# Format mode: "verbose" (default) ou "compact"
if ($null -eq $global:TG_FORMAT_MODE) { $global:TG_FORMAT_MODE = "verbose" }

function Get-WindowEmoji {
    param([string]$Window)
    $e = $global:TG_EMOJI
    if ($Window -match "BULL|BUY|PUMP") { return $e.sun }
    if ($Window -match "BEAR|SELL|DUMP") { return $e.snow }
    return $e.moon
}

function Get-TierBadge {
    param([string]$Tier)
    $t = ($Tier + "").Trim().ToUpper()
    if ($global:TG_TIER_EMOJI.ContainsKey($t)) {
        return "$($global:TG_TIER_EMOJI[$t]) $t"
    }
    return $t
}

function Get-DirectionEmoji {
    param([string]$Direction)
    $e = $global:TG_EMOJI
    $d = ($Direction + "").Trim().ToUpper()
    if ($d -eq "LONG"  -or $d -eq "COMPRA") { return $e.chartUp }
    if ($d -eq "SHORT" -or $d -eq "VENDA")  { return $e.chartDn }
    return ""
}

function Get-ConfidenceBar {
    param([int]$Pct, [int]$Width = 10)
    if ($Pct -lt 0) { $Pct = 0 }
    if ($Pct -gt 100) { $Pct = 100 }
    $filled = [math]::Floor($Width * $Pct / 100)
    $empty  = $Width - $filled
    return ("#" * $filled) + ("." * $empty)
}

# ─────────────────────────────────────────────────────────────────────────────
# Receive-TelegramUpdates  (nivel baixo — compartilhado)
# Busca proximas atualizacoes e avanca o offset global.
# ─────────────────────────────────────────────────────────────────────────────
function Receive-TelegramUpdates {
    param(
        [int]    $Limit   = 20,
        [int]    $Timeout = 0,
        [string] $Token   = $env:TELEGRAM_BOT_TOKEN
    )
    if (-not $Token) { return @() }
    try {
        $uri  = "$global:TELEGRAM_API_BASE/bot$Token/getUpdates?offset=$global:TG_UPDATE_OFFSET&limit=$Limit&timeout=$Timeout"
        $upds = (Invoke-RestMethod -Uri $uri -Method GET -ErrorAction Stop).result
        if ($upds -and @($upds).Count -gt 0) {
            $global:TG_UPDATE_OFFSET = @($upds)[-1].update_id + 1
        }
        return $upds
    } catch { return @() }
}

# ─────────────────────────────────────────────────────────────────────────────
# Initialize-TelegramOffset
# Chama no startup para ignorar mensagens antigas.
# ─────────────────────────────────────────────────────────────────────────────
function Initialize-TelegramOffset {
    param([string] $Token = $env:TELEGRAM_BOT_TOKEN)
    if (-not $Token) { return }
    try {
        $uri  = "$global:TELEGRAM_API_BASE/bot$Token/getUpdates?limit=1&offset=-1"
        $init = Invoke-RestMethod -Uri $uri -Method GET -ErrorAction Stop
        if ($init.result -and @($init.result).Count -gt 0) {
            $global:TG_UPDATE_OFFSET = @($init.result)[-1].update_id + 1
        }
        Write-Host "  [Telegram] Offset inicializado em $global:TG_UPDATE_OFFSET" -ForegroundColor DarkGray
    } catch {}
}

# ─────────────────────────────────────────────────────────────────────────────
# Send-TelegramAlert
# ─────────────────────────────────────────────────────────────────────────────
function Send-TelegramAlert {
    param(
        [Parameter(Mandatory)] [string] $Message,
        [string] $Token   = $env:TELEGRAM_BOT_TOKEN,
        [string] $ChatId  = $env:TELEGRAM_CHAT_ID,
        [string] $Enabled = $env:TELEGRAM_ENABLED
    )
    if ($Enabled -ne "true")  { return $false }
    if (-not $Token)          { return $false }
    if (-not $ChatId)         { return $false }
    try {
        $uri  = "$global:TELEGRAM_API_BASE/bot$Token/sendMessage"
        $body = @{ chat_id = $ChatId; text = $Message; parse_mode = "HTML" }
        $r = Invoke-RestMethod -Uri $uri -Method POST -Body $body -ErrorAction Stop
        return ($r.ok -eq $true)
    } catch {
        Write-Host "  [Telegram] Falha ao enviar alerta: $_" -ForegroundColor DarkRed
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Wait-TelegramApproval
# Envia pergunta e aguarda resposta ok/nao. Usa offset global compartilhado.
# ─────────────────────────────────────────────────────────────────────────────
function Wait-TelegramApproval {
    param(
        [Parameter(Mandatory)] [string] $Message,
        [int]    $TimeoutSeconds = 300,
        [int]    $PollSeconds    = 4,
        [string] $Token   = $env:TELEGRAM_BOT_TOKEN,
        [string] $ChatId  = $env:TELEGRAM_CHAT_ID,
        [string] $Enabled = $env:TELEGRAM_ENABLED
    )

    if ($Enabled -ne "true" -or -not $Token -or -not $ChatId) {
        Write-Host "  [Telegram] Aprovacao indisponivel — fallback Read-Host" -ForegroundColor DarkYellow
        $r = Read-Host "  $Message`n  Digite EXECUTAR para confirmar"
        return ($r -eq "EXECUTAR")
    }

    $APPROVE_WORDS = @("ok","sim","yes","go","executar","s","y")
    $REJECT_WORDS  = @("nao","no","cancel","cancelar","skip","n")

    Send-TelegramAlert -Message $Message -Token $Token -ChatId $ChatId -Enabled $Enabled | Out-Null

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    Write-Host "  [Telegram] Aguardando aprovacao ($([int]($TimeoutSeconds/60))min)..." -ForegroundColor Yellow

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $PollSeconds

        $updates = Receive-TelegramUpdates -Limit 10 -Token $Token

        foreach ($upd in @($updates)) {
            $msgChatId = if ($upd.message) { "$($upd.message.chat.id)" } else { "" }
            if ($msgChatId -ne $ChatId) { continue }

            $text = $upd.message.text.Trim().ToLower()
            if (-not $text) { continue }

            if ($APPROVE_WORDS -contains $text) {
                $who = $upd.message.from.first_name
                Write-Host "  [Telegram] APROVADO por $who" -ForegroundColor Green
                Send-TelegramAlert -Message "<b>OK</b> - Aprovado por $who. Executando..." -Token $Token -ChatId $ChatId -Enabled $Enabled | Out-Null
                return $true
            }
            if ($REJECT_WORDS -contains $text) {
                $who = $upd.message.from.first_name
                Write-Host "  [Telegram] REJEITADO por $who" -ForegroundColor Red
                Send-TelegramAlert -Message "<b>Cancelado</b> por $who" -Token $Token -ChatId $ChatId -Enabled $Enabled | Out-Null
                return $false
            }
            # Outros textos (comandos, etc) ignorados aqui — serao processados depois
        }

        $remaining = [int](($deadline - (Get-Date)).TotalSeconds)
        Write-Host "  [Telegram] Aguardando... ${remaining}s restantes" -ForegroundColor DarkGray
    }

    Write-Host "  [Telegram] Timeout — aprovacao nao recebida" -ForegroundColor Yellow
    Send-TelegramAlert -Message "<b>Timeout</b> - ordem NAO executada (sem resposta em $([int]($TimeoutSeconds/60))min)" -Token $Token -ChatId $ChatId -Enabled $Enabled | Out-Null
    return $false
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-TelegramCommands
# Retorna lista de comandos pendentes (usa offset global).
# Ignora palavras de aprovacao/rejeicao.
# Comandos: status, scan, gem, pausar, retomar, fechar, ajuda, help
# ─────────────────────────────────────────────────────────────────────────────
$TG_KNOWN_COMMANDS = @("status","scan","gem","pausar","retomar","fechar","ajuda","help","custos","cost")
$TG_APPROVAL_WORDS = @("ok","sim","yes","go","executar","s","y","nao","no","cancel","cancelar","skip","n")

function Get-TelegramCommands {
    param(
        [string] $Token   = $env:TELEGRAM_BOT_TOKEN,
        [string] $ChatId  = $env:TELEGRAM_CHAT_ID,
        [string] $Enabled = $env:TELEGRAM_ENABLED
    )
    if ($Enabled -ne "true" -or -not $Token -or -not $ChatId) { return @() }

    $results = @()
    $updates = Receive-TelegramUpdates -Limit 20 -Token $Token

    foreach ($upd in @($updates)) {
        $msgChatId = if ($upd.message) { "$($upd.message.chat.id)" } else { "" }
        if ($msgChatId -ne $ChatId) { continue }

        $text = $upd.message.text
        if (-not $text) { continue }

        $lower = $text.Trim().ToLower()

        # Ignora palavras de aprovacao
        if ($TG_APPROVAL_WORDS -contains $lower) { continue }

        # Extrai comando (com ou sem /)
        $clean = $lower.TrimStart("/")
        $parts = $clean -split "\s+", 2
        $cmd   = $parts[0]
        $arg   = if ($parts.Count -gt 1) { $parts[1].ToUpper().Trim() } else { "" }

        if ($TG_KNOWN_COMMANDS -contains $cmd) {
            $results += [PSCustomObject]@{
                command = $cmd
                arg     = $arg
                raw     = $text
                from    = $upd.message.from.first_name
            }
            Write-Host "  [CMD] $($upd.message.from.first_name): /$cmd $arg" -ForegroundColor Magenta
        }
    }

    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# Format-TelegramMessage  (legado — mantido para compatibilidade)
# ─────────────────────────────────────────────────────────────────────────────
function Format-TelegramMessage {
    param([Parameter(Mandatory)][object]$Gem, [string]$MarketType = "FUTURES")
    $mkt   = if ($Gem.market) { $Gem.market } else { "???" }
    $score = if ($Gem.score)  { $Gem.score }  else { 0 }
    $mode  = if ($Gem.mode)   { $Gem.mode }   else { "???" }
    $sz    = $Gem.sizing
    $vd    = $Gem.vol_data
    $sizing_pct = if ($sz) { [math]::Round($sz.sizing_pct * 100, 2) } else { 0 }
    $sizing_usd = if ($sz) { $sz.sizing_usd } else { 0 }
    $stop_pct   = if ($sz) { [math]::Round($sz.stop_pct * 100, 0) }  else { 0 }
    $target_pct = if ($sz) { [math]::Round($sz.target_pct * 100, 0) } else { 0 }
    $spike      = if ($vd) { $vd.spike_ratio } else { 0 }
    $spike_type = if ($vd) { $vd.spike_type }  else { "" }
    $pct_today  = if ($vd) { $vd.pct_change_today } else { 0 }
    $mode_tag   = if ($mode -eq "DISCOVERY") { "[DISC]" } else { "[MOM]" }
    $mkt_tag    = if ($MarketType -eq "FUTURES") { "[FUTURES]" } else { "[SPOT]" }
    return "<b>GEM ALERT</b> $mode_tag -- $mkt`n$mkt_tag $mode | Score: $score`n`n<b>Sizing:</b> ${sizing_pct}% = $sizing_usd USDT`n<b>Stop:</b> -${stop_pct}%  |  <b>Target:</b> +${target_pct}%`n<b>Vol spike:</b> ${spike}x $spike_type (+${pct_today}%)`n<i>CoinEx GemAgent | $(Get-Date -Format 'HH:mm dd/MM')</i>"
}

function Send-GemAlert {
    param([Parameter(Mandatory)][object]$Gem, [string]$MarketType = "FUTURES")
    return Send-TelegramAlert -Message (Format-TelegramMessage -Gem $Gem -MarketType $MarketType)
}

# ─────────────────────────────────────────────────────────────────────────────
# Send-GemAlertWithLogo
# Envia foto do logo + caption formatada via Format-TgGemApproval.
# Fallback para Send-TelegramAlert se logo_url ausente ou erro no sendPhoto.
# ─────────────────────────────────────────────────────────────────────────────
function Send-GemAlertWithLogo {
    param(
        [Parameter(Mandatory)][object] $Gem,
        [switch]                        $DryRun,
        [string]                        $Token   = $env:TELEGRAM_BOT_TOKEN,
        [string]                        $ChatId  = $env:TELEGRAM_CHAT_ID,
        [string]                        $Enabled = $env:TELEGRAM_ENABLED
    )
    if ($Enabled -ne "true") { return $false }
    if (-not $Token)         { return $false }
    if (-not $ChatId)        { return $false }

    $caption = Format-TgGemApproval -Gem $Gem -DryRun:$DryRun
    $logoUrl = if ($Gem.PSObject.Properties['logo_url']) { $Gem.logo_url } else { $null }

    # Sem logo: fallback direto pra texto
    if (-not $logoUrl) {
        return (Send-TelegramAlert -Message $caption -Token $Token -ChatId $ChatId -Enabled $Enabled)
    }

    # Tenta sendPhoto; fallback para texto se falhar
    try {
        $uri  = "$global:TELEGRAM_API_BASE/bot$Token/sendPhoto"
        $body = @{ chat_id = $ChatId; photo = $logoUrl; caption = $caption; parse_mode = "HTML" }
        $json = $body | ConvertTo-Json -Depth 5
        $r = Invoke-RestMethod -Uri $uri -Method POST -Body $json -ContentType "application/json" -ErrorAction Stop
        if ($r.ok -eq $true) { return $true }
        return (Send-TelegramAlert -Message $caption -Token $Token -ChatId $ChatId -Enabled $Enabled)
    } catch {
        Write-Host "  [Telegram] sendPhoto falhou, fallback texto: $_" -ForegroundColor DarkYellow
        return (Send-TelegramAlert -Message $caption -Token $Token -ChatId $ChatId -Enabled $Enabled)
    }
}

# =============================================================================
# STAGE 3 -- INLINE KEYBOARD CALLBACK FLOW (stubs)
# Aprovacao via tap em botao (callback_query) ao inves de texto.
# =============================================================================

# -----------------------------------------------------------------------------
# New-TgApprovalKeyboard
# Monta o InlineKeyboardMarkup com botoes EXECUTAR / CANCELAR.
# -----------------------------------------------------------------------------
function New-TgApprovalKeyboard {
    param([Parameter(Mandatory)][string]$GemId)
    # Monta InlineKeyboardMarkup com uma linha contendo EXECUTAR e CANCELAR.
    $btnApprove = @{
        text          = "$($global:TG_EMOJI.check) EXECUTAR"
        callback_data = "approve:$GemId"
    }
    $btnReject = @{
        text          = "$($global:TG_EMOJI.cross) CANCELAR"
        callback_data = "reject:$GemId"
    }
    return @{ inline_keyboard = @( ,@($btnApprove, $btnReject) ) }
}

# -----------------------------------------------------------------------------
# Send-TgApprovalRequest
# Envia mensagem com inline keyboard pedindo aprovacao.
# -----------------------------------------------------------------------------
function Send-TgApprovalRequest {
    param(
        [Parameter(Mandatory)][object]$Gem,
        [Parameter(Mandatory)][string]$GemId,
        [string]$Token   = $env:TELEGRAM_BOT_TOKEN,
        [string]$ChatId  = $env:TELEGRAM_CHAT_ID,
        [string]$Enabled = $env:TELEGRAM_ENABLED
    )
    # Early return em config invalida
    if ($Enabled -ne "true" -or -not $Token -or -not $ChatId) {
        return @{ ok = $false; message_id = $null; was_photo = $false }
    }

    $caption  = Format-TgGemApproval -Gem $Gem
    $keyboard = New-TgApprovalKeyboard -GemId $GemId
    $hasLogo  = ($Gem.PSObject.Properties['logo_url']) -and (-not [string]::IsNullOrWhiteSpace($Gem.logo_url))

    # Tenta sendPhoto se houver logo
    if ($hasLogo) {
        try {
            $uri  = "$global:TELEGRAM_API_BASE/bot$Token/sendPhoto"
            $body = @{
                chat_id      = $ChatId
                photo        = $Gem.logo_url
                caption      = $caption
                parse_mode   = "HTML"
                reply_markup = $keyboard
            }
            $json = $body | ConvertTo-Json -Depth 10
            $r = Invoke-RestMethod -Uri $uri -Method POST -Body $json -ContentType "application/json" -ErrorAction Stop
            if ($r.ok -eq $true) {
                return @{ ok = $true; message_id = $r.result.message_id; was_photo = $true }
            }
            # ok=false: cai para fallback texto
        } catch {
            Write-Host "  [Telegram] sendPhoto falhou, fallback texto: $_" -ForegroundColor DarkYellow
        }
    }

    # Fallback / caminho texto
    try {
        $uri  = "$global:TELEGRAM_API_BASE/bot$Token/sendMessage"
        $body = @{
            chat_id      = $ChatId
            text         = $caption
            parse_mode   = "HTML"
            reply_markup = $keyboard
        }
        $json = $body | ConvertTo-Json -Depth 10
        $r = Invoke-RestMethod -Uri $uri -Method POST -Body $json -ContentType "application/json" -ErrorAction Stop
        return @{
            ok         = ($r.ok -eq $true)
            message_id = $r.result.message_id
            was_photo  = $false
        }
    } catch {
        return @{ ok = $false; message_id = $null; was_photo = $false }
    }
}

# -----------------------------------------------------------------------------
# Confirm-TgCallback
# Confirma um callback_query no Telegram (remove o "loading" no botao).
# -----------------------------------------------------------------------------
function Confirm-TgCallback {
    param(
        [Parameter(Mandatory)][string]$CallbackId,
        [string]$Text  = "",
        [string]$Token = $env:TELEGRAM_BOT_TOKEN
    )
    if ([string]::IsNullOrEmpty($Token)) { return $false }
    try {
        $uri  = "$global:TELEGRAM_API_BASE/bot$Token/answerCallbackQuery"
        $body = @{ callback_query_id = $CallbackId; text = $Text }
        $json = $body | ConvertTo-Json -Depth 5
        $r = Invoke-RestMethod -Uri $uri -Method POST -Body $json -ContentType "application/json" -ErrorAction Stop
        return ($r.ok -eq $true)
    } catch {
        return $false
    }
}

# -----------------------------------------------------------------------------
# Update-TgCaption
# Edita a caption (sendPhoto) ou texto (sendMessage) de uma mensagem existente.
# -----------------------------------------------------------------------------
function Update-TgCaption {
    param(
        [Parameter(Mandatory)][int]$MessageId,
        [Parameter(Mandatory)][string]$Caption,
        [switch]$WasPhoto,
        [string]$Token   = $env:TELEGRAM_BOT_TOKEN,
        [string]$ChatId  = $env:TELEGRAM_CHAT_ID
    )
    if ([string]::IsNullOrEmpty($Token) -or [string]::IsNullOrEmpty($ChatId)) { return $false }
    try {
        if ($WasPhoto.IsPresent) {
            $uri  = "$global:TELEGRAM_API_BASE/bot$Token/editMessageCaption"
            $body = @{ chat_id = $ChatId; message_id = $MessageId; caption = $Caption; parse_mode = "HTML" }
        } else {
            $uri  = "$global:TELEGRAM_API_BASE/bot$Token/editMessageText"
            $body = @{ chat_id = $ChatId; message_id = $MessageId; text = $Caption; parse_mode = "HTML" }
        }
        $json = $body | ConvertTo-Json -Depth 5
        $r = Invoke-RestMethod -Uri $uri -Method POST -Body $json -ContentType "application/json" -ErrorAction Stop
        return ($r.ok -eq $true)
    } catch {
        return $false
    }
}

# -----------------------------------------------------------------------------
# Wait-TgCallbackApproval
# Envia request com inline keyboard e aguarda usuario tocar EXECUTAR/CANCELAR.
# -----------------------------------------------------------------------------
function Wait-TgCallbackApproval {
    param(
        [Parameter(Mandatory)][object]$Gem,
        [Parameter(Mandatory)][string]$GemId,
        [int]$TimeoutSeconds = 300,
        [int]$PollSeconds    = 4,
        [string]$Token   = $env:TELEGRAM_BOT_TOKEN,
        [string]$ChatId  = $env:TELEGRAM_CHAT_ID,
        [string]$Enabled = $env:TELEGRAM_ENABLED
    )
    $send = Send-TgApprovalRequest -Gem $Gem -GemId $GemId -Token $Token -ChatId $ChatId -Enabled $Enabled
    if ($send.ok -ne $true) {
        return @{ decision = "error"; from = $null; message_id = $null; elapsed_ms = 0 }
    }

    $messageId = $send.message_id
    $wasPhoto  = $send.was_photo
    $start     = Get-Date
    $deadline  = $start.AddSeconds($TimeoutSeconds)
    $pattern   = "^(approve|reject):" + [regex]::Escape($GemId) + "$"

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $PollSeconds

        $updates = Receive-TelegramUpdates -Token $Token

        foreach ($upd in @($updates)) {
            if (-not $upd.callback_query) { continue }
            $data = $upd.callback_query.data
            if (-not $data) { continue }
            if ($data -notmatch $pattern) { continue }

            $action = $Matches[1]
            $from   = $upd.callback_query.from.first_name
            $cbId   = $upd.callback_query.id

            # B14 fix 2026-05-20 PM6+: idempotency gate.
            # Sistema LIVE Mode 2 com capital $2762.93 -- duplicate callback poderia
            # disparar 2x sizing 1% (+$55 exposicao inesperada) e violar daily_loss CB
            # silenciosamente. Race condition latente entre tg_listener + Wait-Tg... que
            # compartilham $global:TG_UPDATE_OFFSET.
            if (Get-Command Test-CallbackIdempotent -ErrorAction SilentlyContinue) {
                $idemPath = Join-Path $global:JOURNAL_DIR "telegram_callbacks_processed.json"
                $isNew = Test-CallbackIdempotent -Path $idemPath -CallbackId $cbId
                if (-not $isNew) {
                    # ACK pra remover spinner mas skip o trade
                    Confirm-TgCallback -CallbackId $cbId -Token $Token | Out-Null
                    # Continua polling (nao retorna decision) -- pode ser que callback novo chegue
                    continue
                }
            }

            # ACK best-effort
            Confirm-TgCallback -CallbackId $cbId -Token $Token | Out-Null

            $resultCaption = if ($action -eq "approve") {
                "$($global:TG_EMOJI.check) EXECUTADO por $from"
            } else {
                "$($global:TG_EMOJI.cross) CANCELADO por $from"
            }

            if ($null -ne $messageId) {
                Update-TgCaption -MessageId $messageId -Caption $resultCaption -WasPhoto:$wasPhoto -Token $Token -ChatId $ChatId | Out-Null
            }

            return @{
                decision   = $action
                from       = $from
                message_id = $messageId
                elapsed_ms = [int]((Get-Date) - $start).TotalMilliseconds
            }
        }
    }

    return @{
        decision   = "timeout"
        from       = $null
        message_id = $messageId
        elapsed_ms = $TimeoutSeconds * 1000
    }
}

# =============================================================================
# LAYOUTS PROFISSIONAIS
# =============================================================================

# ── Sistema ───────────────────────────────────────────────────────────────────

function Format-TgSystemStart {
    param([switch]$DryRun)
    $e    = $global:TG_EMOJI
    $modoIcon  = if ($DryRun) { $e.bulb } else { $e.rocket }
    $modoLabel = if ($DryRun) { "DRY RUN" } else { "LIVE" }
    $modoSub   = if ($DryRun) { "sem ordens reais" } else { "aprovacao manual ativa" }
    $ts   = (Get-Date).ToString("HH:mm dd/MM/yy")
    return "$($e.robot) <b>SISTEMA LIGADO</b>  $modoIcon $modoLabel`n<i>$modoSub</i>`n$($e.search) GemScan  +  $($e.gear) Orchestrator  +  $($e.target) Trailing`n<i>$ts</i>"
}

function Format-TgSystemStop {
    $e  = $global:TG_EMOJI
    $ts = (Get-Date).ToString("HH:mm dd/MM/yy")
    return "$($e.cross) <b>SISTEMA PARADO</b> <i>$ts</i>"
}

# ── Ciclo ─────────────────────────────────────────────────────────────────────

function Format-TgCycleSummary {
    param(
        [string] $Window,
        [int]    $MomentScore,
        [string] $TrailSummary,
        [string] $GemSummary,
        [string] $ScanSummary,
        [string] $OrchSummary,
        [int]    $NextMin,
        [string] $NextTime,
        [int]    $ElapsedSec,
        [switch] $DryRun
    )
    $e         = $global:TG_EMOJI
    $modeLabel = if ($DryRun) { "DRY" } else { "LIVE" }
    $modeEmoji = if ($DryRun) { $e.bulb } else { $e.rocket }
    $ts        = (Get-Date).ToString("HH:mm dd/MM")
    $wEmoji    = Get-WindowEmoji -Window $Window
    $moodBar   = Get-ConfidenceBar -Pct $MomentScore -Width 10

    # Header com mood visual + robo trabalhando
    $header = "$($e.robot) <b>CICLO $modeLabel</b>  $modeEmoji $ts`n$wEmoji $Window  |  Momentum [$moodBar] $MomentScore/100"

    # Body: cada linha com emoji descritivo do que esta acontecendo
    $bodyTrail = "$($e.target) <b>Trail:</b>  $TrailSummary"
    $bodyGem   = "$($e.gem) <b>Gems:</b>   $GemSummary"
    $bodyScan  = "$($e.search) <b>Scan:</b>   $ScanSummary"

    # Orch: separar EXEC (verde) de ABORTAR (cinza) visualmente, count summary
    $orchPretty = $OrchSummary
    $execCount  = ([regex]::Matches($OrchSummary, "EXECUTAR\(\)").Count)
    $abortCount = ([regex]::Matches($OrchSummary, "ABORTAR\(\)").Count)
    $waitCount  = ([regex]::Matches($OrchSummary, "AGUARDAR\(\)").Count)
    $orchHeader = "$($e.brain) <b>Mesa+Mentor:</b>  $($e.check)$execCount exec  $($e.cross)$abortCount abort"
    if ($waitCount -gt 0) { $orchHeader += "  $($e.clock)$waitCount wait" }
    # Em modo compact, esconde detalhe linha-a-linha; em verbose, mostra
    if ($global:TG_FORMAT_MODE -eq "compact" -and ($execCount + $abortCount + $waitCount) -gt 0) {
        $bodyOrch = $orchHeader
    } else {
        # Verbose: lista por par mas em linhas (não pipe), e marca EXEC com verde
        $items = ($OrchSummary -split "\s*\|\s*") | Where-Object { $_ -match "\S" }
        $lines = @()
        foreach ($it in $items) {
            $line = if ($it -match "EXECUTAR")    { "  $($e.check) $it" }
                    elseif ($it -match "ABORTAR") { "  $($e.cross) $it" }
                    elseif ($it -match "AGUARDAR"){ "  $($e.clock) $it" }
                    else { "  $it" }
            $lines += $line
        }
        $bodyOrch = $orchHeader + "`n" + ($lines -join "`n")
    }

    # Footer com custos colapsados
    $costLine = ""
    if (Get-Command -Name "Get-CostSummary" -ErrorAction SilentlyContinue) {
        try {
            $cs = Get-CostSummary
            $costLine = "`n$($e.money) hoje `$$($cs.today) | mes `$$($cs.month) | proj `$$($cs.projectedMonthly)/mes"
        } catch {}
    }
    $footer = "$($e.clock) proximo ${NextMin}min ($NextTime) | exec ${ElapsedSec}s$costLine"

    return "$header`n$TG_SEP`n$bodyTrail`n$bodyGem`n$bodyScan`n$bodyOrch`n$TG_SEP`n<i>$footer</i>"
}

# ── Gem ───────────────────────────────────────────────────────────────────────

function Format-TgGemApproval {
    param([object]$Gem, [switch]$DryRun)
    $e       = $global:TG_EMOJI
    $sz      = $Gem.sizing
    $sizeUsd = if ($sz) { $sz.sizing_usd } else { 0 }
    $sizePct = if ($sz) { [math]::Round($sz.sizing_pct * 100, 2) } else { 0 }
    $stopPctNum = if ($sz) { [math]::Round($sz.stop_pct * 100, 0) } else { 0 }
    $tgtPctNum  = if ($sz) { [math]::Round($sz.target_pct * 100, 0) } else { 0 }
    $winUsd  = if ($sz) { [math]::Round($sz.sizing_usd * $sz.target_pct, 2) } else { 0 }
    $lossUsd = if ($sz) { [math]::Round($sz.sizing_usd * $sz.stop_pct, 2)   } else { 0 }
    $dryTag  = if ($DryRun) { " [DRY]" } else { "" }

    # TLDR header
    $market  = if ($Gem.market) { $Gem.market } else { "?" }
    $tldr    = "$($e.alert) <b>APROVAR$dryTag</b> $market $sizeUsd USDT -> +`$$winUsd / -`$$lossUsd"

    # CONTEXTO — so monta se houver pelo menos um campo
    $hasMcap     = ($Gem.PSObject.Properties['mcap_usd']     -and $Gem.mcap_usd)
    $hasListing  = ($Gem.PSObject.Properties['listing_days'] -and $Gem.listing_days -ne $null)
    $hasNarr     = ($Gem.PSObject.Properties['narrative']    -and $Gem.narrative)
    $hasOrganic  = ($Gem.PSObject.Properties['organic_score'] -and $Gem.organic_score -ne $null)
    $hasGates    = ($Gem.PSObject.Properties['gates_passed'] -and $Gem.gates_passed)
    $hasContexto = ($hasMcap -or $hasListing -or $hasNarr -or $hasOrganic -or $hasGates)

    $contexto = ""
    if ($hasContexto) {
        $mcapStr = if ($hasMcap)    { "`$" + [math]::Round($Gem.mcap_usd / 1000000.0, 2) + "m" } else { "?" }
        $listStr = if ($hasListing) { "dia $($Gem.listing_days)" } else { "?" }
        $line1   = "$($e.chart) Mcap: $mcapStr | Listing: $listStr"

        $line2 = ""
        if ($hasNarr) { $line2 = "`n$($e.fire) Narrativa: $($Gem.narrative)" }

        $line3 = ""
        if ($hasOrganic -or $hasGates) {
            $orgStr   = if ($hasOrganic) { "$($Gem.organic_score)/100" } else { "?" }
            $gatesStr = if ($hasGates)   { ($Gem.gates_passed -join " ") } else { "?" }
            $line3 = "`n$($e.gem) Organico: $orgStr | Gates: $gatesStr"
        }
        $contexto = "`n`n<b>CONTEXTO</b>`n$line1$line2$line3"
    }

    # EXECUCAO
    $execucao = "`n`n<b>EXECUCAO</b>`n$($e.money) Sizing: `$$sizeUsd ($sizePct%)`n$($e.stop) Stop: -$stopPctNum%`n$($e.target) Alvo: +$tgtPctNum%"

    # Footer
    $footer = if ($DryRun) { "`n`n<i>Modo DryRun - nenhuma acao necessaria</i>" } else { "`n`n$($e.clock) Timeout 5min" }

    return "$tldr$contexto$execucao$footer"
}

function Format-TgGemExecuted {
    param([object]$ExecResult, [object]$Gem)
    $ts   = (Get-Date).ToString("HH:mm dd/MM/yy")
    $mkt  = $ExecResult.market
    $tipo = if ($ExecResult.market_type) { $ExecResult.market_type } else { "SPOT" }
    return "<b>GEM EXECUTADA</b> -- $mkt [$tipo]`n$TG_SEP`nOrdem:   #$($ExecResult.order_id)`nPreco:   $($ExecResult.price) | Qty: $($ExecResult.qty)`nStop:    $($ExecResult.stop)`nAlvo:    $($ExecResult.target)`nTrailing ativo (fase 0)`n<i>$ts</i>"
}

function Format-TgGemRejected {
    param([string]$Market, [string]$Reason = "usuario cancelou")
    $ts = (Get-Date).ToString("HH:mm dd/MM/yy")
    return "<b>GEM CANCELADA</b> -- $Market`n<i>$Reason</i>`n<i>$ts</i>"
}

# ── Orchestrator ──────────────────────────────────────────────────────────────

function Format-TgSetupApproval {
    param(
        [string]$Market,
        [string]$Sinal,
        [double]$Score,
        [string]$Setup,
        [double]$Entry,
        [double]$Stop,
        [double]$Target,
        [double]$RR,
        [double]$RiscoUsd,
        [double]$Qtd,
        [int]   $MentorConf = 0,
        [string]$MentorMsg  = ""
    )
    $stopPct   = if ($Entry -gt 0) { [math]::Round([math]::Abs($Entry - $Stop) / $Entry * 100, 1) } else { 0 }
    $targetPct = if ($Entry -gt 0) { [math]::Round([math]::Abs($Target - $Entry) / $Entry * 100, 1) } else { 0 }
    $confLine  = if ($MentorConf -gt 0) { "Mentor:  EXECUTAR conf=$MentorConf%`n" } else { "" }
    $msgLine   = if ($MentorMsg) {
        $short = $MentorMsg.Substring(0, [math]::Min(120, $MentorMsg.Length))
        "<i>$short...</i>`n"
    } else { "" }
    return "<b>SETUP ENCONTRADO</b> -- $Market $Sinal`nScore: $Score/100 | Setup $Setup`n$TG_SEP`nEntrada: $Entry`nStop:    $Stop (-$stopPct%)`nAlvo:    $Target (+$targetPct%)`nR:R:     1:$RR`nRisco:   $RiscoUsd USDT | Qty: $Qtd`n${confLine}$TG_SEP`n${msgLine}<b>ok</b> executar  |  <b>nao</b> cancelar  |  timeout 5min"
}

function Format-TgSetupResult {
    param([object]$Result, [switch]$DryRun)
    $ts      = (Get-Date).ToString("HH:mm dd/MM/yy")
    $dryTag  = if ($DryRun) { " DRY" } else { "" }
    $dec     = $Result.decisao -replace "DRY_RUN_",""
    $label   = switch -Wildcard ($dec) { "*EXECUTAR*" { "EXECUTADO" } "AGUARDAR" { "AGUARDAR" } "ABORTAR" { "ABORTAR" } default { $dec } }
    $levels  = if ($Result.entryPrice -gt 0) {
        "`nEntrada: $($Result.entryPrice) | Stop: $($Result.stopLoss) | Alvo: $($Result.alvo1) | R:R: $($Result.rrBruto)"
    } else { "" }
    $mentorLine = if ($Result.mentorMensagem) {
        $short = $Result.mentorMensagem.Substring(0, [math]::Min(140, $Result.mentorMensagem.Length))
        "`n<i>$short</i>"
    } else { "" }
    return "<b>$label$dryTag</b> -- $($Result.market)`nScore: $($Result.scorePonderado)/100 | $($Result.sinalTech) | Setup $($Result.qualidadeSetup)$levels$mentorLine`n<i>$ts</i>"
}

# ── Trailing ──────────────────────────────────────────────────────────────────

function Format-TgTrailPhase {
    param([object]$Pos, [double]$OldStop, [int]$OldPhase, [double]$CurrentPrice)
    $phaseLabel = @("inicial","breakeven","lock +33%","trailing livre")
    $ts = (Get-Date).ToString("HH:mm dd/MM/yy")
    $dir = $Pos.side
    $phaseChange = if ([int]$Pos.phase -gt $OldPhase) {
        "Fase $OldPhase  ->  <b>Fase $($Pos.phase) ($($phaseLabel[$Pos.phase]))</b>"
    } else { "Fase $($Pos.phase) ($($phaseLabel[$Pos.phase])) atualizado" }
    return "<b>TRAIL MOVEU</b> -- $($Pos.market) $dir`n$phaseChange`nStop: $OldStop  ->  <b>$($Pos.stopCurrent)</b>`nPreco atual: $CurrentPrice`n<i>$ts</i>"
}

function Format-TgTrailStopHit {
    param([object]$Pos, [double]$CurrentPrice)
    $phaseLabel = @("inicial","breakeven","lock +33%","trailing livre")
    $ts = (Get-Date).ToString("HH:mm dd/MM/yy")
    $fase = $phaseLabel[[int]$Pos.phase]
    $resultado = switch ([int]$Pos.phase) {
        0 { "prejuizo (stop original)" }
        1 { "breakeven - capital protegido" }
        2 { "+33% garantido" }
        3 { "trailing livre executado" }
    }
    return "<b>STOP ATINGIDO</b> -- $($Pos.market) $($Pos.side)`nStop: $($Pos.stopCurrent) | Preco: $CurrentPrice`nFase: $fase`nResultado: $resultado`n<i>$ts</i>"
}

# ── Comandos interativos ──────────────────────────────────────────────────────

function Format-TgHelp {
    return "<b>COMANDOS DISPONIVEIS</b>`n$TG_SEP`n/status       posicoes e janela atual`n/custos       gasto Claude (hoje/semana/mes)`n/scan          forca ciclo imediato`n/scan BTCUSDT  analisa par especifico`n/gem           forca GemScan imediato`n/pausar        pausa o loop`n/retomar       retoma o loop`n/fechar BTCUSDT  fecha trailing`n/ajuda         esta mensagem"
}

# ── Esquadrao V6 ──────────────────────────────────────────────────────────────

function Format-TgEsquadraoResult {
    param(
        [string]         $Market,
        [PSCustomObject] $Triagem,
        [PSCustomObject] $Mesa,
        [PSCustomObject] $Mentor,
        [string]         $Decisao
    )
    $e  = $global:TG_EMOJI
    $ts = (Get-Date).ToString("HH:mm dd/MM")

    # Direction emoji do Mesa (LONG/SHORT)
    $dirEmoji = if ($Mesa) { Get-DirectionEmoji -Direction $Mesa.sinal_consenso } else { "" }

    # Header com banner visual conforme decisão
    $isExec    = $Decisao -match "EXECUTAR"
    $isAbort   = $Decisao -match "ABORTAR"
    $isDryRun  = $Decisao -match "DRY_RUN"
    $decBadge  = if ($isExec)  { "$($e.check) <b>EXECUTAR</b>" }
                  elseif ($isAbort) { "$($e.cross) <b>ABORTAR</b>" }
                  else              { "$($e.clock) <b>$Decisao</b>" }
    $dryTag    = if ($isDryRun) { " <i>(simulado)</i>" } else { "" }
    $header    = "$decBadge$dryTag  $dirEmoji <b>$Market</b>"

    # Triagem com tier badge
    $triagemLine = if ($Triagem) {
        $tierBadge = Get-TierBadge -Tier $Triagem.tier
        "<b>Triagem</b>   $tierBadge   score $($Triagem.score_predicted)"
    } else { "<b>Triagem</b>   -" }

    # Mesa: consensus visual com emoji
    $mesaLine = if ($Mesa) {
        $cons = $Mesa.consensus
        $consIcon = if ($cons -match "FORTE")  { $e.fire }
                    elseif ($cons -match "MEDIO") { $e.bulb }
                    elseif ($cons -match "CAOS")  { $e.cross }
                    else { "" }
        "<b>Mesa</b>      $consIcon $cons $dirEmoji $($Mesa.sinal_consenso)  avg $($Mesa.score_avg)"
    } else { "<b>Mesa</b>      pulada (Tier A direto)" }

    # Mentor com confidence bar visual
    $mentorLine = if ($Mentor) {
        $conf = [int]($Mentor.confianca + 0)
        $bar  = Get-ConfidenceBar -Pct $conf -Width 10
        $decIcon = if ($Mentor.decision -match "APROVAR") { $e.check }
                    elseif ($Mentor.decision -match "VETAR|REJEITAR|ABORTAR") { $e.cross }
                    else { $e.clock }
        $maxLen  = if ($global:TG_FORMAT_MODE -eq "compact") { 90 } else { 240 }
        $msg = if ($Mentor.mentor_mensagem) {
            $m = $Mentor.mentor_mensagem
            if ($m.Length -gt $maxLen) { $m.Substring(0, $maxLen) + "..." } else { $m }
        } else { "" }
        "<b>Mentor</b>    $decIcon $($Mentor.decision)  [$bar] $conf%`n$($e.brain) <i>$msg</i>"
    } else { "<b>Mentor</b>    -" }

    return "$header`n$TG_SEP`n$triagemLine`n$mesaLine`n$mentorLine`n$TG_SEP`n<i>$ts</i>"
}

# ── Cycle filter ──────────────────────────────────────────────────────────────
# Cycle summary so dispara no Telegram se houve "news":
#   - gem encontrado
#   - par passou Mesa (consensus != CAOS)
#   - trailing mudou de fase
#   - posicao executada/fechada
# Caso contrario: silencio (log local apenas).

function Format-TgLiveSetupRisk {
    <#
    .SYNOPSIS
        Mensagem Telegram com painel de risco completo para Mode 2 LIVE.
        User decide aprovar baseado em metrics quant explicitas.
    #>
    [CmdletBinding()]
    param(
        [string]$Market,
        [string]$Direction,         # LONG | SHORT
        [string]$Tier,              # A | B
        [double]$Entry,
        [double]$Stop,
        [double]$Target,
        [double]$SizeUsd,
        [double]$Sharpe,
        [double]$DSR,
        [double]$PSR,
        [double]$PBO,
        [double]$WinRatePct,
        [double]$MeanR,
        [int]   $WfPositive = 0,
        [int]   $WfTotal    = 0,
        [int]   $SampleN    = 0,
        [string]$SampleYears = "",
        [string]$MentorMsg  = "",
        [int]   $MentorConf  = 0,
        [switch]$DryRun
    )
    $e = $global:TG_EMOJI

    # Tier badge
    $tierBadge = if ($Tier -eq "A") { "$($e.check) <b>TIER A LIVE</b>" }
                  elseif ($Tier -eq "B") { "$($e.bulb) <b>TIER B PAPER</b> $($e.alert) edge marginal" }
                  else { "<b>TIER $Tier</b>" }

    $dirEmoji = Get-DirectionEmoji -Direction $Direction
    $modeTag  = if ($DryRun) { "DRY" } else { "LIVE" }
    $modeEmoji = if ($DryRun) { $e.bulb } else { $e.rocket }

    # PnL extremos
    $stopPct   = if ($Entry -gt 0) { [math]::Round([math]::Abs($Entry - $Stop) / $Entry * 100, 2) } else { 0 }
    $targetPct = if ($Entry -gt 0) { [math]::Round([math]::Abs($Target - $Entry) / $Entry * 100, 2) } else { 0 }
    $worstUsd  = [math]::Round($SizeUsd, 2)
    $bestUsd   = if ($stopPct -gt 0) { [math]::Round($SizeUsd * $targetPct / $stopPct, 2) } else { 0 }
    $expectedUsd = [math]::Round($SizeUsd * $MeanR, 2)

    # Gate icons
    $dsrIcon = if ($DSR -ge 0.95) { $e.check } else { $e.alert }
    $psrIcon = if ($PSR -ge 0.95) { $e.check } else { $e.alert }
    $pboIcon = if ($PBO -lt 0.30) { $e.check } else { $e.alert }
    $wfIcon  = if ($WfTotal -gt 0 -and $WfPositive -ge 3) { $e.check } else { $e.alert }
    $wfStr   = if ($WfTotal -gt 0) { "$WfPositive/$WfTotal" } else { "n/a" }

    # Confidence bar Mentor
    $confBar = if ($MentorConf -gt 0) { Get-ConfidenceBar -Pct $MentorConf -Width 10 } else { "" }
    $confLine = if ($MentorConf -gt 0) { "[$confBar] $MentorConf%" } else { "" }

    $shortMsg = if ($MentorMsg) {
        if ($MentorMsg.Length -gt 180) { $MentorMsg.Substring(0, 180) + "..." } else { $MentorMsg }
    } else { "" }

    $body = @"
$modeEmoji <b>SETUP $modeTag</b> $dirEmoji <b>$Market</b>
$tierBadge
$TG_SEP
$($e.target) <b>Entry/Stop/Target</b>
   Entry:  <code>$Entry</code>
   Stop:   <code>$Stop</code> (-$stopPct%)
   Target: <code>$Target</code> (+$targetPct%)
   R:R: 1:$([math]::Round($targetPct/$stopPct, 1))  |  Sizing: <code>`$$SizeUsd</code>

$($e.money) <b>RISCO REAL</b>
   Worst (stop):  -`$$worstUsd
   Best (target): +`$$bestUsd
   Expected:      +`$$expectedUsd  (WR $WinRatePct% historico)

$($e.chart) <b>EDGE BACKTEST</b>
   Sharpe: $Sharpe
   DSR: $DSR $dsrIcon  PSR: $PSR $psrIcon
   PBO: $PBO $pboIcon  WF OOS: $wfStr $wfIcon
   Sample: $SampleN trades / $SampleYears

$($e.brain) <b>MENTOR</b> $confLine
<i>$shortMsg</i>
$TG_SEP
"@
    # MCE Context score (2026-05-19) -- mostra timing context
    $mceLine = ""
    if (Get-Command Test-ContextAllowsTrade -ErrorAction SilentlyContinue) {
        try {
            $regimeStr = "BULL_WEAK"   # default conservador se nao sabemos
            $mce = Test-ContextAllowsTrade -DateBrt (Get-Date) -Regime $regimeStr
            $c = $mce.context
            $mceLine = "`n<b>MCE Context</b> score=<b>$($mce.score)</b> -> $($mce.action) (size x$($mce.size_multiplier))`n" +
                       "  DoW=$($c.dow) Season=$($c.season) Halving=$($c.halving) Session=$($c.session) Macro=$($c.macro) Regime=$($c.regime)`n$TG_SEP`n"
        } catch {}
    }
    $body += $mceLine

    # Macro context panel (info-only, user decide)
    $contextPanel = ""
    if (Get-Command Format-MarketContextPanel -ErrorAction SilentlyContinue) {
        try { $contextPanel = "`n$TG_SEP`n" + (Format-MarketContextPanel) + "`n$TG_SEP`n" } catch {}
    }
    $body += $contextPanel

    if (-not $DryRun) {
        $body += "$($e.check) <b>ok</b> executa  |  $($e.cross) <b>nao</b> cancela  |  timeout 5min"
    } else {
        $body += "<i>Modo DRY -- sem ordem real (apenas observacao)</i>"
    }
    return $body
}


function Test-CycleHasNews {
    param(
        [int]$GemCount        = 0,
        [int]$MesaPassed      = 0,
        [int]$TrailPhaseChg   = 0,
        [int]$Executions      = 0,
        [int]$Closures        = 0
    )
    return (($GemCount + $MesaPassed + $TrailPhaseChg + $Executions + $Closures) -gt 0)
}

# ── Heartbeat (opt-in) ────────────────────────────────────────────────────────
# Quando Test-CycleHasNews=false, sistema fica silencioso. User-feedback 2026-05-17:
# isso deixa user inseguro se sistema vivo. Heartbeat 1x/hora confirma "vivo, sem
# noticias". File-state em journal/heartbeat_last.txt para persistir entre restarts.

function Test-HeartbeatDue {
    [CmdletBinding()]
    param(
        [string] $LastHeartbeatFile,
        [int]    $IntervalMinutes = 60
    )
    if ([string]::IsNullOrEmpty($LastHeartbeatFile)) { return $true }
    if (-not (Test-Path $LastHeartbeatFile)) { return $true }
    try {
        $raw = Get-Content $LastHeartbeatFile -ErrorAction Stop | Select-Object -First 1
        $lastDt = [DateTime]::Parse($raw)
        $ageMin = ((Get-Date) - $lastDt).TotalMinutes
        return ($ageMin -ge $IntervalMinutes)
    } catch {
        return $true   # arquivo corrompido = assume due
    }
}

function Save-HeartbeatTimestamp {
    [CmdletBinding()]
    param([string] $LastHeartbeatFile)
    if ([string]::IsNullOrEmpty($LastHeartbeatFile)) { return }
    try {
        $dir = Split-Path -Parent $LastHeartbeatFile
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        (Get-Date).ToString("o") | Set-Content -Path $LastHeartbeatFile -Encoding UTF8
    } catch {
        Write-Warning "Save-HeartbeatTimestamp falhou: $($_.Exception.Message)"
    }
}

function Format-HeartbeatMessage {
    [CmdletBinding()]
    param(
        [int]    $CyclesQuiet = 1,
        [string] $Window      = "NEUTRAL",
        [int]    $NextMin     = 60,
        [string] $NextTime    = "",
        [int]    $WatchCount  = 0,
        [switch] $DryRun
    )
    $e         = $global:TG_EMOJI
    $modeLabel = if ($DryRun) { "DRY" } else { "LIVE" }
    $wEmoji    = Get-WindowEmoji -Window $Window
    $header    = "$($e.heart) <b>HEARTBEAT $modeLabel</b>  $wEmoji $Window"
    $body      = "$($e.robot) Robo vivo $($e.light)  |  $CyclesQuiet ciclo(s) sem trades"
    $footer    = "$($e.search) $WatchCount pares scaneados  |  $($e.clock) proximo ${NextMin}min ($NextTime)"
    return "$header`n$body`n<i>$footer</i>"
}

function Send-HeartbeatIfDue {
    [CmdletBinding()]
    param(
        [string] $LastHeartbeatFile,
        [int]    $IntervalMinutes = 60,
        [string] $Window          = "NEUTRAL",
        [int]    $NextMin         = 60,
        [string] $NextTime        = "",
        [int]    $WatchCount      = 0,
        [switch] $DryRun,
        [switch] $Enabled
    )
    if (-not $Enabled) { return $false }
    if (-not (Test-HeartbeatDue -LastHeartbeatFile $LastHeartbeatFile -IntervalMinutes $IntervalMinutes)) {
        return $false
    }
    $msg = Format-HeartbeatMessage -Window $Window -NextMin $NextMin `
        -NextTime $NextTime -WatchCount $WatchCount -DryRun:$DryRun
    try {
        Send-TelegramAlert -Message $msg | Out-Null
        Save-HeartbeatTimestamp -LastHeartbeatFile $LastHeartbeatFile
        return $true
    } catch {
        return $false
    }
}

function Format-TgStatusReport {
    param(
        [object[]] $Positions,
        [string]   $Window,
        [int]      $MomentScore,
        [int]      $NextMin,
        [string]   $NextTime,
        [switch]   $Paused
    )
    $pausedLine = if ($Paused) { "`n<b>STATUS: PAUSADO</b>" } else { "" }
    $ts = (Get-Date).ToString("HH:mm dd/MM/yy")
    $phaseLabel = @("inicial","breakeven","lock +33%","trailing")
    $posList = @($Positions) | Where-Object { $_ -ne $null }
    $posLines = if ($posList -and $posList.Count -gt 0) {
        ($posList | ForEach-Object {
            $fase = $phaseLabel[[int]$_.phase]
            "  $($_.market) $($_.side) | $fase | stop=$($_.stopCurrent)"
        }) -join "`n"
    } else { "  nenhuma posicao ativa" }
    return "<b>STATUS DO SISTEMA</b>$pausedLine`n$TG_SEP`nJanela: $Window | Momento: $MomentScore/100`nProximo ciclo: ${NextMin}min ($NextTime)`n$TG_SEP`n<b>Posicoes abertas:</b>`n$posLines`n$TG_SEP`n<i>$ts</i>"
}
