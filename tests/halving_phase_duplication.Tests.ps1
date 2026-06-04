# halving_phase_duplication.Tests.ps1 -- Valida remocao segura de Get-HalvingPhase duplicado
# Pester 3.x / PS 5.1 compatible: sem BeforeAll + sem Join-Path 3-args

$script:projectRoot = Split-Path $PSScriptRoot -Parent
$script:agentsDir   = Join-Path $script:projectRoot "agents"

Describe "Halving Phase Deduplication Safety" {

    It "lib_market_context_engine.ps1 tem Get-HalvingPhase com forma simples (string)" {
        $path = Join-Path $script:agentsDir "lib_market_context_engine.ps1"
        $content = Get-Content $path -Raw
        ($content -match "function Get-HalvingPhase") | Should Be $true
        ($content -match 'return "phase_1_bull"') | Should Be $true
        ($content -match 'return "phase_2_top"')  | Should Be $true
        ($content -match 'return "phase_3_bear"') | Should Be $true
    }

    It "lib_halving_phase_alert.ps1 existe e chama Get-HalvingPhase corretamente" {
        $path = Join-Path $script:agentsDir "lib_halving_phase_alert.ps1"
        (Test-Path $path) | Should Be $true
        $content = Get-Content $path -Raw
        ($content -match "Get-HalvingPhase") | Should Be $true
    }

    It "POST-FIX: lib_market_context.ps1 NAO tem Get-HalvingPhase (apos remocao)" {
        $path = Join-Path $script:agentsDir "lib_market_context.ps1"
        $content = Get-Content $path -Raw
        ($content -match "function Get-HalvingPhase") | Should Be $false
    }

    It "POST-FIX: lib_market_context_engine.ps1 permanece intacto apos fix" {
        $path = Join-Path $script:agentsDir "lib_market_context_engine.ps1"
        $content = Get-Content $path -Raw
        ($content -match "function Get-HalvingPhase") | Should Be $true
        ($content -match 'return "phase_1_bull"')     | Should Be $true
    }
}
