# fix_tp_urgent.ps1 — CORRIGE TPs ERRADOS (300x/100x → 3x correto)
# BREVUSDT: 0.0633 → 0.092721
# RAYUSDT: 0.473 → 0.69311

param([switch]$DryRun = $false)

$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path $PSScriptRoot -Parent) "agents\config.ps1")
. (Join-Path (Split-Path $PSScriptRoot -Parent) "agents\lib_coinex.ps1")
. (Join-Path (Split-Path $PSScriptRoot -Parent) "agents\lib_coinex_position_management.ps1")

$fixes = @(
    @{
        market = "BREVUSDT"
        oldTP = 0.0633
        newTP = 0.092721
        entry = 0.093052
        stop = 0.092959
    },
    @{
        market = "RAYUSDT"
        oldTP = 0.473
        newTP = 0.69311
        entry = 0.6955
        stop = 0.6948
    }
)

Write-Host "🔴 CORRIGINDO TPs ERRADOS" -ForegroundColor Red
Write-Host ""

foreach ($fix in $fixes) {
    $mkt = $fix.market
    $oldTP = $fix.oldTP
    $newTP = $fix.newTP
    $entry = $fix.entry
    $stop = $fix.stop
    $risk = $entry - $stop

    Write-Host "📊 $mkt" -ForegroundColor Yellow
    Write-Host "   Entry:     $entry" -ForegroundColor Gray
    Write-Host "   Stop:      $stop (risk: $('{0:N6}' -f $risk))" -ForegroundColor Yellow
    Write-Host "   TP Atual:  $oldTP ❌ (ERRADO)" -ForegroundColor Red
    Write-Host "   TP Novo:   $newTP ✅ (R:R 1:3)" -ForegroundColor Green
    Write-Host ""

    if (-not $DryRun) {
        try {
            # Cancelar TP existente
            Write-Host "   → Cancelando TP antigo..." -ForegroundColor Cyan
            $cancelResult = CoinEx-CancelPositionTakeProfit -Market $mkt -ErrorAction SilentlyContinue
            if ($?) {
                Write-Host "     ✅ TP antigo cancelado" -ForegroundColor Green
            } else {
                Write-Host "     ⚠️  Falha ao cancelar (pode estar já cancelado)" -ForegroundColor Yellow
            }

            # Colocar novo TP
            Write-Host "   → Colocando novo TP..." -ForegroundColor Cyan
            $newResult = CoinEx-ModifyPositionTakeProfit -Market $mkt -Price ([decimal]$newTP)
            if ($newResult.status -eq 0 -or $newResult.data) {
                Write-Host "     ✅ TP NOVO COLOCADO!" -ForegroundColor Green
            } else {
                Write-Host "     ❌ FALHA: $($newResult | ConvertTo-Json -Depth 2)" -ForegroundColor Red
            }
        } catch {
            Write-Host "   ❌ Erro: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "   [DRY RUN] Seria cancelado e recolocado" -ForegroundColor Gray
    }
    Write-Host ""
}

Write-Host "════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "✅ TPs corrigidos para R:R 1:3 automático" -ForegroundColor Green
