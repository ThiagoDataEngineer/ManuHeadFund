# fallbacks.Tests.ps1 -- Pester 3.x
# Testa Invoke-SentFallback, Invoke-FundFallback, Invoke-ChainFallback
# Funcoes puras: sem Claude, sem CoinEx, sem HTTP

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Stubs minimos de config para as funcoes puras funcionarem
$global:FUNDING_EXTREME     = 0.001
$global:FUNDING_NEUTRAL_MAX = 0.0003
$global:LSR_LONG_EXTREME    = 0.70
$global:LSR_SHORT_EXTREME   = 0.30
$global:HALVING_DATE        = [DateTime]::new(2024, 4, 19)

function Write-Host    { param() }
function Write-Warning { param() }

. "$here\..\agents\sent_agent.ps1"
. "$here\..\agents\fund_agent.ps1"
. "$here\..\agents\chain_agent.ps1"

# ── helpers ──────────────────────────────────────────────────────────────────

function New-Fg { param([int]$Value=50, [string]$Class="Neutral")
    [PSCustomObject]@{ value=$Value; classification=$Class; yesterday=$Value; change=0 } }

function New-Coin { param([double]$Change7d=0)
    [PSCustomObject]@{ price=80000; rank=1; marketCap=1.5e12; volume24h=30e9
                       priceChange24h=0; priceChange7d=$Change7d; priceChange30d=0
                       ath=109000; athChange=-26; circulatingSupply=19e6; maxSupply=21e6 } }

function New-Defi { param([double]$TvlB=90)
    [PSCustomObject]@{ totalTvlB=$TvlB; ethDominance=55; top5Chains="Ethereum,Solana" } }

function New-Messari { param([double]$Ratio=0.35)
    [PSCustomObject]@{ realVolRatio=$Ratio; reportedVol24h=30e9; realVolume24h=($Ratio*30e9); activeAddresses=500000; coinId="bitcoin" } }

function New-Whale { param([string]$Signal="NEUTRO")
    [PSCustomObject]@{ whaleSignal=$Signal; inflowUSD=1e6; outflowUSD=1e6; netFlowUSD=0; txCount=5; topMoves=@() } }

function New-HashRibbon { param([string]$Signal="NEUTRO")
    [PSCustomObject]@{ signal=$Signal; hashRate30d=600; hashRate60d=580; ribbonPct=3.4 } }

function New-EthConc { param([string]$Risk="NORMAL")
    [PSCustomObject]@{ concentrationRisk=$Risk; top10Pct=40 } }

function New-Nupl { param([int]$Current=50)
    [PSCustomObject]@{ current=$Current; avg30d=48; trend="ESTAVEL"; nupl_proxy=0.4 } }

# ═══════════════════════════════════════════════════════════════════════════════
# SENTFALLBACK
# ═══════════════════════════════════════════════════════════════════════════════

Describe "Invoke-SentFallback - sentimento e intensidade do F&G" {

    It "F&G 80 retorna sentimento BULLISH" {
        $out = Invoke-SentFallback -Fg (New-Fg 80) -FundingRate $null -Lsr $null
        ($out.sentimento) | Should Be "BULLISH"
    }

    It "F&G 20 retorna sentimento BEARISH" {
        $out = Invoke-SentFallback -Fg (New-Fg 20) -FundingRate $null -Lsr $null
        ($out.sentimento) | Should Be "BEARISH"
    }

    It "F&G 50 retorna sentimento NEUTRO" {
        $out = Invoke-SentFallback -Fg (New-Fg 50) -FundingRate $null -Lsr $null
        ($out.sentimento) | Should Be "NEUTRO"
    }

    It "intensidade igual ao valor F&G" {
        $out = Invoke-SentFallback -Fg (New-Fg 70) -FundingRate $null -Lsr $null
        ($out.intensidade) | Should Be 70
    }

    It "F&G null retorna intensidade 50" {
        $out = Invoke-SentFallback -Fg $null -FundingRate $null -Lsr $null
        ($out.intensidade) | Should Be 50
    }
}

Describe "Invoke-SentFallback - recomendacao contrarian" {

    It "F&G 15 retorna COMPRAR_MEDO" {
        $out = Invoke-SentFallback -Fg (New-Fg 15) -FundingRate $null -Lsr $null
        ($out.recomendacao_sentimento) | Should Be "COMPRAR_MEDO"
    }

    It "F&G 85 retorna VENDER_EUFORIA" {
        $out = Invoke-SentFallback -Fg (New-Fg 85) -FundingRate $null -Lsr $null
        ($out.recomendacao_sentimento) | Should Be "VENDER_EUFORIA"
    }

    It "F&G 50 retorna AGUARDAR" {
        $out = Invoke-SentFallback -Fg (New-Fg 50) -FundingRate $null -Lsr $null
        ($out.recomendacao_sentimento) | Should Be "AGUARDAR"
    }

    It "F&G 15 ativa contrarian_signal" {
        $out = Invoke-SentFallback -Fg (New-Fg 15) -FundingRate $null -Lsr $null
        ($out.contrarian_signal) | Should Be $true
    }

    It "F&G 50 nao ativa contrarian_signal" {
        $out = Invoke-SentFallback -Fg (New-Fg 50) -FundingRate $null -Lsr $null
        ($out.contrarian_signal) | Should Be $false
    }
}

Describe "Invoke-SentFallback - funding sinal" {

    It "funding acima de EXTREME retorna EXCESSO_LONGS" {
        $out = Invoke-SentFallback -Fg (New-Fg 50) -FundingRate 0.002 -Lsr $null
        ($out.funding_sinal) | Should Be "EXCESSO_LONGS"
    }

    It "funding negativo extremo retorna EXCESSO_SHORTS" {
        $negRate = -0.002
        $out = Invoke-SentFallback -Fg (New-Fg 50) -FundingRate $negRate -Lsr $null
        ($out.funding_sinal) | Should Be "EXCESSO_SHORTS"
    }

    It "funding levemente positivo retorna FAVORAVEL_LONG" {
        $out = Invoke-SentFallback -Fg (New-Fg 50) -FundingRate 0.0001 -Lsr $null
        ($out.funding_sinal) | Should Be "FAVORAVEL_LONG"
    }

    It "funding null retorna NEUTRO" {
        $out = Invoke-SentFallback -Fg (New-Fg 50) -FundingRate $null -Lsr $null
        ($out.funding_sinal) | Should Be "NEUTRO"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# FUNDFALLBACK
# ═══════════════════════════════════════════════════════════════════════════════

Describe "Invoke-FundFallback - ciclo halving domina score" {

    It "BULL-HISTORICO eleva score acima de 60" {
        $out = Invoke-FundFallback -Coin $null -Defi $null -Messari $null -CyclePhase "BULL-HISTORICO(6-18m)"
        ($out.score_fundamental) | Should BeGreaterThan 60
    }

    It "POSSIVEL-BEAR reduz score abaixo de 40" {
        $out = Invoke-FundFallback -Coin $null -Defi $null -Messari $null -CyclePhase "POSSIVEL-BEAR"
        ($out.score_fundamental) | Should BeLessThan 40
    }

    It "CONSOLIDACAO-POS-HALVING mantem score perto de 55" {
        $out = Invoke-FundFallback -Coin $null -Defi $null -Messari $null -CyclePhase "CONSOLIDACAO-POS-HALVING"
        ($out.score_fundamental) | Should BeGreaterThan 50
        ($out.score_fundamental) | Should BeLessThan 70
    }
}

Describe "Invoke-FundFallback - macro_outlook derivado do score" {

    It "score alto retorna macro_outlook BULLISH" {
        $out = Invoke-FundFallback -Coin $null -Defi $null -Messari $null -CyclePhase "BULL-HISTORICO(6-18m)"
        ($out.macro_outlook) | Should Be "BULLISH"
    }

    It "score baixo retorna macro_outlook BEARISH" {
        $out = Invoke-FundFallback -Coin $null -Defi $null -Messari $null -CyclePhase "POSSIVEL-BEAR"
        ($out.macro_outlook) | Should Be "BEARISH"
    }

    It "score neutro retorna macro_outlook NEUTRO" {
        $out = Invoke-FundFallback -Coin $null -Defi $null -Messari $null -CyclePhase "CONSOLIDACAO-POS-HALVING"
        ($out.macro_outlook) | Should Be "NEUTRO"
    }
}

Describe "Invoke-FundFallback - ajustes de dados externos" {

    It "wash trading alto (ratio 0.1) penaliza score" {
        $base = Invoke-FundFallback -Coin $null -Defi $null -Messari $null -CyclePhase "CONSOLIDACAO-POS-HALVING"
        $penalizado = Invoke-FundFallback -Coin $null -Defi $null -Messari (New-Messari 0.1) -CyclePhase "CONSOLIDACAO-POS-HALVING"
        ($penalizado.score_fundamental) | Should BeLessThan ($base.score_fundamental)
    }

    It "volume organico (ratio 0.7) eleva score" {
        $base = Invoke-FundFallback -Coin $null -Defi $null -Messari $null -CyclePhase "CONSOLIDACAO-POS-HALVING"
        $elevado = Invoke-FundFallback -Coin $null -Defi $null -Messari (New-Messari 0.7) -CyclePhase "CONSOLIDACAO-POS-HALVING"
        ($elevado.score_fundamental) | Should BeGreaterThan ($base.score_fundamental)
    }

    It "TVL alto (120B) eleva score" {
        $base = Invoke-FundFallback -Coin $null -Defi $null -Messari $null -CyclePhase "CONSOLIDACAO-POS-HALVING"
        $elevado = Invoke-FundFallback -Coin $null -Defi (New-Defi 120) -Messari $null -CyclePhase "CONSOLIDACAO-POS-HALVING"
        ($elevado.score_fundamental) | Should BeGreaterThan ($base.score_fundamental)
    }

    It "score nunca excede 100" {
        $out = Invoke-FundFallback -Coin (New-Coin 20) -Defi (New-Defi 150) -Messari (New-Messari 0.8) -CyclePhase "BULL-HISTORICO(6-18m)"
        ($out.score_fundamental) | Should BeLessThan 101
    }

    It "score nunca e negativo" {
        $out = Invoke-FundFallback -Coin (New-Coin -20) -Defi (New-Defi 10) -Messari (New-Messari 0.05) -CyclePhase "POSSIVEL-BEAR"
        ($out.score_fundamental) | Should BeGreaterThan -1
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHAINFALLBACK
# ═══════════════════════════════════════════════════════════════════════════════

Describe "Invoke-ChainFallback - whale signal domina" {

    It "whale BULLISH eleva score acima de 60" {
        $out = Invoke-ChainFallback -Whale (New-Whale "BULLISH") -HashRibbon $null -EthConc $null -Nupl $null -DaysPostHalv 400
        ($out.chain_score) | Should BeGreaterThan 60
    }

    It "whale BEARISH reduz score abaixo de 40" {
        $out = Invoke-ChainFallback -Whale (New-Whale "BEARISH") -HashRibbon $null -EthConc $null -Nupl $null -DaysPostHalv 400
        ($out.chain_score) | Should BeLessThan 40
    }

    It "whale BULLISH mapeia comportamento_whales para ACUMULANDO" {
        $out = Invoke-ChainFallback -Whale (New-Whale "BULLISH") -HashRibbon $null -EthConc $null -Nupl $null -DaysPostHalv 400
        ($out.comportamento_whales) | Should Be "ACUMULANDO"
    }

    It "whale BEARISH mapeia comportamento_whales para DISTRIBUINDO" {
        $out = Invoke-ChainFallback -Whale (New-Whale "BEARISH") -HashRibbon $null -EthConc $null -Nupl $null -DaysPostHalv 400
        ($out.comportamento_whales) | Should Be "DISTRIBUINDO"
    }
}

Describe "Invoke-ChainFallback - hash ribbon e concentracao" {

    It "hash ribbon BUY_SIGNAL eleva score" {
        $base = Invoke-ChainFallback -Whale $null -HashRibbon $null -EthConc $null -Nupl $null -DaysPostHalv 400
        $out  = Invoke-ChainFallback -Whale $null -HashRibbon (New-HashRibbon "BUY_SIGNAL") -EthConc $null -Nupl $null -DaysPostHalv 400
        ($out.chain_score) | Should BeGreaterThan ($base.chain_score)
    }

    It "concentracao CRITICAL penaliza score em 15" {
        $base = Invoke-ChainFallback -Whale $null -HashRibbon $null -EthConc $null -Nupl $null -DaysPostHalv 400
        $out  = Invoke-ChainFallback -Whale $null -HashRibbon $null -EthConc (New-EthConc "CRITICAL") -Nupl $null -DaysPostHalv 400
        ($out.chain_score) | Should Be ($base.chain_score - 15)
    }

    It "hash ribbon BEARISH reduz score" {
        $base = Invoke-ChainFallback -Whale $null -HashRibbon $null -EthConc $null -Nupl $null -DaysPostHalv 400
        $out  = Invoke-ChainFallback -Whale $null -HashRibbon (New-HashRibbon "BEARISH") -EthConc $null -Nupl $null -DaysPostHalv 400
        ($out.chain_score) | Should BeLessThan ($base.chain_score)
    }
}

Describe "Invoke-ChainFallback - chain_bias e campos" {

    It "score alto retorna chain_bias BULLISH" {
        $out = Invoke-ChainFallback -Whale (New-Whale "BULLISH") -HashRibbon (New-HashRibbon "BUY_SIGNAL") -EthConc $null -Nupl $null -DaysPostHalv 400
        ($out.chain_bias) | Should Be "BULLISH"
    }

    It "score baixo retorna chain_bias BEARISH" {
        $out = Invoke-ChainFallback -Whale (New-Whale "BEARISH") -HashRibbon (New-HashRibbon "BEARISH") -EthConc (New-EthConc "CRITICAL") -Nupl $null -DaysPostHalv 400
        ($out.chain_bias) | Should Be "BEARISH"
    }

    It "score nunca excede 100" {
        $out = Invoke-ChainFallback -Whale (New-Whale "BULLISH") -HashRibbon (New-HashRibbon "BUY_SIGNAL") -EthConc $null -Nupl (New-Nupl 10) -DaysPostHalv 400
        ($out.chain_score) | Should BeLessThan 101
    }

    It "score nunca e negativo" {
        $out = Invoke-ChainFallback -Whale (New-Whale "BEARISH") -HashRibbon (New-HashRibbon "BEARISH") -EthConc (New-EthConc "CRITICAL") -Nupl (New-Nupl 90) -DaysPostHalv 800
        ($out.chain_score) | Should BeGreaterThan -1
    }

    It "hash_ribbon preenchido com sinal real" {
        $out = Invoke-ChainFallback -Whale $null -HashRibbon (New-HashRibbon "BUY_SIGNAL") -EthConc $null -Nupl $null -DaysPostHalv 400
        ($out.hash_ribbon) | Should Be "BUY_SIGNAL"
    }

    It "supply_fase REDUCAO ATIVA quando 180-540 dias pos-halving" {
        $out = Invoke-ChainFallback -Whale $null -HashRibbon $null -EthConc $null -Nupl $null -DaysPostHalv 400
        ($out.supply_fase) | Should Be "REDUCAO ATIVA"
    }
}
