# lib_kelly_sizing.Tests.ps1 -- Pester 3.x
# Kelly fracionario com cap pra position sizing dinamico.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\lib_kelly_sizing.ps1"


Describe "Get-KellyFraction - formula classica" {
    It "Win 60% odds 2:1 retorna 0.4 (kelly bruto)" {
        # f = (p*b - q) / b = (0.6*2 - 0.4)/2 = 0.4
        $f = Get-KellyFraction -WinRate 0.6 -WinLossRatio 2.0 -CapPct 1.0
        # Cap 1.0 (100%) nao limita; valor bruto = 0.4
        [Math]::Round($f, 4) | Should Be 0.4
    }

    It "Edge negativo retorna 0" {
        # f = (0.3*2 - 0.7)/2 = -0.05 -> 0
        $f = Get-KellyFraction -WinRate 0.3 -WinLossRatio 2.0 -CapPct 1.0
        $f | Should Be 0
    }

    It "Edge zero retorna 0" {
        # Coin flip 50/50 odds 1:1: f = 0
        $f = Get-KellyFraction -WinRate 0.5 -WinLossRatio 1.0 -CapPct 1.0
        $f | Should Be 0
    }
}


Describe "Get-KellyFraction - cap aplicado" {
    It "Cap 0.01 limita kelly bruto 0.4 para 0.01" {
        $f = Get-KellyFraction -WinRate 0.6 -WinLossRatio 2.0 -CapPct 0.01
        $f | Should Be 0.01
    }

    It "Kelly menor que cap retorna kelly bruto" {
        # p=0.51, b=1.0: f = (0.51 - 0.49)/1 = 0.02; cap 0.05 -> retorna 0.02
        $f = Get-KellyFraction -WinRate 0.51 -WinLossRatio 1.0 -CapPct 0.05
        [Math]::Round($f, 4) | Should Be 0.02
    }
}


Describe "Get-KellySize - integracao com capital" {
    It "Capital 1000 com Kelly 0.01 retorna 10 USD" {
        $size = Get-KellySize -Capital 1000 -WinRate 0.6 -WinLossRatio 2.0 -CapPct 0.01
        $size | Should Be 10
    }

    It "Edge zero retorna size 0" {
        $size = Get-KellySize -Capital 1000 -WinRate 0.4 -WinLossRatio 1.0 -CapPct 0.01
        $size | Should Be 0
    }
}
