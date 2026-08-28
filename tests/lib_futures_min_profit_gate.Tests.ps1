# lib_futures_min_profit_gate.Tests.ps1 -- TDD de Test-FuturesMinProfitGate
# (agents/lib_futures_min_profit_gate.ps1)
#
# 2026-08-28: mesmo piso de lucro minimo em dolar ja aplicado em SPOT,
# estendido para FUTURES (LONG e SHORT). Diferente de SPOT, usa
# unrealized_pnl direto da CoinEx (ja correto pra ambos os lados).
#
# Pester 3.4 (motor real de producao/CI).

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_futures_min_profit_gate.ps1")

Describe "Test-FuturesMinProfitGate" {
    It "UnrealizedPnlUsd ausente (null): fail-OPEN, nao bloqueia (dado indisponivel != sem lucro)" {
        $r = Test-FuturesMinProfitGate -UnrealizedPnlUsd $null
        $r.allowed | Should Be $true
        $r.reason | Should Be "pnl_indisponivel_fail_open"
    }

    It "PnL abaixo do piso ($6 default): bloqueia" {
        $r = Test-FuturesMinProfitGate -UnrealizedPnlUsd 3.50
        $r.allowed | Should Be $false
        $r.reason -like "lucro_abaixo_piso_minimo*" | Should Be $true
    }

    It "PnL acima do piso: libera" {
        $r = Test-FuturesMinProfitGate -UnrealizedPnlUsd 10.0
        $r.allowed | Should Be $true
        $r.reason | Should Be "acima_piso_minimo"
    }

    It "PnL exatamente no piso: libera (>=, nao >)" {
        $r = Test-FuturesMinProfitGate -UnrealizedPnlUsd 6.0
        $r.allowed | Should Be $true
    }

    It "PnL negativo (posicao no vermelho): bloqueia (nunca realiza no prejuizo por este gate)" {
        $r = Test-FuturesMinProfitGate -UnrealizedPnlUsd -5.0
        $r.allowed | Should Be $false
    }

    It "SHORT com lucro real positivo (unrealized_pnl ja vem correto da CoinEx): libera igual LONG" {
        # unrealized_pnl da CoinEx ja e' positivo pra SHORT vencedor -- este
        # gate nao precisa saber o lado, so consome o numero pronto.
        $r = Test-FuturesMinProfitGate -UnrealizedPnlUsd 12.0
        $r.allowed | Should Be $true
    }

    It "MinProfitUsd e configuravel" {
        $r = Test-FuturesMinProfitGate -UnrealizedPnlUsd 3.0 -MinProfitUsd 2.0
        $r.allowed | Should Be $true
    }
}
