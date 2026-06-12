# coinex_news.Tests.ps1 -- TDD lib_coinex_news
# Pester 3.x. UTF-8 BOM.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_coinex_news.ps1")

Describe "Test-NewsKeyword" {

    It "detecta listing em portugues" {
        $text = "CoinEx anuncia a listagem de PENDLE no par PENDLE/USDT em 2026-05-15"
        (Test-NewsKeyword -Text $text -Type "listing") | Should Be $true
    }

    It "detecta listing em ingles" {
        $text = "CoinEx will list FOO/USDT trading begins May 20"
        (Test-NewsKeyword -Text $text -Type "listing") | Should Be $true
    }

    It "detecta delisting" {
        $text = "Aviso: removeremos XYZ do par XYZ/USDT em 2026-06-01 -- delisting"
        (Test-NewsKeyword -Text $text -Type "delisting") | Should Be $true
    }

    It "nao confunde listing com marketing geral" {
        $text = "CoinEx celebrates 10 anos com promocoes e novos produtos"
        (Test-NewsKeyword -Text $text -Type "listing") | Should Be $false
    }

    It "detecta maintenance" {
        $text = "Manutencao programada do sistema CoinEx em 2026-05-20"
        (Test-NewsKeyword -Text $text -Type "maintenance") | Should Be $true
    }
}

Describe "Get-MarketsFromText" {

    It "extrai ticker BTCUSDT" {
        $text = "Trade BTC/USDT now with 0.1% fee"
        $r = Get-MarketsFromText -Text $text
        $r -contains "BTCUSDT" | Should Be $true
    }

    It "extrai multiplos tickers" {
        $text = "Listings: PENDLE/USDT, MORPHO/USDT, SKY/USDT today"
        $r = Get-MarketsFromText -Text $text
        $r.Count | Should BeGreaterThan 1
        $r -contains "PENDLEUSDT" | Should Be $true
        $r -contains "MORPHOUSDT" | Should Be $true
    }

    It "dedupe se mesmo ticker mencionado 2x" {
        $text = "PENDLE bom investimento, PENDLE/USDT listou"
        $r = Get-MarketsFromText -Text $text
        ($r | Where-Object { $_ -eq "PENDLEUSDT" }).Count | Should Be 1
    }

    It "retorna empty se nenhum ticker" {
        $text = "Aviso geral sobre o mercado"
        $r = Get-MarketsFromText -Text $text
        @($r).Count | Should Be 0
    }
}

Describe "Invoke-NewsArticleProcess" {

    $testDir = Join-Path $env:TEMP ("news_test_" + [Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    $pipelinePath = Join-Path $testDir "promotion_pipeline.jsonl"

    It "listing article cria DESCOBERTA entry no pipeline" {
        # Need lib_promotion_ladder loaded for Add-PromotionEvent
        . (Join-Path (Split-Path $PSScriptRoot -Parent) "agents\lib_promotion_ladder.ps1")
        $article = [PSCustomObject]@{
            title = "CoinEx lista FOO/USDT em 2026-05-20"
            content = "CoinEx anuncia listagem de FOO no par FOO/USDT"
            url = "https://www.coinex.com/feed/article/abc"
        }
        $r = Invoke-NewsArticleProcess -Article $article -PipelinePath $pipelinePath
        $r.action | Should Be "added_discovery"
        $r.markets -contains "FOOUSDT" | Should Be $true
        # Verifica que entrou no pipeline
        $state = Get-PromotionState -Path $pipelinePath -Market "FOOUSDT"
        $state | Should Not BeNullOrEmpty
        $state.tier_state | Should Be 0
    }

    It "article sem keywords relevantes -> action=skipped" {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) "agents\lib_promotion_ladder.ps1")
        $article = [PSCustomObject]@{
            title = "Opiniao sobre mercado cripto este mes"
            content = "Analise geral promocional"
            url = "https://x"
        }
        $r = Invoke-NewsArticleProcess -Article $article -PipelinePath $pipelinePath
        $r.action | Should Be "skipped"
    }
}
