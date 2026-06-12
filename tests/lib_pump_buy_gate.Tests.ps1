# lib_pump_buy_gate.Tests.ps1 -- Pester 3.x
# Anti-pump-buy gate: BLOQUEIA promocao Tier A se preco muito perto do peak 7d.
# Evita compra em topo local. Resolve padrao PENDLE/INJ drawdown -17/-19% pos-promotion.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\lib_pump_buy_gate.ps1"


Describe "Test-PumpBuyGate - cenarios canonicos" {
    It "Preco 5% abaixo do peak passa (default threshold -5)" {
        # peak=100, current=95 -> -5% = exatamente no limite, deve passar
        $r = Test-PumpBuyGate -CurrentPrice 95 -Peak7d 100
        $r.passes | Should Be $true
    }

    It "Preco 10% abaixo do peak passa folgado" {
        $r = Test-PumpBuyGate -CurrentPrice 90 -Peak7d 100
        $r.passes | Should Be $true
    }

    It "Preco no peak NAO passa (zero pullback)" {
        $r = Test-PumpBuyGate -CurrentPrice 100 -Peak7d 100
        $r.passes | Should Be $false
        $r.reason | Should Match "no_pullback|at_peak|above_peak"
    }

    It "Preco 2% abaixo do peak NAO passa (insufficient pullback)" {
        $r = Test-PumpBuyGate -CurrentPrice 98 -Peak7d 100
        $r.passes | Should Be $false
    }

    It "Preco ACIMA do peak (novo high) NAO passa" {
        $r = Test-PumpBuyGate -CurrentPrice 105 -Peak7d 100
        $r.passes | Should Be $false
    }
}


Describe "Test-PumpBuyGate - threshold customizado" {
    It "Threshold -10 permite preco entre -5 e -10 (NAO passa)" {
        $r = Test-PumpBuyGate -CurrentPrice 95 -Peak7d 100 -MaxDistFromPeakPct -10
        $r.passes | Should Be $false
    }

    It "Threshold -10 permite preco -10% (passa)" {
        $r = Test-PumpBuyGate -CurrentPrice 90 -Peak7d 100 -MaxDistFromPeakPct -10
        $r.passes | Should Be $true
    }

    It "Threshold -3 mais permissivo: -3.5% passa" {
        $r = Test-PumpBuyGate -CurrentPrice 96.5 -Peak7d 100 -MaxDistFromPeakPct -3
        $r.passes | Should Be $true
    }
}


Describe "Test-PumpBuyGate - estrutura retorno" {
    It "Retorna passes + reason + dist_pct + current + peak" {
        $r = Test-PumpBuyGate -CurrentPrice 95 -Peak7d 100
        $r.passes    | Should Not BeNullOrEmpty
        $r.dist_pct  | Should Not BeNullOrEmpty
        $r.PSObject.Properties.Name -contains "reason"      | Should Be $true
        $r.PSObject.Properties.Name -contains "current_price" | Should Be $true
        $r.PSObject.Properties.Name -contains "peak_7d"     | Should Be $true
    }
}


Describe "Test-PumpBuyGate - edge cases" {
    It "Peak zero retorna false (proteje div zero)" {
        $r = Test-PumpBuyGate -CurrentPrice 100 -Peak7d 0
        $r.passes | Should Be $false
        $r.reason | Should Match "invalid"
    }

    It "Current zero retorna false" {
        $r = Test-PumpBuyGate -CurrentPrice 0 -Peak7d 100
        $r.passes | Should Be $false
    }
}


Describe "Get-Peak7dFromCandles - helper" {
    It "Calcula peak de array highs" {
        $candles = @(
            @{ high = 100 }, @{ high = 105 }, @{ high = 102 },
            @{ high = 110 }, @{ high = 108 }, @{ high = 95 }, @{ high = 99 }
        )
        $peak = Get-Peak7dFromCandles -Candles $candles
        $peak | Should Be 110
    }

    It "Array vazio retorna 0" {
        $peak = Get-Peak7dFromCandles -Candles @()
        $peak | Should Be 0
    }
}
