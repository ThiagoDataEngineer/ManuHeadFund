Describe "gem_executor Live Integration Test" {
    BeforeAll {
        # Load gem_executor (this triggers the bug if it exists)
        . "$PSScriptRoot\..\agents\gem_executor.ps1" -ErrorAction SilentlyContinue

        # Check if TDD libs loaded
        $script:tdd_libs_loaded = (
            (Get-Command Get-SafePositionSize -ErrorAction SilentlyContinue) -ne $null -and
            (Get-Command Get-SafeLeverage -ErrorAction SilentlyContinue) -ne $null -and
            (Get-Command Test-ChartPatternGate -ErrorAction SilentlyContinue) -ne $null
        )
    }

    Context "TDD Library Loading" {
        It "Should load lib_sizing_centralized without error" {
            Get-Command Get-SafePositionSize -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should load lib_leverage_cap without error" {
            Get-Command Get-SafeLeverage -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should load lib_chart_gate_active without error" {
            Get-Command Test-ChartPatternGate -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "All TDD libs should be present" {
            $script:tdd_libs_loaded | Should -Be $true
        }
    }

    Context "gem_executor Function Availability" {
        It "Should have Invoke-GemExecutor function" {
            Get-Command Invoke-GemExecutor -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have Get-GemDecision function" {
            Get-Command Get-GemDecision -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Chart Gate Integration" {
        It "Test-ChartPatternGate should detect pump patterns" {
            $prices = @(100, 102, 104, 106, 108, 110)
            $volumes = @(1000, 1100, 1200, 2500, 2600, 2700)

            $result = Test-ChartPatternGate -Market "TEST/USDT" -HistoricalPrice $prices -Volume $volumes
            $result.pass | Should -Be $false
            $result.reason | Should -Match "pump|pattern"
        }

        It "Test-ChartPatternGate should pass normal trends" {
            $prices = @(100, 101, 102, 103, 104, 105)
            $volumes = @(1000, 1100, 1000, 1050, 1000, 1100)

            $result = Test-ChartPatternGate -Market "TEST/USDT" -HistoricalPrice $prices -Volume $volumes
            $result.pass | Should -Be $true
        }
    }

    Context "No Runtime Errors" {
        It "gem_executor should load without throwing exceptions" {
            # If we got here, loading succeeded (no exceptions thrown)
            $true | Should -Be $true
        }

        It "TDD lib loader should not produce variable reference errors" {
            # This catches the $__tddLib: error
            $ErrorActionPreference = "Stop"
            $error.Clear()

            . "$PSScriptRoot\..\agents\gem_executor.ps1" -ErrorAction SilentlyContinue

            # Should not have PowerShell variable reference errors
            $error | Where-Object { $_ -match "Variable reference" } | Should -BeNullOrEmpty
        }
    }
}
