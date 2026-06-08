# Tests for lib_hybrid_orchestrator.ps1
# Pester 3.4 compatible

Describe "Hybrid Orchestrator" {
    BeforeAll {
        $root = Get-Location
        . (Join-Path $root "agents\lib_hybrid_orchestrator.ps1")
    }

    Context "Position Sizing" {
        It "Calculates correct SPOT position for BULL_STRONG" {
            $positions = Get-HybridPositionSizes -Regime "BULL_STRONG"
            ([Math]::Round($positions.spot_usdt, 2) -eq 13.50) | Should Be $true
        }

        It "Reduces positions by 50% for BEAR_STRONG" {
            $positionsNormal = Get-HybridPositionSizes -Regime "BULL_WEAK"
            $positionsBearStrong = Get-HybridPositionSizes -Regime "BEAR_STRONG"
            ($positionsBearStrong.spot_usdt -eq ($positionsNormal.spot_usdt * 0.5)) | Should Be $true
        }

        It "Never exceeds 1% hard cap per market" {
            $positions = Get-HybridPositionSizes -Regime "BULL_STRONG"
            $spotPct = ($positions.spot_usdt / 1350.425) * 100
            ($spotPct -le 1.0) | Should Be $true
        }
    }

    Context "SPOT Trade Execution" {
        It "Creates valid SPOT trade object" {
            $signal = @{
                market = "BTCUSDT"
                entry_price = 50000
                stop_loss_pct = 0.01
                type = "VOL_CLIMAX_ENGULFING"
                confidence = 0.42
            }
            $trade = Execute-SpotTrade -Signal $signal -PositionSizeUSDT 13.5 -Regime "BEAR_WEAK"
            ($trade.market -eq "SPOT") | Should Be $true
            ($trade.position_size_usd -eq 13.5) | Should Be $true
        }

        It "SPOT has NO liquidation risk" {
            $signal = @{
                market = "BTCUSDT"
                entry_price = 50000
                stop_loss_pct = 0.01
                type = "VOL_CLIMAX_ENGULFING"
                confidence = 0.42
            }
            $trade = Execute-SpotTrade -Signal $signal -PositionSizeUSDT 13.5 -Regime "BEAR_WEAK"
            ($trade.liquidation_risk -eq "NONE") | Should Be $true
        }

        It "Calculates stop loss correctly" {
            $signal = @{
                market = "BTCUSDT"
                entry_price = 100
                stop_loss_pct = 0.01
                type = "VOL_CLIMAX"
                confidence = 0.37
            }
            $trade = Execute-SpotTrade -Signal $signal -PositionSizeUSDT 10 -Regime "BULL_WEAK"
            ($trade.stop_loss -eq 99) | Should Be $true
        }
    }

    Context "FUTURES Trade Execution" {
        It "Creates valid FUTURES trade object" {
            $signal = @{
                market = "BTCUSDT"
                entry_price = 50000
                stop_loss_pct = 0.01
                type = "VOL_CLIMAX_ENGULFING"
                confidence = 0.42
            }
            $trade = Execute-FuturesTrade -Signal $signal -PositionSizeUSDT 10.8 -Regime "BEAR_WEAK"
            ($trade.market -eq "FUTURES") | Should Be $true
            ($trade.position_size_usd -eq 10.8) | Should Be $true
        }

        It "FUTURES has liquidation monitoring" {
            $signal = @{
                market = "BTCUSDT"
                entry_price = 50000
                stop_loss_pct = 0.01
                type = "VOL_CLIMAX_ENGULFING"
                confidence = 0.42
            }
            $trade = Execute-FuturesTrade -Signal $signal -PositionSizeUSDT 10.8 -Regime "BEAR_WEAK"
            ($trade.liquidation_risk -eq "MONITOR") | Should Be $true
        }

        It "Calculates liquidation price correctly" {
            $signal = @{
                market = "BTCUSDT"
                entry_price = 100
                stop_loss_pct = 0.01
                type = "VOL_CLIMAX"
                confidence = 0.37
            }
            $trade = Execute-FuturesTrade -Signal $signal -PositionSizeUSDT 10 -Regime "BULL_WEAK"
            ($trade.liquidation_price -eq 50) | Should Be $true
        }

        It "Stop loss is above liquidation price" {
            $signal = @{
                market = "BTCUSDT"
                entry_price = 100
                stop_loss_pct = 0.02
                type = "VOL_CLIMAX"
                confidence = 0.37
            }
            $trade = Execute-FuturesTrade -Signal $signal -PositionSizeUSDT 10 -Regime "BULL_WEAK"
            ($trade.stop_loss -gt $trade.liquidation_price) | Should Be $true
        }
    }

    Context "Hybrid Signal Execution" {
        It "Executes both SPOT and FUTURES simultaneously" {
            $signal = @{
                market = "BTCUSDT"
                type = "VOL_CLIMAX_ENGULFING"
                confidence = 0.42
                entry_price = 50000
                stop_loss_pct = 0.01
                direction = "LONG"
            }
            $result = Execute-HybridSignal -Signal $signal -Regime "BEAR_WEAK"
            ($result.spot_trade -ne $null) | Should Be $true
            ($result.futures_trade -ne $null) | Should Be $true
            ($result.regime -eq "BEAR_WEAK") | Should Be $true
        }

        It "Combined risk equals sum of both markets" {
            $signal = @{
                market = "BTCUSDT"
                type = "VOL_CLIMAX_ENGULFING"
                confidence = 0.42
                entry_price = 50000
                stop_loss_pct = 0.01
            }
            $result = Execute-HybridSignal -Signal $signal -Regime "BEAR_WEAK"
            $combinedRisk = $result.spot_trade.risk_usd + $result.futures_trade.risk_usd
            ($result.combined_risk -eq $combinedRisk) | Should Be $true
        }
    }

    Context "Rebalancing" {
        It "Detects no rebalance needed when drift <10%" {
            $result = Rebalance-HybridCapital -CurrentSpotBalance 1350.425 -CurrentFuturesBalance 1350.425
            ($result.rebalance_needed -eq $false) | Should Be $true
        }

        It "Identifies source market for rebalancing when drift >10%" {
            # Create bigger drift to trigger rebalance_needed=true (11%+ required)
            $result = Rebalance-HybridCapital -CurrentSpotBalance 1700 -CurrentFuturesBalance 1000.85
            ($result.rebalance_needed -eq $true) | Should Be $true
            ($result.from_market -eq "SPOT") | Should Be $true
        }
    }

    Context "Risk Management" {
        It "BEAR_STRONG reduces position by 50%" {
            $positions = Get-HybridPositionSizes -Regime "BEAR_STRONG"
            $positionsBull = Get-HybridPositionSizes -Regime "BULL_WEAK"
            ($positions.spot_usdt -eq ($positionsBull.spot_usdt * 0.5)) | Should Be $true
        }

        It "Each market respects 1% capital hard cap" {
            $signal = @{
                market = "BTCUSDT"
                type = "VOL_CLIMAX"
                entry_price = 50000
                stop_loss_pct = 0.01
            }
            $result = Execute-HybridSignal -Signal $signal -Regime "BULL_STRONG"
            # SPOT should be 1% of $1350.425 = $13.50425
            ([Math]::Round($result.spot_trade.position_size_usd, 2) -eq ([Math]::Round(13.50, 2))) | Should Be $true
        }

        It "Liquidation price is always less than stop loss" {
            $signal = @{
                market = "BTCUSDT"
                type = "VOL_CLIMAX"
                entry_price = 1000
                stop_loss_pct = 0.02
            }
            $trade = Execute-FuturesTrade -Signal $signal -PositionSizeUSDT 10 -Regime "BULL_WEAK"
            ($trade.liquidation_price -lt $trade.stop_loss) | Should Be $true
        }
    }
}

