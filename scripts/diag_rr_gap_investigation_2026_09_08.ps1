# diag_rr_gap_2026_09_08.ps1 -- ONE-SHOT, so leitura.
#
# Investigacao de causa raiz do R:R realizado (1.38) vs design (1:5 ou 1:3/1:4
# calibrado). Pergunta: os trades vencedores fecham a que fracao do caminho
# ate o TP original? Os trades perdedores (stop_loss) batem no SL ORIGINAL ou
# num nivel ja apertado pelo trailing?
#
# Fonte: CoinEx finished-position (realidade) cruzado com trailing_unified_shadow
# (primeiro registro de cada posicao = entry/target/stop mais proximos da
# abertura real, ja que o motor roda a cada ciclo desde o inicio do trade).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

$windowStart = (Get-Date).ToUniversalTime().AddDays(-30)

Write-Host "=== DIAG RR GAP (READ-ONLY) -- janela desde $($windowStart.ToString('yyyy-MM-dd HH:mm')) UTC ===" -ForegroundColor Cyan

$allTrades = @()
try {
    $futPos = CoinEx-Get "/v2/futures/pending-position?market_type=FUTURES" -EA SilentlyContinue
    $futMarkets = @()
    if ($futPos.code -eq 0) { $futMarkets = @($futPos.data | ForEach-Object { $_.market } | Select-Object -Unique) }
    try {
        $shadowMarketsAll = @(Get-StateRecords -Table "trailing_unified_shadow" -ErrorAction SilentlyContinue | ForEach-Object { $_.market } | Select-Object -Unique)
        $futMarkets = @($futMarkets + $shadowMarketsAll | Select-Object -Unique)
    } catch {}

    foreach ($mkt in $futMarkets) {
        try {
            $r = CoinEx-Get "/v2/futures/finished-position?market=$mkt&market_type=FUTURES&page=1&limit=50" -EA SilentlyContinue
            if ($r.code -eq 0 -and $r.data.Count -gt 0) {
                foreach ($p in $r.data) {
                    $updatedAt = try { [datetimeoffset]::FromUnixTimeMilliseconds([long]$p.updated_at).UtcDateTime } catch { $null }
                    $createdAt = try { [datetimeoffset]::FromUnixTimeMilliseconds([long]$p.created_at).UtcDateTime } catch { $null }
                    if ($updatedAt -and $updatedAt -ge $windowStart) {
                        $allTrades += [PSCustomObject]@{
                            market = $mkt; side = "$($p.side)"; closed_at = $updatedAt; opened_at = $createdAt
                            realized_pnl = [double]$p.realized_pnl; finished_type = "$($p.finished_type)"
                            open_price = [double]$p.open_price; settle_price = [double]$p.settle_price
                        }
                    }
                }
            }
        } catch {}
    }
} catch { Write-Host "ERRO coleta CoinEx: $_" -ForegroundColor Red }

$allTrades = @($allTrades | Sort-Object closed_at)
Write-Host "Total trades na janela: $($allTrades.Count)"
Write-Host ""

$results = @()
foreach ($t in $allTrades) {
    try {
        $rows = @(Get-StateRecords -Table "trailing_unified_shadow" -Filter @{ market = $t.market } -ErrorAction Stop)
        $rows = @($rows | Where-Object {
            try {
                $ts = [datetime]$_.ts
                if ($t.opened_at) { $ts -ge $t.opened_at.AddMinutes(-30) -and $ts -le $t.closed_at }
                else { $ts -le $t.closed_at -and $ts -ge $t.closed_at.AddDays(-3) }
            } catch { $false }
        } | Sort-Object { [datetime]$_.ts })

        if ($rows.Count -eq 0) { continue }

        $first = $rows[0]
        $last = $rows[-1]

        $entry = $t.open_price
        $firstRealStop = if ($first.PSObject.Properties['real_stop']) { [double]$first.real_stop } else { $null }
        $lastRealStop  = if ($last.PSObject.Properties['real_stop']) { [double]$last.real_stop } else { $null }

        $closePrice = $t.settle_price

        $results += [PSCustomObject]@{
            market = $t.market; side = $t.side; finished_type = $t.finished_type
            pnl = $t.realized_pnl; entry = $entry
            first_stop_seen = $firstRealStop; last_stop_seen = $lastRealStop
            close_price = $closePrice
            n_shadow_rows = $rows.Count
            first_reason = "$($first.reason)"
            last_reason = "$($last.reason)"
        }
    } catch {}
}

Write-Host "=== Trades com dado shadow cruzado: $($results.Count) de $($allTrades.Count) ===" -ForegroundColor Yellow
foreach ($r in $results) {
    $slDistFirst = if ($r.first_stop_seen -and $r.entry -gt 0) {
        [Math]::Round(([Math]::Abs($r.entry - $r.first_stop_seen) / $r.entry) * 100, 2)
    } else { $null }
    $slMoved = if ($r.first_stop_seen -and $r.last_stop_seen) {
        [Math]::Round((($r.last_stop_seen - $r.first_stop_seen) / $r.first_stop_seen) * 100, 3)
    } else { $null }
    # p/ stop_loss: closePrice bateu perto do first_stop (original) ou do last_stop (ja movido)?
    $closeVsFirst = if ($r.first_stop_seen -and $r.close_price -gt 0) {
        [Math]::Round((([Math]::Abs($r.close_price - $r.first_stop_seen)) / $r.first_stop_seen) * 100, 3)
    } else { $null }
    $closeVsLast = if ($r.last_stop_seen -and $r.close_price -gt 0) {
        [Math]::Round((([Math]::Abs($r.close_price - $r.last_stop_seen)) / $r.last_stop_seen) * 100, 3)
    } else { $null }
    Write-Host ("  {0} {1} type={2} pnl=`${3} entry={4} first_stop={5}(dist={6}%) last_stop={7}(moveu={8}%) close={9} close_vs_first={10}% close_vs_last={11}% n_rows={12}" -f `
        $r.market, $r.side, $r.finished_type, [Math]::Round($r.pnl,2), $r.entry, $r.first_stop_seen, $slDistFirst, $r.last_stop_seen, $slMoved, $r.close_price, $closeVsFirst, $closeVsLast, $r.n_shadow_rows)
}

Write-Host ""
Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
