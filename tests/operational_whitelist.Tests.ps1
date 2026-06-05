# operational_whitelist.Tests.ps1 -- Pester 3.x -- Test-RegimeDirectionAllowed
# Convencoes: ($x) | Should Be $y | sem BeforeAll | sem em-dash | sem &&
# DoW: 0=Sunday, 1=Monday, ..., 6=Saturday

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\lib_operational_whitelist.ps1"

# Helper
function _r {
    param($Regime, $Direction, $DoW, $Mode)
    Test-RegimeDirectionAllowed -Regime $Regime -Direction $Direction -DayOfWeekBRT $DoW -Mode $Mode
}

# ── EXECUTE em ambos os modos ────────────────────────────────────────────────

Describe "Test-RegimeDirectionAllowed - EXECUTE (whitelist live)" {

    It "BULL_STRONG + LONG + Wednesday + paper = execute" {
        $r = _r 'BULL_STRONG' 'LONG' 3 'paper'
        ($r.tier)    | Should Be 'execute'
        ($r.allowed) | Should Be $true
    }

    It "BULL_STRONG + LONG + Wednesday + live = execute" {
        $r = _r 'BULL_STRONG' 'LONG' 3 'live'
        ($r.tier)    | Should Be 'execute'
        ($r.allowed) | Should Be $true
    }

    It "BULL_STRONG + LONG + Sunday + paper = execute (DoW nao bloqueia)" {
        $r = _r 'BULL_STRONG' 'LONG' 0 'paper'
        ($r.tier) | Should Be 'execute'
    }

    It "TRANSITION_UP + LONG + Monday + paper = execute" {
        $r = _r 'TRANSITION_UP' 'LONG' 1 'paper'
        ($r.tier)    | Should Be 'execute'
        ($r.allowed) | Should Be $true
    }

    It "TRANSITION_UP + LONG + Monday + live = execute" {
        $r = _r 'TRANSITION_UP' 'LONG' 1 'live'
        ($r.tier)    | Should Be 'execute'
        ($r.allowed) | Should Be $true
    }
}

# ── OBSERVE paper / SKIP live (assimetria) ───────────────────────────────────

Describe "Test-RegimeDirectionAllowed - OBSERVE paper, SKIP live" {

    It "TRANSITION_UP + LONG + Tuesday + paper = observe (fora janela Monday)" {
        $r = _r 'TRANSITION_UP' 'LONG' 2 'paper'
        ($r.tier)    | Should Be 'observe'
        ($r.allowed) | Should Be $true
    }

    It "TRANSITION_UP + LONG + Tuesday + live = skip" {
        $r = _r 'TRANSITION_UP' 'LONG' 2 'live'
        ($r.tier)    | Should Be 'skip'
        ($r.allowed) | Should Be $false
    }

    It "TRANSITION_UP + LONG + Sunday + live = skip" {
        $r = _r 'TRANSITION_UP' 'LONG' 0 'live'
        ($r.tier) | Should Be 'skip'
    }

    It "BULL_WEAK + LONG + Monday + paper = observe (structural break observa)" {
        $r = _r 'BULL_WEAK' 'LONG' 1 'paper'
        ($r.tier)    | Should Be 'observe'
        ($r.allowed) | Should Be $true
    }

    It "BULL_WEAK + LONG + Monday + live = observe (RE-VALIDATED 2026-05-23 +2.08pp EV)" {
        # SKIP->OBSERVE revalidado (docs/backtest/BLACKLIST_BULL_WEAK_REVALIDATION.md).
        # Rollback via env BULL_WEAK_LONG_SKIP=1.
        $r = _r 'BULL_WEAK' 'LONG' 1 'live'
        ($r.tier)    | Should Be 'observe'
        ($r.allowed) | Should Be $true
    }

    It "BULL_STRONG + SHORT + Wednesday + paper = skip (v3 anti-trend)" {
        $r = _r 'BULL_STRONG' 'SHORT' 3 'paper'
        ($r.tier) | Should Be 'skip'
    }

    It "BULL_STRONG + SHORT + Wednesday + live = skip" {
        $r = _r 'BULL_STRONG' 'SHORT' 3 'live'
        ($r.tier) | Should Be 'skip'
    }

    It "BEAR_WEAK + SHORT + paper = execute (v3 bidirecional)" {
        $r = _r 'BEAR_WEAK' 'SHORT' 3 'paper'
        ($r.tier) | Should Be 'execute'
    }

    It "SIDEWAYS + SHORT + paper = execute (Block2 2026-05-28: +0.34R PF 1.54)" {
        # SIDEWAYS+SHORT edge comprovado -> execute paper, observe live (aguarda 30d forward)
        $r = _r 'SIDEWAYS' 'SHORT' 1 'paper'
        ($r.tier) | Should Be 'execute'
    }

    It "CAPITULATION + SHORT + Saturday + paper = execute (v3 bidirecional)" {
        $r = _r 'CAPITULATION' 'SHORT' 6 'paper'
        ($r.tier) | Should Be 'execute'
    }
}

# ── SKIP em ambos os modos ───────────────────────────────────────────────────

Describe "Test-RegimeDirectionAllowed - SKIP ambos (blacklist completa)" {

    It "BEAR_STRONG + LONG + Monday + paper = skip" {
        $r = _r 'BEAR_STRONG' 'LONG' 1 'paper'
        ($r.tier)    | Should Be 'skip'
        ($r.allowed) | Should Be $false
    }

    It "CAPITULATION + LONG + Tuesday + live = skip" {
        $r = _r 'CAPITULATION' 'LONG' 2 'live'
        ($r.tier) | Should Be 'skip'
    }

    It "SIDEWAYS + LONG + Wednesday + paper = skip" {
        $r = _r 'SIDEWAYS' 'LONG' 3 'paper'
        ($r.tier) | Should Be 'skip'
    }

    It "TRANSITION_DOWN + LONG + Thursday + paper = skip" {
        $r = _r 'TRANSITION_DOWN' 'LONG' 4 'paper'
        ($r.tier) | Should Be 'skip'
    }

    It "BEAR_WEAK + LONG + Friday + live = skip" {
        $r = _r 'BEAR_WEAK' 'LONG' 5 'live'
        ($r.tier) | Should Be 'skip'
    }
}

# ── Edge cases / validacao defensiva ─────────────────────────────────────────

Describe "Test-RegimeDirectionAllowed - validacao de parametros" {

    It "Regime invalido lanca excecao com mensagem clara" {
        { _r 'INVALIDO' 'LONG' 1 'paper' } | Should Throw "Regime invalido"
    }

    It "Direction invalida lanca excecao" {
        { _r 'BULL_STRONG' 'HOLD' 1 'paper' } | Should Throw "Direction invalida"
    }

    It "DayOfWeekBRT abaixo do range lanca excecao" {
        { _r 'BULL_STRONG' 'LONG' -1 'paper' } | Should Throw "DayOfWeekBRT fora do range"
    }

    It "DayOfWeekBRT acima do range lanca excecao" {
        { _r 'BULL_STRONG' 'LONG' 7 'paper' } | Should Throw "DayOfWeekBRT fora do range"
    }

    It "Mode invalido lanca excecao" {
        { _r 'BULL_STRONG' 'LONG' 1 'demo' } | Should Throw "Mode invalido"
    }
}

# ── Estrutura de retorno ─────────────────────────────────────────────────────

Describe "Test-RegimeDirectionAllowed - estrutura de retorno" {

    It "Retorna PSCustomObject com 3 campos obrigatorios" {
        $r = _r 'BULL_STRONG' 'LONG' 1 'live'
        ($r.PSObject.Properties.Name -contains 'allowed') | Should Be $true
        ($r.PSObject.Properties.Name -contains 'tier')    | Should Be $true
        ($r.PSObject.Properties.Name -contains 'reason')  | Should Be $true
    }

    It "Tier sempre em {execute, observe, skip}" {
        $r = _r 'BULL_WEAK' 'LONG' 1 'paper'
        ($r.tier -in @('execute','observe','skip')) | Should Be $true
    }

    It "Reason e string nao-vazia" {
        $r = _r 'BEAR_STRONG' 'SHORT' 3 'live'
        ($r.reason.Length -gt 5) | Should Be $true
    }
}
