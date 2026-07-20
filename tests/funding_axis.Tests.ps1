# funding_axis.Tests.ps1 -- TDD do eixo funding (sinal #1 de pre-dump em perpetuos)
# Funding alto positivo = longs lotados = risco de squeeze pra baixo -> favorece SHORT.
# Funding negativo = shorts lotados = squeeze pra cima -> favorece LONG.
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_entry_conviction_ensemble.ps1"

Describe "Get-FundingConvictionScore (bidirecional)" {

    Context "SHORT favorecido por funding positivo alto" {

        It "funding +0.06pct (longs lotados) = SHORT alto" {
            $s = Get-FundingConvictionScore -FundingRate 0.0006 -Direction "SHORT"
            ($s -ge 75) | Should Be $true
        }

        It "funding extremo +0.1pct = SHORT muito alto" {
            $s = Get-FundingConvictionScore -FundingRate 0.001 -Direction "SHORT"
            ($s -ge 90) | Should Be $true
        }

        It "funding positivo NAO favorece LONG (shortar squeeze)" {
            $s = Get-FundingConvictionScore -FundingRate 0.0006 -Direction "LONG"
            ($s -le 35) | Should Be $true
        }
    }

    Context "LONG favorecido por funding negativo" {

        It "funding -0.06pct (shorts lotados) = LONG alto" {
            $s = Get-FundingConvictionScore -FundingRate -0.0006 -Direction "LONG"
            ($s -ge 75) | Should Be $true
        }
    }

    Context "Neutro / robustez" {

        It "funding ~0 = neutro 50" {
            $s = Get-FundingConvictionScore -FundingRate 0.0 -Direction "SHORT"
            $s | Should Be 50
        }

        It "funding null = neutro 50" {
            $s = Get-FundingConvictionScore -FundingRate $null -Direction "SHORT"
            $s | Should Be 50
        }

        It "clamp 0..100 (funding gigante)" {
            $s = Get-FundingConvictionScore -FundingRate 0.0075 -Direction "SHORT"
            (($s -ge 0) -and ($s -le 100)) | Should Be $true
        }
    }
}

Describe "Pesos incluem funding (direcionais)" {

    It "SHORT pondera funding mais que LONG" {
        $wl = Get-ConvictionDefaultWeights -Direction "LONG"
        $ws = Get-ConvictionDefaultWeights -Direction "SHORT"
        ($ws.funding -gt $wl.funding) | Should Be $true
    }

    It "pesos ainda somam ~1.0 com funding incluido" {
        foreach ($d in @("LONG","SHORT")) {
            $w = Get-ConvictionDefaultWeights -Direction $d
            $sum = ($w.Values | Measure-Object -Sum).Sum
            ([math]::Abs($sum - 1.0) -lt 0.001) | Should Be $true
        }
    }

    It "SHORT mantem overextension > LONG (regressao)" {
        $wl = Get-ConvictionDefaultWeights -Direction "LONG"
        $ws = Get-ConvictionDefaultWeights -Direction "SHORT"
        ($ws.overextension -gt $wl.overextension) | Should Be $true
    }
}
