# lib_trailing_stop_reconcile.Tests.ps1 -- TDD
#
# Achado real 2026-08-06: ARBUSDT/NEARUSDT/OPUSDT tiveram origin corrigido
# (backfill) DEPOIS de varios ciclos com origin=UNKNOWN, onde o motor ja
# calculava e gravava stopCurrent no journal mas NUNCA empurrava pra
# CoinEx (tuIsFutures era false, pulava o push). journal "achava" que
# tinha avancado, entao o proximo ciclo comparava contra esse valor
# adiantado e decidia "stop_calculado_nao_melhora" -- corretora ficava
# presa no valor antigo pra sempre. Confirmado real: SL na CoinEx
# (0.084039 ARBUSDT) != journal (0.08067069).

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_trailing_stop_reconcile.ps1")

Describe "Test-JournalStopAheadOfExchange" {

    It "SHORT: journal MAIS APERTADO que o real (nunca enviado) -> precisa reconciliar (caso real ARBUSDT)" {
        # journal=0.08067069 (calculado, nunca enviado), real=0.084039 (ainda no valor antigo)
        Test-JournalStopAheadOfExchange -Side "SHORT" -JournalStop 0.08067069 -RealStop 0.084039 | Should Be $true
    }

    It "SHORT: journal e real IGUAIS -> nao precisa reconciliar (ja sincronizado)" {
        Test-JournalStopAheadOfExchange -Side "SHORT" -JournalStop 0.084039 -RealStop 0.084039 | Should Be $false
    }

    It "SHORT: journal MENOS apertado que o real (real ja mais protegido) -> nao mexe (nunca afrouxa)" {
        Test-JournalStopAheadOfExchange -Side "SHORT" -JournalStop 0.09 -RealStop 0.084039 | Should Be $false
    }

    It "LONG: journal MAIS ALTO que o real (nunca enviado) -> precisa reconciliar" {
        Test-JournalStopAheadOfExchange -Side "LONG" -JournalStop 60200 -RealStop 60000 | Should Be $true
    }

    It "LONG: journal e real IGUAIS -> nao precisa reconciliar" {
        Test-JournalStopAheadOfExchange -Side "LONG" -JournalStop 60000 -RealStop 60000 | Should Be $false
    }

    It "LONG: journal MAIS BAIXO que o real -> nao mexe (nunca afrouxa)" {
        Test-JournalStopAheadOfExchange -Side "LONG" -JournalStop 59000 -RealStop 60000 | Should Be $false
    }

    It "RealStop=0 (sem SL confirmado na corretora) -> nao mexe, fail-safe" {
        Test-JournalStopAheadOfExchange -Side "SHORT" -JournalStop 0.08 -RealStop 0 | Should Be $false
    }

    It "case-insensitive no Side (short minusculo funciona igual)" {
        Test-JournalStopAheadOfExchange -Side "short" -JournalStop 0.08067069 -RealStop 0.084039 | Should Be $true
    }
}
