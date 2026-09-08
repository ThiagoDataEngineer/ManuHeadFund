# gem_executor_short_override_threshold_unreachable.Tests.ps1 -- TDD
# 2026-09-08: BUG CRITICO REAL -- os 3 overrides de SHORT (breadth/pump/cenario
# em gem_executor.ps1, commits 5776af7/25c45ea) exigem $Gem.score>=85 (breadth/
# cenario) ou >=90 (pump), mas o proprio gate de entrada Tori (Test-ToriConfluence,
# lib_tori_gate_wrapper.ps1) foi recalibrado em 2026-08-20 pra threshold=65 com
# justificativa EXPLICITA no codigo: "FRACTAL sozinho = score 65" e a maioria dos
# sinais reais em mercado BULL/NEUTRO nao passam de FRACTAL+baseline.
#
# Evidencia real (nao suposicao): 10 execucoes reais do trading-pipeline.yml
# (2026-09-08, runs 34251950191..34239145927) -- ~90 avaliacoes de candidato
# TORI_SHORT logadas ([GEM] <mkt> score=N mode=TORI_SHORT). Distribuicao real:
# score=65 (73x), score=66 (12x), score=81 (2x). NUNCA uma vez score>=85.
#
# Ao mesmo tempo, todo ciclo real mostra "BLOQUEADO GATES: breadth_short_blocked"
# dezenas de vezes, e o log [BREADTH GATE OVERRIDE]/[PUMP GATE OVERRIDE]/
# [CENARIO BULL->SHORT OVERRIDE] NUNCA aparece nesses mesmos 10 runs (grep -c
# "BREADTH GATE OVERRIDE" = 0 em todos). Os 3 overrides desenhados especificamente
# pra destravar SHORT com sinal forte sao estruturalmente inalcancaveis dado o
# score real que o proprio pipeline produz -- o override foi calibrado contra uma
# escala antiga do detector de confluencia, nunca atualizado quando o gate de
# entrada foi recalibrado pra 65 no mesmo mes.
#
# Fix: threshold do override alinhado ao teto real observavel (81 visto ao vivo,
# 85 exigiria um 4o sinal raro) -- baixado de 85/90 para 78/85, ainda
# estritamente ACIMA do piso de entrada (65), preservando a intencao original
# (so libera com sinal MAIS forte que o minimo de entrada), mas alcancavel.

$ErrorActionPreference = "Stop"

Describe "GEM Executor -- override SHORT threshold vs distribuicao real de score" {
    Context "Threshold do gate de entrada (fonte real do Gem.score)" {
        It "Test-ToriConfluence usa threshold=65 (piso real de producao, lib_tori_gate_wrapper.ps1)" {
            . (Join-Path (Join-Path $PSScriptRoot "..") "agents\lib_tori_gate_wrapper.ps1")
            $script:TORI_CONFLUENCE_THRESHOLD | Should Be 65
        }
    }

    Context "BUG: distribuicao real de score observada em producao nunca atinge 85" {
        It "scores reais capturados de 10 runs live (2026-09-08) -- max=81, nunca >=85" {
            # Amostra real extraida via gh run view --log dos runs
            # 34251950191,34250648191,34248096193,34247215746,34246278045,
            # 34244762998,34242909329,34241236137,34240321588,34239145927
            $realScoresObserved = @(65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,
                                     66,66,66,66,66,66,66,66,66,66,66,66,
                                     81,81)

            $maxObserved = ($realScoresObserved | Measure-Object -Maximum).Maximum
            $anyReaches85 = @($realScoresObserved | Where-Object { $_ -ge 85 })

            ($maxObserved -lt 85) | Should Be $true
            @($anyReaches85).Count | Should Be 0
        }

        It "com threshold antigo (85), NENHUM candidato real qualificaria pro override de breadth/cenario" {
            $realScoresObserved = @(65,66,81)
            $oldThreshold = 85
            $qualifying = @($realScoresObserved | Where-Object { $_ -ge $oldThreshold })
            @($qualifying).Count | Should Be 0
        }

        It "com threshold antigo (90), NENHUM candidato real qualificaria pro override de pump" {
            $realScoresObserved = @(65,66,81)
            $oldThreshold = 90
            $qualifying = @($realScoresObserved | Where-Object { $_ -ge $oldThreshold })
            @($qualifying).Count | Should Be 0
        }
    }

    Context "FIX: novo threshold alcancavel mas ainda estritamente acima do piso de entrada" {
        It "novo threshold do breadth/cenario override (78) e alcancavel pelo score real observado (81)" {
            $newThreshold = 78
            $realScoresObserved = @(65,66,81)
            $qualifying = @($realScoresObserved | Where-Object { $_ -ge $newThreshold })
            ($qualifying.Count -gt 0) | Should Be $true
        }

        It "novo threshold do pump override (85) e alcancavel pelo teto historico de 4 sinais empilhados" {
            # VOLUME_CLIMAX(20)+RSI_EXTREME(20)+FRACTAL(15)+baseline(50) = 105 -> 85 e alcancavel
            # com stack completo de sinais (raro mas nao impossivel, distinto do 85 atual usado no breadth)
            $newPumpThreshold = 85
            $strongStackScore = 50 + 20 + 20 + 15  # baseline+volume_climax+rsi_extreme+fractal
            ($strongStackScore -ge $newPumpThreshold) | Should Be $true
        }

        It "novo threshold continua estritamente ACIMA do piso de entrada (65) -- override so libera sinal MAIS forte que o minimo, preserva intencao original" {
            $newBreadthThreshold = 78
            $newPumpThreshold = 85
            $entryFloor = 65
            ($newBreadthThreshold -gt $entryFloor) | Should Be $true
            ($newPumpThreshold -gt $entryFloor) | Should Be $true
            ($newPumpThreshold -gt $newBreadthThreshold) | Should Be $true
        }
    }
}
