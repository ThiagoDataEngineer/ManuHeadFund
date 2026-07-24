# Integration test: vol_climax_scanner with lib_hybrid_orchestrator
#
# 2026-07-23 FIX: reescrito -- mesmo problema de lib_hybrid_orchestrator.Tests.ps1
# (fix commit d7fade0): Execute-HybridSignal e Get-HybridPositionSizes
# nunca existiram na lib real (sao Execute-DynamicSignal e Get-PositionSize),
# e o capital hardcoded de $1350 e antigo -- fallback real hoje e $2425.33
# SPOT / $2718.49 FUTURES. Testes agora calculam a partir do capital real
# via Get-DynamicCapital, sem valores chumbados desatualizados.

Describe "Vol Climax Scanner Hybrid Integration" {
    BeforeAll {
        $root = Get-Location
        . (Join-Path $root "agents\lib_hybrid_orchestrator.ps1")
        . (Join-Path $root "agents\lib_regime_position_sizing.ps1")
        . (Join-Path $root "agents\lib_signal_combo.ps1")
        $script:RealCapital = Get-DynamicCapital
    }

    Context "Hybrid Orchestrator Integration" {
        It "Loads lib_hybrid_orchestrator successfully" {
            (Get-Command Execute-DynamicSignal -ErrorAction SilentlyContinue) -ne $null | Should Be $true
        }

        It "Gets position sizes for BEAR_WEAK regime" {
            $spot = Get-PositionSize -Market "SPOT" -Regime "BEAR_WEAK"
            $futures = Get-PositionSize -Market "FUTURES" -Regime "BEAR_WEAK"
            $spot.position_usdt -gt 0 | Should Be $true
            $futures.position_usdt -gt 0 | Should Be $true
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

            $result = Execute-DynamicSignal -Signal $signal -Regime "BEAR_WEAK"

            $result -ne $null | Should Be $true
            $result.trades.Count -gt 0 | Should Be $true
            $result.total_risk -gt 0 | Should Be $true
        }

        It "SPOT position is 1% do capital SPOT real" {
            $spot = Get-PositionSize -Market "SPOT" -Regime "BEAR_WEAK"
            $expected = [Math]::Round($script:RealCapital.spot_capital * 0.01, 2)
            ($spot.position_usdt -eq $expected) | Should Be $true
        }

        It "FUTURES position e 1% do capital FUTURES real" {
            $futures = Get-PositionSize -Market "FUTURES" -Regime "BEAR_WEAK"
            $expected = [Math]::Round($script:RealCapital.futures_capital * 0.01, 2)
            ($futures.position_usdt -eq $expected) | Should Be $true
        }

        It "Both positions respect hard cap (3% em BULL_STRONG, 1% nos demais)" {
            foreach ($regime in @("BULL_STRONG", "BULL_WEAK", "BEAR_WEAK", "BEAR_STRONG")) {
                $spot = Get-PositionSize -Market "SPOT" -Regime $regime
                $futures = Get-PositionSize -Market "FUTURES" -Regime $regime

                $maxPct = if ($regime -eq "BULL_STRONG") { 3.0 } else { 1.0 }
                ($spot.position_pct -le $maxPct) | Should Be $true
                ($futures.position_pct -le $maxPct) | Should Be $true
            }
        }

        It "Supports all 4 regimes sem erro" {
            $regimes = @("BULL_STRONG", "BULL_WEAK", "BEAR_WEAK", "BEAR_STRONG")

            foreach ($regime in $regimes) {
                $signal = @{
                    market = "XRPUSDT"
                    type = "VOL_CLIMAX"
                    entry_price = 2.5
                    stop_loss_pct = 0.01
                }

                { Execute-DynamicSignal -Signal $signal -Regime $regime } | Should Not Throw
            }
        }

        It "Regime filter reduz posicao em BEAR_STRONG pela metade" {
            $bullPos = Get-PositionSize -Market "SPOT" -Regime "BULL_WEAK"
            $bearPos = Get-PositionSize -Market "SPOT" -Regime "BEAR_STRONG"

            $diff = [Math]::Abs($bearPos.position_usdt - ($bullPos.position_usdt * 0.5))
            ($diff -le 0.02) | Should Be $true
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
