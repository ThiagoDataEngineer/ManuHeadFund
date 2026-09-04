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

    # 2026-09-03 FIX CRITICO: achado real -- EXIT por reversao CONFIRMADA
    # (2+ sinais simultaneos) era bloqueado 9/9 vezes pelo piso em dolar
    # fixo, porque trades pequenos (~$90-150 margem) tem lucro em dolar
    # baixo mesmo quando o sinal de reversao aparece cedo o suficiente pra
    # ser util. Os 2 gates (motor de reversao + piso de $) se anulavam por
    # construcao. Fix: EXIT usa piso em R-multiple (proporcional ao risco).
    Context "Action=EXIT usa piso em R-multiple (nao dolar fixo)" {
        It "Action=EXIT + RMultiple abaixo do piso (0.1R default): bloqueia" {
            $r = Test-FuturesMinProfitGate -Action "EXIT" -RMultiple 0.05
            $r.allowed | Should Be $false
            $r.reason -like "exit_abaixo_piso_r_multiple*" | Should Be $true
        }

        It "Action=EXIT + RMultiple acima do piso: libera MESMO com PnL em dolar pequeno -- caso real INJUSDT ($1.51 lucro, mas R-multiple razoavel)" {
            # cenario real que motivou o fix: $1.51 de lucro (bem abaixo do
            # piso de $6), mas ja e' reversao CONFIRMADA (2 sinais) com
            # R-multiple >= 0.1 -- deve liberar, nao mais bloquear por dolar.
            $r = Test-FuturesMinProfitGate -UnrealizedPnlUsd 1.51 -Action "EXIT" -RMultiple 0.15
            $r.allowed | Should Be $true
            $r.reason | Should Be "exit_acima_piso_r_multiple"
        }

        It "Action=EXIT mas RMultiple ausente (dado indisponivel): cai no piso em dolar normal (fail-soft, nao inventa criterio sem dado)" {
            $r = Test-FuturesMinProfitGate -UnrealizedPnlUsd 3.0 -Action "EXIT" -RMultiple $null
            $r.allowed | Should Be $false   # $3.00 < $6.00 default, mesmo comportamento de sempre
        }

        It "Action=PARTIAL (nao EXIT) continua usando piso em dolar, MESMO com RMultiple fornecido -- protecao de migalhas preservada" {
            $r = Test-FuturesMinProfitGate -UnrealizedPnlUsd 3.0 -Action "PARTIAL" -RMultiple 5.0
            $r.allowed | Should Be $false   # PnL baixo bloqueia PARTIAL mesmo com R-multiple alto
        }

        It "Action ausente (chamador antigo, sem os novos parametros): comportamento 100% preservado" {
            $r = Test-FuturesMinProfitGate -UnrealizedPnlUsd 3.0
            $r.allowed | Should Be $false
            $r.reason -like "lucro_abaixo_piso_minimo*" | Should Be $true
        }

        It "MinProfitRMultiple e configuravel" {
            $r = Test-FuturesMinProfitGate -Action "EXIT" -RMultiple 0.15 -MinProfitRMultiple 0.2
            $r.allowed | Should Be $false
        }

        It "R-multiple exatamente no piso: libera (>=, nao >)" {
            $r = Test-FuturesMinProfitGate -Action "EXIT" -RMultiple 0.1
            $r.allowed | Should Be $true
        }
    }
}
