# diag_babyusdt_ticker_check_readonly_2026_08_02.ps1 -- ONE-SHOT, so leitura.
#
# Owner notou que BABYUSDT (apareceu no radar dinamico SHORT como +2 movers
# de 24h, run 30733596594) NAO aparece nas telas reais da CoinEx (Top
# Gainers/Value Leaders nem na lista ordenada por 24h ascendente) que ele
# capturou manualmente. Precisa confirmar se BABYUSDT existe de verdade como
# par FUTURES USDT com o open/close que o radar calculou, ou se e um
# artefato (par delistado/thin/bug de parsing).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "lib_coinex.ps1")

Write-Host "=== DIAG: BABYUSDT e RATSUSDT -- ticker real CoinEx ===" -ForegroundColor Cyan

$allTickers = @(CoinEx-GetAllFuturesTickers)
Write-Host "Total tickers FUTURES: $($allTickers.Count)"

foreach ($sym in @("BABYUSDT", "RATSUSDT")) {
    $t = $allTickers | Where-Object { $_.market -eq $sym }
    if ($t) {
        $open = [double]$t.open
        $close = [double]$t.close
        $change = if ($open -gt 0) { (($close - $open) / $open) * 100 } else { 0 }
        Write-Host ("{0}: open={1} close={2} change_24h={3:N2}% value={4}" -f $sym, $t.open, $t.close, $change, $t.value) -ForegroundColor Yellow
    } else {
        Write-Host "$sym : NAO ENCONTRADO em CoinEx-GetAllFuturesTickers" -ForegroundColor Red
    }
}

Write-Host "`n--- Todos os simbolos que contem 'BABY' (qualquer variante) ---" -ForegroundColor Yellow
$allTickers | Where-Object { $_.market -like "*BABY*" } | ForEach-Object {
    $open = [double]$_.open
    $close = [double]$_.close
    $change = if ($open -gt 0) { (($close - $open) / $open) * 100 } else { 0 }
    Write-Host ("{0}: open={1} close={2} change_24h={3:N2}%" -f $_.market, $_.open, $_.close, $change)
}

Write-Host "`n=== FIM ===" -ForegroundColor Cyan
