# lib_exit_backtest.Tests.ps1 -- TDD do harness de replay de saidas.
# Simulador PURO: dada uma entrada + candles pos-entrada + funcao de politica,
# simula barra-a-barra e mede o desfecho (R, MFE, MAE, capture, motivo).
# Disciplina-primeiro: mede o trailing ATUAL antes de inovar (escolha do user).
#
# Convencoes de realismo (anti-otimismo, Lopez de Prado):
#  - dentro da barra, STOP e checado ANTES de favoravel (adverso primeiro).
#  - gap: se a barra abre alem do stop, preenche no open (nao no stop).
#  - R = (exit-entry)/risk (LONG); risk = entry - initial_stop.
#  - capture_ratio = R_realizado / MFE_R (quanto do melhor a gente manteve).

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_exit_backtest.ps1")

# politica "buy and hold" (nunca mexe stop, nunca sai): isola comportamento do sim
$HoldPolicy = { param($ctx) @{ action = "hold"; new_stop = $null; size_pct = 0 } }

function _C { param($o,$h,$l,$c,$v=1000) [PSCustomObject]@{ open=$o; high=$h; low=$l; close=$c; volume=$v } }

Describe "Invoke-ExitReplay -- LONG basico" {

    It "Time-exit (stop nunca tocado): R, MFE e capture corretos" {
        $entry = @{ side="LONG"; entry_price=100; initial_stop=90 }
        $bars = @( (_C 100 110 99 108), (_C 108 120 107 118) )
        $o = Invoke-ExitReplay -Entry $entry -Candles $bars -PolicyFn $HoldPolicy -MaxBars 2
        $o.exit_reason | Should Be "time"
        [math]::Round($o.r,2)      | Should Be 1.8   # (118-100)/10
        [math]::Round($o.mfe_r,2)  | Should Be 2.0   # (120-100)/10
        [math]::Round($o.mae_r,2)  | Should Be 0.1   # (100-99)/10
        [math]::Round($o.capture_ratio,2) | Should Be 0.9
    }

    It "Stop hit -> R=-1, motivo=stop" {
        $entry = @{ side="LONG"; entry_price=100; initial_stop=90 }
        $bars = @( (_C 100 105 95 102), (_C 101 103 88 92) )
        $o = Invoke-ExitReplay -Entry $entry -Candles $bars -PolicyFn $HoldPolicy -MaxBars 5
        $o.exit_reason | Should Be "stop"
        [math]::Round($o.r,2) | Should Be -1
    }

    It "Gap abaixo do stop preenche no open (mais conservador que o stop)" {
        $entry = @{ side="LONG"; entry_price=100; initial_stop=90 }
        $bars = @( (_C 85 86 80 84) )   # abre 85 < stop 90 -> fill 85
        $o = Invoke-ExitReplay -Entry $entry -Candles $bars -PolicyFn $HoldPolicy -MaxBars 5
        $o.exit_reason | Should Be "stop"
        [math]::Round($o.r,2) | Should Be -1.5   # (85-100)/10
    }
}

Describe "Invoke-ExitReplay -- politica move stop p/ breakeven" {

    It "Sobe +1R, move p/ BE, reverte -> sai em BE (R=0)" {
        $entry = @{ side="LONG"; entry_price=100; initial_stop=90 }
        $bePolicy = {
            param($ctx)
            if ($ctx.r_now -ge 1) { return @{ action="hold"; new_stop=$ctx.entry; size_pct=0 } }
            @{ action="hold"; new_stop=$null; size_pct=0 }
        }
        $bars = @( (_C 100 112 99 111), (_C 108 109 100 101) )
        $o = Invoke-ExitReplay -Entry $entry -Candles $bars -PolicyFn $bePolicy -MaxBars 5
        $o.exit_reason | Should Be "stop"
        [math]::Round($o.r,2) | Should Be 0.0
    }
}

Describe "Invoke-ExitReplay -- saida parcial (R combinado)" {

    It "50% @ +2R + restante no BE = R combinado 1.1" {
        $entry = @{ side="LONG"; entry_price=100; initial_stop=90 }
        $partPolicy = {
            param($ctx)
            if ($ctx.r_now -ge 2 -and $ctx.remaining_size -ge 0.99) {
                return @{ action="partial"; new_stop=$ctx.entry; size_pct=0.5 }
            }
            @{ action="hold"; new_stop=$null; size_pct=0 }
        }
        $bars = @( (_C 100 125 101 122), (_C 120 121 100 100) )
        $o = Invoke-ExitReplay -Entry $entry -Candles $bars -PolicyFn $partPolicy -MaxBars 5
        # 0.5 * 2.2 (parcial @122) + 0.5 * 0 (BE) = 1.1
        [math]::Round($o.r,2) | Should Be 1.1
    }
}

Describe "Invoke-ExitReplay -- SHORT espelhado" {

    It "SHORT favoravel (preco cai) ate time-exit" {
        $entry = @{ side="SHORT"; entry_price=100; initial_stop=110 }  # risk 10
        $bars = @( (_C 100 101 90 92), (_C 92 93 80 82) )
        $o = Invoke-ExitReplay -Entry $entry -Candles $bars -PolicyFn $HoldPolicy -MaxBars 2
        $o.exit_reason | Should Be "time"
        [math]::Round($o.r,2)     | Should Be 1.8   # (100-82)/10
        [math]::Round($o.mfe_r,2) | Should Be 2.0   # (100-80)/10
    }

    It "SHORT stop hit (preco sobe) -> R=-1" {
        $entry = @{ side="SHORT"; entry_price=100; initial_stop=110 }
        $bars = @( (_C 100 112 99 108) )   # high 112 >= stop 110
        $o = Invoke-ExitReplay -Entry $entry -Candles $bars -PolicyFn $HoldPolicy -MaxBars 5
        $o.exit_reason | Should Be "stop"
        [math]::Round($o.r,2) | Should Be -1
    }
}

Describe "Get-ExitReplayStats -- agregacao" {

    It "Agrega n, win_rate, avg_r, avg_capture" {
        $outs = @(
            [PSCustomObject]@{ r=2.0;  mfe_r=2.5; capture_ratio=0.8 },
            [PSCustomObject]@{ r=-1.0; mfe_r=0.5; capture_ratio=0.0 },
            [PSCustomObject]@{ r=1.0;  mfe_r=2.0; capture_ratio=0.5 }
        )
        $s = Get-ExitReplayStats -Outcomes $outs
        $s.n | Should Be 3
        [math]::Round($s.win_rate,2) | Should Be 0.67
        [math]::Round($s.avg_r,3)    | Should Be 0.667
        [math]::Round($s.avg_capture,3) | Should Be 0.433
    }

    It "Lista vazia -> n=0 sem quebrar" {
        $s = Get-ExitReplayStats -Outcomes @()
        $s.n | Should Be 0
    }
}
