# diag_trade_outcomes_analysis_readonly_2026_07_27.ps1 -- diagnostico ONE-SHOT, so leitura
# Owner pediu avaliacao completa: qualidade real das entradas/saidas, se o
# sistema aplicou "smart decisions". Este script puxa TODO o historico de
# trade_outcomes (Supabase) e produz estatisticas agregadas (win rate, PnL
# medio, por source/regime/direction) pra avaliacao real com dado, nao
# suposicao. So leitura.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== DIAG TRADE_OUTCOMES ANALYSIS (READ-ONLY) ===" -ForegroundColor Cyan

try {
    $all = @(Get-StateRecords -Table "trade_outcomes")
    Write-Host "Total historico: $($all.Count)" -ForegroundColor Green

    if ($all.Count -eq 0) { Write-Host "Sem dado."; exit 0 }

    # Ordena por timestamp
    $sorted = $all | Sort-Object { try { [datetime]$_.ts } catch { [datetime]::MinValue } }

    Write-Host "`n--- Todos os registros (ordem cronologica) ---" -ForegroundColor Yellow
    foreach ($t in $sorted) {
        $pnl = if ($t.PSObject.Properties['pnl_percent'] -and $null -ne $t.pnl_percent) { $t.pnl_percent } elseif ($t.PSObject.Properties['pnl_usd']) { $t.pnl_usd } else { "?" }
        # 2026-07-29: id adicionado -- auditoria achou valores app_import repetidos
        # (mesmo pnl varias vezes); precisa ver o id real pra saber se sao
        # registros DISTINTOS (posicoes reais diferentes com pnl parecido por
        # coincidencia) ou o MESMO id sendo lido/exibido mais de uma vez.
        Write-Host ("  id={0} ts={1} market={2} side={3} pnl={4} source={5} close_reason={6}" -f $t.id, $t.ts, $t.market, $t.side, $pnl, $t.source, $t.close_reason)
    }

    Write-Host "`n--- Distribuicao por source ---" -ForegroundColor Yellow
    $all | Group-Object source | Sort-Object Count -Descending | ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" }

    Write-Host "`n--- Distribuicao por side ---" -ForegroundColor Yellow
    $all | Group-Object side | Sort-Object Count -Descending | ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" }

    Write-Host "`n--- Distribuicao por close_reason ---" -ForegroundColor Yellow
    $all | Group-Object close_reason | Sort-Object Count -Descending | ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" }

    $pnls = $all | ForEach-Object {
        if ($_.PSObject.Properties['pnl_percent'] -and $null -ne $_.pnl_percent) { try { [double]$_.pnl_percent } catch { $null } }
        elseif ($_.PSObject.Properties['pnl_usd'] -and $null -ne $_.pnl_usd) { try { [double]$_.pnl_usd } catch { $null } }
        else { $null }
    } | Where-Object { $null -ne $_ }

    if ($pnls -and $pnls.Count -gt 0) {
        $wins = @($pnls | Where-Object { $_ -gt 0 })
        $losses = @($pnls | Where-Object { $_ -le 0 })
        $stats = $pnls | Measure-Object -Average -Sum -Maximum -Minimum
        Write-Host "`n--- PnL Stats (n=$($pnls.Count)) ---" -ForegroundColor Yellow
        Write-Host "  Win rate: $($wins.Count)/$($pnls.Count) ($([math]::Round($wins.Count*100.0/$pnls.Count,1))%)"
        Write-Host "  Soma total: $([math]::Round($stats.Sum,2))"
        Write-Host "  Media: $([math]::Round($stats.Average,2))"
        Write-Host "  Melhor: $([math]::Round($stats.Maximum,2)) | Pior: $([math]::Round($stats.Minimum,2))"
        if ($wins.Count -gt 0) {
            $avgWin = ($wins | Measure-Object -Average).Average
            Write-Host "  Media dos ganhos: $([math]::Round($avgWin,2))"
        }
        if ($losses.Count -gt 0) {
            $avgLoss = ($losses | Measure-Object -Average).Average
            Write-Host "  Media das perdas: $([math]::Round($avgLoss,2))"
        }
    }
} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
