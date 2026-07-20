# lib_token_structural_quality.Tests.ps1 -- Pester 3.x
#
# Gate de qualidade estrutural so-CoinEx (achado 2026-07-20, BABYDOGEUSDT
# comprado autonomo sem gate estrutural nenhum). Testa Get-SpotLiquidityNearPrice
# (pura) e Test-TokenStructuralQuality (veredito por contagem de flags).
#
# NOTA PS 5.1: @(@("a","b")) ACHATA o array interno (vira 2 elementos string,
# nao 1 elemento array de 2) -- precisa do comma-operator @(,@("a","b")) pra
# preservar array-de-arrays, exatamente como ConvertFrom-Json faz com JSON
# real de bids/asks (confirmado: JSON [[preco,qty],...] desserializa certo,
# so a CONSTRUCAO manual do fixture em PS precisa do ",").

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_token_structural_quality.ps1")

function New-FakeDepth {
    param([array]$Bids = @(), [array]$Asks = @())
    [PSCustomObject]@{
        market = "TESTUSDT"
        depth  = [PSCustomObject]@{ bids = $Bids; asks = $Asks }
    }
}

Describe "Get-SpotLiquidityNearPrice -- pura" {
    It "soma bids+asks dentro da banda +-2%" {
        $bids = @(,@("99.5", "10")) + @(,@("90", "999"))
        $asks = @(,@("100.5", "10")) + @(,@("110", "999"))
        $depth = New-FakeDepth -Bids $bids -Asks $asks
        # dentro da banda [98, 102]: bid 99.5*10=995, ask 100.5*10=1005. Fora: 90 e 110.
        $r = Get-SpotLiquidityNearPrice -Depth $depth -ReferencePrice 100 -PctBand 2.0
        $r | Should Be 2000
    }
    It "retorna 0 se ReferencePrice <= 0" {
        $depth = New-FakeDepth -Bids @(,@("1", "1"))
        $r = Get-SpotLiquidityNearPrice -Depth $depth -ReferencePrice 0
        $r | Should Be 0
    }
    It "ignora niveis malformados (sem quebrar)" {
        $bids = @(,@("99")) + @(,@("99.5", "10"))
        $depth = New-FakeDepth -Bids $bids
        $r = Get-SpotLiquidityNearPrice -Depth $depth -ReferencePrice 100 -PctBand 2.0
        $r | Should Be 995
    }
}

Describe "Test-TokenStructuralQuality -- caso real BABYDOGEUSDT (2026-07-20)" {
    It "preco extremo (0.0000002) + liquidez rasa -- 2 flags = BLOCK" {
        # BABYDOGEUSDT real: preco ~0.0000002 (bem abaixo do threshold 0.00001).
        # Liquidez deliberadamente rasa: qty pequena, valor total << 20x de $100.
        $thinDepth = New-FakeDepth -Bids @(,@("0.0000002", "100")) -Asks @(,@("0.0000003", "100"))
        $r = Test-TokenStructuralQuality -Market "BABYDOGEUSDT" -CurrentPrice 0.0000002 -IntendedSizeUsd 100 -Depth $thinDepth
        $r.verdict | Should Be "BLOCK"
        ($r.flags -contains "unit_price_extreme") | Should Be $true
        ($r.flags -contains "liquidity_thin") | Should Be $true
    }

    It "preco normal + liquidez profunda (>=20x a posicao) -- 0 flags = PASS" {
        # posicao=$100, precisa >=$2000 de liquidez perto do preco. bid+ask = 99.5*1000+100.5*1000=200000.
        $deepDepth = New-FakeDepth -Bids @(,@("99.5", "1000")) -Asks @(,@("100.5", "1000"))
        $r = Test-TokenStructuralQuality -Market "BTCUSDT" -CurrentPrice 100 -IntendedSizeUsd 100 -Depth $deepDepth
        $r.verdict | Should Be "PASS"
        @($r.flags).Count | Should Be 0
    }

    It "so preco extremo, liquidez OK (>=20x) -- 1 flag = CAUTION (nao bloqueia moeda legitima barata)" {
        # posicao=$100, precisa >=$2000. qty=250M: 0.000005*250M=1250 + 0.0000051*250M=1275 = 2525 (>=2000).
        $deepDepth = New-FakeDepth -Bids @(,@("0.000005", "250000000")) -Asks @(,@("0.0000051", "250000000"))
        $r = Test-TokenStructuralQuality -Market "CHEAPUSDT" -CurrentPrice 0.000005 -IntendedSizeUsd 100 -Depth $deepDepth
        $r.verdict | Should Be "CAUTION"
        @($r.flags).Count | Should Be 1
        ($r.flags -contains "unit_price_extreme") | Should Be $true
    }

    It "so liquidez rasa, preco normal -- 1 flag = CAUTION" {
        $thinDepth = New-FakeDepth -Bids @(,@("99.5", "0.1")) -Asks @(,@("100.5", "0.1"))
        $r = Test-TokenStructuralQuality -Market "THINUSDT" -CurrentPrice 100 -IntendedSizeUsd 100 -Depth $thinDepth
        $r.verdict | Should Be "CAUTION"
        ($r.flags -contains "liquidity_thin") | Should Be $true
    }

    It "fail-closed: sem depth disponivel (nem Depth passado nem funcao CoinEx-GetSpotDepth) -- CAUTION, nunca PASS silencioso" {
        $r = Test-TokenStructuralQuality -Market "UNKNOWNUSDT" -CurrentPrice 100 -IntendedSizeUsd 100 -Depth $null
        $r.verdict | Should Not Be "PASS"
        ($r.flags -contains "liquidity_unknown") | Should Be $true
    }

    It "usa CoinEx-GetSpotDepth quando Depth nao e passado explicitamente" {
        function CoinEx-GetSpotDepth {
            param($Market, $Limit)
            New-FakeDepth -Bids @(,@("99.5", "1000")) -Asks @(,@("100.5", "1000")) # bid+ask=200000, >=2000
        }
        $r = Test-TokenStructuralQuality -Market "AUTOUSDT" -CurrentPrice 100 -IntendedSizeUsd 100
        $r.verdict | Should Be "PASS"
        Remove-Item Function:\CoinEx-GetSpotDepth -ErrorAction SilentlyContinue
    }
}
