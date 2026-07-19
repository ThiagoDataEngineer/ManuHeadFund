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

# 2026-07-19 FIX: finished-order EXIGE -market (nao aceita "todos os mercados
# de uma vez", causa raiz do "invalid argument" -- unico uso ja funcional no
# codebase, lib_coinex.ps1:576, sempre passa market+market_type+side juntos).
# Sem endpoint de "historico global", itera pelos mercados onde ha (ou houve)
# holding real -- descobertos via balance SPOT + posicoes conhecidas, nao
# adivinhados. Cobertura pratica (nao teoricamente completa: um mercado
# zerado ha muito tempo pode nao aparecer no balance atual).

# ==================== SPOT TRADES ====================
if (-not $FuturesOnly) {
    Write-Host "📈 SPOT TRADES (por mercado com holding real)" -ForegroundColor Yellow
    Write-Host "─" * 60

    $spotMarkets = @()
    try {
        $bal = CoinEx-Get "/v2/assets/spot/balance" -EA SilentlyContinue
        if ($bal.code -eq 0) {
            $spotMarkets = @($bal.data | Where-Object { $_.ccy -ne "USDT" -and ([double]$_.available -gt 0 -or [double]$_.frozen -gt 0) } | ForEach-Object { "$($_.ccy)USDT" })
        }
    } catch {
        Write-Host "⚠️ Falha ao listar mercados via balance: $_" -ForegroundColor Yellow
    }

    if ($spotMarkets.Count -eq 0) {
        Write-Host "⚠️ Nenhum mercado com holding atual -- sem lista de onde buscar historico (limitacao: API exige -market, sem holding atual nao ha como descobrir mercados JA zerados sem lista externa)" -ForegroundColor Yellow
    } else {
        Write-Host "Mercados com holding real: $($spotMarkets -join ', ')" -ForegroundColor Gray
        Write-Host ""
        $totalFound = 0
        foreach ($mkt in $spotMarkets) {
            try {
                $r = CoinEx-Get "/v2/spot/finished-order?market=$mkt&market_type=SPOT&page=1&limit=$Limit" -EA SilentlyContinue
                if ($r.code -eq 0 -and $r.data.Count -gt 0) {
                    $totalFound += $r.data.Count
                    Write-Host "  [$mkt] $($r.data.Count) ordem(ns):" -ForegroundColor Green
                    foreach ($trade in $r.data | Sort-Object { [datetime]$_.create_time } -Descending | Select-Object -First 10) {
                        $type = if ($trade.side -eq "buy") { "BUY" } else { "SELL" }
                        Write-Host "    $type @ $($trade.price) | Filled: $($trade.filled_amount) | Compl: $($trade.create_time)"
                    }
                } elseif ($r.code -ne 0) {
                    Write-Host "  [$mkt] erro: $($r.message)" -ForegroundColor Red
                }
            } catch {
                Write-Host "  [$mkt] exceção: $_" -ForegroundColor Red
            }
        }
        Write-Host ""
        Write-Host "Total SPOT encontrado: $totalFound ordem(ns) em $($spotMarkets.Count) mercado(s) verificado(s)" -ForegroundColor Cyan
    }
}

Write-Host ""
Write-Host ""

# ==================== FUTURES TRADES ====================
if (-not $SpotOnly) {
    Write-Host "📉 FUTURES TRADES (por mercado com posicao aberta ou finished-position conhecida)" -ForegroundColor Yellow
    Write-Host "─" * 60

    $futMarkets = @()
    try {
        $futPos = CoinEx-Get "/v2/futures/pending-position?market_type=FUTURES" -EA SilentlyContinue
        if ($futPos.code -eq 0) {
            $futMarkets = @($futPos.data | ForEach-Object { $_.market } | Select-Object -Unique)
        }
    } catch {
        Write-Host "⚠️ Falha ao listar mercados futures via pending-position: $_" -ForegroundColor Yellow
    }

    if ($futMarkets.Count -eq 0) {
        Write-Host "⚠️ Nenhuma posicao FUTURES aberta agora -- sem lista de mercados pra consultar finished-order (API exige -market; historico de posicoes JA fechadas exigiria lista externa de mercados testados, nao disponivel aqui)" -ForegroundColor Yellow
    } else {
        Write-Host "Mercados com posicao FUTURES: $($futMarkets -join ', ')" -ForegroundColor Gray
        Write-Host ""
        $totalFoundF = 0
        foreach ($mkt in $futMarkets) {
            try {
                $r = CoinEx-Get "/v2/futures/finished-order?market=$mkt&market_type=FUTURES&page=1&limit=$Limit" -EA SilentlyContinue
                if ($r.code -eq 0 -and $r.data.Count -gt 0) {
                    $totalFoundF += $r.data.Count
                    Write-Host "  [$mkt] $($r.data.Count) ordem(ns):" -ForegroundColor Green
                    foreach ($trade in $r.data | Sort-Object { [datetime]$_.create_time } -Descending | Select-Object -First 10) {
                        $type = if ($trade.side -eq "buy") { "BUY" } else { "SELL" }
                        $leverage = if ($trade.PSObject.Properties['leverage'] -and [double]$trade.leverage -gt 0) { "$($trade.leverage)x" } else { "N/A" }
                        Write-Host "    $type ($leverage) @ $($trade.price) | Filled: $($trade.filled_amount) | Compl: $($trade.create_time)"
                    }
                } elseif ($r.code -ne 0) {
                    Write-Host "  [$mkt] erro: $($r.message)" -ForegroundColor Red
                }
            } catch {
                Write-Host "  [$mkt] exceção: $_" -ForegroundColor Red
            }
        }
        Write-Host ""
        Write-Host "Total FUTURES encontrado: $totalFoundF ordem(ns) em $($futMarkets.Count) mercado(s) verificado(s)" -ForegroundColor Cyan
    }

    # finished-position: historico de posicoes FUTURES ja fechadas (mesma limitacao
    # de -market obrigatorio -- tenta os mesmos mercados de pending-position como
    # melhor esforco; posicoes fechadas em mercados sem posicao aberta agora nao
    # aparecem aqui).
    if ($futMarkets.Count -gt 0) {
        Write-Host ""
        Write-Host "📉 FUTURES POSICOES FECHADAS (finished-position, mesmos mercados)" -ForegroundColor Yellow
        Write-Host "─" * 60
        foreach ($mkt in $futMarkets) {
            try {
                $r = CoinEx-Get "/v2/futures/finished-position?market=$mkt&market_type=FUTURES&page=1&limit=$Limit" -EA SilentlyContinue
                if ($r.code -eq 0 -and $r.data.Count -gt 0) {
                    Write-Host "  [$mkt] $($r.data.Count) posicao(oes) fechada(s):" -ForegroundColor Green
                    foreach ($pos in $r.data | Select-Object -First 10) {
                        Write-Host "    side=$($pos.side) | realized_pnl=$($pos.realized_pnl) | close_avbl=$($pos.close_avbl)"
                    }
                } elseif ($r.code -ne 0) {
                    Write-Host "  [$mkt] erro: $($r.message)" -ForegroundColor Red
                }
            } catch {
                Write-Host "  [$mkt] exceção: $_" -ForegroundColor Red
            }
        }
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
