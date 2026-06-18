# cloud_conviction_scan.ps1 -- Fase 3 (OBSERVE): signal + conviction na nuvem.
# Roda no GitHub Actions. Varre top movers, computa o ensemble de 7 eixos (LONG+SHORT)
# e LOGA observacoes no state_store (cloud-persistente). NUNCA executa trade.
# Objetivo: acumular ~1 semana de observacoes p/ validar edge ANTES de virar execucao.
# Cross-platform (ubuntu pwsh). 2026-06-18. ASCII-only.

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root "agents/config.ps1")
$cl = Join-Path $root "agents/config.local.ps1"; if (Test-Path $cl) { . $cl }
. (Join-Path $root "agents/lib_coinex.ps1")
. (Join-Path $root "agents/lib_candle_fetcher.ps1")
. (Join-Path $root "agents/lib_multiframe_analysis.ps1")
. (Join-Path $root "agents/lib_btc_relative_strength.ps1")
. (Join-Path $root "agents/lib_entry_conviction_ensemble.ps1")
. (Join-Path $root "agents/lib_state_store.ps1")

Write-Host "=== CLOUD CONVICTION SCAN (OBSERVE -- zero execucao) ===" -ForegroundColor Cyan

$TOP_N    = 6           # gainers + losers avaliados (limita custo de API/Actions)
$MIN_VOL  = 1000000     # liquidez minima 24h USD
$READY    = 55
$OVERRIDE = 75

# ── Top movers (mesma fonte do backtest) ───────────────────────────────────────
$rows = @()
try {
    $r = Invoke-RestMethod -Uri "$($global:COINEX_BASE_URL)/v2/futures/ticker" -Method GET -TimeoutSec 20
    foreach ($t in $r.data) {
        $open = [double]$t.open; $last = [double]$t.last; $val = [double]$t.value
        if ($open -le 0 -or $val -lt $MIN_VOL) { continue }
        $rows += [PSCustomObject]@{ market = $t.market; chg = [math]::Round(($last - $open) / $open * 100, 1) }
    }
} catch { Write-Host "ticker falhou: $_" -ForegroundColor Yellow; return }

$gainers = @($rows | Sort-Object chg -Descending | Select-Object -First $TOP_N)
$losers  = @($rows | Sort-Object chg | Select-Object -First $TOP_N)

$observations = @()
$ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

function Eval-Conviction($list, $dir) {
    foreach ($g in $list) {
        try {
            $conv = Get-MarketConviction -Market $g.market -Direction $dir -IsFutures $true
            if (-not $conv) { continue }
            $tag = if ($conv.conviction -ge $OVERRIDE) { "OVERRIDE" } elseif ($conv.conviction -ge $READY) { "READY" } else { "below" }
            Write-Host ("  {0,-12} {1,-5} {2,5}/100 [{3}] chg24h={4}%" -f $g.market, $dir, $conv.conviction, $tag, $g.chg)
            $script:observations += [PSCustomObject]@{
                ts            = $ts
                market        = $g.market
                direction     = $dir
                conviction    = $conv.conviction
                ready         = [bool]$conv.ready
                tag           = $tag
                chg_24h       = $g.chg
                axes          = ($conv.axes_detail | ConvertTo-Json -Compress)
                mode          = "OBSERVE"
                pk_id         = "$($g.market)_$($dir)_$ts"
            }
        } catch { Write-Host "  $($g.market) $dir erro: $_" -ForegroundColor DarkGray }
    }
}

Write-Host "-- LONG (gainers) --" -ForegroundColor Green
Eval-Conviction $gainers "LONG"
Write-Host "-- SHORT (losers) --" -ForegroundColor Red
Eval-Conviction $losers "SHORT"

# ── Persistir observacoes (state_store: supabase na nuvem) ──────────────────────
if ($observations.Count -gt 0) {
    try {
        if (Get-Command Save-StateRecords -ErrorAction SilentlyContinue) {
            Save-StateRecords -Table "conviction_observations" -Records @($observations) -PrimaryKey "pk_id"
            Write-Host "OBSERVE: $($observations.Count) observacoes salvas (state_store)" -ForegroundColor Cyan
        } else {
            $out = Join-Path $root "journal/conviction_observations.jsonl"
            $observations | ForEach-Object { $_ | ConvertTo-Json -Compress | Add-Content $out -Encoding UTF8 }
            Write-Host "OBSERVE: $($observations.Count) observacoes (local jsonl)" -ForegroundColor Cyan
        }
    } catch { Write-Host "persist falhou: $_" -ForegroundColor Yellow }
}

# Destaque: oportunidades que cruzaram OVERRIDE (so log -- NAO executa)
$hot = @($observations | Where-Object { $_.tag -eq "OVERRIDE" })
if ($hot.Count -gt 0) {
    Write-Host "[OBSERVE] $($hot.Count) sinal(is) >= $OVERRIDE (executaria se gate live):" -ForegroundColor Magenta
    $hot | ForEach-Object { Write-Host "   $($_.market) $($_.direction) $($_.conviction)/100" -ForegroundColor Magenta }
}
Write-Host "=== FIM (observe) ===" -ForegroundColor Cyan
