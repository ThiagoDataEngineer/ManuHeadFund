# B23 fix 2026-05-20 PM6+520min: Sharpe ceiling + pump-after-discovery gates.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_methodology_gates.ps1")

Describe "B23 Test-SharpeCeilingGate" {
    It "Sharpe 2.5: PASS robust" {
        $r = Test-SharpeCeilingGate -Sharpe 2.5
        $r.passes | Should Be $true
        $r.zone   | Should Be "robust"
    }
    It "Sharpe 4.0: PASS robust" {
        $r = Test-SharpeCeilingGate -Sharpe 4.0
        $r.passes | Should Be $true
        $r.zone   | Should Be "robust"
    }
    It "Sharpe 4.5: PASS suspect (zona 4-5)" {
        $r = Test-SharpeCeilingGate -Sharpe 4.5
        $r.passes | Should Be $true
        $r.zone   | Should Be "suspect"
    }
    It "Sharpe 8.75 (PENDLE real): BLOCK red flag" {
        $r = Test-SharpeCeilingGate -Sharpe 8.75
        $r.passes | Should Be $false
        $r.zone   | Should Be "overfit_red_flag"
    }
    It "Sharpe 8.48 (CFG real): BLOCK red flag" {
        $r = Test-SharpeCeilingGate -Sharpe 8.48
        $r.passes | Should Be $false
    }
    It "Sharpe negativo: BLOCK no_edge" {
        $r = Test-SharpeCeilingGate -Sharpe -0.5
        $r.passes | Should Be $false
        $r.zone   | Should Be "no_edge"
    }
    It "Sharpe 1.0: PASS marginal" {
        $r = Test-SharpeCeilingGate -Sharpe 1.0
        $r.passes | Should Be $true
        $r.zone   | Should Be "marginal"
    }
}

Describe "B23 Test-PumpAfterDiscoveryGate" {
    It "mom_20d 5pct: PASS ok" {
        $r = Test-PumpAfterDiscoveryGate -Mom20dPct 5
        $r.passes | Should Be $true
        $r.zone   | Should Be "ok"
    }
    It "mom_20d 20pct: PASS warn" {
        $r = Test-PumpAfterDiscoveryGate -Mom20dPct 20
        $r.passes | Should Be $true
        $r.zone   | Should Be "warn"
    }
    It "mom_20d 33pct (PENDLE real): BLOCK chase_trap" {
        $r = Test-PumpAfterDiscoveryGate -Mom20dPct 33
        $r.passes | Should Be $false
        $r.zone   | Should Be "chase_trap"
    }
    It "mom_20d 50pct: BLOCK absoluto" {
        $r = Test-PumpAfterDiscoveryGate -Mom20dPct 50
        $r.passes | Should Be $false
    }
    It "mom_20d -10pct: PASS pullback nao eh chase" {
        $r = Test-PumpAfterDiscoveryGate -Mom20dPct -10
        $r.passes | Should Be $true
    }
}
