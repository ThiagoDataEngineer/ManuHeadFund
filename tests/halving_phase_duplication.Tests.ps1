# halving_phase_duplication.Tests.ps1 -- Valida remocao segura de Get-HalvingPhase duplicado

Describe "Halving Phase Deduplication Safety" {
    BeforeAll {
        # PSScriptRoot = tests dir, precisa subir 1 nivel
        $projectRoot = Split-Path $PSScriptRoot -Parent
        $agentsDir = Join-Path $projectRoot "agents"

        # Carrega na ordem certa (igual a scan_master.ps1)
        $enginePath = Join-Path $agentsDir "lib_market_context_engine.ps1"
        $alertPath = Join-Path $agentsDir "lib_halving_phase_alert.ps1"

        if (-not (Test-Path $enginePath)) { throw "Missing: $enginePath" }
        if (-not (Test-Path $alertPath)) { throw "Missing: $alertPath" }
    }

    It "lib_market_context_engine.ps1 tem Get-HalvingPhase com forma simples (string)" {
        $content = Get-Content (Join-Path $projectRoot "agents" "lib_market_context_engine.ps1") -Raw
        $content -match "function Get-HalvingPhase" | Should Be $true
        $content -match 'return "phase_1_bull"' | Should Be $true
        $content -match 'return "phase_2_top"' | Should Be $true
        $content -match 'return "phase_3_bear"' | Should Be $true
    }

    It "lib_halving_phase_alert.ps1 existe e chama Get-HalvingPhase corretamente" {
        $content = Get-Content (Join-Path $projectRoot "agents" "lib_halving_phase_alert.ps1") -Raw
        $content -match "Get-HalvingPhase -DateBrt" | Should Be $true
    }

    It "POST-FIX: lib_market_context.ps1 NAO tem Get-HalvingPhase (apos remocao)" {
        $content = Get-Content (Join-Path $projectRoot "agents" "lib_market_context.ps1") -Raw
        ($content -match "function Get-HalvingPhase") | Should Be $false
    }

    It "POST-FIX: lib_market_context_engine.ps1 permanece intacto apos fix" {
        $content = Get-Content (Join-Path $projectRoot "agents" "lib_market_context_engine.ps1") -Raw
        $content -match "function Get-HalvingPhase" | Should Be $true
        $content -match 'return "phase_1_bull"' | Should Be $true
    }
}
