# setup_credentials_local.ps1
# Carrega credenciais de GitHub Actions secrets OU pede ao usuário
# EXATAMENTE como trading-pipeline.yml faz

#Requires -Version 5.1

$configLocalPath = Join-Path $PSScriptRoot "config.local.ps1"

Write-Host "=== SETUP CREDENCIAIS LOCAIS ===" -ForegroundColor Cyan
Write-Host ""

# Opção 1: GitHub Actions Secrets (se rodando em Actions)
if ($env:GITHUB_ACTIONS -eq "true") {
    Write-Host "🔍 Rodando em GitHub Actions - credenciais via secrets" -ForegroundColor Green

    $content = '$env:COINEX_ACCESS_ID = ''${{ secrets.COINEX_ACCESS_ID }}''' + "`n"
    $content += '$env:COINEX_SECRET_KEY = ''${{ secrets.COINEX_SECRET_KEY }}''' + "`n"
    $content += '$env:TELEGRAM_BOT_TOKEN = ''${{ secrets.TELEGRAM_BOT_TOKEN }}''' + "`n"
    $content += '$env:TELEGRAM_CHAT_ID = ''${{ secrets.TELEGRAM_CHAT_ID }}''' + "`n"
    $content += '$env:SUPABASE_URL = ''${{ secrets.SUPABASE_URL }}''' + "`n"
    $content += '$env:SUPABASE_ANON_KEY = ''${{ secrets.SUPABASE_ANON_KEY }}''' + "`n"
    $content += '$env:SUPABASE_SERVICE_KEY = ''${{ secrets.SUPABASE_SERVICE_KEY }}''' + "`n"

    $content | Out-File $configLocalPath -Encoding UTF8 -Force
    Write-Host "✅ config.local.ps1 criado com credenciais de secrets" -ForegroundColor Green
}
else {
    # Opção 2: Local - pedir ao usuário
    Write-Host "📝 Rodando localmente - insira suas credenciais" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "Você pode encontrar suas credenciais em:" -ForegroundColor Cyan
    Write-Host "├ CoinEx: https://www.coinex.com/user/setting/api" -ForegroundColor White
    Write-Host "├ Telegram Bot: @BotFather no Telegram" -ForegroundColor White
    Write-Host "└ Supabase: https://supabase.com/dashboard" -ForegroundColor White
    Write-Host ""

    $content = ""

    # CoinEx credentials
    $accessId = Read-Host "COINEX_ACCESS_ID"
    if ($accessId) {
        $content += "`$env:COINEX_ACCESS_ID = '$accessId'" + "`n"
    }

    $secretKey = Read-Host "COINEX_SECRET_KEY"
    if ($secretKey) {
        $content += "`$env:COINEX_SECRET_KEY = '$secretKey'" + "`n"
    }

    # Telegram
    $tgToken = Read-Host "TELEGRAM_BOT_TOKEN (opcional)"
    if ($tgToken) {
        $content += "`$env:TELEGRAM_BOT_TOKEN = '$tgToken'" + "`n"
    }

    $tgChatId = Read-Host "TELEGRAM_CHAT_ID (opcional)"
    if ($tgChatId) {
        $content += "`$env:TELEGRAM_CHAT_ID = '$tgChatId'" + "`n"
    }

    # Supabase
    $supUrl = Read-Host "SUPABASE_URL (opcional)"
    if ($supUrl) {
        $content += "`$env:SUPABASE_URL = '$supUrl'" + "`n"
    }

    $supAnonKey = Read-Host "SUPABASE_ANON_KEY (opcional)"
    if ($supAnonKey) {
        $content += "`$env:SUPABASE_ANON_KEY = '$supAnonKey'" + "`n"
    }

    $supServiceKey = Read-Host "SUPABASE_SERVICE_KEY (opcional)"
    if ($supServiceKey) {
        $content += "`$env:SUPABASE_SERVICE_KEY = '$supServiceKey'" + "`n"
    }

    if ($content) {
        $content | Out-File $configLocalPath -Encoding UTF8 -Force
        Write-Host ""
        Write-Host "✅ config.local.ps1 criado com suas credenciais" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "⚠️  Nenhuma credencial fornecida" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "📁 Arquivo: $configLocalPath" -ForegroundColor Cyan
if (Test-Path $configLocalPath) {
    Write-Host "📊 Conteúdo:" -ForegroundColor Green
    Get-Content $configLocalPath | ForEach-Object {
        if ($_ -match "=") {
            $parts = $_ -split "="
            $masked = $parts[1] -replace ".(?=.{4})", "*"
            Write-Host "   $($parts[0]) = $masked" -ForegroundColor White
        }
    }
}

Write-Host ""
Write-Host "🚀 Próximo: Reiniciar daemon" -ForegroundColor Green
Write-Host "   . agents\config.local.ps1" -ForegroundColor Cyan
Write-Host "   position_sync_loop.ps1 começará a sincronizar" -ForegroundColor Cyan
