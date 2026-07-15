# diag_capital_readonly_2026_07_15.ps1 -- diagnostico ONE-SHOT, so leitura
# Confirma capital SPOT/FUTURES real antes de forcar 1 trade de teste
# controlado pra provar o caminho de execucao pos-gates (nunca exercitado
# em producao, breadth neutro bloqueou 100% dos candidatos ate agora).
# NAO envia nenhuma ordem. Remover job apos uso.

$agentsDir = Join-Path $PSScriptRoot ".." "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
# config.ps1 copia $env:COINEX_ACCESS_ID -> $COINEX_ACCESS_ID (variavel de
# script, sem $env:) -- lib_coinex.ps1 le a variavel de script, nao a env var
# diretamente. Sem este dot-source, credenciais ficam "ausentes" mesmo com
# config.local.ps1 carregado.
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")

Write-Host "=== DIAG CAPITAL (READ-ONLY) ===" -ForegroundColor Cyan

try {
    $spot = CoinEx-GetSpotCapitalUSDT
    Write-Host "SPOT capital: $spot USDT" -ForegroundColor Green
} catch {
    Write-Host "SPOT capital: ERRO -- $_" -ForegroundColor Red
}

try {
    $fut = CoinEx-GetFuturesCapitalUSDT
    Write-Host "FUTURES capital: $fut USDT" -ForegroundColor Green
} catch {
    Write-Host "FUTURES capital: ERRO -- $_" -ForegroundColor Red
}

Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
