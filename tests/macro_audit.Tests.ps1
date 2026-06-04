# macro_audit.Tests.ps1 -- Pester tests para lib_macro_audit.ps1
# Pester 3.x compativel
$ErrorActionPreference = 'Stop'
$root   = Split-Path -Parent $PSScriptRoot
$libPath = Join-Path $root "agents\lib_macro_audit.ps1"
. $libPath

Describe "Test-AdaptiveWeightsRotation" {

    It "retorna objeto com propriedades obrigatorias" {
        $r = Test-AdaptiveWeightsRotation -OrchestratorPath (Join-Path $root "agents\orchestrator_v6.ps1")
        $r | Should Not Be $null
        $r.PSObject.Properties.Name -contains 'adaptive_active' | Should Be $true
        $r.PSObject.Properties.Name -contains 'weights_by_regime' | Should Be $true
        $r.PSObject.Properties.Name -contains 'currently_using' | Should Be $true
        $r.PSObject.Properties.Name -contains 'rotation_evidence' | Should Be $true
    }

    It "carrega pesos BULL/NEUTRAL/BEAR do config.ps1" {
        $r = Test-AdaptiveWeightsRotation -OrchestratorPath (Join-Path $root "agents\orchestrator_v6.ps1")
        $r.weights_by_regime.BULL    | Should Not Be $null
        $r.weights_by_regime.NEUTRAL | Should Not Be $null
        $r.weights_by_regime.BEAR    | Should Not Be $null
        $r.weights_by_regime.BULL.Tech | Should Not Be $null
    }

    It "detecta que pesos DIFEREM entre BULL e BEAR" {
        $r = Test-AdaptiveWeightsRotation -OrchestratorPath (Join-Path $root "agents\orchestrator_v6.ps1")
        $r.weights_actually_differ | Should Be $true
    }

    It "detecta switch por macro_bias no orchestrator" {
        $r = Test-AdaptiveWeightsRotation -OrchestratorPath (Join-Path $root "agents\orchestrator_v6.ps1")
        $r.has_regime_switch | Should Be $true
    }

    It "encontra ao menos 4 evidencias de uso real (`$w.X *)" {
        $r = Test-AdaptiveWeightsRotation -OrchestratorPath (Join-Path $root "agents\orchestrator_v6.ps1")
        $r.evidence_count | Should BeGreaterThan 3
    }

    It "veredito final = ROTATION_ACTIVE quando todas condicoes presentes" {
        $r = Test-AdaptiveWeightsRotation -OrchestratorPath (Join-Path $root "agents\orchestrator_v6.ps1")
        $r.adaptive_active | Should Be $true
        $r.verdict | Should Match 'ROTATION_ACTIVE'
    }

    It "respeita ForceMacroBias para testar diferentes regimes" {
        $r = Test-AdaptiveWeightsRotation -ForceMacroBias 'BULLISH'
        $r.currently_using | Should Be 'BULL'

        $r2 = Test-AdaptiveWeightsRotation -ForceMacroBias 'BEARISH'
        $r2.currently_using | Should Be 'BEAR'
    }
}

Describe "Get-AdaptiveWeightsReport" {
    It "gera markdown com veredito" {
        $audit = Test-AdaptiveWeightsRotation -OrchestratorPath (Join-Path $root "agents\orchestrator_v6.ps1")
        $md = Get-AdaptiveWeightsReport -AuditResult $audit
        $md | Should Match 'Audit Pesos Adaptativos'
        $md | Should Match 'Veredito:'
    }
}
