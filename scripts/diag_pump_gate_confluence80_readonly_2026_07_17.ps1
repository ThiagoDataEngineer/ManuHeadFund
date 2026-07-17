# diag_pump_gate_confluence80_readonly_2026_07_17.ps1 -- diagnostico ONE-SHOT, so leitura
# Pergunta: candidatos TORI_SHORT com confluence 80-89 (abaixo do piso 90 do
# [PUMP GATE OVERRIDE], commit 16bbfb2) que travam em pump_short_blocked
# (pump_class=natural_uptrend) -- teriam dado edge positivo se o bypass
# aceitasse confluence>=80 em vez de >=90? Consulta gate_replay_study
# (blocked_by pump_*, direction=SHORT), extrai tori_score de gates_snapshot,
# separa por faixa de confluence e mede o retorno realizado em "returns".
# NAO envia nenhuma ordem, so leitura.

$agentsDir = Join-Path $PSScriptRoot ".." "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== DIAG PUMP GATE CONFLUENCE 80 vs 90 (READ-ONLY) ===" -ForegroundColor Cyan
Write-Host ""

try {
    $rows = @(Get-StateRecords -Table "gate_replay_study" -ErrorAction Stop)
} catch {
    Write-Host "ERRO ao ler gate_replay_study: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Total de linhas em gate_replay_study: $($rows.Count)" -ForegroundColor Gray
Write-Host ""

# Filtra: SHORT, bloqueado por pump gate (pump_short_blocked), com gates_snapshot
$candidates = @()
foreach ($r in $rows) {
    if ($r.direction -ne "SHORT") { continue }
    if (-not $r.blocked_by -or $r.blocked_by -notmatch "pump_short_blocked") { continue }
    if (-not $r.gates_snapshot) { continue }

    $snap = try { $r.gates_snapshot | ConvertTo-Json -Depth 10 | ConvertFrom-Json } catch { $null }
    if (-not $snap) { continue }

    # tori_score pode estar em snap.tori.score, snap.score, ou snap.tori_score
    # dependendo de como Invoke-GemExecute -DryRun serializou o snapshot.
    $toriScore = $null
    foreach ($path in @("tori_score","score")) {
        if ($snap.PSObject.Properties[$path] -and $null -ne $snap.$path) { $toriScore = [double]$snap.$path; break }
    }
    if ($null -eq $toriScore -and $snap.PSObject.Properties['tori'] -and $snap.tori.PSObject.Properties['score']) {
        $toriScore = [double]$snap.tori.score
    }
    if ($null -eq $toriScore) { continue }

    $returns = try { $r.returns | ConvertTo-Json | ConvertFrom-Json } catch { $null }

    $candidates += [PSCustomObject]@{
        market = $r.market
        tori_score = $toriScore
        pump_class = if ($snap.PSObject.Properties['pump_class']) { $snap.pump_class } else { "?" }
        regime = $r.regime
        ts = $r.ts
        r10m = if ($returns -and $returns.PSObject.Properties['10m']) { $returns.'10m' } else { $null }
        r30m = if ($returns -and $returns.PSObject.Properties['30m']) { $returns.'30m' } else { $null }
        r1h  = if ($returns -and $returns.PSObject.Properties['1h'])  { $returns.'1h'  } else { $null }
        r4h  = if ($returns -and $returns.PSObject.Properties['4h'])  { $returns.'4h'  } else { $null }
    }
}

Write-Host "Candidatos SHORT bloqueados por pump_short_blocked com tori_score conhecido: $($candidates.Count)" -ForegroundColor Yellow
Write-Host ""

function Show-Bucket {
    param([string]$Label, [object[]]$Bucket)
    Write-Host "--- $Label (n=$($Bucket.Count)) ---" -ForegroundColor Cyan
    if ($Bucket.Count -eq 0) { Write-Host "  (vazio)" -ForegroundColor DarkYellow; return }
    foreach ($h in @("r10m","r30m","r1h","r4h")) {
        $vals = @($Bucket | Where-Object { $null -ne $_.$h } | ForEach-Object { [double]$_.$h })
        if ($vals.Count -eq 0) { Write-Host "  ${h}: sem dados maturados ainda" -ForegroundColor DarkGray; continue }
        # SHORT lucra quando o preco CAI -> retorno negativo = trade teria dado certo
        $avg = ($vals | Measure-Object -Average).Average
        $winRate = ([double](@($vals | Where-Object { $_ -lt 0 }).Count) / $vals.Count) * 100
        Write-Host ("  {0}: n={1} avg_return={2}% (negativo=SHORT ganharia) win_rate_short={3}%" -f $h, $vals.Count, [Math]::Round($avg,3), [Math]::Round($winRate,1)) -ForegroundColor White
    }
    Write-Host "  Mercados: $(($Bucket | Select-Object -ExpandProperty market -Unique) -join ', ')" -ForegroundColor Gray
    Write-Host ""
}

$b80_89 = @($candidates | Where-Object { $_.tori_score -ge 80 -and $_.tori_score -lt 90 })
$b90plus = @($candidates | Where-Object { $_.tori_score -ge 90 })
$bBelow80 = @($candidates | Where-Object { $_.tori_score -lt 80 })

Show-Bucket "Confluence 80-89 (faixa que o override NAO cobre hoje)" $b80_89
Show-Bucket "Confluence >=90 (faixa que o override JA cobre)" $b90plus
Show-Bucket "Confluence <80 (abaixo do piso do sweep TORI_SHORT)" $bBelow80

Write-Host "=== FIM ===" -ForegroundColor Cyan
