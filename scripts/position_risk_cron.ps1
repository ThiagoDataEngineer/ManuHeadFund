# position_risk_cron.ps1 - Cron job para gestao automatica de risco
# Rodar a cada 5 minutos: */5 * * * * powershell -File position_risk_cron.ps1
# IMPORTANTE: Com posicao aberta, monitoramento a cada 5min e CRITICO!
#
# FUNCOES:
# 1. Trailing stops dinamicos (ATR-based)
# 2. Ajuste de leverage por volatilidade
# 3. Protecao contra liquidacao
# 4. Alertas Telegram

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

# Carregar proteção anti-duplicação
. ".\scripts\check_execution_mode.ps1"

# Executar com proteção (LOCAL ou GITHUB ACTIONS)
Invoke-SafeJob -JobName "risk-manager" -PreferredMode "both" -ScriptBlock {
    . ".\agents\config.ps1"
    . ".\agents\lib_position_risk_manager.ps1"
    . ".\agents\lib_telegram.ps1"

# ============================================================================
# MAIN
# ============================================================================

try {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "POSITION RISK MANAGER - $timestamp" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    # Executar scan completo
    $result = Invoke-PositionRiskScan

    if ($result.success) {
        Write-Host "`n[OK] Scan completo: $($result.positions_scanned) posicoes analisadas" -ForegroundColor Green

        # Resumo de acoes tomadas
        $trailingUpdates = 0
        $leverageAdjusts = 0
        $marginAdds = 0

        foreach ($r in $result.results) {
            if ($r.trailing_stop.success) { $trailingUpdates++ }
            if ($r.leverage_adjust.success) { $leverageAdjusts++ }
            if ($r.liq_protection.success) { $marginAdds++ }
        }

        if ($trailingUpdates -gt 0 -or $leverageAdjusts -gt 0 -or $marginAdds -gt 0) {
            $summary = "Position Risk Manager`n`n" +
                       "Trailing Stops: $trailingUpdates`n" +
                       "Leverage Ajustes: $leverageAdjusts`n" +
                       "Margin Adicionado: $marginAdds`n`n" +
                       "Timestamp: $timestamp"

            Send-TelegramAlert -Message $summary | Out-Null
        }
    } else {
        Write-Host "`n[ERRO] Erro no scan: $($result.error)" -ForegroundColor Red
    }

} catch {
    Write-Host "`n[ERRO CRITICO] $_" -ForegroundColor Red

    # Enviar alerta de erro
    if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
        Send-TelegramAlert -Message "ERRO Position Risk Manager: $_" | Out-Null
    }

    exit 1
}

} # Fim do Invoke-SafeJob
