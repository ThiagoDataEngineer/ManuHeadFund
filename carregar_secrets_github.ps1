# carregar_secrets_github.ps1 - Load GitHub Actions secrets locally
# Carrega credenciais de GitHub Actions para uso local via config.local.ps1
# 2026-07-09 - VERSAO CORRIGIDA (sem gh secret view, usa setup via config)

Write-Host "`nCarregando secrets para ambiente local..." -ForegroundColor Cyan
Write-Host "Metodo: config.local.ps1 + GitHub Secrets`n" -ForegroundColor Yellow

# Verifica se config.local.ps1 existe
if (-not (Test-Path "agents/config.local.ps1")) {
    Write-Host "Erro: agents/config.local.ps1 nao encontrado" -ForegroundColor Red
    exit 1
}

# Carrega config.local.ps1 (tem fallback para env vars)
. agents/config.local.ps1

# Agora settar as vars que vem de env (GitHub Actions as passa automaticamente)
$secrets_to_load = @(
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
foreach ($secret in $secrets_to_load) {
    $envValue = [System.Environment]::GetEnvironmentVariable($secret)
    if ($envValue -and -not ($envValue -like "*placeholder*")) {
        [System.Environment]::SetEnvironmentVariable($secret, $envValue, "Process")
        $masked = $envValue.Substring(0, [Math]::Min(4, $envValue.Length)) + ("*" * [Math]::Max(0, $envValue.Length - 4))
        Write-Host "  OK $secret = $masked" -ForegroundColor Green
        $loaded++
    } else {
        Write-Host "  -- $secret (vazio/placeholder)" -ForegroundColor Yellow
    }
}

Write-Host "`nResultado: $loaded carregadas`n" -ForegroundColor Cyan

if ($loaded -eq 0) {
    Write-Host "INFO: Nenhum secret do GitHub carregado localmente." -ForegroundColor Yellow
    Write-Host "      Isso é normal em ambiente local sem GitHub Actions." -ForegroundColor Yellow
    Write-Host "      Para testar, execute em GitHub Actions ou settar env vars manualmente:" -ForegroundColor Gray
    Write-Host '      `$env:GROQ_API_KEY = "gsk_..."' -ForegroundColor Cyan
} else {
    Write-Host "Proximo: . diagnostico_bloqueios.ps1`n" -ForegroundColor Green
}
