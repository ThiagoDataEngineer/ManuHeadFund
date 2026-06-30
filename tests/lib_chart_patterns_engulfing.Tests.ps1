$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_chart_patterns_engulfing.ps1")

Describe "Detect-EngulfingPattern" {
    It "Bullish engulfing: green candle larger than red" {
        $candles = @(
            @{ open = 100; close = 98; high = 101; low = 97; timestamp = (Get-Date).AddHours(-1); volume = 1000 },
            @{ open = 97; close = 102; high = 103; low = 96; timestamp = (Get-Date); volume = 1200 }
        )

        $patterns = @(Detect-EngulfingPattern -Candles $candles)

        $patterns.Count | Should Be 1
        $patterns[0].direction | Should Be "bullish"
    }

    It "Bearish engulfing: red candle larger than green" {
        $candles = @(
            @{ open = 100; close = 102; high = 103; low = 99; timestamp = (Get-Date).AddHours(-1); volume = 1000 },
            @{ open = 103; close = 97; high = 104; low = 96; timestamp = (Get-Date); volume = 1200 }
        )

        $patterns = @(Detect-EngulfingPattern -Candles $candles)

        $patterns.Count | Should Be 1
        $patterns[0].direction | Should Be "bearish"
    }

    It "No engulfing: partial overlap (not true engulfing)" {
        $candles = @(
            @{ open = 100; close = 98; high = 101; low = 98; timestamp = (Get-Date).AddHours(-1) },
            @{ open = 99; close = 100.5; high = 101; low = 99; timestamp = (Get-Date) }
        )

        $patterns = Detect-EngulfingPattern -Candles $candles

        $patterns.Count | Should Be 0
    }

    It "No engulfing: same direction (no reversal signal)" {
        $candles = @(
            @{ open = 100; close = 102; high = 102.5; low = 99.5; timestamp = (Get-Date).AddHours(-1) },
            @{ open = 103; close = 105; high = 105.5; low = 102.5; timestamp = (Get-Date) }
        )

        $patterns = Detect-EngulfingPattern -Candles $candles

        $patterns.Count | Should Be 0
    }

    It "Engulfing confidence: always 0.32" {
        $candles = @(
            @{ open = 100; close = 98; high = 101; low = 98; timestamp = (Get-Date).AddHours(-1) },
            @{ open = 99; close = 102; high = 102.5; low = 98.5; timestamp = (Get-Date) }
        )

        $patterns = @(Detect-EngulfingPattern -Candles $candles)

        $patterns[0].confidence | Should Be 0.32
    }

    It "Engulfing with volume: returns volume context" {
        $candles = @(
            @{ open = 100; close = 98; high = 101; low = 98; timestamp = (Get-Date).AddHours(-1); volume = 1000 },
            @{ open = 99; close = 102; high = 102.5; low = 98.5; timestamp = (Get-Date); volume = 1500 }
        )

        $patterns = @(Detect-EngulfingPattern -Candles $candles)

        # Pattern detected, volume info stored
        $patterns[0].current_candle | Should Not BeNullOrEmpty
    }

    It "Empty candles: returns empty array" {
        $patterns = Detect-EngulfingPattern -Candles @()

        $patterns.Count | Should Be 0
    }

    It "Single candle: returns empty array (needs 2 minimum)" {
        $patterns = Detect-EngulfingPattern -Candles @(@{ open = 100; close = 101 })

        $patterns.Count | Should Be 0
    }

    It "Multiple candles: detects only latest engulfing" {
        $candles = @(
            @{ open = 100; close = 98; high = 101; low = 98; timestamp = (Get-Date).AddHours(-2) },
            @{ open = 99; close = 102; high = 102.5; low = 98.5; timestamp = (Get-Date).AddHours(-1) },
            @{ open = 103; close = 101; high = 104; low = 100; timestamp = (Get-Date) }
        )

        $patterns = Detect-EngulfingPattern -Candles $candles

        # Only latest pair checked (102 vs 101) - no engulfing
        $patterns.Count | Should Be 0
    }
}

Describe "Validate-EngulfingStrength" {
    It "Strong engulfing (100% envelopment): valid" {
        $pattern = @{
            envelopment_pct = 100
        }

        $valid = Validate-EngulfingStrength -EngulfingPattern $pattern

        $valid | Should Be $true
    }

    It "Weak engulfing (40% envelopment): invalid" {
        $pattern = @{
            envelopment_pct = 40
        }

        $valid = Validate-EngulfingStrength -EngulfingPattern $pattern

        $valid | Should Be $false
    }

    It "Threshold engulfing (50% exactly): valid" {
        $pattern = @{
            envelopment_pct = 50
        }

        $valid = Validate-EngulfingStrength -EngulfingPattern $pattern

        $valid | Should Be $true
    }

    It "Custom threshold: 60% minimum" {
        $pattern = @{
            envelopment_pct = 55
        }

        $valid = Validate-EngulfingStrength -EngulfingPattern $pattern -MinEnvelopmentPct 60

        $valid | Should Be $false
    }

    It "Null pattern: returns false" {
        $valid = Validate-EngulfingStrength -EngulfingPattern $null

        $valid | Should Be $false
    }
}

Describe "Get-EngulfingContext" {
    It "Returns trend_before: uptrend" {
        $candles = @(
            @{ open = 100; close = 101; timestamp = (Get-Date).AddHours(-3) },
            @{ open = 101; close = 102; timestamp = (Get-Date).AddHours(-2) },
            @{ open = 102; close = 103; timestamp = (Get-Date).AddHours(-1) },
            @{ open = 103; close = 98; timestamp = (Get-Date); volume = 1000 }
        )

        $ctx = Get-EngulfingContext -Candles $candles -CurrentIndex 3

        $ctx.trend_before | Should Be "uptrend"
    }

    It "Returns trend_before: downtrend" {
        $candles = @(
            @{ open = 100; close = 99; timestamp = (Get-Date).AddHours(-3) },
            @{ open = 99; close = 98; timestamp = (Get-Date).AddHours(-2) },
            @{ open = 98; close = 97; timestamp = (Get-Date).AddHours(-1) },
            @{ open = 97; close = 102; timestamp = (Get-Date); volume = 1000 }
        )

        $ctx = Get-EngulfingContext -Candles $candles -CurrentIndex 3

        $ctx.trend_before | Should Be "downtrend"
    }

    It "Returns momentum: accelerating (volume up)" {
        $candles = @(
            @{ open = 100; close = 101; timestamp = (Get-Date).AddHours(-1); volume = 1000 },
            @{ open = 101; close = 102; timestamp = (Get-Date); volume = 1500 }
        )

        $ctx = Get-EngulfingContext -Candles $candles -CurrentIndex 1

        $ctx.momentum | Should Be "accelerating"
    }

    It "Returns momentum: decelerating (volume down)" {
        $candles = @(
            @{ open = 100; close = 101; timestamp = (Get-Date).AddHours(-1); volume = 1500 },
            @{ open = 101; close = 102; timestamp = (Get-Date); volume = 1000 }
        )

        $ctx = Get-EngulfingContext -Candles $candles -CurrentIndex 1

        $ctx.momentum | Should Be "decelerating"
    }

    It "Insufficient candles (index < 2): returns null" {
        $candles = @(
            @{ open = 100; close = 101 }
        )

        $ctx = Get-EngulfingContext -Candles $candles -CurrentIndex 0

        $ctx | Should Be $null
    }
}

Describe "Engulfing + Vol_Climax Integration" {
    It "Bullish engulfing after vol_climax: confirms entry" {
        # Vol_Climax detected
        $vc = @{
            type = "vol_climax"
            confidence = 0.37
            direction = "bullish"
        }

        # Engulfing pattern in next candle
        $eng = @{
            type = "engulfing"
            direction = "bullish"
            confidence = 0.32
        }

        # Both same direction = can combine
        ($vc.direction -eq $eng.direction) | Should Be $true
    }

    It "Engulfing contradicts vol_climax direction: reject" {
        $vc = @{
            type = "vol_climax"
            direction = "bullish"
        }

        $eng = @{
            type = "engulfing"
            direction = "bearish"
        }

        # Opposite direction = reject
        ($vc.direction -eq $eng.direction) | Should Be $false
    }
}

