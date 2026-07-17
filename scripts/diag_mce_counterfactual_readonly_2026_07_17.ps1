# diag_mce_counterfactual_readonly_2026_07_17.ps1 -- diagnostico ONE-SHOT, so leitura
# Confirma a hipotese: mce_counterfactual_from_supabase.ps1 le trade_rejections
# sem order=/limit explicito -- com a tabela crescendo ~1000-1600 linhas/dia
# (41 rejeicoes/ciclo, ciclos ~30-50min) e o default de 1000 linhas do
# PostgREST, o script pode nunca ver as entradas MAIS ANTIGAS (as unicas que
# ja teriam 24h pra medir forward-return). Se confirmado, 0/1000 maturadas
# nao e "ainda nao deu tempo" -- e um bug estrutural desde a criacao
# (2026-07-16). NAO envia nenhuma ordem, so leitura.

$agentsDir = Join-Path $PSScriptRoot ".." "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== DIAG MCE COUNTERFACTUAL (READ-ONLY) ===" -ForegroundColor Cyan
Write-Host ""

# [1] Leitura IDENTICA ao script real (sem order/limit) -- ve o que ele ve
Write-Host "[1] Get-StateRecords (mesma chamada do script real, sem order/limit)" -ForegroundColor Yellow
$entries = @()
try {
    $entries = @(Get-StateRecords -Table "trade_rejections" -ErrorAction Stop)
    Write-Host "  Retornadas: $($entries.Count) linhas" -ForegroundColor White
    if ($entries.Count -gt 0) {
        $timestamps = @($entries | ForEach-Object { try { [datetime]::Parse($_.ts) } catch { $null } } | Where-Object { $_ })
        if ($timestamps.Count -gt 0) {
            $oldest = ($timestamps | Sort-Object)[0]
            $newest = ($timestamps | Sort-Object -Descending)[0]
            Write-Host "  ts mais antigo retornado: $oldest" -ForegroundColor White
            Write-Host "  ts mais novo retornado:   $newest" -ForegroundColor White
            $ageOldestHours = ((Get-Date).ToUniversalTime() - $oldest.ToUniversalTime()).TotalHours
            Write-Host "  idade do mais antigo retornado: $([Math]::Round($ageOldestHours,1))h" -ForegroundColor $(if ($ageOldestHours -ge 24) { "Green" } else { "Red" })
        }
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# [2] Query DIRETA via REST com order=ts.asc explicito -- confirma se existem
# linhas com 24h+ de idade na tabela (independente do que a leitura padrao ve)
Write-Host "[2] Query direta ORDER BY ts ASC (pra achar as entradas REALMENTE mais antigas)" -ForegroundColor Yellow
try {
    $cfg = Get-SupabaseRequestHeaders -Method "GET"
    $uri = "$($cfg.url)/rest/v1/trade_rejections?select=ts,market,gate&order=ts.asc&limit=10"
    $oldest10 = Invoke-RestMethod -Uri $uri -Method GET -Headers $cfg.headers -TimeoutSec 30
    Write-Host "  10 entradas mais antigas da tabela (ORDER BY ts ASC de verdade):" -ForegroundColor White
    foreach ($e in $oldest10) {
        $age = ((Get-Date).ToUniversalTime() - [datetime]::Parse($e.ts).ToUniversalTime()).TotalHours
        Write-Host "    ts=$($e.ts) market=$($e.market) gate=$($e.gate) idade=$([Math]::Round($age,1))h" -ForegroundColor $(if ($age -ge 24) { "Green" } else { "Yellow" })
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# [2b] Das 1000 linhas retornadas por [1], quantas NAO sao INIT e tem 24h+?
# Isola se o problema e (a) INIT poluindo o topo mas resto tudo recente
# (tabela so comecou a crescer de verdade ha pouco), ou (b) existem MUITAS
# rejeicoes reais com 24h+ que deveriam ter maturado e nao aparecem no
# "Medidas: X/1000" do script real -- aponta pra falha na busca de candle
# (Get-FwdReturn) em vez de problema de leitura/paginacao.
Write-Host "[2b] Das 1000 linhas de [1]: distribuicao real market != INIT" -ForegroundColor Yellow
$nonInit = @($entries | Where-Object { $_.market -ne "INIT" })
Write-Host "  Total nao-INIT: $($nonInit.Count) / $($entries.Count)" -ForegroundColor White
if ($nonInit.Count -gt 0) {
    $agesNonInit = @($nonInit | ForEach-Object {
        try { ((Get-Date).ToUniversalTime() - [datetime]::Parse($_.ts).ToUniversalTime()).TotalHours } catch { $null }
    } | Where-Object { $null -ne $_ })
    $over24h = @($agesNonInit | Where-Object { $_ -ge 24 })
    Write-Host "  Nao-INIT com idade >= 24h: $($over24h.Count) / $($nonInit.Count)" -ForegroundColor $(if ($over24h.Count -gt 0) { "Red" } else { "Green" })
    if ($over24h.Count -gt 0) {
        Write-Host "  Exemplo (3 primeiras nao-INIT >=24h):" -ForegroundColor White
        $sample = @($nonInit | Where-Object {
            try { ((Get-Date).ToUniversalTime() - [datetime]::Parse($_.ts).ToUniversalTime()).TotalHours -ge 24 } catch { $false }
        } | Select-Object -First 3)
        foreach ($s in $sample) {
            Write-Host "    ts=$($s.ts) market=$($s.market) gate=$($s.gate) entry_price=$($s.entry_price)" -ForegroundColor Gray
        }
    }
    $oldestNonInit = ($agesNonInit | Measure-Object -Maximum).Maximum
    $newestNonInit = ($agesNonInit | Measure-Object -Minimum).Minimum
    Write-Host "  Idade nao-INIT: min=$([Math]::Round($newestNonInit,1))h max=$([Math]::Round($oldestNonInit,1))h" -ForegroundColor White
}
Write-Host ""

# [3] Contagem total real via Prefer: count=exact (header), sem trazer linhas
Write-Host "[3] Contagem TOTAL real da tabela (Prefer: count=exact)" -ForegroundColor Yellow
try {
    $cfg2 = Get-SupabaseRequestHeaders -Method "GET"
    $headers2 = @{} + $cfg2.headers
    $headers2["Prefer"] = "count=exact"
    $uri2 = "$($cfg2.url)/rest/v1/trade_rejections?select=id&limit=1"
    $resp = Invoke-WebRequest -Uri $uri2 -Method GET -Headers $headers2 -TimeoutSec 30
    $contentRange = $resp.Headers["Content-Range"]
    Write-Host "  Content-Range header: $contentRange (formato: inicio-fim/total)" -ForegroundColor White
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== FIM ===" -ForegroundColor Cyan
Write-Host "Se [1] mostrar idade do mais antigo RETORNADO < 24h, MAS [2] mostrar" -ForegroundColor Gray
Write-Host "entradas com 24h+ existindo na tabela -- hipotese CONFIRMADA: a leitura" -ForegroundColor Gray
Write-Host "sem order/limit nunca alcanca as entradas maturaveis." -ForegroundColor Gray
