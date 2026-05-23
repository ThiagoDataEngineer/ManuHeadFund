# setup_telegram_quick.ps1 - Setup Telegram RAPIDO (sem pausas)
# Uso: .\scripts\setup_telegram_quick.ps1 -Token "SEU_TOKEN" -ChatId "SEU_CHAT_ID"

param(
    [Parameter(Mandatory=$false)]
    [string]$Token,
    
    [Parameter(Mandatory=$false)]
    [string]$ChatId
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║    TELEGRAM SETUP RAPIDO - SEM PAUSAS  ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

# Se nao forneceu parametros, mostrar instrucoes
if (-not $Token -or -not $ChatId) {
    Write-Host "`n[INSTRUCOES RAPIDAS]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Telegram → @BotFather → /newbot" -ForegroundColor Gray
    Write-Host "2. Nome: ManuHeadFund Bot" -ForegroundColor Gray
    Write-Host "3. Username: manuheadfund_bot" -ForegroundColor Gray
    Write-Host "4. Copie o TOKEN" -ForegroundColor Gray
    Write-Host "5. Envie mensagem para o bot" -ForegroundColor Gray
    Write-Host "6. Telegram → @userinfobot → Copie seu ID" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Depois execute:" -ForegroundColor Cyan
    Write-Host '.\scripts\setup_telegram_quick.ps1 -Token "SEU_TOKEN" -ChatId "SEU_CHAT_ID"' -ForegroundColor White
    Write-Host ""
    exit 0
}

Write-Host "`n[1/3] Validando credenciais..." -ForegroundColor Yellow

# Validar token
if ($Token -eq "YOUR_BOT_TOKEN" -or $Token.Length -lt 20) {
    Write-Host "✗ Token invalido!" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Token OK" -ForegroundColor Green

# Validar chat ID
if ($ChatId -eq "YOUR_CHAT_ID" -or $ChatId.Length -lt 5) {
    Write-Host "✗ Chat ID invalido!" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Chat ID OK" -ForegroundColor Green

Write-Host "`n[2/3] Salvando configuracao..." -ForegroundColor Yellow

$config = @{
    enabled = $true
    bot_token = $Token
    chat_id = $ChatId
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

Write-Host "✓ Config salva: $configPath" -ForegroundColor Green

Write-Host "`n[3/3] Testando conexao..." -ForegroundColor Yellow

. ".\agents\lib_telegram.ps1"

$testResult = Telegram-SendMessage -Message "✅ *ManuHeadFund* conectado!`n`n📊 Dashboard profissional ativo`n🔔 Alertas automaticos configurados`n`nSistema operacional!"

if ($testResult.success) {
    Write-Host "✓ Mensagem de teste enviada!" -ForegroundColor Green
    Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║       TELEGRAM CONFIGURADO ✓           ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host "`nVerifique seu Telegram agora!" -ForegroundColor Cyan
    Write-Host "`nAlertas ativos:" -ForegroundColor White
    Write-Host "  ✓ Trailing stop (lucro > 3%)" -ForegroundColor Gray
    Write-Host "  ✓ Posicoes abertas/fechadas" -ForegroundColor Gray
    Write-Host "  ✓ Alertas de risco" -ForegroundColor Gray
    Write-Host "  ✓ Resumo diario" -ForegroundColor Gray
} else {
    Write-Host "✗ Falha ao enviar: $($testResult.error)" -ForegroundColor Red
    Write-Host "`nVerifique:" -ForegroundColor Yellow
    Write-Host "  - Token correto?" -ForegroundColor Gray
    Write-Host "  - Chat ID correto?" -ForegroundColor Gray
    Write-Host "  - Enviou mensagem para o bot?" -ForegroundColor Gray
    exit 1
}

Write-Host ""
