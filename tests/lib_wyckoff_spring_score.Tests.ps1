$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_wyckoff_spring_score.ps1")

Describe "Get-MonthsPostHalving" {
    It "Retorna ~25 para maio 2026 (halving 2024-04)" {
        $r = Get-MonthsPostHalving -NowUtc ([datetime]::new(2026,5,22,0,0,0,[DateTimeKind]::Utc))
        # 25 months +/- 0.5
        ($r -ge 24.5 -and $r -le 25.5) | Should Be $true
    }
    It "Retorna ~21 para 2022-02 (halving 2020-05)" {
        $r = Get-MonthsPostHalving -NowUtc ([datetime]::new(2022,2,15,0,0,0,[DateTimeKind]::Utc))
        ($r -ge 20.5 -and $r -le 21.5) | Should Be $true
    }
    It "Retorna -1 para data pre-halving 2020" {
        $r = Get-MonthsPostHalving -NowUtc ([datetime]::new(2018,1,1,0,0,0,[DateTimeKind]::Utc))
        $r | Should Be -1
    }
}

Describe "_WSS-ScoreMonthsPostHalving" {
    It "Mph 14 (bucket 12-18) retorna 95 (prime sweet)" {
        _WSS-ScoreMonthsPostHalving -Mph 14 | Should Be 95
    }
    It "Mph 20 (bucket 18-22) retorna 60 (transition)" {
        _WSS-ScoreMonthsPostHalving -Mph 20 | Should Be 60
    }
    It "Mph 25 (bucket 22-26) retorna 85 (secondary sweet)" {
        _WSS-ScoreMonthsPostHalving -Mph 25 | Should Be 85
    }
    It "Mph negativo (pre-halving) retorna 30" {
        _WSS-ScoreMonthsPostHalving -Mph -2 | Should Be 30
    }
}

Describe "_WSS-ScoreDdZone" {
    It "DD -25 (sweet zone) retorna 100" {
        _WSS-ScoreDdZone -DrawdownPct -25 | Should Be 100
    }
    It "DD -45 (just outside) retorna 60" {
        _WSS-ScoreDdZone -DrawdownPct -45 | Should Be 60
    }
    It "DD 0 (no drawdown, fora de qualquer zona) retorna 0" {
        # 0 nao bate -40 a -15, nem -50 a -10, nem -55 a -5 → fall-through
        _WSS-ScoreDdZone -DrawdownPct 0 | Should Be 0
    }
    It "DD -8 (zona ampla -55 a -5) retorna 30" {
        _WSS-ScoreDdZone -DrawdownPct -8 | Should Be 30
    }
    It "DD -70 (too deep) retorna 0" {
        _WSS-ScoreDdZone -DrawdownPct -70 | Should Be 0
    }
    It "DD null retorna 50 (neutro)" {
        _WSS-ScoreDdZone -DrawdownPct $null | Should Be 50
    }
}

Describe "_WSS-ScoreDdZone -- Side SHORT (curva invertida, 2026-07-25)" {
    # mce_counterfactual_agg (dado real, n=24): NEUTRO|SHORT hit_rate=87.5%,
    # o melhor edge medido. ESTUDO_GATES_SHORT_2026_07_03.md: BEAR_STRONG
    # (drawdown profundo) win=24%, 52% toca stop adverso (squeeze risk).
    # Sweet zone do SHORT = drawdown RASO, oposto do LONG/Spring.
    It "Side padrao (omitido) preserva comportamento LONG -- zero regressao" {
        _WSS-ScoreDdZone -DrawdownPct -25 | Should Be 100
        _WSS-ScoreDdZone -DrawdownPct -70 | Should Be 0
    }
    It "DD 0 a -15 (sweet zone SHORT, drawdown raso) retorna 100" {
        _WSS-ScoreDdZone -DrawdownPct 0 -Side "SHORT" | Should Be 100
        _WSS-ScoreDdZone -DrawdownPct -10 -Side "SHORT" | Should Be 100
        _WSS-ScoreDdZone -DrawdownPct -15 -Side "SHORT" | Should Be 100
    }
    It "DD -15 a -25 (transicao) retorna 60" {
        _WSS-ScoreDdZone -DrawdownPct -20 -Side "SHORT" | Should Be 60
    }
    It "DD -25 a -40 (aprofundando) retorna 30" {
        _WSS-ScoreDdZone -DrawdownPct -30 -Side "SHORT" | Should Be 30
    }
    It "DD alem de -40 (capitulacao profunda, squeeze risk) retorna 0" {
        _WSS-ScoreDdZone -DrawdownPct -45 -Side "SHORT" | Should Be 0
        _WSS-ScoreDdZone -DrawdownPct -70 -Side "SHORT" | Should Be 0
    }
    It "DD null com Side SHORT retorna 50 (neutro, mesma regra do LONG)" {
        _WSS-ScoreDdZone -DrawdownPct $null -Side "SHORT" | Should Be 50
    }
    It "curva SHORT e literalmente oposta a LONG no mesmo DD" {
        # DD -25: LONG=100 (sweet), SHORT=60 (ja saindo da zona rasa)
        (_WSS-ScoreDdZone -DrawdownPct -25 -Side "LONG") | Should Be 100
        (_WSS-ScoreDdZone -DrawdownPct -25 -Side "SHORT") | Should Be 60
        # DD -5: LONG=30 (fora do sweet), SHORT=100 (bem raso, sweet)
        (_WSS-ScoreDdZone -DrawdownPct -5 -Side "LONG") | Should Be 30
        (_WSS-ScoreDdZone -DrawdownPct -5 -Side "SHORT") | Should Be 100
    }
}

Describe "_WSS-ClusterPenalty" {
    It "Cluster 1 (solo) retorna 0" {
        _WSS-ClusterPenalty -ClusterSize 1 | Should Be 0
    }
    It "Cluster 3 retorna 15" {
        _WSS-ClusterPenalty -ClusterSize 3 | Should Be 15
    }
    It "Cluster 11 (correlated bet) retorna 25" {
        _WSS-ClusterPenalty -ClusterSize 11 | Should Be 25
    }
}

Describe "_WSS-ScoreMarketQuality" {
    It "T1 market retorna 100" {
        $qt = @{ "ATOMUSDT" = @{ tier = "T1"; ev_net = 22.6; hit_rate = 100; n = 2 } }
        _WSS-ScoreMarketQuality -Market "ATOMUSDT" -QualityTable $qt | Should Be 100
    }
    It "T3 market retorna 20" {
        $qt = @{ "BNBUSDT" = @{ tier = "T3"; ev_net = -1.28; hit_rate = 33; n = 3 } }
        _WSS-ScoreMarketQuality -Market "BNBUSDT" -QualityTable $qt | Should Be 20
    }
    It "Unknown market retorna 50 (neutro)" {
        _WSS-ScoreMarketQuality -Market "UNKNOWNUSDT" -QualityTable @{} | Should Be 50
    }
}

Describe "_WSS-ScoreBtcVol percentile" {
    It "Vol 3.0% acima de toda a distribuicao [1.0, 2.0] retorna 100" {
        _WSS-ScoreBtcVol -Vol20d 3.0 -VolDistribution @(1.0, 2.0) | Should Be 100
    }
    It "Vol 1.5% no meio retorna 50" {
        _WSS-ScoreBtcVol -Vol20d 1.5 -VolDistribution @(1.0, 2.0) | Should Be 50
    }
    It "Vol null com distribution retorna 50" {
        _WSS-ScoreBtcVol -Vol20d $null -VolDistribution @(1.0, 2.0) | Should Be 50
    }
    It "Vol com distribution vazia retorna 50 (neutro)" {
        _WSS-ScoreBtcVol -Vol20d 2.0 -VolDistribution @() | Should Be 50
    }
}

Describe "Get-WyckoffSpringScore END-TO-END" {
    BeforeAll {
        $script:qt = @{
            "ATOMUSDT" = @{ tier = "T1"; ev_net = 22.6; hit_rate = 100; n = 2 }
            "BNBUSDT"  = @{ tier = "T3"; ev_net = -1.28; hit_rate = 33; n = 3 }
        }
    }

    It "Tier S: market T1 + mph sweet + DD zone + vol high + solo" {
        $r = Get-WyckoffSpringScore -Market "ATOMUSDT" -BtcDrawdownPct -25 -BtcVol20d 3.0 `
              -NowUtc ([datetime]::new(2026,5,22,0,0,0,[DateTimeKind]::Utc)) -ClusterSize 1 `
              -VolDistribution @(1.0,1.5,2.0,2.5,3.5) -QualityTable $script:qt
        # mq=100 * 0.35 + vol_pct=80 * 0.10 + dd=100 * 0.20 + mph=85 * 0.35 - cp=0
        # = 35 + 8 + 20 + 29.75 - 0 = 92.75
        ($r.wss -ge 60) | Should Be $true
        $r.tier | Should Be "S"
    }

    It "Tier B: market T3 + cluster grande + DD ruim" {
        $r = Get-WyckoffSpringScore -Market "BNBUSDT" -BtcDrawdownPct -70 -BtcVol20d 1.0 `
              -NowUtc ([datetime]::new(2026,5,22,0,0,0,[DateTimeKind]::Utc)) -ClusterSize 11 `
              -VolDistribution @(1.5,2.0,2.5,3.0,3.5) -QualityTable $script:qt
        # mq=20 * 0.35 + vol_pct=0 * 0.10 + dd=0 * 0.20 + mph=85 * 0.35 - cp=25
        # = 7 + 0 + 0 + 29.75 - 25 = 11.75
        ($r.wss -lt 45) | Should Be $true
        $r.tier | Should Be "B"
    }

    It "Output structure: PSCustomObject com wss/tier/components" {
        $r = Get-WyckoffSpringScore -Market "ATOMUSDT" -BtcDrawdownPct -25 -BtcVol20d 2.5 `
              -NowUtc ([datetime]::new(2026,5,22,0,0,0,[DateTimeKind]::Utc))
        ($r.wss -is [double]) | Should Be $true
        ($r.tier -in @("S","A","B")) | Should Be $true
        ($r.components.market_quality -is [int]) | Should Be $true
    }

    It "Determinismo: mesma entrada -> mesma saida" {
        $args = @{
            Market = "ATOMUSDT"; BtcDrawdownPct = -22; BtcVol20d = 2.4
            NowUtc = [datetime]::new(2026,5,22,0,0,0,[DateTimeKind]::Utc)
            ClusterSize = 2; VolDistribution = @(1.5,2.0,2.5,3.0); QualityTable = $script:qt
        }
        $r1 = Get-WyckoffSpringScore @args
        $r2 = Get-WyckoffSpringScore @args
        $r1.wss  | Should Be $r2.wss
        $r1.tier | Should Be $r2.tier
    }

    It "WSS clamped [0, 100]" {
        # impossivel ir negativo: mph baixo + cluster max
        $r = Get-WyckoffSpringScore -Market "UNKNOWN" -BtcDrawdownPct -70 -BtcVol20d 0.5 `
              -NowUtc ([datetime]::new(2018,1,1,0,0,0,[DateTimeKind]::Utc)) -ClusterSize 20 `
              -VolDistribution @(1.0,2.0,3.0)
        ($r.wss -ge 0 -and $r.wss -le 100) | Should Be $true
    }

    It "Side omitido (default LONG) preserva wss/tier identico ao comportamento pre-2026-07-25" {
        $args = @{
            Market = "ATOMUSDT"; BtcDrawdownPct = -25; BtcVol20d = 3.0
            NowUtc = [datetime]::new(2026,5,22,0,0,0,[DateTimeKind]::Utc)
            ClusterSize = 1; VolDistribution = @(1.0,1.5,2.0,2.5,3.5); QualityTable = $script:qt
        }
        $withoutSide = Get-WyckoffSpringScore @args
        $withLongSide = Get-WyckoffSpringScore @args -Side "LONG"
        $withoutSide.wss  | Should Be $withLongSide.wss
        $withoutSide.tier | Should Be $withLongSide.tier
    }

    It "Side SHORT em drawdown raso (NEUTRO-like) da tier melhor que Side LONG no mesmo cenario" {
        $args = @{
            Market = "ATOMUSDT"; BtcDrawdownPct = -5; BtcVol20d = 3.0
            NowUtc = [datetime]::new(2026,5,22,0,0,0,[DateTimeKind]::Utc)
            ClusterSize = 1; VolDistribution = @(1.0,1.5,2.0,2.5,3.5); QualityTable = $script:qt
        }
        $long  = Get-WyckoffSpringScore @args -Side "LONG"
        $short = Get-WyckoffSpringScore @args -Side "SHORT"
        ($short.wss -gt $long.wss) | Should Be $true
    }

    It "Side SHORT em drawdown profundo (capitulacao) da tier pior que Side LONG no mesmo cenario" {
        $args = @{
            Market = "ATOMUSDT"; BtcDrawdownPct = -45; BtcVol20d = 3.0
            NowUtc = [datetime]::new(2026,5,22,0,0,0,[DateTimeKind]::Utc)
            ClusterSize = 1; VolDistribution = @(1.0,1.5,2.0,2.5,3.5); QualityTable = $script:qt
        }
        $long  = Get-WyckoffSpringScore @args -Side "LONG"
        $short = Get-WyckoffSpringScore @args -Side "SHORT"
        ($short.wss -lt $long.wss) | Should Be $true
    }
}
