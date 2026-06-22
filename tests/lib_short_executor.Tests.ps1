# TDD do executor SHORT (dormente). Cobre o plano puro + o gate fail-closed.
$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_short_executor.ps1")

Describe "Build-ShortOrderPlan -- regras de ouro" {
    It "SHORT: stop ACIMA da entrada, alvo ABAIXO" {
        $p = Build-ShortOrderPlan -EntryPrice 100 -Capital 1000 -Atr 1 -AtrMult 2 -RR 5
        $p.valid | Should Be $true
        ($p.stop -gt $p.entry) | Should Be $true
        ($p.target -lt $p.entry) | Should Be $true
        $p.side | Should Be "sell"
    }
    It "risco no stop = ~1% do capital (sizing)" {
        # entry 100, atr 1, mult 2 -> stopDist 2 -> stopDistPct 0.02; risk 1% de 1000 = 10
        # notional = 10/0.02 = 500; loss no stop = notional*stopDistPct = 500*0.02 = 10 == risk
        $p = Build-ShortOrderPlan -EntryPrice 100 -Capital 1000 -Atr 1 -AtrMult 2 -RiskPct 0.01 -MaxLeverage 100
        $p.risk_usd | Should Be 10
        $loss = $p.notional_usd * $p.stop_dist_pct
        [math]::Round($loss,2) | Should Be 10
    }
    It "R:R respeitado: targetDist = RR * stopDist" {
        $p = Build-ShortOrderPlan -EntryPrice 100 -Capital 1000 -Atr 1 -AtrMult 2 -RR 5 -MaxLeverage 100
        # stopDist=2, target = 100 - 5*2 = 90
        $p.target | Should Be 90
    }
    It "alavancagem clampada ao teto" {
        # stopDistPct minusculo -> notional gigante -> clamp em MaxLeverage
        $p = Build-ShortOrderPlan -EntryPrice 100 -Capital 1000 -Atr 0.01 -AtrMult 2 -MaxLeverage 10
        $p.leverage | Should Be 10
        $p.reason | Should Be "leverage_capped"
    }
    It "entry invalido -> plano invalido (fail-closed)" {
        (Build-ShortOrderPlan -EntryPrice 0 -Capital 1000).valid | Should Be $false
    }
    It "capital invalido -> plano invalido" {
        (Build-ShortOrderPlan -EntryPrice 100 -Capital 0).valid | Should Be $false
    }
    It "stop muito largo p/ RR (target<=0) -> invalido" {
        # stopPctFallback 0.25, RR 5 -> target = 100 - 5*25 = -25 <=0
        (Build-ShortOrderPlan -EntryPrice 100 -Capital 1000 -Atr 0 -StopPctFallback 0.25 -RR 5).valid | Should Be $false
    }
}

Describe "Test-ShortLiveGate -- fail-closed (dormente)" {
    It "sem flag -> nega (no_live_flag)" {
        $g = Test-ShortLiveGate -Market "BTCUSDT" -FlagPresent $false -ShortTierA @("BTCUSDT")
        $g.allow | Should Be $false
        $g.reason | Should Be "no_live_flag"
    }
    It "flag mas market fora do tier A -> nega" {
        $g = Test-ShortLiveGate -Market "BTCUSDT" -FlagPresent $true -ShortTierA @()
        $g.allow | Should Be $false
        $g.reason | Should Be "not_in_short_tier_a"
    }
    It "flag + market no tier A -> permite" {
        $g = Test-ShortLiveGate -Market "BTCUSDT" -FlagPresent $true -ShortTierA @("BTCUSDT")
        $g.allow | Should Be $true
    }
}

Describe "Test-ShortEntryReady -- consolida stack (fail-closed)" {
    $okArgs = @{ PlanValid=$true; GateAllow=$true; Tier="S"; ClusterExceeded=$false; HasPosition=$false; CapitalSafe=$true }
    It "tudo ok + tier S -> ready" {
        (Test-ShortEntryReady @okArgs).ready | Should Be $true
    }
    It "tier A (nao S) -> bloqueia" {
        $a = $okArgs.Clone(); $a.Tier = "A"
        $r = Test-ShortEntryReady @a
        $r.ready | Should Be $false
        ($r.reason -match "tier_not_S") | Should Be $true
    }
    It "posicao ja aberta -> bloqueia (dedup)" {
        $a = $okArgs.Clone(); $a.HasPosition = $true
        (Test-ShortEntryReady @a).ready | Should Be $false
    }
    It "capital unsafe -> bloqueia" {
        $a = $okArgs.Clone(); $a.CapitalSafe = $false
        (Test-ShortEntryReady @a).ready | Should Be $false
    }
    It "cluster cap excedido -> bloqueia" {
        $a = $okArgs.Clone(); $a.ClusterExceeded = $true
        (Test-ShortEntryReady @a).ready | Should Be $false
    }
    It "plano invalido -> bloqueia" {
        $a = $okArgs.Clone(); $a.PlanValid = $false
        (Test-ShortEntryReady @a).ready | Should Be $false
    }
    It "gate negado (sem flag/tier) -> bloqueia" {
        $a = $okArgs.Clone(); $a.GateAllow = $false
        (Test-ShortEntryReady @a).ready | Should Be $false
    }
}

Describe "Invoke-ShortEntry -- dormente por padrao" {
    It "sem flag dir -> observa, nao coloca ordem" {
        $r = Invoke-ShortEntry -Market "BTCUSDT" -EntryPrice 100 -Capital 1000 -Atr 1 -ShortTierA @("BTCUSDT")
        $r.placed | Should Be $false
        $r.observed | Should Be $true
    }
}
