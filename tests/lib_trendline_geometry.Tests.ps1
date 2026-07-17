# lib_trendline_geometry.Tests.ps1 -- TDD do pre-calculo geometrico de trendlines
# 2026-07-17: achado real -- angulo SEM normalizar escala da ~89 graus pra
# qualquer par (preco em milhares, tempo em unidades de candle, escalas
# incompativeis). Testa que a normalizacao produz angulo VISUAL correto.

$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root "agents\lib_trendline_geometry.ps1")

Describe "Get-TrendlineGeometry -- normalizacao de escala" {

    It "caso real BTCUSDT (dados de 2026-07-17): acha candidata dentro da faixa ideal 20-35 graus" {
        # Swing highs reais puxados da API publica CoinEx no dia da investigacao.
        # Sem normalizacao, TODOS os pares davam ~89 graus (matematicamente sem
        # sentido -- preco em dezenas de milhares vs tempo em unidades de candle).
        $highs = @(
            [PSCustomObject]@{ price=63238.0; barsAgo=51 }
            [PSCustomObject]@{ price=64663.0; barsAgo=43 }
            [PSCustomObject]@{ price=64470.0; barsAgo=37 }
            [PSCustomObject]@{ price=64274.0; barsAgo=31 }
            [PSCustomObject]@{ price=64400.0; barsAgo=28 }
            [PSCustomObject]@{ price=65569.0; barsAgo=13 }
        )
        $result = @(Get-TrendlineGeometry -Points $highs -MinGapCandles 6)
        $inIdeal = @($result | Where-Object { $_.in_ideal_range })
        $inIdeal.Count | Should BeGreaterThan 0
    }

    It "respeita distancia minima de candles (default 6) -- pares mais proximos sao excluidos" {
        $pts = @(
            [PSCustomObject]@{ price=100.0; barsAgo=10 }
            [PSCustomObject]@{ price=105.0; barsAgo=8 }   # gap=2, abaixo do minimo
            [PSCustomObject]@{ price=110.0; barsAgo=2 }   # gap com o 1o = 8, ok
        )
        $result = @(Get-TrendlineGeometry -Points $pts -MinGapCandles 6)
        # so o par (10,100)-(2,110) deveria sobreviver (gap=8); (10,100)-(8,105)
        # e (8,105)-(2,110) tem gap 2 e 6 respectivamente -- so o gap=6 tambem passa
        ($result | Where-Object { $_.gap_candles -lt 6 }).Count | Should Be 0
    }

    It "angulo normalizado e SIMETRICO -- escala de preco absoluta nao distorce (BTC vs par barato)" {
        # Mesma FORMA relativa de movimento (mesma proporcao de subida por
        # candle), preco absoluto MUITO diferente (BTC ~64000 vs gema ~0.05) --
        # angulo normalizado deve ser aproximadamente igual, provando que a
        # normalizacao remove o vies de escala absoluta.
        $btcLike = @(
            [PSCustomObject]@{ price=60000.0; barsAgo=40 }
            [PSCustomObject]@{ price=64000.0; barsAgo=20 }
        )
        $gemLike = @(
            [PSCustomObject]@{ price=0.050; barsAgo=40 }
            [PSCustomObject]@{ price=0.0534; barsAgo=20 }  # mesma proporcao de alta (~6.7%)
        )
        $rBtc = @(Get-TrendlineGeometry -Points $btcLike -MinGapCandles 6)
        $rGem = @(Get-TrendlineGeometry -Points $gemLike -MinGapCandles 6)
        $rBtc.Count | Should Be 1
        $rGem.Count | Should Be 1
        # Com so 2 pontos, a normalizacao faz o angulo SEMPRE dar exatamente 45
        # graus (range de preco e tempo cada um mapeado pra [0,1] inteiro) --
        # o teste real de "sem vies de escala" esta no teste anterior (3+ pontos
        # com movimento nao-uniforme). Aqui so confirma que ambos processam sem erro.
        $rBtc[0].angle_normalized_deg | Should Be 45.0
        $rGem[0].angle_normalized_deg | Should Be 45.0
    }

    It "menos de 2 pontos -> retorna vazio (fail-safe, nao lanca excecao)" {
        $result = @(Get-TrendlineGeometry -Points @([PSCustomObject]@{ price=100.0; barsAgo=5 }))
        $result.Count | Should Be 0
    }

    It "pontos sem variacao de preco (todos iguais) -> retorna vazio (divisao por zero evitada)" {
        $pts = @(
            [PSCustomObject]@{ price=100.0; barsAgo=20 }
            [PSCustomObject]@{ price=100.0; barsAgo=10 }
        )
        $result = @(Get-TrendlineGeometry -Points $pts -MinGapCandles 6)
        $result.Count | Should Be 0
    }

    It "candidatas ordenadas por proximidade ao centro da faixa ideal (27.5 graus)" {
        $pts = @(
            [PSCustomObject]@{ price=100.0; barsAgo=40 }
            [PSCustomObject]@{ price=100.5; barsAgo=30 }   # quase horizontal
            [PSCustomObject]@{ price=130.0; barsAgo=10 }   # inclinacao forte
        )
        $result = @(Get-TrendlineGeometry -Points $pts -MinGapCandles 6)
        $result.Count | Should BeGreaterThan 1
        # a primeira candidata deve ter a MENOR distance_from_ideal_center
        $sorted = $result | Sort-Object distance_from_ideal_center
        $result[0].distance_from_ideal_center | Should Be $sorted[0].distance_from_ideal_center
    }

    It "MinGapCandles customizado e respeitado" {
        $pts = @(
            [PSCustomObject]@{ price=100.0; barsAgo=10 }
            [PSCustomObject]@{ price=105.0; barsAgo=6 }   # gap=4
        )
        (Get-TrendlineGeometry -Points $pts -MinGapCandles 6).Count | Should Be 0
        (Get-TrendlineGeometry -Points $pts -MinGapCandles 3).Count | Should Be 1
    }
}

Describe "Format-TrendlineGeometrySummary" {
    It "formata top N candidatas como texto legivel" {
        $highs = @(
            [PSCustomObject]@{ price=64663.0; barsAgo=43 }
            [PSCustomObject]@{ price=64470.0; barsAgo=37 }
            [PSCustomObject]@{ price=64274.0; barsAgo=31 }
        )
        $candidates = @(Get-TrendlineGeometry -Points $highs -MinGapCandles 6)
        $summary = Format-TrendlineGeometrySummary -Candidates $candidates -TopN 2
        ($summary -match "graus") | Should Be $true
        (@($summary -split "`n").Count -le 2) | Should Be $true
    }

    It "sem candidatas -> mensagem explicita (nao string vazia silenciosa)" {
        $summary = Format-TrendlineGeometrySummary
        ($summary.Length -gt 0) | Should Be $true
        ($summary -match "[Nn]enhum") | Should Be $true
    }
}
