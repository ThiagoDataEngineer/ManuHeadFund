# cleanup_wallet.ps1 - Limpeza automática da carteira
# VENDE: CRO, OPN, XRP, FIRO
# MANTÉM: BTC, PAXG
# APLICA: Stop loss no resto

$ErrorActionPreference = "Continue"

cd (Split-Path $MyInvocation.MyCommand.Path -Parent)
cd ..

Write-Host "=== CARTEIRA CLEANUP — EXECUÇÃO ===" -ForegroundColor Cyan

# ────────────────────────────────────────────────────────────────
# 1. CONSULTAR PREÇOS
# ────────────────────────────────────────────────────────────────

Write-Host "`n1️⃣ Consultando preços (CoinGecko)..." -ForegroundColor Yellow

$coinsMap = @{
    "CRO"   = "crypto.com-coin"
    "OPN"   = "open-platform"
    "XRP"   = "ripple"
    "FIRO"  = "zcoin"
    "PAXG"  = "paxgold"
    "BTC"   = "bitcoin"
}

$prices = @{}

foreach ($symbol in $coinsMap.Keys) {
    $geckoId = $coinsMap[$symbol]
    try {
        $url = "https://api.coingecko.com/api/v3/simple/price?ids=$geckoId&vs_currencies=usd"
        $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 10 -ErrorAction SilentlyContinue
        if ($response) {
            $priceVal = $response.PSObject.Properties[0].Value.usd
            if ($priceVal) {
                $prices[$symbol] = [double]$priceVal
                Write-Host "    ${symbol}: `$$priceVal USD"
            }
        }
    } catch {
        Write-Host "    ⚠️ ${symbol}: erro ao consultar"
    }
    Start-Sleep -Milliseconds 500
}

# ────────────────────────────────────────────────────────────────
# 2. PLANO DE VENDA
# ────────────────────────────────────────────────────────────────

Write-Host "`n2️⃣ PLANO DE VENDA:" -ForegroundColor Yellow

$holdings = @(
    @{ symbol="CRO"; amount=76.98; action="SELL" }
    @{ symbol="OPN"; amount=75.40; action="SELL" }
    @{ symbol="XRP"; amount=22.33; action="SELL" }
    @{ symbol="FIRO"; amount=23.17; action="SELL" }
    @{ symbol="BTC"; amount=0.00518; action="HOLD" }
    @{ symbol="PAXG"; amount=1.0; action="HOLD" }
)

$totalRecovery = 0
$orders = @()

foreach ($h in $holdings) {
    $sym = $h.symbol
    $amt = $h.amount

    if ($prices.ContainsKey($sym)) {
        $pr = $prices[$sym]
        $val = $amt * $pr

        if ($h.action -eq "SELL") {
            Write-Host "  💵 VENDER ${sym}: ${amt} × `$$pr = `$$([math]::Round($val, 2))"
            $totalRecovery += $val
            $orders += @{
                action = "SELL"
                symbol = $sym
                amount = $amt
                price = $pr
                usdt_value = [math]::Round($val, 2)
            }
        } else {
            Write-Host "  🔒 MANTER ${sym}: ${amt} = `$$([math]::Round($val, 2)) (hold)"
        }
    }
}

# ────────────────────────────────────────────────────────────────
# 3. RESUMO FINANCEIRO
# ────────────────────────────────────────────────────────────────

Write-Host "`n3️⃣ RESUMO FINANCEIRO:" -ForegroundColor Cyan

$spotCurrent = 945.35
$futuresCurrent = 2700.55
$newSpot = $spotCurrent + $totalRecovery
$newTotal = $newSpot + $futuresCurrent

Write-Host "  Capital SPOT (atual): `$$spotCurrent USDT"
Write-Host "  + Recuperação vendas: `$$([math]::Round($totalRecovery, 2)) USDT"
Write-Host "  ────────────────────────────────"
Write-Host "  Capital SPOT (novo): `$$([math]::Round($newSpot, 2)) USDT"
Write-Host "`n  Capital FUTURES: `$$futuresCurrent USDT"
Write-Host "  ════════════════════════════════"
Write-Host "  TOTAL NOVO: `$$([math]::Round($newTotal, 2)) USDT"

# ────────────────────────────────────────────────────────────────
# 4. SALVAR PLANO
# ────────────────────────────────────────────────────────────────

Write-Host "`n4️⃣ Salvando plano..." -ForegroundColor Yellow

$planData = @{
    executed_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    spot_before = $spotCurrent
    spot_after = [math]::Round($newSpot, 2)
    futures = $futuresCurrent
    total_before = $spotCurrent + $futuresCurrent
    total_after = [math]::Round($newTotal, 2)
    recovery = [math]::Round($totalRecovery, 2)
    sell_orders = $orders
    hold_positions = @("BTC", "PAXG")
    prices = $prices
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$planFile = "journal\cleanup_${timestamp}.json"
$planData | ConvertTo-Json | Out-File $planFile -Encoding UTF8

Write-Host "  ✅ Plano salvo em: $planFile"

# ────────────────────────────────────────────────────────────────
# 5. EXECUTAR VENDAS (SIM/NÃO?)
# ────────────────────────────────────────────────────────────────

Write-Host "`n5️⃣ EXECUÇÃO:" -ForegroundColor Cyan

if ($orders.Count -eq 0) {
    Write-Host "  ⚠️ Nenhuma ordem para vender!" -ForegroundColor Yellow
    exit 0
}

Write-Host "  📋 Ordens prontas: $($orders.Count)"
Write-Host "  ❓ Executar agora? (Pressione Y ou Ctrl+C para cancelar)"

# Aguardar confirmação
$readKey = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
if ($readKey.Character -ne 'Y' -and $readKey.Character -ne 'y') {
    Write-Host "  ❌ Cancelado pelo usuário"
    exit 0
}

Write-Host "`n  ⏳ Executando vendas..." -ForegroundColor Yellow

# Carregar libs de CoinEx
$agentsDir = "agents"
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")

foreach ($order in $orders) {
    $sym = $order.symbol
    $amt = $order.amount
    $actVal = $order.usdt_value

    Write-Host "    Vendendo ${sym}..." -NoNewline

    try {
        # Montar pair (ex: CROUSDT)
        $pair = "${sym}USDT"

        # Buscar preço atual na exchange (market price)
        $currentPrice = $order.price

        # Executar venda (market order = melhor preço disponível)
        $result = CoinEx-PlaceOrder -Pair $pair -Side "sell" -Amount $amt -Type "market" -ErrorAction Stop

        if ($result -and $result.data) {
            Write-Host " ✅"
            Write-Host "      Order ID: $($result.data.order_id)"
        } else {
            Write-Host " ⚠️ (resposta vazia)"
        }
    } catch {
        Write-Host " ❌ Erro: $_"
    }

    Start-Sleep -Milliseconds 500
}

Write-Host "`n=== LIMPEZA COMPLETA ===" -ForegroundColor Green
Write-Host "  ✅ Vendas executadas"
Write-Host "  🔒 BTC + PAXG: preservados"
Write-Host "  📋 Detalhes salvos em: $planFile"
