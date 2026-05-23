# gem_agent.Tests.ps1 -- Pester 3.x TDD (RED phase) para agents/gem_agent.ps1
# Cobre: Get-CoinExVolSpike, Test-NarrativeMatch, Test-OrganicAccumulation,
#         Invoke-GemScore, Get-GemSizing
# Rodar: Invoke-Pester .\tests\gem_agent.Tests.ps1 -Verbose

$global:ANTHROPIC_API_KEY             = $null
$global:COINEX_ACCESS_ID              = $null
$global:COINEX_SECRET_KEY             = $null
$global:COINEX_BASE_URL               = "https://api.coinex.com"
$global:CLAUDE_MODEL                  = "claude-sonnet-4"
$global:CLAUDE_MAX_TOKENS             = 2048
$global:CLAUDE_TEMP_TRADE             = 0.3
$global:COINEX_FEE_ROUNDTRIP_FALLBACK = 0.0008
$global:COINEX_FEE_MAKER_FALLBACK     = 0.0003
$global:COINEX_FEE_TAKER_FALLBACK     = 0.0005
$global:CAPITAL_TOTAL                 = 1000.0
$global:RISCO_MAXIMO_PCT              = 0.01

$global:GEM_VOL_SPIKE_MIN    = 2.0
$global:GEM_MCAP_DISCOVERY   = 2000000.0
$global:GEM_MCAP_MOMENTUM    = 20000000.0
$global:GEM_LISTING_DAYS_MAX = 10
$global:GEM_CAPITAL_DISCOVERY = 0.002
$global:GEM_CAPITAL_MOMENTUM  = 0.004
$global:GEM_STOP_DISCOVERY    = 0.50
$global:GEM_STOP_MOMENTUM     = 0.30
$global:GEM_TARGET_DISCOVERY  = 2.00
$global:GEM_TARGET_MOMENTUM   = 0.90
$global:GEM_MAX_DAYS_DISC     = 30
$global:GEM_MAX_DAYS_MOM      = 21
$global:GEM_TRAILING_PCT      = 0.30
$global:GEM_SCORE_MIN_DISC    = 70
$global:GEM_SCORE_MIN_MOM     = 60
$global:GEM_CV_ORGANIC_MIN    = 0.5
$global:GEM_WASH_MAX_PCT      = 0.40
$global:GEM_GREEN_RATIO_MIN   = 0.65
$global:GEM_WICK_RATIO_MAX    = 2.5
$global:GEM_RANGE_MIN_PCT     = 0.15

function Write-Host    { param() }
function Write-Warning { param() }
function Invoke-RestMethod {
    param([string]$Uri, [string]$Method, [hashtable]$Headers)
    return $null
}
function Invoke-Claude     { param([string]$s, [string]$u) return "{}" }
function Invoke-ClaudeJson { param([string]$s, [string]$u) return $null }

. "$PSScriptRoot\..\agents\gem_agent.ps1"

# helpers para construir candles de teste
function New-Candle {
    param([double]$open, [double]$high, [double]$low, [double]$close, [double]$volume, [string]$ts = "2024-01-01T00:00:00Z")
    [PSCustomObject]@{ open=$open; high=$high; low=$low; close=$close; volume=$volume; ts=$ts }
}

function New-DailyCandle { param([double]$vol) New-Candle 100 110 90 105 $vol }
function New-DailyOHLCV  { param([double]$open, [double]$close, [double]$vol) New-Candle $open ($open*1.05) ($close*0.95) $close $vol }

# ─────────────────────────────────────────────────────────────────────────────
#  Get-CoinExVolSpike
# ─────────────────────────────────────────────────────────────────────────────

Describe "Get-CoinExVolSpike" {

    Context "spike acima do threshold 2.0x" {
        It "retorna passed=true quando vol_hoje / avg_3d > 2.0" {
            $candles = @(
                (New-DailyCandle 100000),
                (New-DailyCandle 120000),
                (New-DailyCandle 110000),
                (New-DailyCandle 280000)   # hoje: 280K vs avg 110K = 2.55x
            )
            $r = Get-CoinExVolSpike -Market "SKYAIUSDT" -DailyCandles $candles
            $r.passed | Should Be $true
        }

        It "calcula spike_ratio corretamente" {
            $candles = @(
                (New-DailyCandle 100000),
                (New-DailyCandle 100000),
                (New-DailyCandle 100000),
                (New-DailyCandle 230000)   # exatamente 2.3x
            )
            $r = Get-CoinExVolSpike -Market "TESTUSDT" -DailyCandles $candles
            $r.spike_ratio | Should BeGreaterThan 2.29
            $r.spike_ratio | Should BeLessThan 2.31
        }

        It "retorna campos obrigatorios" {
            $candles = @(
                (New-DailyCandle 100000),
                (New-DailyCandle 100000),
                (New-DailyCandle 100000),
                (New-DailyCandle 250000)
            )
            $r = Get-CoinExVolSpike -Market "TESTUSDT" -DailyCandles $candles
            $names = @($r.PSObject.Properties.Name)
            ($names -contains "market")      | Should Be $true
            ($names -contains "vol_today")   | Should Be $true
            ($names -contains "avg_3d")      | Should Be $true
            ($names -contains "spike_ratio") | Should Be $true
            ($names -contains "passed")      | Should Be $true
        }
    }

    Context "spike abaixo do threshold" {
        It "retorna passed=false quando vol_hoje / avg_3d < 2.0" {
            $candles = @(
                (New-DailyCandle 100000),
                (New-DailyCandle 100000),
                (New-DailyCandle 100000),
                (New-DailyCandle 150000)   # 1.5x apenas
            )
            $r = Get-CoinExVolSpike -Market "FLATUSDT" -DailyCandles $candles
            $r.passed | Should Be $false
        }
    }

    Context "dados insuficientes" {
        It "retorna passed=false com menos de 4 candles" {
            $candles = @(
                (New-DailyCandle 100000),
                (New-DailyCandle 200000)
            )
            $r = Get-CoinExVolSpike -Market "SHORTUSDT" -DailyCandles $candles
            $r.passed | Should Be $false
        }

        It "nao lanca excecao com candles vazios" {
            $r = Get-CoinExVolSpike -Market "EMPTYUSDT" -DailyCandles @()
            $r | Should Not BeNullOrEmpty
            $r.passed | Should Be $false
        }

        It "nao lanca excecao com avg_3d zero" {
            $candles = @(
                (New-DailyCandle 0),
                (New-DailyCandle 0),
                (New-DailyCandle 0),
                (New-DailyCandle 100000)
            )
            $r = Get-CoinExVolSpike -Market "ZEROUSDT" -DailyCandles $candles
            $r | Should Not BeNullOrEmpty
            $r.passed | Should Be $false
        }
    }

    Context "spike_type: direcao do preco no dia do spike" {
        It "spike_type BEARISH quando preco cai mais de 10%" {
            $candles = @(
                (New-DailyOHLCV 100 105 100000),
                (New-DailyOHLCV 105 103 110000),
                (New-DailyOHLCV 103 101 90000),
                (New-DailyOHLCV 100  78 300000)   # -22% no dia, spike 3x
            )
            $r = Get-CoinExVolSpike -Market "DISTUSDT" -DailyCandles $candles
            $r.spike_type | Should Be "BEARISH"
        }

        It "spike_type BULLISH quando preco sobe mais de 5%" {
            $candles = @(
                (New-DailyOHLCV 100 102 100000),
                (New-DailyOHLCV 102 101 110000),
                (New-DailyOHLCV 101 103 90000),
                (New-DailyOHLCV 100 112 300000)   # +12% no dia, spike 3x
            )
            $r = Get-CoinExVolSpike -Market "PUMPUSDT" -DailyCandles $candles
            $r.spike_type | Should Be "BULLISH"
        }

        It "spike_type NEUTRAL quando preco varia entre -10% e +5%" {
            $candles = @(
                (New-DailyOHLCV 100 102 100000),
                (New-DailyOHLCV 102 101 110000),
                (New-DailyOHLCV 101 103 90000),
                (New-DailyOHLCV 100 103 300000)   # +3% no dia
            )
            $r = Get-CoinExVolSpike -Market "FLATUSDT" -DailyCandles $candles
            $r.spike_type | Should Be "NEUTRAL"
        }

        It "pct_change_today calculado corretamente" {
            $candles = @(
                (New-DailyOHLCV 100 105 100000),
                (New-DailyOHLCV 105 103 110000),
                (New-DailyOHLCV 103 101 90000),
                (New-DailyOHLCV 100  80 300000)   # -20% exato
            )
            $r = Get-CoinExVolSpike -Market "TESTUSDT" -DailyCandles $candles
            $r.pct_change_today | Should BeLessThan -19
            $r.pct_change_today | Should BeGreaterThan -21
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Test-NarrativeMatch
# ─────────────────────────────────────────────────────────────────────────────

Describe "Test-NarrativeMatch" {

    Context "keyword Tier 1 no nome do par" {
        It "detecta keyword AI" {
            $r = Test-NarrativeMatch -Market "SKYAIUSDT" -CoinGeckoRank $null
            $r.matched    | Should Be $true
            $r.tier       | Should Be 1
            $r.score_pts  | Should Be 15
        }

        It "detecta keyword PEPE" {
            $r = Test-NarrativeMatch -Market "PEPEUSDT" -CoinGeckoRank $null
            $r.matched   | Should Be $true
            $r.tier      | Should Be 1
        }

        It "detecta keyword GPT" {
            $r = Test-NarrativeMatch -Market "CHATGPTUSDT" -CoinGeckoRank $null
            $r.matched | Should Be $true
            $r.tier    | Should Be 1
        }

        It "detecta keyword DOGE" {
            $r = Test-NarrativeMatch -Market "BABYDOGEUSDT" -CoinGeckoRank $null
            $r.matched | Should Be $true
            $r.tier    | Should Be 1
        }
    }

    Context "keyword Tier 2 no nome do par" {
        It "detecta keyword GAME" {
            $r = Test-NarrativeMatch -Market "GAMEFIUSDT" -CoinGeckoRank $null
            $r.matched   | Should Be $true
            $r.tier      | Should Be 2
            $r.score_pts | Should Be 8
        }

        It "detecta keyword YIELD" {
            $r = Test-NarrativeMatch -Market "YIELDUSDT" -CoinGeckoRank $null
            $r.matched | Should Be $true
            $r.tier    | Should Be 2
        }
    }

    Context "sem keyword mas com CoinGecko trending" {
        It "retorna matched=true com rank < 500" {
            $r = Test-NarrativeMatch -Market "RANDOMUSDT" -CoinGeckoRank 203
            $r.matched      | Should Be $true
            $r.trending_rank | Should Be 203
        }

        It "rank < 200 da pontuacao maxima de trending" {
            $r = Test-NarrativeMatch -Market "RANDOMUSDT" -CoinGeckoRank 150
            $r.score_pts | Should BeGreaterThan 10
        }

        It "rank entre 200-500 da pontuacao parcial" {
            $r_low  = Test-NarrativeMatch -Market "AAUSDT" -CoinGeckoRank 450
            $r_high = Test-NarrativeMatch -Market "BBUSDT" -CoinGeckoRank 100
            $r_low.score_pts | Should BeLessThan $r_high.score_pts
        }
    }

    Context "sem narrativa" {
        It "retorna matched=false sem keyword e sem trending" {
            $r = Test-NarrativeMatch -Market "SDUSDT" -CoinGeckoRank $null
            $r.matched   | Should Be $false
            $r.score_pts | Should Be 0
        }

        It "retorna campos obrigatorios mesmo sem match" {
            $r = Test-NarrativeMatch -Market "NOUSDT" -CoinGeckoRank $null
            $names = @($r.PSObject.Properties.Name)
            ($names -contains "matched")      | Should Be $true
            ($names -contains "tier")         | Should Be $true
            ($names -contains "keyword")      | Should Be $true
            ($names -contains "trending_rank")| Should Be $true
            ($names -contains "score_pts")    | Should Be $true
        }
    }

    Context "keyword + trending combinados" {
        It "keyword Tier 1 + trending rank < 200 soma pontuacao maxima 15" {
            $r = Test-NarrativeMatch -Market "AIUSDT" -CoinGeckoRank 100
            $r.score_pts | Should Be 15
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Test-OrganicAccumulation
# ─────────────────────────────────────────────────────────────────────────────

Describe "Test-OrganicAccumulation" {

    Context "volume organico heterogeneo" {
        It "retorna passed=true com CV > 0.5" {
            # volumes muito variados = organico
            $c5 = @(
                (New-Candle 100 105 98 104 5000),
                (New-Candle 104 112 103 111 15000),
                (New-Candle 111 113 108 109 8000),
                (New-Candle 109 120 109 119 25000),
                (New-Candle 119 122 115 117 11000),
                (New-Candle 117 125 116 124 32000)
            )
            $c1 = $c5  # simplificado para teste
            $r = Test-OrganicAccumulation -Candles5min $c5 -Candles1min $c1
            $r.passed | Should Be $true
        }

        It "retorna organic_score > 50 com volumes heterogeneos" {
            $c5 = @(
                (New-Candle 100 108 99 107 3000),
                (New-Candle 107 115 106 114 18000),
                (New-Candle 114 116 110 111 7000),
                (New-Candle 111 122 111 121 29000),
                (New-Candle 121 124 118 120 9000)
            )
            $r = Test-OrganicAccumulation -Candles5min $c5 -Candles1min $c5
            $r.organic_score | Should BeGreaterThan 50
        }
    }

    Context "volume de wash trading" {
        It "retorna wash_detected=true com volumes identicos" {
            # volumes quase identicos = bot
            $c5 = @(
                (New-Candle 100 101 99 100 10000),
                (New-Candle 100 101 99 100 10020),
                (New-Candle 100 101 99 100 9980),
                (New-Candle 100 101 99 100 10010),
                (New-Candle 100 101 99 100 9990),
                (New-Candle 100 101 99 100 10005)
            )
            $r = Test-OrganicAccumulation -Candles5min $c5 -Candles1min $c5
            $r.wash_detected | Should Be $true
        }

        It "retorna passed=false quando wash > 40% dos candles" {
            $c5 = @(
                (New-Candle 100 101 99 100 10000),
                (New-Candle 100 101 99 100 10020),
                (New-Candle 100 101 99 100 9980),
                (New-Candle 100 101 99 100 10010),
                (New-Candle 100 101 99 100 9990),
                (New-Candle 100 101 99 100 10005)
            )
            $r = Test-OrganicAccumulation -Candles5min $c5 -Candles1min $c5
            $r.passed | Should Be $false
        }
    }

    Context "pressao vendedora por wicks superiores excessivos" {
        It "reduz organic_score quando wicks superiores > 2.5x inferiores" {
            # wicks superiores grandes = sellers absorvendo cada impulso
            $c5_clean = @(
                (New-Candle 100 103 99 102 10000),
                (New-Candle 102 105 101 104 12000),
                (New-Candle 104 107 103 106 11000)
            )
            $c5_wicks = @(
                (New-Candle 100 115 99 101 10000),  # wick up = 14, wick down = 1
                (New-Candle 101 116 100 102 12000),
                (New-Candle 102 117 101 103 11000)
            )
            $r_clean = Test-OrganicAccumulation -Candles5min $c5_clean -Candles1min $c5_clean
            $r_wicks = Test-OrganicAccumulation -Candles5min $c5_wicks -Candles1min $c5_wicks
            $r_clean.organic_score | Should BeGreaterThan $r_wicks.organic_score
        }
    }

    Context "dados insuficientes" {
        It "nao lanca excecao com candles vazios" {
            $r = Test-OrganicAccumulation -Candles5min @() -Candles1min @()
            $r | Should Not BeNullOrEmpty
            $r.passed | Should Be $false
        }

        It "retorna campos obrigatorios" {
            $c = @( (New-Candle 100 105 98 103 5000) )
            $r = Test-OrganicAccumulation -Candles5min $c -Candles1min $c
            $names = @($r.PSObject.Properties.Name)
            ($names -contains "organic_score") | Should Be $true
            ($names -contains "cv_volume")     | Should Be $true
            ($names -contains "green_ratio")   | Should Be $true
            ($names -contains "wash_detected") | Should Be $true
            ($names -contains "passed")        | Should Be $true
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Invoke-GemScore
# ─────────────────────────────────────────────────────────────────────────────

Describe "Invoke-GemScore" {

    $vol_ok = [PSCustomObject]@{
        passed      = $true
        spike_ratio = 4.2
        vol_today   = 420000
        avg_3d      = 100000
    }

    $narrative_ok = [PSCustomObject]@{
        matched      = $true
        tier         = 1
        keyword      = "AI"
        trending_rank = 203
        score_pts    = 15
    }

    $organic_ok = [PSCustomObject]@{
        passed        = $true
        organic_score = 74
        wash_detected = $false
    }

    Context "todos os gates passam -- modo DISCOVERY" {
        It "retorna score >= 70 quando todos os gates passam" {
            $r = Invoke-GemScore `
                -Market "SKYAIUSDT" `
                -VolData $vol_ok `
                -NarrativeData $narrative_ok `
                -McapUsd 1200000 `
                -PctRange 0.35 `
                -StructurePassed $true `
                -OrganicData $organic_ok `
                -FingerprintScore 78
            $r.score | Should BeGreaterThan 69
        }

        It "retorna mode=DISCOVERY quando mcap abaixo de 2M" {
            $r = Invoke-GemScore `
                -Market "SKYAIUSDT" `
                -VolData $vol_ok `
                -NarrativeData $narrative_ok `
                -McapUsd 1200000 `
                -PctRange 0.35 `
                -StructurePassed $true `
                -OrganicData $organic_ok `
                -FingerprintScore 78
            $r.mode | Should Be "DISCOVERY"
        }

        It "retorna mode=MOMENTUM quando mcap entre 2M-20M" {
            $r = Invoke-GemScore `
                -Market "ATRUSDT" `
                -VolData $vol_ok `
                -NarrativeData $narrative_ok `
                -McapUsd 5000000 `
                -PctRange 0.25 `
                -StructurePassed $true `
                -OrganicData $organic_ok `
                -FingerprintScore 65
            $r.mode | Should Be "MOMENTUM"
        }

        It "retorna campos obrigatorios" {
            $r = Invoke-GemScore `
                -Market "TESTUSDT" `
                -VolData $vol_ok `
                -NarrativeData $narrative_ok `
                -McapUsd 1000000 `
                -PctRange 0.20 `
                -StructurePassed $true `
                -OrganicData $organic_ok `
                -FingerprintScore 60
            $names = @($r.PSObject.Properties.Name)
            ($names -contains "market")       | Should Be $true
            ($names -contains "score")        | Should Be $true
            ($names -contains "mode")         | Should Be $true
            ($names -contains "gates_passed") | Should Be $true
            ($names -contains "gate_failed")  | Should Be $true
            ($names -contains "sizing_pct")   | Should Be $true
            ($names -contains "alerta")       | Should Be $true
        }
    }

    Context "gate G1 (volume) falha -- bloqueia imediatamente" {
        It "retorna score = 0 quando vol spike nao passa" {
            $vol_fail = [PSCustomObject]@{ passed=$false; spike_ratio=1.5; vol_today=150000; avg_3d=100000 }
            $r = Invoke-GemScore `
                -Market "FLATUSDT" `
                -VolData $vol_fail `
                -NarrativeData $narrative_ok `
                -McapUsd 1000000 `
                -PctRange 0.30 `
                -StructurePassed $true `
                -OrganicData $organic_ok `
                -FingerprintScore 70
            $r.score | Should Be 0
        }

        It "aponta gate_failed = G1 quando volume insuficiente" {
            $vol_fail = [PSCustomObject]@{ passed=$false; spike_ratio=1.5; vol_today=150000; avg_3d=100000 }
            $r = Invoke-GemScore `
                -Market "FLATUSDT" `
                -VolData $vol_fail `
                -NarrativeData $narrative_ok `
                -McapUsd 1000000 `
                -PctRange 0.30 `
                -StructurePassed $true `
                -OrganicData $organic_ok `
                -FingerprintScore 70
            $r.gate_failed | Should Be "G1"
        }
    }

    Context "gate G4 (narrativa) falha -- SDUSDT pattern" {
        It "retorna score abaixo de 70 sem narrativa (SDUSDT pattern)" {
            $no_narrative = [PSCustomObject]@{ matched=$false; tier=0; keyword=""; trending_rank=$null; score_pts=0 }
            $r = Invoke-GemScore `
                -Market "SDUSDT" `
                -VolData $vol_ok `
                -NarrativeData $no_narrative `
                -McapUsd 1000000 `
                -PctRange 0.30 `
                -StructurePassed $true `
                -OrganicData $organic_ok `
                -FingerprintScore 60
            $r.score | Should BeLessThan 70
        }
    }

    Context "gate G6 (organico) falha -- wash trading" {
        It "penaliza score quando wash_detected = true" {
            $wash = [PSCustomObject]@{ passed=$false; organic_score=20; wash_detected=$true }
            $r_wash  = Invoke-GemScore -Market "WASHUSDT"  -VolData $vol_ok -NarrativeData $narrative_ok -McapUsd 1000000 -PctRange 0.30 -StructurePassed $true -OrganicData $wash      -FingerprintScore 60
            $r_clean = Invoke-GemScore -Market "CLEANUSDT" -VolData $vol_ok -NarrativeData $narrative_ok -McapUsd 1000000 -PctRange 0.30 -StructurePassed $true -OrganicData $organic_ok -FingerprintScore 60
            $r_wash.score | Should BeLessThan $r_clean.score
        }
    }

    Context "mcap fora dos limites de gem" {
        It "nao entra em DISCOVERY quando mcap > 2M" {
            $r = Invoke-GemScore `
                -Market "BIGUSDT" `
                -VolData $vol_ok `
                -NarrativeData $narrative_ok `
                -McapUsd 50000000 `
                -PctRange 0.30 `
                -StructurePassed $true `
                -OrganicData $organic_ok `
                -FingerprintScore 70
            $r.mode | Should Not Be "DISCOVERY"
        }

        It "retorna gate_failed=G3 quando mcap > 20M" {
            $r = Invoke-GemScore `
                -Market "BIGCAPUSDT" `
                -VolData $vol_ok `
                -NarrativeData $narrative_ok `
                -McapUsd 50000000 `
                -PctRange 0.30 `
                -StructurePassed $true `
                -OrganicData $organic_ok `
                -FingerprintScore 70
            $r.gate_failed | Should Be "G3"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Get-GemSizing
# ─────────────────────────────────────────────────────────────────────────────

Describe "Get-GemSizing" {

    Context "modo DISCOVERY" {
        It "retorna sizing_pct = 0.002 para DISCOVERY" {
            $r = Get-GemSizing -Mode "DISCOVERY" -BtcDominance 58.0 -Capital 1000.0
            $r.sizing_pct | Should Be 0.002
        }

        It "retorna sizing_usd = 2.0 para capital de 1000" {
            $r = Get-GemSizing -Mode "DISCOVERY" -BtcDominance 58.0 -Capital 1000.0
            $r.sizing_usd | Should Be 2.0
        }

        It "retorna stop_pct = 0.50 para DISCOVERY" {
            $r = Get-GemSizing -Mode "DISCOVERY" -BtcDominance 58.0 -Capital 1000.0
            $r.stop_pct | Should Be 0.50
        }

        It "retorna target_pct = 2.00 para DISCOVERY" {
            $r = Get-GemSizing -Mode "DISCOVERY" -BtcDominance 58.0 -Capital 1000.0
            $r.target_pct | Should Be 2.00
        }

        It "retorna max_days = 30 para DISCOVERY" {
            $r = Get-GemSizing -Mode "DISCOVERY" -BtcDominance 58.0 -Capital 1000.0
            $r.max_days | Should Be 30
        }
    }

    Context "modo MOMENTUM" {
        It "retorna sizing_pct = 0.004 para MOMENTUM" {
            $r = Get-GemSizing -Mode "MOMENTUM" -BtcDominance 50.0 -Capital 1000.0
            $r.sizing_pct | Should Be 0.004
        }

        It "retorna sizing_usd = 4.0 para capital de 1000" {
            $r = Get-GemSizing -Mode "MOMENTUM" -BtcDominance 50.0 -Capital 1000.0
            $r.sizing_usd | Should Be 4.0
        }

        It "retorna stop_pct = 0.30 para MOMENTUM" {
            $r = Get-GemSizing -Mode "MOMENTUM" -BtcDominance 50.0 -Capital 1000.0
            $r.stop_pct | Should Be 0.30
        }

        It "retorna target_pct = 0.90 para MOMENTUM" {
            $r = Get-GemSizing -Mode "MOMENTUM" -BtcDominance 50.0 -Capital 1000.0
            $r.target_pct | Should Be 0.90
        }

        It "retorna max_days = 21 para MOMENTUM" {
            $r = Get-GemSizing -Mode "MOMENTUM" -BtcDominance 50.0 -Capital 1000.0
            $r.max_days | Should Be 21
        }
    }

    Context "moon bag" {
        It "retorna moon_bag_pct = 0.50 em ambos os modos" {
            $rd = Get-GemSizing -Mode "DISCOVERY" -BtcDominance 55.0 -Capital 1000.0
            $rm = Get-GemSizing -Mode "MOMENTUM"  -BtcDominance 55.0 -Capital 1000.0
            $rd.moon_bag_pct | Should Be 0.50
            $rm.moon_bag_pct | Should Be 0.50
        }

        It "retorna trailing_pct = 0.30 para o moon bag" {
            $r = Get-GemSizing -Mode "DISCOVERY" -BtcDominance 55.0 -Capital 1000.0
            $r.trailing_pct | Should Be 0.30
        }
    }

    Context "calculo de sizing para outros capitais" {
        It "sizing_usd escala proporcionalmente com capital" {
            $r = Get-GemSizing -Mode "DISCOVERY" -BtcDominance 55.0 -Capital 5000.0
            $r.sizing_usd | Should Be 10.0
        }

        It "retorna campos obrigatorios" {
            $r = Get-GemSizing -Mode "DISCOVERY" -BtcDominance 55.0 -Capital 1000.0
            $names = @($r.PSObject.Properties.Name)
            ($names -contains "mode")         | Should Be $true
            ($names -contains "sizing_pct")   | Should Be $true
            ($names -contains "sizing_usd")   | Should Be $true
            ($names -contains "stop_pct")     | Should Be $true
            ($names -contains "target_pct")   | Should Be $true
            ($names -contains "max_days")     | Should Be $true
            ($names -contains "moon_bag_pct") | Should Be $true
            ($names -contains "trailing_pct") | Should Be $true
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Output schema -- extended fields (mcap_usd, listing_days, narrative,
#  organic_score, gates_passed, fingerprint_match, btc_dominance, logo_url)
# ─────────────────────────────────────────────────────────────────────────────

Describe "Output schema -- extended fields" {

    $vol_ok = [PSCustomObject]@{
        passed      = $true
        spike_ratio = 4.2
        vol_today   = 420000
        avg_3d      = 100000
        spike_type  = "BULLISH"
        pct_change_today = 8.0
    }
    $narrative_ok = [PSCustomObject]@{
        matched       = $true
        tier          = 1
        keyword       = "AI"
        trending_rank = 203
        score_pts     = 15
    }
    $organic_ok = [PSCustomObject]@{
        passed        = $true
        organic_score = 74
        wash_detected = $false
        uncertain     = $false
    }

    Context "campos adicionais presentes no objeto de saida" {
        It "expoe mcap_usd" {
            $r = Invoke-GemScore -Market "SKYAIUSDT" -VolData $vol_ok -NarrativeData $narrative_ok -McapUsd 1200000 -PctRange 0.35 -StructurePassed $true -OrganicData $organic_ok -FingerprintScore 78 -LogoUrl "https://x/logo.png" -ListingDays 5
            $names = @($r.PSObject.Properties.Name)
            ($names -contains "mcap_usd") | Should Be $true
        }
        It "expoe listing_days" {
            $r = Invoke-GemScore -Market "SKYAIUSDT" -VolData $vol_ok -NarrativeData $narrative_ok -McapUsd 1200000 -PctRange 0.35 -StructurePassed $true -OrganicData $organic_ok -FingerprintScore 78 -LogoUrl "https://x/logo.png" -ListingDays 5
            $names = @($r.PSObject.Properties.Name)
            ($names -contains "listing_days") | Should Be $true
        }
        It "expoe narrative" {
            $r = Invoke-GemScore -Market "SKYAIUSDT" -VolData $vol_ok -NarrativeData $narrative_ok -McapUsd 1200000 -PctRange 0.35 -StructurePassed $true -OrganicData $organic_ok -FingerprintScore 78 -LogoUrl "https://x/logo.png" -ListingDays 5
            $names = @($r.PSObject.Properties.Name)
            ($names -contains "narrative") | Should Be $true
        }
        It "expoe organic_score numerico entre 0 e 100" {
            $r = Invoke-GemScore -Market "SKYAIUSDT" -VolData $vol_ok -NarrativeData $narrative_ok -McapUsd 1200000 -PctRange 0.35 -StructurePassed $true -OrganicData $organic_ok -FingerprintScore 78 -LogoUrl "https://x/logo.png" -ListingDays 5
            $names = @($r.PSObject.Properties.Name)
            ($names -contains "organic_score") | Should Be $true
            $r.organic_score | Should BeGreaterThan -1
            $r.organic_score | Should BeLessThan 101
        }
        It "expoe gates_passed como array" {
            $r = Invoke-GemScore -Market "SKYAIUSDT" -VolData $vol_ok -NarrativeData $narrative_ok -McapUsd 1200000 -PctRange 0.35 -StructurePassed $true -OrganicData $organic_ok -FingerprintScore 78 -LogoUrl "https://x/logo.png" -ListingDays 5
            $names = @($r.PSObject.Properties.Name)
            ($names -contains "gates_passed") | Should Be $true
            ($r.gates_passed -is [System.Collections.IEnumerable]) | Should Be $true
            ($r.gates_passed -is [string]) | Should Be $false
        }
        It "expoe fingerprint_match" {
            $r = Invoke-GemScore -Market "SKYAIUSDT" -VolData $vol_ok -NarrativeData $narrative_ok -McapUsd 1200000 -PctRange 0.35 -StructurePassed $true -OrganicData $organic_ok -FingerprintScore 78 -LogoUrl "https://x/logo.png" -ListingDays 5
            $names = @($r.PSObject.Properties.Name)
            ($names -contains "fingerprint_match") | Should Be $true
        }
        It "expoe logo_url" {
            $r = Invoke-GemScore -Market "SKYAIUSDT" -VolData $vol_ok -NarrativeData $narrative_ok -McapUsd 1200000 -PctRange 0.35 -StructurePassed $true -OrganicData $organic_ok -FingerprintScore 78 -LogoUrl "https://x/logo.png" -ListingDays 5
            $names = @($r.PSObject.Properties.Name)
            ($names -contains "logo_url") | Should Be $true
        }
    }

    Context "gates_passed reflete estado real de cada gate" {
        It "todos os 7 gates passam -- gates_passed tem 7 elementos" {
            $r = Invoke-GemScore -Market "SKYAIUSDT" -VolData $vol_ok -NarrativeData $narrative_ok -McapUsd 1200000 -PctRange 0.35 -StructurePassed $true -OrganicData $organic_ok -FingerprintScore 78 -LogoUrl "https://x/logo.png" -ListingDays 5
            @($r.gates_passed).Count | Should Be 7
        }
        It "G1 passa, G3 short-circuit -- gates_passed contem G1 mas nao G2 ou alem" {
            # vol_ok faz G1 passar; mcap > 20M faz G3 short-circuit antes de avaliar G2
            $r = Invoke-GemScore -Market "BIGUSDT" -VolData $vol_ok -NarrativeData $narrative_ok -McapUsd 50000000 -PctRange 0.05 -StructurePassed $false -OrganicData $organic_ok -FingerprintScore 30 -LogoUrl $null -ListingDays $null
            ($r.gates_passed -contains "G1") | Should Be $true
            ($r.gates_passed -contains "G2") | Should Be $false
            ($r.gates_passed -contains "G3") | Should Be $false
        }
    }

    Context "logo_url valido" {
        It "logo_url casa regex de http quando definido" {
            $r = Invoke-GemScore -Market "SKYAIUSDT" -VolData $vol_ok -NarrativeData $narrative_ok -McapUsd 1200000 -PctRange 0.35 -StructurePassed $true -OrganicData $organic_ok -FingerprintScore 78 -LogoUrl "https://assets.coingecko.com/coins/images/1/small/logo.png" -ListingDays 5
            $r.logo_url | Should Match "^https?://"
        }
    }
}

