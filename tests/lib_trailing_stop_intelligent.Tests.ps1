# tests\lib_trailing_stop_intelligent.Tests.ps1
# Testes TDD para Trailing Stop Inteligente
# 2026-05-24
# Compat: escrito em Pester 5.x syntax. Skipped para Pester 3.4 (operadores -BeGreaterThan/-Throw indisponiveis).
# TODO: portar para Pester 3.4 ou upgrade Pester quando ambiente permitir.

# Skip entire suite when running under Pester 3.4
$pesterModule = Get-Module Pester
if ($pesterModule -and [version]$pesterModule.Version -lt [version]"4.0") {
    Write-Host "[lib_trailing_stop_intelligent] SKIP - Pester $($pesterModule.Version) too old (needs 4.0+)" -ForegroundColor DarkYellow
    return
}

. "$PSScriptRoot\..\agents\lib_trailing_stop_intelligent.ps1"

Describe "Calculate-ATR" {
    It "Should calculate ATR correctly for simple data" {
        $candles = @(
            [PSCustomObject]@{ high=100; low=95; close=98 }
            [PSCustomObject]@{ high=102; low=97; close=100 }
            [PSCustomObject]@{ high=105; low=99; close=103 }
            [PSCustomObject]@{ high=104; low=100; close=102 }
            [PSCustomObject]@{ high=106; low=101; close=105 }
            [PSCustomObject]@{ high=108; low=103; close=106 }
            [PSCustomObject]@{ high=107; low=104; close=105 }
            [PSCustomObject]@{ high=109; low=105; close=108 }
            [PSCustomObject]@{ high=111; low=106; close=110 }
            [PSCustomObject]@{ high=110; low=107; close=109 }
            [PSCustomObject]@{ high=112; low=108; close=111 }
            [PSCustomObject]@{ high=114; low=109; close=113 }
            [PSCustomObject]@{ high=113; low=110; close=112 }
            [PSCustomObject]@{ high=115; low=111; close=114 }
            [PSCustomObject]@{ high=116; low=112; close=115 }
        )
        
        $atr = Calculate-ATR -Candles $candles -Period 14
        
        $atr | Should -BeGreaterThan 0
        $atr | Should -BeLessThan 10
    }
    
    It "Should throw error with insufficient candles" {
        $candles = @(
            [PSCustomObject]@{ high=100; low=95; close=98 }
            [PSCustomObject]@{ high=102; low=97; close=100 }
        )
        
        { Calculate-ATR -Candles $candles -Period 14 } | Should -Throw
    }
    
    It "Should handle high volatility correctly" {
        $candles = @(
            [PSCustomObject]@{ high=100; low=95; close=98 }
            [PSCustomObject]@{ high=110; low=90; close=105 }
            [PSCustomObject]@{ high=120; low=85; close=115 }
            [PSCustomObject]@{ high=115; low=95; close=100 }
            [PSCustomObject]@{ high=125; low=90; close=120 }
            [PSCustomObject]@{ high=130; low=100; close=125 }
            [PSCustomObject]@{ high=120; low=105; close=110 }
            [PSCustomObject]@{ high=135; low=100; close=130 }
            [PSCustomObject]@{ high=140; low=110; close=135 }
            [PSCustomObject]@{ high=130; low=115; close=120 }
            [PSCustomObject]@{ high=145; low=115; close=140 }
            [PSCustomObject]@{ high=150; low=125; close=145 }
            [PSCustomObject]@{ high=140; low=120; close=130 }
            [PSCustomObject]@{ high=155; low=125; close=150 }
            [PSCustomObject]@{ high=160; low=135; close=155 }
        )
        
        $atr = Calculate-ATR -Candles $candles -Period 14
        
        $atr | Should -BeGreaterThan 10
    }
}

Describe "Find-SupportLevels" {
    It "Should find support levels in downtrend" {
        $candles = @(
            [PSCustomObject]@{ high=100; low=95; close=98 }
            [PSCustomObject]@{ high=99; low=94; close=96 }
            [PSCustomObject]@{ high=97; low=92; close=94 }  # Local min
            [PSCustomObject]@{ high=96; low=93; close=95 }
            [PSCustomObject]@{ high=95; low=90; close=92 }
            [PSCustomObject]@{ high=93; low=88; close=90 }  # Local min
            [PSCustomObject]@{ high=92; low=89; close=91 }
            [PSCustomObject]@{ high=91; low=87; close=89 }
            [PSCustomObject]@{ high=90; low=85; close=87 }  # Local min
            [PSCustomObject]@{ high=89; low=86; close=88 }
            [PSCustomObject]@{ high=88; low=84; close=86 }
            [PSCustomObject]@{ high=87; low=83; close=85 }
            [PSCustomObject]@{ high=86; low=82; close=84 }
            [PSCustomObject]@{ high=85; low=81; close=83 }
            [PSCustomObject]@{ high=84; low=80; close=82 }
            [PSCustomObject]@{ high=83; low=79; close=81 }
            [PSCustomObject]@{ high=82; low=78; close=80 }
            [PSCustomObject]@{ high=81; low=77; close=79 }
            [PSCustomObject]@{ high=80; low=76; close=78 }
            [PSCustomObject]@{ high=79; low=75; close=77 }
        )
        
        $supports = Find-SupportLevels -Candles $candles -LookbackPeriod 20
        
        $supports.Count | Should -BeGreaterThan 0
        $supports[0] | Should -BeLessThan 77  # Current price
    }
    
    It "Should return empty array with insufficient candles" {
        $candles = @(
            [PSCustomObject]@{ high=100; low=95; close=98 }
            [PSCustomObject]@{ high=99; low=94; close=96 }
        )
        
        $supports = Find-SupportLevels -Candles $candles -LookbackPeriod 20
        
        $supports.Count | Should -Be 0
    }
    
    It "Should group nearby supports" {
        $candles = @(
            [PSCustomObject]@{ high=100; low=95; close=98 }
            [PSCustomObject]@{ high=99; low=94.5; close=96 }  # Support ~94.5
            [PSCustomObject]@{ high=97; low=95; close=96 }
            [PSCustomObject]@{ high=96; low=94.8; close=95 }  # Support ~94.8 (should group with 94.5)
            [PSCustomObject]@{ high=95; low=93; close=94 }
            [PSCustomObject]@{ high=94; low=92; close=93 }
            [PSCustomObject]@{ high=93; low=91; close=92 }
            [PSCustomObject]@{ high=92; low=90; close=91 }
            [PSCustomObject]@{ high=91; low=89; close=90 }
            [PSCustomObject]@{ high=90; low=88; close=89 }
            [PSCustomObject]@{ high=89; low=87; close=88 }
            [PSCustomObject]@{ high=88; low=86; close=87 }
            [PSCustomObject]@{ high=87; low=85; close=86 }
            [PSCustomObject]@{ high=86; low=84; close=85 }
            [PSCustomObject]@{ high=85; low=83; close=84 }
            [PSCustomObject]@{ high=84; low=82; close=83 }
            [PSCustomObject]@{ high=83; low=81; close=82 }
            [PSCustomObject]@{ high=82; low=80; close=81 }
            [PSCustomObject]@{ high=81; low=79; close=80 }
            [PSCustomObject]@{ high=80; low=78; close=79 }
        )
        
        $supports = Find-SupportLevels -Candles $candles -LookbackPeriod 20 -Tolerance 0.005
        
        # Deve agrupar os dois suportes próximos em um só
        $supports.Count | Should -BeLessThan 2
    }
}

Describe "Calculate-TrailingStopPrice" {
    It "Should not activate trailing if profit below threshold" {
        $position = [PSCustomObject]@{
            side = "long"
            open_price = 100
            latest_price = 101  # +1% profit
            leverage = 5
        }
        
        $candles = @(
            [PSCustomObject]@{ high=100; low=95; close=98 }
            [PSCustomObject]@{ high=102; low=97; close=100 }
            [PSCustomObject]@{ high=105; low=99; close=103 }
            [PSCustomObject]@{ high=104; low=100; close=102 }
            [PSCustomObject]@{ high=106; low=101; close=105 }
            [PSCustomObject]@{ high=108; low=103; close=106 }
            [PSCustomObject]@{ high=107; low=104; close=105 }
            [PSCustomObject]@{ high=109; low=105; close=108 }
            [PSCustomObject]@{ high=111; low=106; close=110 }
            [PSCustomObject]@{ high=110; low=107; close=109 }
            [PSCustomObject]@{ high=112; low=108; close=111 }
            [PSCustomObject]@{ high=114; low=109; close=113 }
            [PSCustomObject]@{ high=113; low=110; close=112 }
            [PSCustomObject]@{ high=115; low=111; close=114 }
            [PSCustomObject]@{ high=116; low=112; close=101 }
        )
        
        $result = Calculate-TrailingStopPrice `
            -Position $position `
            -Candles $candles `
            -CurrentStopLoss 95 `
            -MinProfitPctToActivate 3.0
        
        $result.should_update | Should -Be $false
        $result.reason | Should -Match "below activation threshold"
    }
    
    It "Should calculate tighter trailing for high leverage (50x)" {
        $position = [PSCustomObject]@{
            side = "long"
            open_price = 100
            latest_price = 105  # +5% profit
            leverage = 50
        }
        
        $candles = @(
            [PSCustomObject]@{ high=100; low=95; close=98 }
            [PSCustomObject]@{ high=102; low=97; close=100 }
            [PSCustomObject]@{ high=105; low=99; close=103 }
            [PSCustomObject]@{ high=104; low=100; close=102 }
            [PSCustomObject]@{ high=106; low=101; close=105 }
            [PSCustomObject]@{ high=108; low=103; close=106 }
            [PSCustomObject]@{ high=107; low=104; close=105 }
            [PSCustomObject]@{ high=109; low=105; close=108 }
            [PSCustomObject]@{ high=111; low=106; close=110 }
            [PSCustomObject]@{ high=110; low=107; close=109 }
            [PSCustomObject]@{ high=112; low=108; close=111 }
            [PSCustomObject]@{ high=114; low=109; close=113 }
            [PSCustomObject]@{ high=113; low=110; close=112 }
            [PSCustomObject]@{ high=115; low=111; close=114 }
            [PSCustomObject]@{ high=116; low=112; close=105 }
        )
        
        $result = Calculate-TrailingStopPrice `
            -Position $position `
            -Candles $candles `
            -CurrentStopLoss 95 `
            -MinProfitPctToActivate 3.0
        
        $result.should_update | Should -Be $true
        $result.trailing_pct | Should -BeLessThan 3.0  # Tight trailing for 50x
        $result.new_stop_price | Should -BeGreaterThan 95
    }
    
    It "Should calculate wider trailing for low leverage (5x)" {
        $position = [PSCustomObject]@{
            side = "long"
            open_price = 100
            latest_price = 105  # +5% profit
            leverage = 5
        }
        
        $candles = @(
            [PSCustomObject]@{ high=100; low=95; close=98 }
            [PSCustomObject]@{ high=102; low=97; close=100 }
            [PSCustomObject]@{ high=105; low=99; close=103 }
            [PSCustomObject]@{ high=104; low=100; close=102 }
            [PSCustomObject]@{ high=106; low=101; close=105 }
            [PSCustomObject]@{ high=108; low=103; close=106 }
            [PSCustomObject]@{ high=107; low=104; close=105 }
            [PSCustomObject]@{ high=109; low=105; close=108 }
            [PSCustomObject]@{ high=111; low=106; close=110 }
            [PSCustomObject]@{ high=110; low=107; close=109 }
            [PSCustomObject]@{ high=112; low=108; close=111 }
            [PSCustomObject]@{ high=114; low=109; close=113 }
            [PSCustomObject]@{ high=113; low=110; close=112 }
            [PSCustomObject]@{ high=115; low=111; close=114 }
            [PSCustomObject]@{ high=116; low=112; close=105 }
        )
        
        $result = Calculate-TrailingStopPrice `
            -Position $position `
            -Candles $candles `
            -CurrentStopLoss 95 `
            -MinProfitPctToActivate 3.0
        
        $result.should_update | Should -Be $true
        $result.trailing_pct | Should -BeGreaterThan 3.0  # Wider trailing for 5x
        $result.new_stop_price | Should -BeGreaterThan 95
    }
    
    It "Should never move stop down for LONG position" {
        $position = [PSCustomObject]@{
            side = "long"
            open_price = 100
            latest_price = 105  # +5% profit
            leverage = 5
        }
        
        $candles = @(
            [PSCustomObject]@{ high=100; low=95; close=98 }
            [PSCustomObject]@{ high=102; low=97; close=100 }
            [PSCustomObject]@{ high=105; low=99; close=103 }
            [PSCustomObject]@{ high=104; low=100; close=102 }
            [PSCustomObject]@{ high=106; low=101; close=105 }
            [PSCustomObject]@{ high=108; low=103; close=106 }
            [PSCustomObject]@{ high=107; low=104; close=105 }
            [PSCustomObject]@{ high=109; low=105; close=108 }
            [PSCustomObject]@{ high=111; low=106; close=110 }
            [PSCustomObject]@{ high=110; low=107; close=109 }
            [PSCustomObject]@{ high=112; low=108; close=111 }
            [PSCustomObject]@{ high=114; low=109; close=113 }
            [PSCustomObject]@{ high=113; low=110; close=112 }
            [PSCustomObject]@{ high=115; low=111; close=114 }
            [PSCustomObject]@{ high=116; low=112; close=105 }
        )
        
        $currentStop = 102  # Stop já está alto
        
        $result = Calculate-TrailingStopPrice `
            -Position $position `
            -Candles $candles `
            -CurrentStopLoss $currentStop `
            -MinProfitPctToActivate 3.0
        
        $result.new_stop_price | Should -BeGreaterOrEqual $currentStop
    }
    
    It "Should adjust trailing based on nearby support" {
        $position = [PSCustomObject]@{
            side = "long"
            open_price = 100
            latest_price = 105  # +5% profit
            leverage = 5
        }
        
        # Candles com suporte claro em ~103
        $candles = @(
            [PSCustomObject]@{ high=110; low=103; close=108 }
            [PSCustomObject]@{ high=109; low=102.8; close=106 }  # Support
            [PSCustomObject]@{ high=108; low=104; close=107 }
            [PSCustomObject]@{ high=107; low=103.2; close=105 }  # Support
            [PSCustomObject]@{ high=106; low=104; close=105 }
            [PSCustomObject]@{ high=108; low=103; close=106 }
            [PSCustomObject]@{ high=107; low=104; close=105 }
            [PSCustomObject]@{ high=109; low=105; close=108 }
            [PSCustomObject]@{ high=111; low=106; close=110 }
            [PSCustomObject]@{ high=110; low=107; close=109 }
            [PSCustomObject]@{ high=112; low=108; close=111 }
            [PSCustomObject]@{ high=114; low=109; close=113 }
            [PSCustomObject]@{ high=113; low=110; close=112 }
            [PSCustomObject]@{ high=115; low=111; close=114 }
            [PSCustomObject]@{ high=116; low=112; close=105 }
        )
        
        $result = Calculate-TrailingStopPrice `
            -Position $position `
            -Candles $candles `
            -CurrentStopLoss 95 `
            -MinProfitPctToActivate 3.0
        
        $result.nearest_support | Should -Not -BeNullOrEmpty
        $result.reason | Should -Match "support"
    }
}

Describe "Integration Tests" {
    It "Should handle complete workflow for BNB 50x position" {
        # Simular posição BNB real: Entry $647, Current $658, +85%, 50x
        $position = [PSCustomObject]@{
            side = "long"
            open_price = 647.06
            latest_price = 658.07
            leverage = 50
            stop_loss_price = 627.82
        }
        
        # Candles simulados
        $candles = @()
        for ($i = 0; $i -lt 50; $i++) {
            $candles += [PSCustomObject]@{
                high = 650 + ($i * 0.5)
                low = 645 + ($i * 0.5)
                close = 647 + ($i * 0.5)
            }
        }
        
        $result = Calculate-TrailingStopPrice `
            -Position $position `
            -Candles $candles `
            -CurrentStopLoss $position.stop_loss_price `
            -MinProfitPctToActivate 3.0
        
        $result.pnl_pct | Should -BeGreaterThan 1.0
        $result.trailing_pct | Should -BeLessThan 3.0  # Tight for 50x
        $result.should_update | Should -Be $true
        $result.new_stop_price | Should -BeGreaterThan 627.82
    }
}
