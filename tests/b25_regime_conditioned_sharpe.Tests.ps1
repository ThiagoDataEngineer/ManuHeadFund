# b25_regime_conditioned_sharpe.Tests.ps1 -- B25 (2026-05-21 sessao extra).
# Pester 3.x. Anti-regression de B23 (default thresholds) + lockdown B25 (Phase-aware).

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_methodology_gates.ps1")


Describe "B25 - Regime-conditioned Sharpe ceiling" {

    It "Sem Phase: comportamento legacy preservado (red flag at 5.0)" {
        # B23 default: Sharpe 5.5 = red flag
        $r = Test-SharpeCeilingGate -Sharpe 5.5
        $r.passes | Should Be $false
        $r.zone | Should Be 'overfit_red_flag'
    }

    It "Sem Phase: Sharpe 4.5 = suspect zone (passa mas marked)" {
        $r = Test-SharpeCeilingGate -Sharpe 4.5
        $r.passes | Should Be $true
        $r.zone | Should Be 'suspect'
    }

    It "Phase=bull: thresholds bull (5.0/4.0) iguais a default" {
        $r5 = Test-SharpeCeilingGate -Sharpe 5.5 -Phase "phase_2_bull"
        $r5.zone | Should Be 'overfit_red_flag'
        $r4 = Test-SharpeCeilingGate -Sharpe 4.5 -Phase "phase_2_bull"
        $r4.zone | Should Be 'suspect'
    }

    It "Phase=bear: ceiling apertado (4.0) -- Sharpe 4.5 vira red flag" {
        # Bear regime sharpe_ceiling = 4.0
        $r = Test-SharpeCeilingGate -Sharpe 4.5 -Phase "phase_3_bear"
        $r.passes | Should Be $false
        $r.zone | Should Be 'overfit_red_flag'
    }

    It "Phase=bear: Sharpe 3.5 = suspect (threshold suspect=3.0 bear)" {
        $r = Test-SharpeCeilingGate -Sharpe 3.5 -Phase "phase_3_bear"
        $r.zone | Should Be 'suspect'
        $r.passes | Should Be $true
    }

    It "Phase=bear: Sharpe 2.5 = robust (acima 1.5 marginal)" {
        $r = Test-SharpeCeilingGate -Sharpe 2.5 -Phase "phase_3_bear"
        $r.zone | Should Be 'robust'
    }

    It "Phase=sideways: thresholds intermediarios (4.5/3.5)" {
        $r5 = Test-SharpeCeilingGate -Sharpe 5.0 -Phase "phase_1_sideways"
        $r5.zone | Should Be 'overfit_red_flag'  # 5 > 4.5 sideways ceiling
        $r35 = Test-SharpeCeilingGate -Sharpe 4.0 -Phase "phase_1_sideways"
        $r35.zone | Should Be 'suspect'           # 4 > 3.5 sideways suspect
    }

    It "Get-RegimeAwareThreshold tem entries sharpe_ceiling + sharpe_suspect" {
        $r = Get-RegimeAwareThreshold -Metric "sharpe_ceiling" -Phase "phase_3_bear"
        $r.threshold | Should Be 4.0
        $r2 = Get-RegimeAwareThreshold -Metric "sharpe_suspect" -Phase "phase_3_bear"
        $r2.threshold | Should Be 3.0
    }

    It "Phase invalido -> fallback bull (conservador)" {
        $r = Test-SharpeCeilingGate -Sharpe 5.5 -Phase "nonsense_phase"
        # 'default' branch retorna bull, so 5.5 > 5.0 = red flag
        $r.zone | Should Be 'overfit_red_flag'
    }
}


Describe "B25 - Empiric validation (PENDLE/CFG cases)" {

    It "PENDLE Sharpe 8.75 em phase_3_bear: red flag" {
        $r = Test-SharpeCeilingGate -Sharpe 8.75 -Phase "phase_3_bear"
        $r.passes | Should Be $false
        $r.zone | Should Be 'overfit_red_flag'
    }

    It "CFG Sharpe 8.48 em phase_3_bear: red flag" {
        $r = Test-SharpeCeilingGate -Sharpe 8.48 -Phase "phase_3_bear"
        $r.passes | Should Be $false
    }

    It "RENDER Sharpe ~3.3 em phase_3_bear: suspect (era robust no default)" {
        # Em bear regime, Sharpe 3.3 vai zona suspect (threshold suspect=3.0 bear).
        # Default seria robust (1.5-4 = robust).
        $r = Test-SharpeCeilingGate -Sharpe 3.3 -Phase "phase_3_bear"
        $r.zone | Should Be 'suspect'
    }

    It "ZEC Sharpe 2.5 em phase_3_bear: robust (acima 1.5 mas abaixo 3.0)" {
        $r = Test-SharpeCeilingGate -Sharpe 2.5 -Phase "phase_3_bear"
        $r.zone | Should Be 'robust'
    }
}
