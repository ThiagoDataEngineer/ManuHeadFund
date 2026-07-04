# api_research_cycle.ps1 — Pesquisa continua das APIs (4x/dia via guardian)
# 2026-07-04 (pedido do dono): estudo continuo de fontes de dados da exchange
# como entrada dos agentes que aprendem. v1: FUNDING/CROWDING em todo o universo
# de futures — atualiza watchlist de crowded markets + injeta no fluxo.
# Futuro: orderbook depth, liquidations, position tiers (mesma esteira).

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
$journalDir = Join-Path $root "journal"
$logFile = Join-Path $journalDir "api_research.log"

function Write-RLog { param([string]$M)
    $l = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $M"
    Add-Content -Path $logFile -Value $l -Encoding utf8; Write-Host $l
}

try { . (Join-Path $root "agents\lib_telegram.ps1") } catch { }
. (Join-Path $root "agents\lib_crowding_signal.ps1")

Write-RLog "research cycle: varrendo funding de todos os futures..."

$crowdedLongs = @(); $crowdedShorts = @(); $scanned = 0
try {
    $r = Invoke-RestMethod -Uri "https://api.coinex.com/v2/futures/funding-rate" -TimeoutSec 30
    if ($r.code -eq 0 -and $r.data) {
        $thr = (Get-CrowdingThresholds -JournalDir $journalDir).extreme_pct
        foreach ($row in $r.data) {
            if ($row.market -notmatch 'USDT$') { continue }
            $scanned++
            $fr = 0.0
            try { $fr = [math]::Round([double]$row.latest_funding_rate * 100, 4) } catch { continue }
            if ($fr -ge $thr) { $crowdedLongs += [PSCustomObject]@{ market=$row.market; funding_pct=$fr } }
            elseif ($fr -le -$thr) { $crowdedShorts += [PSCustomObject]@{ market=$row.market; funding_pct=$fr } }
        }
    }
} catch { Write-RLog "fetch funding falhou: $($_.Exception.Message)" }

# Watchlist persistida (consumida por scan_master/mentor via crowding signal)
$watch = [PSCustomObject]@{
    ts = (Get-Date).ToUniversalTime().ToString("o")
    scanned = $scanned
    crowded_longs = @($crowdedLongs | Sort-Object funding_pct -Descending | Select-Object -First 15)
    crowded_shorts = @($crowdedShorts | Sort-Object funding_pct | Select-Object -First 15)
}
($watch | ConvertTo-Json -Depth 4) | Out-File (Join-Path $journalDir "crowding_watchlist.json") -Encoding UTF8 -Force
Write-RLog "scanned=$scanned | crowded_longs=$(@($crowdedLongs).Count) | crowded_shorts=$(@($crowdedShorts).Count)"

# Digest Telegram (visibilidade; SHORT candidates = crowded longs)
if (@($crowdedLongs).Count -gt 0 -and (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue)) {
    $top = @($crowdedLongs | Sort-Object funding_pct -Descending | Select-Object -First 5 | ForEach-Object { "$($_.market) +$($_.funding_pct)%" }) -join " | "
    try { Send-TelegramAlert -Message "🔬 <b>API RESEARCH (funding)</b>`nLongs CROWDED (candidatos a SHORT por evidencia 56%):`n$top`n<i>$scanned futures varridos</i>" | Out-Null } catch { }
}
