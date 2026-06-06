# auto_market_monitor.ps1
# Inicia monitor multi-mercado em loop infinito
# Gera alertas e reports automáticos

$ErrorActionPreference = "Continue"

while ($true) {
    try {
        & ".\scripts\multi_market_pattern_monitor.ps1" -IntervalSeconds 60 -MaxHistory 100
    } catch {
        Write-Host "[ERROR] Monitor falhou: $_" -ForegroundColor Red
        Start-Sleep -Seconds 30
    }
}
