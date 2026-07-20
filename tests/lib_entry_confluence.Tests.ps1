Describe "Entry Confluence Detector" {
    BeforeAll {
        Set-Location $PSScriptRoot/..
        . agents/lib_entry_confluence.ps1
    }

    Context "Volume Climax Detection" {
        It "detecta vol_climax quando vol_24h >> vol_7d" {
            $market = @{name="HYPE"; vol_24h=500000; vol_7d=250000; price=75}
            $result = Test-VolumeClimax -Market $market
            $result.score | Should Be 40
            ($result.confidence -ge 50) | Should Be $true
        }

        It "baixo score quando volume normal" {
            $market = @{name="BTC"; vol_24h=250000; vol_7d=250000; price=42000}
            $result = Test-VolumeClimax -Market $market
            $result.score | Should Be 10
            $result.confidence | Should BeLessThan 10
        }

        It "retorna 0 se market é null" {
            $result = Test-VolumeClimax -Market $null
            $result.score | Should Be 0
        }
    }

    Context "Momentum Bounce Detection" {
        It "detecta bounce quando RSI<30 e preço subindo" {
            # 14 candles com RSI ~20
            $candles = @(
                @{close=100},
                @{close=99},
                @{close=98},
                @{close=97},
                @{close=96},
                @{close=95},
                @{close=94},
                @{close=93},
                @{close=92},
                @{close=91},
                @{close=90},
                @{close=89},
                @{close=88},
                @{close=90}  # bounce up
            )
            $result = Test-MomentumBounce -Candles $candles -RSIThreshold 30
            $result.score | Should Be 30
            $result.reason | Should Match "bounce_yes"
        }

        It "sem bounce quando RSI alto" {
            $candles = @(
                @{close=100},
                @{close=101},
                @{close=102},
                @{close=103},
                @{close=104},
                @{close=105},
                @{close=106},
                @{close=107},
                @{close=108},
                @{close=109},
                @{close=110},
                @{close=111},
                @{close=112},
                @{close=113}
            )
            $result = Test-MomentumBounce -Candles $candles
            $result.score | Should Be 5
        }

        It "retorna 0 se candles insuficientes" {
            $candles = @(@{close=100}, @{close=101})
            $result = Test-MomentumBounce -Candles $candles
            $result.score | Should Be 0
        }
    }

    Context "Structure Support Detection" {
        It "detecta suporte quando preço perto (< 2% acima)" {
            $market = @{name="HYPE"; price=74.8; support_level=73.5; resistance_level=90}  # dist = 1.76%
            $result = Test-StructureSupport -Market $market -BouncePercent 2.0
            $result.score | Should Be 30
            $result.confidence | Should Be 100
        }

        It "score baixo quando longe do suporte" {
            $market = @{name="HYPE"; price=80; support_level=70; resistance_level=90}
            $result = Test-StructureSupport -Market $market
            $result.score | Should Be 10
        }

        It "retorna 0 se sem structure" {
            $result = Test-StructureSupport -Market @{name="UNKNOWN"}
            $result.score | Should Be 0
        }
    }

    Context "Confluence Resolution (Final Decision)" {
        It "retorna readyToEnter=true quando 3 sinais confluem (score>70)" {
            $vol = @{score=40; confidence=80}
            $mom = @{score=30; confidence=70}
            $struct = @{score=30; confidence=60}

            $result = Resolve-ConfluenceScore -VolumeScore $vol -MomentumScore $mom -StructureScore $struct

            $result.confluenceScore | Should BeGreaterThan 70
            $result.readyToEnter | Should Be $true
            $result.entryTiming | Should Be "IMMEDIATE"
        }

        It "retorna readyToEnter=false quando confluência fraca (score<70)" {
            $vol = @{score=10; confidence=20}
            $mom = @{score=5; confidence=10}
            $struct = @{score=10; confidence=15}

            $result = Resolve-ConfluenceScore -VolumeScore $vol -MomentumScore $mom -StructureScore $struct

            $result.confluenceScore | Should BeLessThan 70
            $result.readyToEnter | Should Be $false
            $result.entryTiming | Should Be "WAIT_CONFLUENCE"
        }

        It "calcula confidenceAvg corretamente" {
            $vol = @{score=40; confidence=90}
            $mom = @{score=30; confidence=80}
            $struct = @{score=30; confidence=70}

            $result = Resolve-ConfluenceScore -VolumeScore $vol -MomentumScore $mom -StructureScore $struct

            $result.confidenceAvg | Should Be 80
        }
    }

    Context "RSI Calculator" {
        It "calcula RSI corretamente" {
            $closes = @(44.34, 44.09, 44.15, 43.61, 44.33, 44.83, 45.10, 45.42, 45.84, 46.08, 45.89, 46.03, 45.61, 46.28, 46.00, 46.03)
            $rsi = Calculate-RSI -Closes $closes
            $rsi | Should BeGreaterThan 0
            $rsi | Should BeLessThan 100
        }

        It "RSI=100 quando todos candles subindo" {
            $closes = @(100, 101, 102, 103, 104, 105)
            $rsi = Calculate-RSI -Closes $closes
            $rsi | Should Be 100
        }

        It "RSI=0 quando todos candles caindo" {
            $closes = @(100, 99, 98, 97, 96, 95)
            $rsi = Calculate-RSI -Closes $closes
            $rsi | Should Be 0
        }
    }
}
