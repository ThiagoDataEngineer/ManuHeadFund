# TDD: Volatility Filter + MCE Gates (CORE)

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "Volatility Filter & MCE Gates" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_vol_mce_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        . (Join-Path $projectRoot "agents\lib_volatility_filter.ps1")
        . (Join-Path $projectRoot "agents\lib_mce_gates.ps1")
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    # === VOLATILITY FILTER ===

    It "Test-VolatilityAcceptable existe" {
        Get-Command Test-VolatilityAcceptable -ErrorAction SilentlyContinue | Should Not Be $null
    }

    It "vol <= 3% = OK (1.0x), vol 3-5% = REDUCE (0.5x), vol > 5% = BLOCK (0.0x)" {
        $ok = Test-VolatilityAcceptable -Market "M1" -VolatilityChange5mPct 1.5 -JournalDir $journalDir
        $reduce = Test-VolatilityAcceptable -Market "M2" -VolatilityChange5mPct 4.0 -JournalDir $journalDir
        $block = Test-VolatilityAcceptable -Market "M3" -VolatilityChange5mPct 6.0 -JournalDir $journalDir

        ($ok.size_multiplier) | Should Be 1.0
        ($reduce.size_multiplier) | Should Be 0.5
        ($block.size_multiplier) | Should Be 0.0
    }

    It "volatility_filter_audit.jsonl gerado" {
        $logPath = Join-Path $journalDir "volatility_filter_audit.jsonl"
        (Test-Path $logPath) | Should Be $true
    }

    It "Get-VolatilityTrend detecta trend" {
        $history = @(2.0, 3.5, 4.2)  # Aumentando
        $trend = Get-VolatilityTrend -VolatilityHistory $history -Market "TEST"

        ($trend.trend) | Should Be "INCREASING"
        ($trend.direction) | Should Be 1
    }

    # === MCE GATES ===

    It "Test-BrtTradingWindow existe" {
        Get-Command Test-BrtTradingWindow -ErrorAction SilentlyContinue | Should Not Be $null
    }

    It "BRT 13h = OK, BRT 3h = WAIT" {
        $hour13 = [datetime]"2026-06-06 13:30:00"
        $hour3 = [datetime]"2026-06-06 03:30:00"

        $ok = Test-BrtTradingWindow -Brt $hour13
        $wait = Test-BrtTradingWindow -Brt $hour3

        ($ok.allowed) | Should Be $true
        ($wait.allowed) | Should Be $false
    }

    It "Get-FearGreedIndex retorna escala 0-100" {
        $fg = Get-FearGreedIndex -JournalDir $journalDir

        ($fg.index -ge 0 -and $fg.index -le 100) | Should Be $true
        ($fg.level) | Should Match "(EXTREME_FEAR|FEAR|NEUTRAL|GREED|EXTREME_GREED)"
    }

    It "Invoke-MceGate combina BRT + Fear&Greed" {
        $hour13 = [datetime]"2026-06-06 13:30:00"
        $result = Invoke-MceGate -Market "BTC" -Regime "BULL" -Brt $hour13 -JournalDir $journalDir

        ($result.brt_window) | Should Be "OK"
        ($result.action) | Should Match "(ALLOW|RESTRICT)"
    }
}
