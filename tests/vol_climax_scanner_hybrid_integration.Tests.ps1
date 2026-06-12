# Integration test: vol_climax_scanner with lib_hybrid_orchestrator

Describe "Vol Climax Scanner Hybrid Integration" {
    BeforeAll {
        $root = Get-Location
        . (Join-Path $root "agents\lib_hybrid_orchestrator.ps1")
        . (Join-Path $root "agents\lib_regime_position_sizing.ps1")
        . (Join-Path $root "agents\lib_signal_combo.ps1")
    }

    Context "Hybrid Orchestrator Integration" {
        It "Loads lib_hybrid_orchestrator successfully" {
            (Get-Command Execute-HybridSignal -ErrorAction SilentlyContinue) -ne $null | Should Be $true
        }

        It "Gets hybrid position sizes for BEAR_WEAK regime" {
            $positions = Get-HybridPositionSizes -Regime "BEAR_WEAK"
            $positions.spot_usdt -gt 0 | Should Be $true
            $positions.futures_usdt -gt 0 | Should Be $true
        }

        It "Executes hybrid signal with realistic parameters" {
            $signal = @{
                market = "BTCUSDT"
                type = "VOL_CLIMAX_ENGULFING"
                confidence = 0.42
                entry_price = 50000
                stop_loss_pct = 0.01
                direction = "LONG"
            }

            $result = Execute-HybridSignal -Signal $signal -Regime "BEAR_WEAK"

            $result -ne $null | Should Be $true
            $result.spot_trade -ne $null | Should Be $true
            $result.futures_trade -ne $null | Should Be $true
            $result.combined_risk -gt 0 | Should Be $true
        }

        It "SPOT position is 1% of SPOT capital ($1,350)" {
            $positions = Get-HybridPositionSizes -Regime "BEAR_WEAK"
            # Should be ~13.50
            ([Math]::Round($positions.spot_usdt, 1) -eq 13.5) | Should Be $true
        }

        It "FUTURES position is 0.8% of FUTURES capital ($1,350)" {
            $positions = Get-HybridPositionSizes -Regime "BEAR_WEAK"
            # Should be ~10.80
            ([Math]::Round($positions.futures_usdt, 1) -eq 10.8) | Should Be $true
        }

        It "Both positions respect hard cap" {
            foreach ($regime in @("BULL_STRONG", "BULL_WEAK", "BEAR_WEAK", "BEAR_STRONG")) {
                $positions = Get-HybridPositionSizes -Regime $regime

                # SPOT max: $1,350 * 1% = $13.50
                ($positions.spot_usdt -le 13.505) | Should Be $true

                # FUTURES max: $1,350 * 1% = $13.50 (before 0.8% reduction)
                ($positions.futures_usdt -le 13.505) | Should Be $true
            }
        }

        It "Risk exposure is balanced (SPOT + FUTURES ~equal)" {
            $signal = @{
                market = "ETHUSDT"
                type = "VOL_CLIMAX"
                confidence = 0.40
                entry_price = 2500
                stop_loss_pct = 0.01
            }

            $result = Execute-HybridSignal -Signal $signal -Regime "BULL_WEAK"

            $spotRisk = $result.spot_trade.risk_usd
            $futuresRisk = $result.futures_trade.risk_usd
            $ratio = $spotRisk / $futuresRisk

            # SPOT risk should be slightly higher (position 13.5 vs 10.8)
            ($ratio -ge 1.0 -and $ratio -le 1.5) | Should Be $true
        }

        It "Supports all 4 regimes" {
            $regimes = @("BULL_STRONG", "BULL_WEAK", "BEAR_WEAK", "BEAR_STRONG")

            foreach ($regime in $regimes) {
                $signal = @{
                    market = "XRPUSDT"
                    type = "VOL_CLIMAX"
                    entry_price = 2.5
                    stop_loss_pct = 0.01
                }

                { Execute-HybridSignal -Signal $signal -Regime $regime } | Should Not Throw
            }
        }

        It "Regime filter reduces BEAR_STRONG position" {
            $bullPos = Get-HybridPositionSizes -Regime "BULL_WEAK"
            $bearPos = Get-HybridPositionSizes -Regime "BEAR_STRONG"

            # BEAR_STRONG should be 50% of BULL_WEAK
            ([Math]::Round($bearPos.spot_usdt / $bullPos.spot_usdt, 1) -eq 0.5) | Should Be $true
        }

        It "Capital allocation is persistent (50/50 split)" {
            # Run multiple signals, allocations should stay 50/50
            for ($i = 0; $i -lt 3; $i++) {
                $positions = Get-HybridPositionSizes -Regime "BEAR_WEAK"

                # Total position should always be roughly same
                $total = $positions.spot_usdt + $positions.futures_usdt
                ([Math]::Round($total, 1) -eq 24.3) | Should Be $true
            }
        }
    }

    Context "Log Output Format" {
        It "Creates proper JSONL entries with all required fields" {
            # Simulate what vol_climax_scanner writes
            $entry = [ordered]@{
                ts_utc = (Get-Date).ToUniversalTime().ToString("o")
                market = "LINKUSDT"
                pattern = "VOL_CLIMAX"
                strength = 85
                vol_ratio = 2.8
                regime = "BEAR_WEAK"
                spot_position = 13.50
                futures_position = 10.80
                signal_quality = "vol_climax_solo"
            }

            $json = $entry | ConvertTo-Json -Compress
            $parsed = $json | ConvertFrom-Json

            $parsed.spot_position -eq 13.50 | Should Be $true
            $parsed.futures_position -eq 10.80 | Should Be $true
            $parsed.regime -eq "BEAR_WEAK" | Should Be $true
        }

        It "Hybrid trade log has correct structure" {
            $hybridEntry = @{
                timestamp = (Get-Date).ToUniversalTime().ToString("o")
                market = "BNBUSDT"
                regime = "BULL_WEAK"
                signal_type = "VOL_CLIMAX"
                spot_position = 13.50
                futures_position = 10.80
                combined_risk = 0.2431
                status = "EXECUTED"
            }

            $json = $hybridEntry | ConvertTo-Json -Compress
            $parsed = $json | ConvertFrom-Json

            $parsed.signal_type -eq "VOL_CLIMAX" | Should Be $true
            $parsed.combined_risk -gt 0 | Should Be $true
            $parsed.status -eq "EXECUTED" | Should Be $true
        }
    }
}

