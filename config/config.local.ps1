# config.local.ps1 — Credenciais locais ManuHeadFund (2026-07-14)
# Carregado por todos os daemons via:
#   . (Join-Path $agentsDir "config.local.ps1") -ErrorAction SilentlyContinue
# OU
#   . (Join-Path $root "agents/config.local.ps1") -ErrorAction SilentlyContinue

# CoinEx API Credentials (authentication)
# Apenas 2 credenciais sao necessarias (CoinEx nao usa Passphrase)
if (-not $env:COINEX_ACCESS_ID) { $env:COINEX_ACCESS_ID = "PLACEHOLDER_ACCESS_ID" }
if (-not $env:COINEX_SECRET_KEY) { $env:COINEX_SECRET_KEY = "PLACEHOLDER_SECRET_KEY" }

# CoinEx API Base URL
$env:BASE_URL = "https://api.coinex.com/v2"

# Supabase Credentials (state store)
# Carregados de gh secrets na nuvem ou definidos aqui localmente
if (-not $env:SUPABASE_URL) {
    $env:SUPABASE_URL = "https://urcqtpklpfyvizcgcsia.supabase.co"
}
if (-not $env:SUPABASE_ANON_KEY) {
    $env:SUPABASE_ANON_KEY = "sb_publishable_v_dOX1JVgEm_vlT-Qr5lsw_EQHc-av-"
}

# Telegram Alert Credentials (optional, used by some daemons)
# $env:TELEGRAM_BOT_TOKEN = "YOUR_BOT_TOKEN"
# $env:TELEGRAM_CHAT_ID = "YOUR_CHAT_ID"

# Debug flag (opcional)
# $env:DEBUG_MODE = "1"

Write-Host "[config.local.ps1] CoinEx auth: $(if ($env:COINEX_ACCESS_ID -and $env:COINEX_ACCESS_ID -ne 'PLACEHOLDER_ACCESS_ID') { 'CONFIGURED' } else { 'MISSING - using placeholders' })" -ForegroundColor $(if ($env:COINEX_ACCESS_ID -and $env:COINEX_ACCESS_ID -ne 'PLACEHOLDER_ACCESS_ID') { 'Green' } else { 'Yellow' })
