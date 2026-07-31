# lib_structural_stop_target.Tests.ps1 -- TDD de Get-StructuralStopTarget
# (lib_trailing_stop_intelligent.ps1)
#
# 2026-07-30: achado real (owner olhando o grafico do DOGEUSDT ao vivo) --
# Repair-PositionProtection colocava TP sempre a 32% fixo do entry, SEM
# nenhuma leitura de suporte/resistencia real. Confirmado com dado real:
# TP a 32% ficava sempre FORA do range de 30 dias inteiro do par (range
# real observado: 10-15%). "Quase impossivel de acontecer", como reportado.
#
# Pester 3.4 (motor real de producao/CI) / ASCII-only.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir = Join-Path $projectRoot "agents"

. (Join-Path $agentsDir "lib_trailing_stop_intelligent.ps1")

function New-Candle {
    param([double]$Open, [double]$High, [double]$Low, [double]$Close, [double]$Volume = 1000)
    [PSCustomObject]@{ open=$Open; high=$High; low=$Low; close=$Close; volume=$Volume }
}

# 24 candles com um pivot de suporte claro perto de 95 e resistencia perto de 108,
# preco atual (entry) em 100 -- ambos os pivots dentro do raio de 25% do StructuralMaxPct.
# Warm-up mantido estritamente MONOTONICO (sem pivots espurios) pra nao criar
# swing highs/lows falsos que Find-SupportLevels detectaria antes dos reais.
function New-CandlesWithClearStructure {
    $candles = @()
    # warm-up estritamente ascendente ate 96 (cada high/low maior que o anterior -> sem pivot)
    for ($i = 0; $i -lt 13; $i++) {
        $p = 84 + ($i * 1.0)
        $candles += New-Candle -Open $p -High ($p + 1) -Low ($p - 0.5) -Close ($p + 0.5)
    }
    # descida controlada ate o pivot de suporte em ~95 (swing low cercado por valores maiores)
    $candles += New-Candle -Open 97  -High 98  -Low 97   -Close 97.5
    $candles += New-Candle -Open 97  -High 97.5 -Low 95  -Close 96   # pivot low = 95
    $candles += New-Candle -Open 96  -High 98  -Low 96   -Close 97.5
    # subida ate o pivot de resistencia em ~108 (swing high cercado por valores menores)
    $candles += New-Candle -Open 97.5 -High 103 -Low 97.5 -Close 102
    $candles += New-Candle -Open 102  -High 108 -Low 101  -Close 106  # pivot high = 108
    $candles += New-Candle -Open 106  -High 103 -Low 100  -Close 101
    # candles finais, preco fecha perto de 100 (entry) -- sem novo pivot mais alto que 101
    for ($i = 0; $i -lt 4; $i++) {
        $candles += New-Candle -Open 100 -High 100.5 -Low 99.5 -Close 100
    }
    return $candles
}

Describe "Get-StructuralStopTarget -- fail-safe (sem candles/estrutura)" {

    It "sem candles suficientes -- cai pro fallback fixo (StopPct/TargetPct)" {
        # Cobre o mesmo caminho fail-safe que "Find-SupportLevels indisponivel"
        # cobriria (a funcao so e chamada quando ha candles suficientes) --
        # sem precisar remover a funcao do processo. Remove-Item Function:\X
        # foi tentado antes e descartado: Pester 3.4 roda todos os Describe do
        # arquivo no mesmo processo, entao a remocao vazava pros Describe
        # SEGUINTES tambem (nao so pro resto do mesmo Describe), quebrando os
        # testes de estrutura real logo abaixo -- achado real 2026-07-30.
        $r = Get-StructuralStopTarget -Side "long" -Entry 100.0 -Candles @() -StopPct 0.08 -TargetPct 0.32
        $r.sl_source | Should Be "fixed_pct"
        $r.tp_source | Should Be "fixed_pct"
        $r.stop_loss | Should Be 92.0
        $r.take_profit | Should Be 132.0
    }

    It "SHORT sem candles -- fallback fixo espelhado (SL acima, TP abaixo)" {
        $r = Get-StructuralStopTarget -Side "short" -Entry 100.0 -Candles @() -StopPct 0.08 -TargetPct 0.32
        $r.sl_source | Should Be "fixed_pct"
        $r.stop_loss | Should Be 108.0
        $r.take_profit | Should Be 68.0
    }
}

Describe "Get-StructuralStopTarget -- LONG com estrutura real" {

    It "acha suporte real pro SL quando dentro do raio (25%)" {
        $candles = New-CandlesWithClearStructure
        $r = Get-StructuralStopTarget -Side "long" -Entry 100.0 -Candles $candles -StopPct 0.08 -TargetPct 0.32
        $r.sl_source | Should Be "structural"
        # pivot de suporte esperado ~95 (bem mais perto que o fallback fixo de 92)
        ($r.stop_loss -gt 93.0 -and $r.stop_loss -lt 97.0) | Should Be $true
    }

    It "acha resistencia real pro TP quando dentro do raio (25%)" {
        $candles = New-CandlesWithClearStructure
        $r = Get-StructuralStopTarget -Side "long" -Entry 100.0 -Candles $candles -StopPct 0.08 -TargetPct 0.32
        $r.tp_source | Should Be "structural"
        # pivot de resistencia esperado ~108 (bem mais perto que o fallback fixo de 132)
        ($r.take_profit -gt 105.0 -and $r.take_profit -lt 110.0) | Should Be $true
    }

    It "pivot fora do raio maximo -- ignora e usa fallback fixo (fail-safe contra dado ruim)" {
        $candles = New-CandlesWithClearStructure
        # raio bem apertado (1%) -- nenhum pivot real cabe, deve cair pro fixo
        $r = Get-StructuralStopTarget -Side "long" -Entry 100.0 -Candles $candles -StopPct 0.08 -TargetPct 0.32 -StructuralMaxPct 1.0
        $r.sl_source | Should Be "fixed_pct"
        $r.tp_source | Should Be "fixed_pct"
    }
}

Describe "Get-StructuralStopTarget -- piso minimo de TP vs alvo do modo (2026-07-31)" {
    # Achado real: owner acompanhou OPUSDT aberto como MOMENTUM (alvo de
    # design 150% de distancia, GEM_TARGET_MOMENTUM) fechar via TP estrutural
    # a so 1.65% -- virou um scalp de 20min sem ninguem ter decidido isso.
    # Confirmado via investigacao que 3 de 4 eventos reais do dia (XRPUSDT,
    # OPUSDT, ETHUSDT) landaram na faixa de 1.4%-3%, porque Get-
    # StructuralStopTarget sempre pegava o pivot MAIS PROXIMO, sem nenhuma
    # nocao do alvo original pretendido. Fix: MinTargetFractionOfMode exige
    # que o pivot escolhido valha pelo menos essa fracao do TargetPct antes
    # de aceita-lo no lugar de um pivot mais distante (ou do fallback fixo).

    # 27 candles: pivot de resistencia PROXIMO em ~102 (2% do entry=100,
    # abaixo do piso de 16% quando TargetPct=32%*0.5) E outro mais LONGE em
    # ~120 (20%, acima do piso) -- caso real do OPUSDT (pivot perto demais
    # disponivel, mas nao deveria ser aceito por violar o modo do trade).
    function New-CandlesWithNearAndFarResistance {
        $candles = @()
        for ($i = 0; $i -lt 13; $i++) {
            $p = 84 + ($i * 1.0)
            $candles += New-Candle -Open $p -High ($p + 1) -Low ($p - 0.5) -Close ($p + 0.5)
        }
        $candles += New-Candle -Open 97   -High 98   -Low 97   -Close 97.5
        $candles += New-Candle -Open 97   -High 97.5 -Low 96   -Close 96.5
        $candles += New-Candle -Open 96.5 -High 98   -Low 96   -Close 97.5
        # pivot de resistencia PROXIMO em 102 (2% de distancia do entry=100)
        $candles += New-Candle -Open 98    -High 101 -Low 98   -Close 100
        $candles += New-Candle -Open 100   -High 102 -Low 99   -Close 100.5  # pivot high = 102
        $candles += New-Candle -Open 100.5 -High 101 -Low 99.5 -Close 100
        # sobe de novo mais alto -- pivot de resistencia DISTANTE em 120 (20%)
        $candles += New-Candle -Open 100 -High 101 -Low 99  -Close 100
        $candles += New-Candle -Open 100 -High 115 -Low 99  -Close 110
        $candles += New-Candle -Open 110 -High 120 -Low 109 -Close 118        # pivot high = 120
        $candles += New-Candle -Open 118 -High 119 -Low 100 -Close 101
        for ($i = 0; $i -lt 4; $i++) {
            $candles += New-Candle -Open 100 -High 100.5 -Low 99.5 -Close 100
        }
        return $candles
    }

    It "caso real OPUSDT: pivot proximo demais (2%) e ignorado, prefere pivot distante (20%) que respeita o alvo do modo" {
        $candles = New-CandlesWithNearAndFarResistance
        $r = Get-StructuralStopTarget -Side "long" -Entry 100.0 -Candles $candles -StopPct 0.08 -TargetPct 0.32 -MinTargetFractionOfMode 0.5
        $r.tp_source | Should Be "structural"
        # pivot escolhido deve ser o de 120 (20%), NAO o de 102 (2%)
        ($r.take_profit -gt 115.0) | Should Be $true
    }

    It "sem pivot alternativo mais distante -- aceita o pivot proximo mesmo assim (fail-soft, nao vira fixed_pct por engano)" {
        # Mesmos candles do teste acima, mas cortados antes do 2o pivot (120)
        # existir -- so o pivot proximo (102) esta disponivel.
        $candles = @()
        for ($i = 0; $i -lt 13; $i++) {
            $p = 84 + ($i * 1.0)
            $candles += New-Candle -Open $p -High ($p + 1) -Low ($p - 0.5) -Close ($p + 0.5)
        }
        $candles += New-Candle -Open 97   -High 98   -Low 97   -Close 97.5
        $candles += New-Candle -Open 97   -High 97.5 -Low 96   -Close 96.5
        $candles += New-Candle -Open 96.5 -High 98   -Low 96   -Close 97.5
        $candles += New-Candle -Open 98    -High 101 -Low 98   -Close 100
        $candles += New-Candle -Open 100   -High 102 -Low 99   -Close 100.5  # unico pivot high = 102
        $candles += New-Candle -Open 100.5 -High 101 -Low 99.5 -Close 100
        for ($i = 0; $i -lt 4; $i++) {
            $candles += New-Candle -Open 100 -High 100.5 -Low 99.5 -Close 100
        }
        $r = Get-StructuralStopTarget -Side "long" -Entry 100.0 -Candles $candles -StopPct 0.08 -TargetPct 0.32 -MinTargetFractionOfMode 0.5
        $r.tp_source | Should Be "structural"
        ($r.take_profit -gt 100.0 -and $r.take_profit -lt 103.0) | Should Be $true
    }

    It "MinTargetFractionOfMode=0 desativa o piso -- comportamento identico ao antigo (sempre o mais proximo)" {
        $candles = New-CandlesWithNearAndFarResistance
        $r = Get-StructuralStopTarget -Side "long" -Entry 100.0 -Candles $candles -StopPct 0.08 -TargetPct 0.32 -MinTargetFractionOfMode 0.0
        $r.tp_source | Should Be "structural"
        # com piso zerado, volta a pegar o pivot mais proximo (102)
        ($r.take_profit -gt 100.0 -and $r.take_profit -lt 103.0) | Should Be $true
    }
}

Describe "Get-StructuralStopTarget -- SHORT com estrutura real (espelhado)" {

    It "acha resistencia real pro SL quando dentro do raio" {
        $candles = New-CandlesWithClearStructure
        $r = Get-StructuralStopTarget -Side "short" -Entry 100.0 -Candles $candles -StopPct 0.08 -TargetPct 0.32
        $r.sl_source | Should Be "structural"
        ($r.stop_loss -gt 105.0 -and $r.stop_loss -lt 110.0) | Should Be $true
    }

    It "acha suporte real pro TP quando dentro do raio" {
        $candles = New-CandlesWithClearStructure
        $r = Get-StructuralStopTarget -Side "short" -Entry 100.0 -Candles $candles -StopPct 0.08 -TargetPct 0.32
        $r.tp_source | Should Be "structural"
        ($r.take_profit -gt 93.0 -and $r.take_profit -lt 97.0) | Should Be $true
    }
}

Describe "Get-StructuralStopTarget -- caso real DOGEUSDT (2026-07-30)" {

    It "TP estrutural fica dentro do range real de 30d, nao a 32% fixo fora do grafico inteiro" {
        # Dado real observado: DOGEUSDT SHORT entry~0.070985, range 30d [0.068152, 0.079352].
        # TP fixo (32%) = 0.070985 * 0.68 = 0.048269 -- MUITO abaixo do candle mais baixo
        # de 30 dias inteiros (0.068152), exatamente o "quase impossivel" reportado.
        $entry = 0.070985
        $candles = @()
        # 24 candles oscilando dentro do range real, com pivot de suporte claro
        # perto de 0.0685 (baixo do range) que serve de TP real pro SHORT.
        for ($i = 0; $i -lt 18; $i++) {
            $p = 0.0705 + (($i % 3 - 1) * 0.0003)
            $candles += New-Candle -Open $p -High ($p + 0.0004) -Low ($p - 0.0004) -Close $p
        }
        $candles += New-Candle -Open 0.0705 -High 0.0708 -Low 0.0700 -Close 0.0702
        $candles += New-Candle -Open 0.0702 -High 0.0703 -Low 0.0685 -Close 0.0690   # pivot low real
        $candles += New-Candle -Open 0.0690 -High 0.0695 -Low 0.0688 -Close 0.0692
        for ($i = 0; $i -lt 3; $i++) {
            $candles += New-Candle -Open 0.0700 -High 0.0703 -Low 0.0698 -Close 0.0700
        }

        $r = Get-StructuralStopTarget -Side "short" -Entry $entry -Candles $candles -StopPct 0.08 -TargetPct 0.32
        $fixedTp = $entry * (1 - 0.32)

        $r.tp_source | Should Be "structural"
        # TP estrutural deve ficar MUITO mais perto do entry que o TP fixo antigo
        ([Math]::Abs($r.take_profit - $entry) -lt [Math]::Abs($fixedTp - $entry)) | Should Be $true
    }
}
