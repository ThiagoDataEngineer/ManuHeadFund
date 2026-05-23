# triagem_thresholds_override.Tests.ps1
# TDD strict para Get-TriagemThresholds + _Compute-Tier recalibrado.
#
# Bug raiz (journal/cascade_diagnose_2026_05_15.md):
# - Scanner formula: |change%| * log10(vol/1000) -> range empirico 5-35 em mainstream.
# - Triagem threshold antigo (50/60/75) era calibrado para escala 0-100 que NUNCA
#   eh produzida pelo scanner real -> 100% Tier D em 30+ ciclos observados.
#
# Fix: thresholds OPT-IN via $global:TRIAGEM_THRESHOLDS, recalibrados para escala
# empirica (D<15 ruido, B>=25 movers reais, A>=40 breakouts fortes).
#
# CONTRATO Get-TriagemThresholds (funcao pura):
#   - Sem override                       -> @{D=50; B=60; A=75} (compat antigo)
#   - $global:TRIAGEM_THRESHOLDS valido  -> retorna override
#   - Hashtable parcial (so D)           -> mistura override + default
#   - Hashtable invalida (nao @{})       -> fallback default
#   - Valores fora 1..100                -> fallback default
#   - D >= B ou B >= A                   -> fallback default (incoerente)
#
# UTF-8 BOM, Pester 3.x

# Extrai Get-TriagemThresholds e _Compute-Tier sem rodar triagem inteira
# (evita dependencia de Invoke-GroqJson/etc).
$triagemPath = "$PSScriptRoot\..\agents\triagem_agent.ps1"
$content = Get-Content $triagemPath -Raw

if ($content -match '(?ms)(^function Get-TriagemThresholds\s*\{.*?^\})') {
    Invoke-Expression $matches[1]
}
if ($content -match '(?ms)(^function _Compute-Tier\s*\{.*?^\})') {
    Invoke-Expression $matches[1]
}

# DOW_FAVORAVEL precisa estar definido para _Compute-Tier funcionar
if (-not (Get-Variable -Name TRIAGEM_DOW_FAVORAVEL -ErrorAction SilentlyContinue)) {
    $TRIAGEM_DOW_FAVORAVEL = @("Monday","Tuesday","Wednesday")
}

function _ResetTriagemThresholds {
    if (Test-Path variable:global:TRIAGEM_THRESHOLDS) {
        Remove-Variable -Name TRIAGEM_THRESHOLDS -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe "Get-TriagemThresholds - override OPT-IN para escala empirica" {

    BeforeEach { _ResetTriagemThresholds }
    AfterEach  { _ResetTriagemThresholds }

    It "retorna default 50/60/75 quando sem override" {
        $t = Get-TriagemThresholds
        $t.D | Should Be 50
        $t.B | Should Be 60
        $t.A | Should Be 75
    }

    It "retorna override completo quando setado" {
        $global:TRIAGEM_THRESHOLDS = @{ D = 15; B = 25; A = 40 }
        $t = Get-TriagemThresholds
        $t.D | Should Be 15
        $t.B | Should Be 25
        $t.A | Should Be 40
    }

    It "mistura parcial override + default quando hashtable so tem D" {
        $global:TRIAGEM_THRESHOLDS = @{ D = 20 }
        $t = Get-TriagemThresholds
        $t.D | Should Be 20
        $t.B | Should Be 60   # default
        $t.A | Should Be 75   # default
    }

    It "fallback default quando override nao eh hashtable" {
        $global:TRIAGEM_THRESHOLDS = "invalid"
        $t = Get-TriagemThresholds
        $t.D | Should Be 50
        $t.B | Should Be 60
        $t.A | Should Be 75
    }

    It "fallback default quando D >= B (incoerente)" {
        $global:TRIAGEM_THRESHOLDS = @{ D = 30; B = 25; A = 40 }
        $t = Get-TriagemThresholds
        $t.D | Should Be 50
    }

    It "fallback default quando B >= A (incoerente)" {
        $global:TRIAGEM_THRESHOLDS = @{ D = 15; B = 40; A = 35 }
        $t = Get-TriagemThresholds
        $t.D | Should Be 50
    }

    It "fallback default quando valor fora 1..100" {
        $global:TRIAGEM_THRESHOLDS = @{ D = -5; B = 25; A = 40 }
        $t = Get-TriagemThresholds
        $t.D | Should Be 50
    }

    It "fallback default quando valor > 100" {
        $global:TRIAGEM_THRESHOLDS = @{ D = 15; B = 25; A = 150 }
        $t = Get-TriagemThresholds
        $t.A | Should Be 75
    }
}

Describe "_Compute-Tier - integracao com Get-TriagemThresholds" {

    BeforeEach { _ResetTriagemThresholds }
    AfterEach  { _ResetTriagemThresholds }

    It "retorna D quando score < default D=50 (sem override)" {
        $tier = _Compute-Tier -Score 35 -MacroBias "BULLISH" -DayOfWeek "Monday" -MarketTier "alt"
        $tier | Should Be "D"
    }

    It "retorna B quando score=30 + override D=15/B=25/A=40 (recalibrado)" {
        $global:TRIAGEM_THRESHOLDS = @{ D = 15; B = 25; A = 40 }
        $tier = _Compute-Tier -Score 30 -MacroBias "BULLISH" -DayOfWeek "Monday" -MarketTier "alt"
        $tier | Should Be "B"
    }

    It "retorna A quando score=45 + override D=15/B=25/A=40 + macro+dow OK" {
        $global:TRIAGEM_THRESHOLDS = @{ D = 15; B = 25; A = 40 }
        $tier = _Compute-Tier -Score 45 -MacroBias "BULLISH" -DayOfWeek "Monday" -MarketTier "alt"
        $tier | Should Be "A"
    }

    It "retorna D quando score=10 + override D=15 (ruido)" {
        $global:TRIAGEM_THRESHOLDS = @{ D = 15; B = 25; A = 40 }
        $tier = _Compute-Tier -Score 10 -MacroBias "BULLISH" -DayOfWeek "Monday" -MarketTier "alt"
        $tier | Should Be "D"
    }

    It "BEARISH continua exigindo score >= B mesmo com override" {
        $global:TRIAGEM_THRESHOLDS = @{ D = 15; B = 25; A = 40 }
        $tier = _Compute-Tier -Score 20 -MacroBias "BEARISH" -DayOfWeek "Monday" -MarketTier "alt"
        $tier | Should Be "D"
    }

    It "Thursday+alt nao chega a Tier A mesmo com override + score alto" {
        $global:TRIAGEM_THRESHOLDS = @{ D = 15; B = 25; A = 40 }
        $tier = _Compute-Tier -Score 50 -MacroBias "BULLISH" -DayOfWeek "Thursday" -MarketTier "alt"
        # nao deve ser A (penalidade leve), mas deve ser B (score 50 >= 25)
        $tier | Should Be "B"
    }
}