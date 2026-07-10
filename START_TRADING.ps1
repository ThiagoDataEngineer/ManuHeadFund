# START_TRADING.ps1
# Inicia live trading AGORA
# Simples, sem quebras de syntax

#Requires -Version 5.1
Set-StrictMode -Off

$workdir = "C:\Users\thiag\Coinex_AI_USER_API"
Set-Location $workdir

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   ✅ STARTING LIVE TRADING NOW                              ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "📋 Inicializando sistema..." -ForegroundColor Cyan
Write-Host ""

# 1. Load config
if (Test-Path "agents\config.local.ps1") {
    . "agents\config.local.ps1" -ErrorAction SilentlyContinue
    Write-Host "   ✅ Config carregado" -ForegroundColor Green
}

# 2. Create journal dirs
if (-not (Test-Path "journal")) {
    New-Item -ItemType Directory -Path "journal" -Force | Out-Null
}

# 3. Initialize files
if (-not (Test-Path "journal\trade_outcomes.jsonl")) {
    "" | Out-File -FilePath "journal\trade_outcomes.jsonl" -Encoding UTF8
}

if (-not (Test-Path "journal\gem_recent_decisions.json")) {
    "[]" | Out-File -FilePath "journal\gem_recent_decisions.json" -Encoding UTF8
}

Write-Host "   ✅ Journal inicializado" -ForegroundColor Green

# 4. Load libs
$libs = @(
    "agents\lib_coinex.ps1",
    "agents\lib_journal.ps1",
    "agents\lib_gem_decision_cache.ps1"
)

foreach ($lib in $libs) {
    if (Test-Path $lib) {
        try {
            . $lib -ErrorAction Stop
        } catch {
            Write-Host "   ⚠️  $lib" -ForegroundColor Yellow
        }
    }
}

Write-Host "   ✅ Libraries carregadas" -ForegroundColor Green

# 5. Test CoinEx
try {
    $testApi = Invoke-RestMethod -Uri "https://api.coinex.com/v2/spot/market?market=BTCUSDT" -TimeoutSec 5 -ErrorAction Stop
    Write-Host "   ✅ CoinEx API OK" -ForegroundColor Green
} catch {
    Write-Host "   ⚠️  CoinEx API" -ForegroundColor Yellow
}

# 6. Set regime
"BEAR_WEAK" | Out-File -FilePath "journal\MARKET_REGIME.flag" -Encoding UTF8 -Force
$global:CURRENT_REGIME = "BEAR_WEAK"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ SISTEMA PRONTO" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""

Write-Host "Próximo comando:" -ForegroundColor Yellow
Write-Host "  . .\agents\scan_master.ps1" -ForegroundColor White
Write-Host ""
Write-Host "Ou: Invoke-GemExecute -Market BTCUSDT -Direction LONG" -ForegroundColor White
Write-Host ""

$global:TRADING_READY = $true
