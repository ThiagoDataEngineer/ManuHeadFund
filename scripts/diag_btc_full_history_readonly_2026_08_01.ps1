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
    # ts vem em MILISSEGUNDOS (confirmado real: 1611532800000 -> FromUnixTimeSeconds
    # rejeitava por estourar o range valido). FromUnixTimeMilliseconds e o certo.
    Write-Host ("Primeiro: ts={0} ({1}) close={2}" -f $first.ts, ([DateTimeOffset]::FromUnixTimeMilliseconds($first.ts).ToString("yyyy-MM-dd")), $first.close)
    Write-Host ("Ultimo:   ts={0} ({1}) close={2}" -f $last.ts, ([DateTimeOffset]::FromUnixTimeMilliseconds($last.ts).ToString("yyyy-MM-dd")), $last.close)
}

$outPath = Join-Path (Join-Path $PSScriptRoot "..") "journal/btc_weekly_history_2026_08_01.json"
$sorted = $candles | Sort-Object ts
$sorted | ConvertTo-Json -Depth 5 | Out-File $outPath -Encoding UTF8
Write-Host "Salvo em $outPath (runner efemero -- print abaixo pra capturar via log)" -ForegroundColor Green

# Print CSV compacto (ts_ms,date,close) pra capturar do log do job direto --
# runner e efemero, o journal salvo acima nao sobrevive ao fim do job.
Write-Host "`n--- CSV completo (ts_ms,date,close) ---" -ForegroundColor Yellow
foreach ($c in $sorted) {
    $d = [DateTimeOffset]::FromUnixTimeMilliseconds($c.ts).ToString("yyyy-MM-dd")
    Write-Host "$($c.ts),$d,$($c.close)"
}

Write-Host "`n=== FIM ===" -ForegroundColor Cyan