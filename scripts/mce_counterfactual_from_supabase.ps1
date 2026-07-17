# mce_counterfactual_from_supabase.ps1 -- 2026-07-16
# Le trade_rejections (Supabase, persiste entre jobs efemeros -- diferente
# do journal/mce_counterfactual.jsonl local que scripts/mce_counterfactual_
# report.ps1 le, escrito so por orchestrator_v6.ps1, que nao roda em
# nenhum job do pipeline atual). Mede forward-return 24h/72h dos setups
# que o gem_executor bloqueou (Write-SignalSkip grava em trade_rejections
# desde 2026-07-16), agrupa por regime|direction, grava em
# manuheadfund.mce_counterfactual_agg. Responde: os sinais pulados
# teriam dado edge positivo se tivessemos entrado?
#
# Pre-requisito: tabela public.trade_rejections precisa existir no Supabase
# (docs/SETUP_SUPABASE_SIGNAL_SKIPS.sql) -- nao criavel via codigo, rpc/exec_sql
# nao exposta nesse projeto (confirmado 2026-07-16).

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root "agents\config.ps1")
. (Join-Path $root "agents\lib_coinex.ps1")
. (Join-Path $root "agents\lib_state_store.ps1")

Write-Host "=== MCE COUNTERFACTUAL (via Supabase trade_rejections) ===" -ForegroundColor Cyan

$entries = @()
try {
    $entries = @(Get-StateRecords -Table "trade_rejections" -ErrorAction Stop)
} catch {
    Write-Host "ERRO ao ler trade_rejections: $($_.Exception.Message)" -ForegroundColor Red
    exit 0
}

if ($entries.Count -eq 0) {
    Write-Host "0 entries em trade_rejections -- nada a medir ainda." -ForegroundColor Yellow
    exit 0
}

Write-Host "Lidas $($entries.Count) rejeicoes do Supabase." -ForegroundColor White

$nowUtc = (Get-Date).ToUniversalTime()
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
    if ($null -eq $best -or $bestDelta -gt 7200000) { return $null }
    $raw = ($best.close - $base) / $base * 100
    $signed = if ($Entry.direction -eq "SHORT") { -$raw } else { $raw }
    return [Math]::Round($signed, 2)
}

# 2026-07-17: gate_base normaliza o valor cru de $e.gate (ex: "tori_confluence_
# 65_lt_80" -> "tori_confluence", "breadth_long_blocked" -> "breadth_long_blocked"
# ja e estavel). Sufixos numericos variam por chamada (score real embutido no
# texto) -- sem normalizar, cada rejeicao vira seu proprio grupo de n=1,
# impossivel agregar. So corta o padrao "_<numero>_lt_<numero>" quando presente.
function _Get-GateBase {
    param([string]$Gate)
    if (-not $Gate) { return "unknown" }
    return ($Gate -replace '_\d+(\.\d+)?_lt_\d+(\.\d+)?$', '')
}

$measured = @()
foreach ($e in $entries) {
    $r24 = Get-FwdReturn -Entry $e -Hours 24
    $r72 = Get-FwdReturn -Entry $e -Hours 72
    if ($null -ne $r24) {
        $measured += [PSCustomObject]@{
            market = $e.market; direction = $e.direction; regime = $e.regime
            gate = _Get-GateBase ([string]$e.gate)
            fwd_return_24h = $r24; fwd_return_72h = $r72
        }
    }
}

Write-Host "Medidas: $($measured.Count) / $($entries.Count) (resto ainda nao maturou 24h ou sem candle disponivel)" -ForegroundColor White
Write-Host ""

if ($measured.Count -eq 0) {
    Write-Host "Nenhuma entry madura ainda -- nada a agregar." -ForegroundColor Yellow
    exit 0
}

# 2026-07-17: agrupamento ganhou "gate" (antes so regime|direction) -- misturava
# TODOS os gates que bloquearam (breadth, pump, tori_confluence) no mesmo grupo,
# impossivel usar como evidencia pra calibrar UM gate especifico (ex: motor de
# evolucao ajustando so o tori_confluence_threshold). "group" (chave primaria do
# upsert) ganha o 3o segmento -- registros antigos com "regime|direction" ficam
# orfaos na tabela (nao removidos, so param de nao serem mais atualizados por
# este script; aceitavel, tabela e cache derivado, nao fonte de verdade).
$groups = $measured | Group-Object { "$($_.regime)|$($_.direction)|$($_.gate)" }

Write-Host "RESUMO -- forward return dos setups bloqueados (sign-adjusted p/ SHORT)" -ForegroundColor Cyan
Write-Host ("{0,-40} {1,5} {2,10} {3,10} {4,8}" -f "regime|direcao|gate","n","avg24h%","avg72h%","hit_rate") -ForegroundColor Gray

$aggRows = @()
foreach ($g in ($groups | Sort-Object Name)) {
    $r24 = @($g.Group | ForEach-Object { [double]$_.fwd_return_24h })
    $r72 = @($g.Group | Where-Object { $null -ne $_.fwd_return_72h } | ForEach-Object { [double]$_.fwd_return_72h })
    $avg24 = [Math]::Round(($r24 | Measure-Object -Average).Average, 2)
    $avg72 = if ($r72.Count -gt 0) { [Math]::Round(($r72 | Measure-Object -Average).Average, 2) } else { 0 }
    $hitRate = [Math]::Round((@($r24 | Where-Object { $_ -gt 0 }).Count / $r24.Count), 4)
    Write-Host ("{0,-40} {1,5} {2,10} {3,10} {4,7}%" -f $g.Name, $r24.Count, $avg24, $avg72, [Math]::Round($hitRate * 100, 0))

    $parts = "$($g.Name)".Split("|")
    $aggRows += [PSCustomObject]@{
        group       = $g.Name
        regime      = if ($parts.Count -gt 0) { $parts[0] } else { "" }
        direction   = if ($parts.Count -gt 1) { $parts[1] } else { "" }
        gate        = if ($parts.Count -gt 2) { $parts[2] } else { "" }
        n           = $r24.Count
        hit_rate    = $hitRate
        avg_fwd_24h = $avg24
        avg_fwd_72h = $avg72
        updated_at  = $nowUtc.ToString("o")
    }
}

Write-Host ""
try {
    Save-StateRecords -Table "mce_counterfactual_agg" -Records $aggRows -PrimaryKey "group"
    Write-Host "Gravado em manuheadfund.mce_counterfactual_agg ($($aggRows.Count) grupos)." -ForegroundColor Green
} catch {
    Write-Host "ERRO ao gravar mce_counterfactual_agg: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== FIM ===" -ForegroundColor Cyan
