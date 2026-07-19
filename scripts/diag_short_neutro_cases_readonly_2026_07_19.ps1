# diag_short_neutro_cases_readonly_2026_07_19.ps1 -- diagnostico ONE-SHOT, so leitura
#
# Continuacao do diag_real_edge_readonly_2026_07_19.ps1: mce_counterfactual_agg
# mostrou um padrao (NEUTRO|SHORT|breadth_short_blocked n=18 hit_rate=94.4%,
# NEUTRO|SHORT n=24 hit_rate=87.5%) que sugere o gate de breadth/pump esta
# bloqueando SHORTs com edge aparente em regime NEUTRO. Isso e' AGREGADO --
# este script puxa os CASOS INDIVIDUAIS de manuheadfund.trade_rejections
# (tabela fonte, ver lib_direction_learning.ps1 Write-SignalSkip) pra ver
# QUAIS mercados/condicoes especificas geram esse padrao, antes de considerar
# qualquer mudanca de gate em producao.
#
# NAO decide nada, NAO altera nenhum gate. So read-only.

$agentsDir = Join-Path $PSScriptRoot ".." "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== DIAG SHORT-EM-NEUTRO: casos individuais (READ-ONLY) ===" -ForegroundColor Cyan
Write-Host ""

try {
    $rej = @(Get-StateRecords -Table "trade_rejections" -ErrorAction Stop)
    Write-Host "Total trade_rejections: $($rej.Count)" -ForegroundColor White

    # Filtra os grupos de interesse (regime NEUTRO, direction SHORT, gate contem breadth/pump)
    $target = @($rej | Where-Object {
        $_.regime -eq "NEUTRO" -and $_.direction -eq "SHORT" -and
        ($_.gate -match "breadth_short_blocked|pump_short_blocked")
    })
    Write-Host "Casos NEUTRO|SHORT com gate breadth/pump: $($target.Count)" -ForegroundColor White
    Write-Host ""

    if ($target.Count -eq 0) {
        Write-Host "(nenhum caso encontrado -- confirmar nome exato dos campos regime/direction/gate na tabela)" -ForegroundColor DarkYellow
    } else {
        Write-Host "--- Distribuicao por mercado ---" -ForegroundColor Yellow
        $byMarket = $target | Group-Object -Property market | Sort-Object Count -Descending
        foreach ($g in $byMarket | Select-Object -First 20) {
            Write-Host "  $($g.Name): $($g.Count) casos"
        }

        Write-Host ""
        Write-Host "--- Distribuicao por gate exato (com sufixos, pre-normalizacao) ---" -ForegroundColor Yellow
        $byGate = $target | Group-Object -Property gate | Sort-Object Count -Descending
        foreach ($g in $byGate) {
            Write-Host "  $($g.Name): $($g.Count) casos"
        }

        Write-Host ""
        Write-Host "--- Amostra dos 15 casos mais recentes (market, ts, gate, entry_price) ---" -ForegroundColor Yellow
        $target | Sort-Object -Property ts -Descending | Select-Object -First 15 | ForEach-Object {
            Write-Host "  $($_.ts) | $($_.market) | gate=$($_.gate) | entry=$($_.entry_price)"
        }

        Write-Host ""
        Write-Host "--- Concentracao: top 5 mercados = quanto % do total? ---" -ForegroundColor Yellow
        $top5Count = ($byMarket | Select-Object -First 5 | Measure-Object -Property Count -Sum).Sum
        $concPct = if ($target.Count -gt 0) { [Math]::Round(($top5Count / $target.Count) * 100, 1) } else { 0 }
        Write-Host "  Top 5 mercados concentram $concPct% dos $($target.Count) casos"
        if ($concPct -gt 60) {
            Write-Host "  [ATENCAO: alta concentracao -- padrao pode ser especifico de poucos mercados, nao generalizavel]" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== FIM DIAG -- use isso pra desenhar um teste controlado, NAO pra mudar gate direto ===" -ForegroundColor Cyan
