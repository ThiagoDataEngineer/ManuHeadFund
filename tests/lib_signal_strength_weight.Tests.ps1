# lib_signal_strength_weight.Tests.ps1 -- TDD
#
# Achado 2026-08-04 (owner, discutindo "como ganhar mais" nas posicoes
# reais): o sizing por trade usa MaxConcurrentTrades=15 fixo como divisor
# (Get-SizePerTrade, lib_sizing_dynamics.ps1), reservando fatia igual de
# risco pra ate 15 posicoes possiveis mesmo com so 6 abertas de verdade --
# medido real: margem de $20-70 por posicao numa conta de $5056 (so 9.65%
# do capital FUTURES alocado). Owner pediu: pesar o sizing pela FORCA do
# sinal ($Gem.score, 0-100, ja usado em varios gates -- scoreMin bloqueia
# abaixo de um piso ~65, scores reais vistos em producao vao ate 90+).
#
# Get-SignalStrengthWeight decide o multiplicador (escalonado por faixa,
# nao continuo -- mais simples de auditar): score forte ganha fatia maior,
# score no piso ainda passa no gate mas com menos conviccao = fatia menor.

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_sizing_dynamics.ps1")

Describe "Get-SignalStrengthWeight -- multiplicador escalonado por forca do sinal" {

    It "score forte (>=90) -- peso 1.5x" {
        Get-SignalStrengthWeight -Score 90  | Should Be 1.5
        Get-SignalStrengthWeight -Score 95  | Should Be 1.5
        Get-SignalStrengthWeight -Score 100 | Should Be 1.5
    }

    It "score padrao (75-89) -- peso 1.0x" {
        Get-SignalStrengthWeight -Score 75 | Should Be 1.0
        Get-SignalStrengthWeight -Score 80 | Should Be 1.0
        Get-SignalStrengthWeight -Score 89 | Should Be 1.0
    }

    It "score fraco (abaixo de 75, ainda passou no gate) -- peso 0.6x" {
        Get-SignalStrengthWeight -Score 65 | Should Be 0.6
        Get-SignalStrengthWeight -Score 74 | Should Be 0.6
    }

    It "score exatamente no limite da faixa forte (90) conta como forte" {
        Get-SignalStrengthWeight -Score 90 | Should Be 1.5
    }

    It "score exatamente no limite da faixa padrao (75) conta como padrao, nao fraco" {
        Get-SignalStrengthWeight -Score 75 | Should Be 1.0
    }

    It "score invalido/ausente (0, negativo, null) -- fail-safe pro peso mais conservador (0.6x), nunca quebra" {
        Get-SignalStrengthWeight -Score 0 | Should Be 0.6
        Get-SignalStrengthWeight -Score -5 | Should Be 0.6
    }

    It "score acima de 100 (dado corrompido/nao clampado) -- ainda trata como forte, nao lanca excecao" {
        Get-SignalStrengthWeight -Score 150 | Should Be 1.5
    }
}

Describe "Get-SizePerTrade -- aceita peso de sinal opcional, sem quebrar chamadas antigas" {

    It "sem SignalWeight (chamada antiga, back-compat) -- comportamento identico a hoje" {
        $r = Get-SizePerTrade -AllocatedCapital 1000 -MaxConcurrentTrades 15 -StopLossPct 0.02
        $r | Should Be 33.33
    }

    It "com SignalWeight=1.0 (score padrao) -- mesmo resultado de sem peso" {
        $r1 = Get-SizePerTrade -AllocatedCapital 1000 -MaxConcurrentTrades 15 -StopLossPct 0.02
        $r2 = Get-SizePerTrade -AllocatedCapital 1000 -MaxConcurrentTrades 15 -StopLossPct 0.02 -SignalWeight 1.0
        $r2 | Should Be $r1
    }

    It "com SignalWeight=1.5 (sinal forte) -- tamanho 50% maior" {
        $base = Get-SizePerTrade -AllocatedCapital 1000 -MaxConcurrentTrades 15 -StopLossPct 0.02
        $weighted = Get-SizePerTrade -AllocatedCapital 1000 -MaxConcurrentTrades 15 -StopLossPct 0.02 -SignalWeight 1.5
        $weighted | Should Be ([math]::Round($base * 1.5, 2))
    }

    It "com SignalWeight=0.6 (sinal fraco) -- tamanho 40% menor" {
        $base = Get-SizePerTrade -AllocatedCapital 1000 -MaxConcurrentTrades 15 -StopLossPct 0.02
        $weighted = Get-SizePerTrade -AllocatedCapital 1000 -MaxConcurrentTrades 15 -StopLossPct 0.02 -SignalWeight 0.6
        $weighted | Should Be ([math]::Round($base * 0.6, 2))
    }
}
