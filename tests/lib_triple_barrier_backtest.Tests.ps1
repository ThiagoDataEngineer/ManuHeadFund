# lib_triple_barrier_backtest.Tests.ps1 -- Pester 3.x
# TDD 2026-06-24: backtest REAL (triple-barrier Lopez de Prado), substitui o fake que
# ESTIMAVA pnl do score. Simula entrada+stop+alvo no caminho de preco REAL.
# SHORT: stop ACIMA, alvo ABAIXO. LONG: stop ABAIXO, alvo ACIMA.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_triple_barrier_backtest.ps1")

# barras: cada uma { h=high, l=low, c=close }
Describe "Invoke-TripleBarrier - SHORT" {
    It "Preco cai e bate o ALVO primeiro -> WIN (pnl positivo p/ short)" {
        $bars = @(@{h=101;l=99;c=100}, @{h=100;l=95;c=96}, @{h=97;l=90;c=91})
        $r = Invoke-TripleBarrier -Bars $bars -Entry 100 -Stop 105 -Target 92 -Direction "SHORT"
        $r.outcome | Should Be "target"
        ($r.pnl_pct -gt 0) | Should Be $true
    }
    It "Preco sobe e bate o STOP primeiro -> LOSS" {
        $bars = @(@{h=103;l=99;c=102}, @{h=106;l=101;c=105})
        $r = Invoke-TripleBarrier -Bars $bars -Entry 100 -Stop 105 -Target 92 -Direction "SHORT"
        $r.outcome | Should Be "stop"
        ($r.pnl_pct -lt 0) | Should Be $true
    }
    It "Nao bate nenhum -> TIMEOUT (sai no ultimo close)" {
        $bars = @(@{h=101;l=99;c=100}, @{h=102;l=98;c=99})
        $r = Invoke-TripleBarrier -Bars $bars -Entry 100 -Stop 105 -Target 92 -Direction "SHORT"
        $r.outcome | Should Be "timeout"
    }
}

Describe "Invoke-TripleBarrier - LONG (espelhado)" {
    It "Sobe e bate ALVO -> WIN" {
        $bars = @(@{h=102;l=99;c=101}, @{h=109;l=104;c=108})
        $r = Invoke-TripleBarrier -Bars $bars -Entry 100 -Stop 95 -Target 108 -Direction "LONG"
        $r.outcome | Should Be "target"; ($r.pnl_pct -gt 0) | Should Be $true
    }
    It "Cai e bate STOP -> LOSS" {
        $bars = @(@{h=101;l=94;c=95})
        $r = Invoke-TripleBarrier -Bars $bars -Entry 100 -Stop 95 -Target 108 -Direction "LONG"
        $r.outcome | Should Be "stop"; ($r.pnl_pct -lt 0) | Should Be $true
    }
}

Describe "Measure-BacktestEdge - agrega com anti-overfit (effective_n)" {
    It "Calcula win_rate, EV e effective_n (dias distintos, nao trades)" {
        $trades = @(
            @{ pnl_pct=2; win=$true;  date="2026-01-01" }
            @{ pnl_pct=-1; win=$false; date="2026-01-01" }  # mesmo dia -> nao infla n efetivo
            @{ pnl_pct=3; win=$true;  date="2026-01-02" }
        )
        $m = Measure-BacktestEdge -Trades $trades
        $m.n_trades | Should Be 3
        $m.effective_n | Should Be 2   # 2 dias distintos
        $m.win_rate | Should Be ([math]::Round(2/3,4))
    }
    It "Lista vazia -> zeros (sem edge)" {
        (Measure-BacktestEdge -Trades @()).n_trades | Should Be 0
    }
}
