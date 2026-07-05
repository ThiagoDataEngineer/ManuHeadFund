# webhook_alerts.ps1 - Sistema de alertas com webhooks

param(
  [string]$AlertType = "",
  [string]$Symbol = "",
  [hashtable]$AlertData = @{}
)

function Send-TelegramAlert {
  param([string]$Message, [string]$BotToken, [string]$ChatId)
  
  try {
    $url = "https://api.telegram.org/bot$BotToken/sendMessage"
    $body = @{
      chat_id = $ChatId
      text = $Message
      parse_mode = "HTML"
    } | ConvertTo-Json
    
    Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Body $body -ErrorAction Stop
    Write-Host "✅ Telegram alerta enviado" -ForegroundColor Green
  } catch {
    Write-Host "❌ Erro Telegram: $_" -ForegroundColor Red
  }
}

function Send-EmailAlert {
  param([string]$Subject, [string]$Body, [hashtable]$SmtpConfig)
  
  try {
    $cred = New-Object System.Management.Automation.PSCredential(
      $SmtpConfig.from,
      (ConvertTo-SecureString $SmtpConfig.password -AsPlainText -Force)
    )
    
    Send-MailMessage -SmtpServer $SmtpConfig.smtp -Port $SmtpConfig.port -UseSsl `
      -From $SmtpConfig.from -To $SmtpConfig.to -Subject $Subject -Body $Body -Credential $cred
    
    Write-Host "✅ Email alerta enviado" -ForegroundColor Green
  } catch {
    Write-Host "⚠️  Email não configurado: $_" -ForegroundColor Yellow
  }
}

function Format-AlertMessage {
  param([string]$Type, [string]$Symbol, [hashtable]$Data)
  
  $timestamp = Get-Date -Format 'HH:mm:ss'
  
  switch ($Type) {
    "OVERBOUGHT" {
      return "<b>🔴 OVERBOUGHT</b> $Symbol`n" +
             "RSI: <code>$($Data.rsi)</code>`n" +
             "Price: <code>$($Data.price)</code>`n" +
             "Change: <code>$($Data.change)%</code>`n" +
             "⏰ $timestamp"
    }
    "OVERSOLD" {
      return "<b>🟢 OVERSOLD</b> $Symbol`n" +
             "RSI: <code>$($Data.rsi)</code>`n" +
             "Price: <code>$($Data.price)</code>`n" +
             "Change: <code>$($Data.change)%</code>`n" +
             "⏰ $timestamp"
    }
    "VOLATILITY_SPIKE" {
      return "<b>⚡ VOLATILITY SPIKE</b> $Symbol`n" +
             "Mudança 1h: <code>$($Data.change)%</code>`n" +
             "RSI: <code>$($Data.rsi)</code>`n" +
             "⏰ $timestamp"
    }
    "HIGH_CONVICTION" {
      return "<b>💡 HIGH CONVICTION</b> $Symbol`n" +
             "Score: <code>$($Data.score)</code>`n" +
             "Regime: <code>$($Data.regime)</code>`n" +
             "Direction: <code>$($Data.direction)</code>`n" +
             "⏰ $timestamp"
    }
    "REGIME_CHANGE" {
      return "<b>🔄 REGIME CHANGE</b> $Symbol`n" +
             "Novo: <code>$($Data.newRegime)</code>`n" +
             "Anterior: <code>$($Data.oldRegime)</code>`n" +
             "⏰ $timestamp"
    }
    "TRADE_ENTRY" {
      return "<b>✅ TRADE ENTRY</b> $Symbol`n" +
             "Type: <code>$($Data.type)</code>`n" +
             "Entry: <code>$($Data.entry)</code>`n" +
             "SL: <code>$($Data.sl)</code>`n" +
             "TP: <code>$($Data.tp)</code>`n" +
             "Risk: <code>$($Data.risk)%</code>`n" +
             "⏰ $timestamp"
    }
    default { return "Alerta: $Type $Symbol" }
  }
}

# Carregar config
$config = Get-Content config\alerts_config.json | ConvertFrom-Json

# Enviar alertas
if ($config.alerting.telegram.enabled) {
  $msg = Format-AlertMessage -Type $AlertType -Symbol $Symbol -Data $AlertData
  Send-TelegramAlert -Message $msg `
    -BotToken $config.alerting.telegram.botToken `
    -ChatId $config.alerting.telegram.chatId
}

if ($config.alerting.email.enabled) {
  Send-EmailAlert -Subject "$AlertType — $Symbol" `
    -Body (Format-AlertMessage -Type $AlertType -Symbol $Symbol -Data $AlertData) `
    -SmtpConfig $config.alerting.email
}

Write-Host "✅ Webhook executado: $AlertType $Symbol" -ForegroundColor Green
