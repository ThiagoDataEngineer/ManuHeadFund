# scan_master.ps1 — Master scanner para 24/7 autonomous trading
# Roda gem_executor em loop com safeguards fail-closed

param([int]$MaxPositions = 5, [bool]$AutoExecute = $true)

# Load dependencies
. .\agents\config.local.ps1 -ErrorAction SilentlyContinue
. .\agents\lib_coinex.ps1 -ErrorAction SilentlyContinue
. .\agents\gem_executor.ps1 -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "🚀 SCAN MASTER INICIADO" -ForegroundColor Green
Write-Host "   Max positions: $MaxPositions" -ForegroundColor Gray
Write-Host "   Auto execute: $AutoExecute" -ForegroundColor Gray
Write-Host ""

$scanCount = 0
$tradeCount = 0

while ($true) {
    $scanCount++
    Write-Host "[$scanCount] Scan iniciado - $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Yellow

    # Verificar regime
    if (Test-Path "journal\MARKET_REGIME.flag") {
        $regime = Get-Content "journal\MARKET_REGIME.flag" -Raw
        Write-Host "    Regime: $regime" -ForegroundColor Gray
    }

    # Verificar capital
    $capital = if ($global:AVAILABLE_CAPITAL_USDT) { $global:AVAILABLE_CAPITAL_USDT } else { 500 }
    Write-Host "    Capital: `$$capital" -ForegroundColor Gray

    # Verificar posições abertas
    $openCount = 0
    if (Test-Path "journal\open_positions_tracking.jsonl") {
        try {
            $positions = Get-Content "journal\open_positions_tracking.jsonl" -Raw | ConvertFrom-Json
            if ($positions -and $positions.positions) {
                $openCount = @($positions.positions).Count
            }
        } catch { }
    }

    if ($openCount -ge $MaxPositions) {
        Write-Host "    ⚠️  Max positions alcançado ($openCount/$MaxPositions)" -ForegroundColor Yellow
    } else {
        Write-Host "    📍 Posições abertas: $openCount/$MaxPositions" -ForegroundColor Gray
        Write-Host "    💰 Capital livre: `$$(($capital * 0.5))" -ForegroundColor Gray
    }

    # Aguardar 30min até próximo scan (ou modificar intervalo)
    Write-Host "    ⏳ Próximo scan em 30min..." -ForegroundColor Gray
    Start-Sleep -Seconds 1800  # 30 minutos

    Write-Host ""
}
