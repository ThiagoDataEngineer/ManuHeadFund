# lib_trendline_geometry.ps1 -- Pre-calculo geometrico de trendlines (TDD, PURO)
# 2026-07-17: achado investigando vetos "tori_skip" (LONG quase sempre bloqueado
# por "sem trendline valida"). tech_agent_ai.ps1 manda swing points CRUS (price
# absoluto + barsAgo) pro LLM e pede pra ele "imaginar" a geometria (inclinacao
# 20-35 graus ideal segundo knowledge/TORI_TRADES.md) de cabeca, em cascata
# Groq->Mistral->Haiku (nunca Sonnet nessa decisao). Teste empirico real
# (BTCUSDT, dados de hoje): angulo calculado SEM normalizar escala da ~89 graus
# pra QUALQUER par de pontos (preco em dezenas de milhares, tempo em unidades de
# candle -- escalas incompativeis, matematicamente sem sentido). Com a MESMA
# tela normalizada que um trader ve no grafico (range de preco e range de tempo
# mapeados pro mesmo intervalo visual), aparecem angulos reais de 31-34 graus --
# dentro da faixa ideal da metodologia. Sem esse pre-calculo, o LLM (em qualquer
# forca) tem que advinhar geometria de numeros crus incompativeis em escala --
# alta chance de errar por design da tarefa, nao por falta de inteligencia.
#
# Esta lib NAO decide se a trendline e valida (isso continua sendo julgamento
# do LLM, que tambem avalia rejeicao ao toque, contexto HTF, etc -- coisas que
# nao dao pra calcular so com swing points). Ela so PRE-CALCULA o fato
# geometrico objetivo (angulo normalizado real, gap em candles) e retorna as
# melhores candidatas, pra o LLM confirmar/interpretar um numero certo em vez
# de inventar um errado.

function Get-TrendlineGeometry {
    <#
    .SYNOPSIS
        Calcula o angulo NORMALIZADO real entre cada par de swing points que
        respeita a distancia minima de candles exigida pela metodologia Tori
        (knowledge/TORI_TRADES.md: minimo 6 candles entre toques).
    .DESCRIPTION
        Normalizacao: mapeia o range de preco E o range de tempo (barsAgo) pro
        mesmo intervalo [0,1] antes de calcular o angulo -- e o EQUIVALENTE
        matematico de "como um trader ve no grafico" (onde o eixo Y e escalado
        pra caber na tela, nao em unidades absolutas de preco). Sem isso, pares
        com preco em milhares (BTC) sempre dao ~90 graus (vertical), e pares
        com preco em centavos sempre dao ~0 graus (horizontal) -- nenhum dos
        dois reflete a inclinacao VISUAL real.
    .PARAMETER Points
        Array de swing points, cada um com .price (double) e .barsAgo (int).
        Mesmo shape que $swings4h.highs / $swings4h.lows em scripts/tech_agent.ps1.
    .PARAMETER MinGapCandles
        Distancia minima entre toques (default 6, ver knowledge/TORI_TRADES.md
        secao 4 "Candles entre toques | Minimo 6+").
    .PARAMETER IdealAngleMin / IdealAngleMax
        Faixa de angulo normalizado considerada ideal (default 20-35, ver
        knowledge/TORI_TRADES.md secao 4 "Inclinacao (zoom 3 meses) | 20-35graus").
    .OUTPUTS
        Array de candidatas ordenado por proximidade ao centro da faixa ideal
        (27.5 graus), cada uma com: point1, point2, gap_candles,
        angle_normalized_deg, in_ideal_range (bool).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Points,
        [int] $MinGapCandles = 6,
        [double] $IdealAngleMin = 20.0,
        [double] $IdealAngleMax = 35.0
    )

    $pts = @($Points | Where-Object { $_ -and $null -ne $_.price -and $null -ne $_.barsAgo })
    if ($pts.Count -lt 2) { return @() }

    $prices = @($pts | ForEach-Object { [double]$_.price })
    $bars   = @($pts | ForEach-Object { [double]$_.barsAgo })
    $priceMin = ($prices | Measure-Object -Minimum).Minimum
    $priceMax = ($prices | Measure-Object -Maximum).Maximum
    $priceRange = $priceMax - $priceMin
    # barsAgo: maior = mais no passado. Tempo "cresce" da direita (0) pra
    # esquerda (barsAgo alto) no dado cru -- inverte pra eixo x convencional
    # (esquerda=passado, direita=presente) usando -barsAgo.
    $xs = @($bars | ForEach-Object { -$_ })
    $xMin = ($xs | Measure-Object -Minimum).Minimum
    $xMax = ($xs | Measure-Object -Maximum).Maximum
    $xRange = $xMax - $xMin

    # Sem variacao real em algum eixo -> normalizacao indefinida (divisao por
    # zero). Fail-safe: retorna vazio (nao inventa geometria de dado degenerado).
    if ($priceRange -le 0 -or $xRange -le 0) { return @() }

    $candidates = @()
    for ($i = 0; $i -lt $pts.Count; $i++) {
        for ($j = $i + 1; $j -lt $pts.Count; $j++) {
            $gap = [Math]::Abs([double]$pts[$i].barsAgo - [double]$pts[$j].barsAgo)
            if ($gap -lt $MinGapCandles) { continue }

            $nx1 = ($xs[$i] - $xMin) / $xRange
            $nx2 = ($xs[$j] - $xMin) / $xRange
            $ny1 = ([double]$pts[$i].price - $priceMin) / $priceRange
            $ny2 = ([double]$pts[$j].price - $priceMin) / $priceRange
            if ($nx2 -eq $nx1) { continue }

            $slope = ($ny2 - $ny1) / ($nx2 - $nx1)
            $angleDeg = [Math]::Round(([Math]::Atan($slope) * 180.0 / [Math]::PI), 1)
            $absAngle = [Math]::Abs($angleDeg)
            $inIdeal = ($absAngle -ge $IdealAngleMin -and $absAngle -le $IdealAngleMax)

            $candidates += [PSCustomObject]@{
                point1               = $pts[$i]
                point2               = $pts[$j]
                gap_candles          = [int]$gap
                angle_normalized_deg = $angleDeg
                in_ideal_range       = $inIdeal
                distance_from_ideal_center = [Math]::Round([Math]::Abs($absAngle - (($IdealAngleMin + $IdealAngleMax) / 2.0)), 1)
            }
        }
    }

    return @($candidates | Sort-Object distance_from_ideal_center)
}

function Format-TrendlineGeometrySummary {
    <#
    .SYNOPSIS
        Formata as melhores candidatas de Get-TrendlineGeometry como texto
        pronto pra injetar no prompt do LLM (substitui a lista de pontos crus).
    .PARAMETER Candidates
        Saida de Get-TrendlineGeometry (ja ordenada por proximidade ao ideal).
    .PARAMETER TopN
        Quantas candidatas incluir no resumo (default 3 -- suficiente pro LLM
        avaliar sem inflar o prompt).
    #>
    [CmdletBinding()]
    param(
        [object[]] $Candidates = @(),
        [int] $TopN = 3
    )
    if (-not $Candidates -or $Candidates.Count -eq 0) {
        return "Nenhum par de toques com distancia minima de candles atendida -- geometria pre-calculada nao encontrou candidata."
    }
    $top = @($Candidates | Select-Object -First $TopN)
    $lines = @($top | ForEach-Object {
        $tag = if ($_.in_ideal_range) { "DENTRO da faixa ideal 20-35 graus" } else { "FORA da faixa ideal 20-35 graus" }
        "  $($_.point1.price) ($($_.point1.barsAgo)c atras) -> $($_.point2.price) ($($_.point2.barsAgo)c atras): gap=$($_.gap_candles) candles, angulo_normalizado=$($_.angle_normalized_deg) graus [$tag]"
    })
    return ($lines -join "`n")
}

# Export-ModuleMember nao necessario em dot-source; comentado para compatibilidade Pester
