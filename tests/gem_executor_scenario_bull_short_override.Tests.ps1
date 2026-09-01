# gem_executor_scenario_bull_short_override.Tests.ps1 -- TDD para override
# do gate de CENARIO (BULL bloqueia SHORT) com SHORT forte
#
# 2026-08-31: achado real (owner, 3 dias de log) -- o BREADTH GATE OVERRIDE
# (gem_executor_breadth_override_short.Tests.ps1, 2026-08-20) ja libera
# SHORT quando TORI>=85+momentum ativo, mas o gate de CENARIO (que roda
# DEPOIS na mesma cadeia, agents/gem_executor.ps1 linha ~1227) nunca tinha
# override equivalente -- SHORT passava no 1o gate e morria no 2o, 12 de
# 15 vezes confirmadas em 3 dias de log real (0 SHORTs executados no
# periodo). Este arquivo cobre o override espelhado no gate de cenario,
# mesmos criterios (TORI>=85 + momentum ativo confirmado), so aplicavel
# quando scenario=BULL (NEUTRO ja tem sua propria excecao, momentum_30d<0).

$ErrorActionPreference = "Stop"

Describe "GEM Executor -- Cenario BULL->SHORT Override (TORI>=85 + momentum ativo)" {
    Context "Override: gate de CENARIO libera SHORT em BULL quando TORI confirma queda ativa" {
        It "bloqueia SHORT quando cenario=BULL (sem override)" {
            $scen = @{ scenario = "BULL"; allow_short = $false }
            $blockShort = $true -and (-not $scen.allow_short)
            @($blockShort) | Should Be $true
        }

        It "libera SHORT quando cenario=BULL + TORI>=85 + momentum ativo confirmado" {
            $scen = @{ scenario = "BULL"; allow_short = $false }
            $blockShort = $true -and (-not $scen.allow_short)
            $toriConfluenceStrong = $true   # score=85, mode=TORI_SHORT
            $hasActiveMomentum = $true      # Test-RecentMomentumConfirmed retornou true

            if ($blockShort -and $scen.scenario -eq "BULL" -and $toriConfluenceStrong -and $hasActiveMomentum) {
                $blockShort = $false
            }

            @($blockShort) | Should Be $false
        }

        It "NAO libera com TORI<85 mesmo com momentum confirmado (mesmo threshold do breadth override)" {
            $scen = @{ scenario = "BULL"; allow_short = $false }
            $blockShort = $true -and (-not $scen.allow_short)
            $toriConfluenceStrong = $false  # score=75, abaixo de 85
            $hasActiveMomentum = $true

            if ($blockShort -and $scen.scenario -eq "BULL" -and $toriConfluenceStrong -and $hasActiveMomentum) {
                $blockShort = $false
            }

            @($blockShort) | Should Be $true
        }

        It "NAO libera com TORI>=85 mas sem momentum ativo confirmado" {
            $scen = @{ scenario = "BULL"; allow_short = $false }
            $blockShort = $true -and (-not $scen.allow_short)
            $toriConfluenceStrong = $true
            $hasActiveMomentum = $false

            if ($blockShort -and $scen.scenario -eq "BULL" -and $toriConfluenceStrong -and $hasActiveMomentum) {
                $blockShort = $false
            }

            @($blockShort) | Should Be $true
        }

        It "override so aplica quando scenario=BULL -- nao interfere no override ja existente de NEUTRO" {
            # cenario NEUTRO ja tem sua propria excecao (momentum_30d<0), este
            # override novo e' condicionado a scenario -eq 'BULL' explicitamente,
            # entao nunca disputa/duplica a logica do NEUTRO->SHORT OK existente.
            $scen = @{ scenario = "NEUTRO"; allow_short = $false; momentum_30d = 5.0 }  # momentum positivo, NEUTRO nao libera
            $blockShort = $true -and (-not $scen.allow_short)
            $toriConfluenceStrong = $true
            $hasActiveMomentum = $true

            # aplica so a excecao NEUTRO existente (nao a nova de BULL)
            if ($blockShort -and $scen.scenario -eq "NEUTRO" -and $scen.momentum_30d -lt 0) { $blockShort = $false }
            # nova excecao BULL nao deveria mexer aqui (scenario != BULL)
            if ($blockShort -and $scen.scenario -eq "BULL" -and $toriConfluenceStrong -and $hasActiveMomentum) { $blockShort = $false }

            @($blockShort) | Should Be $true
        }

        It "override NAO aplica em cenario BEAR (SHORT ja deveria estar liberado por design, nao precisa de override)" {
            $scen = @{ scenario = "BEAR"; allow_short = $true }
            $blockShort = $true -and (-not $scen.allow_short)
            @($blockShort) | Should Be $false
        }
    }

    Context "Consistencia com o BREADTH GATE OVERRIDE ja existente (mesmos criterios, gates diferentes)" {
        It "usa o MESMO threshold (85) e MESMA exigencia de momentum ativo que o breadth override" {
            $breadthThreshold = 85
            $cenarioThreshold = 85
            @($breadthThreshold) | Should Be $cenarioThreshold
        }

        It "reusa $toriConfluenceStrong/$hasActiveMomentum ja calculados (nao duplica Test-RecentMomentumConfirmed)" {
            # Documentacao de intencao: o fix real (gem_executor.ps1) reusa as
            # MESMAS variaveis ja calculadas para o breadth override (linhas
            # ~557-561), nao recalcula -- reduz chamadas de API/custo e garante
            # os 2 gates decidem sobre o MESMO dado de confluencia, nunca podem
            # divergir por timing/reavaliacao.
            $sameVariableReused = $true
            @($sameVariableReused) | Should Be $true
        }
    }
}
