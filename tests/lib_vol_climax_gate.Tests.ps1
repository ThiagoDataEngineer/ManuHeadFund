param([string] $ModulePath = "$PSScriptRoot\..\agents")

Describe "lib_vol_climax_gate — SHORT signal detection" {
    . "$ModulePath\lib_vol_climax_gate.ps1"

    Context "Test-VolClimaxGate logic" {
        It "passes when all 3 gates are true (RSI 82, vol 2.6x, ADX 68)" {
            $result = Test-VolClimaxGate -RSI 82 -CurrentVolume 260000 -Avg3dVolume 100000 -ADX 68
            $result.passes | Should Be $true
            $result.rsi_pass | Should Be $true
            $result.vol_pass | Should Be $true
            $result.adx_pass | Should Be $true
        }

        It "fails when RSI abaixo de 80 (not extreme)" {
            $result = Test-VolClimaxGate -RSI 75 -CurrentVolume 260000 -Avg3dVolume 100000 -ADX 68
            $result.passes | Should Be $false
            $result.rsi_pass | Should Be $false
        }

        It "fails when vol abaixo de 2.5x (no panic)" {
            $result = Test-VolClimaxGate -RSI 82 -CurrentVolume 200000 -Avg3dVolume 100000 -ADX 68
            $result.passes | Should Be $false
            $result.vol_pass | Should Be $false
        }

        It "fails when ADX ate 60 (no trend)" {
            $result = Test-VolClimaxGate -RSI 82 -CurrentVolume 260000 -Avg3dVolume 100000 -ADX 58
            $result.passes | Should Be $false
            $result.adx_pass | Should Be $false
        }

        It "calculates vol_ratio correctly (2.60)" {
            $result = Test-VolClimaxGate -RSI 82 -CurrentVolume 260000 -Avg3dVolume 100000 -ADX 68
            $result.vol_ratio | Should Be 2.60
        }
    }

    Context "Add-VolClimaxObservation logging" {
        BeforeEach {
            $testPath = "$env:TEMP\vol_climax_test.jsonl"
            if (Test-Path $testPath) { Remove-Item $testPath -Force }
        }

        AfterEach {
            if (Test-Path $testPath) { Remove-Item $testPath -Force }
        }

        It "creates file if not exists" {
            $gateResult = Test-VolClimaxGate -RSI 82 -CurrentVolume 260000 -Avg3dVolume 100000 -ADX 68
            Add-VolClimaxObservation -Path $testPath -Market "BTCUSDT" -GateResult $gateResult -Regime "BEAR_WEAK"
            Test-Path $testPath | Should Be $true
        }

        It "logs entry with correct schema" {
            $gateResult = Test-VolClimaxGate -RSI 82 -CurrentVolume 260000 -Avg3dVolume 100000 -ADX 68
            $entry = Add-VolClimaxObservation -Path $testPath -Market "ETHUSDT" -GateResult $gateResult -Regime "BEAR_WEAK"

            $entry.market | Should Be "ETHUSDT"
            $entry.signal_type | Should Be "vol_climax"
            $entry.rsi | Should Be 82
            $entry.vol_ratio | Should Be 2.60
            $entry.adx | Should Be 68
            $entry.regime | Should Be "BEAR_WEAK"
        }

        It "appends multiple entries" {
            $gateResult1 = Test-VolClimaxGate -RSI 82 -CurrentVolume 260000 -Avg3dVolume 100000 -ADX 68
            $gateResult2 = Test-VolClimaxGate -RSI 85 -CurrentVolume 300000 -Avg3dVolume 100000 -ADX 72

            Add-VolClimaxObservation -Path $testPath -Market "BTCUSDT" -GateResult $gateResult1 -Regime "BEAR_WEAK"
            Add-VolClimaxObservation -Path $testPath -Market "ETHUSDT" -GateResult $gateResult2 -Regime "BEAR_WEAK"

            $lines = @(Get-Content $testPath)
            $lines.Count | Should Be 2
        }

        It "includes timestamp in ISO format" {
            $gateResult = Test-VolClimaxGate -RSI 82 -CurrentVolume 260000 -Avg3dVolume 100000 -ADX 68
            $entry = Add-VolClimaxObservation -Path $testPath -Market "BTCUSDT" -GateResult $gateResult -Regime "BEAR_WEAK"

            $entry.ts | Should Match "^\d{4}-\d{2}-\d{2}T"
        }
    }

    Context "Integration: gate + logging" {
        BeforeEach {
            $testPath = "$env:TEMP\vol_climax_integration_test.jsonl"
            if (Test-Path $testPath) { Remove-Item $testPath -Force }
        }

        AfterEach {
            if (Test-Path $testPath) { Remove-Item $testPath -Force }
        }

        It "logs signal only when gate passes" {
            $passResult = Test-VolClimaxGate -RSI 82 -CurrentVolume 260000 -Avg3dVolume 100000 -ADX 68
            $failResult = Test-VolClimaxGate -RSI 75 -CurrentVolume 260000 -Avg3dVolume 100000 -ADX 68

            if ($passResult.passes) {
                Add-VolClimaxObservation -Path $testPath -Market "PASS" -GateResult $passResult -Regime "BEAR_WEAK"
            }

            if ($failResult.passes) {
                Add-VolClimaxObservation -Path $testPath -Market "FAIL" -GateResult $failResult -Regime "BEAR_WEAK"
            }

            $lines = @(Get-Content $testPath)
            $lines.Count | Should Be 1
            $lines[0] | Should Match "PASS"
        }
    }
}
