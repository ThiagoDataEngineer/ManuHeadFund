# dsr_global.Tests.ps1 -- TDD lib_dsr_global.ps1
# Pester 3.x. Multi-testing penalty Bailey-LdP.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_dsr_global.ps1")

$testDir = Join-Path $env:TEMP ("dsr_test_" + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
$testJson = Join-Path $testDir "dsr_global.json"

Describe "DSR Global Registry" {

    It "Get-DsrTrials retorna 0 quando registry nao existe" {
        $n = Get-DsrTrials -Path $testJson
        $n | Should Be 0
    }

    It "Add-DsrTrial incrementa de 0 para 1" {
        Add-DsrTrial -Path $testJson -GateName "obs_to_c" -Market "PENDLEUSDT" | Out-Null
        (Get-DsrTrials -Path $testJson) | Should Be 1
    }

    It "Add-DsrTrial 3x acumula para 4 (somando o anterior)" {
        Add-DsrTrial -Path $testJson -GateName "obs_to_c" -Market "X" | Out-Null
        Add-DsrTrial -Path $testJson -GateName "c_to_b" -Market "Y" | Out-Null
        Add-DsrTrial -Path $testJson -GateName "b_to_a" -Market "Z" | Out-Null
        (Get-DsrTrials -Path $testJson) | Should Be 4
    }

    It "Persistencia: novo Get-DsrTrials reflete count salvo" {
        $n = Get-DsrTrials -Path $testJson
        $n | Should Be 4
        $exists = Test-Path $testJson
        $exists | Should Be $true
    }

    It "Get-DsrAdjustedThreshold infla com N trials (multi-testing penalty)" {
        $base = 0.95
        # Com 1 trial, ajustado deve ser proximo do base
        $adj1 = Get-DsrAdjustedThreshold -BaseThreshold $base -NTrials 1
        $adj1 | Should BeGreaterThan 0.9
        $adj1 | Should BeLessThan 1.0

        # Com 1000 trials, ajustado deve ser bem maior
        $adj1000 = Get-DsrAdjustedThreshold -BaseThreshold $base -NTrials 1000
        $adj1000 | Should BeGreaterThan $adj1

        # N=4 (atual) deve ser entre os dois
        $adj4 = Get-DsrAdjustedThreshold -BaseThreshold $base -NTrials 4
        $adj4 | Should BeGreaterThan $adj1
        $adj4 | Should BeLessThan $adj1000
    }
}
