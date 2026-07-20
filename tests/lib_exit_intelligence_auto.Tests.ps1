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

        # 2026-07-17: mesmo buraco do L2 -- L3 vende 70% do bag (bem mais agressivo
        # que L2), entao o piso e maior (default +15%) pra so realizar num reversal
        # que ja tem lucro real em jogo, nao no primeiro tique negativo.
        It "NAO dispara L3 com ganho positivo mas abaixo do piso" {
            # entry 1.11 -> current 1.12 = +0.9% de ganho, reversal presente mas abaixo do piso 15%
            $d = Resolve-ExitAutoDecision -Closes $closesRev -Current 1.12 -Entry 1.11 -Sl 0.50 -RealQty 1000
            $d.action | Should Not Be 'SELL'
        }

        It "piso de L3 e configuravel via MinGainPctL3" {
            $d = Resolve-ExitAutoDecision -Closes $closesRev -Current 1.12 -Entry 1.11 -Sl 0.50 -RealQty 1000 -MinGainPctL3 0.5
            $d.action | Should Be 'SELL'
            $d.layer  | Should Be 3
        }
    }

    Context "Layer 2 - RSI sobrecomprado com ganho -> vende 25%" {
        It "dispara SELL 25% quando RSI>=70 e ganho>=piso (sem reversal, longe do SL)" {
            # closes so de alta -> RSI = 100 (avgLoss=0). entry baixo, SL longe, sem reversal.
            $d = Resolve-ExitAutoDecision -Closes $closesUp -Current 1.05 -Entry 0.80 -Sl 0.50 -RealQty 1000
            $d.action | Should Be 'SELL'
            $d.layer  | Should Be 2
            $d.pct    | Should Be 25
        }

        # 2026-07-17: causa raiz achado #3/#4 -- antes L2 disparava com QUALQUER
        # gain>0 (ate +0.01%), vendendo 25% contra alvos de +90-200%. Agora exige
        # piso minimo (default +8%) pra RSI ruidoso nao cortar o trade cedo demais.
        It "NAO dispara L2 com ganho positivo mas abaixo do piso (RSI ruido cedo)" {
            # entry 1.04 -> current 1.05 = +0.96% de ganho, RSI=100 (so alta) mas abaixo do piso 8%
            $d = Resolve-ExitAutoDecision -Closes $closesUp -Current 1.05 -Entry 1.04 -Sl 0.50 -RealQty 1000
            $d.action | Should Not Be 'SELL'
        }

        It "piso de L2 e configuravel via MinGainPctL2" {
            $d = Resolve-ExitAutoDecision -Closes $closesUp -Current 1.05 -Entry 1.04 -Sl 0.50 -RealQty 1000 -MinGainPctL2 0.5
            $d.action | Should Be 'SELL'
            $d.layer  | Should Be 2
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

    # Layer 5 CLIMAX (2026-07-03) — base empirica knowledge/UNIVERSE_PHYSICS.md:
    # bag que pumpou >=25% no DIA -> vender no climax (D+1 mediana -4.6%, D+7 -10.4%,
    # pior 5% -44%; vender ganha em 63% dos casos; n=6212, OOS 4 regimes).
    Context "Layer 5 - CLIMAX do dia (pump >=25%) -> vende 100%" {
        It "dispara SELL 100% layer 5 quando dia >= +25% e ganho > 0" {
            # dayOpen 1.00 -> current 1.30 = +30% no dia; entry 0.90 -> ganho total
            $d = Resolve-ExitAutoDecision -Closes $closesUp -Current 1.30 -Entry 0.90 -Sl 0.50 -RealQty 1000 -DayOpen 1.00
            $d.action | Should Be 'SELL'
            $d.layer  | Should Be 5
            $d.pct    | Should Be 100
            $d.reason | Should Be 'climax_dissipacao'
        }
        It "NAO dispara com dia < threshold (+10% apenas)" {
            $d = Resolve-ExitAutoDecision -Closes $closesUp -Current 1.10 -Entry 0.90 -Sl 0.50 -RealQty 1000 -DayOpen 1.00
            $d.layer | Should Not Be 5
        }
        It "NAO dispara sem ganho total (principio: nunca vende no prejuizo)" {
            # dia +30% mas entry 2.00 >> current -> prejuizo total
            $d = Resolve-ExitAutoDecision -Closes $closesUp -Current 1.30 -Entry 2.00 -Sl 0.50 -RealQty 1000 -DayOpen 1.00
            $d.action | Should Not Be 'SELL'
        }
        It "DayOpen desconhecido (0) -> layer inativa, avalia as demais (fail-safe)" {
            $d = Resolve-ExitAutoDecision -Closes $closesUp -Current 1.05 -Entry 0.80 -Sl 0.50 -RealQty 1000 -DayOpen 0
            $d.layer | Should Not Be 5
        }
        It "L5 tem prioridade sobre L4 (climax vence perto-do-SL)" {
            # dia +30% E perto do SL -> escolhe L5 (mesma acao 100%, razao correta p/ auditoria)
            $d = Resolve-ExitAutoDecision -Closes $closesUp -Current 1.30 -Entry 0.90 -Sl 1.28 -RealQty 1000 -DayOpen 1.00
            $d.layer | Should Be 5
        }
        It "threshold configuravel (ClimaxThresholdPct 15 -> +20% dispara)" {
            $d = Resolve-ExitAutoDecision -Closes $closesUp -Current 1.20 -Entry 0.90 -Sl 0.50 -RealQty 1000 -DayOpen 1.00 -ClimaxThresholdPct 15
            $d.layer | Should Be 5
        }
        It "sellQty usa haircut 0.997 como o L4" {
            $d = Resolve-ExitAutoDecision -Closes $closesUp -Current 1.30 -Entry 0.90 -Sl 0.50 -RealQty 1000 -DayOpen 1.00
            $d.sellQty | Should Be ([math]::Floor(1000 * 0.997 * 1e6) / 1e6)
        }
    }
}
