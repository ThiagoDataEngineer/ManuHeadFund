# diag_btc_full_history_readonly_2026_08_01.ps1 -- ONE-SHOT, so leitura.
#
# Owner pediu pra materializar o ciclo do BTC com dado real (nao so o modelo
# teorico de halving). Puxa candles semanais de BTCUSDT (maior granularidade
# que cobre o historico completo em poucas linhas) direto da CoinEx e salva
# em JSON pra montar o grafico real no artifact.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")

Write-Host "=== DIAG: historico completo BTCUSDT (semanal) ===" -ForegroundColor Cyan

$candles = CoinEx-GetCandles -market "BTCUSDT" -period "1w" -limit 1000
Write-Host "Candles retornados: $($candles.Count)"
if ($candles.Count -gt 0) {
    $first = $candles | Sort-Object ts | Select-Object -First 1
    $last  = $candles | Sort-Object ts | Select-Object -Last 1
    Write-Host ("Primeiro: ts={0} ({1}) close={2}" -f $first.ts, ([DateTimeOffset]::FromUnixTimeSeconds($first.ts).ToString("yyyy-MM-dd")), $first.close)
    Write-Host ("Ultimo:   ts={0} ({1}) close={2}" -f $last.ts, ([DateTimeOffset]::FromUnixTimeSeconds($last.ts).ToString("yyyy-MM-dd")), $last.close)
}

$outPath = Join-Path (Join-Path $PSScriptRoot "..") "journal/btc_weekly_history_2026_08_01.json"
$candles | Sort-Object ts | ConvertTo-Json -Depth 5 | Out-File $outPath -Encoding UTF8
Write-Host "Salvo em $outPath" -ForegroundColor Green

Write-Host "`n=== FIM ===" -ForegroundColor Cyan