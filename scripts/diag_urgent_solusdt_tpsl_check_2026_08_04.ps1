# diag_urgent_solusdt_tpsl_check_2026_08_04.ps1 -- ONE-SHOT, so leitura, URGENTE.
#
# Owner reportou (2026-08-04 ~12:39 UTC): posicao SOLUSDT SHORT futures aberta
# por volta das 07:00 UTC (~5.5h atras) aparentemente SEM TP/SL. Este script
# consulta a API CoinEx DIRETAMENTE (nao o journal/trailing_state, que pode
# estar desatualizado) e imprime TODOS os campos de protecao (TP e SL) da
# posicao real, sem filtro nem dependencia de estado local.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG URGENTE: TP/SL real SOLUSDT (direto na CoinEx) ===" -ForegroundColor Cyan

try {
    $allPos = @(CoinEx-GetPendingPositions)
    Write-Host "Total posicoes FUTURES abertas: $($allPos.Count)`n"

    foreach ($p in $allPos) {
        $mkt = [string]$p.market
        $side = if ($p.PSObject.Properties['side']) { [string]$p.side } else { "?" }
        $isSol = $mkt -eq "SOLUSDT"
        $color = if ($isSol) { "Yellow" } else { "White" }

        Write-Host "--- $mkt (side=$side) ---" -ForegroundColor $color
        Write-Host ("  open_time raw: {0}" -f ($p.PSObject.Properties['created_at'].Value))
        Write-Host ("  stop_loss_price: {0}" -f ($p.PSObject.Properties['stop_loss_price'].Value))
        Write-Host ("  take_profit_price: {0}" -f ($p.PSObject.Properties['take_profit_price'].Value))
        if ($p.PSObject.Properties['stop_loss_type']) { Write-Host ("  stop_loss_type: {0}" -f $p.stop_loss_type) }
        if ($p.PSObject.Properties['take_profit_type']) { Write-Host ("  take_profit_type: {0}" -f $p.take_profit_type) }
        if ($isSol) {
            Write-Host "  --- RAW COMPLETO ---" -ForegroundColor Yellow
            $p | ConvertTo-Json -Depth 6 | Write-Host
        }
    }

    Write-Host "`n=== VERIFICACAO ESPECIFICA SOLUSDT (CoinEx-GetPosition) ===" -ForegroundColor Cyan
    try {
        $solDirect = CoinEx-GetPosition -market "SOLUSDT"
        $solDirect | ConvertTo-Json -Depth 6 | Write-Host
    } catch {
        Write-Host "CoinEx-GetPosition -market SOLUSDT falhou (funcao pode nao existir/nome diferente): $_" -ForegroundColor DarkYellow
    }

    Write-Host "`n=== RESUMO ===" -ForegroundColor Cyan
    $sol = $allPos | Where-Object { $_.market -eq "SOLUSDT" } | Select-Object -First 1
    if (-not $sol) {
        Write-Host "SOLUSDT NAO aparece em CoinEx-GetPendingPositions -- pode ja ter fechado, ou nome de mercado diferente." -ForegroundColor Yellow
    } else {
        $realSL = if ($sol.PSObject.Properties['stop_loss_price'] -and $sol.stop_loss_price) { [double]$sol.stop_loss_price } else { 0.0 }
        $realTP = if ($sol.PSObject.Properties['take_profit_price'] -and $sol.take_profit_price) { [double]$sol.take_profit_price } else { 0.0 }
        if ($realSL -le 0 -and $realTP -le 0) {
            Write-Host "CONFIRMADO CRITICO: SOLUSDT SEM STOP LOSS E SEM TAKE PROFIT na corretora agora." -ForegroundColor Red
        } elseif ($realSL -le 0) {
            Write-Host "CONFIRMADO CRITICO: SOLUSDT SEM STOP LOSS na corretora agora (TP=$realTP presente)." -ForegroundColor Red
        } elseif ($realTP -le 0) {
            Write-Host "SOLUSDT sem TAKE PROFIT na corretora agora (SL=$realSL presente, menos critico que SL ausente)." -ForegroundColor Yellow
        } else {
            Write-Host "SOLUSDT TEM protecao real na corretora: SL=$realSL TP=$realTP -- reporte pode estar desatualizado ou ja foi corrigido pelo auto-repair." -ForegroundColor Green
        }
    }

    # Journal side-by-side, so pra contexto (nao e fonte de verdade)
    try {
        $journalRow = @(Get-StateRecords -Table "trailing_state" -Filter @{ market = "SOLUSDT"; active = $true })
        if ($journalRow.Count -gt 0) {
            Write-Host "`n(contexto) trailing_state journal para SOLUSDT:" -ForegroundColor DarkGray
            $journalRow | ConvertTo-Json -Depth 4 | Write-Host
        }
    } catch {}

} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
