# Wrapper para telegram_listener que seta env vars antes
param([switch]$Force, [switch]$Once)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$configPath = Join-Path (Join-Path $projectRoot "config") "telegram.json"

# Load config from telegram.json (git-tracked, always up-to-date)
if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $env:TELEGRAM_BOT_TOKEN = $config.bot_token
        $env:TELEGRAM_CHAT_ID = $config.chat_id
    } catch {
        Write-Error "Failed to load telegram config: $_"
        exit 1
    }
} else {
    Write-Error "telegram.json not found at $configPath"
    exit 1
}

# Call listener com parâmetros passados
& (Join-Path $scriptRoot "telegram_listener.ps1") -Force:$Force -Once:$Once
