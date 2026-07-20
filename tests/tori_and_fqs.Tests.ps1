Describe "Tori Logic + FQS Default (Blocker #4 + #5 Fix)" {

    BeforeAll {
        . (Join-Path $PSScriptRoot "..\agents\lib_tori_simplified.ps1")
        . (Join-Path $PSScriptRoot "..\agents\lib_fqs_default_quality.ps1")
    }

    Context "Tori Requirement Clarity (Blocker #4)" {
        It "Should mark Tori OPTIONAL for elite mesa 75+" {
            $result = Get-ToriRequirement -MesaScore 84
            $result.required | Should -Be $false
            $result.allows_skip | Should -Be $true
        }

        It "Should mark Tori REQUIRED but less strict for strong mesa 60-75" {
            $result = Get-ToriRequirement -MesaScore 70
            $result.required | Should -Be $true
            $result.allows_skip | Should -Be $false  # SKIP still blocks
            $result.allows_wait | Should -Be $true   # WAIT is ok
        }

        It "Should mark Tori STRICTLY REQUIRED for normal mesa <60" {
            $result = Get-ToriRequirement -MesaScore 50
            $result.required | Should -Be $true
            $result.allows_skip | Should -Be $false
            $result.allows_wait | Should -Be $false  # WAIT also blocks
        }
    }

    Context "Tori Signal Consistency (Blocker #4)" {
        It "Should PASS ENTER signal always" {
            # ENTER always ok regardless of mesa
            $r1 = Test-ToriGateConsistent -MesaScore 40 -ToriSignal "ENTER"
            $r1.pass | Should -Be $true

            $r2 = Test-ToriGateConsistent -MesaScore 80 -ToriSignal "ENTER"
            $r2.pass | Should -Be $true
        }

        It "Should PASS SKIP for elite mesa 75+" {
            # Elite mesa can proceed even if Tori says SKIP
            $result = Test-ToriGateConsistent -MesaScore 84 -ToriSignal "SKIP"
            $result.pass | Should -Be $true
        }

        It "Should FAIL SKIP for normal mesa <60" {
            # TRUMPUSDT error: entered with Tori SKIP + mesa probably <70
            $result = Test-ToriGateConsistent -MesaScore 50 -ToriSignal "SKIP"
            $result.pass | Should -Be $false
        }

        It "Should FAIL WAIT for normal mesa <60" {
            $result = Test-ToriGateConsistent -MesaScore 45 -ToriSignal "WAIT"
            $result.pass | Should -Be $false
        }
    }

    Context "FQS Default Quality (Blocker #5)" {
        It "Should return FQS value when present" {
            $gem = @{ market = "TEST"; fqs = 6 }
            $result = Get-FqsQualityOrDefault -Gem $gem
            $result | Should -Be 6
        }

        It "Should return default 4 when FQS missing" {
            $gem = @{ market = "TEST" }  # No fqs field
            $result = Get-FqsQualityOrDefault -Gem $gem
            $result | Should -Be 4
        }

        It "Should return default 4 when FQS null/empty" {
            $gem1 = @{ market = "TEST"; fqs = $null }
            $result1 = Get-FqsQualityOrDefault -Gem $gem1
            $result1 | Should -Be 4

            $gem2 = @{ market = "TEST"; fqs = "" }
            $result2 = Get-FqsQualityOrDefault -Gem $gem2
            $result2 | Should -Be 4
        }
    }

    Context "FQS Gate Passes with Default (Blocker #5)" {
        It "Should PASS when FQS missing but mesa elite 75+" {
            # Before: rejected (no FQS)
            # After: passes (default 4 acceptable for elite mesa)
            $gem = @{ market = "BIOUSDT"; mesa_score = 70 }
            $result = Test-FqsGatePassesWithDefault -Gem $gem -MesaScore 70
            $result.pass | Should -Be $true
            $result.is_default | Should -Be $true
        }

        It "Should use lower minimum for elite mesa" {
            $gem = @{ market = "TEST" }
            $result = Test-FqsGatePassesWithDefault -Gem $gem -MesaScore 80 -MinQualityRequired 4
            $result.min_required | Should -BeLessThan 4  # Lowered for elite
        }

        It "Should use higher minimum for weak mesa" {
            $gem = @{ market = "TEST" }
            $result = Test-FqsGatePassesWithDefault -Gem $gem -MesaScore 45 -MinQualityRequired 4
            $result.min_required | Should -BeGreaterThan 4  # Raised for weak
        }
    }

    Context "Blocker Evidence: Lost Gems Now Pass" {
        It "BIOUSDT (score 70, FQS missing) should now pass" {
            $gem = @{ market = "BIOUSDT"; mesa_score = 70 }
            $result = Test-FqsGatePassesWithDefault -Gem $gem -MesaScore 70
            $result.pass | Should -Be $true  # Before: FAIL (FQS missing)
        }

        It "TRUMPUSDT-like (Tori SKIP, mesa 50) should now FAIL properly" {
            # Before: passed (unclear gate logic) → loss
            # After: fails clearly (Tori SKIP + mesa 50 = required to pass Tori)
            $result = Test-ToriGateConsistent -MesaScore 50 -ToriSignal "SKIP"
            $result.pass | Should -Be $false
        }
    }
}
