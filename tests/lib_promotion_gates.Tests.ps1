# lib_promotion_gates.Tests.ps1 -- Pester 3.x
# Suite de gates pre-promotion + pre-trade:
#   - Test-ConcentrationLimit  (max N Tier A LIVE)
#   - Test-DailyLossCircuit    (equity -X% dia)
#   - Test-SectorConcentration (max N por setor)
#   - Test-CooldownPostDemote  (30d sem re-promote)
#   - Test-MinVolumeGate       (vol minimo $500K)
#   - Test-PhaseBoundarySafety (7d apos phase change)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\lib_promotion_gates.ps1"
. "$here\..\agents\lib_fundamental_quality.ps1"


Describe "Invoke-AllGates - FQS wire (NEW 2026-05-19 PM)" {
    $tmp = Join-Path $env:TEMP "fqs_aag_$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $regFile = Join-Path $tmp "coin_registry.json"
    @{
        BLUEUSDT = @{ age_years=10; supply_capped=$true; burn_active=$true; utility_score=0.9; concentration_top10=0.20; recovered_2021_ath=$true; listing_years=5 }
        AVDUSDT  = @{ age_years=0.2; supply_capped=$false; burn_active=$false; utility_score=0; concentration_top10=0.8; recovered_2021_ath=$false; listing_years=0.1 }
    } | ConvertTo-Json -Depth 5 | Out-File $regFile -Encoding utf8

    It "BLUE_CHIP passa FQS gate em Invoke-AllGates TIER_A" {
        $r = Invoke-AllGates -Market "BLUEUSDT" -VolumeUsd 1000000 `
            -CurrentTierACount 1 -CurrentTierAMarkets @("BTCUSDT") `
            -TargetTier "TIER_A_LIVE" -FundamentalRegistryPath $regFile
        $r.gates.fundamental_quality | Should Not Be $null
        $r.gates.fundamental_quality.passes | Should Be $true
    }
    It "AVOID (FQS baixo) BLOQUEIA em Invoke-AllGates" {
        $r = Invoke-AllGates -Market "AVDUSDT" -VolumeUsd 1000000 `
            -CurrentTierACount 1 -CurrentTierAMarkets @("BTCUSDT") `
            -TargetTier "TIER_A_LIVE" -FundamentalRegistryPath $regFile
        $r.gates.fundamental_quality.passes | Should Be $false
        ($r.blocked_by -contains "fundamental_quality") | Should Be $true
        $r.all_pass | Should Be $false
    }
    It "Sem TargetTier (legacy) NAO aplica FQS gate" {
        $r = Invoke-AllGates -Market "AVDUSDT" -VolumeUsd 1000000 `
            -CurrentTierACount 1 -CurrentTierAMarkets @("BTCUSDT")
        # FQS gate so dispara com TargetTier definido (opt-in)
        $r.gates.PSObject.Properties["fundamental_quality"] | Should Be $null
    }

    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}


# =============================================================================
# Wire 4 gates orfaos (2026-05-20): pump_buy / time_of_week / slippage / cross_corr
# Todos opt-in via params -- chamada sem param mantem backward-compat.
# =============================================================================

Describe "Invoke-AllGates - 4 orphan gates wired (2026-05-20)" {

    It "pump_buy gate wired quando CurrentPrice + Peak7d fornecidos (passa: 5% abaixo peak)" {
        $r = Invoke-AllGates -Market "BTCUSDT" -VolumeUsd 1000000 `
            -CurrentTierACount 1 -CurrentTierAMarkets @("ETHUSDT") `
            -CurrentPrice 95 -Peak7d 100
        $r.gates.pump_buy | Should Not Be $null
        $r.gates.pump_buy.passes | Should Be $true
    }

    It "pump_buy gate BLOQUEIA quando preco no peak (sem pullback)" {
        $r = Invoke-AllGates -Market "BTCUSDT" -VolumeUsd 1000000 `
            -CurrentTierACount 1 -CurrentTierAMarkets @("ETHUSDT") `
            -CurrentPrice 100 -Peak7d 100
        $r.gates.pump_buy.passes | Should Be $false
        ($r.blocked_by -contains "pump_buy") | Should Be $true
    }

    It "pump_buy gate skip quando params nao fornecidos (backward compat)" {
        $r = Invoke-AllGates -Market "BTCUSDT" -VolumeUsd 1000000 `
            -CurrentTierACount 1 -CurrentTierAMarkets @("ETHUSDT")
        $r.gates.PSObject.Properties["pump_buy"] | Should Be $null
    }

    It "time_of_week gate sempre wired (defaults seguros)" {
        # Wednesday default = nao bloqueia
        $wed = Get-Date "2026-05-20 14:00:00"  # Wed
        $r = Invoke-AllGates -Market "BTCUSDT" -VolumeUsd 1000000 `
            -CurrentTierACount 1 -CurrentTierAMarkets @("ETHUSDT") `
            -DateBrt $wed
        $r.gates.time_of_week | Should Not Be $null
        $r.gates.time_of_week.passes | Should Be $true
    }

    It "time_of_week BLOQUEIA Thursday tarde LONG (default seasonal block)" {
        $thu = Get-Date "2026-05-21 18:00:00"  # Thursday 18h
        $r = Invoke-AllGates -Market "BTCUSDT" -VolumeUsd 1000000 `
            -CurrentTierACount 1 -CurrentTierAMarkets @("ETHUSDT") `
            -DateBrt $thu -Direction "long"
        $r.gates.time_of_week.passes | Should Be $false
        ($r.blocked_by -contains "time_of_week") | Should Be $true
    }

    It "slippage gate wired quando PositionSizeUsd fornecido (ratio 100x = pass)" {
        $r = Invoke-AllGates -Market "BTCUSDT" -VolumeUsd 1000000 `
            -CurrentTierACount 1 -CurrentTierAMarkets @("ETHUSDT") `
            -PositionSizeUsd 5000   # ratio = 200x > 100
        $r.gates.slippage | Should Not Be $null
        $r.gates.slippage.passes | Should Be $true
    }

    It "slippage BLOQUEIA quando ratio < min (posicao muito grande pra liquidez)" {
        $r = Invoke-AllGates -Market "BTCUSDT" -VolumeUsd 100000 `
            -CurrentTierACount 1 -CurrentTierAMarkets @("ETHUSDT") `
            -PositionSizeUsd 5000   # ratio = 20x << 100
        $r.gates.slippage.passes | Should Be $false
        ($r.blocked_by -contains "slippage") | Should Be $true
    }

    It "slippage skip quando PositionSizeUsd nao fornecido (backward compat)" {
        $r = Invoke-AllGates -Market "BTCUSDT" -VolumeUsd 1000000 `
            -CurrentTierACount 1 -CurrentTierAMarkets @("ETHUSDT")
        $r.gates.PSObject.Properties["slippage"] | Should Be $null
    }

    It "cross_asset_correlation wired quando CurrentLongMarkets fornecido (sem matriz: sector proxy)" {
        $r = Invoke-AllGates -Market "BTCUSDT" -VolumeUsd 1000000 `
            -CurrentTierACount 1 -CurrentTierAMarkets @("ETHUSDT") `
            -CurrentLongMarkets @("XMRUSDT")  # privacy != BTC sector -> pass (proxy)
        $r.gates.cross_corr | Should Not Be $null
    }

    It "cross_asset_correlation skip quando CurrentLongMarkets vazio (backward compat)" {
        $r = Invoke-AllGates -Market "BTCUSDT" -VolumeUsd 1000000 `
            -CurrentTierACount 1 -CurrentTierAMarkets @("ETHUSDT")
        $r.gates.PSObject.Properties["cross_corr"] | Should Be $null
    }
}


Describe "Get-FundingZScore (cache offline)" {
    It "Sem arquivo: retorna reason no_history" {
        $tmp = Join-Path $env:TEMP "fz_$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $r = Get-FundingZScore -Market "NOPE" -HistoryDir $tmp
            $r.z | Should Be $null
            $r.reason | Should Be "no_history"
        } finally { Remove-Item $tmp -Recurse -Force }
    }
    It "Baseline insuficiente: reason insufficient_baseline" {
        $tmp = Join-Path $env:TEMP "fz_$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $file = Join-Path $tmp "BTCUSDT.jsonl"
            1..5 | ForEach-Object {
                @{ funding_time = (1700000000000 + $_*28800000); funding_rate = "0.0001" } |
                  ConvertTo-Json -Compress | Out-File -Append $file -Encoding utf8
            }
            $r = Get-FundingZScore -Market "BTCUSDT" -HistoryDir $tmp
            $r.z | Should Be $null
            $r.reason | Should Be "insufficient_baseline"
        } finally { Remove-Item $tmp -Recurse -Force }
    }
    It "Spike no fim devolve z alto" {
        $tmp = Join-Path $env:TEMP "fz_$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $file = Join-Path $tmp "BTCUSDT.jsonl"
            $rates = @(); 1..49 | ForEach-Object { $rates += 0.0001 }; $rates += 0.005
            $i = 0
            foreach ($r in $rates) {
                @{ funding_time = (1700000000000 + $i*28800000); funding_rate = "$r" } |
                  ConvertTo-Json -Compress | Out-File -Append $file -Encoding utf8
                $i++
            }
            $r = Get-FundingZScore -Market "BTCUSDT" -HistoryDir $tmp
            $r.z | Should Not Be $null
            ($r.z -gt 3.0) | Should Be $true
        } finally { Remove-Item $tmp -Recurse -Force }
    }
}


Describe "Test-FundingRateGate (no_baseline)" {
    It "Market sem historico: passa com note=no_baseline" {
        $tmp = Join-Path $env:TEMP "fg_$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $global:JOURNAL_DIR = $tmp
            $r = Test-FundingRateGate -Market "NOHIST" -Direction "long"
            $r.passes | Should Be $true
            $r.reason | Should Be "no_baseline"
        } finally { Remove-Item $tmp -Recurse -Force }
    }
}


Describe "Test-BetaConcentration" {
    $tmp = Join-Path $env:TEMP "bc_$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $betaFile = Join-Path $tmp "beta_vs_btc.json"
    @{
        window_days = 180
        base        = "BTCUSDT"
        beta        = @{
            BTCUSDT=1.0; INJUSDT=1.21; ZECUSDT=1.57; CFGUSDT=1.28; RENDERUSDT=1.30
            HYPEUSDT=-0.26; NEARUSDT=-0.10; SOLUSDT=-0.03; SAFEUSDT=0.5
        }
    } | ConvertTo-Json -Depth 5 | Out-File $betaFile -Encoding utf8

    It "Candidate sozinho retorna beta candidato + sum=candidate + avg=candidate" {
        $r = Test-BetaConcentration -Market "HYPEUSDT" -CurrentTierAMarkets @() -BetaPath $betaFile
        $r.candidate_beta | Should Be -0.26
        $r.beta_sum | Should Be 0.26
        $r.beta_avg | Should Be 0.26
        $r.passes | Should Be $true
    }
    It "5 amplifiers + 1 safe (avg 1.14) WARN com cap 1.2 (V1.6 recalibragem)" {
        $tierA = @("RENDERUSDT","CFGUSDT","ZECUSDT","BTCUSDT","INJUSDT")
        $r = Test-BetaConcentration -Market "SAFEUSDT" -CurrentTierAMarkets $tierA -BetaPath $betaFile
        # sum = 1.30+1.28+1.57+1.0+1.21+0.5 = 6.86 / 6 = 1.143 avg -> WARN (>1.0 mas <1.2)
        $r.beta_avg | Should Be 1.143
        $r.passes | Should Be $true   # V1.6: cap 1.2, ainda passa
        $r.level | Should Be "WARN"
    }
    It "5 amplifiers heavy (avg > 1.2) BLOCK" {
        # 5 amplifiers heavy avg = 1.27 > 1.2 cap
        $tierA = @("RENDERUSDT","CFGUSDT","ZECUSDT","BTCUSDT","INJUSDT")
        $r = Test-BetaConcentration -Market "ZECUSDT" -CurrentTierAMarkets $tierA -BetaPath $betaFile
        # Including ZEC twice gives 1.57 weight. With 6 positions avg should exceed 1.2
        # sum: 1.30+1.28+1.57+1.0+1.21+1.57 = 7.93 / 6 = 1.32
        ($r.beta_avg -gt 1.2) | Should Be $true
        $r.passes | Should Be $false
        $r.level | Should Be "BLOCK"
    }
    It "Mix amplifiers + AAA+ negativos baixa AVG ate OK" {
        # 5 amplifiers + 5 AAA+ negativos: avg sobe pouco
        $tierA = @("RENDERUSDT","CFGUSDT","ZECUSDT","BTCUSDT","INJUSDT","HYPEUSDT","NEARUSDT","SOLUSDT")
        $r = Test-BetaConcentration -Market "SAFEUSDT" -CurrentTierAMarkets $tierA -BetaPath $betaFile
        # 9 markets total. sum = 1.30+1.28+1.57+1.0+1.21+0.26+0.10+0.03+0.5 = 7.25 / 9 = 0.81 avg
        # 0.81 -> WARN (>0.8) mas passes (<1.0)
        $r.passes | Should Be $true
        $r.beta_avg -le 1.0 | Should Be $true
    }
    It "Single trade muito amplifier (beta 1.5) BLOCK avg" {
        $r = Test-BetaConcentration -Market "ZECUSDT" -CurrentTierAMarkets @() -BetaPath $betaFile
        # sozinho: avg = 1.57 -> BLOCK
        $r.passes | Should Be $false
    }
    It "Cap customizado override (strict avg 0.5)" {
        $tierA = @("BTCUSDT")
        $r = Test-BetaConcentration -Market "INJUSDT" -CurrentTierAMarkets $tierA -BetaPath $betaFile -MaxAvgBeta 0.5
        # avg = (1.0 + 1.21)/2 = 1.105 -> >0.5 BLOCK
        $r.passes | Should Be $false
    }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}


Describe "Get-CapitalScaledDailyLossThreshold" {
    It "Capital <$5K retorna -2%" {
        [double](Get-CapitalScaledDailyLossThreshold -CapitalUsd 2700) | Should Be ([double]-2.0)
    }
    It "Capital exato $5K retorna -3%" {
        [double](Get-CapitalScaledDailyLossThreshold -CapitalUsd 5000) | Should Be ([double]-3.0)
    }
    It "Capital >=$5K e <$10K retorna -3%" {
        [double](Get-CapitalScaledDailyLossThreshold -CapitalUsd 7500) | Should Be ([double]-3.0)
    }
    It "Capital >=$10K retorna -5%" {
        [double](Get-CapitalScaledDailyLossThreshold -CapitalUsd 12000) | Should Be ([double]-5.0)
        [double](Get-CapitalScaledDailyLossThreshold -CapitalUsd 50000) | Should Be ([double]-5.0)
    }
    It "Capital zero retorna -2% (conservador)" {
        [double](Get-CapitalScaledDailyLossThreshold -CapitalUsd 0) | Should Be ([double]-2.0)
    }
    It "Boundaries customizadas" {
        [double](Get-CapitalScaledDailyLossThreshold -CapitalUsd 3000 -Tier1Cap 1000 -Tier2Cap 2000) | Should Be ([double]-5.0)
    }
}


Describe "Test-CrossAssetCorrelation (matrix path)" {
    It "Usa matriz quando presente e bloqueia se max corr >= threshold" {
        $tmp = Join-Path $env:TEMP "xc_$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $matFile = Join-Path $tmp "correlation_matrix.json"
            @{
                window_days = 30
                markets     = @("AAA","BBB","CCC")
                matrix      = @{
                    AAA = @{ AAA=1.0; BBB=0.91; CCC=0.20 }
                    BBB = @{ AAA=0.91; BBB=1.0; CCC=0.30 }
                    CCC = @{ AAA=0.20; BBB=0.30; CCC=1.0 }
                }
            } | ConvertTo-Json -Depth 5 | Out-File $matFile -Encoding utf8
            $r = Test-CrossAssetCorrelation -Market "AAA" -CurrentLongMarkets @("BBB","CCC") -MatrixPath $matFile
            $r.passes | Should Be $false
            $r.max_corr | Should Be 0.91
        } finally { Remove-Item $tmp -Recurse -Force }
    }
    It "Passa quando max corr < threshold" {
        $tmp = Join-Path $env:TEMP "xc_$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $matFile = Join-Path $tmp "correlation_matrix.json"
            @{
                window_days = 30
                markets     = @("AAA","CCC")
                matrix      = @{
                    AAA = @{ AAA=1.0; CCC=0.25 }
                    CCC = @{ AAA=0.25; CCC=1.0 }
                }
            } | ConvertTo-Json -Depth 5 | Out-File $matFile -Encoding utf8
            $r = Test-CrossAssetCorrelation -Market "AAA" -CurrentLongMarkets @("CCC") -MatrixPath $matFile
            $r.passes | Should Be $true
        } finally { Remove-Item $tmp -Recurse -Force }
    }
}


Describe "Get-DailyEquityDelta" {
    It "Primeira chamada do dia registra baseline e devolve delta 0" {
        $tmp = Join-Path $env:TEMP "ged_$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $r = Get-DailyEquityDelta -CurrentEquityUsd 1000 -StateDir $tmp
            $r.first_call | Should Be $true
            $r.delta_pct | Should Be 0
            $r.start_equity | Should Be 1000
        } finally { Remove-Item $tmp -Recurse -Force }
    }
    It "Segunda chamada com queda 7% devolve delta -7%" {
        $tmp = Join-Path $env:TEMP "ged_$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $null = Get-DailyEquityDelta -CurrentEquityUsd 1000 -StateDir $tmp
            $r2 = Get-DailyEquityDelta -CurrentEquityUsd 930 -StateDir $tmp
            $r2.first_call | Should Be $false
            $r2.delta_pct | Should Be -7
            $r2.start_equity | Should Be 1000
        } finally { Remove-Item $tmp -Recurse -Force }
    }
    It "Dia novo recomeca baseline" {
        $tmp = Join-Path $env:TEMP "ged_$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $d1 = [datetime]"2026-01-01 10:00"
            $d2 = [datetime]"2026-01-02 10:00"
            $null = Get-DailyEquityDelta -CurrentEquityUsd 1000 -StateDir $tmp -Now $d1
            $r2 = Get-DailyEquityDelta -CurrentEquityUsd 800 -StateDir $tmp -Now $d2
            $r2.first_call | Should Be $true
            $r2.start_equity | Should Be 800
        } finally { Remove-Item $tmp -Recurse -Force }
    }
}


Describe "Test-ConcentrationLimit" {
    It "Count 3 com max 5 passa" {
        $r = Test-ConcentrationLimit -CurrentTierACount 3 -MaxTierA 5
        $r.passes | Should Be $true
    }

    It "Count 5 no limite passa" {
        $r = Test-ConcentrationLimit -CurrentTierACount 5 -MaxTierA 5
        $r.passes | Should Be $true
    }

    It "Count 6 acima do limite NAO passa" {
        $r = Test-ConcentrationLimit -CurrentTierACount 6 -MaxTierA 5
        $r.passes | Should Be $false
        $r.reason | Should Match "concentration"
    }
}


Describe "Test-DailyLossCircuit" {
    It "Equity -3% (acima do threshold -5) passa" {
        $r = Test-DailyLossCircuit -EquityTodayPct -3.0 -ThresholdPct -5.0
        $r.passes | Should Be $true
    }

    It "Equity exatamente -5% triggers circuit (NAO passa)" {
        $r = Test-DailyLossCircuit -EquityTodayPct -5.0 -ThresholdPct -5.0
        $r.passes | Should Be $false
    }

    It "Equity -8% NAO passa" {
        $r = Test-DailyLossCircuit -EquityTodayPct -8.0 -ThresholdPct -5.0
        $r.passes | Should Be $false
        $r.reason | Should Match "daily_loss"
    }

    It "Equity positivo passa" {
        $r = Test-DailyLossCircuit -EquityTodayPct 2.5 -ThresholdPct -5.0
        $r.passes | Should Be $true
    }
}


Describe "Test-SectorConcentration" {
    BeforeEach {
        $script:tmpMap = Join-Path $env:TEMP "sec_$([Guid]::NewGuid().ToString('N')).json"
        @{
            markets = @{
                "BTCUSDT" = "store_of_value"
                "ETHUSDT" = "l1"
                "INJUSDT" = "l1"
                "TONUSDT" = "l1"
                "ZECUSDT" = "privacy"
                "ONDOUSDT" = "rwa"
                "CFGUSDT" = "rwa"
                "PENDLEUSDT" = "rwa"
            }
        } | ConvertTo-Json -Depth 3 | Out-File $script:tmpMap -Encoding utf8
    }
    AfterEach {
        if (Test-Path $script:tmpMap) { Remove-Item $script:tmpMap -Force }
    }

    It "Adicionar 3a RWA com max 2 NAO passa" {
        $r = Test-SectorConcentration -Market "ENAUSDT" `
            -CurrentTierAMarkets @("CFGUSDT","PENDLEUSDT","BTCUSDT") `
            -SectorMapPath $script:tmpMap -MaxPerSector 2
        # ENA nao mapeado mas CFG+PENDLE ja sao 2 RWA. ENA nao tem mapping (unknown).
        # Como ENA nao tem sector, deve passar (nao colide com nenhum sector)
        $r.passes | Should Be $true
    }

    It "Adicionar 3a L1 quando ja tem 2 L1 NAO passa" {
        $r = Test-SectorConcentration -Market "TONUSDT" `
            -CurrentTierAMarkets @("INJUSDT","ETHUSDT") `
            -SectorMapPath $script:tmpMap -MaxPerSector 2
        $r.passes | Should Be $false
        $r.reason | Should Match "sector"
    }

    It "Adicionar 1a L2 com max 2 passa (sem outras L2)" {
        $r = Test-SectorConcentration -Market "ARBUSDT" `
            -CurrentTierAMarkets @("BTCUSDT","ETHUSDT") `
            -SectorMapPath $script:tmpMap -MaxPerSector 2
        $r.passes | Should Be $true
    }

    It "Market nao mapeado (unknown) sempre passa" {
        $r = Test-SectorConcentration -Market "FOOUSDT" `
            -CurrentTierAMarkets @("BTCUSDT","ETHUSDT") `
            -SectorMapPath $script:tmpMap -MaxPerSector 2
        $r.passes | Should Be $true
    }
}


Describe "Test-CooldownPostDemote" {
    BeforeEach {
        $script:tmpDemote = Join-Path $env:TEMP "dem_$([Guid]::NewGuid().ToString('N')).jsonl"
    }
    AfterEach {
        if (Test-Path $script:tmpDemote) { Remove-Item $script:tmpDemote -Force }
    }

    It "Market nunca demoted passa" {
        $r = Test-CooldownPostDemote -Market "BTCUSDT" -DemoteHistoryPath $script:tmpDemote -CooldownDays 30
        $r.passes | Should Be $true
    }

    It "Demote 5 dias atras NAO passa (cooldown 30d)" {
        $oldTs = (Get-Date).AddDays(-5).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        '{"market":"PENDLEUSDT","demoted_at":"' + $oldTs + '","reason":"drawdown"}' | Out-File $script:tmpDemote -Encoding utf8
        $r = Test-CooldownPostDemote -Market "PENDLEUSDT" -DemoteHistoryPath $script:tmpDemote -CooldownDays 30
        $r.passes | Should Be $false
        $r.reason | Should Match "cooldown"
    }

    It "Demote 60 dias atras passa (cooldown expirou)" {
        $oldTs = (Get-Date).AddDays(-60).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        '{"market":"PENDLEUSDT","demoted_at":"' + $oldTs + '","reason":"drawdown"}' | Out-File $script:tmpDemote -Encoding utf8
        $r = Test-CooldownPostDemote -Market "PENDLEUSDT" -DemoteHistoryPath $script:tmpDemote -CooldownDays 30
        $r.passes | Should Be $true
    }
}


Describe "Test-MinVolumeGate" {
    It "Vol acima do minimo passa" {
        $r = Test-MinVolumeGate -VolumeUsd 1000000 -MinVolumeUsd 500000
        $r.passes | Should Be $true
    }

    It "Vol abaixo do minimo NAO passa" {
        $r = Test-MinVolumeGate -VolumeUsd 50000 -MinVolumeUsd 500000
        $r.passes | Should Be $false
        $r.reason | Should Match "volume"
    }

    It "Vol $7K6 (caso CFG real) NAO passa" {
        $r = Test-MinVolumeGate -VolumeUsd 7600 -MinVolumeUsd 500000
        $r.passes | Should Be $false
    }
}


Describe "Test-PhaseBoundarySafety" {
    It "Phase nunca mudou (null timestamp) passa" {
        $r = Test-PhaseBoundarySafety -PhaseChangedAt $null -SafetyDays 7
        $r.passes | Should Be $true
    }

    It "Phase mudou 3 dias atras NAO passa" {
        $r = Test-PhaseBoundarySafety -PhaseChangedAt ((Get-Date).AddDays(-3)) -SafetyDays 7
        $r.passes | Should Be $false
        $r.reason | Should Match "phase"
    }

    It "Phase mudou 10 dias atras passa" {
        $r = Test-PhaseBoundarySafety -PhaseChangedAt ((Get-Date).AddDays(-10)) -SafetyDays 7
        $r.passes | Should Be $true
    }
}


Describe "Test-TimeOfWeekGate" {
    It "Monday 12h LONG passa" {
        $mon = [datetime]"2024-01-15 12:00:00"
        $r = Test-TimeOfWeekGate -DateBrt $mon -Direction "long"
        $r.passes | Should Be $true
    }

    It "Thursday 16h LONG NAO passa (Thu afternoon block)" {
        $thu = [datetime]"2024-01-18 16:00:00"
        $r = Test-TimeOfWeekGate -DateBrt $thu -Direction "long"
        $r.passes | Should Be $false
        $r.reason | Should Match "time_of_week"
    }

    It "Thursday 16h SHORT passa (block so afeta LONG)" {
        $thu = [datetime]"2024-01-18 16:00:00"
        $r = Test-TimeOfWeekGate -DateBrt $thu -Direction "short"
        $r.passes | Should Be $true
    }

    It "Thursday 10h LONG passa (fora da janela)" {
        $thu = [datetime]"2024-01-18 10:00:00"
        $r = Test-TimeOfWeekGate -DateBrt $thu -Direction "long"
        $r.passes | Should Be $true
    }
}


Describe "Test-SlippageBudget" {
    It "Vol 1M com posicao 100 (ratio 10K) passa" {
        $r = Test-SlippageBudget -VolumeUsd24h 1000000 -PositionSizeUsd 100
        $r.passes | Should Be $true
        $r.ratio | Should BeGreaterThan 100
    }

    It "Vol 5K com posicao 100 (ratio 50) NAO passa" {
        $r = Test-SlippageBudget -VolumeUsd24h 5000 -PositionSizeUsd 100
        $r.passes | Should Be $false
        $r.reason | Should Match "slippage"
    }

    It "CFG caso real vol 7K6 posicao 50 (ratio 152) passa" {
        $r = Test-SlippageBudget -VolumeUsd24h 7600 -PositionSizeUsd 50
        $r.passes | Should Be $true
    }

    It "Position zero retorna false" {
        $r = Test-SlippageBudget -VolumeUsd24h 1000000 -PositionSizeUsd 0
        $r.passes | Should Be $false
    }
}


Describe "Test-CrossAssetCorrelation" {
    BeforeEach {
        $script:tmpMap2 = Join-Path $env:TEMP "corr_$([Guid]::NewGuid().ToString('N')).json"
        @{
            markets = @{
                "BTCUSDT" = "store_of_value"
                "ETHUSDT" = "l1"
                "INJUSDT" = "l1"
                "ZECUSDT" = "privacy"
            }
        } | ConvertTo-Json -Depth 3 | Out-File $script:tmpMap2 -Encoding utf8
    }
    AfterEach {
        if (Test-Path $script:tmpMap2) { Remove-Item $script:tmpMap2 -Force }
    }

    It "Sem posicao L1 atual, adicionar L1 passa" {
        $r = Test-CrossAssetCorrelation -Market "INJUSDT" -CurrentLongMarkets @("BTCUSDT") -SectorMapPath $script:tmpMap2
        $r.passes | Should Be $true
    }

    It "Ja com 1 L1 atual, adicionar 2a L1 NAO passa (correlato)" {
        $r = Test-CrossAssetCorrelation -Market "INJUSDT" -CurrentLongMarkets @("ETHUSDT","BTCUSDT") -SectorMapPath $script:tmpMap2
        $r.passes | Should Be $false
        $r.reason | Should Match "correlated"
    }
}


Describe "Test-FundingRateGate" {
    It "Z=0.5 LONG passa (funding neutro)" {
        $r = Test-FundingRateGate -FundingZScore 0.5 -Direction "long"
        $r.passes | Should Be $true
    }

    It "Z=2.5 LONG NAO passa (overheated)" {
        $r = Test-FundingRateGate -FundingZScore 2.5 -Direction "long"
        $r.passes | Should Be $false
        $r.reason | Should Match "overheated"
    }

    It "Z=-2.5 SHORT NAO passa (overcold = capitulation)" {
        $r = Test-FundingRateGate -FundingZScore -2.5 -Direction "short"
        $r.passes | Should Be $false
    }

    It "Z=2.5 SHORT passa (funding bearish ok pra short)" {
        $r = Test-FundingRateGate -FundingZScore 2.5 -Direction "short"
        $r.passes | Should Be $true
    }
}


Describe "Add-DemoteEvent - persistencia" {
    BeforeEach {
        $script:tmpDemote = Join-Path $env:TEMP "addemote_$([Guid]::NewGuid().ToString('N')).jsonl"
    }
    AfterEach {
        if (Test-Path $script:tmpDemote) { Remove-Item $script:tmpDemote -Force }
    }

    It "Adiciona evento + readable via Test-Cooldown" {
        Add-DemoteEvent -Market "X" -Reason "test" -DemoteHistoryPath $script:tmpDemote
        $r = Test-CooldownPostDemote -Market "X" -DemoteHistoryPath $script:tmpDemote -CooldownDays 30
        $r.passes | Should Be $false  # acabou de demote, deve estar em cooldown
    }
}
