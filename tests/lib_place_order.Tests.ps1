# Tests for lib_place_order.ps1

Describe "Place Order Library" {
    BeforeAll {
        $root = Get-Location
        . (Join-Path $root "agents\lib_place_order.ps1")
        . (Join-Path $root "agents\lib_hybrid_orchestrator.ps1")

        # 2026-07-23 FIX: Place-Order rejeita posicoes acima de 1% do capital
        # REAL (Get-DynamicCapital -- busca CoinEx, cai no fallback real
        # $2425.33 SPOT / $2718.49 FUTURES se API falhar). Testes antigos
        # usavam Quantity*Price chumbados (ex: 0.01*50000=$500) que violam o
        # cap de 1% ($24.25) do capital atual -- nao e bug de producao, e o
        # teste que ficou desatualizado com o capital real. Calculando a
        # partir do capital real em vez de chumbar, os testes acompanham
        # qualquer capital futuro sem quebrar de novo.
        $__capital = Get-DynamicCapital
        $script:SafeSpotPrice = 100
        $script:SafeSpotQty = [Math]::Round(($__capital.spot_capital * 0.005) / $script:SafeSpotPrice, 4)  # ~0.5% do cap, margem de sobra
        $script:SafeFuturesPrice = 100
        $script:SafeFuturesQty = [Math]::Round(($__capital.futures_capital * 0.005) / $script:SafeFuturesPrice, 4)
    }

    Context "Trading Mode" {
        It "Defaults to PAPER mode" {
            Set-TradingMode -Mode "PAPER"
            (Get-TradingMode) -eq "PAPER" | Should Be $true
        }

        It "Switches to LIVE mode" {
            Set-TradingMode -Mode "LIVE"
            (Get-TradingMode) -eq "LIVE" | Should Be $true
        }

        It "Switches back to PAPER mode" {
            Set-TradingMode -Mode "PAPER"
            (Get-TradingMode) -eq "PAPER" | Should Be $true
        }
    }

    Context "Paper Mode Orders" {
        BeforeEach {
            Set-TradingMode -Mode "PAPER"
        }

        It "Creates paper SPOT BUY order" {
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice

            $result.status -eq "PAPER" | Should Be $true
            $result.market -eq "BTCUSDT" | Should Be $true
            $result.type -eq "SPOT" | Should Be $true
            $result.side -eq "BUY" | Should Be $true
            $result.filled -eq $script:SafeSpotQty | Should Be $true
            $result.is_paper -eq $true | Should Be $true
        }

        It "Creates paper FUTURES SELL order" {
            $result = Place-Order -Market "ETHUSDT" -Type "FUTURES" -Side "SELL" -Quantity $script:SafeFuturesQty -Price $script:SafeFuturesPrice

            $result.status -eq "PAPER" | Should Be $true
            $result.type -eq "FUTURES" | Should Be $true
            $result.side -eq "SELL" | Should Be $true
        }

        It "Generates client_id if not provided" {
            $result = Place-Order -Market "XRPUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice

            [string]::IsNullOrWhiteSpace($result.client_id) -eq $false | Should Be $true
            $result.client_id -match "order_" | Should Be $true
        }

        It "Uses provided client_id for idempotency" {
            $clientId = "test_order_12345"
            $result = Place-Order -Market "LINKUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice -ClientId $clientId

            $result.client_id -eq $clientId | Should Be $true
        }

        It "Handles all market pairs" {
            $pairs = @("BTCUSDT", "ETHUSDT", "LINKUSDT", "BNBUSDT")
            foreach ($pair in $pairs) {
                $result = Place-Order -Market $pair -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice

                $result.market -eq $pair | Should Be $true
                $result.status -eq "PAPER" | Should Be $true
            }
        }

        It "Paper mode returns instant fill" {
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice

            $result.filled -eq $script:SafeSpotQty | Should Be $true
            $result.avg_price -eq $script:SafeSpotPrice | Should Be $true
        }
    }

    Context "Order Validation" {
        BeforeEach {
            Set-TradingMode -Mode "PAPER"
        }

        It "Creates order with valid parameters" {
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice
            $result.status -eq "PAPER" | Should Be $true
        }

        It "Generates proper error structure for edge cases" {
            # Test with extreme values (still valid) -- quantidade minuscula,
            # dentro do cap por construcao (positionValue ~0)
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.00001 -Price 100000

            $result.ContainsKey("status") | Should Be $true
            $result.filled -eq 0.00001 | Should Be $true
        }
    }

    Context "Order Sizing" {
        BeforeEach {
            Set-TradingMode -Mode "PAPER"
        }

        It "Accepts small quantity" {
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity ($script:SafeSpotQty / 10) -Price $script:SafeSpotPrice

            $result.filled -eq ($script:SafeSpotQty / 10) | Should Be $true
        }

        It "Accepts larger quantity dentro do cap real" {
            $result = Place-Order -Market "XRPUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice

            $result.filled -eq $script:SafeSpotQty | Should Be $true
        }

        It "Handles fractional prices" {
            # Preco fracionario alto exige quantidade proporcionalmente menor
            # pra respeitar o cap real de 1% do capital.
            $fractionalPrice = 50123.45
            $qty = [Math]::Round(($script:SafeSpotQty * $script:SafeSpotPrice) / $fractionalPrice, 8)
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity $qty -Price $fractionalPrice

            $result.avg_price -eq $fractionalPrice | Should Be $true
        }
    }

    Context "Multiple Orders" {
        BeforeEach {
            Set-TradingMode -Mode "PAPER"
        }

        It "Creates multiple independent orders" {
            $orders = @()
            $orders += Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice
            $orders += Place-Order -Market "ETHUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice
            $orders += Place-Order -Market "LINKUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice

            @($orders).Count -eq 3 | Should Be $true
            $orders[0].market -eq "BTCUSDT" | Should Be $true
            $orders[1].market -eq "ETHUSDT" | Should Be $true
            $orders[2].market -eq "LINKUSDT" | Should Be $true
        }

        It "Each order has unique client_id (auto-generated)" {
            $order1 = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice
            $order2 = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice

            $order1.client_id -ne $order2.client_id | Should Be $true
        }

        It "Can reuse client_id for retry (idempotency)" {
            $clientId = "retry_test_001"
            $order1 = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice -ClientId $clientId
            $order2 = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice -ClientId $clientId

            $order1.client_id -eq $clientId | Should Be $true
            $order2.client_id -eq $clientId | Should Be $true
            # In real scenario, server would dedupe and return same order
        }
    }

    Context "SPOT vs FUTURES" {
        BeforeEach {
            Set-TradingMode -Mode "PAPER"
        }

        It "SPOT order has correct type" {
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice
            $result.type -eq "SPOT" | Should Be $true
        }

        It "FUTURES order has correct type" {
            $result = Place-Order -Market "BTCUSDT" -Type "FUTURES" -Side "BUY" -Quantity $script:SafeFuturesQty -Price $script:SafeFuturesPrice
            $result.type -eq "FUTURES" | Should Be $true
        }

        It "Both execute same way in paper mode" {
            $spot = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice
            $futures = Place-Order -Market "BTCUSDT" -Type "FUTURES" -Side "BUY" -Quantity $script:SafeFuturesQty -Price $script:SafeFuturesPrice

            $spot.status -eq $futures.status | Should Be $true
        }
    }

    Context "Error Handling" {
        BeforeEach {
            Set-TradingMode -Mode "PAPER"
        }

        It "Returns valid response structure on success" {
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity $script:SafeSpotQty -Price $script:SafeSpotPrice

            $result.ContainsKey("status") | Should Be $true
            $result.ContainsKey("market") | Should Be $true
            $result.ContainsKey("client_id") | Should Be $true
            $result.ContainsKey("filled") | Should Be $true
        }

        It "Handles zero quantity gracefully" {
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0 -Price 50000

            $result.filled -eq 0 | Should Be $true
            $result.status -eq "PAPER" | Should Be $true
        }
    }
}

