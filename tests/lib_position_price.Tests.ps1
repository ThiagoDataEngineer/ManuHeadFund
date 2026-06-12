# lib_position_price.Tests.ps1 -- Resolucao de preco quando mark_price=0 (API bug
# comum em micro-caps CoinEx). Antes o watcher pulava a gestao (posicao sem stop).
# Pester 3.x. PS 5.1. Funcoes puras, deterministicas.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_position_price.ps1")

Describe "Resolve-MarkPrice - fallback mark=0 -> ticker last" {
    It "mark valido (>0): usa o mark" {
        (Resolve-MarkPrice -Mark 0.021 -TickerLast 0.020) | Should Be 0.021
    }
    It "mark=0: cai para o ticker last" {
        (Resolve-MarkPrice -Mark 0 -TickerLast 0.020781) | Should Be 0.020781
    }
    It "mark negativo: cai para o ticker last" {
        (Resolve-MarkPrice -Mark -1 -TickerLast 0.01781) | Should Be 0.01781
    }
    It "mark=0 E ticker=0: retorna 0 (sem preco valido -> caller pula)" {
        (Resolve-MarkPrice -Mark 0 -TickerLast 0) | Should Be 0
    }
    It "mark=0 e ticker negativo/invalido: retorna 0" {
        (Resolve-MarkPrice -Mark 0 -TickerLast -5) | Should Be 0
    }
}

Describe "Get-PositionPnlPct - pnl baseado em preco (price-based, sem leverage)" {
    It "LONG no lucro" {
        [math]::Round((Get-PositionPnlPct -Price 0.022 -Entry 0.020 -Side "long"), 6) | Should Be 10
    }
    It "LONG no prejuizo (MONUSDT real: -3.16%)" {
        $p = Get-PositionPnlPct -Price 0.020781 -Entry 0.021459 -Side "long"
        [math]::Round($p, 2) | Should Be -3.16
    }
    It "LONG no prejuizo (BABYUSDT real: -6.62%)" {
        $p = Get-PositionPnlPct -Price 0.01781 -Entry 0.019072 -Side "long"
        [math]::Round($p, 2) | Should Be -6.62
    }
    It "SHORT no lucro (preco caiu)" {
        [math]::Round((Get-PositionPnlPct -Price 0.018 -Entry 0.020 -Side "short"), 6) | Should Be 10
    }
    It "SHORT no prejuizo (preco subiu)" {
        [math]::Round((Get-PositionPnlPct -Price 0.022 -Entry 0.020 -Side "short"), 6) | Should Be -10
    }
    It "entry<=0: retorna 0 (sem divisao por zero)" {
        (Get-PositionPnlPct -Price 0.02 -Entry 0 -Side "long") | Should Be 0
    }
    It "preco<=0: retorna 0 (preco invalido)" {
        (Get-PositionPnlPct -Price 0 -Entry 0.02 -Side "long") | Should Be 0
    }
}

Describe "Test-PriceUsable - guard de preco valido" {
    It "preco > 0 = usavel" {
        (Test-PriceUsable -Price 0.02) | Should Be $true
    }
    It "preco = 0 = nao usavel (caller pula ciclo)" {
        (Test-PriceUsable -Price 0) | Should Be $false
    }
    It "preco negativo = nao usavel" {
        (Test-PriceUsable -Price -1) | Should Be $false
    }
}
