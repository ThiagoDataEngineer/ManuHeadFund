# lib_position_protection_target_mode.Tests.ps1 -- TDD de Repair-PositionProtection
# usando o alvo REAL do trade (Get-TrailingPositions.target) como piso do
# TP estrutural, em vez do TargetPct generico (0.32) pra qualquer modo.
#
# 2026-07-31: achado real (owner acompanhou OPUSDT aberto como MOMENTUM --
# alvo de design 150% de distancia, GEM_TARGET_MOMENTUM -- fechar via TP
# estrutural a so 1.65%, virando scalp de 20min sem ninguem decidir isso).
# Investigacao confirmou 3 de 4 eventos reais do dia na mesma faixa (1.4%-3%)
# porque Get-StructuralStopTarget so tinha o TargetPct default (0.32) como
# piso, nunca o alvo real persistido em Add-TrailingPosition (campo target,
# preco absoluto calculado na entrada). Fix: Repair-PositionProtection agora
# busca o registro real via Get-TrailingPositions e deriva o TargetPct
# efetivo dele antes de chamar Get-StructuralStopTarget.
#
# Pester 3.4 (motor real de producao/CI) / ASCII-only.

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

. (Join-Path $agentsDir "lib_trailing_stop_intelligent.ps1")
. (Join-Path $agentsDir "lib_position_protection.ps1")

# Mocks DEPOIS do dot-source (lib_position_protection.ps1 define as versoes
# reais dessas funcoes -- um mock declarado ANTES seria sobrescrito, mesmo
# achado ja documentado hoje em tests/gem_executor_tori_gate.Tests.ps1).
function CoinEx-GetPendingPositions {
    param([string]$Market)
    @([PSCustomObject]@{ avg_entry_price = 100.0; side = "long" })
}
function Get-MarketPrecision { param($Market, $MarketType) [PSCustomObject]@{ quote_ccy_precision = 4 } }
function CoinEx-GetFuturesCandles {
    param($Market, $Period, $Limit)
    # Mesma estrutura de candles do teste "pivot proximo vs distante" em
    # lib_structural_stop_target.Tests.ps1 -- resistencia PROXIMA em 102 (2%)
    # e DISTANTE em 120 (20%), entry=100.
    $candles = @()
    for ($i = 0; $i -lt 13; $i++) {
        $p = 84 + ($i * 1.0)
        $candles += [PSCustomObject]@{ open=$p; high=($p+1); low=($p-0.5); close=($p+0.5); volume=1000 }
    }
    $candles += [PSCustomObject]@{ open=97;   high=98;   low=97;   close=97.5; volume=1000 }
    $candles += [PSCustomObject]@{ open=97;   high=97.5; low=96;   close=96.5; volume=1000 }
    $candles += [PSCustomObject]@{ open=96.5; high=98;   low=96;   close=97.5; volume=1000 }
    $candles += [PSCustomObject]@{ open=98;    high=101; low=98;   close=100;   volume=1000 }
    $candles += [PSCustomObject]@{ open=100;   high=102; low=99;   close=100.5; volume=1000 }  # pivot 102 (2%)
    $candles += [PSCustomObject]@{ open=100.5; high=101; low=99.5; close=100;   volume=1000 }
    $candles += [PSCustomObject]@{ open=100; high=101; low=99;  close=100; volume=1000 }
    $candles += [PSCustomObject]@{ open=100; high=115; low=99;  close=110; volume=1000 }
    $candles += [PSCustomObject]@{ open=110; high=120; low=109; close=118; volume=1000 }        # pivot 120 (20%)
    $candles += [PSCustomObject]@{ open=118; high=119; low=100; close=101; volume=1000 }
    for ($i = 0; $i -lt 4; $i++) {
        $candles += [PSCustomObject]@{ open=100; high=100.5; low=99.5; close=100; volume=1000 }
    }
    return $candles
}
function Set-PositionProtection {
    param($Market, $StopLoss, $TakeProfit, $MaxRetries)
    $global:__last_sl = $StopLoss
    $global:__last_tp = $TakeProfit
    [PSCustomObject]@{ success = $true; sl_set = $true; tp_set = $true; reason = "protected" }
}

Describe "Repair-PositionProtection -- usa alvo REAL do trade (nao TargetPct generico)" {

    It "trade MOMENTUM com alvo real distante (120, 20%) -- ignora pivot proximo (102, 2%), respeita o alvo real" {
        function Get-TrailingPositions {
            @([PSCustomObject]@{ market = "TESTUSDT"; active = $true; target = 120.0 })
        }
        $r = Repair-PositionProtection -Market "TESTUSDT" -EnableTrailing $false
        $r.success | Should Be $true
        # TP deve ser o pivot distante (120), nao o proximo (102) -- o alvo
        # real do trade (120, derivado de Get-TrailingPositions.target) vira
        # o piso minimo que Get-StructuralStopTarget usa antes de aceitar
        # um pivot mais proximo no lugar dele.
        ($global:__last_tp -gt 115.0) | Should Be $true
    }

    It "sem registro no journal (Get-TrailingPositions vazio) -- cai pro TargetPct default (0.32), comportamento antigo preservado" {
        function Get-TrailingPositions { @() }
        $r = Repair-PositionProtection -Market "TESTUSDT" -EnableTrailing $false
        $r.success | Should Be $true
        # sem alvo real conhecido, o piso vira metade de 32% = 16% -- ainda
        # acima do pivot proximo (2%), entao tambem deveria preferir o
        # pivot distante (120) mesmo sem o journal.
        ($global:__last_tp -gt 115.0) | Should Be $true
    }

    It "Get-TrailingPositions indisponivel -- fail-soft, nao quebra o fluxo" {
        Remove-Item Function:\Get-TrailingPositions -ErrorAction SilentlyContinue
        $r = Repair-PositionProtection -Market "TESTUSDT" -EnableTrailing $false
        $r.success | Should Be $true
    }
}
