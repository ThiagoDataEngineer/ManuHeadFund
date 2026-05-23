# setup_telegram.ps1 - Configurar Telegram Bot
# Rodar: .\scripts\setup_telegram.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      TELEGRAM BOT SETUP - RAPIDO       ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`n[1/4] CRIAR BOT" -ForegroundColor Yellow
Write-Host "→ Telegram: @BotFather" -ForegroundColor Gray
Write-Host "→ Comando: /newbot" -ForegroundColor Gray
Write-Host "→ Nome: ManuHeadFund Bot" -ForegroundColor Gray
Write-Host "→ Username: manuheadfund_bot (ou similar)" -ForegroundColor Gray

Write-Host "`n[2/4] COLAR TOKEN" -ForegroundColor Yellow
$botToken = Read-Host "Token"

if (-not $botToken -or $botToken -eq "YOUR_BOT_TOKEN") {
    Write-Host "✗ Token invalido!" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Token recebido" -ForegroundColor Green

Write-Host "`n[3/4] OBTER CHAT ID" -ForegroundColor Yellow
Write-Host "→ Envie qualquer mensagem para o bot no Telegram" -ForegroundColor Gray
Write-Host "→ Aguardando 3 segundos..." -ForegroundColor Gray

Start-Sleep -Seconds 3

try {
    $url = "https://api.telegram.org/bot$botToken/getUpdates"
    $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 10
    
    if ($response.ok -and $response.result.Count -gt 0) {
        $chatId = $response.result[-1].message.chat.id
        Write-Host "✓ Chat ID: $chatId" -ForegroundColor Green
    } else {
        Write-Host "! Nenhuma mensagem encontrada" -ForegroundColor Yellow
        $chatId = Read-Host "Chat ID manual"
    }
} catch {
    Write-Host "! Erro ao buscar automaticamente" -ForegroundColor Yellow
    $chatId = Read-Host "Chat ID manual"
}

if (-not $chatId) {
    Write-Host "✗ Chat ID invalido!" -ForegroundColor Red
    exit 1
}

Write-Host "`n[4/4] SALVANDO CONFIG" -ForegroundColor Yellow

$config = @{
    enabled = $true
    bot_token = $botToken
    chat_id = $chatId.ToString()
    alerts = @{
        position_opened = $true
        position_closed = $true
        stop_loss_hit = $true
        take_profit_hit = $true
        trailing_activated = $true
        risk_alert = $true
        daily_summary = $true
    }
    quiet_hours = @{
        enabled = $false
        start = "22:00"
        end = "08:00"
    }
}

$configDir = "config"
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

$configPath = Join-Path $configDir "telegram.json"
$config | ConvertTo-Json -Depth 10 | Out-File -FilePath $configPath -Encoding UTF8 -Force

Write-Host "✓ Config salva" -ForegroundColor Green

Write-Host "`n[TESTE] Enviando mensagem..." -ForegroundColor Yellow

. ".\agents\lib_telegram.ps1"

$testResult = Telegram-SendMessage -Message "✅ *ManuHeadFund* conectado!`n`nAlertas automáticos ativados."

if ($testResult.success) {
    Write-Host "✓ Mensagem enviada!" -ForegroundColor Green
    Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║         TELEGRAM CONFIGURADO ✓         ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host "`nVerifique seu Telegram!" -ForegroundColor Cyan
} else {
    Write-Host "✗ Falha: $($testResult.error)" -ForegroundColor Red
}

Write-Host "`nAlertas ativos:" -ForegroundColor Gray
Write-Host "  • Trailing stop ativado (lucro > 3%)" -ForegroundColor Gray
Write-Host "  • Posição aberta/fechada" -ForegroundColor Gray
Write-Host "  • Alertas de risco" -ForegroundColor Gray
