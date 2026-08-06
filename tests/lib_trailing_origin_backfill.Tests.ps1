# lib_trailing_origin_backfill.Tests.ps1 -- TDD
#
# Achado real 2026-08-06: ARBUSDT/NEARUSDT/OPUSDT abertas via regime_surf
# ANTES do fix de Register-PositionTrailing/-Origin (commit c0f9f6e) tem
# origin.asset_class="UNKNOWN" gravado -- trailing_stop_monitor.ps1 usa
# isso pra decidir $tuIsFutures, entao NUNCA envia push real de stop pra
# CoinEx-ModifyPositionStopLoss (so atualiza o journal, aparencia de
# progresso sem protecao real mudar na corretora). Backfill corrige o
# registro (so o journal, nunca ordem/posicao real).

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_trailing_origin_backfill.ps1")

Describe "Test-OriginNeedsBackfill" {

    It "origin=null + posicao FUTURES real -> precisa backfill (caso SOONUSDT/PIPPINUSDT)" {
        Test-OriginNeedsBackfill -JournalOrigin $null -IsRealFutures $true | Should Be $true
    }

    It "origin.asset_class=UNKNOWN + posicao FUTURES real -> precisa backfill (caso ARBUSDT/NEARUSDT/OPUSDT)" {
        $origin = [PSCustomObject]@{ asset_class = "UNKNOWN"; trade_style = "UNKNOWN" }
        Test-OriginNeedsBackfill -JournalOrigin $origin -IsRealFutures $true | Should Be $true
    }

    It "origin.asset_class=FUTURES ja correto -> NAO precisa backfill (nao mexe no que ja esta certo)" {
        $origin = [PSCustomObject]@{ asset_class = "FUTURES"; trade_style = "SWING" }
        Test-OriginNeedsBackfill -JournalOrigin $origin -IsRealFutures $true | Should Be $false
    }

    It "posicao NAO e FUTURES real (SPOT de verdade ou ja fechou) -> NAO mexe mesmo com origin=UNKNOWN" {
        $origin = [PSCustomObject]@{ asset_class = "UNKNOWN"; trade_style = "UNKNOWN" }
        Test-OriginNeedsBackfill -JournalOrigin $origin -IsRealFutures $false | Should Be $false
    }

    It "origin.asset_class diz SPOT mas e FUTURES real (dado contraditorio) -> corrige, confia na corretora" {
        $origin = [PSCustomObject]@{ asset_class = "SPOT"; trade_style = "SWING" }
        Test-OriginNeedsBackfill -JournalOrigin $origin -IsRealFutures $true | Should Be $true
    }

    It "origin como STRING JSON crua (round-trip Supabase) -- ainda detecta UNKNOWN corretamente" {
        $originStr = '{"asset_class":"UNKNOWN","trade_style":"UNKNOWN"}'
        Test-OriginNeedsBackfill -JournalOrigin $originStr -IsRealFutures $true | Should Be $true
    }

    It "origin como STRING invalida/corrompida -> trata como precisa backfill (fail-safe)" {
        Test-OriginNeedsBackfill -JournalOrigin "nao-e-json{{{" -IsRealFutures $true | Should Be $true
    }
}

Describe "Resolve-BackfilledOrigin" {

    It "origin=null -> default FUTURES/SWING" {
        $r = Resolve-BackfilledOrigin -JournalOrigin $null
        $r.asset_class | Should Be "FUTURES"
        $r.trade_style | Should Be "SWING"
    }

    It "origin com trade_style=SCALP ja valido -- preserva (nao forca SWING por cima de dado bom)" {
        $origin = [PSCustomObject]@{ asset_class = "UNKNOWN"; trade_style = "SCALP" }
        $r = Resolve-BackfilledOrigin -JournalOrigin $origin
        $r.asset_class | Should Be "FUTURES"
        $r.trade_style | Should Be "SCALP"
    }

    It "origin com trade_style=UNKNOWN -- fallback SWING (nao propaga o valor invalido)" {
        $origin = [PSCustomObject]@{ asset_class = "UNKNOWN"; trade_style = "UNKNOWN" }
        $r = Resolve-BackfilledOrigin -JournalOrigin $origin
        $r.trade_style | Should Be "SWING"
    }

    It "origin com trade_style invalido/corrompido (ex: BANANA) -- fallback SWING, nao propaga lixo" {
        $origin = [PSCustomObject]@{ asset_class = "UNKNOWN"; trade_style = "BANANA" }
        $r = Resolve-BackfilledOrigin -JournalOrigin $origin
        $r.trade_style | Should Be "SWING"
    }
}
