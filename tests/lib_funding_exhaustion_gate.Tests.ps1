param([string] $ModulePath = "$PSScriptRoot\..\agents")

Describe "lib_funding_exhaustion_gate — Dead-hand divergence hunt" {
    . "$ModulePath\lib_funding_exhaustion_gate.ps1"

    Context "Test-FundingExhaustionGate main logic" {
        It "FQS < 4: skip (low quality)" {
            $result = Test-FundingExhaustionGate `
                -AssetMarket "LOWQUALITYUSDT" `
                -FQSScore 3.5 `
                -BtcADX 15 `
                -FundingRate 0.0008 `
                -Regime "BEAR_WEAK"

            $result | Should Be $null
        }

        It "FQS >= 4 but BTC ADX trending (25+): skip (BTC not lateral)" {
            $result = Test-FundingExhaustionGate `
                -AssetMarket "PENDLE" `
                -FQSScore 5.0 `
                -BtcADX 28 `
                -FundingRate 0.0008 `
                -Regime "BEAR_WEAK"

            $result | Should Be $null
        }

        It "FQS >= 4, BTC lateral (ADX < 20), Funding low (0.03%): skip" {
            $result = Test-FundingExhaustionGate `
                -AssetMarket "ETHUSDT" `
                -FQSScore 5.0 `
                -BtcADX 15 `
                -FundingRate 0.0003 `
                -Regime "BEAR_WEAK"

            $result | Should Be $null
        }

        It "FQS=5, BTC ADX=15 (lateral), Funding=0.06% (exhaus): divergence found" {
            $result = Test-FundingExhaustionGate `
                -AssetMarket "PENDLE" `
                -FQSScore 5.0 `
                -BtcADX 15 `
                -FundingRate 0.0006 `
                -Regime "BEAR_WEAK"

            $result.divergence_found | Should Be $true
            $result.funding_rate | Should Be 0.0006
            $result.risk_tier | Should Be "0.1%"
        }

        It "Perfect conditions (FQS=6, ADX=10, Funding=0.1%)" {
            $result = Test-FundingExhaustionGate `
                -AssetMarket "BTCBTC" `
                -FQSScore 6.0 `
                -BtcADX 10 `
                -FundingRate 0.001 `
                -Regime "BEAR_WEAK"

            $result.divergence_found | Should Be $true
            $result.entry_signal | Should Be "FUNDING_EXHAUS_SHORT"
        }

        It "Non-BEAR_WEAK regime: skip (not applicable)" {
            $result = Test-FundingExhaustionGate `
                -AssetMarket "ETHUSDT" `
                -FQSScore 5.0 `
                -BtcADX 15 `
                -FundingRate 0.0008 `
                -Regime "BULL_STRONG"

            $result | Should Be $null
        }
    }

    Context "Boundary conditions" {
        It "BTC ADX exactly 20: skip (not lateral)" {
            $result = Test-FundingExhaustionGate `
                -AssetMarket "ETHUSDT" `
                -FQSScore 5.0 `
                -BtcADX 20 `
                -FundingRate 0.0008 `
                -Regime "BEAR_WEAK"

            $result | Should Be $null
        }

        It "BTC ADX 19.9: pass (lateral)" {
            $result = Test-FundingExhaustionGate `
                -AssetMarket "ETHUSDT" `
                -FQSScore 5.0 `
                -BtcADX 19.9 `
                -FundingRate 0.0008 `
                -Regime "BEAR_WEAK"

            $result.divergence_found | Should Be $true
        }

        It "Funding exactly 0.05% (threshold): pass" {
            $result = Test-FundingExhaustionGate `
                -AssetMarket "ETHUSDT" `
                -FQSScore 5.0 `
                -BtcADX 15 `
                -FundingRate 0.0005 `
                -Regime "BEAR_WEAK"

            $result.divergence_found | Should Be $true
        }

        It "Funding 0.049% (below threshold): skip" {
            $result = Test-FundingExhaustionGate `
                -AssetMarket "ETHUSDT" `
                -FQSScore 5.0 `
                -BtcADX 15 `
                -FundingRate 0.00049 `
                -Regime "BEAR_WEAK"

            $result | Should Be $null
        }

        It "FQS exactly 4.0 (threshold): pass" {
            $result = Test-FundingExhaustionGate `
                -AssetMarket "ETHUSDT" `
                -FQSScore 4.0 `
                -BtcADX 15 `
                -FundingRate 0.0008 `
                -Regime "BEAR_WEAK"

            $result.divergence_found | Should Be $true
        }
    }

    Context "Multiple opportunities in one cycle" {
        It "2+ assets qualify simultaneously" {
            $opp1 = Test-FundingExhaustionGate `
                -AssetMarket "PENDLE" `
                -FQSScore 5.0 `
                -BtcADX 15 `
                -FundingRate 0.0008 `
                -Regime "BEAR_WEAK"

            $opp2 = Test-FundingExhaustionGate `
                -AssetMarket "UNI" `
                -FQSScore 4.5 `
                -BtcADX 12 `
                -FundingRate 0.0007 `
                -Regime "BEAR_WEAK"

            $opp1 | Should Not Be $null
            $opp2 | Should Not Be $null
            $opp1.entry_signal | Should Be "FUNDING_EXHAUS_SHORT"
            $opp2.entry_signal | Should Be "FUNDING_EXHAUS_SHORT"
        }
    }

    Context "Integration: logging divergence opportunities" {
        BeforeEach {
            $testPath = "$env:TEMP\div_log_$(Get-Random).jsonl"
        }

        AfterEach {
            if (Test-Path $testPath) { Remove-Item $testPath -Force }
        }

        It "Saves divergence opportunity with metadata" {
            $div = @{
                divergence_found = $true
                funding_rate = 0.0008
                risk_tier = "0.1%"
                entry_signal = "FUNDING_EXHAUS_SHORT"
            }

            Save-DivergenceOpportunity -Path $testPath `
                -Market "PENDLE" `
                -Divergence $div `
                -BtcADX 15 `
                -Timestamp (Get-Date)

            (Test-Path $testPath) | Should Be $true
        }

        It "Log entry contains all fields" {
            $div = @{
                divergence_found = $true
                funding_rate = 0.0008
                risk_tier = "0.1%"
                entry_signal = "FUNDING_EXHAUS_SHORT"
            }

            Save-DivergenceOpportunity -Path $testPath `
                -Market "ETHUSDT" `
                -Divergence $div `
                -BtcADX 12 `
                -Timestamp (Get-Date)

            $entry = Get-Content $testPath | ConvertFrom-Json
            $entry.market | Should Be "ETHUSDT"
            $entry.funding_rate | Should Be 0.0008
            $entry.risk_tier | Should Be "0.1%"
            $entry.btc_adx | Should Be 12
        }

        It "Multiple divergences appended to same log" {
            Save-DivergenceOpportunity -Path $testPath -Market "PENDLE" `
                -Divergence @{ funding_rate = 0.0008; entry_signal = "FUNDING_EXHAUS_SHORT" } -BtcADX 15 -Timestamp (Get-Date)

            Start-Sleep -Milliseconds 10

            Save-DivergenceOpportunity -Path $testPath -Market "UNI" `
                -Divergence @{ funding_rate = 0.0007; entry_signal = "FUNDING_EXHAUS_SHORT" } -BtcADX 12 -Timestamp (Get-Date)

            $lines = @(Get-Content $testPath)
            $lines.Count | Should Be 2
        }
    }
}
