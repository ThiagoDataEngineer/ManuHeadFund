# lib_telegram_essential_alerts.ps1
# Only essential alerts for capital owner
# 2026-07-08

# Regras:
# 1. TRADE OPENED — quando entra
# 2. TRADE CLOSED (TP/SL/Manual) — quando sai
# 3. TRAILING GAIN — quando SL sobe garantindo ganho
# 4. STOP LOSS HIT — quando SL bateu
# 5. TAKE PROFIT HIT — quando TP bateu
# 6. SYSTEM DOWN — quando para (daemon morreu)
# 7. SYSTEM UP — quando restartou

function Send-EssentialAlert {
    <#
    .SYNOPSIS
    Envia APENAS alertas essenciais pro dono do capital.
    Sem spam de bloqueios, sem debug, sem info.

    .PARAMETER Type
    TRADE_OPEN, TRADE_CLOSE_TP, TRADE_CLOSE_SL, TRAILING_GAIN,
    SYSTEM_DOWN, SYSTEM_UP, CRITICAL_ERROR
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Type,
        [Parameter(Mandatory)] [string] $Message,
        [string] $Market = "",
        [double] $Entry = 0,
        [double] $Current = 0,
        [double] $Exit = 0,
        [double] $PnL = 0,
        [double] $PnLPct = 0,
        [int] $DurationMinutes = 0
    )

    $timestamp = [datetime]::UtcNow.ToString("HH:mm dd/MM")

    switch ($Type) {
        "TRADE_OPEN" {
            $emoji = "🟢"
            $bold = "ENTRADA"
            $msg = "$emoji $bold — $Market`n`nEntry: $Entry`nStop: $(if($Market -eq '') { 'N/A' } else { 'Definido' })`nAlvo: $(if($Market -eq '') { 'N/A' } else { 'Definido' })`nCapital: $([math]::Round($PnL, 2)) USDT`n`n_$timestamp_"
        }

        "TRADE_CLOSE_TP" {
            $emoji = "✅"
            $bold = "TP BATIDO"
            $msg = "$emoji $bold — $Market`n`nEntry: $Entry`nExit: $Exit`nLucro: $([math]::Round($PnL, 2)) USD (+$([math]::Round($PnLPct, 2))%)`nTempo: ${DurationMinutes}min`n`n_$timestamp_"
        }

        "TRADE_CLOSE_SL" {
            $emoji = "🔴"
            $bold = "SL BATIDO"
            $msg = "$emoji $bold — $Market`n`nEntry: $Entry`nExit: $Exit`nPerda: $([math]::Round($PnL, 2)) USD ($([math]::Round($PnLPct, 2))%)`nTempo: ${DurationMinutes}min`n`n_$timestamp_"
        }

        "TRAILING_GAIN" {
            $emoji = "📈"
            $bold = "GANHO GARANTIDO"
            $msg = "$emoji $bold — $Market`n`nLucro atual: +$([math]::Round($PnL, 2)) USD (+$([math]::Round($PnLPct, 2))%)`nSL movido para: $Current (breakeven + buffer)`nStatus: Ganho protegido`n`n_$timestamp_"
        }

        "SYSTEM_DOWN" {
            $emoji = "🚨"
            $bold = "SISTEMA PAROU"
            $msg = "$emoji $bold`n`nDaemon: $Market`nRazão: $Message`n`nAção: Verificar logs e reiniciar`n`n_$timestamp_"
        }

        "SYSTEM_UP" {
            $emoji = "🟢"
            $bold = "SISTEMA ONLINE"
            $msg = "$emoji $bold`n`nDaemon: $Market`nStatus: Operacional`n`n_$timestamp_"
        }

        "CRITICAL_ERROR" {
            $emoji = "🚨"
            $bold = "CRITICO"
            $msg = "$emoji $bold`n`n$Message`n`nAção: IMEDIATO - verificar console`n`n_$timestamp_"
        }

        default {
            return
        }
    }

    # Enviar para Telegram
    try {
        if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
            Send-TelegramAlert -Message $msg | Out-Null
        }
    } catch {
        Write-Host "[WARN] Falha ao enviar alerta: $_" -ForegroundColor Yellow
    }
}

function Send-TradeOpenAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Direction,
        [Parameter(Mandatory)] [double] $Entry,
        [Parameter(Mandatory)] [double] $Stop,
        [Parameter(Mandatory)] [double] $Target,
        [Parameter(Mandatory)] [double] $SizeUSD,
        [string] $MarketType = "FUTURES"
    )

    $dir_emoji = if ($Direction -eq "SHORT") { "📉" } else { "📈" }
    $msg = @"
🟢 **ENTRADA** — $Market $dir_emoji

Entry: $Entry
Stop: $Stop
Alvo: $Target
Capital: $SizeUSD USDT
Tipo: $MarketType

_$([datetime]::UtcNow.ToString("HH:mm dd/MM"))_
"@

    Send-EssentialAlert -Type "TRADE_OPEN" -Message $msg -Market $Market -Entry $Entry
}

function Send-TradeCloseAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Reason,  # TP, SL, MANUAL
        [Parameter(Mandatory)] [double] $Entry,
        [Parameter(Mandatory)] [double] $Exit,
        [Parameter(Mandatory)] [double] $PnLUSD,
        [Parameter(Mandatory)] [double] $PnLPct,
        [int] $DurationMinutes = 0
    )

    $type = if ($Reason -eq "TP") { "TRADE_CLOSE_TP" } elseif ($Reason -eq "SL") { "TRADE_CLOSE_SL" } else { "TRADE_CLOSE_TP" }

    Send-EssentialAlert -Type $type -Message "" `
        -Market $Market `
        -Entry $Entry `
        -Exit $Exit `
        -PnL $PnLUSD `
        -PnLPct $PnLPct `
        -DurationMinutes $DurationMinutes
}

function Send-TrailingGainAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $CurrentPnLUSD,
        [Parameter(Mandatory)] [double] $CurrentPnLPct,
        [Parameter(Mandatory)] [double] $NewStop
    )

    Send-EssentialAlert -Type "TRAILING_GAIN" -Message "" `
        -Market $Market `
        -Current $NewStop `
        -PnL $CurrentPnLUSD `
        -PnLPct $CurrentPnLPct
}

function Send-SystemDownAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $DaemonName,
        [string] $Reason = ""
    )

    Send-EssentialAlert -Type "SYSTEM_DOWN" `
        -Message $Reason `
        -Market $DaemonName
}

function Send-SystemUpAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $DaemonName
    )

    Send-EssentialAlert -Type "SYSTEM_UP" `
        -Message "" `
        -Market $DaemonName
}

function Send-CriticalErrorAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message
    )

    Send-EssentialAlert -Type "CRITICAL_ERROR" -Message $Message
}

# Export-ModuleMember -Function @(
# 'Send-TradeOpenAlert'
# 'Send-TradeCloseAlert'
# 'Send-TrailingGainAlert'
# 'Send-SystemDownAlert'
# 'Send-SystemUpAlert'
# 'Send-CriticalErrorAlert'
# ) -ErrorAction SilentlyContinue


