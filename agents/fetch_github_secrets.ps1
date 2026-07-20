# fetch_github_secrets.ps1
# Busca secrets do GitHub Actions via gh CLI
# Escreve em config.local.ps1

#Requires -Version 5.1

$configLocalPath = Join-Path $PSScriptRoot "config.local.ps1"
$repoOwner = "ThiagoDataEngineer"
$repoName = "ManuHeadFund"

Write-Host "=== FETCH GITHUB SECRETS ===" -ForegroundColor Cyan
Write-Host ""

# Verificar se gh CLI está disponível
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "❌ GitHub CLI (gh) não está instalado" -ForegroundColor Red
    Write-Host "   Instale em: https://cli.github.com/" -ForegroundColor Yellow
    exit 1
}

# Verificar se autenticado
try {
    $user = gh auth status 2>&1
    Write-Host "✅ GitHub CLI autenticado" -ForegroundColor Green
} catch {
    Write-Host "❌ Não autenticado no GitHub" -ForegroundColor Red
    Write-Host "   Execute: gh auth login" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "🔐 Buscando secrets..." -ForegroundColor Yellow

$secrets = @(
    "COINEX_ACCESS_ID"
    "COINEX_SECRET_KEY"
    "TELEGRAM_BOT_TOKEN"
    "TELEGRAM_CHAT_ID"
    "SUPABASE_URL"
    "SUPABASE_ANON_KEY"
    "SUPABASE_SERVICE_KEY"
    "ANTHROPIC_API_KEY"
)

$content = ""
foreach ($secret in $secrets) {
    try {
        $value = gh secret view $secret --repo "$repoOwner/$repoName" 2>&1 | Select-Object -First 1
        if ($value -and $value -notmatch "error|not found") {
            $content += "`$env:${secret} = '$value'" + "`n"
            Write-Host "   ✅ $secret" -ForegroundColor Green
        } else {
            Write-Host "   ⚠️  $secret (não encontrado)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "   ❌ ${secret}: $_" -ForegroundColor Red
    }
}

if ($content) {
    $content | Out-File $configLocalPath -Encoding UTF8 -Force
    Write-Host ""
    Write-Host "✅ config.local.ps1 criado com secrets do GitHub!" -ForegroundColor Green
    Write-Host "📁 $configLocalPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Credenciais carregadas:" -ForegroundColor Green
    Get-Content $configLocalPath | ForEach-Object {
        if ($_ -match "^`$env:") {
            $parts = $_ -split "="
            $name = $parts[0].Trim().Replace('$env:', '')
            Write-Host "   ✓ $name" -ForegroundColor White
        }
    }
} else {
    Write-Host ""
    Write-Host "❌ Nenhum secret foi recuperado" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🚀 Daemon posso começar agora!" -ForegroundColor Green
Write-Host "   Reiniciar position_sync_loop.ps1" -ForegroundColor Cyan
