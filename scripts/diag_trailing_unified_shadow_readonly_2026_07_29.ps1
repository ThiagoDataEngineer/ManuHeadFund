# diag_trailing_unified_shadow_readonly_2026_07_29.ps1 -- diagnostico
# ONE-SHOT, so leitura. Antes de promover o motor unificado de trailing
# (lib_trailing_unified.ps1, Resolve-TrailingDecision) de SHADOW (so log)
# pra ATIVO (escreve stop real), preciso ver o historico real acumulado
# desde 2026-07-19 (trailing_unified_shadow) -- quantas vezes o motor
# unificado teria sugerido algo DIFERENTE do que os motores fragmentados
# reais fizeram, e se essas sugestoes eram mais conservadoras (aperta
# antes) ou mais soltas (aperta depois).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG trailing_unified_shadow (historico real desde 2026-07-19) ===" -ForegroundColor Cyan
try {
    $rows = @(Get-StateRecords -Table "trailing_unified_shadow")
    Write-Host "Total de observacoes: $($rows.Count)`n"

    if ($rows.Count -eq 0) { Write-Host "Nenhum dado ainda." -ForegroundColor DarkYellow; exit 0 }

    $byAction = $rows | Group-Object unified_action
    Write-Host "--- Distribuicao por acao sugerida ---" -ForegroundColor Yellow
    foreach ($g in $byAction) { Write-Host "  $($g.Name): $($g.Count)" }

    Write-Host "`n--- Amostra (ultimas 20, mais recentes) ---" -ForegroundColor Yellow
    $sorted = $rows | Sort-Object { try { [datetime]$_.ts } catch { [datetime]::MinValue } } -Descending | Select-Object -First 20
    foreach ($r in $sorted) {
        Write-Host ("ts={0} market={1} side={2} real_stop={3} unified_action={4} unified_new_stop={5} reason={6}" -f `
            $r.ts, $r.market, $r.side, $r.real_stop, $r.unified_action, $r.unified_new_stop, $r.reason)
    }

    $differed = @($rows | Where-Object { $_.would_have_differed -eq $true })
    Write-Host "`n--- Casos onde o motor unificado teria feito DIFERENTE do real (would_have_differed=true): $($differed.Count) / $($rows.Count) ---" -ForegroundColor Yellow
    foreach ($u in ($differed | Select-Object -First 20)) {
        $realStop = [double]$u.real_stop
        $unifiedStop = [double]$u.unified_new_stop
        $diffPct = if ($realStop -gt 0) { [math]::Round((($unifiedStop - $realStop) / $realStop) * 100, 3) } else { 0 }
        Write-Host "  $($u.market) [$($u.side)]: real=$realStop unified=$unifiedStop diff=$diffPct% reason=$($u.reason) ts=$($u.ts)"
    }
} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM ===" -ForegroundColor Cyan
