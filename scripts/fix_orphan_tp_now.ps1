# fix_orphan_tp_now.ps1 — Coloca TP automático em posições SEM TP
# 2026-07-02: BREVUSDT + RAYUSDT abertos SEM TP
# Cálculo: RR 1:3 padrão (stop já existe)

param(
    [switch]$DryRun
)

. (Join-Path (Split-Path $PSScriptRoot -Parent) "agents\config.ps1")
. (Join-Path (Split-Path $PSScriptRoot -Parent) "agents\lib_coinex.ps1")
. (Join-Path (Split-Path $PSScriptRoot -Parent) "agents\lib_coinex_position_management.ps1")

$positions = @(
    @{
        market = "BREVUSDT"
        side = "sell"  # SHORT
        entry = 0.093052
        stop = 0.092959
        rr_ratio = 3.0
    },
    @{
        market = "RAYUSDT"
        side = "sell"  # SHORT
        entry = 0.6955
        stop = 0.6948
        rr_ratio = 3.0
    }
)

Write-Host "🔧 COLOCANDO TP AUTOMÁTICO (RR 1:3)" -ForegroundColor Cyan
Write-Host ""

foreach ($pos in $positions) {
    $mkt = $pos.market
    $entry = [double]$pos.entry
    $stop = [double]$pos.stop
    $rr = [double]$pos.rr_ratio

    # SHORT: stop acima, target abaixo
    # risk = entry - stop
    # target = entry - (risk × RR)
    $risk = [double]($entry - $stop)
    $target = [double]($entry - ($risk * $rr))

    # Forçar conversão para decimal com 8 casas
    $targetDecimal = [decimal]::Round([decimal]$target, 8)

    Write-Host "📊 $mkt" -ForegroundColor White
    Write-Host "   Entry:  $entry" -ForegroundColor Gray
    Write-Host "   Stop:   $stop (risk: $('{0:N6}' -f $risk))" -ForegroundColor Yellow
    Write-Host "   Target: $('{0:N6}' -f $target) (R:R 1:$rr)" -ForegroundColor Green

    if (-not $DryRun) {
        try {
            # CoinEx ModifyPositionTakeProfit para futures (parâmetro: -Price, não -TakeProfit)
            $result = CoinEx-ModifyPositionTakeProfit -Market $mkt -Price $targetDecimal
            if ($result.success) {
                Write-Host "   ✅ TP COLOCADO!" -ForegroundColor Green
            } else {
                Write-Host "   ⚠️  Falha: code=$($result.error_code) msg=$($result.error_msg)" -ForegroundColor Red
                Write-Host "   📝 Debug: $($result | ConvertTo-Json)" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "   ❌ Erro: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "   [DRY RUN] Seria colocado" -ForegroundColor DarkGray
    }
    Write-Host ""
}

Write-Host "════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "✅ Posições protegidas com R:R 1:3 automático" -ForegroundColor Green
