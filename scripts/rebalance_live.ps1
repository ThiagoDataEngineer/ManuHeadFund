# rebalance_live.ps1 — Executa rebalance via CoinEx API direto
# 2026-07-08: Close WAVES (-13%), SOLUSDT SHORT anti-regime, reduce ETHUSDT 50%
# Uso: powershell.exe -NoProfile -File scripts/rebalance_live.ps1

. (Join-Path (Split-Path $PSScriptRoot -Parent) "config/config.ps1") -ErrorAction SilentlyContinue

$apiBase = if ($env:COINEX_API_URL) { $env:COINEX_API_URL } else { "https://api.coinex.com" }
$apiKey = if ($env:COINEX_API_KEY) { $env:COINEX_API_KEY } else { "" }
$apiSecret = if ($env:COINEX_API_SECRET) { $env:COINEX_API_SECRET } else { "" }
$uid = if ($env:COINEX_UID) { $env:COINEX_UID } else { "" }

function Get-FuturesPosition {
    param([string]$Market)
    try {
        $resp = Invoke-RestMethod -Uri "$apiBase/v2/futures/positions/$Market" -Method GET -TimeoutSec 10 `
            -Headers @{ "Authorization" = "Bearer $apiKey" }
        if ($resp.code -eq 0 -and $resp.data) { return $resp.data[0] }
    } catch { Write-Host "Error fetching $Market : $_" -ForegroundColor Red }
    return $null
}

function Close-Position {
    param([string]$Market, [double]$Qty, [string]$CloseSide)
    try {
        Write-Host "[CLOSE] $Market qty=$Qty side=$CloseSide" -ForegroundColor Cyan
        $body = @{
            market = $Market
            side = $CloseSide
            quantity = $Qty
            type = "market"
        } | ConvertTo-Json

        $resp = Invoke-RestMethod -Uri "$apiBase/v2/futures/place-order" -Method POST -TimeoutSec 10 `
            -Headers @{ "Authorization" = "Bearer $apiKey"; "Content-Type" = "application/json" } `
            -Body $body

        if ($resp.code -eq 0 -and $resp.data -and $resp.data.order_id) {
            Write-Host "  ✅ order=$($resp.data.order_id)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  ❌ error: $($resp.message)" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "  ❌ exception: $_" -ForegroundColor Red
        return $false
    }
}

"[$(Get-Date -Format 'HH:mm:ss')] REBALANCE LIVE INICIADO"

$actions = @(
    @{ market="WAVESUSDT"; action="close"; pct=1.0 }   # Close 100%
    @{ market="SOLUSDT"; action="close"; pct=1.0 }     # Close 100% SHORT
    @{ market="ETHUSDT"; action="reduce"; pct=0.5 }    # Reduce 50%
)

$closed = 0
foreach ($a in $actions) {
    $pos = Get-FuturesPosition -Market $a.market
    if (-not $pos) { Write-Host "$($a.market) not found"; continue }

    $qty = [double]$pos.quantity
    if ($qty -le 0) { Write-Host "$($a.market) qty=0"; continue }

    $qtyToClose = $qty * $a.pct
    $side = if ([string]$pos.side -eq "long") { "sell" } else { "buy" }

    if (Close-Position -Market $a.market -Qty $qtyToClose -CloseSide $side) {
        $closed++
    }
    Start-Sleep -Milliseconds 500  # Rate limit
}

"[$(Get-Date -Format 'HH:mm:ss')] REBALANCE CONCLUÍDO ($closed posições operadas)"
