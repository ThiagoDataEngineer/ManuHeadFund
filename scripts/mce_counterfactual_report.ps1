# mce_counterfactual_report.ps1 -- Evolucao D 2026-07-06.
# Mede forward return 24h/72h dos setups que o MCE degradou (BLOCK/PAPER_ONLY).
# Fonte: journal/mce_counterfactual.jsonl (escrito por orchestrator_v6 na decisao).
# Output: preenche fwd_return_24h/72h in-place + resumo por regime+direcao no console
# e em journal/mce_counterfactual_summary.json.
#
# Retorno e sign-adjusted: SHORT com preco caindo = retorno positivo (o trade teria
# lucrado). Se a media dos bloqueados for positiva, thresholds 0.20/0.50 estao caros.
#
# Uso: pwsh/powershell -File scripts\mce_counterfactual_report.ps1
# Agendado via loop do scan_master ou manual. PS 5.1. UTF-8 BOM.

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root "agents\config.ps1")
. (Join-Path $root "agents\lib_coinex.ps1")
# _Mirror-LearningToSupabase (espelho manuheadfund) vive em lib_direction_learning.
. (Join-Path $root "agents\lib_direction_learning.ps1")

$cfPath = Join-Path $root "journal\mce_counterfactual.jsonl"
if (-not (Test-Path $cfPath)) {
    Write-Host "Sem journal/mce_counterfactual.jsonl ainda -- nada a medir." -ForegroundColor Yellow
    return
}

$nowUtc = (Get-Date).ToUniversalTime()
$lines = Get-Content $cfPath -Encoding UTF8 | Where-Object { $_ -and $_.Trim() }
$entries = @()
foreach ($ln in $lines) {
    try { $entries += ($ln | ConvertFrom-Json) } catch { }
}
if ($entries.Count -eq 0) { Write-Host "0 entries validas."; return }

# Cache de candles por market (1 fetch por market cobre todas as entries dele)
$candleCache = @{}
function Get-FwdReturn {
    param($Entry, [int] $Hours)
    $ts = [datetime]::Parse($Entry.ts).ToUniversalTime()
    if (($nowUtc - $ts).TotalHours -lt $Hours) { return $null }   # ainda nao maturou
    $base = [double]$Entry.entry_price
    if ($base -le 0) { return $null }                              # sem preco de referencia
    $mkt = [string]$Entry.market
    if (-not $candleCache.ContainsKey($mkt)) {
        try { $candleCache[$mkt] = @(CoinEx-GetCandles $mkt "1hour" 100) } catch { $candleCache[$mkt] = @() }
    }
    $candles = $candleCache[$mkt]
    if ($candles.Count -eq 0) { return $null }
    $targetTs = [long](([datetimeoffset]$ts.AddHours($Hours)).ToUnixTimeMilliseconds())
    $best = $null; $bestDelta = [long]::MaxValue
    foreach ($c in $candles) {
        $d = [Math]::Abs($c.ts - $targetTs)
        if ($d -lt $bestDelta) { $bestDelta = $d; $best = $c }
    }
    # Candle mais proximo precisa estar a <2h do alvo (senao dado velho demais p/ janela)
    if ($null -eq $best -or $bestDelta -gt 7200000) { return $null }
    $raw = ($best.close - $base) / $base * 100
    $signed = if ($Entry.direction -eq "SHORT") { -$raw } else { $raw }
    return [Math]::Round($signed, 2)
}

$updated = 0
foreach ($e in $entries) {
    if ($null -eq $e.fwd_return_24h) {
        $r = Get-FwdReturn -Entry $e -Hours 24
        if ($null -ne $r) { $e.fwd_return_24h = $r; $updated++ }
    }
    if ($null -eq $e.fwd_return_72h) {
        $r = Get-FwdReturn -Entry $e -Hours 72
        if ($null -ne $r) { $e.fwd_return_72h = $r; $updated++ }
    }
}

if ($updated -gt 0) {
    ($entries | ForEach-Object { $_ | ConvertTo-Json -Compress }) | Set-Content $cfPath -Encoding UTF8
}

# ── Resumo por regime + direcao ──────────────────────────────────────────────
$groups = $entries | Where-Object { $null -ne $_.fwd_return_24h } |
    Group-Object { "$($_.regime)|$($_.direction)" }

$summary = @()
Write-Host ""
Write-Host "MCE COUNTERFACTUAL -- forward return dos setups degradados (sign-adjusted)" -ForegroundColor Cyan
Write-Host ("{0,-28} {1,5} {2,10} {3,10} {4,8}" -f "regime|direcao","n","avg24h%","avg72h%","win24h") -ForegroundColor Gray
foreach ($g in ($groups | Sort-Object Name)) {
    $r24 = @($g.Group | ForEach-Object { [double]$_.fwd_return_24h })
    $r72 = @($g.Group | Where-Object { $null -ne $_.fwd_return_72h } | ForEach-Object { [double]$_.fwd_return_72h })
    $avg24 = [Math]::Round(($r24 | Measure-Object -Average).Average, 2)
    $avg72 = if ($r72.Count -gt 0) { [Math]::Round(($r72 | Measure-Object -Average).Average, 2) } else { $null }
    $win24 = [Math]::Round((@($r24 | Where-Object { $_ -gt 0 }).Count / $r24.Count) * 100, 0)
    Write-Host ("{0,-28} {1,5} {2,10} {3,10} {4,7}%" -f $g.Name, $r24.Count, $avg24, $avg72, $win24)
    $summary += [PSCustomObject]@{
        group = $g.Name; n = $r24.Count
        avg_fwd_24h = $avg24; avg_fwd_72h = $avg72; win_rate_24h = $win24
    }
}

$pendCount = @($entries | Where-Object { $null -eq $_.fwd_return_24h }).Count
Write-Host ""
Write-Host "Total: $($entries.Count) entries | $updated atualizadas agora | $pendCount aguardando maturacao" -ForegroundColor Gray

$outPath = Join-Path $root "journal\mce_counterfactual_summary.json"
[PSCustomObject]@{
    generated_at = $nowUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
    total_entries = $entries.Count
    pending = $pendCount
    groups = $summary
} | ConvertTo-Json -Depth 4 | Set-Content $outPath -Encoding UTF8
Write-Host "Resumo salvo em journal\mce_counterfactual_summary.json" -ForegroundColor Green

# Espelho Supabase (manuheadfund.mce_counterfactual_agg) — AGREGADO por regime|direction.
# PK = group ("regime|direction"). Best-effort; nao quebra o report se falhar.
if ((Get-Command _Mirror-LearningToSupabase -ErrorAction SilentlyContinue) -and $summary.Count -gt 0) {
    $mceRows = @($summary | ForEach-Object {
        $parts = "$($_.group)".Split("|")
        @{
            group        = [string]$_.group
            regime       = [string]$parts[0]
            direction    = if ($parts.Count -gt 1) { [string]$parts[1] } else { "" }
            n            = [int]$_.n
            hit_rate     = [double]$_.win_rate_24h
            avg_fwd_24h  = [double]$_.avg_fwd_24h
            avg_fwd_72h  = if ($null -ne $_.avg_fwd_72h) { [double]$_.avg_fwd_72h } else { $null }
            updated_at   = $nowUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
    })
    _Mirror-LearningToSupabase -Table "mce_counterfactual_agg" -PrimaryKey "group" -Records $mceRows
}
