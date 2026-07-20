# lib_trailing_walkforward.Tests.ps1 -- TDD da camada de validacao.
# Walk-forward multi-ativo + teste PAREADO (mesma entrada -> todas as politicas,
# delta isola o efeito da SAIDA controlando qualidade da entrada) + bootstrap CI.
# Disciplina do projeto: nada vai live sem delta robusto vs ATUAL.

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_exit_backtest.ps1")
. (Join-Path $agentsDir "lib_trailing_policy.ps1")
. (Join-Path $agentsDir "lib_trailing_baseline.ps1")
. (Join-Path $agentsDir "lib_trailing_walkforward.ps1")

function _MkCandles {
    param([int]$N, [double]$Start=100, [double]$Drift=0.5, [double]$Range=2)
    $bars = @()
    $p = $Start
    for ($i = 0; $i -lt $N; $i++) {
        $o = $p
        $c = $p + $Drift
        $h = ([math]::Max($o,$c)) + $Range
        $l = ([math]::Min($o,$c)) - $Range
        $bars += [PSCustomObject]@{ ts=(Get-Date).AddDays($i); open=$o; high=$h; low=$l; close=$c; volume=1000; atr=0 }
        $p = $c
    }
    return $bars
}

Describe "Invoke-WalkForwardExit -- pareado multi-ativo" {

    It "Roda N entradas por ativo, politicas pareadas (mesma contagem)" {
        $map = @{
            "AAA" = _MkCandles -N 120 -Drift 0.8
            "BBB" = _MkCandles -N 120 -Drift -0.3
        }
        $res = Invoke-WalkForwardExit -CandlesMap $map -PolicyNames @("atual","runner","scalp") -EntryFrequency 40 -HoldBars 30

        $res.atual.Count  | Should BeGreaterThan 0
        $res.runner.Count | Should Be $res.atual.Count   # pareado
        $res.scalp.Count  | Should Be $res.atual.Count
    }

    It "Ignora ativo curto demais sem quebrar" {
        $map = @{
            "AAA" = _MkCandles -N 120 -Drift 0.8
            "TINY" = _MkCandles -N 10
        }
        $res = Invoke-WalkForwardExit -CandlesMap $map -PolicyNames @("atual","runner") -EntryFrequency 40 -HoldBars 30
        $res.atual.Count | Should BeGreaterThan 0
    }
}

Describe "Get-PairedDelta -- delta + bootstrap" {

    It "Calcula mean_delta, win_rate, n corretos" {
        $base = @(
            [PSCustomObject]@{ r=1.0 }, [PSCustomObject]@{ r=1.0 }, [PSCustomObject]@{ r=1.0 }
        )
        $cand = @(
            [PSCustomObject]@{ r=2.0 }, [PSCustomObject]@{ r=2.0 }, [PSCustomObject]@{ r=0.0 }
        )
        $d = Get-PairedDelta -BaselineOutcomes $base -CandidateOutcomes $cand -BootstrapIters 200 -Seed 7
        $d.n | Should Be 3
        [math]::Round($d.mean_delta,3) | Should Be 0.333   # (1+1-1)/3
        [math]::Round($d.win_rate,3)   | Should Be 0.667   # 2 de 3 deltas > 0
    }

    It "Bootstrap CI presente e ci_low <= mean <= ci_high" {
        $base = @(1..20 | ForEach-Object { [PSCustomObject]@{ r=0.0 } })
        $cand = @(1..20 | ForEach-Object { [PSCustomObject]@{ r=0.5 } })   # candidate sempre +0.5
        $d = Get-PairedDelta -BaselineOutcomes $base -CandidateOutcomes $cand -BootstrapIters 500 -Seed 7
        [math]::Round($d.mean_delta,2) | Should Be 0.5
        $d.ci_low  | Should Not BeNullOrEmpty
        $d.ci_high | Should Not BeNullOrEmpty
        ($d.ci_low -le $d.mean_delta)  | Should Be $true
        ($d.mean_delta -le $d.ci_high) | Should Be $true
    }

    It "Block bootstrap: ROBUST com edge forte; respeita blocos" {
        $base = @(1..40 | ForEach-Object { [PSCustomObject]@{ r=0.0 } })
        $cand = @(1..40 | ForEach-Object { [PSCustomObject]@{ r=0.5 } })
        $keys = @(1..40 | ForEach-Object { if ($_ -le 20) { "A" } else { "B" } })
        $d = Get-PairedDeltaBlocked -BaselineOutcomes $base -CandidateOutcomes $cand -BlockKeys $keys -BootstrapIters 500 -Seed 7
        $d.n_blocks | Should Be 2
        [math]::Round($d.mean_delta,2) | Should Be 0.5
        $d.verdict | Should Be "ROBUST"
    }

    It "Verdict ROBUST quando ci_low > 0; FRAGIL quando cruza 0" {
        $base = @(1..30 | ForEach-Object { [PSCustomObject]@{ r=0.0 } })
        $candStrong = @(1..30 | ForEach-Object { [PSCustomObject]@{ r=0.4 } })
        $dStrong = Get-PairedDelta -BaselineOutcomes $base -CandidateOutcomes $candStrong -BootstrapIters 500 -Seed 7
        $dStrong.verdict | Should Be "ROBUST"

        # candidate igual ao baseline -> delta 0 -> nao robusto
        $candFlat = @(1..30 | ForEach-Object { [PSCustomObject]@{ r=0.0 } })
        $dFlat = Get-PairedDelta -BaselineOutcomes $base -CandidateOutcomes $candFlat -BootstrapIters 500 -Seed 7
        $dFlat.verdict | Should Not Be "ROBUST"
    }
}
