# Tests para lib_regime_surf.ps1 (Pester 3.4.0)
# TDD: cerebro do surf bidirecional -- LONG bull / SHORT bear, fail-closed.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_regime_surf.ps1")

# Helpers de cenario (espelham Get-MarketScenario)
function New-BearScen  { [pscustomobject]@{ scenario="BEAR";        allow_long=$false; allow_short=$true;  strategy="short_ou_caixa" } }
function New-BullScen  { [pscustomobject]@{ scenario="BULL";        allow_long=$true;  allow_short=$false; strategy="long" } }
function New-CapitScen { [pscustomobject]@{ scenario="CAPITULACAO"; allow_long=$true;  allow_short=$false; strategy="acumula_long_fundo" } }
function New-NeutroScen{ [pscustomobject]@{ scenario="NEUTRO";      allow_long=$false; allow_short=$false; strategy="espera" } }

Describe "Resolve-RegimeSurfDecision -- Fail-closed (Regra #5)" {
    It "Sem cenario -> SKIP" {
        $r = Resolve-RegimeSurfDecision -Price 100 -Capital 5000
        $r.direction | Should Be "SKIP"
        $r.act | Should Be $false
    }
    It "Preco invalido -> SKIP" {
        $r = Resolve-RegimeSurfDecision -Scenario (New-BearScen) -Price 0 -Capital 5000 -ShortConviction 80 -Momentum30dPct -20
        $r.direction | Should Be "SKIP"
    }
    It "Capital invalido -> SKIP" {
        $r = Resolve-RegimeSurfDecision -Scenario (New-BearScen) -Price 100 -Capital 0 -ShortConviction 80 -Momentum30dPct -20
        $r.direction | Should Be "SKIP"
    }
    It "Cenario NEUTRO (nenhum lado) -> SKIP caixa" {
        $r = Resolve-RegimeSurfDecision -Scenario (New-NeutroScen) -Price 100 -Capital 5000 -LongConviction 90 -ShortConviction 90
        $r.direction | Should Be "SKIP"
    }
}

Describe "Resolve-RegimeSurfDecision -- SHORT surfa o bear" {
    It "BEAR + downtrend + conviction -> SHORT" {
        $r = Resolve-RegimeSurfDecision -Scenario (New-BearScen) -Price 100 -Capital 5000 -ShortConviction 70 -Momentum30dPct -20
        $r.act | Should Be $true
        $r.direction | Should Be "SHORT"
    }
    It "SHORT: stop ACIMA da entrada (Regra #1)" {
        $r = Resolve-RegimeSurfDecision -Scenario (New-BearScen) -Price 100 -Capital 5000 -ShortConviction 70 -Momentum30dPct -20 -StopPct 8
        ($r.stop -gt $r.entry) | Should Be $true
        $r.stop | Should Be 108
    }
    It "SHORT: target ABAIXO da entrada com R:R" {
        $r = Resolve-RegimeSurfDecision -Scenario (New-BearScen) -Price 100 -Capital 5000 -ShortConviction 70 -Momentum30dPct -20 -StopPct 8 -RR 1.5
        ($r.target -lt $r.entry) | Should Be $true
        $r.target | Should Be 88   # 100 - (8*1.5)
    }
    It "BEAR mas momentum POSITIVO (nao confirma downtrend) -> SKIP" {
        $r = Resolve-RegimeSurfDecision -Scenario (New-BearScen) -Price 100 -Capital 5000 -ShortConviction 90 -Momentum30dPct 5
        $r.direction | Should Be "SKIP"
    }
    It "BEAR + downtrend mas conviction baixa -> SKIP" {
        $r = Resolve-RegimeSurfDecision -Scenario (New-BearScen) -Price 100 -Capital 5000 -ShortConviction 20 -Momentum30dPct -20
        $r.direction | Should Be "SKIP"
    }
}

Describe "Resolve-RegimeSurfDecision -- LONG surfa o bull" {
    It "BULL + uptrend + conviction -> LONG" {
        $r = Resolve-RegimeSurfDecision -Scenario (New-BullScen) -Price 100 -Capital 5000 -LongConviction 70 -Momentum30dPct 15
        $r.direction | Should Be "LONG"
    }
    It "LONG: stop ABAIXO da entrada (Regra #1)" {
        $r = Resolve-RegimeSurfDecision -Scenario (New-BullScen) -Price 100 -Capital 5000 -LongConviction 70 -Momentum30dPct 15 -StopPct 8
        ($r.stop -lt $r.entry) | Should Be $true
        $r.stop | Should Be 92
    }
    It "BULL mas momentum negativo -> SKIP (nao surfa contra)" {
        $r = Resolve-RegimeSurfDecision -Scenario (New-BullScen) -Price 100 -Capital 5000 -LongConviction 90 -Momentum30dPct -10
        $r.direction | Should Be "SKIP"
    }
    It "CAPITULACAO permite LONG mesmo com momentum negativo (compra fundo)" {
        $r = Resolve-RegimeSurfDecision -Scenario (New-CapitScen) -Price 100 -Capital 5000 -LongConviction 70 -Momentum30dPct -30
        $r.direction | Should Be "LONG"
    }
}

Describe "Resolve-RegimeSurfDecision -- Sizing risk-based (Regra #2)" {
    It "Risco = RiskPct do capital" {
        $r = Resolve-RegimeSurfDecision -Scenario (New-BearScen) -Price 100 -Capital 5000 -ShortConviction 70 -Momentum30dPct -20 -RiskPct 1
        $r.risk_usd | Should Be 50   # 1% de 5000
    }
    It "Notional = risco / dist_stop (mover ate stop = risco alvo)" {
        # risco 50, stop 8% -> notional = 50/0.08 = 625
        $r = Resolve-RegimeSurfDecision -Scenario (New-BearScen) -Price 100 -Capital 5000 -ShortConviction 70 -Momentum30dPct -20 -RiskPct 1 -StopPct 8
        $r.size_usd | Should Be 625
    }
    It "Micro sizing (0.2%) reduz notional proporcional" {
        $r = Resolve-RegimeSurfDecision -Scenario (New-BearScen) -Price 100 -Capital 5000 -ShortConviction 70 -Momentum30dPct -20 -RiskPct 0.2 -StopPct 8
        $r.risk_usd | Should Be 10
        $r.size_usd | Should Be 125
    }
}
