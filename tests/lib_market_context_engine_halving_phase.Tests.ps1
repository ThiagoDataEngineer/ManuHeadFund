# lib_market_context_engine_halving_phase.Tests.ps1 -- Pester 3.x
# Get-HalvingPhase: retorna categoria do ciclo halving (vs Get-HalvingFactor numerico)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\lib_market_context_engine.ps1"


Describe "Get-HalvingPhase - boundaries do halving 2024" {
    It "Pre-halving (Apr 2024 - 1d) retorna pre_halving" {
        $p = Get-HalvingPhase -DateBrt ([datetime]"2024-04-18")
        $p | Should Be "pre_halving"
    }

    It "Halving day + 1mes = phase_1_bull" {
        $p = Get-HalvingPhase -DateBrt ([datetime]"2024-05-19")
        $p | Should Be "phase_1_bull"
    }

    It "Halving + 11mes = phase_1_bull (final)" {
        $p = Get-HalvingPhase -DateBrt ([datetime]"2025-03-19")
        $p | Should Be "phase_1_bull"
    }

    It "Halving + 13mes = phase_2_top (start)" {
        $p = Get-HalvingPhase -DateBrt ([datetime]"2025-05-19")
        $p | Should Be "phase_2_top"
    }

    It "Halving + 17mes = phase_2_top (final)" {
        $p = Get-HalvingPhase -DateBrt ([datetime]"2025-09-19")
        $p | Should Be "phase_2_top"
    }

    It "Halving + 25mes = phase_3_bear (atual 2026-05)" {
        $p = Get-HalvingPhase -DateBrt ([datetime]"2026-05-19")
        $p | Should Be "phase_3_bear"
    }

    It "Halving + 32mes = phase_4_recovery" {
        $p = Get-HalvingPhase -DateBrt ([datetime]"2026-12-19")
        $p | Should Be "phase_4_recovery"
    }
}


Describe "Test-PhaseAllowsBullWeak - gate strict_v3" {
    It "phase_1_bull = ALLOW" {
        Test-PhaseAllowsBullWeak -Phase "phase_1_bull" | Should Be $true
    }

    It "phase_2_top = BLOCK (validado holdout 2025)" {
        Test-PhaseAllowsBullWeak -Phase "phase_2_top" | Should Be $false
    }

    It "phase_3_bear = false (dados insuficientes)" {
        Test-PhaseAllowsBullWeak -Phase "phase_3_bear" | Should Be $false
    }

    It "phase_4_recovery = ALLOW reduzido" {
        Test-PhaseAllowsBullWeak -Phase "phase_4_recovery" | Should Be $true
    }
}
