# setup_telegram_quick.ps1 - Setup Telegram RAPIDO (sem pausas)
# Uso: .\scripts\setup_telegram_quick.ps1 -Token "SEU_TOKEN" -ChatId "SEU_CHAT_ID"

param(
    [Parameter(Mandatory=$false)]
    [string]$Token,
    
    [Parameter(Mandatory=$false)]
    [string]$ChatId
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "`nâ•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—" -ForegroundColor Cyan
Write-Host "â•‘    TELEGRAM SETUP RAPIDO - SEM PAUSAS  â•‘" -ForegroundColor Cyan
Write-Host "â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•" -ForegroundColor Cyan

# Se nao forneceu parametros, mostrar instrucoes
if (-not $Token -or -not $ChatId) {
    Write-Host "`n[INSTRUCOES RAPIDAS]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Telegram â†’ @BotFather â†’ /newbot" -ForegroundColor Gray
    Write-Host "2. Nome: ManuHeadFund Bot" -ForegroundColor Gray
    Write-Host "3. Username: manuheadfund_bot" -ForegroundColor Gray
    Write-Host "4. Copie o TOKEN" -ForegroundColor Gray
    Write-Host "5. Envie mensagem para o bot" -ForegroundColor Gray
    Write-Host "6. Telegram â†’ @userinfobot â†’ Copie seu ID" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Depois execute:" -ForegroundColor Cyan
    Write-Host '.\scripts\setup_telegram_quick.ps1 -Token "SEU_TOKEN" -ChatId "SEU_CHAT_ID"' -ForegroundColor White
    Write-Host ""
    exit 0
}

Write-Host "`n[1/3] Validando credenciais..." -ForegroundColor Yellow

# Validar token
if ($Token -eq "YOUR_BOT_TOKEN" -or $Token.Length -lt 20) {
    Write-Host "âœ— Token invalido!" -ForegroundColor Red
    exit 1
}

Write-Host "âœ“ Token OK" -ForegroundColor Green

# Validar chat ID
if ($ChatId -eq "YOUR_CHAT_ID" -or $ChatId.Length -lt 5) {
    Write-Host "âœ— Chat ID invalido!" -ForegroundColor Red
    exit 1
}

Write-Host "âœ“ Chat ID OK" -ForegroundColor Green

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

Write-Host "âœ“ Config salva: $configPath" -ForegroundColor Green

Write-Host "`n[3/3] Testando conexao..." -ForegroundColor Yellow

. ".\agents\lib_telegram.ps1"

$testResult = Telegram-SendMessage -Message "âœ… *ManuHeadFund* conectado!`n`nðŸ“Š Dashboard profissional ativo`nðŸ”” Alertas automaticos configurados`n`nSistema operacional!"

if ($testResult.success) {
    Write-Host "âœ“ Mensagem de teste enviada!" -ForegroundColor Green
    Write-Host "`nâ•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—" -ForegroundColor Green
    Write-Host "â•‘       TELEGRAM CONFIGURADO âœ“           â•‘" -ForegroundColor Green
    Write-Host "â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•" -ForegroundColor Green
    Write-Host "`nVerifique seu Telegram agora!" -ForegroundColor Cyan
    Write-Host "`nAlertas ativos:" -ForegroundColor White
    Write-Host "  âœ“ Trailing stop (lucro > 3%)" -ForegroundColor Gray
    Write-Host "  âœ“ Posicoes abertas/fechadas" -ForegroundColor Gray
    Write-Host "  âœ“ Alertas de risco" -ForegroundColor Gray
    Write-Host "  âœ“ Resumo diario" -ForegroundColor Gray
} else {
    Write-Host "âœ— Falha ao enviar: $($testResult.error)" -ForegroundColor Red
    Write-Host "`nVerifique:" -ForegroundColor Yellow
    Write-Host "  - Token correto?" -ForegroundColor Gray
    Write-Host "  - Chat ID correto?" -ForegroundColor Gray
    Write-Host "  - Enviou mensagem para o bot?" -ForegroundColor Gray
    exit 1
}

Write-Host ""
