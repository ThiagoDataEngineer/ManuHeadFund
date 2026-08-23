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

Describe "Test-JournalStopAheadOfExchange -- piso de sanidade (2026-08-23)" {
    # Achado real: CoinEx-PlaceMultiExitLadder escrevia um 2o SL na corretora
    # usando o template generico (-50% do entry), sobrepondo o SL correto.
    # Sem piso, essa funcao reconciliava o journal pro valor errado (achando
    # que era "atraso legitimo"). RENDERUSDT real: entry=1.5824, journal
    # apertado corretamente ate 1.57162 (preco tinha subido ate peak 1.6015),
    # SL do ladder bugado ~50% abaixo = ~0.79 (nao literalmente visto no log,
    # mas o SL real reportado pelo trailing monitor apareceu como 1.4623 --
    # ja um valor intermediario, o pior caso puro (-50%) e ainda mais extremo).

    It "LONG: gap pequeno (atraso legitimo, 2%) -- ainda reconcilia (comportamento pre-existente)" {
        # journal=60200 (calculado, nunca enviado), real=60000 (valor antigo) -- gap=0.33%
        Test-JournalStopAheadOfExchange -Side "LONG" -JournalStop 60200 -RealStop 60000 | Should Be $true
    }

    It "LONG: gap ENORME (caso real do bug -- SL do ladder a -50% do entry) -- RECUSA reconciliar" {
        # journal=1.57162 (apertado corretamente), real=0.79 (SL bugado do ladder, -50% do entry ~1.58)
        # gap = |1.57162 - 0.79| / 1.57162 = ~49.7%, bem acima do piso 20%
        Test-JournalStopAheadOfExchange -Side "LONG" -JournalStop 1.57162 -RealStop 0.79 | Should Be $false
    }

    It "LONG: gap no limiar exato (20%) -- ainda reconcilia (fronteira inclusiva)" {
        # journal=100, real=80 -- gap exato 20%
        Test-JournalStopAheadOfExchange -Side "LONG" -JournalStop 100 -RealStop 80 | Should Be $true
    }

    It "LONG: gap logo acima do limiar (20.01%) -- recusa" {
        Test-JournalStopAheadOfExchange -Side "LONG" -JournalStop 100 -RealStop 79.98 | Should Be $false
    }

    It "SHORT: gap ENORME (espelho do caso LONG) -- recusa reconciliar" {
        # journal=0.08067069 (apertado), real=0.16 (SL bugado bem mais frouxo, dobro)
        Test-JournalStopAheadOfExchange -Side "SHORT" -JournalStop 0.08067069 -RealStop 0.16 | Should Be $false
    }

    It "MaxSanityGapPct=0 desativa o piso -- reconcilia mesmo com gap enorme (opt-out explicito)" {
        Test-JournalStopAheadOfExchange -Side "LONG" -JournalStop 1.57162 -RealStop 0.79 -MaxSanityGapPct 0 | Should Be $true
    }

    It "MaxSanityGapPct customizado (0.05 = 5%) -- gap de 10% agora recusa" {
        # journal=100, real=90 -- gap=10%, acima do limiar customizado 5%
        Test-JournalStopAheadOfExchange -Side "LONG" -JournalStop 100 -RealStop 90 -MaxSanityGapPct 0.05 | Should Be $false
    }

    It "gap grande mas na direcao 'nunca afrouxa' (real MAIS protegido) -- continua recusando por esse motivo, nao pelo piso" {
        # journal=59000, real=60000 (real ja mais protegido) -- ja seria $false antes do piso existir
        Test-JournalStopAheadOfExchange -Side "LONG" -JournalStop 59000 -RealStop 60000 | Should Be $false
    }
}

Describe "Get-JournalStopSanityGap" {
    It "calcula gap fracionario correto (caso real do bug, LONG)" {
        $gap = Get-JournalStopSanityGap -JournalStop 1.57162 -RealStop 0.79
        [math]::Round($gap, 3) | Should Be 0.497
    }

    It "gap zero quando journal e real sao iguais" {
        Get-JournalStopSanityGap -JournalStop 100 -RealStop 100 | Should Be 0
    }

    It "JournalStop<=0 retorna 0 (fail-safe, evita divisao por zero)" {
        Get-JournalStopSanityGap -JournalStop 0 -RealStop 50 | Should Be 0
    }

    It "gap e sempre positivo (abs), independente de qual lado e maior" {
        $gapUp   = Get-JournalStopSanityGap -JournalStop 100 -RealStop 80
        $gapDown = Get-JournalStopSanityGap -JournalStop 80  -RealStop 100
        $gapUp   | Should Be 0.2
        [math]::Round($gapDown, 2) | Should Be 0.25
    }
}
