# lib_dca_accumulator.Tests.ps1 — 12 TDD

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_dca_accumulator.ps1")

$global:JOURNAL_DIR = Join-Path $PSScriptRoot "test_journal"
if (-not (Test-Path $global:JOURNAL_DIR)) { mkdir $global:JOURNAL_DIR | Out-Null }

Describe "DcaAccumulator: Test-DcaShouldBuy" {
    It "compra quando BTC < fundo histórico + 10%" {
        $should = Test-DcaShouldBuy -BtcPrice 44000 -BtcHistoricalLow 40000 -BtcHistoricalHigh 65000
        $should | Should Be $true
    }

    It "não compra quando BTC > fundo + 10%" {
        $should = Test-DcaShouldBuy -BtcPrice 50000 -BtcHistoricalLow 40000 -BtcHistoricalHigh 65000
        $should | Should Be $false
    }

    It "compra em downtrend > 20%" {
        $should = Test-DcaShouldBuy -BtcPrice 50000 -BtcHistoricalLow 40000 -BtcHistoricalHigh 65000 -DowntrendThreshold 0.25
        $should | Should Be $true
    }
}

Describe "DcaAccumulator: Get-DcaAllocationPercentage" {
    It "retorna 2% para pre_halving" {
        $alloc = Get-DcaAllocationPercentage -HalvingPhase "pre_halving"
        $alloc | Should Be 0.02
    }

    It "retorna 3% para phase_3_bear (agressivo)" {
        $alloc = Get-DcaAllocationPercentage -HalvingPhase "phase_3_bear"
        $alloc | Should Be 0.03
    }

    It "dobra alocação quando macro_bias < 30 (pessimista)" {
        $alloc = Get-DcaAllocationPercentage -HalvingPhase "phase_1_bull" -MacroBias 20
        $alloc | Should Be 0.02
    }

    It "metade alocação quando macro_bias > 70 (otimista)" {
        $alloc = Get-DcaAllocationPercentage -HalvingPhase "phase_1_bull" -MacroBias 80
        $alloc | Should Be 0.005
    }
}

Describe "DcaAccumulator: Invoke-DcaBuy" {
    It "calcula quantidade corretamente" {
        $result = Invoke-DcaBuy -AvailableCapital 10000 -DcaPctAllocation 0.01 -Market "BTCUSDT" -Price 50000
        $result.executed | Should Be $true
        $result.usd | Should Be 100
        $result.qty | Should Be 0.002
    }

    It "rejeita compra < $10" {
        $result = Invoke-DcaBuy -AvailableCapital 500 -DcaPctAllocation 0.01 -Market "BTCUSDT" -Price 50000
        $result.executed | Should Be $false
    }
}

Describe "DcaAccumulator: Get/Save DcaState" {
    It "salva e carrega state corretamente" {
        $state = @{ accumulated_usd = 1000; positions = @() }
        Save-DcaState -AccumulatedUsd 1000 -Positions @() -LastBuy (Get-Date) -JournalDir $global:JOURNAL_DIR

        $loaded = Get-DcaState -JournalDir $global:JOURNAL_DIR
        $loaded.accumulated_usd | Should Be 1000
    }

    It "retorna default se arquivo não existe" {
        Remove-Item (Join-Path $global:JOURNAL_DIR "dca_state.json") -ErrorAction SilentlyContinue
        $state = Get-DcaState -JournalDir $global:JOURNAL_DIR
        $state.accumulated_usd | Should Be 0.0
    }
}

Describe "DcaAccumulator: Get-DcaStatistics" {
    It "calcula statisticas corretamente" {
        $stats = Get-DcaStatistics -JournalDir $global:JOURNAL_DIR
        ($stats.total_purchases -ge 0) | Should Be $true
        $stats.total_usd_invested | Should Be 0
    }
}
