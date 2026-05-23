# scanner_score_clamp_override.Tests.ps1 -- Pester 3.x
# EUREKA B (2026-05-15): Get-QuickTechScore clamp em 65 torna Tier A
# matematicamente impossivel (precisa >=75). Override OPT-IN segue padrao TopN.
#
# Contrato:
#   - Sem $global:SCANNER_SCORE_CLAMP_OVERRIDE: clamp = 65 (regression default)
#   - Override valido (1..100): clamp = override
#   - Override invalido (<=0, negativo, nao numerico): fallback default 65
#   - Override > 100: cap em 100 (score eh 0-100 por definicao)
#
# Vide journal/diagnose_triagem_tier_d_2026_05_15.md secao "EUREKA B".

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir  = Join-Path (Split-Path $here -Parent) 'agents'
$scannerPs1 = Join-Path $agentsDir 'scanner.ps1'

# Extrai apenas Get-ScoreClamp (funcao pura, sem dependencias) sem rodar scanner inteiro.
$scannerContent = Get-Content -Raw -Path $scannerPs1
if ($scannerContent -match '(?ms)(^function Get-ScoreClamp\s*\{.*?^\})') {
    Invoke-Expression $Matches[1]
}

function Reset-ClampOverride {
    if (Test-Path variable:global:SCANNER_SCORE_CLAMP_OVERRIDE) {
        Remove-Variable -Name SCANNER_SCORE_CLAMP_OVERRIDE -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe "Get-ScoreClamp - override OPT-IN para scanner score (EUREKA B)" {

    BeforeEach { Reset-ClampOverride }
    AfterEach  { Reset-ClampOverride }

    It "Sem override (variavel nao setada): clamp permanece 65 (regression)" {
        Reset-ClampOverride
        (Get-ScoreClamp -Default 65) | Should Be 65
    }

    It "Com override = 85 (calibracao recomendada): clamp = 85" {
        $global:SCANNER_SCORE_CLAMP_OVERRIDE = 85
        (Get-ScoreClamp -Default 65) | Should Be 85
    }

    It "Com override = 100 (cap maximo): clamp = 100" {
        $global:SCANNER_SCORE_CLAMP_OVERRIDE = 100
        (Get-ScoreClamp -Default 65) | Should Be 100
    }

    It "Com override = 0 (invalido): cai pro default 65" {
        $global:SCANNER_SCORE_CLAMP_OVERRIDE = 0
        (Get-ScoreClamp -Default 65) | Should Be 65
    }

    It "Com override = -1 (negativo invalido): cai pro default 65" {
        $global:SCANNER_SCORE_CLAMP_OVERRIDE = -1
        (Get-ScoreClamp -Default 65) | Should Be 65
    }

    It "Com override = 150 (> 100): cap em 100 (sanity)" {
        $global:SCANNER_SCORE_CLAMP_OVERRIDE = 150
        (Get-ScoreClamp -Default 65) | Should Be 100
    }

    It "Com override = 'abc' (nao numerico): cai pro default 65" {
        $global:SCANNER_SCORE_CLAMP_OVERRIDE = "abc"
        (Get-ScoreClamp -Default 65) | Should Be 65
    }

    It "Default custom: -Default 70 sem override retorna 70" {
        Reset-ClampOverride
        (Get-ScoreClamp -Default 70) | Should Be 70
    }
}
