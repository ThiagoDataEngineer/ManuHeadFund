# lib_pyramid_exit.Tests.ps1 — 10 TDD

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_pyramid_exit.ps1")

$global:JOURNAL_DIR = Join-Path $PSScriptRoot "test_journal"
if (-not (Test-Path $global:JOURNAL_DIR)) { mkdir $global:JOURNAL_DIR | Out-Null }

Describe "PyramidExit: Test-NewAllTimeHigh" {
    It "detecta ATH novo quando price > recent_high" {
        $isAth = Test-NewAllTimeHigh -CurrentPrice 70000 -RecentHigh 65000 -ExitHistory @()
        $isAth | Should Be $true
    }

    It "não detecta ATH quando price <= recent_high" {
        $isAth = Test-NewAllTimeHigh -CurrentPrice 60000 -RecentHigh 65000 -ExitHistory @()
        $isAth | Should Be $false
    }

    It "rejeita ATH se últimavenda < 1% atrás" {
        $lastExit = @{ price = 69500 }
        $isAth = Test-NewAllTimeHigh -CurrentPrice 70000 -RecentHigh 65000 -ExitHistory @($lastExit)
        $isAth | Should Be $false
    }

    It "aceita ATH se última venda > 1% atrás" {
        $lastExit = @{ price = 68000 }
        $isAth = Test-NewAllTimeHigh -CurrentPrice 70000 -RecentHigh 65000 -ExitHistory @($lastExit)
        $isAth | Should Be $true
    }
}

Describe "PyramidExit: Invoke-PyramidExit" {
    It "executa venda piramidal 20%" {
        $positions = @(
            @{ market = "BTCUSDT"; qty = 1.0; entry_price = 50000 }
        )
        $result = Invoke-PyramidExit -CurrentPrice 70000 -Positions $positions -ExitPercentage 0.20 -JournalDir $global:JOURNAL_DIR

        $result.executed | Should Be $true
        $result.exits[0].qty_sold | Should Be 0.2
        $result.exits[0].gain_usd | Should Be 4000  # (70k - 50k) * 0.2
    }

    It "rejeita se sem posições" {
        $result = Invoke-PyramidExit -CurrentPrice 70000 -Positions @() -JournalDir $global:JOURNAL_DIR
        $result.executed | Should Be $false
    }
}

Describe "PyramidExit: Get/Save PyramidExitState" {
    It "salva e carrega state" {
        $positions = @( @{ market = "BTCUSDT"; qty = 0.8; entry_price = 50000 } )
        Save-PyramidExitState -Positions $positions -ExitHistory @() -GainsLockedUsd 4000 -JournalDir $global:JOURNAL_DIR

        $state = Get-PyramidExitState -JournalDir $global:JOURNAL_DIR
        $state.gains_locked_usd | Should Be 4000
    }
}

Describe "PyramidExit: Get-PyramidExitStatistics" {
    It "retorna estatísticas vazias se nenhuma saída" {
        Remove-Item (Join-Path $global:JOURNAL_DIR "pyramid_exits.jsonl") -ErrorAction SilentlyContinue
        $stats = Get-PyramidExitStatistics -JournalDir $global:JOURNAL_DIR
        $stats.total_exits | Should Be 0
    }
}
