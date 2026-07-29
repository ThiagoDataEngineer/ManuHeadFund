# lib_regime_rr_calibration.Tests.ps1 -- TDD pra calibragem autonoma de R:R
# minimo por regime+direcao, baseada em edge REAL medido (mce_counterfactual_agg).
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..
. ".\agents\lib_regime_rr_calibration.ps1"

Describe "Get-RegimeRRCalibration (pura)" {

    It "n abaixo do minimo (20) -- SEM_EDGE_MEDIDO, mantem default 1:5" {
        $r = Get-RegimeRRCalibration -Regime "NEUTRO" -Direction "SHORT" -N 10 -HitRate 0.95
        $r.rr_min | Should Be 5.0
        $r.tier   | Should Be "SEM_EDGE_MEDIDO"
    }

    It "hit_rate >= 85% com n>=20 -- EDGE_FORTE, R:R reduzido pra 1:3 (caso real: NEUTRO|SHORT hit_rate=87.5% n=24)" {
        $r = Get-RegimeRRCalibration -Regime "NEUTRO" -Direction "SHORT" -N 24 -HitRate 0.875
        $r.rr_min | Should Be 3.0
        $r.tier   | Should Be "EDGE_FORTE"
    }

    It "hit_rate entre 60-85% com n>=20 -- EDGE_MODERADO, R:R reduzido pra 1:4 (caso real: BEAR|LONG hit_rate=67.7% n=62)" {
        $r = Get-RegimeRRCalibration -Regime "BEAR" -Direction "LONG" -N 62 -HitRate 0.677
        $r.rr_min | Should Be 4.0
        $r.tier   | Should Be "EDGE_MODERADO"
    }

    It "hit_rate abaixo de 60% mesmo com n>=20 -- mantem default 1:5 (dado real, mas sem edge suficiente)" {
        $r = Get-RegimeRRCalibration -Regime "BULL" -Direction "SHORT" -N 40 -HitRate 0.45
        $r.rr_min | Should Be 5.0
        $r.tier   | Should Be "SEM_EDGE_MEDIDO"
    }

    It "N=0 (sem nenhum dado) -- SEM_EDGE_MEDIDO, default preservado" {
        $r = Get-RegimeRRCalibration -Regime "UNKNOWN" -Direction "LONG" -N 0 -HitRate 0.0
        $r.rr_min | Should Be 5.0
        $r.tier   | Should Be "SEM_EDGE_MEDIDO"
    }

    It "fronteira exata: hit_rate=0.85 conta como EDGE_FORTE (>=, nao >)" {
        $r = Get-RegimeRRCalibration -Regime "NEUTRO" -Direction "SHORT" -N 25 -HitRate 0.85
        $r.tier | Should Be "EDGE_FORTE"
    }

    It "fronteira exata: hit_rate=0.60 conta como EDGE_MODERADO (>=, nao >)" {
        $r = Get-RegimeRRCalibration -Regime "BEAR" -Direction "LONG" -N 25 -HitRate 0.60
        $r.tier | Should Be "EDGE_MODERADO"
    }

    It "fronteira exata: n=20 (MinSampleSize) ja conta como amostra valida" {
        $r = Get-RegimeRRCalibration -Regime "NEUTRO" -Direction "SHORT" -N 20 -HitRate 0.90
        $r.tier | Should Be "EDGE_FORTE"
    }

    It "DefaultRR customizado e respeitado quando SEM_EDGE_MEDIDO" {
        $r = Get-RegimeRRCalibration -Regime "BULL" -Direction "LONG" -N 5 -HitRate 0.5 -DefaultRR 6.0
        $r.rr_min | Should Be 6.0
    }
}

Describe "Resolve-RegimeRRCalibration -- wrapper I/O (fail-soft)" {

    It "sem _Get-LearningFromSupabase disponivel -- cai no default sem lancar" {
        if (Get-Command _Get-LearningFromSupabase -ErrorAction SilentlyContinue) {
            Remove-Item function:_Get-LearningFromSupabase -ErrorAction SilentlyContinue
        }
        { $script:__r = Resolve-RegimeRRCalibration -Regime "NEUTRO" -Direction "SHORT" } | Should Not Throw
        $script:__r.rr_min | Should Be 5.0
        $script:__r.tier   | Should Be "SEM_EDGE_MEDIDO"
    }

    It "agrega multiplas linhas (gates diferentes) do mesmo regime+direction ponderando por n" {
        Set-Item function:_Get-LearningFromSupabase -Value {
            param($Table, $Filter)
            return @(
                [PSCustomObject]@{ regime="NEUTRO"; direction="SHORT"; gate="breadth_short_blocked"; n=18; hit_rate=0.944 },
                [PSCustomObject]@{ regime="NEUTRO"; direction="SHORT"; gate="pump_short_blocked"; n=6; hit_rate=0.50 }
            )
        }
        # weighted: (18*0.944 + 6*0.50) / 24 = (16.992+3.0)/24 = 0.83133...
        $r = Resolve-RegimeRRCalibration -Regime "NEUTRO" -Direction "SHORT"
        $r.tier | Should Be "EDGE_MODERADO"
        Remove-Item function:_Get-LearningFromSupabase -ErrorAction SilentlyContinue
    }

    It "excecao dentro do wrapper de I/O nunca propaga (fail-soft real)" {
        Set-Item function:_Get-LearningFromSupabase -Value { param($Table, $Filter) throw "Supabase indisponivel" }
        { $script:__r2 = Resolve-RegimeRRCalibration -Regime "BEAR" -Direction "LONG" } | Should Not Throw
        $script:__r2.rr_min | Should Be 5.0
        Remove-Item function:_Get-LearningFromSupabase -ErrorAction SilentlyContinue
    }

    It "tabela vazia (Supabase disponivel mas sem linhas) -- default preservado" {
        Set-Item function:_Get-LearningFromSupabase -Value { param($Table, $Filter) return @() }
        $r = Resolve-RegimeRRCalibration -Regime "CAPITULACAO" -Direction "LONG"
        $r.rr_min | Should Be 5.0
        $r.tier   | Should Be "SEM_EDGE_MEDIDO"
        Remove-Item function:_Get-LearningFromSupabase -ErrorAction SilentlyContinue
    }
}
