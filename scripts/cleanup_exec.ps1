# cleanup_exec.ps1 - Executa limpeza de carteira
$ErrorActionPreference = "Continue"

cd (Split-Path $MyInvocation.MyCommand.Path -Parent)
cd ..

Write-Host "=== CLEANUP CARTEIRA ===" -ForegroundColor Cyan

# Libs
. "agents\config.ps1"
. "agents\lib_coinex.ps1"

# 1. PREÇOS
Write-Host "`nConsultando precos..." -ForegroundColor Yellow
$prices = @{}
$symbols = "CRO","OPN","XRP","FIRO","BTC","PAXG"

foreach ($symbol in $symbols) {
    try {
        $pair = "$symbol`USDT"
        $ticker = CoinEx-GetTicker -Market $pair
        if ($ticker.data.last) {
            $p = [double]$ticker.data.last
            $prices[$symbol] = $p
            Write-Host "  $symbol = `$$p"
        }
    } catch {
        Write-Host "  ! $symbol erro"
    }
    Start-Sleep -Milliseconds 300
}

# 2. VENDER
Write-Host "`nVendendo..." -ForegroundColor Cyan

$sales = @(
    @{sym="CRO"; amt=76.98}
    @{sym="OPN"; amt=75.40}
    @{sym="XRP"; amt=22.33}
    @{sym="FIRO"; amt=23.17}
)

$total = 0
foreach ($sale in $sales) {
    $s = $sale.sym
    $a = $sale.amt

    if ($prices.ContainsKey($s)) {
        $v = $a * $prices[$s]
        $total += $v

        Write-Host "  $s..." -NoNewline
        try {
            $order = CoinEx-PlaceSpotOrder -Market "$s`USDT" -Side "sell" -Amount $a
            if ($order.data.order_id) {
                Write-Host " OK"
            } else {
                Write-Host " VAZIO"
            }
        } catch {
            Write-Host " ERRO"
        }
        Start-Sleep -Milliseconds 500
    }
}

Write-Host "`nRecuperacao: `$$([math]::Round($total, 2))" -ForegroundColor Green
Write-Host "BTC+PAXG: preservados" -ForegroundColor Green
