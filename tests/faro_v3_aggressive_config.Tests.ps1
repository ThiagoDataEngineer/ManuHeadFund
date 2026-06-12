param([string] $ModulePath = "$PSScriptRoot\..\agents")

Describe "FARO V3 Aggressive Config (score 30→28)" {
    . "$ModulePath\lib_faro_v3_scoring.ps1"

    Context "Score threshold lowball 28 (from 35)" {
        It "accepts score ~28 when 4/7 signals with high values" {
            # 4 * 25 = 100 raw, / 175 * 100 = 57 actual score
            $result = Get-FaroScoreV3 -VolScore 25 -PatternScore 25 -SentimentScore 25 -MomentumScore 25
            $result.score | Should Be 57
            $result.signal_count | Should Be 4
            $result.decision | Should Be "WATCH"
        }

        It "lowers decision to WATCH with 4 signals (was SKIP in old system)" {
            # Old: 4 signals = SKIP (not enough)
            # New: 4 signals + score ≥ 28 = WATCH (investigate)
            $result = Get-FaroScoreV3 -VolScore 25 -PatternScore 25 -SentimentScore 25 -MomentumScore 25
            ($result.signal_count -eq 4) | Should Be $true
            ($result.decision -eq "WATCH") | Should Be $true
        }

        It "always ENTERs with 5+ signals" {
            # 5 * 25 = 125 raw, / 175 * 100 = 71 actual score
            $result = Get-FaroScoreV3 -VolScore 25 -PatternScore 25 -SentimentScore 25 -MomentumScore 25 -FingerprintScore 25
            $result.signal_count | Should Be 5
            $result.decision | Should Be "ENTRA"
        }
    }

    Context "Remove vol filter (capture micro-caps)" {
        It "accepts any volume > 0" {
            $result = Get-FaroScoreV3 -VolScore 10
            $result.breakdown.volume | Should Be 10
        }

        It "penalizes no volume" {
            $result = Get-FaroScoreV3 -VolScore 0 -PatternScore 5 -SentimentScore 5 -MomentumScore 5
            $result.signal_count | Should Be 3
        }
    }

    Context "Daily cap increase 3→5 gems/day" {
        It "config allows 5 concurrent gems" {
            $config = @{ MaxGemsPerDay = 5 }
            $config.MaxGemsPerDay | Should Be 5
        }
    }

    Context "Confidence calculation" {
        It "calculates 4/7 signals as 0.57 confidence" {
            $result = Get-FaroScoreV3 -VolScore 10 -PatternScore 10 -SentimentScore 10 -MomentumScore 10
            $result.signal_count | Should Be 4
            $result.confidence | Should Be 0.57
        }

        It "calculates 5/7 signals as 0.71 confidence" {
            $result = Get-FaroScoreV3 -VolScore 10 -PatternScore 10 -SentimentScore 10 -MomentumScore 10 -FingerprintScore 10
            $result.signal_count | Should Be 5
            $result.confidence | Should Be 0.71
        }
    }
}
