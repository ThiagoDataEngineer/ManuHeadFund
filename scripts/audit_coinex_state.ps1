# audit_coinex_state.ps1 — Audit histórico real de trades + balance + posições abertas
# Uso: .\scripts\audit_coinex_state.ps1

param(
    [switch]$SpotOnly,
    [switch]$FuturesOnly,
    [int]$Limit = 100
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"

Set-Location $projectRoot

# ==================== LOAD LIBS ====================
try {
    . (Join-Path $agentsDir "config.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_coinex.ps1") -ErrorAction Stop
} catch {
    Write-Host "❌ Erro ao carregar config/libs: $_" -ForegroundColor Red
    exit 1
}

Write-Host "🔍 AUDITANDO ESTADO COINEX..." -ForegroundColor Cyan
Write-Host ""

# ==================== BALANCE ====================
Write-Host "📊 BALANCE REAL" -ForegroundColor Yellow
Write-Host "─" * 60

try {
    $spotBal = CoinEx-Get "/v2/assets/spot/balance" -EA SilentlyContinue
    if ($spotBal.code -eq 0) {
        Write-Host "✅ SPOT Balance:" -ForegroundColor Green
        $usdt_spot = $spotBal.data | Where-Object { $_.ccy -eq "USDT" } | Select-Object -First 1
        if ($usdt_spot) {
            Write-Host "   USDT Available: $($usdt_spot.available)"
            Write-Host "   USDT Frozen: $($usdt_spot.frozen)"
            Write-Host "   USDT Total: $([double]$usdt_spot.available + [double]$usdt_spot.frozen)"
        }
        $allCoins = @($spotBal.data | Where-Object { [double]$_.available -gt 0 -or [double]$_.frozen -gt 0 })
        if ($allCoins.Count -gt 1) {
            Write-Host "   Outras moedas (não-zero):" -ForegroundColor Gray
            foreach ($coin in $allCoins | Where-Object { $_.ccy -ne "USDT" }) {
                Write-Host "     $($coin.ccy): $($coin.available) (frozen: $($coin.frozen))"
            }
        }
    } else {
        Write-Host "❌ Erro ao puxar balance: $($spotBal.message)" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Exceção: $_" -ForegroundColor Red
}

Write-Host ""

try {
    $futuresBal = CoinEx-Get "/v2/assets/futures/balance" -EA SilentlyContinue
    if ($futuresBal.code -eq 0) {
        Write-Host "✅ FUTURES Balance:" -ForegroundColor Green
        $usdt_fut = $futuresBal.data | Where-Object { $_.ccy -eq "USDT" } | Select-Object -First 1
        if ($usdt_fut) {
            Write-Host "   USDT Available: $($usdt_fut.available)"
            Write-Host "   USDT Frozen: $($usdt_fut.frozen)"
            Write-Host "   USDT Total: $([double]$usdt_fut.available + [double]$usdt_fut.frozen)"
        }
    } else {
        Write-Host "❌ Erro ao puxar futures balance: $($futuresBal.message)" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Exceção: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host ""

# ==================== SPOT TRADES ====================
if (-not $FuturesOnly) {
    Write-Host "📈 SPOT TRADES (últimos $Limit)" -ForegroundColor Yellow
    Write-Host "─" * 60

    try {
        $spotTrades = CoinEx-Get "/v2/spot/finished-order?limit=$Limit" -EA SilentlyContinue
        if ($spotTrades.code -eq 0 -and $spotTrades.data.Count -gt 0) {
            Write-Host "Total trades encontrados: $($spotTrades.data.Count)" -ForegroundColor Green
            Write-Host ""
            foreach ($trade in $spotTrades.data | Sort-Object { [datetime]$_.create_time } -Descending | Select-Object -First 20) {
                $type = if ($trade.side -eq "buy") { "BUY" } else { "SELL" }
                $pnl = [double]$trade.filled_amount * ([double]$trade.avg_price - [double]$trade.price)
                Write-Host "  $($trade.market) | $type @ $($trade.avg_price) | Qty: $($trade.filled_amount) | Compl: $($trade.create_time)"
            }
        } else {
            Write-Host "❌ Nenhum trade spot encontrado ou erro: $($spotTrades.message)" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ Exceção ao puxar trades spot: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host ""

# ==================== FUTURES TRADES ====================
if (-not $SpotOnly) {
    Write-Host "📉 FUTURES TRADES (últimos $Limit)" -ForegroundColor Yellow
    Write-Host "─" * 60

    try {
        $futuresTrades = CoinEx-Get "/v2/futures/finished-order?limit=$Limit" -EA SilentlyContinue
        if ($futuresTrades.code -eq 0 -and $futuresTrades.data.Count -gt 0) {
            Write-Host "Total trades encontrados: $($futuresTrades.data.Count)" -ForegroundColor Green
            Write-Host ""
            foreach ($trade in $futuresTrades.data | Sort-Object { [datetime]$_.create_time } -Descending | Select-Object -First 20) {
                $type = if ($trade.side -eq "buy") { "BUY" } else { "SELL" }
                $leverage = if ([double]$trade.leverage -gt 0) { "$($trade.leverage)x" } else { "N/A" }
                Write-Host "  $($trade.market) | $type ($leverage) @ $($trade.avg_price) | Qty: $($trade.filled_amount) | Compl: $($trade.create_time)"
            }
        } else {
            Write-Host "❌ Nenhum trade futures encontrado ou erro: $($futuresTrades.message)" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ Exceção ao puxar trades futures: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host ""

# ==================== POSIÇÕES ABERTAS ====================
Write-Host "🔓 POSIÇÕES ABERTAS" -ForegroundColor Yellow
Write-Host "─" * 60

if (-not $FuturesOnly) {
    try {
        $spotOpen = CoinEx-Get "/v2/spot/pending-order?limit=100" -EA SilentlyContinue
        if ($spotOpen.code -eq 0 -and $spotOpen.data.Count -gt 0) {
            Write-Host "✅ SPOT Pending Orders: $($spotOpen.data.Count)" -ForegroundColor Green
            foreach ($order in $spotOpen.data | Select-Object -First 10) {
                Write-Host "  $($order.market) | $($order.side) @ $($order.price) | Qty: $($order.amount)" -ForegroundColor Gray
            }
        } else {
            Write-Host "✅ SPOT: Nenhuma ordem aberta" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠️ Erro ao puxar spot pending: $_" -ForegroundColor Yellow
    }
}

Write-Host ""

if (-not $SpotOnly) {
    try {
        $futuresOpen = CoinEx-Get "/v2/futures/pending-position?limit=100" -EA SilentlyContinue
        if ($futuresOpen.code -eq 0 -and $futuresOpen.data.Count -gt 0) {
            Write-Host "✅ FUTURES Posições Abertas: $($futuresOpen.data.Count)" -ForegroundColor Green
            foreach ($pos in $futuresOpen.data | Select-Object -First 10) {
                Write-Host "  $($pos.market) | Side: $($pos.side) | Qty: $($pos.quantity) | Entry: $($pos.entry_price) | Leverage: $($pos.leverage)x" -ForegroundColor Gray
            }
        } else {
            Write-Host "✅ FUTURES: Nenhuma posição aberta" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠️ Erro ao puxar futures pending: $_" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "✅ Audit concluído $(Get-Date)" -ForegroundColor Green
