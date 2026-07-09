# carregar_secrets_github.ps1 - Load GitHub Actions secrets locally
# Carrega credenciais de GitHub Actions para uso local
# 2026-07-09

Write-Host "`n`$(_)" -ForegroundColor Cyan
Write-Host "Carregando secrets de GitHub Actions..." -ForegroundColor Cyan
Write-Host "Requer: gh CLI autenticado`n" -ForegroundColor Yellow

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "Erro: GitHub CLI nao encontrado. Instale em https://cli.github.com" -ForegroundColor Red
    exit 1
}

$secrets = @(
    "GROQ_API_KEY",
    "GROQ_API_KEY_2",
    "ANTHROPIC_API_KEY",
    "COINEX_ACCESS_ID",
    "COINEX_SECRET_KEY",
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "SUPABASE_SERVICE_KEY",
    "TELEGRAM_BOT_TOKEN",
    "TELEGRAM_CHAT_ID"
)

$loaded = 0
$failed = 0

foreach ($secret in $secrets) {
    try {
        $value = gh secret view $secret 2>$null
        if ($LASTEXITCODE -eq 0 -and $value) {
            [System.Environment]::SetEnvironmentVariable($secret, $value, "Process")
            $masked = if ($value.Length -gt 4) { $value.Substring(0, 4) + ("*" * ($value.Length - 4)) } else { "****" }
            Write-Host "  OK $secret = $masked" -ForegroundColor Green
            $loaded++
        } else {
            Write-Host "  -- $secret (nao encontrado)" -ForegroundColor Yellow
            $failed++
        }
    } catch {
        Write-Host "  ERROR $secret : $($_.Exception.Message.Substring(0, 40))" -ForegroundColor Red
        $failed++
    }
}

Write-Host "`nResultado: $loaded carregadas, $failed faltando`n" -ForegroundColor Cyan
if ($loaded -eq 0) {
    Write-Host "Erro: Nenhum secret carregado. gh auth status?" -ForegroundColor Red
}

Write-Host "Proximo: . diagnostico_bloqueios.ps1`n" -ForegroundColor Green
