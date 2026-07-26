# diag_conviction_observations_readonly_2026_07_26.ps1 -- diagnostico ONE-SHOT, so leitura
# Owner perguntou se o Threshold=75 (Resolve-ConvictionOverride) poderia ter
# sido calibrado com dado real em vez de escolha de design. cloud_conviction_scan.ps1
# roda desde 2026-06-18 (>5 semanas) com o objetivo explicito de "acumular ~1
# semana de observacoes p/ validar edge ANTES de virar execucao" -- mas a
# analise de edge nunca foi feita. Este script confirma quanto dado real
# existe na tabela conviction_observations antes de decidir se da pra
# calibrar o threshold com evidencia, ou se ainda faltam outcomes reais
# (conviction sozinha nao mede se o trade teria dado certo -- precisa cruzar
# com preco futuro, que este script NAO faz, so mede volume/distribuicao).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== DIAG CONVICTION_OBSERVATIONS (READ-ONLY) ===" -ForegroundColor Cyan
Write-Host "Backend: $(Test-StateBackend)" -ForegroundColor Cyan

try {
    $all = @(Get-StateRecords -Table "conviction_observations")
    Write-Host "Total de observacoes: $($all.Count)" -ForegroundColor Green

    if ($all.Count -gt 0) {
        $dates = $all | ForEach-Object { try { ([datetime]$_.ts).Date } catch { $null } } | Where-Object { $_ }
        if ($dates) {
            $minDate = ($dates | Measure-Object -Minimum).Minimum
            $maxDate = ($dates | Measure-Object -Maximum).Maximum
            Write-Host "Periodo: $minDate ate $maxDate" -ForegroundColor Cyan
        }

        $byTag = $all | Group-Object tag | Sort-Object Count -Descending
        Write-Host "`nDistribuicao por tag:" -ForegroundColor Cyan
        $byTag | ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" }

        $byDir = $all | Group-Object direction | Sort-Object Count -Descending
        Write-Host "`nDistribuicao por direction:" -ForegroundColor Cyan
        $byDir | ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" }

        $overrideCount = @($all | Where-Object { $_.tag -eq "OVERRIDE" }).Count
        $readyCount = @($all | Where-Object { $_.tag -eq "READY" }).Count
        $belowCount = @($all | Where-Object { $_.tag -eq "below" }).Count
        Write-Host "`nResumo: OVERRIDE(>=75)=$overrideCount READY(55-74)=$readyCount below(<55)=$belowCount" -ForegroundColor Yellow

        $convictions = $all | ForEach-Object { try { [double]$_.conviction } catch { $null } } | Where-Object { $null -ne $_ }
        if ($convictions) {
            $stats = $convictions | Measure-Object -Average -Maximum -Minimum
            Write-Host "`nConviction stats: avg=$([math]::Round($stats.Average,1)) min=$($stats.Minimum) max=$($stats.Maximum)" -ForegroundColor Cyan
        }

        Write-Host "`nNOTA: esta tabela NAO tem outcome real (preco futuro) -- so mede" -ForegroundColor Yellow
        Write-Host "a distribuicao de conviction observada, nao se >=75 teria sido lucrativo." -ForegroundColor Yellow
        Write-Host "Pra calibrar de verdade, precisaria cruzar cada observacao com o preco" -ForegroundColor Yellow
        Write-Host "N dias depois (fwd_return), igual mce_counterfactual_agg faz para outros gates." -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERRO ao consultar conviction_observations: $_" -ForegroundColor Red
}

Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
