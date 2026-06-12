# trailing_stop_manager.Tests.ps1 -- TDD para Get-TrailingStopState (3 fases + moon bag)

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "trailing_stop_manager.ps1")

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

function Make-State {
    param(
        [double]$Entry   = 100.0,
        [double]$Stop    = 90.0,    # risco inicial = 10
        [double]$Current = 100.0,
        [double]$Peak    = 100.0,
        [double]$Target  = 130.0,   # R:R 1:3 => risco=10, alvo=+30
        [string]$Mode    = "STANDARD",
        [double]$ATR     = 5.0
    )
    return Get-TrailingStopState `
        -EntryPrice   $Entry `
        -InitialStop  $Stop `
        -CurrentPrice $Current `
        -PeakPrice    $Peak `
        -TargetPrice  $Target `
        -Mode         $Mode `
        -ATR          $ATR
}

# ─────────────────────────────────────────────────────────────────────────────
# FASE 1 - Stop fixo (price < entry + 1R)
# ─────────────────────────────────────────────────────────────────────────────

Describe "Fase 1 - Stop fixo" {

    It "retorna fase 1 quando price nao atingiu +1R" {
        $s = Make-State -Current 105.0 -Peak 105.0  # risco=10, +1R = entry+10 = 110
        $s.phase | Should Be 1
    }

    It "stop permanece no valor inicial na fase 1" {
        $s = Make-State -Current 105.0 -Peak 105.0
        $s.stop_price | Should Be 90.0
    }

    It "acao e HOLD na fase 1" {
        $s = Make-State -Current 108.0 -Peak 108.0
        $s.action | Should Be "HOLD"
    }

    It "STOP_HIT quando price cai abaixo do stop inicial" {
        $s = Make-State -Current 89.0 -Peak 100.0
        $s.action | Should Be "STOP_HIT"
    }

    It "STOP_HIT exatamente no stop" {
        $s = Make-State -Current 90.0 -Peak 100.0
        $s.action | Should Be "STOP_HIT"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# FASE 2 - Break-even (+1R atingido)
# ─────────────────────────────────────────────────────────────────────────────

Describe "Fase 2 - Break-even" {

    It "entra fase 2 quando price >= entry + 1R" {
        $s = Make-State -Current 110.0 -Peak 110.0  # entry=100, risco=10, +1R = 110
        $s.phase | Should Be 2
    }

    It "stop move para entry na fase 2" {
        $s = Make-State -Current 110.0 -Peak 110.0
        $s.stop_price | Should Be 100.0
    }

    It "acao e MOVE_STOP na transicao para fase 2" {
        $s = Make-State -Current 110.0 -Peak 110.0
        $s.action | Should Be "MOVE_STOP"
    }

    It "stop nao desce abaixo de entry mesmo se price recua" {
        # price recuou para 105 mas peak foi 115 (ja em fase 2/3)
        $s = Make-State -Current 105.0 -Peak 115.0
        $s.stop_price | Should BeGreaterThan 99.9
    }

    It "STOP_HIT quando price cai abaixo do break-even" {
        $s = Make-State -Current 99.0 -Peak 115.0
        $s.action | Should Be "STOP_HIT"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# FASE 3 - Trailing STANDARD (ATR x 2.0)
# ─────────────────────────────────────────────────────────────────────────────

Describe "Fase 3 - Trailing STANDARD (ATR)" {

    It "entra fase 3 quando price >= entry + 2R" {
        $s = Make-State -Current 120.0 -Peak 120.0  # entry=100, risco=10, +2R = 120
        $s.phase | Should Be 3
    }

    It "stop = peak - (ATR x 2.0) no modo STANDARD" {
        # peak=120, ATR=5, trail=10 => stop=110
        $s = Make-State -Current 120.0 -Peak 120.0 -ATR 5.0
        $s.stop_price | Should Be 110.0
    }

    It "stop sobe quando peak sobe" {
        $s1 = Make-State -Current 120.0 -Peak 120.0 -ATR 5.0
        $s2 = Make-State -Current 130.0 -Peak 130.0 -ATR 5.0
        $s2.stop_price | Should BeGreaterThan $s1.stop_price
    }

    It "stop nao desce quando price recua mas peak mantem" {
        # peak foi 130 mas price recuou para 122
        $s = Make-State -Current 122.0 -Peak 130.0 -ATR 5.0
        $s.stop_price | Should Be 120.0  # peak 130 - ATR*2 (10) = 120
    }

    It "STOP_HIT quando price cai abaixo do trailing stop" {
        # peak=130, ATR=5, stop=120; price=119 => hit
        $s = Make-State -Current 119.0 -Peak 130.0 -ATR 5.0
        $s.action | Should Be "STOP_HIT"
    }

    It "ATR zero usa fallback de 3pct do peak" {
        # ATR=0 => fallback 3% => peak=120, stop=116.4
        $s = Make-State -Current 120.0 -Peak 120.0 -ATR 0.0
        $s.stop_price | Should Be ([math]::Round(120.0 * 0.97, 4))
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# FASE 3 - Trailing GEM (20% abaixo do peak)
# ─────────────────────────────────────────────────────────────────────────────

Describe "Fase 3 - Trailing GEM (20pct)" {

    It "stop = peak x 0.80 no modo GEM" {
        # peak=140 => 140*0.80=112 > entry(100) => sem floor
        $s = Make-State -Current 140.0 -Peak 140.0 -Mode "GEM"
        $s.stop_price | Should Be 112.0
    }

    It "stop nunca desce abaixo de entry no modo GEM" {
        # peak=115 => 115*0.80=92 menor que entry(100) => trunca em entry
        $s = Make-State -Entry 100 -Stop 90 -Current 115.0 -Peak 115.0 -Mode "GEM" -ATR 5
        ($s.stop_price -ge 100.0) | Should Be $true
    }

    It "stop GEM sobe com peak" {
        $s1 = Make-State -Current 120.0 -Peak 120.0 -Mode "GEM"
        $s2 = Make-State -Current 200.0 -Peak 200.0 -Mode "GEM"
        $s2.stop_price | Should BeGreaterThan $s1.stop_price
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Moon Bag - exit parcial no target
# ─────────────────────────────────────────────────────────────────────────────

Describe "Moon Bag - exit parcial" {

    It "PARTIAL_EXIT quando price >= target no modo GEM" {
        # entry=100, stop=90, target=130, price=130
        $s = Make-State -Current 130.0 -Peak 130.0 -Target 130.0 -Mode "GEM"
        $s.action | Should Be "PARTIAL_EXIT"
    }

    It "partial_pct e 50 no modo GEM" {
        $s = Make-State -Current 130.0 -Peak 130.0 -Target 130.0 -Mode "GEM"
        $s.partial_pct | Should Be 50
    }

    It "PARTIAL_EXIT nao ocorre no modo STANDARD" {
        $s = Make-State -Current 130.0 -Peak 130.0 -Target 130.0 -Mode "STANDARD"
        $s.action | Should Not Be "PARTIAL_EXIT"
    }

    It "apos PARTIAL_EXIT stop do moon bag nunca abaixo de entry" {
        # price subiu muito alem do target
        $s = Make-State -Current 200.0 -Peak 200.0 -Target 130.0 -Mode "GEM"
        ($s.stop_price -ge 100.0) | Should Be $true
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Edge cases
# ─────────────────────────────────────────────────────────────────────────────

Describe "Edge cases" {

    It "retorna objeto com campos obrigatorios" {
        $s = Make-State
        $s.phase        | Should Not BeNullOrEmpty
        $s.stop_price   | Should Not BeNullOrEmpty
        $s.action       | Should Not BeNullOrEmpty
        $s.partial_pct  | Should Not BeNullOrEmpty
    }

    It "entry == stop nao causa divisao por zero" {
        { Make-State -Entry 100 -Stop 100 -Current 100 -Peak 100 } | Should Not Throw
    }

    It "price muito acima nao causa overflow" {
        { Make-State -Current 999999 -Peak 999999 -Mode "GEM" } | Should Not Throw
    }
}
