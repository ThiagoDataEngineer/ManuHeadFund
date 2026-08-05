# diag_spot_radar_impact_2026_08_04.ps1 -- ONE-SHOT, so leitura.
#
# Owner pediu (antes de decidir estender o radar dinamico pra SPOT) entender
# o impacto real: quantas moedas SPOT-only (sem contrato FUTURES) tem
# movimento forte de 24h AGORA, que hoje nunca entram no scan GEM porque
# scripts/gem_scanner_executor_live.ps1 so chama CoinEx-GetAllFuturesTickers
# no radar dinamico (CoinEx-GetAllSpotTickers existe pronta, nunca usada
# nesse fluxo).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_market_movers.ps1")

Write-Host "=== DIAG: impacto real de estender o radar dinamico pra SPOT ===" -ForegroundColor Cyan

try {
    $futTickers = @(CoinEx-GetAllFuturesTickers)
    $spotTickers = @(CoinEx-GetAllSpotTickers)
    Write-Host "Total tickers FUTURES: $($futTickers.Count) | Total tickers SPOT: $($spotTickers.Count)"

    $futSymbols = @{}
    foreach ($t in $futTickers) { $futSymbols[[string]$t.market] = $true }

    # Movers FUTURES (comportamento atual, ja em producao)
    $futMovers = @(Get-DynamicMarketMoversFromRawTickers -RawTickers $futTickers -ExcludeSymbols @())
    Write-Host "`nMovers FUTURES (threshold 24h +-10%, comportamento ATUAL): $($futMovers.Count)"
    $futMovers | Sort-Object { [math]::Abs($_.change_24h) } -Descending | Select-Object -First 15 | ForEach-Object {
        Write-Host ("  {0,-16} change_24h={1,7:N2}%" -f $_.symbol, $_.change_24h)
    }

    # Movers SPOT (proposto) -- exclui symbols que JA tem contrato futures
    # (esses ja seriam capturados pelo radar de futures acima, nao duplicar).
    $spotOnlySymbols = @($spotTickers | Where-Object { -not $futSymbols.ContainsKey([string]$_.market) })
    Write-Host "`nTickers SPOT que NAO tem contrato FUTURES (universo novo real): $($spotOnlySymbols.Count)"

    $spotMovers = @(Get-DynamicMarketMoversFromRawTickers -RawTickers $spotOnlySymbols -ExcludeSymbols @())
    Write-Host "`nMovers SPOT-ONLY (threshold 24h +-10%, PROPOSTO -- hoje invisivel pro scanner): $($spotMovers.Count)"
    $spotMovers | Sort-Object { [math]::Abs($_.change_24h) } -Descending | Select-Object -First 20 | ForEach-Object {
        Write-Host ("  {0,-16} change_24h={1,7:N2}% vol24h=`${2:N0}" -f $_.symbol, $_.change_24h, $_.volume24h)
    }

    Write-Host "`n--- Resumo ---" -ForegroundColor Yellow
    Write-Host "Universo hoje (curadoria 26 + radar futures): ate $($futMovers.Count) movers extras"
    Write-Host "Universo COM radar SPOT: mais $($spotMovers.Count) movers extras que hoje sao 100% invisiveis"
    Write-Host "Aumento no numero de candidatos avaliados por ciclo: +$($spotMovers.Count) (antes de qualquer filtro de volume/liquidez)"

} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
