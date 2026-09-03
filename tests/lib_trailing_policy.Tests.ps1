# lib_trailing_policy.Tests.ps1 -- TDD da politica de saida por tipo de operacao.
# PURO, sem LLM (barato): scalp/swing/short/long/runner recebem gestao propria.
# Plugga no harness (Invoke-ExitReplay) -> mensuravel. Cada politica = hipotese.

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_exit_backtest.ps1")
. (Join-Path $agentsDir "lib_trailing_baseline.ps1")
. (Join-Path $agentsDir "lib_trailing_policy.ps1")

function _C { param($o,$h,$l,$c,$atr=0,$v=1000) [PSCustomObject]@{ open=$o; high=$h; low=$l; close=$c; atr=$atr; volume=$v } }

Describe "Resolve-ExitPolicy -- seletor por tipo" {

    It "scalp: breakeven cedo + time-stop curto" {
        $p = Resolve-ExitPolicy -TradeType "scalp" -Direction "LONG"
        $p.breakeven_at_r | Should BeLessThan 1.0
        $p.time_stop_bars | Should BeGreaterThan 0
        $p.time_stop_bars | Should BeLessThan 20
    }

    It "swing LONG: chandelier + parciais em 1R e 2R" {
        $p = Resolve-ExitPolicy -TradeType "swing" -Direction "LONG"
        $p.trail_method | Should Be "chandelier"
        @($p.partials).Count | Should BeGreaterThan 1
        ($p.partials[0].at_r) | Should Be 1.0
    }

    It "swing SHORT mais apertado que swing LONG (trail_atr_mult menor)" {
        $pl = Resolve-ExitPolicy -TradeType "swing" -Direction "LONG"
        $ps = Resolve-ExitPolicy -TradeType "swing" -Direction "SHORT"
        $ps.trail_atr_mult | Should BeLessThan $pl.trail_atr_mult
    }

    It "runner (pos-parcial): sem novas parciais, sai so em reversao" {
        $p = Resolve-ExitPolicy -TradeType "runner" -Direction "LONG"
        @($p.partials).Count | Should Be 0
        $p.reversal_exit_signals | Should BeGreaterThan 0
    }

    It "tipo desconhecido -> default sano (nao-nulo)" {
        $p = Resolve-ExitPolicy -TradeType "xyz" -Direction "LONG"
        $p | Should Not BeNullOrEmpty
        $p.trade_type | Should Be "standard"
    }
}

Describe "Get-ExitDecision -- regras puras" {

    It "Breakeven: r_now >= breakeven_at_r move stop p/ entry (LONG)" {
        $pol = @{ breakeven_at_r=1.0; trail_method="none"; partials=@(); time_stop_bars=0; reversal_exit_signals=0; reversal_tighten_signals=0 }
        $ctx = @{ side="LONG"; entry=100; risk=10; r_now=1.2; peak=112; current_stop=90; remaining_size=1.0; bars_held=3; signals=0; atr=0 }
        $d = Get-ExitDecision -Policy $pol -Context $ctx
        $d.new_stop | Should Be 100
    }

    It "Parcial: r_now>=1, parciais[{1R,0.33}] -> partial ~0.33" {
        $pol = @{ breakeven_at_r=0; trail_method="none"; partials=@(@{at_r=1.0;pct=0.33}); time_stop_bars=0; reversal_exit_signals=0; reversal_tighten_signals=0 }
        $ctx = @{ side="LONG"; entry=100; risk=10; r_now=1.1; peak=111; current_stop=90; remaining_size=1.0; bars_held=2; signals=0; atr=0 }
        $d = Get-ExitDecision -Policy $pol -Context $ctx
        $d.action | Should Be "partial"
        [math]::Round($d.size_pct,2) | Should Be 0.33
    }

    It "Chandelier: new_stop = peak - mult*atr (LONG)" {
        $pol = @{ breakeven_at_r=0; trail_method="chandelier"; trail_atr_mult=3.0; partials=@(); time_stop_bars=0; reversal_exit_signals=0; reversal_tighten_signals=0 }
        $ctx = @{ side="LONG"; entry=100; risk=10; r_now=2.0; peak=120; current_stop=95; remaining_size=1.0; bars_held=4; signals=0; atr=2.0 }
        $d = Get-ExitDecision -Policy $pol -Context $ctx
        $d.new_stop | Should Be 114   # 120 - 3*2
    }

    It "Time-stop: bars_held >= time_stop_bars -> exit" {
        $pol = @{ breakeven_at_r=0; trail_method="none"; partials=@(); time_stop_bars=8; reversal_exit_signals=0; reversal_tighten_signals=0 }
        $ctx = @{ side="LONG"; entry=100; risk=10; r_now=0.5; peak=106; current_stop=95; remaining_size=1.0; bars_held=8; signals=0; atr=0 }
        $d = Get-ExitDecision -Policy $pol -Context $ctx
        $d.action | Should Be "exit"
    }

    It "Reversao confirmada (signals>=limite) -> exit" {
        $pol = @{ breakeven_at_r=0; trail_method="none"; partials=@(); time_stop_bars=0; reversal_exit_signals=3; reversal_tighten_signals=2 }
        $ctx = @{ side="LONG"; entry=100; risk=10; r_now=2.0; peak=121; current_stop=100; remaining_size=0.5; bars_held=5; signals=3; atr=0 }
        $d = Get-ExitDecision -Policy $pol -Context $ctx
        $d.action | Should Be "exit"
    }

    It "Reversao ambigua (signals=tighten) NAO sai, so aperta stop (nao vende no fundo)" {
        $pol = @{ breakeven_at_r=0; trail_method="none"; partials=@(); time_stop_bars=0; reversal_exit_signals=3; reversal_tighten_signals=2 }
        $ctx = @{ side="LONG"; entry=100; risk=10; r_now=2.0; peak=121; current_stop=100; remaining_size=0.5; bars_held=5; signals=2; atr=0 }
        $d = Get-ExitDecision -Policy $pol -Context $ctx
        $d.action | Should Be "hold"
        $d.new_stop | Should BeGreaterThan 100   # apertou acima do BE
    }

    It "SHORT breakeven: r_now>=limite move stop p/ entry (ratchet p/ baixo no harness)" {
        $pol = @{ breakeven_at_r=1.0; trail_method="none"; partials=@(); time_stop_bars=0; reversal_exit_signals=0; reversal_tighten_signals=0 }
        $ctx = @{ side="SHORT"; entry=100; risk=10; r_now=1.5; peak=85; current_stop=110; remaining_size=1.0; bars_held=3; signals=0; atr=0 }
        $d = Get-ExitDecision -Policy $pol -Context $ctx
        $d.new_stop | Should Be 100
    }

    # 2026-09-02 FIX CRITICO: achado real (owner, "toma muito stop") -- 59
    # execucoes reais confirmaram que o max de sinais de reversao simultaneos
    # observado em producao e' 2, nunca 3. reversal_exit_signals=3 (antigo)
    # era estruturalmente quase inatingivel, e PARTIAL por R-multiple sozinho
    # nunca disparava porque a maioria dos trades reverte ANTES de chegar em
    # R=1.0. Estas 4 provas cobrem o novo criterio 3b (reversal_partial_pct).
    Context "PARTIAL por reversao isolada (2026-09-02, criterio 3b)" {
        It "1 sinal de reversao (tighten) + lucro real + reversal_partial_pct definido -> partial" {
            $pol = @{ breakeven_at_r=0; trail_method="none"; partials=@(@{at_r=1.0;pct=0.5}); time_stop_bars=0; reversal_exit_signals=2; reversal_tighten_signals=1; reversal_partial_pct=0.3 }
            $ctx = @{ side="LONG"; entry=100; risk=10; r_now=0.4; peak=104; current_stop=98; remaining_size=1.0; bars_held=2; signals=1; atr=0 }
            $d = Get-ExitDecision -Policy $pol -Context $ctx
            $d.action | Should Be "partial"
            $d.size_pct | Should Be 0.3
        }

        It "sem lucro real (r_now<=0), mesmo com sinal de reversao: NAO realiza (nunca vende no prejuizo por ruido)" {
            $pol = @{ breakeven_at_r=0; trail_method="none"; partials=@(); time_stop_bars=0; reversal_exit_signals=2; reversal_tighten_signals=1; reversal_partial_pct=0.3 }
            $ctx = @{ side="LONG"; entry=100; risk=10; r_now=-0.2; peak=99; current_stop=95; remaining_size=1.0; bars_held=2; signals=1; atr=0 }
            $d = Get-ExitDecision -Policy $pol -Context $ctx
            $d.action | Should Not Be "partial"
        }

        It "reversal_partial_pct AUSENTE (policy antiga, opt-in nao ativado): comportamento antigo preservado, nunca realiza so por sinal isolado" {
            $pol = @{ breakeven_at_r=0; trail_method="none"; partials=@(); time_stop_bars=0; reversal_exit_signals=2; reversal_tighten_signals=1 }
            $ctx = @{ side="LONG"; entry=100; risk=10; r_now=0.4; peak=104; current_stop=98; remaining_size=1.0; bars_held=2; signals=1; atr=0 }
            $d = Get-ExitDecision -Policy $pol -Context $ctx
            $d.action | Should Not Be "partial"
        }

        It "ja houve PARTIAL anterior (remaining<1.0): criterio 3b nao repete (so dispara uma vez, antes de qualquer realizacao)" {
            $pol = @{ breakeven_at_r=0; trail_method="none"; partials=@(); time_stop_bars=0; reversal_exit_signals=2; reversal_tighten_signals=1; reversal_partial_pct=0.3 }
            $ctx = @{ side="LONG"; entry=100; risk=10; r_now=0.4; peak=104; current_stop=98; remaining_size=0.7; bars_held=2; signals=1; atr=0 }
            $d = Get-ExitDecision -Policy $pol -Context $ctx
            $d.action | Should Not Be "partial"
        }

        It "2 sinais (>=exit_n) tem PRECEDENCIA sobre o criterio 3b -- vira exit, nao partial" {
            $pol = @{ breakeven_at_r=0; trail_method="none"; partials=@(); time_stop_bars=0; reversal_exit_signals=2; reversal_tighten_signals=1; reversal_partial_pct=0.3 }
            $ctx = @{ side="LONG"; entry=100; risk=10; r_now=0.4; peak=104; current_stop=98; remaining_size=1.0; bars_held=2; signals=2; atr=0 }
            $d = Get-ExitDecision -Policy $pol -Context $ctx
            $d.action | Should Be "exit"
        }

        It "SHORT: mesmo criterio funciona espelhado (r_now>0 = lucro real em SHORT)" {
            $pol = @{ breakeven_at_r=0; trail_method="none"; partials=@(); time_stop_bars=0; reversal_exit_signals=2; reversal_tighten_signals=1; reversal_partial_pct=0.3 }
            $ctx = @{ side="SHORT"; entry=100; risk=10; r_now=0.4; peak=96; current_stop=102; remaining_size=1.0; bars_held=2; signals=1; atr=0 }
            $d = Get-ExitDecision -Policy $pol -Context $ctx
            $d.action | Should Be "partial"
        }
    }

    # 2026-09-02: as policies REAIS (Resolve-ExitPolicy/Get-CurrentTrailingPolicy)
    # agora usam reversal_exit_signals=2 (nao mais 3) -- prova de que o
    # threshold real de producao mudou, nao so a funcao pura isolada.
    Context "Thresholds reais das policies (2026-09-02, causa raiz do 'toma muito stop')" {
        It "Resolve-ExitPolicy standard: reversal_exit_signals=2 (nao mais 3 -- max real observado em producao e' 2)" {
            $p = Resolve-ExitPolicy -TradeType "standard" -Direction "LONG"
            $p.reversal_exit_signals | Should Be 2
            $p.reversal_tighten_signals | Should Be 1
        }
        It "Resolve-ExitPolicy standard/scalp/swing tem reversal_partial_pct definido (opt-in ativo)" {
            (Resolve-ExitPolicy -TradeType "standard" -Direction "LONG").reversal_partial_pct | Should Be 0.3
            (Resolve-ExitPolicy -TradeType "scalp" -Direction "LONG").reversal_partial_pct | Should Be 0.3
            (Resolve-ExitPolicy -TradeType "swing" -Direction "LONG").reversal_partial_pct | Should Be 0.3
        }
        It "Get-CurrentTrailingPolicy (policy 'atual', a mais usada em producao real): reversal_exit_signals=2 + reversal_partial_pct ativo" {
            $p = Get-CurrentTrailingPolicy
            $p.reversal_exit_signals | Should Be 2
            $p.reversal_tighten_signals | Should Be 1
            $p.reversal_partial_pct | Should Be 0.3
        }
    }
}

Describe "Resolve-ExitPolicyGated -- gate validado (uptrend->runner)" {

    It "LONG uptrend + regime bull -> runner" {
        $p = Resolve-ExitPolicyGated -TrendUp $true -Regime "BULL_WEAK" -Direction "LONG"
        $p.selected | Should Be "runner"
        $p.trade_type | Should Be "runner"
    }

    It "LONG downtrend -> atual (runner perde em downtrend)" {
        $p = Resolve-ExitPolicyGated -TrendUp $false -Regime "BULL_WEAK" -Direction "LONG"
        $p.selected | Should Be "atual"
    }

    It "Uptrend MAS regime bear -> atual (gate conservador)" {
        $p = Resolve-ExitPolicyGated -TrendUp $true -Regime "BEAR_WEAK" -Direction "LONG"
        $p.selected | Should Be "atual"
    }

    It "SHORT defere ao atual (achado validado e LONG)" {
        $p = Resolve-ExitPolicyGated -TrendUp $true -Regime "BULL_STRONG" -Direction "SHORT"
        $p.selected | Should Be "atual"
    }
}

Describe "Combo: politica por tipo rodando no harness" {

    It "swing LONG num trade vencedor captura parte do MFE (capture>0)" {
        $script:swingPol = Resolve-ExitPolicy -TradeType "swing" -Direction "LONG"
        $fn = { param($ctx) Get-ExitDecision -Policy $script:swingPol -Context $ctx }
        $entry = @{ side="LONG"; entry_price=100; initial_stop=90; trade_type="swing" }
        $bars = @(
            (_C 100 112 99 110 2),
            (_C 110 125 108 123 2),
            (_C 123 130 118 120 2),
            (_C 120 122 110 112 2)
        )
        $o = Invoke-ExitReplay -Entry $entry -Candles $bars -PolicyFn $fn -MaxBars 4
        $o.r | Should BeGreaterThan 0
        $o.capture_ratio | Should BeGreaterThan 0
    }
}
