# daily_cycle_mode.Tests.ps1 -- TDD DAILY_CYCLE_MODE override
# Pester 3.x, sem acentos.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_seasonality.ps1")

Describe "DAILY_CYCLE_MODE override" {

    BeforeEach {
        $global:DAILY_CYCLE_MODE = $false
    }

    It "default off: window e scanIntervalMin seguem horario" {
        $global:DAILY_CYCLE_MODE = $false
        $s = Get-SeasonalityContext
        $s.window | Should Not Be "DAILY"
        ($s.scanIntervalMin -in @(15, 30, 60, 120)) | Should Be $true
    }

    It "ativado: forca window=DAILY e scanIntervalMin=1440" {
        $global:DAILY_CYCLE_MODE = $true
        $s = Get-SeasonalityContext
        $s.window | Should Be "DAILY"
        $s.scanIntervalMin | Should Be 1440
    }

    It "ativado: scoreAdjustment zero (nao penaliza)" {
        $global:DAILY_CYCLE_MODE = $true
        $s = Get-SeasonalityContext
        $s.scoreAdjustment | Should Be 0
    }

    It "desativado depois de ativado: volta ao normal" {
        $global:DAILY_CYCLE_MODE = $true
        $s1 = Get-SeasonalityContext
        $global:DAILY_CYCLE_MODE = $false
        $s2 = Get-SeasonalityContext
        $s1.window | Should Be "DAILY"
        $s2.window | Should Not Be "DAILY"
    }
}
