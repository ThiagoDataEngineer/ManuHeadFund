# Tests for lib_hybrid_orchestrator.ps1
# Pester 3.4 compatible
#
# 2026-07-23 FIX: reescrito por completo -- a lib evoluiu desde o teste
# original (funcoes renomeadas/removidas, nunca detectado porque o CI real
# nunca rodou Pester 5 syntax neste arquivo):
# - Get-HybridPositionSizes nunca existiu -- funcao real e Get-PositionSize
#   (-Market/-Regime/-IsScalp, nao so -Regime)
# - Execute-HybridSignal nunca existiu -- funcao real e Execute-DynamicSignal
# - Rebalance-HybridCapital nunca existiu nesta lib (sem logica de
#   rebalanceamento aqui -- ver lib_portfolio_rebalance.ps1 pra isso)
# - Execute-SpotTrade/Execute-FuturesTrade tem params -Signal/-PositionSize
#   (nao -PositionSizeUSDT), retornam "position_usdt" (nao "position_size_usd"),
#   e NAO tem liquidation_risk/liquidation_price -- Execute-FuturesTrade e
#   uma copia funcional de Execute-SpotTrade, sem logica de alavancagem/
#   liquidacao real (achado, nao consertado aqui -- fora do escopo desta
#   correcao de teste).
# - Capital fallback real e $2425.33 SPOT / $2718.49 FUTURES (nao os valores
#   antigos 1350.425/1700/1000.85 do teste original).
#
# Nenhuma das funcoes de execucao (Get-PositionSize, Execute-SpotTrade,
# Execute-FuturesTrade, Execute-DynamicSignal) desta lib e chamada por
# nenhum motor real -- lib_gem_router.ps1 tem sua PROPRIA Get-PositionSize
# com assinatura diferente, que sobrescreve esta quando ambas sao
# dot-sourceadas no mesmo escopo. So Get-DynamicCapital e usada de fato
# (por lib_place_order.ps1).

Describe "Hybrid Orchestrator" {
    BeforeAll {
        $root = Get-Location
        . (Join-Path $root "agents\lib_hybrid_orchestrator.ps1")
        $script:RealCapital = Get-DynamicCapital
    }

    Context "Position Sizing" {
        It "Calculates SPOT position for BULL_STRONG (3% base)" {
            $positions = Get-PositionSize -Market "SPOT" -Regime "BULL_STRONG"
            $expected = [Math]::Round($script:RealCapital.spot_capital * 0.03, 2)
            ($positions.position_usdt -eq $expected) | Should Be $true
        }

        It "Reduces positions by 50% for BEAR_STRONG vs BULL_WEAK" {
            # 2026-07-23 FIX: comparar contra o position_usdt JA arredondado
            # (24.25*0.5=12.125, banker's rounding do .NET arredonda pro
            # par mais proximo = 12.12) diverge do calculo real da lib, que
            # arredonda so o resultado final (capital*0.01*0.5, sem
            # arredondamento intermediario) = 12.13. Comparar com tolerancia.
            $positionsNormal = Get-PositionSize -Market "SPOT" -Regime "BULL_WEAK"
            $positionsBearStrong = Get-PositionSize -Market "SPOT" -Regime "BEAR_STRONG"
            $diff = [Math]::Abs($positionsBearStrong.position_usdt - ($positionsNormal.position_usdt * 0.5))
            ($diff -le 0.01) | Should Be $true
        }

        It "Never exceeds 3% hard cap per market (BULL_STRONG)" {
            $positions = Get-PositionSize -Market "SPOT" -Regime "BULL_STRONG"
            ($positions.position_pct -le 3.0) | Should Be $true
        }

        It "Never exceeds 1% hard cap per market (regime normal)" {
            $positions = Get-PositionSize -Market "SPOT" -Regime "BULL_WEAK"
            ($positions.position_pct -le 1.0) | Should Be $true
        }
    }

    Context "SPOT Trade Execution" {
        It "Creates valid SPOT trade object" {
            $signal = @{
                market = "BTCUSDT"
                entry_price = 50000
                stop_loss_pct = 0.01
                type = "VOL_CLIMAX_ENGULFING"
                confidence = 0.42
            }
            $trade = Execute-SpotTrade -Signal $signal -PositionSize 13.5
            ($trade.market -eq "SPOT") | Should Be $true
            ($trade.position_usdt -eq 13.5) | Should Be $true
        }

        It "Calculates stop loss correctly" {
            $signal = @{
                market = "BTCUSDT"
                entry_price = 100
                stop_loss_pct = 0.01
                type = "VOL_CLIMAX"
                confidence = 0.37
            }
            $trade = Execute-SpotTrade -Signal $signal -PositionSize 10
            ($trade.stop_loss -eq 99) | Should Be $true
        }
    }

    Context "FUTURES Trade Execution" {
        It "Creates valid FUTURES trade object" {
            $signal = @{
                market = "BTCUSDT"
                entry_price = 50000
                stop_loss_pct = 0.01
                type = "VOL_CLIMAX_ENGULFING"
                confidence = 0.42
            }
            $trade = Execute-FuturesTrade -Signal $signal -PositionSize 10.8
            ($trade.market -eq "FUTURES") | Should Be $true
            ($trade.position_usdt -eq 10.8) | Should Be $true
        }

        It "KNOWN GAP: Execute-FuturesTrade nao calcula liquidacao/alavancagem real" {
            # 2026-07-23: Execute-FuturesTrade e uma copia funcional de
            # Execute-SpotTrade -- mesma formula de stop_loss, sem
            # liquidation_price nem ajuste por leverage. Documentando o gap
            # em vez de mascarar com uma expectativa falsa (nenhum motor
            # real chama esta funcao hoje, ver nota no topo do arquivo).
            $signal = @{ market = "BTCUSDT"; entry_price = 100; stop_loss_pct = 0.01 }
            $trade = Execute-FuturesTrade -Signal $signal -PositionSize 10
            $trade.ContainsKey("liquidation_price") | Should Be $false
        }
    }

    Context "Dynamic Signal Execution" {
        It "Executa SPOT e/ou FUTURES conforme capital disponivel" {
            $signal = @{
                market = "BTCUSDT"
                type = "VOL_CLIMAX_ENGULFING"
                confidence = 0.42
                entry_price = 50000
                stop_loss_pct = 0.01
                direction = "LONG"
            }
            $result = Execute-DynamicSignal -Signal $signal -Regime "BEAR_WEAK"
            ($result.trades.Count -gt 0) | Should Be $true
            ($result.regime -eq "BEAR_WEAK") | Should Be $true
        }

        It "total_risk soma o risco de todos os trades executados" {
            $signal = @{
                market = "BTCUSDT"
                type = "VOL_CLIMAX_ENGULFING"
                confidence = 0.42
                entry_price = 50000
                stop_loss_pct = 0.01
            }
            $result = Execute-DynamicSignal -Signal $signal -Regime "BEAR_WEAK"
            $expectedRisk = ($result.trades | Measure-Object -Property risk_usd -Sum).Sum
            ($result.total_risk -eq $expectedRisk) | Should Be $true
        }
    }

    Context "Risk Management" {
        It "Each market respects 3% cap for BULL_STRONG" {
            $result = Get-PositionSize -Market "SPOT" -Regime "BULL_STRONG"
            $expected = [Math]::Round($script:RealCapital.spot_capital * 0.03, 2)
            ($result.position_usdt -eq $expected) | Should Be $true
        }

        It "Scalp trades usam 3% mesmo fora de BULL_STRONG" {
            $normal = Get-PositionSize -Market "SPOT" -Regime "BEAR_WEAK" -IsScalp $false
            $scalp = Get-PositionSize -Market "SPOT" -Regime "BEAR_WEAK" -IsScalp $true
            ($scalp.position_usdt -gt $normal.position_usdt) | Should Be $true
        }
    }
}
