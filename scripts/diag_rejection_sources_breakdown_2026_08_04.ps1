# diag_rejection_sources_breakdown_2026_08_04.ps1 -- ONE-SHOT, so leitura.
#
# diag_why_spot_not_entering mostrou volume altissimo de trade_rejections
# (centenas em minutos) mas ZERO com source contendo "gem", e trailing_state
# praticamente sem registros mode=GEM. Precisa confirmar: candidatos GEM
# simplesmente nao estao sendo AVALIADOS (scanner GEM nao roda / nao gera
# candidato), ou estao sendo avaliados com um source diferente do esperado
# (nome mudou, "source" grava outra coisa)?

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG: breakdown real de trade_rejections.source (ultimas 2h) ===" -ForegroundColor Cyan

try {
    $cfg = Get-SupabaseRequestHeaders -Method "GET"
    $uri = "$($cfg.url)/rest/v1/trade_rejections?select=*&order=ts.desc&limit=1000"
    $rawResponse = Invoke-RestMethod -Uri $uri -Method GET -Headers $cfg.headers -TimeoutSec 30
    Write-Host "DEBUG rawResponse type: $($rawResponse.GetType().FullName)"
    Write-Host "DEBUG rawResponse is array: $($rawResponse -is [array])"
    if ($rawResponse -is [array]) { Write-Host "DEBUG rawResponse.Count: $($rawResponse.Count)" }
    $rows = @($rawResponse)
    Write-Host "Total puxado: $($rows.Count)"
    if ($rows.Count -gt 0) {
        Write-Host "DEBUG rows[0] type: $($rows[0].GetType().FullName)"
        Write-Host "DEBUG rows[0] raw: $($rows[0] | ConvertTo-Json -Compress -Depth 3)"
    }

    $cutoff = (Get-Date).ToUniversalTime().AddHours(-2)
    $recent = @($rows | Where-Object {
        $ts = try { if ($_.ts -is [datetime]) { $_.ts } else { [datetime]::Parse([string]$_.ts) } } catch { $null }
        $ts -and $ts -gt $cutoff
    })
    Write-Host "Ultimas 2h: $($recent.Count)`n"

    Write-Host "--- Por source (todos os valores distintos vistos) ---" -ForegroundColor Yellow
    $recent | Group-Object source | Sort-Object Count -Descending | ForEach-Object {
        Write-Host ("  source='{0}'  count={1}" -f $_.Name, $_.Count)
    }

    Write-Host "`n--- Por direction ---" -ForegroundColor Yellow
    $recent | Group-Object direction | Sort-Object Count -Descending | ForEach-Object {
        Write-Host ("  direction='{0}'  count={1}" -f $_.Name, $_.Count)
    }

    Write-Host "`n--- Por regime ---" -ForegroundColor Yellow
    $recent | Group-Object regime | Sort-Object Count -Descending | ForEach-Object {
        Write-Host ("  regime='{0}'  count={1}" -f $_.Name, $_.Count)
    }

    Write-Host "`n--- Amostra de 10 registros crus (todos os campos) ---" -ForegroundColor Yellow
    $recent | Select-Object -First 10 | ForEach-Object {
        Write-Host ("  ts={0} market={1} dir={2} source={3} regime={4}" -f $_.ts, $_.market, $_.direction, $_.source, $_.regime)
        Write-Host ("    gate={0}" -f $_.gate)
    }

    Write-Host "`n--- Markets distintos vistos (ultimas 2h) ---" -ForegroundColor Yellow
    $distinctMarkets = @($recent | Select-Object -ExpandProperty market -Unique)
    Write-Host "Total markets distintos: $($distinctMarkets.Count)"
    Write-Host ($distinctMarkets -join ", ")

} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
