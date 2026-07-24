# trailing_executor_phase2.Tests.ps1 — Smart SL + Multiple Levels
# TDD: 21 testes

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_trailing_executor_phase2.ps1"

Describe "Trailing Executor Phase 2" {

    Context "Order Flow Intensity Detection" {
        It "Low volume = low intensity" {
            $candles = @(
                [PSCustomObject]@{ close = 100; volume = 1000; open = 99 }
                [PSCustomObject]@{ close = 101; volume = 900; open = 100 }
                [PSCustomObject]@{ close = 100; volume = 800; open = 101 }
                [PSCustomObject]@{ close = 102; volume = 950; open = 100 }
                [PSCustomObject]@{ close = 101; volume = 1000; open = 102 }
            )
            $result = Test-OrderFlowIntensity -Candles $candles
            $result.signal | Should Match "low|medium"
        }

        It "High volume spike = high intensity" {
            $candles = @(
                [PSCustomObject]@{ close = 100; volume = 1000; open = 99 }
                [PSCustomObject]@{ close = 100.5; volume = 2000; open = 100 }
                [PSCustomObject]@{ close = 101; volume = 5000; open = 100.5 }
                [PSCustomObject]@{ close = 101.5; volume = 8000; open = 101 }
                [PSCustomObject]@{ close = 102; volume = 9000; open = 101.5 }
            )
            $result = Test-OrderFlowIntensity -Candles $candles
            $result.signal | Should Be "high"
            $result.intensity | Should BeGreaterThan 60
        }

        It "CustomWindowSize funciona" {
            $candles = @(
                [PSCustomObject]@{ close = 100; volume = 1000; open = 99 }
                [PSCustomObject]@{ close = 101; volume = 2000; open = 100 }
                [PSCustomObject]@{ close = 102; volume = 3000; open = 101 }
            )
            $result = Test-OrderFlowIntensity -Candles $candles -WindowSize 2
            $result.intensity | Should BeGreaterThan 0
        }

        It "Trata insuficientes candles" {
            $candles = @([PSCustomObject]@{ close = 100; volume = 1000; open = 99 })
            $result = Test-OrderFlowIntensity -Candles $candles -WindowSize 5
            $result.signal | Should Be "low"
            $result.intensity | Should Be 0
        }
    }

    Context "Volume Price Agreement" {
        It "High agreement = valid" {
            $candles = @(
                [PSCustomObject]@{ close = 101; open = 100; volume = 1000 }  # UP
                [PSCustomObject]@{ close = 102; open = 101; volume = 2000 }  # UP
                [PSCustomObject]@{ close = 103; open = 102; volume = 1500 }  # UP
            )
            $result = Test-VolumePriceAgreement -Candles $candles
            $result.valid | Should Be $true
            $result.confidence | Should BeGreaterThan 60
        }

        It "Low agreement = invalid" {
            # 2026-07-23 FIX: volumes originais (500 UP + 5000 UP = 5500 vs
            # 10000 DOWN) davam agreement=64.5% (>=60, valid=true) -- dados
            # nao geravam de fato "low agreement". Rebalanceado pra UP/DOWN
            # ficarem proximos (3500 vs 3500 = 50%, < 60% threshold).
            $candles = @(
                [PSCustomObject]@{ close = 101; open = 100; volume = 500 }   # UP
                [PSCustomObject]@{ close = 99; open = 101; volume = 3500 }   # DOWN
                [PSCustomObject]@{ close = 100; open = 99; volume = 3000 }   # UP
            )
            $result = Test-VolumePriceAgreement -Candles $candles
            $result.valid | Should Be $false
        }
    }

    Context "Multiple Stop Levels" {
        It "LONG: nivel 1 = entrada" {
            $levels = New-StopLevelStructure -EntryPrice 100 -StopPrice 95 -Side "LONG"
            $levels.level_1_breakeven | Should Be 100
            $levels.current_level | Should Be 1
        }

        It "LONG: nivel 2 = +5%" {
            $levels = New-StopLevelStructure -EntryPrice 100 -StopPrice 95 -Side "LONG"
            [math]::Round($levels.level_2_lock) | Should Be 105
        }

        It "LONG: nivel 3 = +10%" {
            $levels = New-StopLevelStructure -EntryPrice 100 -StopPrice 95 -Side "LONG"
            [math]::Round($levels.level_3_trailing) | Should Be 110
        }

        It "SHORT: nivel 1 = entrada" {
            $levels = New-StopLevelStructure -EntryPrice 100 -StopPrice 105 -Side "SHORT"
            $levels.level_1_breakeven | Should Be 100
        }

        It "SHORT: nivel 2 = -5%" {
            $levels = New-StopLevelStructure -EntryPrice 100 -StopPrice 105 -Side "SHORT"
            [math]::Round($levels.level_2_lock) | Should Be 95
        }

        It "SHORT: nivel 3 = -10%" {
            $levels = New-StopLevelStructure -EntryPrice 100 -StopPrice 105 -Side "SHORT"
            [math]::Round($levels.level_3_trailing) | Should Be 90
        }
    }

    Context "Stop Level Transitions" {
        It "Level 1→2 quando profit ≥ 5%" {
            $levels = New-StopLevelStructure -EntryPrice 100 -StopPrice 95 -Side "LONG"
            $result = Update-StopLevel -Structure $levels -CurrentPrice 105.5 -Side "LONG"
            $result.moved | Should Be $true
            $result.new_level | Should Be 2
            $levels.current_level | Should Be 2
        }

        It "Level 2→3 quando profit ≥ 10%" {
            $levels = New-StopLevelStructure -EntryPrice 100 -StopPrice 95 -Side "LONG"
            $levels.current_level = 2  # Manual advance
            $result = Update-StopLevel -Structure $levels -CurrentPrice 110.5 -Side "LONG"
            $result.moved | Should Be $true
            $result.new_level | Should Be 3
        }

        It "Não move se profit insuficiente" {
            $levels = New-StopLevelStructure -EntryPrice 100 -StopPrice 95 -Side "LONG"
            $result = Update-StopLevel -Structure $levels -CurrentPrice 103 -Side "LONG"
            $result.moved | Should Be $false
            $result.new_level | Should Be 1
        }

        It "Log hit_log quando transição" {
            $levels = New-StopLevelStructure -EntryPrice 100 -StopPrice 95 -Side "LONG"
            Update-StopLevel -Structure $levels -CurrentPrice 105.5 -Side "LONG"
            $levels.hit_log.Count | Should Be 1
            $levels.hit_log[0].from_level | Should Be 1
            $levels.hit_log[0].to_level | Should Be 2
        }
    }

    Context "Integrated SmartTrailingUpdate" {
        It "Detecta flow + atualiza level" {
            $candles = @(
                [PSCustomObject]@{ close = 100; volume = 1000; open = 99 }
                [PSCustomObject]@{ close = 100.5; volume = 2000; open = 100 }
                [PSCustomObject]@{ close = 101; volume = 5000; open = 100.5 }
                [PSCustomObject]@{ close = 101.5; volume = 8000; open = 101 }
                [PSCustomObject]@{ close = 102; volume = 9000; open = 101.5 }
            )
            $levels = New-StopLevelStructure -EntryPrice 100 -StopPrice 95 -Side "LONG"
            $result = Update-TrailingWithSmartSL -Market "BTCUSDT" -CurrentPrice 105.5 `
                -Candles $candles -Side "LONG" -StopLevels $levels
            $result.success | Should Be $true
            $result.flow_intensity | Should BeGreaterThan 50
        }

        It "Retorna novo SL para nível atual" {
            $candles = @(
                [PSCustomObject]@{ close = 100; volume = 5000; open = 99 }
                [PSCustomObject]@{ close = 101; volume = 6000; open = 100 }
                [PSCustomObject]@{ close = 102; volume = 7000; open = 101 }
            )
            $levels = New-StopLevelStructure -EntryPrice 100 -StopPrice 95 -Side "LONG"
            $levels.current_level = 2
            $result = Update-TrailingWithSmartSL -Market "ETHUSDT" -CurrentPrice 105 `
                -Candles $candles -Side "LONG" -StopLevels $levels
            $result.new_sl | Should Be $levels.level_2_lock
        }

        It "Calcula profit_pct corretamente" {
            $candles = @(
                [PSCustomObject]@{ close = 100; volume = 1000; open = 99 }
                [PSCustomObject]@{ close = 101; volume = 1000; open = 100 }
            )
            $levels = New-StopLevelStructure -EntryPrice 100 -StopPrice 95 -Side "LONG"
            $result = Update-TrailingWithSmartSL -Market "BTCUSDT" -CurrentPrice 110 `
                -Candles $candles -Side "LONG" -StopLevels $levels
            $result.profit_pct | Should Be 10
        }
    }

    Context "Sintaxe" {
        It "lib_trailing_executor_phase2.ps1 parse OK" {
            $err = $null
            [void][System.Management.Automation.PSParser]::Tokenize(
                (Get-Content ".\agents\lib_trailing_executor_phase2.ps1" -Raw),
                [ref]$err
            )
            $err.Count | Should Be 0
        }
    }

}
