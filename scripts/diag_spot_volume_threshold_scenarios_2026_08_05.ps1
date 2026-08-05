# diag_spot_volume_threshold_scenarios_2026_08_05.ps1 -- ONE-SHOT, so leitura.
#
# Achado real (run 31017396381, producao): radar dinamico SPOT trouxe 10
# movers reais (HEIUSDT, EVRMOREUSDT, CYSUSDT, etc) mas TODOS foram
# descartados pelo piso de volume24h < $100k que ja existe em
# scripts/gem_scanner_executor_live.ps1 [2] GENERATE CANDIDATES (aplicado
# igualmente a curadoria manual + radar futures + radar SPOT). Owner quer
# ver quantos candidatos SPOT-only passariam com pisos mais baixos antes
# de decidir se vale abaixar.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_market_movers.ps1")

Write-Host "=== DIAG: cenarios de piso de volume pro radar SPOT ===" -ForegroundColor Cyan

try {
    $futTickers = @(CoinEx-GetAllFuturesTickers)
    $spotTickers = @(CoinEx-GetAllSpotTickers)
    $futSymbols = @{}
    foreach ($t in $futTickers) { $futSymbols[[string]$t.market] = $true }
    $spotOnlyTickers = @($spotTickers | Where-Object { -not $futSymbols.ContainsKey([string]$_.market) })

    # Sem MaxResults aqui -- queremos ver o universo TODO de movers SPOT-only
    # antes de qualquer teto, pra decidir o piso de volume com visao completa.
    $allSpotMovers = @(Get-DynamicMarketMoversFromRawTickers -RawTickers $spotOnlyTickers -ExcludeSymbols @())
    Write-Host "Total movers SPOT-only (|change_24h|>=10%, sem teto de volume): $($allSpotMovers.Count)`n"

    foreach ($threshold in @(0, 5000, 10000, 20000, 30000, 50000, 100000)) {
        $passing = @($allSpotMovers | Where-Object { [double]$_.volume24h -ge $threshold })
        Write-Host ("Piso `${0,-8}: {1,3} candidatos passariam" -f $threshold, $passing.Count)
    }

    Write-Host "`n--- Todos os movers SPOT-only, ordenados por volume24h (desc) ---" -ForegroundColor Yellow
    $allSpotMovers | Sort-Object { [double]$_.volume24h } -Descending | ForEach-Object {
        Write-Host ("  {0,-16} change_24h={1,7:N2}%  vol24h=`${2:N0}" -f $_.symbol, $_.change_24h, $_.volume24h)
    }

    Write-Host "`n--- Com piso $30000, top 10 por forca de movimento (o que entraria de fato) ---" -ForegroundColor Yellow
    $withThreshold = @($allSpotMovers | Where-Object { [double]$_.volume24h -ge 30000 })
    $top10 = @($withThreshold | Sort-Object { [math]::Abs($_.change_24h) } -Descending | Select-Object -First 10)
    $top10 | ForEach-Object {
        Write-Host ("  {0,-16} change_24h={1,7:N2}%  vol24h=`${2:N0}" -f $_.symbol, $_.change_24h, $_.volume24h)
    }

} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
