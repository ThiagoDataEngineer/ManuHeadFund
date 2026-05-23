$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_beta_cap_per_phase.ps1")

Describe "Get-BetaCapForPhase" {
    It "h24_p1_bull returns cap 1.6 (bull amplifies)" {
        (Get-BetaCapForPhase -Phase "h24_p1_bull").block | Should Be 1.6
    }
    It "h24_p3_bear returns cap 1.4 (relaxed from 1.2)" {
        (Get-BetaCapForPhase -Phase "h24_p3_bear").block | Should Be 1.4
    }
    It "h24_p2_top returns cap 1.2 (conservador)" {
        (Get-BetaCapForPhase -Phase "h24_p2_top").block | Should Be 1.2
    }
    It "Unknown phase returns default 1.2 (current prod)" {
        $r = Get-BetaCapForPhase -Phase "unknown_phase"
        $r.block | Should Be 1.2
        $r.source | Should Be "default"
    }
    It "Empty phase returns default" {
        (Get-BetaCapForPhase).source | Should Be "default"
    }
}

Describe "Test-BetaWithinCap" {
    It "beta 0.9 phase bear: OK" {
        (Test-BetaWithinCap -Beta 0.9 -Phase "h24_p3_bear").level | Should Be "OK"
    }
    It "beta 1.3 phase bear: WARN (warn=1.1, block=1.4)" {
        (Test-BetaWithinCap -Beta 1.3 -Phase "h24_p3_bear").level | Should Be "WARN"
    }
    It "beta 1.5 phase bear: BLOCK" {
        (Test-BetaWithinCap -Beta 1.5 -Phase "h24_p3_bear").level | Should Be "BLOCK"
    }
    It "beta 1.5 phase bull: WARN (warn=1.3, block=1.6)" {
        (Test-BetaWithinCap -Beta 1.5 -Phase "h24_p1_bull").level | Should Be "WARN"
    }
    It "beta 1.5 phase bull NOT BLOCK (cap 1.6)" {
        (Test-BetaWithinCap -Beta 1.5 -Phase "h24_p1_bull").level | Should Not Be "BLOCK"
    }
    It "beta 1.7 phase bull: BLOCK" {
        (Test-BetaWithinCap -Beta 1.7 -Phase "h24_p1_bull").level | Should Be "BLOCK"
    }
    It "Strict mode: WARN treated as BLOCK" {
        (Test-BetaWithinCap -Beta 1.3 -Phase "h24_p3_bear" -Strict).level | Should Be "BLOCK"
    }
}

Describe "Get-AllPhaseCaps" {
    It "Returns 8 phases (h20+h24 x4 each)" {
        @(Get-AllPhaseCaps).Count | Should Be 8
    }
    It "All have valid warn < block" {
        foreach ($c in (Get-AllPhaseCaps)) {
            ($c.warn -lt $c.block) | Should Be $true
        }
    }
}

Describe "Property: cap monotonic with phase risk" {
    It "Bull cap >= bear cap (bull tolerates more)" {
        $bull = (Get-BetaCapForPhase -Phase "h24_p1_bull").block
        $bear = (Get-BetaCapForPhase -Phase "h24_p3_bear").block
        ($bull -ge $bear) | Should Be $true
    }
    It "Top cap <= bear cap (top mais conservador que bear sweet)" {
        $top = (Get-BetaCapForPhase -Phase "h24_p2_top").block
        $bear = (Get-BetaCapForPhase -Phase "h24_p3_bear").block
        ($top -le $bear) | Should Be $true
    }
}

Describe "Property: backward compat" {
    It "Default = atual prod 1.0/1.2 (no breaking change)" {
        $d = Get-BetaCapForPhase -Phase ""
        $d.warn | Should Be 1.0
        $d.block | Should Be 1.2
    }
}
