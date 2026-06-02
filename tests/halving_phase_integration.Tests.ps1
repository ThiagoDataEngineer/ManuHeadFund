# halving_phase_integration.Tests.ps1 -- Testa carregamento na ordem de scan_master.ps1

Describe "Halving Phase Integration Order" {
    BeforeAll {
        $projectRoot = Split-Path $PSScriptRoot -Parent
        $agentsDir = Join-Path $projectRoot "agents"
        $scriptDir = Join-Path $projectRoot "scripts"
    }

    It "scan_master.ps1 carrega libs na ordem correta (context antes de engine)" {
        $content = Get-Content (Join-Path $scriptDir "scan_master.ps1") -Raw

        # Verifica que market_context vem ANTES de market_context_engine
        $idx1 = $content.IndexOf("lib_market_context.ps1")
        $idx2 = $content.IndexOf("lib_market_context_engine.ps1")

        ($idx1 -gt -1) | Should Be $true
        ($idx2 -gt -1) | Should Be $true
        ($idx1 -lt $idx2) | Should Be $true
    }

    It "lib_market_context.ps1 nao define Get-HalvingPhase" {
        $content = Get-Content (Join-Path $agentsDir "lib_market_context.ps1") -Raw
        ($content -match "function Get-HalvingPhase") | Should Be $false
    }

    It "lib_market_context_engine.ps1 define Get-HalvingPhase com DateBrt obrigatorio" {
        $content = Get-Content (Join-Path $agentsDir "lib_market_context_engine.ps1") -Raw
        $content -match "function Get-HalvingPhase" | Should Be $true
        $content -match "DateBrt" | Should Be $true
    }

    It "lib_halving_phase_alert.ps1 chama Get-HalvingPhase com -DateBrt" {
        $content = Get-Content (Join-Path $agentsDir "lib_halving_phase_alert.ps1") -Raw
        $content -match "Get-HalvingPhase -DateBrt" | Should Be $true
    }

    It "orchestrator_parallel.ps1 carrega libs na ordem correta" {
        $content = Get-Content (Join-Path $agentsDir "lib_orchestrator_parallel.ps1") -Raw

        # Verifica que market_context vem ANTES de market_context_engine
        $idx1 = $content.IndexOf('lib_market_context.ps1')
        $idx2 = $content.IndexOf('lib_market_context_engine.ps1')

        ($idx1 -gt -1) | Should Be $true
        ($idx2 -gt -1) | Should Be $true
        ($idx1 -lt $idx2) | Should Be $true
    }
}
