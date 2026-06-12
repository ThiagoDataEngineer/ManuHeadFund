# TDD: Semana 5 — Live Integration (gates → PlaceOrder)

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "Semana 5: Live Trading Integration" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_live_integ_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $projectRoot "agents\lib_live_integration.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Invoke-LiveTradeChain existe" {
        $cmd = Get-Command Invoke-LiveTradeChain -ErrorAction SilentlyContinue
        ($cmd -ne $null) | Should Be $true
    }

    It "GOOD trade (gates + capital pass) = can place order" {
        if (Get-Command Invoke-LiveTradeChain -ErrorAction SilentlyContinue) {
            # Entry 10, SL 9 (risk=1), Target 60 (reward=50), RR=50 >> 5 ✓
            $result = Invoke-LiveTradeChain -Market "LINKUSDT" `
                -VolumeUsd 5000000 -EquityTodayPct 0 -CurrentTierACount 1 `
                -EntryPrice 10 -StoplossPrice 9 -TargetPrice 60 `
                -ProposedSizeUsd 50 -AccountBalance 5000 -JournalDir $journalDir

            ($result.can_place_order) | Should Be $true
        }
    }

    It "BLOCKED (volume too low) before PlaceOrder" {
        if (Get-Command Invoke-LiveTradeChain -ErrorAction SilentlyContinue) {
            $result = Invoke-LiveTradeChain -Market "SOLUSDT" `
                -VolumeUsd 500000 -EquityTodayPct 0 -CurrentTierACount 1 `
                -EntryPrice 100 -StoplossPrice 95 -TargetPrice 125 `
                -ProposedSizeUsd 50 -AccountBalance 5000 -JournalDir $journalDir

            ($result.can_place_order) | Should Be $false
        }
    }

    It "OVERSIZED position (capital safety) blocks" {
        if (Get-Command Invoke-LiveTradeChain -ErrorAction SilentlyContinue) {
            $result = Invoke-LiveTradeChain -Market "LINKUSDT" `
                -VolumeUsd 5000000 -EquityTodayPct 0 -CurrentTierACount 1 `
                -EntryPrice 100 -StoplossPrice 95 -TargetPrice 125 `
                -ProposedSizeUsd 5000 -AccountBalance 5000 -JournalDir $journalDir

            ($result.can_place_order) | Should Be $false
        }
    }

    It "Emergency halt (DD >= 15%) blocks PlaceOrder" {
        if (Get-Command Invoke-LiveTradeChain -ErrorAction SilentlyContinue) {
            $result = Invoke-LiveTradeChain -Market "UNI" `
                -VolumeUsd 5000000 -EquityTodayPct -16 -CurrentTierACount 1 `
                -EntryPrice 10 -StoplossPrice 9 -TargetPrice 50 `
                -ProposedSizeUsd 50 -AccountBalance 5000 -JournalDir $journalDir

            ($result.can_place_order) | Should Be $false
        }
    }

    It "live_trade_chain.jsonl registra tentativas" {
        if (Get-Command Invoke-LiveTradeChain -ErrorAction SilentlyContinue) {
            $chainPath = Join-Path $journalDir "live_trade_chain.jsonl"

            $null = Invoke-LiveTradeChain -Market "NEAR" `
                -VolumeUsd 5000000 -EquityTodayPct 0 -CurrentTierACount 0 `
                -EntryPrice 10 -StoplossPrice 9 -TargetPrice 60 `
                -ProposedSizeUsd 50 -AccountBalance 5000 -JournalDir $journalDir

            Test-Path $chainPath | Should Be $true
        }
    }
}
