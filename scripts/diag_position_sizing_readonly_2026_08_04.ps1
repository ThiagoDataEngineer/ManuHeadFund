# diag_position_sizing_readonly_2026_08_04.ps1 -- ONE-SHOT, so leitura.
#
# Owner quer discutir "como ganhar mais" nas posicoes reais abertas
# (BTCUSDT, HYPEUSDT, TIAUSDT, ARBUSDT, ETHUSDT) -- precisa do TAMANHO
# real de cada posicao (margem/notional em USDT), nao so o PnL em dolares
# que o Position Risk Manager ja loga. $0.13 de PnL pode ser otimo ou
# pessimo dependendo se a posicao e de $5 ou $500 de margem.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")

Write-Host "=== DIAG: tamanho real das posicoes FUTURES abertas ===" -ForegroundColor Cyan

$positions = @(CoinEx-GetPendingPositions)
Write-Host "Posicoes encontradas: $($positions.Count)`n"

$totalMargin = 0.0
$totalNotional = 0.0

foreach ($p in $positions) {
    $margin = [double]$p.margin_avbl
    $notional = [double]$p.settle_value
    $leverage = [double]$p.leverage
    $entry = [double]$p.avg_entry_price
    $unrealized = [double]$p.unrealized_pnl
    $qty = [double]$p.open_interest
    $side = [string]$p.side

    $totalMargin += $margin
    $totalNotional += $notional

    Write-Host ("{0,-10} side={1,-5} leverage={2}x qty={3} entry={4} margem=\${5:N2} notional=\${6:N2} pnl_nao_realizado=\${7:N2}" -f `
        $p.market, $side, $leverage, $qty, $entry, $margin, $notional, $unrealized) -ForegroundColor Yellow
}

Write-Host "`n--- Totais ---" -ForegroundColor Cyan
Write-Host "Margem total alocada em FUTURES: `$$([math]::Round($totalMargin,2))"
Write-Host "Notional total (exposicao real): `$$([math]::Round($totalNotional,2))"

try {
    $spot = CoinEx-GetSpotCapitalUSDT
    $fut = CoinEx-GetFuturesCapitalUSDT
    Write-Host "`nCapital SPOT disponivel: `$$spot"
    Write-Host "Capital FUTURES disponivel (livre + em uso): `$$fut"
    Write-Host "Capital TOTAL (spot+futures): `$$([math]::Round([double]$spot + [double]$fut, 2))"
    if (($totalMargin + [double]$fut) -gt 0) {
        $pctAllocated = ($totalMargin / ([double]$fut + $totalMargin)) * 100
        Write-Host "Percentual do capital FUTURES ja alocado em margem: $([math]::Round($pctAllocated,2))%"
    }
} catch {
    Write-Host "ERRO ao buscar capital: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM ===" -ForegroundColor Cyan
