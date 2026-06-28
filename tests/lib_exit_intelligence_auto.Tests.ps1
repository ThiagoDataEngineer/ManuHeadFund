# Tests para lib_exit_intelligence_auto.ps1 (nucleo puro Resolve-ExitAutoDecision)
# Foco: causa raiz 2026-06-28 (qty fantasma / dust) + as 3 layers de profit-taking.

Describe "Resolve-ExitAutoDecision (Exit Intelligence Auto - nucleo puro)" {
    BeforeAll {
        $root = Get-Location
        . (Join-Path $root "agents\lib_exit_intelligence_auto.ps1")

        # closes "saudaveis" (subindo) p/ casos que nao testam reversal/RSI
        $script:closesUp   = @(1.0, 1.01, 1.02, 1.03, 1.05)
        # 3 closes em queda monotonica no fim -> reversal
        $script:closesRev  = @(1.10, 1.20, 1.18, 1.15, 1.12)
    }

    Context "Guardas (SKIP) - dados insuficientes / poeira" {
        It "SKIP sem preco" {
            (Resolve-ExitAutoDecision -Closes $closesUp -Current 0 -Entry 1 -RealQty 100).action | Should Be 'SKIP'
        }
        It "SKIP sem saldo" {
            (Resolve-ExitAutoDecision -Closes $closesUp -Current 1 -Entry 1 -RealQty 0).action | Should Be 'SKIP'
        }
        It "SKIP poeira (notional < MinNotionalUsd)" {
            # REGRESSAO MET: 0.0147 MET @ 0.165 = ~0.0024 USD -> poeira, nunca tenta vender
            $d = Resolve-ExitAutoDecision -Closes $closesRev -Current 0.165 -Entry 0.138 -Sl 0.135 -RealQty 0.0147
            $d.action | Should Be 'SKIP'
            $d.reason | Should Be 'poeira'
        }
        It "SKIP sem entry (profit-taking exige ganho conhecido)" {
            $d = Resolve-ExitAutoDecision -Closes $closesUp -Current 1 -Entry 0 -RealQty 1000
            $d.action | Should Be 'SKIP'
            $d.reason | Should Be 'sem_entry'
        }
        It "SKIP poucos candles" {
            (Resolve-ExitAutoDecision -Closes @(1,2) -Current 2 -Entry 1 -RealQty 1000).action | Should Be 'SKIP'
        }
    }

    Context "Layer 4 - perto do SL com ganho -> vende 100%" {
        It "dispara SELL 100% quando distToSL <= 2.5% e ganho > 0" {
            # preco 1.02, SL 1.00 -> distToSL = (1.02-1.00)/1.02 = 1.96% (<=2.5), entry 0.90 -> ganho
            $d = Resolve-ExitAutoDecision -Closes $closesUp -Current 1.02 -Entry 0.90 -Sl 1.00 -RealQty 1000
            $d.action | Should Be 'SELL'
            $d.layer  | Should Be 4
            $d.pct    | Should Be 100
        }
        It "sellQty = floor(realQty * 0.997 * 1e6)/1e6 (haircut anti balance-not-enough)" {
            $d = Resolve-ExitAutoDecision -Closes $closesUp -Current 1.02 -Entry 0.90 -Sl 1.00 -RealQty 1000
            $expected = [math]::Floor(1000 * 0.997 * 1e6) / 1e6
            $d.sellQty | Should Be $expected
        }
        It "NAO dispara L4 se sem ganho (gain <= 0)" {
            $d = Resolve-ExitAutoDecision -Closes $closesUp -Current 1.02 -Entry 1.50 -Sl 1.00 -RealQty 1000
            $d.action | Should Not Be 'SELL'
        }
    }

    Context "Layer 3 - reversal com ganho -> vende 70%" {
        It "dispara SELL 70% em reversal + ganho (longe do SL)" {
            $d = Resolve-ExitAutoDecision -Closes $closesRev -Current 1.12 -Entry 0.80 -Sl 0.50 -RealQty 1000
            $d.action   | Should Be 'SELL'
            $d.layer    | Should Be 3
            $d.pct      | Should Be 70
            $d.reversal | Should Be $true
        }
        It "sellQty = floor(realQty * 0.70 * 1e6)/1e6" {
            $d = Resolve-ExitAutoDecision -Closes $closesRev -Current 1.12 -Entry 0.80 -Sl 0.50 -RealQty 1000
            $d.sellQty | Should Be ([math]::Floor(1000 * 0.70 * 1e6) / 1e6)
        }
        It "NAO dispara em reversal se gain <= 0" {
            $d = Resolve-ExitAutoDecision -Closes $closesRev -Current 1.12 -Entry 2.00 -Sl 0.50 -RealQty 1000
            $d.action | Should Not Be 'SELL'
        }
    }

    Context "Layer 2 - RSI sobrecomprado com ganho -> vende 25%" {
        It "dispara SELL 25% quando RSI>=70 e ganho>0 (sem reversal, longe do SL)" {
            # closes so de alta -> RSI = 100 (avgLoss=0). entry baixo, SL longe, sem reversal.
            $d = Resolve-ExitAutoDecision -Closes $closesUp -Current 1.05 -Entry 0.80 -Sl 0.50 -RealQty 1000
            $d.action | Should Be 'SELL'
            $d.layer  | Should Be 2
            $d.pct    | Should Be 25
        }
    }

    Context "Prioridade das layers e HOLD" {
        It "L4 tem prioridade sobre L3 (perto do SL ganha do reversal)" {
            # reversal presente E perto do SL -> deve escolher L4 (100%)
            $d = Resolve-ExitAutoDecision -Closes $closesRev -Current 1.02 -Entry 0.80 -Sl 1.00 -RealQty 1000
            $d.layer | Should Be 4
        }
        It "HOLD quando avalia mas nenhuma layer dispara" {
            # ganho pequeno, longe do SL, sem reversal, RSI < 70 (closes mistos)
            $mixed = @(1.00, 0.99, 1.00, 0.99, 1.001)
            $d = Resolve-ExitAutoDecision -Closes $mixed -Current 1.001 -Entry 1.00 -Sl 0.50 -RealQty 1000
            $d.action | Should Be 'HOLD'
        }
    }
}
