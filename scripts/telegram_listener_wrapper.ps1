# Wrapper para telegram_listener que seta env vars antes
param([switch]$Force, [switch]$Once)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Set env vars
$env:TELEGRAM_BOT_TOKEN = "8763265579:AAFPaVZjeS_rQSzs4xpzb9stMG5veP_Qo54"
$env:TELEGRAM_CHAT_ID = "5592104053"

# Call listener com parâmetros passados
& (Join-Path $scriptRoot "telegram_listener.ps1") -Force:$Force -Once:$Once
