# lib_coin_exposure_cap.Tests.ps1 -- Pester 3.x
# TDD 2026-06-24: bloqueia trades GIGANTES / acumulacao por moeda.
# Causa raiz: dedup olhava ledger local (gem_safety_state) que desviava da realidade ->
# PAXG (entrou por recovery, fora do ledger) foi re-comprado ate $1023 (45% da carteira).
# Test-CoinExposureCap olha o SALDO REAL: bloqueia re-entrada + cap % por moeda.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_gem_safety.ps1")

Describe "Test-CoinExposureCap - bloqueia acumulacao por moeda" {
    It "Ja segura posicao relevante -> bloqueia re-entrada" {
        $r = Test-CoinExposureCap -HeldUsd 533 -TradeUsd 18 -PortfolioUsd 2250
        $r.allowed | Should Be $false
        $r.reason | Should Be "ja_posicionado"
    }
    It "Projetado acima do cap por moeda -> bloqueia (trade gigante)" {
        # held 0 mas trade unico de 300 em portfolio 2250 = 13% > cap 10%
        $r = Test-CoinExposureCap -HeldUsd 0 -TradeUsd 300 -PortfolioUsd 2250 -MaxPerCoinPct 10
        $r.allowed | Should Be $false
        $r.reason | Should Be "cap_por_moeda"
    }
    It "Sem holding + trade pequeno dentro do cap -> permite" {
        $r = Test-CoinExposureCap -HeldUsd 0 -TradeUsd 18 -PortfolioUsd 2250 -MaxPerCoinPct 10
        $r.allowed | Should Be $true
    }
    It "Holding minusculo (poeira < ReentryBlockUsd) -> permite (nao trava por poeira)" {
        $r = Test-CoinExposureCap -HeldUsd 0.5 -TradeUsd 18 -PortfolioUsd 2250 -ReentryBlockUsd 5
        $r.allowed | Should Be $true
    }
    It "Portfolio invalido -> fail-safe permite (nao trava por dado ruim)" {
        (Test-CoinExposureCap -HeldUsd 0 -TradeUsd 18 -PortfolioUsd 0).allowed | Should Be $true
    }
}
