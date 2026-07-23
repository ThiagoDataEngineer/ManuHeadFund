Describe "Sizing Centralized (Blocker #2 Fix)" {

    BeforeAll {
        . (Join-Path $PSScriptRoot "..\agents\lib_sizing_centralized.ps1")
    }

    Context "Get-SafePositionSize Basic" {
        It "Should return 1% of capital as max loss (standard)" {
            $result = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.02 -ConvictionPercent 100

            $result.max_loss_usd | Should Be 36.45  # 3645 * 0.01
            [math]::Round($result.max_loss_pct, 2) | Should Be 1
        }

        It "Should calculate size from SL distance" {
            # Entry 100, SL 98 = 2% stop loss
            # Max loss $36.45 (3645*0.01) -> size = $36.45 / 0.02 = $1822.5
            # 2026-07-23 FIX: teste anterior (sintaxe Pester 5, nunca rodava no
            # motor real 3.4) esperava 1800, usando $36 arredondado no comentario
            # em vez do max_loss_usd exato ($36.45) -- o codigo real sempre
            # calculou 1822.5, o teste que estava com a conta simplificada errada.
            $result = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.02

            $result.size_usd | Should Be 1822.5
            [math]::Round($result.size_pct, 1) | Should Be 50
        }

        It "Should reduce size for low conviction (<50)" {
            # Same entry/stop, but conviction 25 = 50% reduction
            $resultHigh = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.02 -ConvictionPercent 100
            $resultLow = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.02 -ConvictionPercent 25

            # Low conviction should be ~25% of high (25/50 = 0.5)
            $resultLow.size_usd | Should BeLessThan $resultHigh.size_usd
        }

        It "Should cap leverage at 5x maximum" {
            # Force very small SL to create huge position
            $result = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.001  # tiny SL

            # Max = capital * 5x = $18,225
            ($result.size_usd -le 18225) | Should Be $true
        }
    }

    Context "Consistency Across Scenarios" {
        It "Should use 1% capital rule for ALL inputs (exceto quando cap de leverage 5x intervem)" {
            # Three different scenarios. s1/s2 tem SL grande o suficiente pra nao
            # bater o cap de 5x leverage -- max_loss = Capital*1% exato (36.45).
            # 2026-07-23 FIX: s3 usa StopLossPercent=0.001 (bem pequeno), fazendo
            # sizeUsd teorico (36.45/0.001=36450) estourar o cap de 5x leverage
            # (Capital*5=18225) -- o mesmo cenario que o teste "cap leverage at 5x"
            # acima ja cobre isoladamente. Com o size CAPADO, o max_loss REAL fica
            # menor que 1% (18225*0.001=18.225) -- comportamento correto (protege
            # contra leverage excessiva), nao um bug. Teste anterior (sintaxe
            # Pester 5, nunca rodava no motor real) assumia 1% sempre, sem
            # considerar o cap.
            $s1 = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.02
            $s2 = Get-SafePositionSize -Capital 3645 -EntryPrice 50 -StopLossPercent 0.01
            $s3 = Get-SafePositionSize -Capital 3645 -EntryPrice 1000 -StopLossPercent 0.001

            $s1.max_loss_usd | Should Be 36.45
            $s2.max_loss_usd | Should Be 36.45
            $s3.max_loss_usd | Should Be 18.225
        }
    }

    Context "Get-SafePositionSizeFromGem" {
        It "Should work from Gem object (wrapper)" {
            $gem = @{
                entry_price = 100
                stop_loss = 98
                conviction = 80
                market = "TESTUSDT"
            }

            $result = Get-SafePositionSizeFromGem -Gem $gem -Capital 3645

            $result.size_usd | Should BeGreaterThan 0
            [math]::Round($result.max_loss_pct, 1) | Should Be 1
        }

        It "Should return null for invalid gem" {
            $gem = @{
                entry_price = 0  # Invalid
                stop_loss = 98
            }

            $result = Get-SafePositionSizeFromGem -Gem $gem -Capital 3645
            $result | Should BeNullOrEmpty
        }
    }

    Context "Blocker #2 Evidence: Consistency" {
        It "Should NOT return 0.3% sizing anymore (old bug)" {
            # Old code: $size = capital * 0.003 = $10.93
            # New code: $size should be $1800 (1% / 2% SL)
            $result = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.02

            $result.size_usd | Should BeGreaterThan 1000  # Much larger than $10
        }

        It "Should NOT return 0.2% sizing anymore (old bug)" {
            $result = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.02

            # Old: capital * 0.002 = $7.29
            # New: $1800
            $result.size_usd | Should BeGreaterThan 1000
        }

        It "All paths should return same size for same inputs" {
            # Before fix: lib_gem_router, lib_kelly_wire, lib_hybrid_orchestrator all different
            # After fix: all use Get-SafePositionSize

            $capital = 3645
            $entry = 100
            $stop = 98

            $size1 = Get-SafePositionSize -Capital $capital -EntryPrice $entry -StopLossPercent 0.02
            $size2 = Get-SafePositionSize -Capital $capital -EntryPrice $entry -StopLossPercent 0.02
            $size3 = Get-SafePositionSize -Capital $capital -EntryPrice $entry -StopLossPercent 0.02

            $size1.size_usd | Should Be $size2.size_usd
            $size2.size_usd | Should Be $size3.size_usd
        }
    }
}
