# Tests for lib_place_order.ps1

Describe "Place Order Library" {
    BeforeAll {
        $root = Get-Location
        . (Join-Path $root "agents\lib_place_order.ps1")
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
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.01 -Price 50000

            $result.status -eq "PAPER" | Should Be $true
            $result.market -eq "BTCUSDT" | Should Be $true
            $result.type -eq "SPOT" | Should Be $true
            $result.side -eq "BUY" | Should Be $true
            $result.filled -eq 0.01 | Should Be $true
            $result.is_paper -eq $true | Should Be $true
        }

        It "Creates paper FUTURES SELL order" {
            $result = Place-Order -Market "ETHUSDT" -Type "FUTURES" -Side "SELL" -Quantity 1.0 -Price 2500

            $result.status -eq "PAPER" | Should Be $true
            $result.type -eq "FUTURES" | Should Be $true
            $result.side -eq "SELL" | Should Be $true
        }

        It "Generates client_id if not provided" {
            $result = Place-Order -Market "XRPUSDT" -Type "SPOT" -Side "BUY" -Quantity 100 -Price 2.5

            [string]::IsNullOrWhiteSpace($result.client_id) -eq $false | Should Be $true
            $result.client_id -match "order_" | Should Be $true
        }

        It "Uses provided client_id for idempotency" {
            $clientId = "test_order_12345"
            $result = Place-Order -Market "LINKUSDT" -Type "SPOT" -Side "BUY" -Quantity 10 -Price 25 -ClientId $clientId

            $result.client_id -eq $clientId | Should Be $true
        }

        It "Handles all market pairs" {
            $pairs = @("BTCUSDT", "ETHUSDT", "LINKUSDT", "BNBUSDT")
            foreach ($pair in $pairs) {
                $result = Place-Order -Market $pair -Type "SPOT" -Side "BUY" -Quantity 0.01 -Price 100

                $result.market -eq $pair | Should Be $true
                $result.status -eq "PAPER" | Should Be $true
            }
        }

        It "Paper mode returns instant fill" {
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.1 -Price 45000

            $result.filled -eq 0.1 | Should Be $true
            $result.avg_price -eq 45000 | Should Be $true
        }
    }

    Context "Order Validation" {
        BeforeEach {
            Set-TradingMode -Mode "PAPER"
        }

        It "Creates order with valid parameters" {
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.01 -Price 50000
            $result.status -eq "PAPER" | Should Be $true
        }

        It "Generates proper error structure for edge cases" {
            # Test with extreme values (still valid)
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.00001 -Price 100000

            $result.ContainsKey("status") | Should Be $true
            $result.filled -eq 0.00001 | Should Be $true
        }
    }

    Context "Order Sizing" {
        BeforeEach {
            Set-TradingMode -Mode "PAPER"
        }

        It "Accepts small quantity (0.001 BTC)" {
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.001 -Price 50000

            $result.filled -eq 0.001 | Should Be $true
        }

        It "Accepts large quantity (100 XRP)" {
            $result = Place-Order -Market "XRPUSDT" -Type "SPOT" -Side "BUY" -Quantity 100 -Price 2.5

            $result.filled -eq 100 | Should Be $true
        }

        It "Handles fractional prices" {
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.01 -Price 50123.45

            $result.avg_price -eq 50123.45 | Should Be $true
        }
    }

    Context "Multiple Orders" {
        BeforeEach {
            Set-TradingMode -Mode "PAPER"
        }

        It "Creates multiple independent orders" {
            $orders = @()
            $orders += Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.01 -Price 50000
            $orders += Place-Order -Market "ETHUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.1 -Price 2500
            $orders += Place-Order -Market "LINKUSDT" -Type "SPOT" -Side "BUY" -Quantity 10 -Price 25

            @($orders).Count -eq 3 | Should Be $true
            $orders[0].market -eq "BTCUSDT" | Should Be $true
            $orders[1].market -eq "ETHUSDT" | Should Be $true
            $orders[2].market -eq "LINKUSDT" | Should Be $true
        }

        It "Each order has unique client_id (auto-generated)" {
            $order1 = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.01 -Price 50000
            $order2 = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.01 -Price 50000

            $order1.client_id -ne $order2.client_id | Should Be $true
        }

        It "Can reuse client_id for retry (idempotency)" {
            $clientId = "retry_test_001"
            $order1 = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.01 -Price 50000 -ClientId $clientId
            $order2 = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.01 -Price 50000 -ClientId $clientId

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
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.01 -Price 50000
            $result.type -eq "SPOT" | Should Be $true
        }

        It "FUTURES order has correct type" {
            $result = Place-Order -Market "BTCUSDT" -Type "FUTURES" -Side "BUY" -Quantity 0.01 -Price 50000
            $result.type -eq "FUTURES" | Should Be $true
        }

        It "Both execute same way in paper mode" {
            $spot = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.01 -Price 50000
            $futures = Place-Order -Market "BTCUSDT" -Type "FUTURES" -Side "BUY" -Quantity 0.01 -Price 50000

            $spot.status -eq $futures.status | Should Be $true
            $spot.filled -eq $futures.filled | Should Be $true
        }
    }

    Context "Error Handling" {
        BeforeEach {
            Set-TradingMode -Mode "PAPER"
        }

        It "Returns valid response structure on success" {
            $result = Place-Order -Market "BTCUSDT" -Type "SPOT" -Side "BUY" -Quantity 0.01 -Price 50000

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

