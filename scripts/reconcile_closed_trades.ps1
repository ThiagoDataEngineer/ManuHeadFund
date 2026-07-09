# reconcile_closed_trades.ps1 — Registra trades FECHADOS no journal
# 2026-07-08: trade_outcomes.jsonl só tem 8 OPEN, 0 FECHADOS.
# Causa: position_sync_realtime registra posições abertas VIVAS, não fechadas.
# Solução: pull closed trades via CoinEx API orders endpoint, registra como CLOSED no journal

param(
    [bool]$DryRun = $false,
    [string]$OutputPath = "journal/trade_outcomes_closed.jsonl"
)

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent

# 2026-07-09 FIX: path correto e agents/config.ps1 (config/ so tem JSONs).
# config.ps1 ja carrega config.local.ps1 (credenciais) quando existir.
if (Test-Path (Join-Path $root "agents\config.ps1")) {
    . (Join-Path $root "agents\config.ps1")
}
if (Test-Path (Join-Path $root "agents\lib_coinex.ps1")) {
    . (Join-Path $root "agents\lib_coinex.ps1")
}

"[$(Get-Date -Format 'HH:mm:ss')] RECONCILE CLOSED TRADES INICIADO"
"Output: $OutputPath"
"DryRun: $DryRun"

$baseUrl = if ($env:COINEX_API_URL) { $env:COINEX_API_URL } else { "https://api.coinex.com" }
$closedTrades = @()

# Fetch últimas 100 ordens futures FECHADAS (limit 100)
try {
    Write-Host "Fetching closed orders from CoinEx..." -ForegroundColor Cyan
    $resp = Invoke-RestMethod -Uri "$baseUrl/v2/futures/orders?status=done&limit=100" -Method GET `
        -TimeoutSec 15 -Headers @{
            "Authorization" = "Bearer $(if ($env:COINEX_API_KEY) { $env:COINEX_API_KEY } else { '' })"
        } -ErrorAction Stop

    if ($resp.code -eq 0 -and $resp.data) {
        $orders = @($resp.data)
        Write-Host "Found $($orders.Count) closed orders" -ForegroundColor Green

        foreach ($o in $orders) {
            $cumulativePnL = if ($o.realized_pnl) { [double]$o.realized_pnl } else { 0 }
            $pnlPct = if ($o.price -and $cumulativePnL -ne 0) {
                [math]::Round(($cumulativePnL / ([double]$o.price * [double]$o.quantity)) * 100, 2)
            } else { 0 }

            $trade = [PSCustomObject]@{
                trade_id = "$($o.market)-$(Get-Date $o.created_at -Format 'yyyyMMdd-HHmmss')"
                market = $o.market
                direction = if ($o.side -eq "buy") { "LONG" } else { "SHORT" }
                entry_price = [double]$o.price
                entry_time = [datetime]$o.created_at | ConvertTo-Json -AsArray | ConvertFrom-Json
                status = "closed"
                pnl_usd = $cumulativePnL
                pnl_pct = $pnlPct
                size_usd = [double]$o.price * [double]$o.quantity
                leverage = if ($o.leverage) { [double]$o.leverage } else { 1.0 }
                source = "coinex_api_closed_orders"
                registered_at = (Get-Date -Format 'o')
                close_time = [datetime]$o.updated_at | ConvertTo-Json -AsArray | ConvertFrom-Json
                notes = "Reconcile from closed orders API"
            }
            $closedTrades += $trade
        }
    }
} catch {
    Write-Host "Error fetching closed orders: $_" -ForegroundColor Red
}

# Registra no journal
if ($closedTrades.Count -gt 0) {
    Write-Host "Registering $($closedTrades.Count) closed trades..." -ForegroundColor Yellow

    if ($DryRun) {
        Write-Host "[DRY] Would write to $OutputPath"
        $closedTrades | ForEach-Object { $_ | ConvertTo-Json -Compress }
    } else {
        $closedTrades | ForEach-Object { $_ | ConvertTo-Json -Compress } |
            Add-Content -Path $OutputPath -Encoding UTF8
        Write-Host "✅ Closed trades saved to $OutputPath" -ForegroundColor Green
    }

    # Statísticas
    $byMarket = $closedTrades | Group-Object market
    $winners = @($closedTrades | Where-Object { $_.pnl_usd -gt 0 })
    $losers = @($closedTrades | Where-Object { $_.pnl_usd -le 0 })
    $totalPnL = ($closedTrades | Measure-Object -Sum pnl_usd).Sum

    Write-Host "`n[STATS] Closed trades:"
    Write-Host "  Total: $($closedTrades.Count)"
    Write-Host "  Winners: $($winners.Count) ({0:P1})" -f ($winners.Count / $closedTrades.Count)
    Write-Host "  Losers: $($losers.Count) ({0:P1})" -f ($losers.Count / $closedTrades.Count)
    Write-Host "  PnL total: `$$totalPnL USD"
    Write-Host "`n  By market:"
    $byMarket | ForEach-Object { "    $($_.Name): $($_.Count) trades" }
}

"[$(Get-Date -Format 'HH:mm:ss')] RECONCILE CONCLUÍDO"
