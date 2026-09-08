# diag_expectancy_stats_2026_09_08.ps1 -- ONE-SHOT, so leitura.
#
# Owner quer calcular a expectativa matematica real do sistema (win_rate,
# R:R medio, avg_win, avg_loss) usando trades FUTURES fechados reais via
# CoinEx finished-position, janela de 30 dias, universo de mercados
# ampliado (posicoes abertas agora + trailing_unified_shadow, mesmo padrao
# ja validado em diag_stoploss_rootcause_2026_09_08.ps1).
#
# NAO calcula sizing nem altera nada -- so estatistica descritiva.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

$windowStart = (Get-Date).ToUniversalTime().AddDays(-30)

Write-Host "=== DIAG EXPECTANCY STATS (READ-ONLY) -- janela desde $($windowStart.ToString('yyyy-MM-dd HH:mm')) UTC ===" -ForegroundColor Cyan
Write-Host ""

# ── universo de mercados: posicoes abertas agora + shadow table ──
$futMarkets = @()
try {
    $futPos = CoinEx-Get "/v2/futures/pending-position?market_type=FUTURES" -EA SilentlyContinue
    if ($futPos.code -eq 0) {
        $futMarkets = @($futPos.data | ForEach-Object { $_.market } | Select-Object -Unique)
    }
} catch {}
try {
    $shadowMarketsAll = @(Get-StateRecords -Table "trailing_unified_shadow" -ErrorAction SilentlyContinue | ForEach-Object { $_.market } | Select-Object -Unique)
    $futMarkets = @($futMarkets + $shadowMarketsAll | Select-Object -Unique)
} catch {}
try {
    $trailMarketsAll = @(Get-StateRecords -Table "trailing_state" -ErrorAction SilentlyContinue | ForEach-Object { $_.market } | Select-Object -Unique)
    $futMarkets = @($futMarkets + $trailMarketsAll | Select-Object -Unique)
} catch {}

Write-Host "Universo de mercados verificados ($($futMarkets.Count)): $($futMarkets -join ', ')" -ForegroundColor White
Write-Host ""

$allTrades = @()
foreach ($mkt in $futMarkets) {
    try {
        $r = CoinEx-Get "/v2/futures/finished-position?market=$mkt&market_type=FUTURES&page=1&limit=100" -EA SilentlyContinue
        if ($r.code -eq 0 -and $r.data.Count -gt 0) {
            foreach ($p in $r.data) {
                $updatedAt = try { [datetimeoffset]::FromUnixTimeMilliseconds([long]$p.updated_at).UtcDateTime } catch { $null }
                if ($updatedAt -and $updatedAt -ge $windowStart) {
                    $allTrades += [PSCustomObject]@{
                        market        = $mkt
                        closed_at     = $updatedAt
                        side          = "$($p.side)"
                        realized_pnl  = [double]$p.realized_pnl
                        finished_type = "$($p.finished_type)"
                        open_price    = [double]$p.open_price
                        close_avbl    = [double]$p.close_avbl
                        margin_avbl   = if ($p.PSObject.Properties.Name -contains 'margin_avbl') { [double]$p.margin_avbl } else { $null }
                    }
                }
            }
        }
    } catch {
        Write-Host "  [$mkt] erro: $_" -ForegroundColor Red
    }
}

$allTrades = @($allTrades | Sort-Object closed_at)
Write-Host "Total trades FUTURES fechados na janela (30d): $($allTrades.Count)" -ForegroundColor White
Write-Host ""

if ($allTrades.Count -eq 0) {
    Write-Host "SEM DADOS -- nao da pra calcular estatistica." -ForegroundColor Red
    exit 0
}

# ── por finished_type ──
Write-Host "=== POR finished_type ===" -ForegroundColor Cyan
$byType = $allTrades | Group-Object finished_type
foreach ($g in $byType) {
    $sum = ($g.Group | Measure-Object -Property realized_pnl -Sum).Sum
    Write-Host ("  {0}: n={1} pnl_total=`${2}" -f $g.Name, $g.Count, [Math]::Round($sum,2))
}
Write-Host ""

# ── win/loss stats gerais ──
$wins = @($allTrades | Where-Object { $_.realized_pnl -gt 0 })
$losses = @($allTrades | Where-Object { $_.realized_pnl -lt 0 })
$flat = @($allTrades | Where-Object { $_.realized_pnl -eq 0 })

$winRate = if ($allTrades.Count -gt 0) { $wins.Count / $allTrades.Count } else { 0 }
$lossRate = if ($allTrades.Count -gt 0) { $losses.Count / $allTrades.Count } else { 0 }
$avgWin = if ($wins.Count -gt 0) { ($wins | Measure-Object -Property realized_pnl -Average).Average } else { 0 }
$avgLoss = if ($losses.Count -gt 0) { [Math]::Abs(($losses | Measure-Object -Property realized_pnl -Average).Average) } else { 0 }
$totalPnl = ($allTrades | Measure-Object -Property realized_pnl -Sum).Sum
$rrRealized = if ($avgLoss -gt 0) { $avgWin / $avgLoss } else { 0 }
$expectancyPerTrade = ($winRate * $avgWin) - ($lossRate * $avgLoss)

Write-Host "=== ESTATISTICA GERAL (30d) ===" -ForegroundColor Cyan
Write-Host "  n total: $($allTrades.Count)"
Write-Host "  wins: $($wins.Count) | losses: $($losses.Count) | flat: $($flat.Count)"
Write-Host "  win_rate: $([Math]::Round($winRate*100,1))%"
Write-Host "  avg_win: `$$([Math]::Round($avgWin,2))"
Write-Host "  avg_loss: `$$([Math]::Round($avgLoss,2))"
Write-Host "  R:R realizado (avg_win/avg_loss): $([Math]::Round($rrRealized,2))"
Write-Host "  expectativa por trade (`$): `$$([Math]::Round($expectancyPerTrade,2))"
Write-Host "  pnl_total (30d): `$$([Math]::Round($totalPnl,2))"
Write-Host ""

# ── janela real coberta (primeiro trade -> ultimo trade) ──
$firstTrade = $allTrades[0].closed_at
$lastTrade = $allTrades[-1].closed_at
$daysCovered = ($lastTrade - $firstTrade).TotalDays
$tradesPerDay = if ($daysCovered -gt 0) { $allTrades.Count / $daysCovered } else { $allTrades.Count }

Write-Host "=== FREQUENCIA ===" -ForegroundColor Cyan
Write-Host "  primeiro trade: $($firstTrade.ToString('yyyy-MM-dd HH:mm'))"
Write-Host "  ultimo trade: $($lastTrade.ToString('yyyy-MM-dd HH:mm'))"
Write-Host "  dias cobertos: $([Math]::Round($daysCovered,1))"
Write-Host "  trades/dia (media): $([Math]::Round($tradesPerDay,2))"
Write-Host ""

# ── distribuicao de tamanho de perda/ganho em % (se margin_avbl disponivel) ──
Write-Host "=== TOP 10 MAIORES PERDAS ===" -ForegroundColor Cyan
$allTrades | Sort-Object realized_pnl | Select-Object -First 10 | ForEach-Object {
    Write-Host ("  {0} {1} pnl=`${2} type={3}" -f $_.closed_at.ToString('yyyy-MM-dd HH:mm'), $_.market, [Math]::Round($_.realized_pnl,2), $_.finished_type)
}
Write-Host ""
Write-Host "=== TOP 10 MAIORES GANHOS ===" -ForegroundColor Cyan
$allTrades | Sort-Object realized_pnl -Descending | Select-Object -First 10 | ForEach-Object {
    Write-Host ("  {0} {1} pnl=`${2} type={3}" -f $_.closed_at.ToString('yyyy-MM-dd HH:mm'), $_.market, [Math]::Round($_.realized_pnl,2), $_.finished_type)
}
Write-Host ""

Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
